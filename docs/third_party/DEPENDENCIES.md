# Dependencies

## A0 / A1

| Name | Version / pin | License | Why used | Update strategy |
| --- | --- | --- | --- | --- |
| Godot Engine | 4.6.x | MIT | Runtime and GDScript toolchain | Upgrade deliberately after headless checks pass |

No third-party source code, plugins, assets, or test framework have been
copied or installed in this milestone. The tests use a small local headless
runner to avoid adding a framework before the Reuse Spike. Tactical Slash was
inspected as a MIT-licensed camera reference; the outcome is documented in
`reuse-audit.md` and does not add it as a dependency.

## A10

| Name | Version / pin | License | Why used | Update strategy |
| --- | --- | --- | --- | --- |
| KayKit Forest Nature Pack | 1.0 FREE | CC0 1.0 | Minimal-art scaffold (`AssetCatalog`) needs real meshes for a couple of arena obstacle props | Re-download and re-audit in `assets.csv` if a newer pack version replaces these files |
| KayKit Dungeon Pack | 1.1 FREE | CC0 1.0 | Modular wall run (`wall_generic`) and the interactable chest (`chest_wood_01`) | Same as above |
| KayKit Adventurers | 2.0 FREE | CC0 1.0 | Player character mesh (`character_hero_placeholder`); static bind-pose swap only, no animation wiring yet | Same as above |

Only specific files were copied out of each pack, into their own
`godot/assets/kaykit_*/` directory, from the full packs downloaded to a local
machine path outside the repo. See `assets.csv` for the per-asset audit row
and `NOTICE.md` for attribution.
