# ADR-007: KayKit hill blocks are authored as heightfield stamps

## Status

Accepted.

## Context

`ProceduralTerrainProvider` owns one cached heightfield (`_grid`).
`CompiledTerrain` builds both the visual mesh and the collision body from
`terrain.export_navigation_geometry()`, specifically so raycasts and
character grounding cannot silently disagree with terrain queries.
`MapNavigationCompiler` bakes the navmesh from the same source, and
`VegetationGenerator` places props via `terrain.height_at()` /
`terrain.slope_at()`. One heightfield is authoritative for mesh, collision,
navmesh, and every gameplay query.

`docs/plans/forest-nature-pack-import.md` (finding #6) imported the 61 KayKit
hill/cliff models but deliberately left them uncatalogued: a hill placed as an
ordinary scene prop is invisible to all of the above, so actors would walk
through it, vegetation would spawn inside it, and pathing would ignore it.

This ADR covers only the **21 freestanding `Hill_WxDxH` blocks**. The
40-piece `Hill_Cliff_*`/`Hill_Top_*` modular tile kit is a grid-snapped ramp
system that needs its own authoring UI and is deferred.

## Decision

Hills are authored as heightfield stamps, not props.

MapSpec gains a `hills` array (`{id, asset, position, rotation_deg}`, the same
shape as `assetPlacement`). `MapCompiler._compile_hills()` runs immediately
after `terrain.generate()` succeeds and before paths, walls, other
placements, or vegetation are compiled. For each hill it samples
`base_elevation := terrain.height_at(position)` from the *pre-stamp* terrain,
then calls `ProceduralTerrainProvider.stamp_hill(center, rotation, size,
base_elevation)`, which reshapes `_grid` into a flat-topped rounded box: the
top is `base_elevation + height` inside the model's nominal `width × depth`
footprint, blending back down to `base_elevation` over a 0.25 m skirt that
matches the model's own measured sloped skirt (every `Hill_WxDxH` model's X/Z
mesh bounds exceed its nominal size by ~0.25 m per side; height is exact).
Multiple stamps combine with `max()`, so they are commutative and never carve
terrain down.

Because the stamp runs first, every existing terrain consumer gets hills for
free with no changes of its own: `CompiledTerrain`'s mesh and collision, the
baked `NavigationMesh`, `MapNavigationCompiler`'s discrete reachability grid,
and `VegetationGenerator`'s slope checks all already read `_grid` through the
provider's public API.

The KayKit mesh is still instantiated on top of the stamp — a stamp-only
hill would render as a low-poly, flat-shaded procedural-terrain-colored mesa
(the terrain mesh is 2 m resolution, `CompiledTerrain`'s shader has no rock
texture), losing the pack's stylised look entirely. Rendering the actual mesh
risks z-fighting where its flat top is coincident with the terrain's own
now-raised flat top. This is mitigated the same way `_compile_bridges`
already lifts bridge meshes above terrain (`height_at(...) + 0.12`): each
hill's `AssetDefinition.display_offset` carries a small +0.03 m epsilon,
guaranteeing the mesh always draws above the terrain surface. Verified
against an actual render (`godot --rendering-driver opengl3`, no
`--headless`, since headless mode here has no real rasterizer): the flat top
shows no z-fighting. The trade-off is a visible collar where the terrain's
2 m-resolution, box-shaped riser pokes out past the mesh's smaller, rounded
organic base — more a blocky pedestal peeking around the model than a thin
line, since the stamp's rounded-box silhouette does not pixel-match the
mesh's own skirt geometry. Acceptable for this decision (no floating, no
clipping, no z-fighting), but a closer per-model skirt profile or a matching
collar material would be a reasonable follow-up if it reads as too blocky in
practice.

Hills do not get a `MapRuntimeBlocker` — the terrain's own collision mesh
(built from the same stamped `_grid`) already blocks them physically, so a
separate blocker would only duplicate collision. They do keep
`blocks_navigation = true` with box `collision_size = (width, height,
depth)`, which plugs into `MapCompiler._navigation_blockers()` for the
discrete reachability grid as defense-in-depth. The primary exclusion
mechanism is the baked navmesh's existing slope filter
(`MapNavigationCompiler._triangle_exceeds_slope`): a 0.25 m-wide, ≥2 m-tall
transition sampled on the navmesh's 2 m stride produces a slope of at least
~41° at every hill edge, comfortably over the default 35° `hard_slope_deg`
limit for every cataloged height (2/4/8 m checked as the worst case). A
hill's flat top is therefore walkable but disconnected from the surrounding
terrain — an unclimbable obstacle, matching the "freestanding block" naming
that distinguishes these models from the ramped `Hill_Cliff_*`/`Hill_Top_*`
kit.

`AssetDefinition` gains no new fields: hills reuse `collision_size` (already
present for wall assets) to carry nominal `(width, height, depth)`, and
`collision_shape = "box"`. `footprint_radius` (used for MapSpec bounds/overlap
checks and the discrete reachability grid) is the circumscribed-circle
half-diagonal of the *measured* mesh bounds, not the generic single-axis-max
formula the other vegetation families use — that formula only covers a
rectangle's rotated corners for square footprints, and hills are frequently
rectangular.

## Consequences

- Hand-placed props, walls, and other hills cannot overlap a hill's
  reserved footprint (`OVERLAP` error), and generated vegetation cannot land
  inside it — both reuse the existing radius-reservation mechanism, which
  conservatively excludes the whole hill footprint (including its flat top)
  rather than only the steep skirt. Hilltop vegetation decoration is
  therefore not possible today; that would need a slope-only exclusion and is
  a plausible follow-up, not required by this work.
- `scripts/generate_forest_catalog.py` is the only place hill catalog entries
  are produced (id, footprint, collision size, palette); `godot/data/assets/
  forest/*.tres`, `AssetCatalog.DEFINITION_PATHS`, `map_builder/js/
  asset-catalog.js`, and `docs/third_party/assets.csv` are generated from it
  and must never be hand-edited.
- The 40-piece `Hill_Cliff_*`/`Hill_Top_*` modular kit remains imported but
  uncatalogued. Authoring it needs grid-snapping placement UI so adjacent
  tiles align, which this stamp mechanism does not provide.
