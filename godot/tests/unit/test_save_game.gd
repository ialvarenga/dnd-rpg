class_name TestSaveGame
extends RefCounted

static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_round_trip_preserves_mid_combat_state(failures)
	_test_from_dict_defaults_missing_fields(failures)
	_test_is_compatible_detects_version_drift(failures)
	return {"name": "unit/test_save_game", "failures": failures}


## Builds a state that looks like a real mid-combat save point: partially
## spent turn resources, a condition, a spent reaction, movement already
## consumed, and non-default world_flags/world_state -- exercising every
## field the A8 DoD lists (HP, positions, turn, movement, action resources,
## conditions, reactions, RNG state).
static func _mid_combat_state() -> BattleState:
	var state := TestHelpers.make_battle(1234)
	state.phase = &"combat"
	state.round_number = 3
	state.current_turn_index = 1
	state.rng_state = 987654321
	state.world_flags = {"door_north_open": true, "turns_elapsed": 3}

	var hero: ActorState = state.actors[1]
	hero.hp = 11
	hero.position = Vector3(4.5, 0.0, -2.25)
	hero.movement_remaining = 2.5
	hero.action_available = false
	hero.bonus_action_available = false
	hero.reaction_available = false
	hero.disengaged = true
	hero.conditions.append(&"poisoned")

	var enemy: ActorState = state.actors[2]
	enemy.hp = 4
	enemy.conditions.append(&"prone")
	return state


static func _test_round_trip_preserves_mid_combat_state(failures: Array[String]) -> void:
	var state := _mid_combat_state()
	var original := SaveGame.create(state, "test_arena", {"chest_opened": false})
	var restored := SaveGame.from_dict(original.to_dict())

	_expect(restored.map_id == "test_arena", "map_id did not round-trip", failures)
	_expect(restored.schema_version == SaveGame.SCHEMA_VERSION, "schema_version did not round-trip", failures)
	_expect(restored.rules_version == Resolver.RULES_VERSION, "rules_version did not round-trip", failures)
	_expect(restored.content_version == DefinitionLibrary.CONTENT_VERSION, "content_version did not round-trip", failures)
	_expect(restored.world_state.get("chest_opened") == false, "world_state did not round-trip", failures)

	var restored_state := restored.battle_state
	_expect(restored_state.round_number == 3, "round_number did not round-trip", failures)
	_expect(restored_state.current_turn_index == 1, "current_turn_index did not round-trip", failures)
	_expect(restored_state.rng_state == 987654321, "rng_state did not round-trip", failures)
	_expect(restored_state.world_flags.get("door_north_open") == true, "world_flags did not round-trip", failures)

	var restored_hero: ActorState = restored_state.actors[1]
	_expect(restored_hero.hp == 11, "actor HP did not round-trip", failures)
	_expect(restored_hero.position.is_equal_approx(Vector3(4.5, 0.0, -2.25)), "actor position did not round-trip", failures)
	_expect(is_equal_approx(restored_hero.movement_remaining, 2.5), "movement_remaining did not round-trip", failures)
	_expect(not restored_hero.action_available, "action_available did not round-trip", failures)
	_expect(not restored_hero.bonus_action_available, "bonus_action_available did not round-trip", failures)
	_expect(not restored_hero.reaction_available, "reaction_available did not round-trip", failures)
	_expect(restored_hero.disengaged, "disengaged did not round-trip", failures)
	_expect(restored_hero.conditions.has(&"poisoned"), "conditions did not round-trip", failures)

	var restored_enemy: ActorState = restored_state.actors[2]
	_expect(restored_enemy.hp == 4, "second actor HP did not round-trip", failures)
	_expect(restored_enemy.conditions.has(&"prone"), "second actor conditions did not round-trip", failures)

	_expect(
		JSON.stringify(original.to_dict()) == JSON.stringify(restored.to_dict()),
		"save round-trip is not byte-stable",
		failures,
	)


static func _test_from_dict_defaults_missing_fields(failures: Array[String]) -> void:
	var restored := SaveGame.from_dict({})
	_expect(restored.schema_version == SaveGame.SCHEMA_VERSION, "missing schema_version should default", failures)
	_expect(restored.map_id == "", "missing map_id should default to empty string", failures)
	_expect(restored.battle_state != null, "missing battle_state should still produce a usable BattleState", failures)
	_expect(restored.world_state.is_empty(), "missing world_state should default to an empty dictionary", failures)


static func _test_is_compatible_detects_version_drift(failures: Array[String]) -> void:
	var save := SaveGame.create(_mid_combat_state())
	_expect(save.is_compatible(), "freshly created save should be compatible with current versions", failures)
	_expect(not save.is_compatible(Resolver.RULES_VERSION + 1, DefinitionLibrary.CONTENT_VERSION), "rules_version drift should be detected", failures)
	_expect(not save.is_compatible(Resolver.RULES_VERSION, DefinitionLibrary.CONTENT_VERSION + 1), "content_version drift should be detected", failures)

	var stale := SaveGame.from_dict(save.to_dict())
	stale.schema_version = SaveGame.SCHEMA_VERSION + 1
	_expect(not stale.is_compatible(), "schema_version drift should be detected", failures)


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
