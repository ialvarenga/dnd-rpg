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

