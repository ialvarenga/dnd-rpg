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

# Spike A-0 combat fields.
var attack_bonus: int = 0
var damage_die: int = 6
var damage_modifier: int = 0


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
	return copy


func is_alive() -> bool:
	return hp > 0 and not conditions.has(&"dead")


func is_conscious() -> bool:
	return is_alive() and not conditions.has(&"unconscious")


func is_prone() -> bool:
	# Unconscious actors are prone for the small A5 ruleset without needing a
	# second, redundant condition entry in their serialized state.
	return conditions.has(&"prone") or conditions.has(&"unconscious")


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
	}


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
	return actor
