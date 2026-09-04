# Godot Project

This directory contains the Godot 4.6 runtime for the tactical RPG. The
current implementation covers the A0 foundation, deterministic A-0 simulation
spike, A1 camera/locomotion prototype, A2 simulation-to-presentation
integration, A3 authoritative movement budgets, A4 authoritative turns, and
A5 actions/combat, A6's bounded utility enemy AI, A7's data-driven
ability/condition definitions, and A8's save/load/replay.
The playable 64×64 m test arena has a tactical camera, navigation region,
obstacle route, hover preview, and click-to-move playback through
Command/Event.

The main architectural rule is that authoritative gameplay state belongs in
`sim/`, independently of scenes and Godot nodes. Engine-facing code will live
in `world/` and presentation code in `view/`.

## Project layout

### `project.godot`

The Godot project configuration and entry point. It selects the test arena as
the main scene, configures the Jolt 3D physics backend, and names the physics
layers used by terrain, characters, interactables, cover, triggers, and
projectiles.

### `scenes/`

Contains hand-authored Godot scenes.

- `test_arena.tscn` is the 64×64 m test environment. It includes the original
  floor, cubes, wall, door placeholder, collision, and directional light, plus
  the A1 `CameraRig -> Pivot -> Camera3D` hierarchy, a visible capsule
  character, navigation mesh, a central pathfinding obstacle, and destination/
  path debug visuals. A2 adds `EventPlayer`; the character is now a
  presentation-only `CharacterView`.

### `sim/`

The authoritative, deterministic rules layer. Its classes extend
`RefCounted`, not `Node`, so the rules can run headlessly without input,
animation, physics, or a scene.

The resolution flow is:

```text
Command + BattleState + providers
                ↓
             Resolver
                ↓
        ResolutionResult
         (Events + RNG state)
                ↓
       apply events to state
```

Core files:

- `actor_state.gd` defines an actor's authoritative statistics, resources,
  position, conditions, and clone behavior.
- `battle_state.gd` owns all actors, initiative and turn state, world flags,
  and the serializable deterministic RNG state.
- `command.gd` represents an intent such as `move`, `attack`, or `end_turn`.
- `event.gd` represents an accepted state change or a command rejection.
- `resolution_result.gd` carries the ordered events and next RNG state returned
  by resolution.
- `resolver.gd` validates commands, calculates their outcomes without mutating
  the input state, clamps combat movement on the resolved polyline, resolves
  Basic Attack, Dash, Disengage, simplified conditions, and opportunity attacks
  on a temporary state clone, and applies individual events when requested.
- `rules/initiative.gd`, `rules/turn_order.gd`, and `rules/encounter.gd`
  calculate deterministic d20 + DEX initiative, eligible turn advancement,
  and the exploration/combat lifecycle without engine dependencies.
- `polyline.gd` provides the pure path-length and exact-distance clamp helpers
  used as the authoritative movement-cost source.
- `dice.gd` provides deterministic dice rolls from an explicit RNG state.
- `save_game.gd` is the authoritative save snapshot: `schema_version`,
  `game_version`, `rules_version`, `content_version`, `map_id`,
  `battle_state`, and a `world_state` placeholder reserved for A9
  interactable state. `is_compatible()` checks all three version stamps
  before a caller trusts a loaded save.
- `replay_log.gd` is a separate, non-authoritative debug/regression
  artifact: an `initial_snapshot`, the exact `commands` resolved against it,
  and a hash of the resulting events after each one. `find_divergences()`
  re-resolves the same commands from a fresh clone and flags any command
  whose replayed hash no longer matches what was recorded.

#### `sim/definitions/`

Data-driven ability/condition content (A7). `AbilityDefinition` and
`ConditionDefinition` are Godot Resources with a stable id, explicit costs,
and typed effects/modifiers; `DefinitionLibrary` indexes them from a fixed
manifest (no directory scanning) and is the single place the resolver and
`ActorState` look up content instead of branching on ids.

#### `sim/ports/`

Defines the interfaces the pure simulation needs from the engine-facing
world. `nav_provider.gd` abstracts path queries and movement cost, while
`los_provider.gd` abstracts line-of-sight queries. Concrete Godot adapters live
under `world/`; tests use fakes.

### `ai/`

Engine-independent enemy decision-making. `EnemyAI` accepts a `BattleState`
snapshot and returns one `Command`; the caller resolves and applies that command
before requesting another decision. It evaluates a deliberately small,
deterministically ordered candidate set through the existing pure resolver.
`AIQueryBudget` and the budgeted port decorators cap speculative navigation and
line-of-sight work, while rejected or incomplete candidates are never selected.

### `tests/`

Contains the lightweight headless test runner and its suites.

- `test_runner.gd` runs every registered suite and exits non-zero if any test
  fails, making it suitable for CI.
- `test_helpers.gd` creates repeatable battle fixtures, applies resolution
  results, and serializes event logs consistently.
- `unit/test_simulation.gd` checks cloning, deterministic resolution,
  snapshot-hash purity, serialization round-trips, event application,
  navigation rejection behavior, initiative tie breaks, turn ownership, and
  per-turn resource restoration.
- `deterministic/test_replay.gd` runs independent seed-42 simulations 1,000
  times and compares their event-log hashes. It also verifies that seed 43 can
  produce a different result.
- `integration/test_headless_contract.gd` exercises command resolution and
  application together without a scene.
- `unit/test_enemy_ai.gd` checks legal candidate enumeration, deterministic
  replay, query budgets, attack/approach choices, rejection handling,
  incremental decisions, and A5 invariants.
- `integration/test_arena_runtime.gd` exercises terrain-input Command creation,
  EventPlayer/CharacterView playback, replacement, rejection, and obstacle
  routing in the main scene.
- `unit/test_save_game.gd` checks `SaveGame` round-tripping a mid-combat
  state (HP, position, movement, action/bonus/reaction resources,
  conditions, `disengaged`, RNG state, `world_flags`/`world_state`) and
  `is_compatible()` detecting schema/rules/content version drift.
- `deterministic/test_replay_log.gd` records a `ReplayLog` through a short
  combat sequence, checks that `find_divergences()` reports nothing for a
  clean replay and exactly the tampered index for a corrupted hash, and
  that the log still replays clean after a serialization round-trip.
- `integration/test_save_load_service.gd` exercises real `FileAccess`/
  `DirAccess` under `user://`, cleaning up the slot it wrote afterward.
- `fakes/` contains predictable navigation and line-of-sight implementations
  used by the test suites.

### Reserved directories

- `world/` contains the A2 Godot navigation and line-of-sight provider
  adapters, the arena input/composition controller, the A1 path-following
  utility, and the A8 `SaveLoadService` file I/O adapter.
- `view/` contains the tactical camera plus `EventPlayer` and `CharacterView`.
  It interpolates accepted movement events but does not make simulation rules.
- `data/actors/`, `data/abilities/`, and `data/conditions/` are reserved for
  data-driven gameplay definitions introduced in later phases.

The `.gd.uid` files beside scripts are Godot-generated resource identifiers.
They should remain tracked when their corresponding scripts are tracked.

## Running the project

Use Godot 4.6.x from the repository root:

```sh
godot --editor --path godot
```

Open `res://scenes/test_arena.tscn` to inspect the current arena. In play mode:

- `W`, `A`, `S`, `D` pan the camera;
- middle-mouse drag pans; mouse wheel zooms; `Q`/`E` rotate;
- move the pointer over terrain to preview the resolved path, cost, and
  remaining movement (exploration explicitly ignores the budget); left-click
  terrain to create or replace a move Command. Accepted events update the
  authoritative state immediately; `EventPlayer` then interpolates the exact
  resolved path on the character view.

The `NavigationRegion3D` holds the authored navigation mesh; enable navigation
debug visibility in the editor to inspect its walkable surface and the gap
around the central obstacle.

Validate imports and scripts:

```sh
godot --headless --path godot --editor --quit
```

Run all automated tests:

```sh
godot --headless --path godot --script res://tests/test_runner.gd
```

For the architectural rationale and upcoming phases, see the repository-level
`implementation_plan.md` and the ADRs under `docs/ADR/`.
