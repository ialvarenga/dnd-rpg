from __future__ import annotations

import copy
import json
import re
import subprocess
import sys
import unittest
from pathlib import Path
from typing import Any, Iterator


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
REFERENCE_MAP = REPOSITORY_ROOT / "world_authoring" / "maps" / "forest_encounter_reference.json"
ASSET_CATALOG_SOURCE = REPOSITORY_ROOT / "godot" / "world" / "asset_catalog.gd"


def load_reference_map() -> dict[str, Any]:
    with REFERENCE_MAP.open(encoding="utf-8") as handle:
        return json.load(handle)


def catalog_asset_ids() -> set[str]:
    """Read B1's declared resources; do not mirror its catalog IDs in Python."""
    source = ASSET_CATALOG_SOURCE.read_text(encoding="utf-8")
    definition_paths = re.findall(r'"(res://data/assets/[^"\n]+\.tres)"', source)
    if not definition_paths:
        raise AssertionError("B1 AssetCatalog.DEFINITION_PATHS contains no asset definitions")

    ids: set[str] = set()
    for resource_path in definition_paths:
        definition_path = REPOSITORY_ROOT / "godot" / resource_path.removeprefix("res://")
        definition = definition_path.read_text(encoding="utf-8")
        match = re.search(r'^id = &"([a-z][a-z0-9_]*)"$', definition, re.MULTILINE)
        if match is None:
            raise AssertionError(f"B1 asset definition has no stable ID: {definition_path}")
        ids.add(match.group(1))
    return ids


def asset_references(document: dict[str, Any]) -> Iterator[tuple[str, str]]:
    for collection_name in ("vegetation", "structures", "interactables"):
        for index, placement in enumerate(document.get(collection_name, [])):
            yield f"/{collection_name}/{index}/asset", placement["asset"]


def assert_assets_are_catalogued(document: dict[str, Any]) -> None:
    known_ids = catalog_asset_ids()
    for location, asset_id in asset_references(document):
        if asset_id.startswith("res://"):
            raise AssertionError(f"{location}: raw resource path is not allowed: {asset_id}")
        if asset_id not in known_ids:
            raise AssertionError(f"{location}: unknown B1 AssetCatalog ID: {asset_id}")


def positioned_coordinates(document: dict[str, Any]) -> Iterator[tuple[str, list[float]]]:
    for region_index, region in enumerate(document.get("regions", [])):
        for point_index, point in enumerate(region["polygon"]):
            yield f"/regions/{region_index}/polygon/{point_index}", point
    for collection_name in ("vegetation", "structures", "actors", "spawn_points", "interactables"):
        for index, placement in enumerate(document.get(collection_name, [])):
            yield f"/{collection_name}/{index}/position", placement["position"]


def assert_coordinates_are_within_bounds(document: dict[str, Any]) -> None:
    bounds = document["map"]["bounds"]
    width_m = bounds["width_m"]
    height_m = bounds["height_m"]
    for location, (east_m, north_m) in positioned_coordinates(document):
        if not 0 <= east_m <= width_m or not 0 <= north_m <= height_m:
            raise AssertionError(
                f"{location}: coordinate [{east_m}, {north_m}] is outside "
                f"[0, {width_m}] x [0, {height_m}]"
            )


class B3ReferenceMapTests(unittest.TestCase):
    def run_validator(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, "-m", "world_authoring.validation.validate", "map-spec", str(REFERENCE_MAP)],
            cwd=Path("/tmp"),
            env={"PYTHONPATH": str(REPOSITORY_ROOT)},
            text=True,
            capture_output=True,
            check=False,
        )

    def test_reference_map_is_deterministic_and_schema_valid(self) -> None:
        first_load = load_reference_map()
        second_load = load_reference_map()
        self.assertEqual(first_load, second_load)
        self.assertEqual(first_load["version"], "1.0")
        self.assertEqual(first_load["map"]["id"], "forest_encounter_reference")
        self.assertEqual(first_load["map"]["seed"], 918273)
        self.assertEqual(first_load["map"]["preset"], "encounter")

        result = self.run_validator()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_reference_assets_are_real_b1_catalog_ids_without_raw_paths(self) -> None:
        document = load_reference_map()
        assert_assets_are_catalogued(document)

        raw_path_document = copy.deepcopy(document)
        raw_path_document["vegetation"][0]["asset"] = "res://assets/example.tscn"
        with self.assertRaisesRegex(AssertionError, r"/vegetation/0/asset: raw resource path"):
            assert_assets_are_catalogued(raw_path_document)

        unknown_asset_document = copy.deepcopy(document)
        unknown_asset_document["vegetation"][0]["asset"] = "unknown_tree"
        with self.assertRaisesRegex(AssertionError, r"/vegetation/0/asset: unknown B1 AssetCatalog ID"):
            assert_assets_are_catalogued(unknown_asset_document)

    def test_reference_coordinates_are_within_bounds(self) -> None:
        document = load_reference_map()
        assert_coordinates_are_within_bounds(document)

        outside_bounds_document = copy.deepcopy(document)
        outside_bounds_document["spawn_points"][0]["position"] = [65, 8]
        with self.assertRaisesRegex(AssertionError, r"/spawn_points/0/position: coordinate \[65, 8\] is outside"):
            assert_coordinates_are_within_bounds(outside_bounds_document)


if __name__ == "__main__":
    unittest.main()
