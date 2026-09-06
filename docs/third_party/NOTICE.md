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

### Kenney UI Pack - Adventure 1.0 (C5)

- Author/source: Kenney, https://kenney.nl/assets/ui-pack-adventure
- License: CC0 1.0. Credit is not required; this project credits Kenney anyway.
- File used: `panel_brown_dark.png`, copied unmodified from the pack into
  `godot/assets/kenney_ui/` and nine-sliced only on the HUD actor panel.

### game-icons.net HUD icons (C5)

All icons below are CC BY 3.0 and are copied unmodified from the
[`game-icons/icons`](https://github.com/game-icons/icons) repository. Required
credit: “Icons made by Lorc, available on https://game-icons.net”. The
view-side `IconSet` resource assigns them by stable UI id; no icon is gameplay
authority.

| Local file | Icon | Artist | Source |
| --- | --- | --- | --- |
| `godot/assets/game_icons/broadsword.svg` | Broadsword | Lorc | https://game-icons.net/1x1/lorc/broadsword.html |
| `godot/assets/game_icons/run.svg` | Run | Lorc | https://game-icons.net/1x1/lorc/run.html |
| `godot/assets/game_icons/bordered-shield.svg` | Bordered Shield | Lorc | https://game-icons.net/1x1/lorc/bordered-shield.html |
| `godot/assets/game_icons/return-arrow.svg` | Return Arrow | Lorc | https://game-icons.net/1x1/lorc/return-arrow.html |

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

### KayKit Adventurers 2.0 (A10, B1, combat encounters)

- Author: Kay Lousberg, www.kaylousberg.com
- License: CC0 1.0 (Creative Commons Zero / public domain).
- Files used: `Knight.glb`, plus `Rogue.glb`, `Ranger.glb`, `Barbarian.glb`,
  and `Mage.glb` from the FREE archive; `Druid.glb` and `Engineer.glb` from
  the EXTRA archive. They were copied unmodified into
  `godot/assets/kaykit_adventurers/`; duplicate models shipped in both
  archives were not copied twice. The compatible movement clips are documented
  separately above.
- See `assets.csv` for the full per-asset audit trail.
