class_name Equipment
extends RefCounted

## Pure lookups over ActorState.equipment_slots: which item fills a slot and
## the item facts that need no wielder context (range bands, held model).
## Every number that combines an item with its wielder -- attack bonus,
## damage, armor class -- is derived by AttackMath (sim/rules/attack_math.gd).
## There is no equip command in this milestone: equipment_slots is populated
## once when an actor is built from an ActorDefinition and never mutated by
## the resolver, so lookups only ever run at read time.

## Fixed slot order (ADR-001/ADR-004: fixed manifests, ordered iteration,
## never scan). Only "weapon" and "armor" exist in this milestone; the order
## itself is not currently observable (each slot is read independently) but
## is kept explicit for future multi-slot aggregation.
const SLOT_ORDER: Array[StringName] = [&"weapon", &"armor"]

const SLOT_WEAPON := &"weapon"
const SLOT_ARMOR := &"armor"


static func weapon(actor: ActorState, defs: DefinitionLibrary) -> ItemDefinition:
	return _equipped_item(actor, SLOT_WEAPON, defs)


static func armor(actor: ActorState, defs: DefinitionLibrary) -> ItemDefinition:
	return _equipped_item(actor, SLOT_ARMOR, defs)


static func is_ranged_weapon(actor: ActorState, defs: DefinitionLibrary) -> bool:
	var wielded := weapon(actor, defs)
	return wielded != null and wielded.is_ranged_weapon


static func normal_range(actor: ActorState, defs: DefinitionLibrary, fallback: float) -> float:
	var wielded := weapon(actor, defs)
	return wielded.normal_range_meters if wielded != null and wielded.normal_range_meters > 0.0 else fallback


static func long_range(actor: ActorState, defs: DefinitionLibrary, fallback: float) -> float:
	var wielded := weapon(actor, defs)
	if wielded != null and wielded.long_range_meters > 0.0:
		return wielded.long_range_meters
	return normal_range(actor, defs, fallback)


## View-facing: the wielded weapon's held model path, or "" if unarmed or the
## weapon has no visual. Read by CharacterView setup, never by Resolver/AI.
static func held_weapon_model_path(actor: ActorState, defs: DefinitionLibrary) -> String:
	var wielded := weapon(actor, defs)
	return wielded.held_model_path if wielded != null else ""


static func _equipped_item(actor: ActorState, slot: StringName, defs: DefinitionLibrary) -> ItemDefinition:
	var item_id: StringName = actor.equipment_slots.get(slot, &"")
	if item_id == &"":
		return null
	return defs.get_item(item_id)
