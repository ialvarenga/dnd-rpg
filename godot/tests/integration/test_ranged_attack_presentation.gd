class_name TestRangedAttackPresentation
extends Node

## A ranged attack is settled by the simulation at once; its presentation
## (draw, arrow in flight, then the target's reaction) must still narrate the
## target's side only when the arrow lands. Bare CharacterViews have no
## animator, so the bow looses immediately and only the flight takes time.

const ARROW_MODEL := "res://assets/kaykit_adventurers_weapons/arrow_bow.gltf"
const ARRIVAL_TIMEOUT_MSEC := 2000


func run() -> Dictionary:
	var failures: Array[String] = []
	await _test_hit_reaction_waits_for_the_arrow(failures)
	await _test_miss_drops_short_and_reacts_on_arrival(failures)
	_test_attacker_without_projectile_narrates_at_once(failures)
	await _test_reset_mid_flight_drops_the_shot(failures)
	await _test_events_played_mid_flight_queue_behind_the_arrow(failures)
	return {"name": "integration/test_ranged_attack_presentation", "failures": failures}


func _test_hit_reaction_waits_for_the_arrow(failures: Array[String]) -> void:
	var scene := _make_scene(ARROW_MODEL)
	var player: EventPlayer = scene["player"]
	var target: CharacterView = scene["target"]
	player.play_events(_ranged_attack(scene, true))
	_expect(_feedback_texts(target).is_empty(), "a ranged hit's damage text appeared before the arrow flew", failures)
	_expect(player.is_busy(), "the event player should be busy while the arrow is in flight", failures)
	_expect(_arrows().size() == 1, "a ranged attack from a bow wielder should launch one arrow", failures)
	await _wait_for_arrival(player)
	_expect(not player.is_busy(), "the event player stayed busy after the arrow landed", failures)
	_expect(_feedback_texts(target) == ["-4"], "the ranged hit's damage text should appear on the target once the arrow lands", failures)
	await get_tree().process_frame
	_expect(_arrows().is_empty(), "an arrow that hit should be removed on arrival", failures)
	_free_scene(scene)


func _test_miss_drops_short_and_reacts_on_arrival(failures: Array[String]) -> void:
	var scene := _make_scene(ARROW_MODEL)
	var player: EventPlayer = scene["player"]
	var target: CharacterView = scene["target"]
	player.play_events(_ranged_attack(scene, false))
	_expect(_feedback_texts(target).is_empty(), "a ranged miss was narrated before the arrow flew", failures)
	await _wait_for_arrival(player)
	_expect(_feedback_texts(target) == ["MISS"], "a ranged miss should put MISS on its target once the arrow lands", failures)
	var arrows := _arrows()
	_expect(arrows.size() == 1, "a missed arrow should stay stuck in the ground for a moment", failures)
	if arrows.size() == 1:
		var landed := arrows[0].global_position
		_expect(landed.x < target.global_position.x - 1.0 and landed.y < target.global_position.y - 0.5, "a missed arrow should drop into the ground short of the target", failures)
	_free_scene(scene)


func _test_attacker_without_projectile_narrates_at_once(failures: Array[String]) -> void:
	var scene := _make_scene("")
	var player: EventPlayer = scene["player"]
	var target: CharacterView = scene["target"]
	player.play_events(_ranged_attack(scene, false))
	_expect(_feedback_texts(target) == ["MISS"] and not player.is_busy(), "a ranged attack with no projectile model should narrate at once like melee", failures)
	_expect(_arrows().is_empty(), "no arrow should fly for an attacker with no projectile model", failures)
	_free_scene(scene)


func _test_reset_mid_flight_drops_the_shot(failures: Array[String]) -> void:
	var scene := _make_scene(ARROW_MODEL)
	var player: EventPlayer = scene["player"]
	var target: CharacterView = scene["target"]
	player.play_events(_ranged_attack(scene, true))
	player.reset_views(BattleState.new())
	_expect(not player.is_busy(), "reset_views should drop a shot still in flight", failures)
	await get_tree().create_timer(0.8).timeout
	_expect(_feedback_texts(target).is_empty(), "a shot dropped by reset_views should never narrate its damage", failures)
	_expect(_arrows().is_empty(), "reset_views should remove the arrow in flight", failures)
	_free_scene(scene)


func _test_events_played_mid_flight_queue_behind_the_arrow(failures: Array[String]) -> void:
	var scene := _make_scene(ARROW_MODEL)
	var player: EventPlayer = scene["player"]
	var archer: CharacterView = scene["archer"]
	var target: CharacterView = scene["target"]
	player.play_events(_ranged_attack(scene, true))
	var later: Array[Event] = [Event.create(&"damage_taken", {"actor_id": archer.actor_id, "amount": 2})]
	player.play_events(later)
	_expect(_feedback_texts(archer).is_empty(), "a batch played mid-flight should wait behind the arrow", failures)
	await _wait_for_arrival(player)
	_expect(_feedback_texts(target) == ["-4"] and _feedback_texts(archer) == ["-2"], "the queued batch should narrate after the arrow's own consequences", failures)
	_free_scene(scene)


func _make_scene(projectile_model_path: String) -> Dictionary:
	var player := EventPlayer.new()
	add_child(player)
	var archer := CharacterView.new()
	archer.actor_id = 11
	archer.projectile_model_path = projectile_model_path
	add_child(archer)
	var target := CharacterView.new()
	target.actor_id = 12
	add_child(target)
	archer.global_position = Vector3.ZERO
	target.global_position = Vector3(10.0, 0.0, 0.0)
	player.register_character_view(archer)
	player.register_character_view(target)
	return {"player": player, "archer": archer, "target": target}


func _ranged_attack(scene: Dictionary, hit: bool) -> Array[Event]:
	var archer: CharacterView = scene["archer"]
	var target: CharacterView = scene["target"]
	var events: Array[Event] = [Event.create(&"attack_rolled", {"actor_id": archer.actor_id, "target_id": target.actor_id, "hit": hit, "is_ranged": true})]
	if hit:
		events.append(Event.create(&"damage_taken", {"actor_id": target.actor_id, "source_actor_id": archer.actor_id, "amount": 4}))
	return events


func _wait_for_arrival(player: EventPlayer) -> void:
	var deadline := Time.get_ticks_msec() + ARRIVAL_TIMEOUT_MSEC
	while player.is_busy() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _free_scene(scene: Dictionary) -> void:
	for node in scene.values():
		(node as Node).queue_free()
	for arrow in _arrows():
		arrow.queue_free()


func _arrows() -> Array[ArrowProjectile]:
	var arrows: Array[ArrowProjectile] = []
	for child in get_children():
		if child is ArrowProjectile and not (child as Node).is_queued_for_deletion():
			arrows.append(child as ArrowProjectile)
	return arrows


func _feedback_texts(actor: CharacterView) -> Array[String]:
	var texts: Array[String] = []
	for child in actor.get_children():
		if child is FloatingCombatText:
			texts.append((child as FloatingCombatText).text)
	return texts


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
