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
    return root


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        if args.command == "terraform":
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
