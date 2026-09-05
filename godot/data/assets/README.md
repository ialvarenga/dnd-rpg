# Asset catalog

Each `.tres` file is one compiler-facing asset definition. `id` is the stable
value that future MapSpecs may contain; `scene_path` is intentionally confined
to these data files and must never appear in a MapSpec.

The compiler should use `AssetCatalog.get_definition()`, `find_matching()`,
and `can_place()` rather than loading scenes itself. Definitions state the
asset's semantic type, tags, circular placement footprint, maximum terrain
slope, and whether it blocks navigation. Presentation offsets are metadata for
the existing hand-authored arena and keep its visual adapter free of asset
specific exceptions.

HUD textures and icon mappings are deliberately outside this compiler-facing
catalog. They live under `assets/kenney_ui/`, `assets/game_icons/`, and
`data/ui/hud_icons.tres`; their sources and licenses are recorded in
`docs/third_party/NOTICE.md`. `IconSet` is view-only and must not be used to
choose gameplay behavior.
