# B3 hand-authored reference map

`forest_encounter_reference.json` is the small, deterministic MapSpec v1
fixture for future Map Compiler tests. It demonstrates map metadata, terrain,
a region, explicit vegetation, a structure, and a player spawn using B1 asset
IDs only.

Terrain's optional `surface` value selects its repeated visual material. The
available values are `grass` (the default), `sand`, `dirt`, and `stone`; for
example: `"terrain": { "profile": "flat", "surface": "sand" }`.

The optional `player.character_asset` selects the player model from the Godot
asset catalog. The reference map uses the currently available
`character_knight_01` asset.

This phase establishes an authoring contract fixture only. Compilation,
runtime instantiation, terrain generation, navigation generation, procedural
vegetation, and AI authoring are deliberately deferred to later B phases.

## Dialogue coin costs

A dialog option may declare a positive integer `coin_cost`. Choosing it
transfers that many coins from the player to the speaking actor before the
option's normal outcome runs. Coin-cost options cannot include a `check` in
the current contract; author a separate payment or skill-check option instead.
