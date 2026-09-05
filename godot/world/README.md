# World contracts

`TerrainProvider` is the Godot boundary between MapSpec v1 terrain intent and
future terrain implementations. Its `generate(profile, seed, bounds)` input
accepts the B2 profiles (`flat`, `rolling_hills`, `valley`), a non-negative
seed through `2147483647`, and width/height bounds through `256` meters.
Query coordinates are absolute east (`x`) and north (`z`) meters from the
southwest corner.

This B4 phase defines only the contract. `FlatTerrainProvider` under
`tests/fakes` is deterministic test support: valid queries return height `0`,
`Vector3.UP`, and slope `0`; its navigation geometry is empty. B5 will
implement procedural profiles, and B9 will own navigation generation/baking.
`ProceduralTerrainProvider` is the B5 implementation. It deterministically
evaluates `flat`, `rolling_hills`, and `valley` in absolute meters and exports
4m terrain triangles for a future navigation consumer.

`MapCompiler.compile(spec)` is the B7-B10 entry point for an already
schema-validated MapSpec. It produces `MapCompilationResult`: a compiled root,
terrain, catalog-backed placements, a single `NavigationRegion3D`, and stable
`MapValidationError` values (`code`, `entity_id`, `context`, `message`). It
uses `VegetationGenerator` derived seeds based on a stable integer hash of
`map_seed|region_id|generator_version` and only catalog IDs.

Rivers and roads accept B8 `control_points` and reserve their widths against
vegetation/structures. B11 renders them as bounded material ribbons and keeps
road flattening in the procedural heightfield. River crossings require a
catalog-backed bridge with matching `river_id` and `road_id` semantics.

`CompiledTerrain` makes its visible mesh and `StaticBody3D` collision from
the exact `TerrainProvider.export_navigation_geometry()` triangles. The single
`NavigationRegion3D` uses those same triangles; catalog placements receive
matching runtime collision blockers and `blocks_navigation` assets feed the
deterministic reachability grid. `compiled_forest_map.tscn` is the manual B11
compile-and-play smoke scene. Navigation remains one 256m-or-smaller region;
64m chunks remain deferred until profiling proves a single bake misses budget.
