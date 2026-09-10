# Marco B — Map Compiler

**Status: CONCLUÍDO** (B1–B10 e B11, mapa de referência jogável).

> Extraído de `implementation_plan.md` v3.0. Registro histórico detalhado. Para
> o estado atual do projeto veja
> [implementation_plan.md](../../implementation_plan.md).

---

# Fase B1 — Asset Catalog

**Status:** concluída.

Todo objeto reutilizável:

```yaml
id: oak_tree_01
scene: res://assets/vegetation/oak_tree_01.tscn

type: vegetation

tags:
  - tree
  - temperate

footprint:
  radius: 2.1

placement:
  max_slope_deg: 27
```

## Compiler never accepts

```text
raw res:// path
```

from a MapSpec.

Only:

```text
asset ID
```

---

# Fase B2 — Schema source of truth

**Status:** concluída.

Escolha definitiva:

```text
JSON Schema
```

como contrato canônico.

Motivo:

- language-neutral;
- Python can validate;
- docs can be generated;
- structured-output systems can consume it;
- Godot may receive already validated JSON.

Canonical files:

```text
world_authoring/schema/map_spec.schema.json
world_authoring/schema/map_patch.schema.json
```

## Python

Use:

```text
jsonschema
```

and optionally generated Pydantic models.

Pydantic:

```text
generated or aligned from the schema
```

Não manter manualmente duas definições.

## Godot

Map Compiler:

```text
expects validated MapSpec
```

mas ainda executa sanity checks críticos:

- unknown asset;
- impossible enum;
- missing required object.

Falhar alto em desenvolvimento.

---

# Fase B3 — MapSpec v1

**Status:** concluída.

Handwritten first.

Scope:

```text
map
terrain
regions
vegetation
structures
spawn_points
```

## Example

```yaml
version: 1

map:
  id: forest_test
  preset: encounter
  width_m: 64
  height_m: 64
  seed: 918273

terrain:
  profile: rolling_hills

regions:

  - id: north_forest

    polygon:
      - [0, 32]
      - [64, 32]
      - [64, 64]
      - [0, 64]

    vegetation:
      profile: temperate_dense

structures:

  - id: cabin
    asset: medieval_house_01
    position: [34, 24]

spawn_points:

  - id: player_start
    position: [12, 8]
```

---

# Fase B4 — TerrainProvider

**Status:** concluída.

Define interface conceptual:

```text
TerrainProvider
```

Operations:

```text
generate(profile, seed, bounds)
height_at(x,z)
normal_at(x,z)
slope_at(x,z)
export_navigation_geometry()
```

Implementations:

```text
Terrain3DProvider
CustomArrayMeshTerrainProvider
```

O spike decide qual será produção inicialmente.

---

# Fase B5 — Procedural terrain

**Status:** concluída.

Profiles:

- flat;
- rolling_hills;
- valley.

Input:

```text
profile
seed
parameters
```

Output:

```text
heightfield
```

LLM nunca gera heightmap individual.

---

# Fase B6 — VegetationGenerator

**Status:** concluída.

Flow:

```text
region polygon
↓
Poisson / blue-noise sampling
↓
candidate point
↓
slope
↓
clearances
↓
height query
↓
asset selection
↓
MultiMesh
```

## Determinism

Every generator receives derived seed:

```text
map_seed
+
region_id
+
generator_version
```

Use stable hash.

---

# Fase B7 — Structures

**Status:** concluída.

```text
asset catalog
↓
PackedScene
↓
instantiate
↓
position
rotation
```

Before placement:

- footprint test;
- terrain slope;
- bounds;
- collision with reserved areas.

---

# Fase B8 — Rivers + Roads

**Status:** concluída.

Only after basic compiler works.

## Rivers

```text
semantic control points
↓
spline
↓
terrain deformation
↓
water
↓
vegetation exclusion
```

No hydraulic simulation.

## Roads

```text
control points
or
semantic from/to anchors
↓
path planning
↓
spline
↓
terrain flattening
↓
material
```

---

# Fase B9 — Navigation compilation

**Status:** concluída.

Map complete:

```text
terrain
structures
bridges
walls
roads
```

then:

```text
navigation source geometry
↓
bake
↓
regions
```

## Chunk strategy

Only if necessary.

For medium:

```text
256 × 256m
```

candidate:

```text
64 × 64m navigation regions
```

But do not implement chunking blindly if one bake is fast enough.

Measure first.

---

# Fase B10 — Validation

**Status:** concluída.

Single validation pipeline.

## Schema

Examples:

- malformed IDs;
- invalid enum;
- missing field;
- unknown asset.

## Spatial

Examples:

- building outside map;
- overlap;
- invalid river crossing;
- spawn inside structure;
- impossible slope.

## Gameplay

Examples:

```text
spawn → objective reachable?
spawn → encounter reachable?
required door state solvable?
```

## Structured error

```json
{
  "code": "NAV_UNREACHABLE",
  "entity": "village",
  "context": {
    "from": "player_start"
  },
  "message": "Village is unreachable from player_start."
}
```

---

# MARCO B CONCLUÍDO

Manual:

```text
MapSpec
↓
validate
↓
compile
↓
play
```

must work reliably.

---

# Fase B11 — Playable map completion (required before Marco C)

**Status:** concluída para o mapa de referência jogável. A troca opcional
para `MultiMesh` e o benchmark formal de floresta densa 256×256m continuam
adiados; não bloqueiam o mapa atual, que compila, navega e é coberto por
testes de integração.

The compiler's deterministic data path is not sufficient by itself for a
player-facing map. Complete this phase before any AI authoring work so that
MapSpec has proven runtime semantics and generated maps can actually be
played.

## B11.1 — Terrain presentation and collision

- Convert `TerrainProvider.export_navigation_geometry()` / the procedural
  heightfield into a visible terrain mesh with a material.
- Add terrain collision that agrees with `height_at`, `normal_at`, and slope
  queries.
- Verify a character can move, raycast/click, and stand correctly on flat,
  rolling-hills, and valley maps.

## B11.2 — Complete rivers, roads, and bridges

- Render bounded-width road and water ribbons from B8 control points.
- Keep the current deterministic road flattening and add river-bed/water
  presentation without hydraulic simulation.
- Add a catalog-backed bridge entity and explicit MapSpec bridge semantics.
- Permit road/river crossings only when a compatible bridge validates and
  compiles; retain `INVALID_RIVER_CROSSING` otherwise.

## B11.3 — Vegetation rendering and runtime blockers

- Replace per-instance generated vegetation rendering with `MultiMesh` where
  profiling shows it is worthwhile, while preserving catalog placement
  metadata and deterministic placement IDs.
- Add collision/navigation blockers that match each catalog footprint.
- Profile a representative 256×256m dense forest before choosing batching
  thresholds.

## B11.4 — Production navigation bake

- Build Godot navigation source geometry from completed terrain, structures,
  vegetation blockers, roads, bridges, and walls.
- Bake and measure one `NavigationRegion3D` for the maximum 256×256m map.
- Drive runtime path queries through the existing `GodotNavProvider`; ensure
  click-to-move, AI, and compiler reachability observe the same walkable map.
- Introduce 64×64m navigation regions only if the measured single bake fails
  the agreed responsiveness/memory budget; document the measurement either
  way.

## B11.5 — Gameplay MapSpec semantics and validation

- Define canonical schema fields for encounter targets/objectives, doors and
  required states, bridges, and any spawn/actor runtime data needed to play.
- Extend the structured validation pipeline for spawn-to-objective,
  spawn-to-encounter, and required-door-state reachability on the baked map.
- Keep JSON Schema as structural truth and use compiler errors only for
  engine, spatial, and gameplay checks.

## B11.6 — End-to-end playable reference map

- Compile the B3 `forest_encounter_reference.json` without replacing its
  hand-authored source.
- Load the compiled root into a runtime test scene with terrain, catalog
  structures/vegetation, navigation, spawn points, and an objective/encounter.
- Add headless integration coverage for compile → instantiate → navigation →
  click-to-move/AI reachability, plus a short manual playable smoke test.

### Exit criteria

```text
validated MapSpec
↓
compile with no structured errors
↓
load generated map
↓
player can move from spawn to objective/encounter
↓
navigation and collision agree
↓
combat can begin and finish
```

Deferred beyond B11: hydraulic simulation, arbitrary terrain editing, world
streaming, and navigation chunking unless measurement requires the latter.
