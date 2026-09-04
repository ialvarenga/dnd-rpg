# ADR-002: Jolt is the 3D physics engine for this Godot 4.6 project

## Status

Accepted — A0.

## Decision

Use Godot 4.6's new-project default 3D physics engine, Jolt. This is recorded
explicitly so an engine upgrade or project-setting change cannot silently
change the intended physics backend.

## Consequences

The pure simulation has no physics-engine dependency. Physics will be used by
world and view layers only, beginning in later phases.

