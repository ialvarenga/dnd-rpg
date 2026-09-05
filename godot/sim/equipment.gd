class_name Equipment
extends RefCounted

## Pure equipment aggregation over ActorState.equipment_slots, read by
## Resolver (attack/armor calculations) and EnemyAI (expected-damage scoring)
## instead of either one reading ActorState's base combat fields directly.
## There is no equip command in this milestone: equipment_slots is populated
## once when an actor is built from an ActorDefinition and never mutated by
## the resolver, so aggregation only ever runs at read time.
##
## An actor with an empty (or partially empty) equipment_slots aggregates
## back to exactly its own base fields -- existing actors with no equipment
## content behave identically to before Fase C2.

## Fixed slot order (ADR-001/ADR-004: fixed manifests, ordered iteration,
## never scan). Only "weapon" and "armor" exist in this milestone; the order
## itself is not currently observable (each slot is aggregated
## independently) but is kept explicit for future multi-slot aggregation.
const SLOT_ORDER: Array[StringName] = [&"weapon", &"armor"]

const SLOT_WEAPON := &"weapon"
const SLOT_ARMOR := &"armor"


static func aggregate_attack_bonus(actor: ActorState, defs: DefinitionLibrary) -> int:
	var weapon := _equipped_item(actor, SLOT_WEAPON, defs)
	return actor.attack_bonus + (weapon.attack_bonus_modifier if weapon != null else 0)


## A weapon's damage_die of 0 means "does not override"; only a positive
## weapon damage_die replaces the wielder's own.
static func aggregate_damage_die(actor: ActorState, defs: DefinitionLibrary) -> int:
	var weapon := _equipped_item(actor, SLOT_WEAPON, defs)
	if weapon != null and weapon.damage_die > 0:
		return weapon.damage_die
	return actor.damage_die


static func aggregate_damage_modifier(actor: ActorState, defs: DefinitionLibrary) -> int:
	var weapon := _equipped_item(actor, SLOT_WEAPON, defs)
	return actor.damage_modifier + (weapon.damage_modifier if weapon != null else 0)


static func aggregate_armor_class(actor: ActorState, defs: DefinitionLibrary) -> int:
	var armor := _equipped_item(actor, SLOT_ARMOR, defs)
	return actor.armor_class + (armor.armor_class_bonus if armor != null else 0)


static func _equipped_item(actor: ActorState, slot: StringName, defs: DefinitionLibrary) -> ItemDefinition:
	var item_id: StringName = actor.equipment_slots.get(slot, &"")
	if item_id == &"":
		return null
	return defs.get_item(item_id)
