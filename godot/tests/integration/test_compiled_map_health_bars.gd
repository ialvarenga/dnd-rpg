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
	_test_exploration_destination_marker(map, failures)
	_test_state_changed_health_update(map, failures)
	await _test_approach_then_attack(map, failures)
	await _test_container_highlight_and_approach(map, failures)
	map.queue_free()
	return {"name": "integration/test_compiled_map_health_bars", "failures": failures}


func _test_health_bar_creation(map: CompiledMapController, failures: Array[String]) -> void:
	_expect(map.character.get_node_or_null("WorldHealthBar") is WorldHealthBar, "player CharacterView has no WorldHealthBar", failures)
	_expect(not map.hostile_views.is_empty(), "compiled map spawned no hostile CharacterView to test", failures)
	for hostile in map.hostile_views.values():
		var view := hostile as CharacterView
		_expect(view != null and view.get_node_or_null("WorldHealthBar") is WorldHealthBar, "spawned hostile CharacterView has no WorldHealthBar", failures)
	var has_ranged_enemy := false
	for actor_id in map.hostile_views:
		var actor := map.battle_state.actors[int(actor_id)] as ActorState
		has_ranged_enemy = has_ranged_enemy or Equipment.is_ranged_weapon(actor, DefinitionLibrary.get_default())
	_expect(has_ranged_enemy, "shipping map did not place its archer on the Emberwatch rise", failures)
	_expect(map._interactable_highlights.size() == map.battle_state.interactables.size(), "not every pickup and container received an interaction highlight", failures)
	for highlight in map._interactable_highlights.values():
		_expect((highlight as MeshInstance3D).visible == false, "interaction highlight was visible before hover or selection", failures)


func _test_exploration_destination_marker(map: CompiledMapController, failures: Array[String]) -> void:
	var target := map.character.global_position + Vector3(1.0, -1.0, 0.0)
	map._show_exploration_destination(target)
	_expect(map._destination_marker != null and map._destination_marker.visible, "compiled map did not show an exploration destination marker", failures)
	map.battle_state.phase = &"combat"
	map._process(0.0)
	_expect(not map._destination_marker.visible, "exploration destination marker remained visible in combat", failures)
	map.battle_state.phase = &"exploration"


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
	# _test_state_changed_health_update just hit this same actor with AC forced
	# to 0, and a light stat block can be downed by that one roll. Restore it, so
	# this test measures approach-then-attack rather than the previous damage roll.
	target.hp = target.max_hp
	target.condition_states.clear()
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


func _test_container_highlight_and_approach(map: CompiledMapController, failures: Array[String]) -> void:
	var container: InteractableState
	for interactable in map.battle_state.interactables.values():
		if (interactable as InteractableState).type in [&"chest", &"barrel"]:
			container = interactable as InteractableState
			break
	if container == null:
		failures.append("compiled map spawned no container to test")
		return
	var player := map.battle_state.actors[map.character.actor_id] as ActorState
	var enemy_id: int = map.hostile_views.keys()[0]
	var requested_start := container.position + Vector3(4.0, 1.0, 0.0)
	var start := map.nav_provider.snap_to_navmesh(requested_start)
	player.position = start
	player.movement_remaining = player.movement_speed
	player.action_available = true
	player.condition_states.clear()
	map.character.synchronize_to_authoritative_position(start)
	map.battle_state.phase = &"combat"
	map.battle_state.initiative_order = [player.id, enemy_id]
	map.battle_state.current_turn_index = 0
	var inventory_before := player.inventory.size()
	map._approach_interactable(container.id)
	var highlight := map._interactable_highlights.get(container.id) as MeshInstance3D
	_expect(highlight != null and highlight.visible, "clicked container did not show its interaction highlight", failures)
	_expect(not map._pending_interactable_id.is_empty(), "out-of-range container click did not queue its interaction", failures)
	_expect(player.action_available and player.inventory.size() == inventory_before, "container interaction executed before approach movement completed", failures)
	_expect(player.position.distance_to(container.position) <= container.interact_range + 0.001, "container approach did not end inside interaction range", failures)
	for _frame in range(240):
		if not map.character.is_moving():
			break
		await get_tree().physics_frame
	_expect(map._pending_interactable_id.is_empty(), "queued container interaction did not complete after movement", failures)
	_expect(not player.action_available and player.inventory.size() == inventory_before + 1, "queued container loot was not collected after movement", failures)
	_expect(container.state == &"open", "looted container did not update authoritative interactable state", failures)
	_expect(map._interactable_highlights.has(container.id) and not (map._interactable_highlights[container.id] as MeshInstance3D).visible, "looted container did not retain a hidden, retry-safe highlight", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
