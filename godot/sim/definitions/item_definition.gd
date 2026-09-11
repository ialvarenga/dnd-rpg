class_name ItemDefinition
extends Resource

## Stable content definition for an equippable/carryable item (Longsword,
## Leather Armor, ...). Items author SRD equipment facts -- category, die,
## properties, base AC -- and never a wielder-specific number: AttackMath
## (sim/rules/attack_math.gd) derives attack, damage, and AC from these facts
## plus the wearer's ability scores and proficiencies. Explicit typed values,
## no expression language, matching AbilityDefinition/ConditionDefinition
## (ADR-004).

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""

## "weapon" | "armor" | "" (carryable but not equippable in this milestone).
@export var slot: StringName = &""

## Weapon-only, ignored otherwise. weapon_category is &"simple" or &"martial"
## and decides proficiency; weapon_properties uses the SRD property names
## (&"finesse", &"light", &"thrown", ...) of which only finesse changes the
## attack math today.
@export var weapon_category: StringName = &""
@export var weapon_properties: Array[StringName] = []
@export var damage_die: int = 0
@export var damage_type: StringName = &"untyped"
@export var normal_range_meters: float = 0.0
@export var long_range_meters: float = 0.0
@export var is_ranged_weapon: bool = false

## Armor-only, ignored otherwise. armor_category is &"light" (base + Dex),
## &"medium" (base + Dex, at most +2), or &"heavy" (base only).
@export var armor_category: StringName = &""
@export var base_armor_class: int = 0

## A +N magic item: added to attack and damage rolls for a weapon, to AC for
## armor.
@export var magic_bonus: int = 0

## Weapon-only, presentation-facing. Path to the held model CharacterView
## attaches to the wielder's hand bone; empty means nothing is shown.
@export var held_model_path: String = ""
## Weapon-only, presentation-facing. Skeleton bone the held model attaches to:
## a bow sits in the off hand (&"handslot.l"), everything else in the right.
@export var held_bone: StringName = &"handslot.r"
## Weapon-only, presentation-facing. Rotation applied to the held model on its
## bone, for props authored facing the other way (the bow's string must face
## the archer, not the target).
@export var held_rotation_degrees: Vector3 = Vector3.ZERO
## Weapon-only, presentation-facing. Model EventPlayer flies from the wielder
## to the target of a ranged attack; empty means the attack is narrated with
## no projectile.
@export var projectile_model_path: String = ""

## Ability granted when this carried item is used. Empty means the item is not
## consumable.
@export var use_ability_id: StringName = &""
