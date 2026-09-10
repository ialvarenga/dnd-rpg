# ADR-004: Godot Resources as the A7 content format, resolved through a generic effect vocabulary

## Status

Accepted — A7.

## Decision

Ability and condition content (`AbilityDefinition`, `AbilityEffect`,
`ConditionDefinition`) is authored as plain Godot `Resource` subclasses under
`sim/definitions/`, serialized as `.tres` text resources under
`data/abilities/` and `data/conditions/`. This is the "simplest project-native
format" available: there is no YAML parser in the project, and `.tres` is natively
serializable, diffable, editor-authorable, and loadable with the engine's own
`load()` — no new dependency, no expression language, no mod loader.

`DefinitionLibrary` (`sim/definitions/definition_library.gd`) is the single
runtime registry for both catalogs, indexed by stable `StringName` id. Its
default instance loads a fixed, explicit manifest of resource paths (no
directory scanning, so content stays deterministic across runs/platforms).
`Resolver.resolve()` takes an optional `defs: DefinitionLibrary` parameter
that defaults to this library when omitted, so every pre-A7 call site keeps
working unchanged while tests can inject an alternate library to prove
behavior is actually read from data (see `tests/unit/test_definitions.gd`)
and to exercise unknown-definition rejection deterministically.

`Resolver` never branches on a concrete ability or condition id. Command
routing only maps a command type to an ability id (`&"dash" -> &"dash"`,
`&"attack"/&"basic_attack" -> &"basic_attack"`, ...); all subsequent behavior
comes from the looked-up `AbilityDefinition`'s costs and a small, fixed
vocabulary of typed effect handlers:

- `add_base_movement` (multiplier against `movement_speed`) — Dash.
- `apply_disengage` — Disengage.
- `apply_condition` / `remove_condition` — generic condition mutation,
  available to future content.
- `perform_attack` (range/is_ranged/attack_kind) — Basic Attack; wraps the
  existing LoS/range/roll/damage pipeline as one effect, per the instruction
  to keep v1 effects "deliberately small" rather than decomposing attack
  math into an expression language.

Condition modifiers are explicit typed booleans on `ConditionDefinition`
(`attack_roll_disadvantage`, `melee_advantage_when_close`,
`ranged_disadvantage_when_not_close`, `prevents_actions`, `counts_as_prone`,
`half_speed_required_to_stand`, `ends_life`) instead of hardcoded
`conditions.has(&"poisoned")`-style checks. `ActorState.is_alive()` /
`is_conscious()` / `is_prone()` and the resolver's attack-roll advantage
math now aggregate these flags across an actor's condition ids via
`DefinitionLibrary.get_default()`, rather than switching on literal ids.
`ActorState`/`BattleState` still store only condition/ability *ids*
(`StringName`), never mutable definition objects, matching the existing
save-by-reference convention.

`DefinitionLibrary.CONTENT_VERSION` and `BattleState.content_version`
(serialized in `to_dict`/`from_dict`) exist so a future save/load pass (A8)
can carry and validate content compatibility alongside `rules_version`,
without building the rest of the save pipeline now.

## Consequences

Adding or tuning an ability/condition (e.g. changing Dash's multiplier, or
adding a new "Prone grants melee advantage"-style modifier to a new
condition) is a data change under `data/`, not a `Resolver` code change,
as long as it fits the existing effect/modifier vocabulary. Extending the
vocabulary (a new effect `type` or modifier flag) is still a `Resolver` code
change, by design — v1 deliberately has no expression language or scripted
effects.

`ActorState`'s condition predicates and the resolver's attack-roll flags
resolve conditions through `DefinitionLibrary.get_default()` rather than
threading a definitions parameter through every call site in `sim/rules/`
and `ai/`. This keeps the refactor's footprint limited to `sim/resolver.gd`,
`sim/actor_state.gd`, and `sim/battle_state.gd`; the trade-off is that
`is_alive()`/`is_conscious()`/`is_prone()` always consult the default
content, even when a caller resolves a command against an injected
alternate `DefinitionLibrary`. Ability lookups and attack-roll modifiers
*do* honor an injected library, which is what the A7 tests need to prove
data-drivenness and unknown-id rejection; if a future phase needs full
content injection for lifecycle/eligibility checks too, thread
`DefinitionLibrary` through `ActorState`'s predicates and their callers at
that point.

The reuse review rejected third-party ability-system integration: the local
definitions remain the only content format and runtime authority.
