class_name TestGameplayOutcomeRuntime
extends Node


func run() -> Dictionary:
	var failures: Array[String] = []
	var map := preload("res://scenes/compiled_forest_map.tscn").instantiate() as CompiledMapController
	get_tree().root.add_child(map)
	for _frame in range(8):
		await get_tree().process_frame
	if map.session == null or map.character == null or map.encounter_definitions.is_empty():
		failures.append("compiled map did not finish gameplay-outcome setup")
		map.queue_free()
		return {"name": "integration/test_gameplay_outcome_runtime", "failures": failures}

	var resolved_types: Array[StringName] = []
	map.session.events_resolved.connect(func(events: Array[Event]):
		for event in events:
			resolved_types.append(event.type)
	)
	var encounter_id: String = map.encounter_definitions.keys()[0]
	var encounter: Dictionary = map.encounter_definitions[encounter_id]
	var enemy_id: int = -1
	for actor_id in encounter.combatant_ids:
		if map.hostile_views.has(actor_id):
			enemy_id = actor_id
			break
	if enemy_id < 0:
		failures.append("authored encounter had no runtime hostile participant")
		map.queue_free()
		return {"name": "integration/test_gameplay_outcome_runtime", "failures": failures}

	var start := Command.create(&"start_combat", enemy_id)
	start.metadata = {"encounter_id": encounter_id, "participant_actor_ids": encounter.combatant_ids.duplicate()}
	map._start_encounter(start, true)
	var initial_combat_snapshot := JSON.stringify(map.battle_state.stable_snapshot())
	var pickup := _first_interactable(map, &"pickup")
	var chest := _first_interactable(map, &"chest")
	var pickup_view := map.compilation.root.get_node_or_null(NodePath(pickup.id)) if pickup != null else null

	# Exercise authoritative inventory and interactable mutations after the
	# checkpoint. Retry must reverse both container and pickup collection.
	if pickup != null:
		_prepare_player_interaction(map, pickup)
		map._resolve_interaction(pickup.id)
	if chest != null:
		_prepare_player_interaction(map, chest)
		map._resolve_interaction(chest.id)
	var player := map.battle_state.actors[map.character.actor_id] as ActorState
	_expect(pickup == null or pickup.state == &"collected", "pickup did not mutate before retry regression", failures)
	_expect(chest == null or chest.state == &"open" and chest.contents.is_empty(), "chest loot did not mutate before retry regression", failures)

	# Seed pending presentation work to prove defeat actively cancels it.
	map._pending_interactable_id = pickup.id if pickup != null else "pending"
	map._pending_targeted_action = {"ability_id": &"basic_attack", "target_id": enemy_id}
	map._targeting_ability_id = &"basic_attack"
	map.character.play_movement(PackedVector3Array([map.character.global_position, map.character.global_position + Vector3(4.0, 0.0, 0.0)]), map.character.global_position + Vector3(4.0, 0.0, 0.0))

	player.hp = 5
	var enemy := map.battle_state.actors[enemy_id] as ActorState
	TestHelpers.guarantee_hits(enemy)
	TestHelpers.set_fixed_damage(enemy, 6)
	player.position = enemy.position + Vector3(1.25, 0.0, 0.0)
	map.character.synchronize_to_authoritative_position(player.position)
	map.character.play_movement(PackedVector3Array([map.character.global_position, map.character.global_position + Vector3(4.0, 0.0, 0.0)]), map.character.global_position + Vector3(4.0, 0.0, 0.0))
	map.battle_state.initiative_order = [enemy_id, player.id]
	map.battle_state.current_turn_index = 0
	var lethal := Command.create(&"basic_attack", enemy_id)
	lethal.target_id = player.id
	var defeat: ResolutionResult = map.session.submit_command(lethal)
	map.event_player.play_events(defeat.events)

	_expect(_event_count(defeat.events, &"combat_ended") == 1, "decisive runtime attack did not end combat exactly once", failures)
	_expect(map.battle_state.phase == &"game_over" and map.battle_state.game_outcome == &"defeat", "runtime defeat did not remain in game_over", failures)
	_expect(map.hud.outcome_overlay.visible and map.hud.outcome_overlay.outcome == &"defeat", "defeat overlay did not appear", failures)
	_expect(not map.character.is_moving() and map.character._is_dead, "defeat did not stop movement and play the death presentation", failures)
	_expect(map._pending_interactable_id.is_empty() and map._pending_targeted_action.is_empty() and map._targeting_ability_id == &"", "defeat did not clear queued world actions", failures)

	var locked_snapshot := JSON.stringify(map.battle_state.stable_snapshot())
	for _tick in range(3):
		map._process(1.0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(10.0, 10.0)
	map._unhandled_input(click)
	_expect(JSON.stringify(map.battle_state.stable_snapshot()) == locked_snapshot, "AI, detection, or world input changed state after defeat", failures)
	_expect(resolved_types.count(&"combat_ended") == 1 and resolved_types.count(&"combat_started") == 1, "hostile detection restarted combat after defeat", failures)

	map._on_retry_requested()
	_expect(JSON.stringify(map.battle_state.stable_snapshot()) == initial_combat_snapshot, "retry did not deterministically restore and restart the encounter checkpoint", failures)
	_expect(not map.hud.outcome_overlay.visible and not map.character._is_dead, "retry did not reset outcome and character presentation", failures)
	_expect(pickup == null or (map.battle_state.interactables[pickup.id] as InteractableState).state == &"ready", "retry did not restore pickup state", failures)
	_expect(chest == null or (map.battle_state.interactables[chest.id] as InteractableState).state == &"closed", "retry did not restore chest state", failures)
	_expect(pickup_view == null or (pickup_view as Node3D).visible, "retry did not restore collected pickup presentation", failures)
	var health_bar := map.character.get_node_or_null("WorldHealthBar") as WorldHealthBar
	_expect(health_bar != null and is_equal_approx(health_bar.fraction, 1.0), "retry did not synchronize the player health bar", failures)

	map.queue_free()
	return {"name": "integration/test_gameplay_outcome_runtime", "failures": failures}


func _first_interactable(map: CompiledMapController, type: StringName) -> InteractableState:
	for interactable in map.battle_state.interactables.values():
		if (interactable as InteractableState).type == type:
			return interactable as InteractableState
	return null


func _prepare_player_interaction(map: CompiledMapController, interactable: InteractableState) -> void:
	var player := map.battle_state.actors[map.character.actor_id] as ActorState
	player.position = interactable.position
	player.action_available = true
	map.battle_state.initiative_order = [player.id]
	map.battle_state.current_turn_index = 0
	map.character.synchronize_to_authoritative_position(player.position)


func _event_count(events: Array[Event], event_type: StringName) -> int:
	var count := 0
	for event in events:
		if event.type == event_type:
			count += 1
	return count


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
