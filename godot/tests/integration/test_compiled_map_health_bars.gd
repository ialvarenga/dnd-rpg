class_name TestCompiledMapHealthBars
extends Node


func run() -> Dictionary:
	var failures: Array[String] = []
	var map := preload("res://scenes/compiled_forest_map.tscn").instantiate() as CompiledMapController
	get_tree().root.add_child(map)
	for _frame in range(8):
		await get_tree().process_frame
	if map.session == null or map.character == null:
		failures.append("compiled map did not finish encounter setup")
		map.queue_free()
		return {"name": "integration/test_compiled_map_health_bars", "failures": failures}

	_test_health_bar_creation(map, failures)
	_test_state_changed_health_update(map, failures)
	await _test_approach_then_attack(map, failures)
	map.queue_free()
	return {"name": "integration/test_compiled_map_health_bars", "failures": failures}


func _test_health_bar_creation(map: CompiledMapController, failures: Array[String]) -> void:
	_expect(map.character.get_node_or_null("WorldHealthBar") is WorldHealthBar, "player CharacterView has no WorldHealthBar", failures)
	_expect(not map.hostile_views.is_empty(), "compiled map spawned no hostile CharacterView to test", failures)
	for hostile in map.hostile_views.values():
		var view := hostile as CharacterView
		_expect(view != null and view.get_node_or_null("WorldHealthBar") is WorldHealthBar, "spawned hostile CharacterView has no WorldHealthBar", failures)


func _test_state_changed_health_update(map: CompiledMapController, failures: Array[String]) -> void:
	if map.hostile_views.is_empty():
		return
	var target_id: int = map.hostile_views.keys()[0]
	var target_state := map.battle_state.actors[target_id] as ActorState
	var player_state := map.battle_state.actors[map.character.actor_id] as ActorState
	var target_view := map.hostile_views[target_id] as CharacterView
	var target_bar := target_view.get_node_or_null("WorldHealthBar") as WorldHealthBar
	if target_state == null or player_state == null or target_bar == null:
		failures.append("health-bar update prerequisites were unavailable")
		return
	map.battle_state.phase = &"combat"
	map.battle_state.initiative_order = [map.character.actor_id, target_id]
	map.battle_state.current_turn_index = 0
	# Exercise the authored enemy position. MapCompiler also creates a visual
	# anchor there, and that anchor must not leave an invisible static blocker
	# which rejects an otherwise legal adjacent attack as no_line_of_sight.
	player_state.position = target_state.position + Vector3(1.25, 0.0, 0.0)
	target_state.armor_class = 0
	var result: ResolutionResult = map.session.submit_ability(map.character.actor_id, &"basic_attack", target_id, Vector3.INF)
	var expected_fraction := clampf(float(target_state.hp) / maxf(1.0, float(target_state.max_hp)), 0.0, 1.0)
	_expect(not result.events.any(func(event: Event): return event.type == &"command_rejected" and event.data.get("reason") == &"no_line_of_sight"), "authored enemy anchor blocked line of sight to an adjacent target", failures)
	_expect(result.events.any(func(event: Event): return event.type == &"damage_taken"), "test attack did not apply damage through EncounterSession", failures)
	_expect(is_equal_approx(target_bar.fraction, expected_fraction), "WorldHealthBar did not reflect authoritative HP after session state_changed", failures)


func _test_approach_then_attack(map: CompiledMapController, failures: Array[String]) -> void:
	if map.hostile_views.is_empty():
		return
	var target_id: int = map.hostile_views.keys()[0]
	var target := map.battle_state.actors[target_id] as ActorState
	var player := map.battle_state.actors[map.character.actor_id] as ActorState
	var start := target.position + Vector3(4.0, 0.0, 0.0)
	player.position = start
	player.movement_remaining = player.movement_speed
	player.action_available = true
	map.character.synchronize_to_authoritative_position(start)
	map.battle_state.phase = &"combat"
	map.battle_state.initiative_order = [player.id, target.id]
	map.battle_state.current_turn_index = 0
	target.armor_class = 0
	var hp_before := target.hp
	map._targeting_ability_id = &"basic_attack"
	map._submit_targeted_ability(target.id)
	_expect(not map._pending_targeted_action.is_empty(), "out-of-range click did not queue the targeted action", failures)
	_expect(player.action_available and target.hp == hp_before, "targeted action executed before approach movement completed", failures)
	_expect(player.position.distance_to(target.position) <= AbilityTargeting.target_range(DefinitionLibrary.get_default(), &"basic_attack") + AbilityTargeting.RANGE_EPSILON, "approach movement did not end within ability range", failures)
	for _frame in range(240):
		if not map.character.is_moving():
			break
		await get_tree().physics_frame
	_expect(map._pending_targeted_action.is_empty(), "queued targeted action did not complete after movement", failures)
	_expect(not player.action_available and target.hp < hp_before, "queued targeted action was not performed after movement", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
