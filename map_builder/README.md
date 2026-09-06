# MapSpec Map Builder

A dependency-free browser editor for MapSpec v1 maps. It exports the exact JSON contract consumed by the Python validator and Godot compiler.

Run from the repository root so the builder can preview the bundled Godot
music assets:

```sh
python scripts/serve_map_builder.py
```

That server sends `Cache-Control: no-store`, so edits to the builder's ES modules
take effect on a plain reload. Plain `python -m http.server 8000` also works, but
browsers cache its modules heuristically and may validate against a stale schema
copy until a hard reload.

Open `http://localhost:8000/map_builder/`. Use the toolbar to place point entities or draw regions, roads, and rivers; each entry also has precise numeric/JSON coordinate controls.

**Export JSON** always downloads a copy—it never writes to the repository.

In Chrome/Edge (browsers with the File System Access API), Import/Save work like a native editor instead:
- **Import JSON** opens a file picker; the picked file is remembered for the rest of the session.
- **Save** writes back to that same file in place (e.g. straight into `world_authoring/maps/`). The first time you save a map that wasn't imported, it behaves like Save As and asks where to create the file.
- **Save As** always prompts for a new file location and switches subsequent Saves to it.

Browsers without the API (e.g. Firefox, Safari) fall back to the old Import-via-file-input / Export-only flow.

Before adding an exported map to `world_authoring/maps/`, run the canonical validation check from the repository root:

```sh
python -m world_authoring.validation.validate map-spec path/to/exported-map.json
```

The importer validates before replacing the current map. Validation includes MapSpec schema rules, catalog lookups, and cross-reference checks; out-of-bounds positions are warnings rather than export-blocking errors.

## Music cues

Map authors select ambient and battle music from the curated catalog. The
builder shows display names, mood tags, and preview controls, while exported
MapSpec files retain only stable cue IDs. Godot's `MusicDirector` resolves
those IDs through its runtime allowlist.
