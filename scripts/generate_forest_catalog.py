#!/usr/bin/env python3
"""Generate the KayKit forest catalog artifacts from imported glTF bounds."""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
import zlib
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "godot/assets/kaykit_forest"
CATALOG_PATH = ROOT / "godot/world/asset_catalog.gd"
JS_PATH = ROOT / "map_builder/js/asset-catalog.js"
CSV_PATH = ROOT / "docs/third_party/assets.csv"
FOREST_DIR = ROOT / "godot/data/assets/forest"
FAMILIES = {"trees": ("tree", 27, True), "bushes": ("bush", 35, False), "grass": ("grass", 45, False), "rocks": ("rock", 40, True)}
# Atlas palette columns each family may use, from scripts/generate_forest_palettes.py.
# Autumn (6 gold, 7 rust, 8 dry) stays out of the automatic rotation so a
# temperate region does not sprout autumn trees; author it per asset instead.
PALETTES = {"tree": (1, 2, 3, 4, 5), "bush": (1, 2, 3, 4, 5), "grass": (1, 2, 3, 4), "rock": (1, 2, 5), "hill": (1, 2, 5)}
# Only the 21 freestanding Hill_WxDxH blocks are catalogued (as heightfield
# stamps -- see ADR-007). The 40-piece Hill_Cliff_*/Hill_Top_* modular tile
# kit needs grid-snapping authoring UI and is a separate, larger job.
HILL_BLOCK_RE = re.compile(r"^Hill_(\d+)x(\d+)x(\d+)_Color1\.gltf$")
# Anti z-fight offset lifting the hill mesh above the stamped terrain surface
# it is coincident with; keep in sync with ADR-007.
HILL_DISPLAY_EPSILON_M = 0.03
LEGACY = {
    "Tree_1_A_Color1.gltf": "tree_oak_01", "Tree_3_A_Color1.gltf": "tree_oak_02",
    "Rock_3_R_Color1.gltf": "rock_large_01", "Bush_1_A_Color1.gltf": "bush_01",
    "Grass_1_A_Color1.gltf": "grass_01",
}
SOURCE = "KayKit Forest Nature Pack 1.0 (www.kaylousberg.com)"


@dataclass(frozen=True)
class Model:
    file: Path
    folder: str
    id: str
    family: str
    tags: list[str]
    radius: float
    offset_y: float
    slope: int
    blocks: bool
    palette_index: int
    asset_type: str = "vegetation"
    collision_shape: str = "cylinder"
    collision_size: tuple[float, float, float] | None = None
    # (width_m, depth_m) footprint for hills, so the map builder can draw a
    # to-scale rectangle instead of the generic circular footprint.
    nominal_size: tuple[float, float] | None = None

    @property
    def scene_path(self) -> str:
        return "res://assets/kaykit_forest/%s/%s" % (self.folder, self.file.name)

    @property
    def label(self) -> str:
        name = self.file.stem.removesuffix("_Color1")
        return name.replace("_", " ").replace("Singlesided", "Single-sided")


def gltf_bounds(path: Path) -> tuple[list[float], list[float]]:
    doc = json.loads(path.read_text())
    accessor = doc["accessors"][doc["meshes"][0]["primitives"][0]["attributes"]["POSITION"]]
    return accessor["min"], accessor["max"]


def stable_id(path: Path) -> str:
    return "forest_" + path.stem.removesuffix("_Color1").lower()


def palette_for(asset_id: str, family: str) -> int:
    """Spread a family's models across its palettes, stably across runs."""
    choices = PALETTES[family]
    return choices[zlib.crc32(asset_id.encode()) % len(choices)]


def models() -> list[Model]:
    result: list[Model] = []
    for folder, (family, slope, blocks) in FAMILIES.items():
        for path in sorted((ASSET_ROOT / folder).glob("*.gltf")):
            minimum, maximum = gltf_bounds(path)
            radius = max(abs(minimum[0]), abs(maximum[0]), abs(minimum[2]), abs(maximum[2]))
            tags = ["temperate", "forest", family]
            if path.name.startswith("Tree_Bare_"):
                tags.append("bare")
            if "Singlesided" in path.name:
                tags.append("singlesided")
            asset_id = stable_id(path)
            result.append(Model(path, folder, asset_id, family, tags, max(0.05, round(radius, 2)), -minimum[1], slope, blocks, palette_for(asset_id, family)))
    result.extend(hill_models())
    return result


def hill_models() -> list[Model]:
    """The 21 freestanding Hill_WxDxH blocks, catalogued as heightfield
    stamps rather than surface props (ADR-007). footprint_radius uses the
    circumscribed-circle half-diagonal of the *measured* mesh bounds (safe
    under any rotation); nominal_size and collision_size use the exact
    filename dimensions, matching ProceduralTerrainProvider.stamp_hill.
    """
    result: list[Model] = []
    for path in sorted((ASSET_ROOT / "hills").glob("*.gltf")):
        match = HILL_BLOCK_RE.match(path.name)
        if not match:
            continue
        width, depth, height = (float(value) for value in match.groups())
        minimum, maximum = gltf_bounds(path)
        half_diagonal = math.hypot(max(abs(minimum[0]), abs(maximum[0])), max(abs(minimum[2]), abs(maximum[2])))
        asset_id = stable_id(path)
        result.append(Model(
            path, "hills", asset_id, "hill", ["temperate", "forest", "hill"],
            round(half_diagonal, 2), HILL_DISPLAY_EPSILON_M, 90, True, palette_for(asset_id, "hill"),
            asset_type="terrain_feature", collision_shape="box", collision_size=(width, height, depth), nominal_size=(width, depth),
        ))
    return result


def tres(model: Model) -> str:
    tags = ", ".join('"%s"' % tag for tag in model.tags)
    collision_size_line = "\ncollision_size = Vector3(%s, %s, %s)" % model.collision_size if model.collision_size is not None else ""
    return '''[gd_resource type="Resource" script_class="AssetDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="res://world/asset_definition.gd" id="1"]

[resource]
script = ExtResource("1")
id = &"%s"
scene_path = "%s"
asset_type = &"%s"
tags = PackedStringArray(%s)
footprint_radius = %s
placement_max_slope_deg = %s.0
blocks_navigation = %s
collision_shape = "%s"%s
display_offset = Vector3(0, %s, 0)
palette_index = %s
''' % (model.id, model.scene_path, model.asset_type, tags, model.radius, model.slope, str(model.blocks).lower(), model.collision_shape, collision_size_line, model.offset_y, model.palette_index)


def replace_generated_block(text: str, paths: list[str]) -> str:
    begin, end = "\t# generated:forest:begin", "\t# generated:forest:end"
    generated = [begin] + ['\t"res://data/assets/forest/%s.tres",' % path for path in paths] + [end]
    pattern = re.escape(begin) + r".*?" + re.escape(end)
    if re.search(pattern, text, re.S):
        return re.sub(pattern, "\n".join(generated), text, flags=re.S)
    needle = "]\n\nstatic var _definitions_by_id"
    return text.replace(needle, "\n".join(generated) + "\n]\n\nstatic var _definitions_by_id", 1)


def asset_js(all_models: list[Model]) -> str:
    legacy = [
        ["floor_dirt_large", "terrain_tile", ["dirt", "dungeon", "ground"], 1.4, "Floor dirt large", "terrain"],
        ["floor_tile_small", "terrain_tile", ["dungeon", "ground", "stone"], 1.4, "Floor tile small", "terrain"],
        ["bridge_wood_01", "bridge", ["bridge", "wood"], 2, "Wood bridge", "bridge"],
        ["wall_dungeon_01", "structure", ["dungeon", "wall"], 1, "Dungeon wall", "structure"], ["wall_run_dungeon_01", "structure", ["dungeon", "wall"], 10, "Dungeon wall run", "structure"], ["wall_doorway_dungeon_01", "structure", ["doorway", "dungeon", "wall"], 1, "Dungeon doorway", "structure"], ["barrier_dungeon_01", "structure", ["barrier", "cover", "dungeon"], 1, "Dungeon barrier", "structure"], ["chest_wood_01", "prop", ["chest", "dungeon", "interactable", "wood"], .9, "Wood chest", "prop"], ["barrel_large_01", "prop", ["barrel", "dungeon", "wood"], .55, "Large barrel", "prop"], ["crates_stacked_01", "prop", ["crate", "cover", "dungeon", "wood"], 1, "Stacked crates", "prop"], ["torch_lit_01", "prop", ["dungeon", "light", "torch", "wall"], .15, "Lit torch", "prop"], ["tree_oak_01", "vegetation", ["temperate", "tree"], 2.1, "Oak tree 1", "tree"], ["tree_oak_02", "vegetation", ["temperate", "tree"], 1.8, "Oak tree 2", "tree"], ["rock_large_01", "vegetation", ["cover", "rock", "temperate"], 1.5, "Large rock", "rock"], ["bush_01", "vegetation", ["bush", "temperate"], .7, "Bush", "bush"], ["grass_01", "vegetation", ["grass", "temperate"], .25, "Grass", "grass"], ["character_knight_01", "character", ["hero", "humanoid", "knight"], .45, "Knight", "character"], ["character_barbarian_01", "character", ["humanoid", "barbarian", "hostile"], .5, "Barbarian", "character"], ["character_druid_01", "character", ["humanoid", "druid", "hostile"], .45, "Druid", "character"], ["character_engineer_01", "character", ["humanoid", "engineer", "hostile"], .45, "Engineer", "character"], ["character_mage_01", "character", ["humanoid", "mage", "hostile"], .45, "Mage", "character"], ["character_ranger_01", "character", ["humanoid", "ranger", "hostile"], .45, "Ranger", "character"], ["character_rogue_01", "character", ["humanoid", "rogue", "hostile"], .45, "Rogue", "character"], ["healing_potion_pickup_01", "pickup", ["potion", "healing", "pickup", "interactable"], .55, "Healing potion", "pickup"],
    ]
    entries = legacy + [[m.id, m.asset_type, m.tags, m.radius, m.label, m.family, list(m.nominal_size) if m.nominal_size else None] for m in all_models if m.file.name not in LEGACY]
    return "// Generated by scripts/generate_forest_catalog.py; do not edit.\nexport const ASSETS=" + json.dumps(entries, separators=(",", ",")) + ".map(([id,asset_type,tags,footprint_radius,label,family,size])=>({id,asset_type,tags,footprint_radius,label,family,size}));\nexport const hasAsset=id=>ASSETS.some(a=>a.id===id);\nexport const byType=t=>ASSETS.filter(a=>a.asset_type===t);\nexport const firstId=t=>(byType(t)[0]||ASSETS[0]).id;\nexport const footprint=id=>ASSETS.find(a=>a.id===id)?.footprint_radius||0;\nexport const sizeOf=id=>ASSETS.find(a=>a.id===id)?.size||null;\nexport const families=t=>[...new Set(byType(t).map(a=>a.family))].sort();\nexport const search=(t,q='')=>{const needle=q.trim().toLowerCase();return byType(t).filter(a=>!needle||[a.id,a.label,...a.tags,a.family].join(' ').toLowerCase().includes(needle));};\n"


def write_or_check(path: Path, content: str, check: bool) -> bool:
    current = path.read_text() if path.exists() else ""
    if current == content:
        return False
    if check:
        print("Out of date: %s" % path.relative_to(ROOT))
        return True
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    return False


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    discovered = models()
    if len(discovered) != 158:
        raise SystemExit("Expected 158 catalogued models (137 vegetation + 21 hill blocks), found %d" % len(discovered))
    generated = [m for m in discovered if m.file.name not in LEGACY]
    drift = False
    expected = {m.id + ".tres": tres(m) for m in generated}
    for filename, content in expected.items():
        drift |= write_or_check(FOREST_DIR / filename, content, args.check)
    if FOREST_DIR.exists():
        for path in FOREST_DIR.glob("*.tres"):
            if path.name not in expected:
                if args.check:
                    print("Unexpected generated file: %s" % path.relative_to(ROOT)); drift = True
                else:
                    path.unlink()
    paths = [m.id for m in generated]
    drift |= write_or_check(CATALOG_PATH, replace_generated_block(CATALOG_PATH.read_text(), paths), args.check)
    drift |= write_or_check(JS_PATH, asset_js(discovered), args.check)
    rows = list(csv.reader(CSV_PATH.open(newline="")))
    header, existing = rows[0], rows[1:]
    generated_ids = {m.id for m in generated}
    legacy_by_id = {id: name for name, id in LEGACY.items()}
    for row in existing:
        if row and row[0] in legacy_by_id:
            model = next(item for item in discovered if item.file.name == legacy_by_id[row[0]])
            row[5] = "godot/assets/kaykit_forest/%s/%s" % (model.folder, model.file.name)
            # glTF texture URI rewritten on import; shared atlas repainted -- see NOTICE.md.
            row[6] = "yes"
    existing = [row for row in existing if not row or row[0] not in generated_ids]
    for m in generated:
        existing.append([m.id, SOURCE, "Kay Lousberg", "CC0 1.0", "2026-09-06", "godot/assets/kaykit_forest/%s/%s" % (m.folder, m.file.name), "yes"])
    output = "\n".join(",".join('"%s"' % cell.replace('"', '""') if any(c in cell for c in ',"\n') else cell for cell in row) for row in [header, *existing]) + "\n"
    drift |= write_or_check(CSV_PATH, output, args.check)
    if args.check and drift:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
