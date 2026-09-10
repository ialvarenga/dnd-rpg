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
var saving_throw_proficiencies: Array[StringName] = []

var movement_speed: float = 9.0
var movement_remaining: float = 9.0
var action_available: bool = true
var bonus_action_available: bool = true
var reaction_available: bool = true
var condition_states: Array[ConditionState] = []
var disengaged: bool = false

## Ability id -> activations already spent from that ability's `max_uses` pool.
## Absent keys mean nothing spent. Unlike the per-turn flags above this survives
## the turn, so it is part of the stable snapshot and the save round-trip.
var ability_uses_spent: Dictionary = {}

# Spike A-0 combat fields. These are the actor's own base stats; Resolver
# reads through Equipment (sim/equipment.gd) to combine them with whatever is
# in equipment_slots, so they stay meaningful even for an unequipped actor.
var attack_bonus: int = 0
var damage_die: int = 6
var damage_modifier: int = 0

# Fase C2 content fields. There is no equip command in this milestone:
# equipment_slots/ability_ids are populated once (see from_definition) and
# remain immutable content. Inventory starts from content but is mutable
# authoritative state: consumable effects remove entries and BattleState's
# stable snapshot therefore includes it.
var ability_ids: Array[StringName] = []
## Slot (Equipment.SLOT_WEAPON/SLOT_ARMOR) -> ItemDefinition id.
var equipment_slots: Dictionary = {}
var inventory: Array[StringName] = []
## Fungible, actor-owned currency. Payments move this between actors instead
## of consuming an inventory item, so every balance remains authoritative.
var coins: int = 0
## Which ActorDefinition this actor was built from, if any (empty for actors
## constructed ad hoc, e.g. in tests). Save/HUD-facing metadata only; Resolver
## never looks this up.
var definition_id: StringName = &""

## Social stance, deliberately separate from `side`. `side` stays the combat
## team; this decides whether the actor is currently out for your blood. Only
## &"hostile" actors trigger encounter detection, so a &"neutral" enemy-side
## actor can be walked up to and talked to until it is provoked. Authored per
## map instance (MapSpec actor.initial_disposition), not per stat block, and
## changed only by the set_disposition command.
var disposition: StringName = &"hostile"

## Dialog graph this actor opens when talked to; &"" means not talkable.
## Authored per map instance (MapSpec actor.dialog), not part of the
## ActorDefinition, so the same stat block can be silent on one map and
## talkative on another.
var dialog_id: StringName = &""


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
	actor.saving_throw_proficiencies = definition.saving_throw_proficiencies.duplicate()
	actor.movement_speed = definition.movement_speed
	actor.movement_remaining = definition.movement_speed
	actor.attack_bonus = definition.attack_bonus
	actor.damage_die = definition.damage_die
	actor.damage_modifier = definition.damage_modifier
	actor.ability_ids = definition.ability_ids.duplicate()
	actor.equipment_slots = definition.equipment_slots.duplicate()
	actor.inventory = definition.starting_inventory.duplicate()
	actor.coins = definition.starting_coins
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
	copy.saving_throw_proficiencies = saving_throw_proficiencies.duplicate()
	copy.movement_speed = movement_speed
	copy.movement_remaining = movement_remaining
	copy.action_available = action_available
	copy.bonus_action_available = bonus_action_available
	copy.reaction_available = reaction_available
	for condition_state in condition_states:
		copy.condition_states.append(condition_state.clone())
	copy.disengaged = disengaged
	copy.attack_bonus = attack_bonus
	copy.damage_die = damage_die
	copy.damage_modifier = damage_modifier
	copy.ability_ids = ability_ids.duplicate()
	copy.equipment_slots = equipment_slots.duplicate()
	copy.inventory = inventory.duplicate()
	copy.coins = coins
	copy.ability_uses_spent = ability_uses_spent.duplicate()
	copy.definition_id = definition_id
	copy.disposition = disposition
	copy.dialog_id = dialog_id
	return copy


func is_alive() -> bool:
	return hp > 0 and not _has_condition_flag(&"ends_life")


func is_conscious() -> bool:
	return is_alive() and not _has_condition_flag(&"prevents_actions")


## Whether this actor may react at all right now, independent of whether its
## per-round reaction is still unspent (reaction_available).
func can_take_reactions() -> bool:
	return is_conscious() and not _has_condition_flag(&"prevents_reactions")


func is_prone() -> bool:
	# Both "prone" and "unconscious" flag counts_as_prone in their
	# ConditionDefinition, so an unconscious actor is prone here without
	# needing a second, redundant condition entry in their serialized state.
	return _has_condition_flag(&"counts_as_prone")


func add_condition(
	condition_id: StringName,
	source_actor_id: int = -1,
	remaining_triggers: int = -1,
	expiration_timing: StringName = &"none"
) -> void:
	var existing := condition_state(condition_id)
	if existing == null:
		condition_states.append(ConditionState.create(condition_id, source_actor_id, remaining_triggers, expiration_timing))
	else:
		existing.source_actor_id = source_actor_id
		existing.remaining_triggers = remaining_triggers
		existing.expiration_timing = expiration_timing


func remove_condition(condition_id: StringName) -> void:
	for index in range(condition_states.size() - 1, -1, -1):
		if condition_states[index].definition_id == condition_id:
			condition_states.remove_at(index)


func condition_state(condition_id: StringName) -> ConditionState:
	for state in condition_states:
		if state.definition_id == condition_id:
			return state
	return null


func has_condition(condition_id: StringName) -> bool:
	return condition_state(condition_id) != null


func condition_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for state in condition_states:
		ids.append(state.definition_id)
	return ids


func ability_modifier(ability: StringName) -> int:
	var score := 10
	match ability:
		&"strength": score = strength
		&"dexterity": score = dexterity
		&"constitution": score = constitution
		&"intelligence": score = intelligence
		&"wisdom": score = wisdom
		&"charisma": score = charisma
	return floori(float(score - 10) / 2.0)


func saving_throw_modifier(ability: StringName) -> int:
	return ability_modifier(ability) + (proficiency_bonus if saving_throw_proficiencies.has(ability) else 0)


func _has_condition_flag(flag_name: StringName) -> bool:
	var library := DefinitionLibrary.get_default()
	for condition_id in condition_ids():
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
		"saving_throw_proficiencies": SimulationSerialization.value_to_data(saving_throw_proficiencies),
		"movement_speed": movement_speed,
		"movement_remaining": movement_remaining,
		"action_available": action_available,
		"bonus_action_available": bonus_action_available,
		"reaction_available": reaction_available,
		"condition_states": condition_states.map(func(state: ConditionState): return state.to_dict()),
		"disengaged": disengaged,
		"attack_bonus": attack_bonus,
		"damage_die": damage_die,
		"damage_modifier": damage_modifier,
		"ability_ids": SimulationSerialization.value_to_data(ability_ids),
		"equipment_slots": _equipment_slots_to_data(equipment_slots),
		"inventory": SimulationSerialization.value_to_data(inventory),
		"coins": coins,
		"ability_uses_spent": _ability_uses_to_data(ability_uses_spent),
		"definition_id": String(definition_id),
		"disposition": String(disposition),
		"dialog_id": String(dialog_id),
	}


## Keys are StringName ability ids; JSON needs plain String keys, exactly like
## _equipment_slots_to_data below.
static func _ability_uses_to_data(uses: Dictionary) -> Dictionary:
	var data := {}
	for ability_id in uses.keys():
		data[String(ability_id)] = int(uses[ability_id])
	return data


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
	for proficiency in data.get("saving_throw_proficiencies", []):
		actor.saving_throw_proficiencies.append(StringName(str(proficiency)))
	actor.movement_speed = float(data.get("movement_speed", 9.0))
	actor.movement_remaining = float(data.get("movement_remaining", 9.0))
	actor.action_available = bool(data.get("action_available", true))
	actor.bonus_action_available = bool(data.get("bonus_action_available", true))
	actor.reaction_available = bool(data.get("reaction_available", true))
	for condition_data in data.get("condition_states", []):
		if condition_data is Dictionary:
			actor.condition_states.append(ConditionState.from_dict(condition_data))
	# Direct BattleState deserialization remains tolerant of the pre-v3 shape,
	# while SaveGame compatibility still rejects old schema versions.
	if actor.condition_states.is_empty():
		var legacy_conditions: Variant = SimulationSerialization.data_to_value(data.get("conditions", []))
		if legacy_conditions is Array:
			for condition in legacy_conditions:
				actor.add_condition(StringName(str(condition)))
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
	actor.coins = maxi(0, int(data.get("coins", 0)))
	var restored_uses: Variant = data.get("ability_uses_spent", {})
	if restored_uses is Dictionary:
		for ability_id in (restored_uses as Dictionary).keys():
			actor.ability_uses_spent[StringName(str(ability_id))] = int((restored_uses as Dictionary)[ability_id])
	actor.definition_id = StringName(str(data.get("definition_id", "")))
	actor.disposition = StringName(str(data.get("disposition", "hostile")))
	actor.dialog_id = StringName(str(data.get("dialog_id", "")))
	return actor
