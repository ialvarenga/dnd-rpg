class_name ConditionDefinition
extends Resource

## Stable content definition for a status condition (Poisoned, Prone,
## Unconscious, Dead, ...). Modifiers are explicit typed booleans -- no
## expression language -- consulted generically by Resolver/ActorState instead
## of hardcoded condition-id checks (e.g. `conditions.has(&"poisoned")`).

@export var id: StringName = &""
@export var display_name: String = ""
@export var tags: Array[StringName] = []

## Attack-roll modifiers.
@export var attack_roll_disadvantage: bool = false
@export var melee_advantage_when_close: bool = false
@export var ranged_disadvantage_when_not_close: bool = false

## Actor-eligibility / movement modifiers.
@export var prevents_actions: bool = false
@export var counts_as_prone: bool = false
@export var half_speed_required_to_stand: bool = false

## Lifecycle modifier: actor is treated as no longer alive.
@export var ends_life: bool = false
