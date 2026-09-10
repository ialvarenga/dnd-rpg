# Deferred LLM World Authoring

This work is intentionally scheduled after the gameplay roadmaps in
`implementation_plan.md`. It must consume stable map, combat, party, and
world-state contracts rather than define them.

## E1 — Natural language to MapSpec

Accept a world description plus the JSON Schema, asset catalog, terrain and
vegetation profiles, map bounds, and generator capabilities. Produce a
structured `MapSpec`, never prose parsed at runtime.

## E2 — Validation repair

Run `MapSpec` through the validator, return structured errors to a repair
model, apply a `MapPatch`, and retry at most three times before returning the
errors to the author.

## E3 — Conversational MapPatch

Support `ADD`, `REMOVE`, `MOVE`, `ROTATE`, `RESIZE`, `CHANGE_DENSITY`, and
`CHANGE_PROFILE`. Prefer patches to full regeneration.

## E4 — Versioning

Persist `map_spec_version`, `asset_catalog_version`, `generator_version`, and
seed. Generation must be reproducible for one version set.
