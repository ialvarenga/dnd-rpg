class_name TestJumpPresentation
extends Node

## ADR-009: a ledge jump is settled by the simulation at once, but the view
## flies it -- takeoff, arc, landing -- and the event player holds the rest of
## the batch until touchdown, so a hard landing's damage and Prone play on the
## ground rather than in mid-air.

const LANDING_TIMEOUT_MSEC := 3000
const JUMP_CLIPS := ["Idle_A", "Walking_A", "Running_A", "Jump_Start", "Jump_Idle", "Jump_Land", "Death_A", "Lie_Idle", "Lie_StandUp"]


func run() -> Dictionary:
	var failures: Array[String] = []
	await _test_soft_landing(failures)
	await _test_hard_landing_waits_for_touchdown(failures)
	await _test_walk_then_jump_completes_once(failures)
	await _test_push_fall_flies_the_arc(failures)
	return {"name": "integration/test_jump_presentation", "failures": failures}


func _test_soft_landing(failures: Array[String]) -> void:
	var scene := _make_scene()
	var player: EventPlayer = scene["player"]
	var view: CharacterView = scene["view"]
	var from := Vector3(0, 5, 0)
	var to := Vector3(2, 3.8, 0)
	view.global_position = from
	player.play_events(_jump(view, from, to, &"drop"))
	_expect(player.is_busy() and view.is_moving(), "a jump in flight should keep the player and the view busy", failures)
	await _wait_until_idle(player)
	_expect(view.global_position.is_equal_approx(to), "the view did not land on the jump's landing point", failures)
	_expect(view.animator.current_state == &"jump_land", "a soft landing should play the landing clip", failures)
	_expect(CharacterView.LAND_SOUNDS.has(view.movement_sfx.stream), "a soft landing should play a landing thud on MovementSfx", failures)
	_expect((scene["completed"] as Array).size() == 1 and int(scene["completed"][0]) == view.actor_id, "a jump should complete the view's movement exactly once", failures)
	_free_scene(scene)


func _test_hard_landing_waits_for_touchdown(failures: Array[String]) -> void:
	var scene := _make_scene()
	var player: EventPlayer = scene["player"]
	var view: CharacterView = scene["view"]
	var from := Vector3(0, 5, 0)
	var to := Vector3(2, 0.8, 0)
	view.global_position = from
	var events := _jump(view, from, to, &"drop")
	events.append(Event.create(&"fall_started", {"actor_id": view.actor_id, "from": from, "to": to, "fall_distance": 4.2, "deliberate": true, "prone": true}))
	events.append(Event.create(&"damage_taken", {"actor_id": view.actor_id, "amount": 4, "damage_type": &"fall"}))
	events.append(Event.create(&"condition_added", {"actor_id": view.actor_id, "condition": &"prone", "source_actor_id": view.actor_id}))
	player.play_events(events)
	_expect(_feedback_texts(view).is_empty(), "a hard landing's damage was narrated while the jumper was still in the air", failures)
	await _wait_until_idle(player)
	_expect(_feedback_texts(view).has("-4"), "a hard landing's damage should be narrated on touchdown", failures)
	_expect(view.animator.current_state in [&"knockdown", &"prone"], "a hard landing should knock the jumper down instead of playing the landing clip", failures)
	_expect(CharacterView.HARD_LAND_SOUNDS.has(view.movement_sfx.stream), "a hard landing should play the heavy thud", failures)
	_free_scene(scene)


func _test_walk_then_jump_completes_once(failures: Array[String]) -> void:
	var scene := _make_scene()
	var player: EventPlayer = scene["player"]
	var view: CharacterView = scene["view"]
	var start := Vector3(-2, 5, 0)
	var takeoff := Vector3(0, 5, 0)
	var landing := Vector3(2, 3.8, 0)
	view.global_position = start
	var events: Array[Event] = [Event.create(&"movement_segment", {"actor_id": view.actor_id, "from": start, "to": takeoff, "path": PackedVector3Array([start, takeoff])})]
	events.append_array(_jump(view, takeoff, landing, &"drop"))
	player.play_events(events)
	await get_tree().physics_frame
	_expect(view.global_position.y >= 4.99, "the view jumped before walking to the ledge", failures)
	await _wait_until_idle(player)
	_expect(view.global_position.is_equal_approx(landing), "the walk-then-jump move did not end on the landing", failures)
	_expect((scene["completed"] as Array).size() == 1 and int(scene["completed"][0]) == view.actor_id, "a walk leading into a jump must complete only once, after the landing", failures)
	_free_scene(scene)


func _test_push_fall_flies_the_arc(failures: Array[String]) -> void:
	var scene := _make_scene()
	var player: EventPlayer = scene["player"]
	var view: CharacterView = scene["view"]
	var from := Vector3(0, 5, 0)
	var to := Vector3(3, 0.8, 0)
	view.global_position = from
	var events: Array[Event] = [
		Event.create(&"forced_movement", {"actor_id": view.actor_id, "source_actor_id": 99, "from": from, "to": to, "distance": 3.0}),
		Event.create(&"fall_started", {"actor_id": view.actor_id, "from": from, "to": to, "fall_distance": 4.2, "deliberate": false, "prone": true}),
	]
	player.play_events(events)
	_expect(player.is_busy(), "a Shove fall should be flown, holding narration until the landing", failures)
	await _wait_until_idle(player)
	_expect(view.global_position.is_equal_approx(to), "a pushed creature did not land at the push's landing point", failures)
	_expect(view.animator.current_state in [&"knockdown", &"prone"], "a Shove fall should end knocked down", failures)
	_free_scene(scene)


func _jump(view: CharacterView, from: Vector3, to: Vector3, kind: StringName) -> Array[Event]:
	return [Event.create(&"jump_performed", {"actor_id": view.actor_id, "kind": kind, "from": from, "to": to, "height": absf(from.y - to.y), "running": false, "movement_cost": 2.0})]


func _make_scene() -> Dictionary:
	var player := EventPlayer.new()
	add_child(player)
	var view := CharacterView.new()
	view.actor_id = 11
	var animator := CharacterAnimator.new()
	animator.name = "CharacterAnimator"
	animator.animation_set = ActorAnimationSet.new()
	view.add_child(animator)
	var sfx := AudioStreamPlayer3D.new()
	sfx.name = "MovementSfx"
	view.add_child(sfx)
	add_child(view)
	var animation_player := AnimationPlayer.new()
	var library := AnimationLibrary.new()
	for clip in JUMP_CLIPS:
		library.add_animation(clip, Animation.new())
	animation_player.add_animation_library(&"test", library)
	view.add_child(animation_player)
	animator.configure_players([animation_player])
	player.register_character_view(view)
	var completed: Array[int] = []
	view.movement_completed.connect(func(actor_id: int): completed.append(actor_id))
	return {"player": player, "view": view, "completed": completed}


func _wait_until_idle(player: EventPlayer) -> void:
	var deadline := Time.get_ticks_msec() + LANDING_TIMEOUT_MSEC
	while player.is_busy() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	await get_tree().physics_frame


func _free_scene(scene: Dictionary) -> void:
	(scene["player"] as Node).queue_free()
	(scene["view"] as Node).queue_free()


func _feedback_texts(actor: CharacterView) -> Array[String]:
	var texts: Array[String] = []
	for child in actor.get_children():
		if child is FloatingCombatText:
			texts.append((child as FloatingCombatText).text)
	return texts


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
