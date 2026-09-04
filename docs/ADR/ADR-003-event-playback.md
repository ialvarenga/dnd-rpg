# ADR-003: Presentation plays accepted movement events after state application

## Status

Accepted — A2.

## Decision

The world controller resolves a terrain-click move command against the pure
`BattleState`, applies every returned event immediately, then passes the event
list to `EventPlayer`. `EventPlayer` sends only `movement_segment` paths to a
`CharacterView`; it cannot create commands or mutate simulation state.

The authoritative actor position therefore advances on acceptance, while the
visible character interpolates the exact path delivered in the accepted event.
When an accepted replacement arrives while the view is in flight, the world
layer adds a `presentation_path` from the current visible position to the
authoritative event destination. `EventPlayer` replaces playback with that
path immediately; this presentation-only rebase does not alter `BattleState`.
When playback completes, the view is synchronized to the already-authoritative
actor position to remove small collision/tolerance drift.

## Consequences

Repeated clicks are deterministic commands against current authoritative state.
Rejected commands have no movement event and consequently cannot start or alter
view movement. Navigation and line-of-sight queries are Godot adapters under
`world/`, never dependencies of `sim/`.
