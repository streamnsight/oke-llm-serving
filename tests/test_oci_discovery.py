import io
import json
import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest.mock import patch

from oke_llm_serving.cli import main
from oke_llm_serving.model_profile import ProfileError
from oke_llm_serving.oci_discovery import (
    DiscoveryFailure, OciSession, assess_capacity, discover_accelerators,
)


class FakeSession:
    tenancy_id = "root-tenancy"
    region = "region-one"

    def __init__(self):
        self.calls = []
        self.failures = {}
        self.responses = {
            "list_region_subscriptions": [{"region_name": self.region, "status": "READY"}],
            "list_availability_domains": [{"name": "AD-1"}, {"name": "AD-2"}],
            "list_shapes": [{"shape": "VM.GPU.Test.2", "gpus": 2, "gpu_description": "Test GPU",
                             "memory_in_gbs": 512, "quota_names": ["gpu-test-count"],
                             "rdma_ports": 0, "rdma_bandwidth_in_gbps": 0},
                            {"shape": "VM.Standard.Test", "gpus": 0}],
            "list_limit_definitions": [{"name": "gpu-test-count", "scope_type": "AD",
                                        "is_resource_availability_supported": True}],
            "list_limit_values": [{"name": "gpu-test-count", "scope_type": "AD", "availability_domain": "AD-1", "value": 10}],
            "get_resource_availability": {"used": 2, "available": 8, "effective_quota_value": 10},
            "capacity": {"shape_availabilities": [{"instance_shape": "VM.GPU.Test.2", "availability_status": "AVAILABLE", "available_count": 2}]},
        }

    def call(self, service, region, method, *args, **kwargs):
        self.calls.append((service, region, method, args, kwargs))
        if method in self.failures:
            raise self.failures[method]
        return self.responses[method]

    def capacity(self, region, ad, shapes, fault_domain):
        return self.call("compute", region, "capacity", self.tenancy_id, ad, shapes, fault_domain)


class InventoryTests(unittest.TestCase):
    def test_separates_root_limits_from_target_headroom(self):
        session = FakeSession()
        result = discover_accelerators(compartment_id="child-compartment", session=session)
        self.assertEqual(result["status"], "complete")
        self.assertEqual(result["compartment_id"], "child-compartment")
        calls = {call[2]: call for call in session.calls}
        self.assertEqual(calls["list_limit_values"][3][0], "root-tenancy")
        self.assertEqual(calls["get_resource_availability"][3], ("compute", "gpu-test-count", "child-compartment"))
        self.assertEqual(calls["get_resource_availability"][4], {"availability_domain": "AD-1"})
        shapes = result["regions"][0]["availability_domains"][0]["shapes"]
        self.assertEqual(len(shapes), 1)
        self.assertIsNone(shapes[0]["gpu_memory_gib"])
        self.assertEqual(shapes[0]["memory_in_gbs"], 512)
        self.assertTrue(all(c[4].get("paginated") for c in session.calls if c[2].startswith("list_")))

    def test_regional_limit_omits_ad(self):
        session = FakeSession()
        session.responses["list_limit_values"][0].update(scope_type="REGION", availability_domain=None)
        discover_accelerators(session=session)
        call = next(c for c in session.calls if c[2] == "get_resource_availability")
        self.assertEqual(call[4], {})

    def test_missing_ad_does_not_make_invalid_headroom_request(self):
        session = FakeSession()
        session.responses["list_limit_values"][0]["availability_domain"] = None
        result = discover_accelerators(session=session)
        self.assertEqual(result["status"], "partial")
        self.assertFalse(any(c[2] == "get_resource_availability" for c in session.calls))

    def test_denied_inventory_is_unknown_not_empty_success(self):
        session = FakeSession()
        session.failures["list_shapes"] = DiscoveryFailure("403", "NotAuthorized")
        result = discover_accelerators(session=session)
        self.assertEqual(result["status"], "partial")
        ad = result["regions"][0]["availability_domains"][0]
        self.assertEqual(ad["status"], "unknown")
        self.assertEqual(ad["error"]["status"], "403")

    def test_unsupported_headroom_and_null_values_remain_unknown(self):
        for response in ({"available": None, "used": None}, {}):
            session = FakeSession()
            session.responses["get_resource_availability"] = response
            result = discover_accelerators(session=session)
            self.assertEqual(result["regions"][0]["limits"][0]["resource_availability"]["status"], "unknown")
        session = FakeSession()
        session.failures["get_resource_availability"] = DiscoveryFailure("404", "NotFound")
        self.assertEqual(discover_accelerators(session=session)["status"], "partial")

    def test_fractional_availability_is_not_discarded(self):
        session = FakeSession()
        session.responses["get_resource_availability"] = {"fractional_availability": 0.5}
        self.assertEqual(discover_accelerators(session=session)["status"], "complete")

    def test_headroom_budget_is_explicit(self):
        session = FakeSession()
        result = discover_accelerators(max_limit_checks=0, session=session)
        self.assertEqual(result["status"], "partial")
        self.assertEqual(result["headroom_queries_used"], 0)
        self.assertFalse(any(c[2] == "get_resource_availability" for c in session.calls))

    def test_unsubscribed_region_is_not_scanned(self):
        session = FakeSession()
        result = discover_accelerators(regions=["other-region"], session=session)
        self.assertEqual(result["regions"][0]["status"], "not_ready_or_unsubscribed")
        self.assertEqual(len(session.calls), 1)

    def test_unmapped_quota_is_not_guessed(self):
        session = FakeSession()
        session.responses["list_shapes"][0]["quota_names"] = ["unmapped-name"]
        result = discover_accelerators(shape_names=["VM.GPU.Test.2"], session=session)
        self.assertEqual(result["regions"][0]["unmapped_shape_quota_names"], ["unmapped-name"])
        self.assertEqual(result["status"], "partial")


class CapacityTests(unittest.TestCase):
    def assess(self, session, **kwargs):
        return assess_capacity(region="region-one", availability_domain="AD-1", shape_names=["VM.GPU.Test.2"], session=session, **kwargs)

    def test_counts_instances_and_uses_root(self):
        session = FakeSession()
        result = self.assess(session, requested_instances=3)
        self.assertEqual(result["report_compartment_id"], "root-tenancy")
        self.assertEqual(result["shapes"][0]["available_instances"], 2)
        self.assertFalse(result["shapes"][0]["reported_sufficient"])
        self.assertEqual(session.calls[0][3][0], "root-tenancy")

    def test_unsupported_hardware_or_missing_shape_is_not_no_capacity(self):
        for rows in ([], [{"instance_shape": "VM.GPU.Test.2", "availability_status": "HARDWARE_NOT_SUPPORTED", "available_count": 0}]):
            session = FakeSession()
            session.responses["capacity"] = {"shape_availabilities": rows}
            result = self.assess(session)
            self.assertIsNone(result["shapes"][0]["reported_sufficient"])
            self.assertEqual(result["status"], "partial")

    def test_out_of_capacity_is_a_known_negative(self):
        session = FakeSession()
        session.responses["capacity"]["shape_availabilities"][0].update(availability_status="OUT_OF_HOST_CAPACITY", available_count=0)
        result = self.assess(session)
        self.assertEqual(result["status"], "complete")
        self.assertFalse(result["shapes"][0]["reported_sufficient"])

    def test_fault_domain_rows_are_never_summed(self):
        session = FakeSession()
        row = session.responses["capacity"]["shape_availabilities"][0]
        session.responses["capacity"]["shape_availabilities"] = [dict(row, fault_domain=fd) for fd in ["FD-1", "FD-2"]]
        result = self.assess(session, requested_instances=3)
        self.assertEqual(len(result["shapes"]), 2)
        self.assertTrue(all(r["reported_sufficient"] is False for r in result["shapes"]))

    def test_report_denial_is_partial_and_sanitized(self):
        session = FakeSession()
        session.failures["capacity"] = DiscoveryFailure("403", "NotAuthorized")
        result = self.assess(session)
        self.assertEqual(result["status"], "partial")
        self.assertEqual(result["report"]["error"]["status"], "403")
        self.assertIsNone(result["shapes"][0]["available_instances"])

    def test_real_sdk_serializes_report_in_root_compartment(self):
        try:
            import oci
        except ImportError:
            self.skipTest("OCI SDK extra is not installed")
        session = object.__new__(OciSession)
        session.sdk, session.tenancy_id = oci, "root-tenancy"
        with patch.object(session, "call", return_value={}) as call:
            session.capacity("region-one", "AD-1", ["VM.GPU.Test.2"], None)
        details = oci.util.to_dict(call.call_args.args[3])
        self.assertEqual(details["compartment_id"], "root-tenancy")
        self.assertEqual(details["shape_availabilities"][0]["instance_shape"], "VM.GPU.Test.2")
        self.assertIsNone(details["shape_availabilities"][0]["fault_domain"])


class OciCliTests(unittest.TestCase):
    def test_external_oci_protocol(self):
        out = io.StringIO()
        query = {"operation": "inventory", "regions": '["region-one"]', "shape_names": '["VM.GPU.Test.2"]'}
        with patch("sys.stdin", io.StringIO(json.dumps(query))), redirect_stdout(out), \
                patch("oke_llm_serving.oci_discovery.OciSession", return_value=FakeSession()):
            self.assertEqual(main(["terraform-oci"]), 0)
        result = json.loads(json.loads(out.getvalue())["result_json"])
        self.assertEqual(result["status"], "complete")

    def test_explicit_region_bootstraps_principal_clients(self):
        with patch("oke_llm_serving.oci_discovery.OciSession", return_value=FakeSession()) as factory:
            discover_accelerators(regions=["region-one"], auth="resource_principal", tenancy_id="root-tenancy")
        self.assertEqual(factory.call_args.args[-1], "region-one")

    def test_capacity_does_not_accept_target_compartment(self):
        query = {"operation": "capacity", "compartment_id": "child"}
        out, err = io.StringIO(), io.StringIO()
        with patch("sys.stdin", io.StringIO(json.dumps(query))), redirect_stdout(out), redirect_stderr(err):
            self.assertEqual(main(["terraform-oci"]), 2)
        self.assertEqual(out.getvalue(), "")
        self.assertEqual(json.loads(err.getvalue())["error"]["code"], "invalid_query")

    def test_invalid_request_does_not_call_oci(self):
        with self.assertRaises(ProfileError):
            assess_capacity(region="r", availability_domain="a", shape_names=[], requested_instances=0)

    @unittest.skipUnless(importlib.util.find_spec("oci"), "OCI SDK extra is not installed")
    def test_external_entry_point_imports_sdk_without_shadowing_stdlib(self):
        root = Path(__file__).resolve().parents[1]
        for module in ["accelerator-inventory", "capacity-assessment"]:
            query = {"operation": "inventory", "config_file": str(root / "tests/nonexistent-oci-config")}
            result = subprocess.run([sys.executable, str(root / "terraform/modules" / module / "discover.py")],
                                    input=json.dumps(query), text=True, capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(result.stdout, "")
            self.assertEqual(json.loads(result.stderr)["error"]["code"], "oci_authentication_error")


if __name__ == "__main__":
    unittest.main()
