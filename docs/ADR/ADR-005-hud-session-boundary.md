# ADR-005: HUD is a read-model; EncounterSession and Resolver retain command authority

## Status

Accepted — C5.

## Decision

`HudRoot` is presentation code. It projects `BattleState` through the pure
`HudViewModel`, subscribes explicitly to one `EncounterSession`, and emits
intent signals for hotbar abilities, end turn, and cancel. It does not retain
an authoritative copy of state, create `Command` values, call `Resolver`, or
apply events.

World controllers own target selection and receive those HUD signals. Ability
and end-turn requests cross the existing `EncounterSession` API, whose sole
submission path remains `Resolver.resolve()` followed by event application.
Cancel is presentation-only until a future explicit targeting read-model needs
it; it clears or toggles visual state and never changes `BattleState`.

Keyboard actions are routed by `HudRoot`, not by simulation or controller
input handlers. Interactive controls use `MOUSE_FILTER_STOP`, while empty and
decorative layout is pass-through, so a HUD click cannot reach the terrain
picker. Icon lookup is a view-side `IconSet` resource keyed by stable ids;
controllers do not branch on an actor, ability, or icon id.

HUD modals may pause world-side processing. `HudRoot` owns the C/I/Esc sheet
shortcuts and exposes the combined modal pause state to controllers and the
camera rig. The sheet remains a read-model: its Use button only re-emits the
existing inventory-item intent, which the world controller submits through
`EncounterSession`.

## Consequences

ADR-001 remains intact: input and UI are not simulation dependencies, and
`Resolver` remains the authority on command acceptance. ADR-003 remains
intact: presentation can play only accepted events after application. ADR-004
continues to govern gameplay definitions; UI icon mappings are separate,
non-authoritative presentation resources and cannot alter an ability's rules.

The HUD is reusable across hand-authored and compiled-map scenes because both
bind it to the same `EncounterSession` boundary. Any future targeting mode
must remain presentation state and submit its final intent through that API.
