from __future__ import annotations

import subprocess
import sys
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).parent / "fixtures"


class SchemaValidationCliTests(unittest.TestCase):
    """Exercise the public CLI, including schema resolution from another CWD."""

    def run_validator(self, schema: str, fixture: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, "-m", "world_authoring.validation.validate", schema, str(FIXTURES / fixture)],
            cwd=Path("/tmp"),
            env={"PYTHONPATH": str(REPOSITORY_ROOT)},
            text=True,
            capture_output=True,
            check=False,
        )

    def test_valid_minimal_map_spec(self) -> None:
        result = self.run_validator("map-spec", "valid_minimal_map_spec.json")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_invalid_map_spec_cases_report_paths(self) -> None:
        cases = {
            "invalid_map_spec_unknown_field.json": "/: Additional properties",
            "invalid_map_spec_raw_asset_path.json": "/structures/0/asset:",
            "invalid_map_spec_bad_vector.json": "/spawn_points/0/position:",
            "invalid_map_spec_missing_required.json": "/map: 'seed' is a required property",
            "invalid_map_spec_invalid_enum.json": "/map/preset:",
        }
        for fixture, expected in cases.items():
            with self.subTest(fixture=fixture):
                result = self.run_validator("map-spec", fixture)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn(expected, result.stdout)

    def test_valid_map_patch(self) -> None:
        result = self.run_validator("map-patch", "valid_map_patch.json")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_invalid_map_patch_cases(self) -> None:
        for fixture in ("invalid_map_patch_malformed_operation.json", "invalid_map_patch_raw_asset_path.json"):
            with self.subTest(fixture=fixture):
                result = self.run_validator("map-patch", fixture)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("/operations/0:", result.stdout)


if __name__ == "__main__":
    unittest.main()
