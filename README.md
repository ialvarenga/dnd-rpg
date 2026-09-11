# Deterministic Tactical RPG

The current milestone includes completed Marco E combat depth: a headless,
deterministic simulation with
authoritative turns, encounter-scoped initiative and outcomes, objectives,
action economy, melee and ranged attacks, saving throws, timed conditions,
cover, high ground, weapon masteries, forced movement and falls, weighted
terrain, area effects, stealth/surprise, bounded tactical enemy AI, and
save/load/replay.
Enemy AI evaluates data-driven abilities against state snapshots through the
same pure resolver, then callers apply the chosen result before requesting its
next incremental command. `SaveGame` is the authoritative snapshot (rules- and
content-version stamped); `ReplayLog` is a separate, non-authoritative
command-log artifact used to detect resolver/content regressions. The compiled
MapSpec runtime supports defeat and deterministic in-memory encounter retry,
encounter victory, and objective-driven adventure completion. Open rules
content is tracked in `docs/rules/open-content-ledger.csv`.

The reusable HUD is an explicit `EncounterSession` read-model. It displays
actor resources, turn order, conditions, event narration, and an advisory
action bar; hotbar/end-turn input is emitted to the world controller and then
submitted only through `EncounterSession` and `Resolver`. HUD controls consume
their clicks before terrain picking. `1`–`6` select the first hotbar slots
(all nine actions remain clickable), `Space` ends
a turn, and `Escape` cancels presentation state. See
`docs/ADR/ADR-005-hud-session-boundary.md`,
`docs/ADR/ADR-008-combat-depth-rules.md`, and `docs/third_party/NOTICE.md`.

## Requirements

- Godot 4.6.x (Jolt 3D physics explicitly selected in project settings)

## Run

From the repository root:

```sh
godot --editor --path godot
godot --headless --path godot --script res://tests/test_runner.gd
godot --headless --path godot --editor --quit
python3 scripts/generate_forest_catalog.py --check
```

The test command runs unit, deterministic replay, arena runtime, compiled-map
runtime, outcome/retry, animation, HUD input, and integration-safe headless
checks. It exits non-zero on failure.

## Layout

- `godot/sim/` is the authoritative pure simulation, including initiative,
  encounter lifecycle, turn ownership, action/reaction resources, exact
  polyline movement costs, attack resolution, data-driven ability/condition
  definitions, and the `SaveGame`/`ReplayLog` (de)serialization types.
- `godot/world/` contains engine-backed navigation/LOS adapters, arena input,
  and the `SaveLoadService` file I/O adapter.
- `godot/ai/` contains engine-independent utility AI and bounded port
  decorators; it has no scene, Node, input, physics, or Godot navigation
  dependencies.
- `godot/view/` contains presentation-only camera and event playback.
- `docs/ADR/` records architectural decisions.

See [implementation_plan.md](implementation_plan.md) for the project plan.
