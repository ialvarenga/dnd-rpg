# Third-party notices

No third-party code is included as of A1. Tactical Slash was inspected as a
camera reference but no source was copied or adapted; see `reuse-audit.md`
for the immutable source and decision.

When code is reused, add its repository URL, immutable commit or tag, license,
files/concepts used, local modifications, and required attribution here and in
`reuse-audit.md`.

## Assets

### Forge & Fantasy Weapon SFX Pack (C6)

- Author/source: Case Portman Audio, https://caseportman.itch.io/forge-fantasy-weapon-sfx
- License: Forge & Fantasy Royalty-Free Sound Effects License. The pack permits
  use, modification, and inclusion in commercial game projects, but prohibits
  standalone sound-effect redistribution.
- Files used: `Sword_Swing_Long_01.ogg`, `Sword_Swing_Long_03.ogg`, and
  `Sword_Swing_Long_05.ogg`, copied unmodified into
  `godot/assets/sfx/combat/` for the basic-attack presentation.

### Hurt Sound Effects (C6)

- Author/source: EZduzziteh, https://opengameart.org/content/hurt-sound-effects
- License: CC0 1.0 (Creative Commons Zero / public domain).
- Files used: `hurt_01.mp3` and `hurt_05.mp3`, copied unmodified into
  `godot/assets/sfx/characters/` for damage-taken presentation.

### KayKit Forest Nature Pack 1.0 (A10, B1)

- Author: Kay Lousberg, www.kaylousberg.com
- License: CC0 1.0 (Creative Commons Zero / public domain) -- attribution not
  required, credited here anyway per the pack's own request.
- All 198 Color1 models and `forest_texture.png` are copied into
  `godot/assets/kaykit_forest/`, with two project modifications noted below. Of
  these, 137 trees, bushes, grass, and rocks are catalogued and individually
  audited in `assets.csv`; the 61 Hill/Cliff models are imported but
  deliberately not yet authorable terrain.
- Modification 1: each model's glTF image URI is rewritten from
  `forest_texture.png` to `../forest_texture.png` by
  `scripts/import_forest_pack.py`, so every family folder shares the one atlas.
  Geometry, UVs, and material parameters are untouched.
- Modification 2: `forest_texture.png` columns 2-8 are repainted by
  `scripts/generate_forest_palettes.py`. The pack ships those columns blank and
  labelled "space reserved for ... extra tier colors -- or you can add your own
  colors if you'd like"; this project fills them with recoloured copies of the
  pack's own column 1, which is left untouched.
- `materials/forest_palette_*.tres` are project-authored UV offsets over the
  pack atlas, not copied pack files.

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
- Files used: `Rig_Medium_MovementBasic.glb`, `Rig_Medium_CombatMelee.glb`,
  `Rig_Medium_General.glb`, and `Rig_Medium_MovementAdvanced.glb`, copied
  unmodified into `godot/assets/kaykit_character_animations/`. On the
  compatible `Rig_Medium` skeleton used by the knight/raider: `Walking_A`
  plays while a character follows a resolved movement path;
  `Melee_1H_Attack_Slice_Horizontal` plays after a resolved basic attack;
  `Idle_A`/`Hit_A`/`Death_A` narrate idle/damage-taken/death; `Dodge_Backward`
  narrates a missed incoming attack; `Melee_Blocking` is the weapon-ready
  pose entered when combat starts.
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
- Weapon props `sword_1handed.gltf`/`.bin` (+ `knight_texture.png`) and
  `dagger.gltf`/`.bin` (+ `rogue_texture.png`), from the FREE archive's
  `Assets/gltf/`, copied unmodified into
  `godot/assets/kaykit_adventurers_weapons/`. CharacterView attaches these to
  the `handslot.r` bone of the equipped wielder (knight/longsword,
  raider/dagger) via a `BoneAttachment3D`; the dagger is visual only and adds
  no combat modifiers. Not a placeable catalog asset, so its audit record
  lives here rather than in `assets.csv`.
- See `assets.csv` for the full per-asset audit trail of the character models.
