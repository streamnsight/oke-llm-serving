"""OCI entitlement inventory and physical-capacity observations, without allocation."""

from datetime import datetime, timezone

from .model_profile import ProfileError


def now():
    return datetime.now(timezone.utc).isoformat()


class OciSession:
    """Small SDK boundary; imports/authentication are unnecessary for model inspection."""
    def __init__(self, profile="DEFAULT", config_file=None, auth="config", tenancy_id=None, region=None):
        try:
            import oci
        except ImportError:
            raise ProfileError("oci_sdk_missing", "Install the OCI extra: pip install -e '.[oci]'.") from None
        self.sdk = oci
        try:
            signer = None
            if auth == "config":
                config = oci.config.from_file(profile_name=profile, **({"file_location": config_file} if config_file else {}))
                self.tenancy_id = config["tenancy"]
                self.region = region or config["region"]
                if tenancy_id and tenancy_id != self.tenancy_id:
                    raise ProfileError("invalid_input", "The supplied tenancy does not match the selected OCI profile.")
            elif auth in {"resource_principal", "instance_principal"}:
                signer = (oci.auth.signers.get_resource_principals_signer() if auth == "resource_principal"
                          else oci.auth.signers.InstancePrincipalsSecurityTokenSigner())
                self.tenancy_id = tenancy_id or getattr(signer, "tenancy_id", None)
                self.region = region or getattr(signer, "region", None)
                config = {}
                if not self.tenancy_id or not self.region:
                    raise ProfileError("invalid_input", "Principal authentication requires a tenancy ID and region.")
            else:
                raise ProfileError("invalid_input", "Use config, resource_principal or instance_principal authentication.")
            self.config = dict(config, region=self.region)
            self.options = {"timeout": (10, 30), "retry_strategy": oci.retry.NoneRetryStrategy()}
            if signer:
                self.options["signer"] = signer
            self.clients = {}
        except ProfileError:
            raise
        except Exception:
            raise ProfileError("oci_authentication_error", "Could not initialize OCI authentication; check the selected profile or principal configuration.") from None

    def client(self, service, region):
        key = (service, region)
        if key not in self.clients:
            cls = {"identity": self.sdk.identity.IdentityClient,
                   "compute": self.sdk.core.ComputeClient, "limits": self.sdk.limits.LimitsClient}[service]
            try:
                self.clients[key] = cls(dict(self.config, region=region), **self.options)
            except (self.sdk.exceptions.InvalidConfig, self.sdk.exceptions.InvalidPrivateKey, OSError):
                raise ProfileError("oci_authentication_error", "Could not initialize the OCI client; check signing credentials.") from None
        return self.clients[key]

    def call(self, service, region, method, *args, paginated=False, **kwargs):
        try:
            function = getattr(self.client(service, region), method)
            response = (self.sdk.pagination.list_call_get_all_results(function, *args, **kwargs)
                        if paginated else function(*args, **kwargs))
            return self.sdk.util.to_dict(response.data)
        except self.sdk.exceptions.ServiceError as exc:
            # Never propagate service messages, request headers, signing material or URLs.
            raise DiscoveryFailure(str(exc.status), str(exc.code)) from None
        except (self.sdk.exceptions.RequestException, self.sdk.exceptions.ConfigFileNotFound):
            raise DiscoveryFailure("connection_error", "OCI request could not be completed.") from None

    def capacity(self, region, ad, shapes, fault_domain):
        models = self.sdk.core.models
        details = models.CreateComputeCapacityReportDetails(
            compartment_id=self.tenancy_id, availability_domain=ad,
            shape_availabilities=[models.CreateCapacityReportShapeAvailabilityDetails(
                instance_shape=shape, fault_domain=fault_domain) for shape in shapes],
        )
        return self.call("compute", region, "create_compute_capacity_report", details)


class DiscoveryFailure(Exception):
    def __init__(self, status, code):
        self.status, self.code = status, code


def observe(function, *args, **kwargs):
    timestamp = now()
    try:
        return {"status": "observed", "observed_at": timestamp, "data": function(*args, **kwargs)}
    except DiscoveryFailure as exc:
        return {"status": "unknown", "observed_at": timestamp,
                "error": {"status": exc.status, "code": exc.code}, "data": None}


def summary_status(observations):
    return "complete" if all(o["status"] == "observed" for o in observations) else "partial"


def discover_accelerators(*, compartment_id=None, regions=None, shape_names=None,
                          profile="DEFAULT", config_file=None, auth="config", tenancy_id=None,
                          region=None, max_limit_checks=100, session=None):
    if type(max_limit_checks) is not int or not 0 <= max_limit_checks <= 1000:
        raise ProfileError("invalid_input", "max_limit_checks must be an integer between 0 and 1000.")
    if regions is not None and (not isinstance(regions, list) or not regions or any(not isinstance(r, str) or not r for r in regions)):
        raise ProfileError("invalid_input", "regions must be a nonempty list of region names.")
    if shape_names is not None and (not isinstance(shape_names, list) or any(not isinstance(s, str) or not s for s in shape_names)):
        raise ProfileError("invalid_input", "shape_names must be a list of shape names.")
    session = session or OciSession(profile, config_file, auth, tenancy_id, region or (regions[0] if regions else None))
    compartment_id = compartment_id or session.tenancy_id
    subscriptions = observe(session.call, "identity", session.region, "list_region_subscriptions", session.tenancy_id, paginated=True)
    requested = list(dict.fromkeys(regions or [session.region]))
    result = {"schema_version": "1.0", "observed_at": now(), "tenancy_id": session.tenancy_id,
              "compartment_id": compartment_id, "subscriptions": subscriptions, "regions": [],
              "warnings": ["Shape visibility, entitlement headroom and host capacity are separate observations.",
                           "Host memory is not GPU VRAM; NVLink topology and per-GPU memory are not inferred.",
                           "Quota-name links are exact API-name matches only; no GPU/instance entitlement conversion is assumed."]}
    subscriptions_by_name = {s["region_name"]: s for s in subscriptions["data"] or []}
    checks_left = max_limit_checks
    all_observations = [subscriptions]
    for selected_region in requested:
        entry = {"region": selected_region}
        sub = subscriptions_by_name.get(selected_region)
        if subscriptions["status"] == "observed" and (sub is None or sub.get("status") != "READY"):
            entry.update(status="not_ready_or_unsubscribed", availability_domains=[], limits=[])
            result["regions"].append(entry)
            all_observations.append({"status": "unknown"})
            continue
        ads = observe(session.call, "identity", selected_region, "list_availability_domains", session.tenancy_id, paginated=True)
        definitions = observe(session.call, "limits", selected_region, "list_limit_definitions", session.tenancy_id, service_name="compute", paginated=True)
        values = observe(session.call, "limits", selected_region, "list_limit_values", session.tenancy_id, "compute", paginated=True)
        observations = [ads, definitions, values]
        entry.update(availability_domains_observation=ads, limit_definitions_observation=definitions,
                     limit_values_observation=values, availability_domains=[], limits=[])
        quota_names = set()
        for ad in ads["data"] or []:
            ad_name = ad["name"]
            shapes = observe(session.call, "compute", selected_region, "list_shapes", compartment_id, availability_domain=ad_name, paginated=True)
            observations.append(shapes)
            gpu_shapes = []
            for shape in shapes["data"] or []:
                if not shape.get("gpus") or (shape_names and shape.get("shape") not in shape_names):
                    continue
                fields = ["shape", "gpus", "gpu_description", "ocpus", "memory_in_gbs", "local_disks",
                          "local_disks_total_size_in_gbs", "rdma_ports", "rdma_bandwidth_in_gbps", "quota_names"]
                normalized = {key: shape.get(key) for key in fields}
                normalized["gpu_memory_gib"] = None
                normalized["nvlink_topology"] = None
                quota_names.update(shape.get("quota_names") or [])
                gpu_shapes.append(normalized)
            # Avoid retaining non-GPU inventory; the request status still distinguishes unknown from an empty result.
            entry["availability_domains"].append({"name": ad_name, "status": shapes["status"],
                "observed_at": shapes["observed_at"], "error": shapes.get("error"), "shapes": sorted(gpu_shapes, key=lambda s: s["shape"])})
        defs = {d["name"]: d for d in definitions["data"] or []}
        for value in values["data"] or []:
            name = value.get("name", "")
            # With a shape filter, retain exact mappings only; without it include GPU-named limits as context.
            if name not in quota_names and (shape_names or "gpu" not in name.lower()):
                continue
            definition = defs.get(name, {})
            scope = value.get("scope_type") or definition.get("scope_type")
            ad_name = value.get("availability_domain")
            limit = {"name": name, "scope_type": scope, "availability_domain": ad_name,
                     "tenancy_limit": value.get("value"), "description": definition.get("description"),
                     "are_quotas_supported": definition.get("are_quotas_supported"),
                     "matched_shape_quota_name": name in quota_names}
            if scope not in {"AD", "REGION", "GLOBAL"} or (scope == "AD" and not ad_name):
                availability = {"status": "unknown", "data": None, "reason": "Missing or unsupported limit scope."}
            elif definition.get("is_resource_availability_supported") is False:
                availability = {"status": "unknown", "data": None, "reason": "Resource availability is not supported for this limit."}
            elif checks_left == 0:
                availability = {"status": "unknown", "data": None, "reason": "Configured headroom-query budget exhausted."}
            else:
                checks_left -= 1
                availability = observe(session.call, "limits", selected_region, "get_resource_availability", "compute", name, compartment_id,
                                       **({"availability_domain": ad_name} if scope == "AD" else {}))
                data = availability["data"]
                if data is not None and data.get("available") is None and data.get("fractional_availability") is None:
                    availability.update(status="unknown", reason="API returned no available headroom value.")
            limit["resource_availability"] = availability
            observations.append(availability)
            entry["limits"].append(limit)
        observed_names = {limit["name"] for limit in entry["limits"]}
        entry["unmapped_shape_quota_names"] = sorted(quota_names - observed_names)
        if entry["unmapped_shape_quota_names"]:
            observations.append({"status": "unknown"})
        entry["status"] = summary_status(observations)
        all_observations.extend(observations)
        result["regions"].append(entry)
    result["status"] = summary_status(all_observations)
    result["headroom_queries_used"] = max_limit_checks - checks_left
    return result


def assess_capacity(*, region, availability_domain, shape_names, fault_domain=None,
                    requested_instances=1, profile="DEFAULT", config_file=None,
                    auth="config", tenancy_id=None, session=None):
    if not region or not availability_domain or not isinstance(shape_names, list) or not shape_names or any(not isinstance(s, str) or not s for s in shape_names):
        raise ProfileError("invalid_input", "Region, availability domain and at least one shape are required.")
    if type(requested_instances) is not int or requested_instances < 1:
        raise ProfileError("invalid_input", "requested_instances must be a positive integer.")
    if len(shape_names) > 100:
        raise ProfileError("invalid_input", "Limit each capacity assessment to 100 shapes.")
    session = session or OciSession(profile, config_file, auth, tenancy_id, region)
    shapes = list(dict.fromkeys(shape_names))
    report = observe(session.capacity, region, availability_domain, shapes, fault_domain)
    rows = []
    returned = (report["data"] or {}).get("shape_availabilities", []) or []
    for shape in shapes:
        matches = [r for r in returned if r.get("instance_shape") == shape]
        # Preserve FD-scoped rows. Never add counts across potentially overlapping report scopes.
        for row in matches or [{}]:
            status, count = row.get("availability_status"), row.get("available_count")
            enough = (count >= requested_instances if status == "AVAILABLE" and type(count) is int and count >= 0
                      else False if status == "OUT_OF_HOST_CAPACITY" else None)
            rows.append({"shape": shape, "fault_domain": row.get("fault_domain", fault_domain),
                         "availability_status": status or "UNKNOWN", "available_instances": count,
                         "requested_instances": requested_instances, "reported_sufficient": enough})
    partial = report["status"] != "observed" or any(r["reported_sufficient"] is None for r in rows)
    return {"schema_version": "1.0", "observed_at": report["observed_at"], "status": "partial" if partial else "complete",
            "region": region, "availability_domain": availability_domain,
            "report_compartment_id": session.tenancy_id, "fault_domain": fault_domain,
            "report": report, "shapes": rows,
            "warnings": ["This is a host-capacity observation, not a reservation or launch guarantee.",
                         "Counts are instances, not individual GPUs. No quota or deployment-compartment eligibility is assessed.",
                         "Reported counts do not establish that RDMA/compute-cluster placement will succeed."]}
