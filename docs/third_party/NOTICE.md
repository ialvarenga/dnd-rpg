# Third-party notices

No third-party code is included as of A1. Tactical Slash was inspected as a
camera reference but no source was copied or adapted; see `reuse-audit.md`
for the immutable source and decision.

When code is reused, add its repository URL, immutable commit or tag, license,
files/concepts used, local modifications, and required attribution here and in
`reuse-audit.md`.

## Assets

### KayKit Forest Nature Pack 1.0 (A10, B1)

- Author: Kay Lousberg, www.kaylousberg.com
- License: CC0 1.0 (Creative Commons Zero / public domain) -- attribution not
  required, credited here anyway per the pack's own request.
- Files used: `Tree_1_A_Color1.gltf`/`.bin`, `Tree_3_A_Color1.gltf`/`.bin`,
  `Rock_3_R_Color1.gltf`/`.bin`, `Bush_1_A_Color1.gltf`/`.bin`,
  `Grass_1_A_Color1.gltf`/`.bin`, and `forest_texture.png`, copied unmodified
  into `godot/assets/kaykit_forest/`.
- See `assets.csv` for the full per-asset audit trail.

### KayKit Character Animations 1.1

- Author: Kay Lousberg, www.kaylousberg.com
- License: CC0 1.0 (Creative Commons Zero / public domain).
- Files used: `Rig_Medium_MovementBasic.glb`, copied unmodified into
  `godot/assets/kaykit_character_animations/`. Its `Walking_A` clip plays on
  the compatible `Rig_Medium` skeleton used by the knight while the character
  follows a resolved movement path.
- This shared animation library is not a placeable catalog asset, so its audit
  record lives here rather than in `assets.csv`.

### KayKit Dungeon Pack 1.1 (A10, B1)

- Author: Kay Lousberg, www.kaylousberg.com
- License: CC0 1.0 (Creative Commons Zero / public domain).
- Files used: `wall.gltf`/`.bin`, `wall_doorway.gltf`/`.bin`,
  `floor_dirt_large.gltf`/`.bin`, `floor_tile_small.gltf`/`.bin`,
  `barrier.gltf`/`.bin`, `chest.gltf`/`.bin`, `barrel_large.gltf`/`.bin`,
  `crates_stacked.gltf`/`.bin`, `torch_lit.gltf`/`.bin`, and
  `dungeon_texture.png`, copied unmodified into `godot/assets/kaykit_dungeon/`.
  `wall_run_5.tscn` is a local composite scene (5 instances of `wall.gltf`
  tiled to span the arena's 20m wall) authored for this project, not a file
  from the pack itself.
- See `assets.csv` for the full per-asset audit trail.

### KayKit Adventurers 2.0 (A10, B1)

- Author: Kay Lousberg, www.kaylousberg.com
- License: CC0 1.0 (Creative Commons Zero / public domain).
- Files used: `Knight.glb` (self-contained: mesh, skeleton, and texture all
  embedded), copied unmodified into `godot/assets/kaykit_adventurers/`. The
  compatible movement clips are documented separately above.
- See `assets.csv` for the full per-asset audit trail.
