class_name TestHelpers
extends RefCounted

static func make_battle(seed: int = 42) -> BattleState:
	var state := BattleState.new()
	state.phase = &"combat"
	state.rng_seed = seed
	state.rng_state = seed
	state.initiative_order = [1, 2]

	var hero := ActorState.new()
	hero.id = 1
	hero.side = &"heroes"
	hero.position = Vector3.ZERO
	hero.hp = 20
	hero.max_hp = 20
	hero.armor_class = 12
	hero.movement_speed = 9.0
	hero.movement_remaining = 9.0
	hero.attack_bonus = 5
	hero.damage_die = 6
	hero.damage_modifier = 3
	state.actors[hero.id] = hero

	var enemy := ActorState.new()
	enemy.id = 2
	enemy.side = &"enemies"
	enemy.position = Vector3(1.0, 0.0, 0.0)
	enemy.hp = 20
	enemy.max_hp = 20
	enemy.armor_class = 10
	enemy.movement_speed = 9.0
	enemy.movement_remaining = 9.0
	enemy.attack_bonus = 4
	enemy.damage_die = 6
	enemy.damage_modifier = 2
	state.actors[enemy.id] = enemy
	return state


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

