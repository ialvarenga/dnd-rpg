# Deterministic Tactical RPG

The current milestone is A6: a headless, deterministic simulation with
authoritative turns, action economy, basic attacks, conditions, opportunity
attacks, and bounded utility enemy AI. Enemy AI evaluates a small set of
commands against state snapshots through the same pure resolver, then callers
apply the chosen result before requesting its next incremental command. The
hand-built 64×64 m playable test arena remains an A5 presentation fixture:
terrain hover resolves a non-mutating movement preview; terrain clicks resolve
and apply commands and events, while Godot presentation plays only accepted
movement paths.

## Requirements

- Godot 4.6.x (Jolt 3D physics explicitly selected in project settings)

## Run

From the repository root:

```sh
godot --editor --path godot
godot --headless --path godot --script res://tests/test_runner.gd
godot --headless --path godot --editor --quit
```

The test command runs unit, deterministic replay, and integration-safe
headless checks. It exits non-zero on failure.

## Layout

- `godot/sim/` is the authoritative pure simulation, including initiative,
  encounter lifecycle, turn ownership, action/reaction resources, exact
  polyline movement costs, combat-budget clamping, and attack resolution.
- `godot/world/` contains engine-backed navigation/LOS adapters and arena input.
- `godot/ai/` contains engine-independent utility AI and bounded port
  decorators; it has no scene, Node, input, physics, or Godot navigation
  dependencies.
- `godot/view/` contains presentation-only camera and event playback.
- `docs/ADR/` records architectural decisions.

See [implementation_plan.md](implementation_plan.md) for the project plan.
