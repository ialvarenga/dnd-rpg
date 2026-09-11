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
	_test_music_director(controller, failures)
	await _test_hud_runtime(controller, arena.get_node("HudRoot"), player, failures)
	_test_hud_input_routing(controller, arena.get_node("HudRoot"), failures)
	await _test_preview_and_clamped_combat_movement(controller, player, event_player, failures)
	_test_command_event_view_pipeline(controller, player, event_player, failures)
	await _test_animation_movement_transition(controller, player, event_player, failures)
	await _test_knockdown_sequence(controller, player, event_player, failures)
	await _test_target_replacement(controller, player, event_player, failures)
	await _test_obstacle_route(controller, player, event_player, failures)
	await _test_rejected_and_invalid_clicks(controller, player, failures)
	_test_chest_interaction(controller, failures)
	_test_camera_pan_direction(arena.get_node("PlayerCharacter/CameraRig"), failures)
	arena.queue_free()
	return {"name": "integration/test_arena_runtime", "failures": failures}


func _test_music_director(controller: TestArenaController, failures: Array[String]) -> void:
	var music := controller.get_node_or_null("MusicDirector") as MusicDirector
	var player := music.get_node_or_null("AudioStreamPlayer") as AudioStreamPlayer if music != null else null
	_expect(music != null and player != null, "test arena has no MusicDirector presentation node", failures)
	if music == null or player == null:
		return
	_expect(player.stream == MusicDirector.AMBIENT_TRACKS[music.ambient_track_id], "test arena did not start the selected ambient cue", failures)
	controller.battle_state.phase = &"combat"
	controller._process(0.0)
	_expect(player.stream == MusicDirector.BATTLE_TRACKS[music.battle_track_id], "MusicDirector did not follow the test arena combat phase", failures)
	controller.battle_state.phase = &"exploration"
	controller._process(0.0)


func _test_hud_runtime(controller: TestArenaController, hud: HudRoot, player: CharacterView, failures: Array[String]) -> void:
	# The signal-driven HUD has rendered the initial state after bind(). A real
	# UI click is consuming (STOP), while decorative layout remains pass-through.
	var hp_label: Label = hud.get_node("Margin/Layout/ActorPortrait/Margin/Rows/HPText")
	_expect(hp_label.text.begins_with("HP"), "HUD did not render actor data after bind", failures)
	var before := (controller.battle_state.actors[player.actor_id] as ActorState).movement_remaining
	controller.session.submit_move(player.actor_id, player.global_position + Vector3(0.5, 0.0, 0.0), player.global_position)
	await get_tree().process_frame
	var move: ProgressBar = hud.get_node("Margin/Layout/MovementControls/ResourcePips/Move")
	_expect(move.value <= 100.0 and (controller.battle_state.actors[player.actor_id] as ActorState).movement_remaining <= before, "HUD did not sync pips after state_changed", failures)
	var end_turn: Button = hud.get_node("Margin/Layout/EndTurn")
	_expect(end_turn.mouse_filter == Control.MOUSE_FILTER_STOP, "HUD controls must consume clicks before terrain input", failures)
	_expect(hud.hotbar.mouse_filter == Control.MOUSE_FILTER_IGNORE, "empty hotbar space should remain pass-through", failures)
	for button in hud.hotbar.get_children():
		_expect((button as Control).mouse_filter == Control.MOUSE_FILTER_STOP, "hotbar buttons must consume clicks before terrain input", failures)
		_expect((button as Button).get_theme_constant(&"icon_max_width") == 24, "hotbar SVG icons must be constrained to HUD scale", failures)
	_expect(end_turn.get_theme_constant(&"icon_max_width") == 28, "end-turn SVG icon must be constrained to HUD scale", failures)


func _test_hud_input_routing(controller: TestArenaController, hud: HudRoot, failures: Array[String]) -> void:
	for slot in range(6):
		_expect(InputMap.has_action(StringName("hotbar_%d" % (slot + 1))), "missing hotbar_%d input action" % (slot + 1), failures)
	_expect(InputMap.has_action(&"tactical_end_turn"), "missing tactical_end_turn input action", failures)
	_expect(InputMap.has_action(&"tactical_cancel"), "missing tactical_cancel input action", failures)
	var ability_requests: Array[StringName] = []
	var end_turn_requests := [0]
	hud.ability_requested.connect(func(ability_id): ability_requests.append(ability_id))
	hud.end_turn_requested.connect(func(): end_turn_requests[0] += 1)
	var first_button := hud.hotbar.get_child(0) as AbilityButton
	first_button.disabled = false
	_send_hud_action(hud, &"hotbar_1")
	_expect(ability_requests == [&"basic_attack"], "hotbar input did not route through HudRoot", failures)
	_send_hud_action(hud, &"tactical_end_turn")
	_expect(end_turn_requests[0] == 1, "end-turn input did not route through HudRoot", failures)
	var overlay_was_visible: bool = (controller.get_node("DebugOverlay") as CanvasLayer).visible
	_send_hud_action(hud, &"tactical_cancel")
	_expect((controller.get_node("DebugOverlay") as CanvasLayer).visible != overlay_was_visible, "cancel input did not reach the presentation controller through HudRoot", failures)


func _send_hud_action(hud: HudRoot, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	hud._unhandled_input(event)


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
	controller._update_debug_view()
	_expect(controller._line_mesh.get_surface_count() == 1, "combat movement preview did not render its path", failures)

	# Earlier phases of this suite already moved the actor, so the clamped
	# endpoint is derived from where it actually stands rather than a literal.
	var clamp_origin: Vector3 = (controller.battle_state.actors[player.actor_id] as ActorState).position
	var clamp_budget: float = actor.movement_remaining
	controller.handle_terrain_click(target)
	_expect(controller.last_resolution.events.size() == 2 and controller.last_resolution.events[0].data["clamped"], "confirmed combat movement was not clamped", failures)
	var authoritative_position: Vector3 = (controller.battle_state.actors[player.actor_id] as ActorState).position
	var expected_endpoint := clamp_origin + (target - clamp_origin).normalized() * clamp_budget
	_expect(authoritative_position.distance_to(expected_endpoint) < 0.001, "confirmed clamp did not apply the authoritative endpoint; expected %s got %s" % [expected_endpoint, authoritative_position], failures)
	var playback_path := event_player.get_resolved_path(player.actor_id)
	_expect(not playback_path.is_empty() and playback_path[playback_path.size() - 1].distance_to(authoritative_position) < 0.001, "clamped event did not reach EventPlayer with its authoritative endpoint", failures)
	await _wait_for_destination(player, 240)
	_expect(player.destination_state == &"reached" and player.global_position.distance_to(authoritative_position) < 0.001, "CharacterView did not synchronize to clamped authoritative position", failures)

	controller.battle_state.phase = &"exploration"
	actor.movement_remaining = actor.movement_speed
	controller._update_debug_view()
	_expect(controller._line_mesh.get_surface_count() == 0, "movement path remained visible during exploration", failures)


func _test_command_event_view_pipeline(controller: TestArenaController, player: CharacterView, event_player: EventPlayer, failures: Array[String]) -> void:
	var start := player.global_position
	var clicked_position := Vector3(-9.0, 0.1, -2.0)
	controller.handle_terrain_click(clicked_position)
	_expect(controller.destination_marker.visible, "exploration click did not show a destination marker", failures)
	_expect((controller.destination_marker.global_position - Vector3.UP * DestinationClickMarker.GROUND_LIFT).distance_to(clicked_position) < 0.001, "exploration marker was not placed at the clicked position", failures)
	_expect(controller.last_command != null and controller.last_command.type == &"move", "terrain input did not create a move Command", failures)
	_expect(controller.last_resolution != null and controller.last_resolution.events[0].type == &"movement_segment", "move Command did not resolve to movement event", failures)
	_expect(event_player.last_played_events.size() > 0 and event_player.last_played_events[0].type == &"movement_segment", "accepted movement did not reach EventPlayer", failures)
	_expect(player.is_moving(), "EventPlayer did not start CharacterView movement", failures)
	var authoritative_position: Vector3 = (controller.battle_state.actors[player.actor_id] as ActorState).position
	_expect(authoritative_position != start and player.global_position == start, "state was not applied before visual interpolation", failures)


func _test_animation_movement_transition(_controller: TestArenaController, player: CharacterView, event_player: EventPlayer, failures: Array[String]) -> void:
	_expect(player.animator != null, "player prefab has no CharacterAnimator", failures)
	_expect(player.combat_sfx != null, "player prefab has no positional combat sound player", failures)
	var start := player.global_position
	var target := start + Vector3(1.5, 0.0, 0.0)
	event_player.play_events([Event.create(&"movement_segment", {"actor_id": player.actor_id, "path": PackedVector3Array([start, target]), "to": target})])
	await get_tree().physics_frame
	if player.animator != null:
		_expect(player.animator.current_state == &"locomotion", "movement did not enter locomotion animation state", failures)
	await _wait_for_destination(player, 180)
	if player.animator != null:
		_expect(player.animator.current_state == &"idle", "movement completion did not return animator to idle", failures)
		event_player.play_events([Event.create(&"attack_rolled", {"actor_id": player.actor_id})])
		_expect(player.animator.current_state == &"attack" and player.animator.current_clip == &"Melee_1H_Attack_Slice_Horizontal", "attack_rolled did not play the knight's melee attack clip", failures)
		_expect(player.combat_sfx.stream != null and player.combat_sfx.stream.resource_path.begins_with("res://assets/sfx/combat/Sword_Swing_Long_"), "attack_rolled did not play a sword attack sound", failures)
		# General remains optional, so unavailable non-movement clips must still
		# be harmless during event narration.
		event_player.play_events([Event.create(&"damage_taken", {"actor_id": player.actor_id, "amount": 1}), Event.create(&"interaction_completed", {"actor_id": player.actor_id}), Event.create(&"actor_died", {"actor_id": player.actor_id})])
		_expect(player.animator != null and player.animator.current_state in [&"idle", &"hit", &"death"], "absent optional clips crashed event narration", failures)
		_configure_event_animation_clips(player.animator)
		event_player.play_events([Event.create(&"attack_rolled", {"actor_id": player.actor_id})])
		_expect(player.animator.current_state == &"attack", "attack_rolled did not narrate attack", failures)
		event_player.play_events([Event.create(&"damage_taken", {"actor_id": player.actor_id, "amount": 1})])
		_expect(player.animator.current_state == &"hit", "damage_taken did not narrate hit", failures)
		_expect(player.combat_sfx.stream != null and player.combat_sfx.stream.resource_path.begins_with("res://assets/sfx/characters/hurt_"), "damage_taken did not play a hurt sound", failures)
		event_player.play_events([Event.create(&"interaction_completed", {"actor_id": player.actor_id})])
		_expect(player.animator.current_state == &"interact", "interaction_completed did not narrate interact", failures)
		event_player.play_events([
			Event.create(&"damage_taken", {"actor_id": player.actor_id, "amount": 1}),
			Event.create(&"actor_died", {"actor_id": player.actor_id}),
		])
		await get_tree().physics_frame
		_expect(player.animator.current_state == &"death", "damage followed by actor_died did not narrate death", failures)


## Shove -> knockdown -> prone -> stand-up -> walk, driven only by narrated
## events. The clips are short and their player sits in the tree so real
## animation_finished signals chain the sequence.
func _test_knockdown_sequence(controller: TestArenaController, player: CharacterView, event_player: EventPlayer, failures: Array[String]) -> void:
	if player.animator == null:
		return
	# The previous test narrated this view's death; start from the live actor.
	var actor: ActorState = controller.battle_state.actors[player.actor_id]
	player.reset_presentation(actor)
	var clip_player := _configure_knockdown_clips(player)
	event_player.play_events([Event.create(&"action_spent", {"actor_id": player.actor_id, "action": &"shove", "target_id": -1})])
	_expect(player.animator.current_state == &"shove" and player.animator.current_clip == &"Melee_Block_Attack", "a shove's action_spent did not play its authored animation verb", failures)

	event_player.play_events([Event.create(&"condition_added", {"actor_id": player.actor_id, "condition": &"prone", "source_actor_id": -1})])
	_expect(player.animator.current_state == &"shove" and player.is_presentation_busy(), "the fall did not wait for the push to connect", failures)
	_expect(await _wait_for_animator_state(player, &"knockdown", 90), "Prone did not play the knockdown fall", failures)
	_expect(await _wait_for_animator_state(player, &"prone", 90), "the knockdown did not settle into the prone loop", failures)
	_expect(not player.is_presentation_busy(), "lying prone kept the view busy", failures)
	event_player.play_events([Event.create(&"damage_taken", {"actor_id": player.actor_id, "amount": 1})])
	_expect(player.animator.current_state == &"prone", "a hit reaction stood a prone actor back up", failures)

	var start := player.global_position
	var target := start + Vector3(1.5, 0.0, 0.0)
	event_player.play_events([
		Event.create(&"condition_removed", {"actor_id": player.actor_id, "condition": &"prone"}),
		Event.create(&"movement_segment", {"actor_id": player.actor_id, "path": PackedVector3Array([start, target]), "to": target}),
	])
	await get_tree().physics_frame
	_expect(player.animator.current_state == &"stand_up" and player.is_moving() and player.global_position == start, "a prone move walked before its stand-up finished", failures)
	_expect(await _wait_for_animator_state(player, &"locomotion", 90), "the queued walk did not start after the stand-up", failures)
	await _wait_for_destination(player, 180)
	_expect(player.destination_state == &"reached" and not player.is_presentation_busy(), "the queued walk did not reach its destination", failures)

	event_player.play_events([Event.create(&"d20_test_rolled", {"actor_id": player.actor_id, "source_actor_id": player.actor_id, "test_type": &"saving_throw", "success": true})])
	_expect(await _wait_for_animator_state(player, &"hit", 90), "a resisted shove did not stagger its target", failures)
	clip_player.queue_free()
	_configure_event_animation_clips(player.animator)
	player.reset_presentation(actor)


func _configure_knockdown_clips(view: CharacterView) -> AnimationPlayer:
	var clip_player := AnimationPlayer.new()
	var library := AnimationLibrary.new()
	for clip in PackedStringArray(["Idle_A", "Walking_A", "Melee_Blocking", "Melee_Block_Attack", "Death_A", "Lie_Idle", "Lie_StandUp", "Hit_A"]):
		var animation := Animation.new()
		animation.length = 0.1
		animation.loop_mode = Animation.LOOP_LINEAR if clip == "Lie_Idle" else Animation.LOOP_NONE
		library.add_animation(clip, animation)
	clip_player.add_animation_library(&"test", library)
	view.add_child(clip_player)
	view.animator.configure_players([clip_player])
	return clip_player


func _wait_for_animator_state(view: CharacterView, state: StringName, max_frames: int) -> bool:
	for _frame in range(max_frames):
		if view.animator.current_state == state:
			return true
		await get_tree().physics_frame
	return view.animator.current_state == state


func _configure_event_animation_clips(animator: CharacterAnimator) -> void:
	var player := AnimationPlayer.new()
	var library := AnimationLibrary.new()
	for clip in PackedStringArray(["Idle_A", "Walking_A", "Melee_1H_Attack_Slice_Horizontal", "Hit_A", "Interact", "Death_A"]):
		library.add_animation(clip, Animation.new())
	player.add_animation_library(&"test", library)
	animator.configure_players([player])


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
	# The A10 collision resize shrank CentralObstacle's nav cutout from a
	# hand-authored 4x14m strip down to ~6.4x5.6m (matching Rock_3_R's real
	# footprint plus clearance), so a detour now only needs to clear z > 2.8
	# instead of the old z > 7 -- a straight, unobstructed path never exceeds
	# z ~= 2 here, so 2.5 still only trips on an actual detour.
	for point in path:
		if absf(point.z) > 2.5:
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


## A10: the Chest node's InteractableState round-trips through the same
## Command/Resolver/apply pipeline as movement -- submit_interact() bypasses
## the screen-raycast input boundary the same way handle_terrain_click's
## callers bypass _terrain_position_from_screen elsewhere in this suite.
func _test_chest_interaction(controller: TestArenaController, failures: Array[String]) -> void:
	controller.handle_terrain_click(Vector3(10.0, 0.1, -10.0))
	var first := controller.submit_interact("chest_a")
	_expect(first.events.size() == 2 and first.events[0].type == &"interaction_completed" and first.events[1].type == &"items_looted", "first chest interaction did not resolve to interaction_completed and items_looted", failures)
	_expect((controller.battle_state.interactables["chest_a"] as InteractableState).state == &"open", "chest did not open after interaction", failures)
	_expect((controller.battle_state.actors[controller.character.actor_id] as ActorState).inventory.count(&"healing_potion") == 2, "chest potion was not added to the player's inventory", failures)
	var second := controller.submit_interact("chest_a")
	_expect(second.events.size() == 1 and second.events[0].type == &"command_rejected" and second.events[0].data["reason"] == &"invalid_interactable_state", "re-opening an already-open chest was not rejected", failures)


## Regression test for a sign bug where holding "camera_pan_forward" (W)
## moved the rig's target_focus away from its own forward vector instead of
## toward it -- Input.get_vector's forward/back pair is (negative_y,
## positive_y), so naively multiplying by input_vector.y inverted the pan.
func _test_camera_pan_direction(rig: TacticalCameraRig, failures: Array[String]) -> void:
	var forward := Vector3(-sin(rig.target_yaw), 0.0, -cos(rig.target_yaw))
	var right := Vector3(-forward.z, 0.0, forward.x)

	var left_delta := _pan_delta(rig, &"camera_pan_left")
	_expect(
		left_delta.length() > 0.01 and left_delta.normalized().dot(right) < -0.9,
		"camera_pan_left should move target_focus left of the rig's forward vector; moved %s" % left_delta,
		failures,
	)

	var right_delta := _pan_delta(rig, &"camera_pan_right")
	_expect(
		right_delta.length() > 0.01 and right_delta.normalized().dot(right) > 0.9,
		"camera_pan_right should move target_focus right of the rig's forward vector; moved %s" % right_delta,
		failures,
	)

	var forward_delta := _pan_delta(rig, &"camera_pan_forward")
	_expect(
		forward_delta.length() > 0.01 and forward_delta.normalized().dot(forward) > 0.9,
		"camera_pan_forward should move target_focus toward the rig's forward vector; moved %s" % forward_delta,
		failures,
	)

	var back_delta := _pan_delta(rig, &"camera_pan_back")
	_expect(
		back_delta.length() > 0.01 and back_delta.normalized().dot(forward) < -0.9,
		"camera_pan_back should move target_focus away from the rig's forward vector; moved %s" % back_delta,
		failures,
	)


## The rig re-anchors target_focus to its follow target at the top of every
## _process, so the baseline has to be sampled after a neutral frame -- reading
## it straight after the previous direction's frame would fold that pan into
## this delta.
func _pan_delta(rig: TacticalCameraRig, action: StringName) -> Vector3:
	rig._process(0.1)
	var before := rig.target_focus
	Input.action_press(action)
	rig._process(0.1)
	Input.action_release(action)
	return rig.target_focus - before


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
