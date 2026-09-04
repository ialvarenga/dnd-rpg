# Godot Project

This directory contains the Godot 4.6 runtime for the tactical RPG. The
current implementation covers the A0 foundation, deterministic A-0 simulation
spike, and the A1 camera/locomotion prototype. The playable 64×64 m test arena
now has a tactical camera, navigation region, obstacle route, and a direct
click-to-move CharacterBody3D controller. This controller is explicitly
presentation-side only; A2 will replace it with Command/Event playback.

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
  path debug visuals.

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
  the input state, and applies individual events when requested.
- `dice.gd` provides deterministic dice rolls from an explicit RNG state.

#### `sim/ports/`

Defines the interfaces the pure simulation needs from the engine-facing
world. `nav_provider.gd` abstracts path queries and movement cost, while
`los_provider.gd` abstracts line-of-sight queries. Concrete Godot adapters will
be added under `world/`; tests use fakes.

### `tests/`

Contains the lightweight headless test runner and its suites.

- `test_runner.gd` runs every registered suite and exits non-zero if any test
  fails, making it suitable for CI.
- `test_helpers.gd` creates repeatable battle fixtures, applies resolution
  results, and serializes event logs consistently.
- `unit/test_simulation.gd` checks cloning, deterministic resolution,
  non-mutation, event application, and rejection behavior.
- `deterministic/test_replay.gd` runs independent seed-42 simulations 1,000
  times and compares their event-log hashes. It also verifies that seed 43 can
  produce a different result.
- `integration/test_headless_contract.gd` exercises command resolution and
  application together without a scene.
- `fakes/` contains predictable navigation and line-of-sight implementations
  used by the test suites.

### Reserved directories

- `world/` contains the A1 direct prototype controller and an engine-independent
  locomotion follower, and is reserved for later Godot-backed navigation,
  line-of-sight, physics, terrain, and other world adapters.
- `view/` contains the A1 tactical camera and is reserved for later animation,
  visual effects, UI, and other presentation code.
- `ai/` is reserved for enemy decision-making built on top of simulation
  commands.
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
- left-click terrain to set or replace the character destination.

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
