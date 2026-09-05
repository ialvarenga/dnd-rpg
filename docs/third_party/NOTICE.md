# Third-party notices

No third-party code is included as of A1. Tactical Slash was inspected as a
camera reference but no source was copied or adapted; see `reuse-audit.md`
for the immutable source and decision.

When code is reused, add its repository URL, immutable commit or tag, license,
files/concepts used, local modifications, and required attribution here and in
`reuse-audit.md`.

## Assets

### KayKit Forest Nature Pack 1.0 (A10)

- Author: Kay Lousberg, www.kaylousberg.com
- License: CC0 1.0 (Creative Commons Zero / public domain) -- attribution not
  required, credited here anyway per the pack's own request.
- Files used: `Tree_1_A_Color1.gltf`/`.bin`, `Tree_3_A_Color1.gltf`/`.bin`,
  `Rock_3_R_Color1.gltf`/`.bin`, `forest_texture.png`, copied unmodified into
  `godot/assets/kaykit_forest/`.
- See `assets.csv` for the full per-asset audit trail.

### KayKit Dungeon Pack 1.1 (A10)

- Author: Kay Lousberg, www.kaylousberg.com
- License: CC0 1.0 (Creative Commons Zero / public domain).
- Files used: `wall.gltf`/`.bin`, `chest.gltf`/`.bin`, `dungeon_texture.png`,
  copied unmodified into `godot/assets/kaykit_dungeon/`.
  `wall_run_5.tscn` is a local composite scene (5 instances of `wall.gltf`
  tiled to span the arena's 20m wall) authored for this project, not a file
  from the pack itself.
- See `assets.csv` for the full per-asset audit trail.

### KayKit Adventurers 2.0 (A10)

- Author: Kay Lousberg, www.kaylousberg.com
- License: CC0 1.0 (Creative Commons Zero / public domain).
- Files used: `Knight.glb` (self-contained: mesh, skeleton, and texture all
  embedded), copied unmodified into `godot/assets/kaykit_adventurers/`. No
  animation clips from the pack's separate `Animations/` library are wired up
  yet -- the arena has no animation-playback layer at all currently, so this
  is a static bind-pose swap only.
- See `assets.csv` for the full per-asset audit trail.
