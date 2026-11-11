"""JSON CLI and Terraform external-program entry point."""

import argparse
import json
import sys

from .model_profile import ProfileError, inspect_model


def parser():
    root = argparse.ArgumentParser(description="Inspect Hugging Face model requirements without downloading weights.")
    commands = root.add_subparsers(dest="command", required=True)
    command = commands.add_parser("inspect")
    command.add_argument("model")
    command.add_argument("--revision", default="main")
    command.add_argument("--checkpoint")
    command.add_argument("--context-length", type=int, default=4096)
    command.add_argument("--concurrency", type=int, default=1)
    command.add_argument("--kv-dtype", default="bfloat16")
    command.add_argument("--weight-dtype", default="checkpoint")
    command.add_argument("--runtime-gib", type=float, default=2.0)
    command.add_argument("--margin", type=float, default=0.2)
    commands.add_parser("terraform", help="Read the external data-source query from stdin.")
    inventory = commands.add_parser("inventory", help="Inspect GPU shapes and entitlement headroom; does not allocate hardware.")
    inventory.add_argument("--compartment-id")
    inventory.add_argument("--regions", nargs="+")
    inventory.add_argument("--shapes", nargs="+", dest="shape_names")
    inventory.add_argument("--max-limit-checks", type=int, default=100)
    capacity = commands.add_parser("capacity", help="Create a host-capacity report in the tenancy root; does not allocate hardware.")
    capacity.add_argument("--region", required=True)
    capacity.add_argument("--availability-domain", required=True)
    capacity.add_argument("--shapes", nargs="+", dest="shape_names", required=True)
    capacity.add_argument("--fault-domain")
    capacity.add_argument("--requested-instances", type=int, default=1)
    for command in (inventory, capacity):
        command.add_argument("--profile", default="DEFAULT")
        command.add_argument("--config-file")
        command.add_argument("--auth", choices=["config", "instance_principal", "resource_principal"], default="config")
        command.add_argument("--tenancy-id", help="Required if principal authentication cannot derive the tenancy.")
    commands.add_parser("terraform-oci", help="Read an OCI discovery external-data-source query from stdin.")
    return root


def terraform_oci_query(query):
    from .oci_discovery import assess_capacity, discover_accelerators

    common = {"profile", "config_file", "auth", "tenancy_id"}
    inventory = {"compartment_id", "regions", "shape_names", "max_limit_checks"}
    capacity = {"region", "availability_domain", "shape_names", "fault_domain", "requested_instances"}
    if not isinstance(query, dict) or any(not isinstance(v, str) for v in query.values()):
        raise ProfileError("invalid_query", "Terraform query must be a string-valued object.")
    operation = query.get("operation")
    allowed = inventory if operation == "inventory" else capacity if operation == "capacity" else None
    if allowed is None or set(query) - (common | allowed | {"operation"}):
        raise ProfileError("invalid_query", "Unknown OCI discovery operation or query key.")
    params = {k: v for k, v in query.items() if k != "operation" and v != ""}
    for key in ("regions", "shape_names"):
        if key in params:
            params[key] = json.loads(params[key])
    for key in ("max_limit_checks", "requested_instances"):
        if key in params:
            params[key] = int(params[key])
    if operation == "capacity" and not {"region", "availability_domain", "shape_names"}.issubset(params):
        raise ProfileError("invalid_query", "Capacity query requires region, availability_domain and shape_names.")
    result = (discover_accelerators if operation == "inventory" else assess_capacity)(**params)
    return {"result_json": json.dumps(result, allow_nan=False)}


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        if args.command == "terraform-oci":
            output = terraform_oci_query(json.load(sys.stdin))
        elif args.command in {"inventory", "capacity"}:
            from .oci_discovery import assess_capacity, discover_accelerators

            params = vars(args).copy()
            command = params.pop("command")
            output = (discover_accelerators if command == "inventory" else assess_capacity)(**params)
        elif args.command == "terraform":
            query = json.load(sys.stdin)
            allowed = {"model", "revision", "checkpoint", "context_length", "concurrency", "kv_dtype", "weight_dtype", "runtime_gib", "margin"}
            if not isinstance(query, dict) or set(query) - allowed or "model" not in query:
                raise ProfileError("invalid_query", "Invalid Terraform query keys; model is required.")
            if any(not isinstance(v, str) for v in query.values()):
                raise ProfileError("invalid_query", "Terraform query values must be strings.")
            for key in ("context_length", "concurrency"):
                if key in query:
                    query[key] = int(query[key])
            for key in ("runtime_gib", "margin"):
                if key in query:
                    query[key] = float(query[key])
            if not query.get("checkpoint"):
                query.pop("checkpoint", None)
            profile = inspect_model(**query)
            output = {"profile_json": json.dumps(profile, allow_nan=False)}
        else:
            params = vars(args).copy()
            params.pop("command")
            output = inspect_model(**params)
        print(json.dumps(output, indent=2, allow_nan=False))
        return 0
    except ProfileError as exc:
        print(json.dumps({"error": {"code": exc.code, "message": str(exc)}}), file=sys.stderr)
    except (ValueError, TypeError):
        print(json.dumps({"error": {"code": "invalid_input", "message": "Invalid JSON or numeric input."}}), file=sys.stderr)
    return 2
