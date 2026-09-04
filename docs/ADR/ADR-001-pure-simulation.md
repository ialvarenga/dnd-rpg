# ADR-001: Authoritative simulation is pure and event driven

## Status

Accepted — A0 / Spike A-0.

## Decision

Combat rules live in `godot/sim/` as `Command → Resolver → ResolutionResult →
Event → apply(BattleState)`. `BattleState`, rather than a Godot Node, owns all
authoritative actor and RNG state. `Resolver.resolve()` does not mutate its
input and receives navigation and line-of-sight through ports.

## Consequences

Simulation can execute in headless tests without a scene, input, animation,
physics query, or `NavigationServer3D`. View code will narrate events but will
not make combat decisions.

