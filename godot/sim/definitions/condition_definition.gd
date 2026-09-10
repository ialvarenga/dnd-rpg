class_name ConditionDefinition
extends Resource

## Stable content definition for a status condition (Poisoned, Prone,
## Unconscious, Dead, ...). Modifiers are explicit typed booleans -- no
## expression language -- consulted generically by Resolver/ActorState instead
## of hardcoded condition-id checks (e.g. `conditions.has(&"poisoned")`).

@export var id: StringName = &""
@export var display_name: String = ""
@export var tags: Array[StringName] = []

## Instance lifetime defaults. -1 is permanent; otherwise the count is
## consumed at the selected actor turn boundary.
@export var default_duration_triggers: int = -1
@export var default_expiration_timing: StringName = &"none"

## Attack-roll modifiers.
@export var attack_roll_disadvantage: bool = false
@export var melee_advantage_when_close: bool = false
@export var ranged_disadvantage_when_not_close: bool = false
@export var attacks_against_disadvantage: bool = false

## Actor-eligibility / movement modifiers.
@export var prevents_actions: bool = false
## Blocks reactions (opportunity attacks, reaction abilities) while leaving the
## actor's own turn intact -- e.g. BG3-style Prone.
@export var prevents_reactions: bool = false
@export var counts_as_prone: bool = false
@export var half_speed_required_to_stand: bool = false

## Lifecycle modifier: actor is treated as no longer alive.
@export var ends_life: bool = false
