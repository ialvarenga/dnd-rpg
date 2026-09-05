# MapSpec Map Builder

A dependency-free browser editor for MapSpec v1 maps. It exports the exact JSON contract consumed by the Python validator and Godot compiler.

Run from this repository:

```sh
cd map_builder
python -m http.server 8000
```

Open `http://localhost:8000/`. Use the toolbar to place point entities or draw regions, roads, and rivers; each entry also has precise numeric/JSON coordinate controls. Export downloads a JSON file only—it never writes to the repository.

Before adding an exported map to `world_authoring/maps/`, run the canonical validation check from the repository root:

```sh
python -m world_authoring.validation.validate map-spec path/to/exported-map.json
```

The importer validates before replacing the current map. Validation includes MapSpec schema rules, catalog lookups, and cross-reference checks; out-of-bounds positions are warnings rather than export-blocking errors.
