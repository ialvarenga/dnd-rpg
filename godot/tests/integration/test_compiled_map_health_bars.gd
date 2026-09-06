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
	player_state.position = Vector3.ZERO
	target_state.position = Vector3(1.0, 0.0, 0.0)
	target_state.armor_class = 0
	var result: ResolutionResult = map.session.submit_ability(map.character.actor_id, &"basic_attack", target_id, Vector3.INF)
	var expected_fraction := clampf(float(target_state.hp) / maxf(1.0, float(target_state.max_hp)), 0.0, 1.0)
	_expect(result.events.any(func(event: Event): return event.type == &"damage_taken"), "test attack did not apply damage through EncounterSession", failures)
	_expect(is_equal_approx(target_bar.fraction, expected_fraction), "WorldHealthBar did not reflect authoritative HP after session state_changed", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
