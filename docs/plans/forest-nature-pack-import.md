# Plan — Import KayKit Forest Nature Pack 1.0 (FREE + EXTRA)

Goal: bring every model from both packs into the project, catalogue the
usable ones behind stable asset IDs, and make the MapSpec Map Builder able to
browse and place them.

Source packs:

- `~/Documents/rpg_assets/KayKit_Forest_Nature_Pack_1.0_FREE`
- `~/Documents/rpg_assets/KayKit_Forest_Nature_Pack_1.0_EXTRA`

---

## 0. Findings that shape the plan

These were verified against the actual files, not assumed.

1. **EXTRA is a strict superset of FREE.** `EXTRA/Assets/gltf/Color1/`
   contains all 105 FREE models plus Hills/Cliffs, `Rock_4..6` and
   `Tree_5..7` — 198 models. The only FREE files absent from `Color1/` are the
   four untextured `Grass_*_Mesh` base meshes, which also sit at the EXTRA
   `gltf/` root.
2. **The two packs ship the same texture.** `FREE/Textures/forest_texture.png`
   and `EXTRA/Textures/forest_texture.png` are pixel-identical (only PNG
   encoding metadata differs), and both match the already-imported
   `godot/assets/kaykit_forest/forest_texture.png`. **No texture work needed.**
3. **The 8 color folders are pure UV shifts of one atlas.** Verified on
   `Tree_1_A`, `Rock_1_A`, `Hill_4x4x4`, `Grass_1_A` and `Bush_1_A`:

   ```text
   UV_ColorN.u == UV_Color1.u + 0.125 * (N - 1)      (v unchanged)
   ```

   The 1024x1024 atlas is 8 palette columns of width 0.125. So every palette is
   reproducible from the `Color1` meshes with `StandardMaterial3D.uv1_offset`.
   Copying all 8 folders would cost 1,584 glTF+bin pairs / ~56 MB for zero
   geometric difference. **Decision: copy `Color1` only (~7 MB) and add eight
   palette materials.**
4. **FREE and EXTRA `Color1` geometry is the same.** `Tree_1_A_Color1.bin`
   differs in 8 bytes out of 17,484 (float rounding from a re-export). The five
   already-imported models can be replaced by their EXTRA copies so the whole
   directory has one provenance.
5. **Every model is one node, one mesh, one `forest` material**, and every glTF
   carries `POSITION` `min`/`max`. Footprints, display offsets and box collision
   sizes are therefore **derivable from the files** — no hand-authoring 137
   `.tres` resources by eye.
6. **Hills/Cliffs (61 models) are grid-snapped modular terrain.** This project
   generates terrain procedurally (`ProceduralTerrainProvider` + baked navmesh),
   so hill meshes placed as props would clip and float. **Decision: import and
   Godot-import the files, but do not add catalog definitions yet.**
7. **The catalog is duplicated three ways today**, and a test enforces two of
   them:
   - `godot/data/assets/*.tres` + the hardcoded
     `AssetCatalog.DEFINITION_PATHS` array,
   - `map_builder/js/asset-catalog.js`,
   - `docs/third_party/assets.csv`
     (`test_asset_catalog._test_catalog_and_audit_csv_ids_match` asserts CSV
     and catalog IDs match **in both directions**).

   Hand-maintaining 137 new entries across three files is not viable.
   **Decision: generate all three from the glTF files.**

### Resulting scope

| Family | Models | Catalogued now |
| --- | ---: | --- |
| Tree | 26 | yes |
| Tree_Bare | 6 | yes |
| Bush | 22 | yes |
| Grass | 8 | yes |
| Grass (single-sided) | 8 | yes |
| Rock | 67 | yes |
| Hill / Cliff / Hill_Top | 61 | **no** (files imported only) |
| **Total** | **198** | **137** |

Five of the 137 already exist as hand-tuned IDs (`tree_oak_01`, `tree_oak_02`,
`rock_large_01`, `bush_01`, `grass_01`). Those are kept as-is, so the generator
emits 132 new definitions and the catalog grows from 24 to 156 entries.

---

## 1. Copy and import the meshes

Target layout — subfolders, because ~600 files (glTF + bin + `.import`) in one
flat directory is unmanageable:

```text
godot/assets/kaykit_forest/
  forest_texture.png          (unchanged)
  materials/                  (stage 2)
  trees/    Tree_*_Color1.gltf|.bin        (32)
  bushes/   Bush_*_Color1.gltf|.bin        (22)
  grass/    Grass_*_Color1.gltf|.bin       (16)
  rocks/    Rock_*_Color1.gltf|.bin        (67)
  hills/    Hill_*_Color1.gltf|.bin        (61)
```

Steps:

1. Add `scripts/import_forest_pack.py` (idempotent, takes the pack root as an
   argument) that copies `EXTRA/Assets/gltf/Color1/*.{gltf,bin}` into the
   family subfolders above.
2. Skip the four `Grass_*_Mesh` / `Grass_*_SingleSided_Mesh` base meshes — they
   are untextured authoring meshes with no palette UVs and nothing consumes them.
3. Move the five existing models into their new subfolders (overwriting with the
   EXTRA copies) and update the five `scene_path` values in
   `godot/data/assets/*.tres` plus their `local_path` in `assets.csv`.
4. Do **not** touch `forest_texture.png` — it is already correct for all
   palettes (finding 2).
5. Regenerate `.import` files with
   `godot --headless --path godot --editor --quit`. Commit them; they are part
   of the project.

**Risk:** the CI step `godot --headless --path godot --editor --quit` now
imports 198 scenes with LOD and shadow-mesh generation. Measure it; if it is
slow, set `meshes/generate_lods=false` for the low-poly grass/bush models via a
`.gdignore`-free per-file `.import` tweak in the generator.

**Repo size:** +~7 MB of source assets. `godot/.godot/` is already gitignored.

---

## 2. Palette materials

`godot/assets/kaykit_forest/materials/forest_palette_{1..8}.tres` —
`StandardMaterial3D` with:

```text
albedo_texture  = res://assets/kaykit_forest/forest_texture.png
uv1_offset      = Vector3(0.125 * (n - 1), 0, 0)
metallic        = 0.0
roughness       = 0.6      # matches the glTF's pbrMetallicRoughness
```

Wiring:

- Add `@export_range(1, 8) var palette_index := 1` to `AssetDefinition`.
- `AssetCatalog.instantiate(id)` applies
  `material_override = load(palette material)` on the instantiated
  `MeshInstance3D` when `palette_index != 1`. Single surface per mesh, so
  `material_override` is safe and lossless.
- Palette 1 stays the default, which keeps every existing map rendering exactly
  as it does today.

Per-placement palette selection in MapSpec is **deferred** (see stage 7) —
it is a schema change and is not needed to place the new assets.

---

## 3. Catalog generator (the core of the work)

New `scripts/generate_forest_catalog.py`, the single source of truth for the
three downstream catalogs.

**Input:** `godot/assets/kaykit_forest/{trees,bushes,grass,rocks}/*.gltf`
(hills excluded by an explicit family allowlist).

**Derived per model:**

| Field | Derivation |
| --- | --- |
| `id` | `forest_` + filename lowercased, `_color1` stripped (`Tree_1_A` -> `forest_tree_1_a`, `Rock_3_R` -> `forest_rock_3_r`). Matches the `STABLE_ID` regex in `schema-constants.js`. |
| `scene_path` | `res://assets/kaykit_forest/<family>/<file>.gltf` |
| `asset_type` | `vegetation` for every catalogued family |
| `tags` | `temperate`, `forest`, plus family (`tree`/`bush`/`grass`/`rock`), plus `bare` for `Tree_Bare_*`, `singlesided` for `*_Singlesided_*` |
| `footprint_radius` | `max(abs(x), abs(z))` over the `POSITION` accessor `min`/`max`, rounded to 2 dp, clamped to a `0.05` floor (the catalog test requires `> 0`) |
| `display_offset` | `Vector3(0, -min.y, 0)` when `min.y != 0`, so models sit on the ground plane |
| `placement_max_slope_deg` | per-family table: tree 27, bush 35, grass 45, rock 40 |
| `blocks_navigation` | `true` for tree/rock, `false` for bush/grass |
| `collision_shape` | `cylinder` for all catalogued families |

Sanity check on the derivation: `Tree_1_A` yields radius 1.93 against the
hand-tuned `tree_oak_01` value of 2.1 — the same order, so the derived numbers
are usable without per-model review.

**Outputs (all generated, none hand-edited afterwards):**

1. `godot/data/assets/forest/<id>.tres` — 132 `AssetDefinition` resources.
2. The `DEFINITION_PATHS` array in `godot/world/asset_catalog.gd`, rewritten
   between `# generated:forest:begin` / `# generated:forest:end` markers so the
   hand-written 24 entries stay untouched and the test's
   `definitions.size() == DEFINITION_PATHS.size()` contract still holds.
3. `map_builder/js/asset-catalog.js`, rewritten whole. The entry tuple gains
   the fields the builder needs for a usable picker:

   ```js
   [id, asset_type, tags, footprint_radius, label, family]
   ```

   `label` is a human name (`Tree 1 A`, `Rock 3 R`); `hasAsset`, `byType`,
   `firstId` and `footprint` keep their current signatures.
4. `docs/third_party/assets.csv` — 132 new rows in the existing schema. The
   header must not change; the test asserts it exactly.

**`--check` mode** re-derives everything and exits non-zero on drift. Wire it
into `.github/workflows/ci.yml` next to `check_gdscript_style.py`.

---

## 4. Godot-side wiring and test updates

1. **`test_asset_catalog._test_tagged_type_query_is_deterministic`** currently
   asserts `tree_ids == [&"tree_oak_01", &"tree_oak_02"]`. With 32 trees this
   fails. Replace with: the query returns a stable, sorted, non-empty set that
   contains the legacy IDs and only `vegetation`+`tree` assets — determinism
   without freezing the catalog's contents.
2. **`VegetationGenerator` needs weighting.** It picks uniformly from
   `find_matching(vegetation, ["temperate"])`, which goes from 5 candidates to
   137 — the result would be dominated by rocks (67) and grass (16), with trees
   a minority. Replace the single uniform draw with a per-profile weighted
   family draw, then a uniform draw inside the chosen family:

   ```text
   temperate_dense  -> tree 0.55, bush 0.20, grass 0.20, rock 0.05
   temperate_sparse -> tree 0.30, bush 0.25, grass 0.35, rock 0.10
   ```

   Both draws come from the same seeded `RandomNumberGenerator`, so placement
   stays deterministic. This changes generated output for existing maps, so bump
   `VegetationGenerator.GENERATOR_VERSION` to `"1.1"`.
   `test_map_compiler` asserts determinism and clearance, not golden IDs, so it
   keeps passing.
3. Confirm catalog load cost: 156 `.tres` loaded eagerly in
   `AssetCatalog._ensure_loaded()`. Measure in the headless test run; if it is
   material, make loading lazy per-ID with the manifest kept for the size check.
4. `godot/data/assets/README.md` — document that `data/assets/forest/` is
   generated and must not be hand-edited.

---

## 5. Map Builder support

Today the asset picker in `map_builder/js/panels/list-panel-factory.js` is a
flat `<select>` over `byType(assetType).map(a => a.id)`. At 137 vegetation
entries that is unusable. Changes:

1. **`asset-catalog.js`** — generated in stage 3, now carrying `label` and
   `family`. Add `families(type)` and `search(type, query)` helpers alongside the
   existing exports.
2. **Searchable, grouped picker.** Replace the bare `<select>` with a filter
   text input plus a `<select>` whose options are grouped in `<optgroup>` by
   family, filtered live by the input. Keeping a `<select>` as the value control
   means `bindList`'s `[data-field]` change handler is unchanged. Options show
   `label` and the footprint, e.g. `Tree 1 A — 1.93 m`.
3. **Stable defaults.** `defaultEntity` calls `firstId(assetType)`, whose result
   changes once the catalog is regenerated. Add an explicit `defaultAsset` to
   each entry in `panels/entity-type-configs.js` (`vegetation` ->
   `tree_oak_01`, `structures` -> `wall_dungeon_01`, ...) and have
   `defaultEntity` prefer it, falling back to `firstId`.
4. **To-scale footprints in the SVG preview.** `svg-preview.js` draws every
   point entity as a fixed `r=6` dot. With assets from 0.05 m grass to 3 m trees
   this hides all overlap problems. Use the already-exported `footprint(id)` to
   draw the real footprint circle at `pxPerMeter`, keeping the fixed dot as a
   centre marker. This is the change that makes 137 assets actually authorable.
5. **`index.html` / `styles.css`** — markup and styles for the filter input and
   the footprint circles.
6. **Optional: thumbnails.** A `godot/tools/generate_thumbnails.gd` run headless
   can render each catalogued model to
   `map_builder/thumbnails/<id>.webp`, referenced from the builder the same way
   `music-catalog.js` references `../godot/assets/music/*.ogg` (the dev server
   already serves the repo root). Worth doing, but it is not a blocker — land it
   after the picker works.

---

## 6. Documentation and licensing

1. `docs/third_party/NOTICE.md` — rewrite the KayKit Forest Nature Pack section:
   all 198 `Color1` models plus `forest_texture.png` copied unmodified; 137 are
   catalogued and individually audited in `assets.csv`; the 61 Hill/Cliff models
   are imported but not yet catalogued. Note that the eight palette materials in
   `materials/` are project-authored (a UV offset over the pack's own atlas), not
   pack files.
2. `docs/third_party/assets.csv` — generated rows (stage 3). Do **not** add
   hill rows: the catalog/CSV test requires every row to have a catalog
   definition, and the hills deliberately have none. The NOTICE pack section
   covers their provenance.
3. `map_builder/README.md` — document the searchable picker and the fact that
   `js/asset-catalog.js` is generated.
4. Root `README.md` — mention `scripts/generate_forest_catalog.py` in the run
   commands.

---

## 7. Deferred / follow-up (not in this plan's scope)

- **Per-placement palette in MapSpec.** Adding an optional `palette` integer to
  `assetPlacement` touches `map_spec.schema.json`, `map_builder/js/validation.js`
  and `map_compiler.gd`. Worth doing once palettes prove useful in practice.
- **Hills/Cliffs as authorable terrain.** Needs a decision about how modular
  terrain coexists with the procedural heightmap and the navmesh bake — a
  terrain-authoring phase, not an asset-import task.
- **MultiMesh rendering for grass.** `VegetationGenerator`'s header already
  anticipates this; 16 grass models across dense regions is when it starts to
  matter.

---

## 8. Execution order and verification

```text
1. scripts/import_forest_pack.py  ~/Documents/rpg_assets/KayKit_Forest_Nature_Pack_1.0_EXTRA
2. godot --headless --path godot --editor --quit          # generates .import
3. scripts/generate_forest_catalog.py                     # .tres + gd + js + csv
4. godot --headless --path godot --editor --quit          # imports the new .tres
5. python3 scripts/check_gdscript_style.py
6. godot --headless --path godot --script res://tests/test_runner.gd
7. python -m world_authoring.validation.validate map-spec world_authoring/maps/forest_encounter_reference.json
8. python scripts/serve_map_builder.py                    # browser smoke test
```

Browser smoke test: open `http://localhost:8000/map_builder/`, add a vegetation
entity, filter the picker for "rock", pick `forest_rock_5_c`, confirm the SVG
preview draws its footprint to scale, export the JSON and re-run step 7 on it.

Suggested commit split:

1. `feat: import full KayKit forest nature pack meshes` (stages 1-2)
2. `feat: generate forest asset catalog from gltf sources` (stages 3-4)
3. `feat: add searchable asset picker to the map builder` (stage 5)
4. `docs: record forest nature pack import` (stage 6)
