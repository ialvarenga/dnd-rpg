class_name ActorState
extends RefCounted

var id: int = -1
var side: StringName = &"neutral"
var position: Vector3 = Vector3.ZERO

var hp: int = 1
var max_hp: int = 1
var armor_class: int = 10

var strength: int = 10
var dexterity: int = 10
var constitution: int = 10
var intelligence: int = 10
var wisdom: int = 10
var charisma: int = 10
var proficiency_bonus: int = 2

var movement_speed: float = 9.0
var movement_remaining: float = 9.0
var action_available: bool = true
var bonus_action_available: bool = true
var reaction_available: bool = true
var conditions: Array[StringName] = []
var disengaged: bool = false

# Spike A-0 combat fields. These are the actor's own base stats; Resolver
# reads through Equipment (sim/equipment.gd) to combine them with whatever is
# in equipment_slots, so they stay meaningful even for an unequipped actor.
var attack_bonus: int = 0
var damage_die: int = 6
var damage_modifier: int = 0

# Fase C2 content fields. There is no equip command in this milestone:
# equipment_slots/inventory/ability_ids are populated once (see
# from_definition) and never mutated by Resolver, so they are immutable
# content, not simulated state -- kept out of BattleState.stable_snapshot().
var ability_ids: Array[StringName] = []
## Slot (Equipment.SLOT_WEAPON/SLOT_ARMOR) -> ItemDefinition id.
var equipment_slots: Dictionary = {}
var inventory: Array[StringName] = []
## Which ActorDefinition this actor was built from, if any (empty for actors
## constructed ad hoc, e.g. in tests). Save/HUD-facing metadata only; Resolver
## never looks this up.
var definition_id: StringName = &""


## Builds a fresh ActorState from stable content instead of a caller setting
## HP/AC/etc. constants by hand. The result is fully independent of
## `definition` -- later mutation of the ActorState (or of the definition
## resource, though content is expected to stay immutable at runtime) cannot
## affect the other.
static func from_definition(definition: ActorDefinition, actor_id: int, side: StringName, position: Vector3) -> ActorState:
	var actor := ActorState.new()
	actor.id = actor_id
	actor.side = side
	actor.position = position
	actor.hp = definition.max_hp
	actor.max_hp = definition.max_hp
	actor.armor_class = definition.armor_class
	actor.strength = definition.strength
	actor.dexterity = definition.dexterity
	actor.constitution = definition.constitution
	actor.intelligence = definition.intelligence
	actor.wisdom = definition.wisdom
	actor.charisma = definition.charisma
	actor.proficiency_bonus = definition.proficiency_bonus
	actor.movement_speed = definition.movement_speed
	actor.movement_remaining = definition.movement_speed
	actor.attack_bonus = definition.attack_bonus
	actor.damage_die = definition.damage_die
	actor.damage_modifier = definition.damage_modifier
	actor.ability_ids = definition.ability_ids.duplicate()
	actor.equipment_slots = definition.equipment_slots.duplicate()
	actor.inventory = definition.starting_inventory.duplicate()
	actor.definition_id = definition.id
	return actor


func clone() -> ActorState:
	var copy := ActorState.new()
	copy.id = id
	copy.side = side
	copy.position = position
	copy.hp = hp
	copy.max_hp = max_hp
	copy.armor_class = armor_class
	copy.strength = strength
	copy.dexterity = dexterity
	copy.constitution = constitution
	copy.intelligence = intelligence
	copy.wisdom = wisdom
	copy.charisma = charisma
	copy.proficiency_bonus = proficiency_bonus
	copy.movement_speed = movement_speed
	copy.movement_remaining = movement_remaining
	copy.action_available = action_available
	copy.bonus_action_available = bonus_action_available
	copy.reaction_available = reaction_available
	copy.conditions = conditions.duplicate()
	copy.disengaged = disengaged
	copy.attack_bonus = attack_bonus
	copy.damage_die = damage_die
	copy.damage_modifier = damage_modifier
	copy.ability_ids = ability_ids.duplicate()
	copy.equipment_slots = equipment_slots.duplicate()
	copy.inventory = inventory.duplicate()
	copy.definition_id = definition_id
	return copy


func is_alive() -> bool:
	return hp > 0 and not _has_condition_flag(&"ends_life")


func is_conscious() -> bool:
	return is_alive() and not _has_condition_flag(&"prevents_actions")


func is_prone() -> bool:
	# Both "prone" and "unconscious" flag counts_as_prone in their
	# ConditionDefinition, so an unconscious actor is prone here without
	# needing a second, redundant condition entry in their serialized state.
	return _has_condition_flag(&"counts_as_prone")


func _has_condition_flag(flag_name: StringName) -> bool:
	var library := DefinitionLibrary.get_default()
	for condition_id in conditions:
		var definition := library.get_condition(condition_id)
		if definition != null and bool(definition.get(flag_name)):
			return true
	return false


func to_dict() -> Dictionary:
	return {
		"id": id,
		"side": String(side),
		"position": SimulationSerialization.value_to_data(position),
		"hp": hp,
		"max_hp": max_hp,
		"armor_class": armor_class,
		"strength": strength,
		"dexterity": dexterity,
		"constitution": constitution,
		"intelligence": intelligence,
		"wisdom": wisdom,
		"charisma": charisma,
		"proficiency_bonus": proficiency_bonus,
		"movement_speed": movement_speed,
		"movement_remaining": movement_remaining,
		"action_available": action_available,
		"bonus_action_available": bonus_action_available,
		"reaction_available": reaction_available,
		"conditions": SimulationSerialization.value_to_data(conditions),
		"disengaged": disengaged,
		"attack_bonus": attack_bonus,
		"damage_die": damage_die,
		"damage_modifier": damage_modifier,
		"ability_ids": SimulationSerialization.value_to_data(ability_ids),
		"equipment_slots": _equipment_slots_to_data(equipment_slots),
		"inventory": SimulationSerialization.value_to_data(inventory),
		"definition_id": String(definition_id),
	}


static func _equipment_slots_to_data(slots: Dictionary) -> Dictionary:
	var data := {}
	for slot in slots.keys():
		data[String(slot)] = String(slots[slot])
	return data


static func from_dict(data: Dictionary) -> ActorState:
	var actor := ActorState.new()
	actor.id = int(data.get("id", -1))
	actor.side = StringName(str(data.get("side", "neutral")))
	var restored_position: Variant = SimulationSerialization.data_to_value(data.get("position", {}))
	if restored_position is Vector3:
		actor.position = restored_position
	actor.hp = int(data.get("hp", 1))
	actor.max_hp = int(data.get("max_hp", 1))
	actor.armor_class = int(data.get("armor_class", 10))
	actor.strength = int(data.get("strength", 10))
	actor.dexterity = int(data.get("dexterity", 10))
	actor.constitution = int(data.get("constitution", 10))
	actor.intelligence = int(data.get("intelligence", 10))
	actor.wisdom = int(data.get("wisdom", 10))
	actor.charisma = int(data.get("charisma", 10))
	actor.proficiency_bonus = int(data.get("proficiency_bonus", 2))
	actor.movement_speed = float(data.get("movement_speed", 9.0))
	actor.movement_remaining = float(data.get("movement_remaining", 9.0))
	actor.action_available = bool(data.get("action_available", true))
	actor.bonus_action_available = bool(data.get("bonus_action_available", true))
	actor.reaction_available = bool(data.get("reaction_available", true))
	var restored_conditions: Variant = SimulationSerialization.data_to_value(data.get("conditions", []))
	if restored_conditions is Array:
		for condition in restored_conditions:
			actor.conditions.append(StringName(str(condition)))
	actor.disengaged = bool(data.get("disengaged", false))
	actor.attack_bonus = int(data.get("attack_bonus", 0))
	actor.damage_die = int(data.get("damage_die", 6))
	actor.damage_modifier = int(data.get("damage_modifier", 0))
	var restored_ability_ids: Variant = SimulationSerialization.data_to_value(data.get("ability_ids", []))
	if restored_ability_ids is Array:
		for ability_id in restored_ability_ids:
			actor.ability_ids.append(StringName(str(ability_id)))
	var restored_equipment: Variant = data.get("equipment_slots", {})
	if restored_equipment is Dictionary:
		for slot_key in (restored_equipment as Dictionary).keys():
			actor.equipment_slots[StringName(str(slot_key))] = StringName(str((restored_equipment as Dictionary)[slot_key]))
	var restored_inventory: Variant = SimulationSerialization.data_to_value(data.get("inventory", []))
	if restored_inventory is Array:
		for item_id in restored_inventory:
			actor.inventory.append(StringName(str(item_id)))
	actor.definition_id = StringName(str(data.get("definition_id", "")))
	return actor
