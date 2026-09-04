# Deterministic Tactical RPG

The current milestone is A0 plus Spike A-0: a headless, deterministic combat
simulation and a hand-built 64×64 m test arena. It deliberately contains no
camera, navigation-server integration, or gameplay presentation yet.

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

- `godot/sim/` is the authoritative pure simulation.
- `godot/world/` will contain engine-backed provider adapters in later phases.
- `godot/view/` is reserved for presentation.
- `docs/ADR/` records architectural decisions.

See [implementation_plan.md](implementation_plan.md) for the project plan.
