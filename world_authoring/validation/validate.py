"""Validate MapSpec and MapPatch JSON with the canonical Draft 2020-12 schemas.

Run from any directory with ``python -m world_authoring.validation.validate``.
Schema paths are derived from this module, not the process working directory.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Iterable

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource


SCHEMA_DIRECTORY = Path(__file__).resolve().parents[1] / "schema"
SCHEMA_FILES = {
    "map-spec": "map_spec.schema.json",
    "map-patch": "map_patch.schema.json",
}


def _load_schema(name: str) -> dict[str, Any]:
    with (SCHEMA_DIRECTORY / SCHEMA_FILES[name]).open(encoding="utf-8") as handle:
        return json.load(handle)


def build_validator(schema_name: str) -> Draft202012Validator:
    """Build a validator whose registry contains every canonical local schema."""
    schemas = [_load_schema(name) for name in SCHEMA_FILES]
    registry = Registry().with_resources(
        (schema["$id"], Resource.from_contents(schema)) for schema in schemas
    )
    return Draft202012Validator(_load_schema(schema_name), registry=registry, format_checker=FormatChecker())


def format_error(error: Any) -> str:
    """Render a deterministic, JSON-pointer-like location for one validation error."""
    path = "/".join(str(part) for part in error.absolute_path)
    location = "/" + path if path else "/"
    return f"{location}: {error.message}"


def validate_document(document: Any, schema_name: str) -> list[str]:
    """Return path-specific validation errors, sorted for stable CLI and test output."""
    errors: Iterable[Any] = build_validator(schema_name).iter_errors(document)
    return [format_error(error) for error in sorted(errors, key=lambda item: list(item.absolute_path))]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate MapSpec or MapPatch JSON against canonical schemas.")
    parser.add_argument("schema", choices=sorted(SCHEMA_FILES), help="Canonical schema to apply")
    parser.add_argument("document", type=Path, help="JSON document to validate")
    args = parser.parse_args(argv)

    try:
        with args.document.open(encoding="utf-8") as handle:
            document = json.load(handle)
    except (OSError, json.JSONDecodeError) as error:
        print(f"{args.document}: unable to read JSON: {error}")
        return 2

    errors = validate_document(document, args.schema)
    if errors:
        for error in errors:
            print(error)
        return 1
    print(f"valid {args.schema}: {args.document}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
