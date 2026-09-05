class_name ItemDefinition
extends Resource

## Stable content definition for an equippable/carryable item (Longsword,
## Leather Armor, ...). Modifiers are explicit typed values -- no expression
## language, matching AbilityDefinition/ConditionDefinition (ADR-004) --
## aggregated generically by Equipment (sim/equipment.gd) instead of Resolver
## branching on a concrete item id.

@export var id: StringName = &""
@export var display_name: String = ""

## "weapon" | "armor" | "" (carryable but not equippable in this milestone).
@export var slot: StringName = &""

## Weapon-only, ignored otherwise. Added on top of the wielder's own
## attack_bonus. damage_die of 0 means "no override" -- Equipment falls back
## to the wielder's base damage_die.
@export var attack_bonus_modifier: int = 0
@export var damage_die: int = 0
@export var damage_modifier: int = 0

## Armor-only, ignored otherwise. Added on top of the wearer's own
## armor_class.
@export var armor_class_bonus: int = 0
