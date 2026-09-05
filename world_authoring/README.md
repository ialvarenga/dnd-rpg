# World authoring contracts

`schema/map_spec.schema.json` and `schema/map_patch.schema.json` are the
canonical, language-neutral source of truth for map authoring. Authoring and
Python tooling must validate emitted JSON with:

```bash
python -m world_authoring.validation.validate map-spec path/to/map.json
python -m world_authoring.validation.validate map-patch path/to/patch.json
```

The command resolves canonical schemas relative to its installed module, so it
does not depend on the current working directory. MapPatch operations are
ordered and are applied only when `base_map_version` matches the map being
edited; validate the resulting MapSpec after every patch.

Godot receives already validated JSON. Starting in B3 it will nevertheless
perform critical runtime sanity checks and fail loudly in development for an
unknown asset, impossible enum, or missing required runtime object.

Schema versions are document-contract versions. A breaking schema change must
introduce a deliberate version/migration decision; never silently reinterpret
an existing version.
