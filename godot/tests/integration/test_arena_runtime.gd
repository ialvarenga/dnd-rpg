class_name TestArenaRuntime
extends Node


func run() -> Dictionary:
	var failures: Array[String] = []
	var arena := preload("res://scenes/test_arena.tscn").instantiate()
	get_tree().root.add_child(arena)
	for _frame in range(5):
		await get_tree().physics_frame
	var controller: TestArenaController = arena
	var player: CharacterView = arena.get_node("PlayerCharacter")
	var event_player: EventPlayer = arena.get_node("EventPlayer")
	var navigation_ready: bool = await _wait_for_navigation(controller, player, Vector3(-9.0, 0.1, -2.0), 120)
	_expect(navigation_ready, "NavigationRegion3D did not synchronize for the A2 runtime test", failures)
	if not navigation_ready:
		arena.queue_free()
		return {"name": "integration/test_arena_runtime", "failures": failures}
	await _test_preview_and_clamped_combat_movement(controller, player, event_player, failures)
	_test_command_event_view_pipeline(controller, player, event_player, failures)
	await _test_target_replacement(controller, player, event_player, failures)
	await _test_obstacle_route(controller, player, event_player, failures)
	await _test_rejected_and_invalid_clicks(controller, player, failures)
	arena.queue_free()
	return {"name": "integration/test_arena_runtime", "failures": failures}


func _test_preview_and_clamped_combat_movement(controller: TestArenaController, player: CharacterView, event_player: EventPlayer, failures: Array[String]) -> void:
	var actor: ActorState = controller.battle_state.actors[player.actor_id]
	controller.battle_state.phase = &"combat"
	controller.battle_state.initiative_order = [player.actor_id]
	controller.battle_state.current_turn_index = 0
	var target := Vector3(-8.0, player.global_position.y, 0.0)
	actor.movement_remaining = 0.0
	var state_before_zero_budget := JSON.stringify(controller.battle_state.stable_snapshot()).md5_text()
	var position_before_zero_budget := player.global_position
	controller.handle_terrain_click(target)
	_expect(controller.last_resolution.events.size() == 1 and controller.last_resolution.events[0].data["reason"] == &"no_movement_remaining", "zero-budget combat move was not rejected", failures)
	_expect(JSON.stringify(controller.battle_state.stable_snapshot()).md5_text() == state_before_zero_budget, "zero-budget rejection applied BattleState", failures)
	_expect(player.global_position.distance_to(position_before_zero_budget) < 0.001 and not player.is_moving(), "zero-budget rejection moved CharacterView", failures)
	var empty_target: Vector3 = (controller.battle_state.actors[player.actor_id] as ActorState).position
	controller.handle_terrain_click(empty_target)
	_expect(controller.last_resolution.events.size() == 1 and controller.last_resolution.events[0].data["reason"] == &"no_movement", "empty movement segment was not rejected", failures)
	_expect(player.global_position.distance_to(position_before_zero_budget) < 0.001 and not player.is_moving(), "empty movement segment moved CharacterView", failures)

	actor.movement_remaining = 2.0
	var state_before_preview := JSON.stringify(controller.battle_state.stable_snapshot()).md5_text()
	var position_before_preview := player.global_position
	var preview := controller.preview_move_target(target)
	_expect(preview.events.size() == 2 and preview.events[0].type == &"movement_segment", "combat preview did not resolve movement", failures)
	_expect(JSON.stringify(controller.battle_state.stable_snapshot()).md5_text() == state_before_preview, "preview applied BattleState", failures)
	_expect(player.global_position.distance_to(position_before_preview) < 0.001 and not player.is_moving(), "preview moved CharacterView", failures)

	controller.handle_terrain_click(target)
	_expect(controller.last_resolution.events.size() == 2 and controller.last_resolution.events[0].data["clamped"], "confirmed combat movement was not clamped", failures)
	var authoritative_position: Vector3 = (controller.battle_state.actors[player.actor_id] as ActorState).position
	_expect(authoritative_position.distance_to(Vector3(-10.0, player.global_position.y, 0.0)) < 0.001, "confirmed clamp did not apply the authoritative endpoint", failures)
	var playback_path := event_player.get_resolved_path(player.actor_id)
	_expect(not playback_path.is_empty() and playback_path[playback_path.size() - 1].distance_to(authoritative_position) < 0.001, "clamped event did not reach EventPlayer with its authoritative endpoint", failures)
	await _wait_for_destination(player, 240)
	_expect(player.destination_state == &"reached" and player.global_position.distance_to(authoritative_position) < 0.001, "CharacterView did not synchronize to clamped authoritative position", failures)

	controller.battle_state.phase = &"exploration"
	actor.movement_remaining = actor.movement_speed


func _test_command_event_view_pipeline(controller: TestArenaController, player: CharacterView, event_player: EventPlayer, failures: Array[String]) -> void:
	var start := player.global_position
	controller.handle_terrain_click(Vector3(-9.0, 0.1, -2.0))
	_expect(controller.last_command != null and controller.last_command.type == &"move", "terrain input did not create a move Command", failures)
	_expect(controller.last_resolution != null and controller.last_resolution.events[0].type == &"movement_segment", "move Command did not resolve to movement event", failures)
	_expect(event_player.last_played_events.size() > 0 and event_player.last_played_events[0].type == &"movement_segment", "accepted movement did not reach EventPlayer", failures)
	_expect(player.is_moving(), "EventPlayer did not start CharacterView movement", failures)
	var authoritative_position: Vector3 = (controller.battle_state.actors[player.actor_id] as ActorState).position
	_expect(authoritative_position != start and player.global_position == start, "state was not applied before visual interpolation", failures)


func _test_target_replacement(controller: TestArenaController, player: CharacterView, event_player: EventPlayer, failures: Array[String]) -> void:
	for _frame in range(4):
		await get_tree().physics_frame
	var visible_before_replace := player.global_position
	controller.handle_terrain_click(Vector3(-12.0, 0.1, -6.0))
	_expect(controller.last_command != null and controller.last_command.target_pos == Vector3(-12.0, 0.1, -6.0), "replacement did not create the latest Command", failures)
	var expected_path := event_player.get_resolved_path(player.actor_id)
	_expect(not expected_path.is_empty(), "replacement Command produced no EventPlayer path", failures)
	_expect(expected_path[0].distance_to(visible_before_replace) < 0.35, "replacement EventPlayer path did not rebase to CharacterView", failures)
	await get_tree().physics_frame
	_expect(player.get_debug_velocity().z < -0.01, "replacement did not interrupt playback toward the new target", failures)
	await _wait_for_destination(player, 360)
	var authoritative_position: Vector3 = (controller.battle_state.actors[player.actor_id] as ActorState).position
	_expect(player.destination_state == &"reached" and player.global_position.distance_to(authoritative_position) < 0.001, "replacement path did not synchronize CharacterView", failures)


func _test_obstacle_route(controller: TestArenaController, player: CharacterView, event_player: EventPlayer, failures: Array[String]) -> void:
	controller.handle_terrain_click(Vector3(12.0, 0.1, 0.0))
	var path := event_player.get_resolved_path(player.actor_id)
	var routed_around_barrier := false
	for point in path:
		if absf(point.z) > 6.5:
			routed_around_barrier = true
			break
	await _wait_for_destination(player, 600)
	var authoritative_position: Vector3 = (controller.battle_state.actors[player.actor_id] as ActorState).position
	if player.destination_state != &"reached" or player.global_position.distance_to(authoritative_position) > 0.001 or not routed_around_barrier:
		failures.append("main-scene obstacle route through A2 pipeline failed: state=%s position=%s path=%s" % [player.destination_state, player.global_position, path])


func _test_rejected_and_invalid_clicks(controller: TestArenaController, player: CharacterView, failures: Array[String]) -> void:
	var before := player.global_position
	controller.handle_terrain_click(Vector3(50.0, 0.1, 0.0))
	_expect(controller.last_command != null and controller.last_command.type == &"move", "non-navigable click did not create a Command", failures)
	_expect(controller.last_resolution.events.size() == 1 and controller.last_resolution.events[0].type == &"command_rejected", "non-navigable click was not rejected", failures)
	for _frame in range(10):
		await get_tree().physics_frame
	_expect(player.global_position.distance_to(before) < 0.001 and not player.is_moving(), "rejected command altered CharacterView", failures)
	controller.handle_terrain_click(null)
	_expect(controller.last_input_status == &"outside_terrain" and player.global_position.distance_to(before) < 0.001, "invalid terrain click altered CharacterView", failures)


func _wait_for_destination(player: CharacterView, max_frames: int) -> void:
	for _frame in range(max_frames):
		await get_tree().physics_frame
		if player.destination_state == &"reached":
			return


func _wait_for_navigation(controller: TestArenaController, player: CharacterView, target: Vector3, max_frames: int) -> bool:
	for _frame in range(max_frames):
		if controller.nav_provider.is_reachable(player.global_position, target):
			return true
		await get_tree().physics_frame
	return false


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
