class_name TestHelpers
extends RefCounted

static func make_battle(seed: int = 42) -> BattleState:
	var state := BattleState.new()
	state.phase = &"combat"
	state.rng_seed = seed
	state.rng_state = seed
	state.initiative_order = [1, 2]

	# Derived through AttackMath: the hero attacks at +5 for 1d6+3 against AC
	# 12 (Str 16 scimitar, studded leather) and the enemy at +4 for 1d6+2
	# against AC 10 (Str 14 scimitar, unarmored). Dexterity stays 10 so
	# initiative is decided by the dice alone.
	var hero := ActorState.new()
	hero.id = 1
	hero.side = &"heroes"
	hero.position = Vector3.ZERO
	hero.hp = 20
	hero.max_hp = 20
	hero.strength = 16
	hero.weapon_proficiencies = [&"simple", &"martial"]
	hero.equipment_slots = {&"weapon": &"scimitar", &"armor": &"studded_leather"}
	hero.movement_speed = 9.0
	hero.movement_remaining = 9.0
	state.actors[hero.id] = hero

	var enemy := ActorState.new()
	enemy.id = 2
	enemy.side = &"enemies"
	enemy.position = Vector3(1.0, 0.0, 0.0)
	enemy.hp = 20
	enemy.max_hp = 20
	enemy.strength = 14
	enemy.weapon_proficiencies = [&"simple", &"martial"]
	enemy.equipment_slots = {&"weapon": &"scimitar"}
	enemy.movement_speed = 9.0
	enemy.movement_remaining = 9.0
	state.actors[enemy.id] = enemy
	return state


## Every attack `actor` makes hits unless its d20 shows a natural 1. Only the
## attack roll changes: proficiency never reaches damage.
static func guarantee_hits(actor: ActorState) -> void:
	actor.proficiency_bonus = 100


## Unarms `actor` so each hit deals exactly `amount` damage: an unarmed strike
## is 1 + Strength modifier with no die, even on a critical hit.
static func set_fixed_damage(actor: ActorState, amount: int) -> void:
	actor.equipment_slots.erase(&"weapon")
	actor.strength = 10 + 2 * (amount - 1)


## Strips `actor` down to AC 5 (unarmored, Dexterity 1).
static func make_easy_target(actor: ActorState) -> void:
	actor.equipment_slots.erase(&"armor")
	actor.dexterity = 1


static func apply_result(state: BattleState, result: ResolutionResult) -> void:
	for event in result.events:
		Resolver.apply(state, event)
	state.rng_state = result.next_rng_state


static func event_log_entry(result: ResolutionResult) -> String:
	var entries: Array[String] = []
	for event in result.events:
		entries.append("%s:%s" % [event.type, JSON.stringify(_stable_event_data(event.data))])
	entries.append("rng:%d" % result.next_rng_state)
	return "|".join(entries)


static func _stable_event_data(data: Dictionary) -> Dictionary:
	var stable := {}
	var keys: Array = data.keys()
	keys.sort()
	for key_variant in keys:
		var key: String = str(key_variant)
		stable[key] = _stable_value(data[key_variant])
	return stable


static func _stable_value(value: Variant) -> Variant:
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is PackedVector3Array:
		var points: Array = []
		for point in value:
			points.append([point.x, point.y, point.z])
		return points
	if value is Dictionary:
		return _stable_event_data(value)
	return value

