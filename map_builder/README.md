# MapSpec Map Builder

A dependency-free browser editor for MapSpec v1 maps. It exports the exact JSON contract consumed by the Python validator and Godot compiler.

Run from the repository root so the builder can preview the bundled Godot
music assets:

```sh
python3 scripts/serve_map_builder.py
```

That server sends `Cache-Control: no-store`, so edits to the builder's ES modules
take effect on a plain reload. Plain `python3 -m http.server 8000` also works, but
browsers cache its modules heuristically and may validate against a stale schema
copy until a hard reload.

Open `http://localhost:8000/map_builder/`. The editor is organized around:

- a section navigator for setup, environment, layout, gameplay, and narrative;
- the central map canvas and its active drawing controls;
- a contextual property inspector for the selected item or placement tool.

Use **Place** for repeated point placement; the tool remains active until
**Done**, **Select**, or `Escape`. Use **Draw** for regions, roads, rivers, and
walls, then finish with the canvas control, `Enter`, or a double-click on the
last point. The `+` action creates a point entity at the map center for precise
numeric editing. Dialogs are non-spatial and are added directly to their
inspector.

**New Map** opens a compact setup form for the ID, preset, bounds, and seed.
The filename and unsaved state appear beside the title, and the editor warns
before replacing unsaved work.

Asset pickers are searchable and grouped by family. Their catalog is generated:
run `python3 scripts/generate_forest_catalog.py` after changing imported forest
glTF assets rather than editing `js/asset-catalog.js` by hand.

**Export JSON** always downloads a copy—it never writes to the repository.

In Chrome/Edge (browsers with the File System Access API), Import/Save work like a native editor instead:
- **Import JSON** opens a file picker; the picked file is remembered for the rest of the session.
- **Save** writes back to that same file in place (e.g. straight into `world_authoring/maps/`). The first time you save a map that wasn't imported, it behaves like Save As and asks where to create the file.
- **Save As** always prompts for a new file location and switches subsequent Saves to it.

Browsers without the API (e.g. Firefox and Safari) cannot overwrite an imported
file in place. **Save** remains available and downloads an updated JSON copy;
Import uses the browser file input and **Save As** remains hidden.

The validation summary below the canvas combines schema and collision checks.
Its issues are clickable and open the affected setup panel or entity. Save,
Save As, and Export all block on the same error set.

Before adding an exported map to `world_authoring/maps/`, run the canonical validation check from the repository root:

```sh
python3 -m world_authoring.validation.validate map-spec path/to/exported-map.json
```

Run the dependency-free Map Builder module tests with:

```sh
npm test --prefix map_builder
```

The importer validates before replacing the current map. Validation includes MapSpec schema rules, catalog lookups, and cross-reference checks; out-of-bounds positions are warnings rather than export-blocking errors.

## Music cues

Map authors select ambient and battle music from the curated catalog. The
builder shows display names, mood tags, and preview controls, while exported
MapSpec files retain only stable cue IDs. Godot's `MusicDirector` resolves
those IDs through its runtime allowlist.
