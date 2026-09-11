# Dependencies

## Gameplay rules

| Name | Version / pin | License | Why used | Update strategy |
| --- | --- | --- | --- | --- |
| System Reference Document | 5.2.1 | CC BY 4.0 | Openly licensed fifth-edition-compatible combat, action, condition, and equipment rules | Keep this rules pack pinned to 5.2.1; audit and version any later SRD migration explicitly in `docs/rules/open-content-ledger.csv` |

## A0 / A1

| Name | Version / pin | License | Why used | Update strategy |
| --- | --- | --- | --- | --- |
| Godot Engine | 4.6.x | MIT | Runtime and GDScript toolchain | Upgrade deliberately after headless checks pass |

No third-party source code, plugins, assets, or test framework have been
copied or installed in this milestone. The tests use a small local headless
runner to avoid adding a framework before the Reuse Spike. Tactical Slash was
inspected as a MIT-licensed camera reference; the outcome is documented in
`reuse-audit.md` and does not add it as a dependency.

## B2

| Name | Version / pin | License | Why used | Update strategy |
| --- | --- | --- | --- | --- |
| jsonschema | >=4.23,<5 | MIT | Validate canonical Draft 2020-12 MapSpec and MapPatch contracts in Python authoring tools | Upgrade deliberately after validating the schema fixture suite |

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

## C5

| Name | Version / pin | License | Why used | Update strategy |
| --- | --- | --- | --- | --- |
| Kenney UI Pack - Adventure | 1.0 (2024) | CC0 1.0 | One nine-sliced brown panel texture for the actor HUD panel | Re-download from the source archive; keep only HUD textures assigned in scenes |
| game-icons.net | `game-icons/icons` `82d948812bfe3f269ef8f731dcdb07b08160edc4` | CC BY 3.0 | Sixteen view-side SVG icons for HUD ability, item, end-turn, character, and settings presentation | Re-audit each icon's artist, URL, and license before adding or replacing an SVG |

The C5 UI assets are presentation-only. `godot/data/ui/hud_icons.tres` maps
stable view ids to textures; it is not gameplay content and is never read by
the simulation or a controller decision branch. See `NOTICE.md` for the exact
files, authors, sources, and attribution text.
