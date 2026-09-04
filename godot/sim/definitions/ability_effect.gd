class_name AbilityEffect
extends Resource

## One explicit, typed effect entry inside an AbilityDefinition. v1 deliberately
## avoids an expression language: `type` selects one of a small fixed set of
## generic handlers in Resolver, and the remaining fields are plain data for
## that handler to read.

@export var type: StringName = &""

## add_base_movement: movement gained = actor.movement_speed * multiplier.
@export var multiplier: float = 1.0

## apply_condition / remove_condition: condition id to add or remove.
@export var condition_id: StringName = &""

## perform_attack: base range/weapon metadata (overridable by Command.metadata).
@export var range_meters: float = 1.5
@export var is_ranged: bool = false
@export var attack_kind: StringName = &"basic"
