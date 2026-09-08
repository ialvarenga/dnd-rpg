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

## perform_attack: legacy range fallback plus weapon metadata. New definitions
## should author AbilityDefinition.target_range_meters.
@export var range_meters: float = 1.5
@export var is_ranged: bool = false
@export var attack_kind: StringName = &"basic"

## heal: roll heal_dice_count d heal_die and add heal_modifier. A heal_die of
## 0 means the effect has no dice metadata, preserving existing effects.
@export var heal_die: int = 0
@export var heal_dice_count: int = 1
@export var heal_modifier: int = 0

## consume_item: stable inventory item id required by this effect. Empty means
## the effect does not consume an item.
@export var consumes_item_id: StringName = &""
