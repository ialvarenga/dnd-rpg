class_name EventPlayer
extends Node

## Narrates accepted simulation events. It is intentionally unable to resolve
## commands or change BattleState; the controller applies state before calling
## play_events().

signal movement_started(actor_id: int, path: PackedVector3Array)
signal movement_completed(actor_id: int)
signal feedback_presented(event: Event, feedback: FloatingCombatText)

const FLOATING_COMBAT_TEXT_SCENE := preload("res://view/ui/floating_combat_text.tscn")
## Gaining/losing this condition is narrated as a knockdown/stand-up.
const PRONE_CONDITION := &"prone"
## A hit arrow flies at the target's chest; the view origin is capsule centre.
const ARROW_TARGET_HEIGHT := 0.3
## View origin to feet (AssetDefinition.display_offset of the character art).
const VIEW_ORIGIN_HEIGHT := 0.9
## A missed arrow falls into the ground this far short of its target.
const MISS_DROP_SHORT_METERS := 1.2
## Longer than any draw plus flight: if a loose or arrival never reports, the
## deferred narration is flushed anyway so combat cannot stall on presentation.
const SHOT_WATCHDOG_SECONDS := 3.0
## Longer than a walk to a ledge plus the jump itself, for the same reason.
const FLIGHT_WATCHDOG_SECONDS := 12.0

var _views_by_actor: Dictionary = {}
var _last_paths: Dictionary = {}
var last_played_events: Array[Event] = []
# A ranged attack pauses narration until its arrow lands: the attack event,
# the rest of its batch (resumed from next_index), the arrow once loosed, and
# a serial so a stale arrival or watchdog cannot resume a later shot.
var _pending_shot: Dictionary = {}
var _shot_serial := 0
# Likewise a ledge jump (or a Shove fall) holds the rest of its batch until the
# flier lands, so a hard landing's knockdown, damage, and Prone -- and any
# walking leg after the jump -- play on the ground.
var _pending_flight: Dictionary = {}
var _flight_serial := 0


func register_character_view(view: CharacterView) -> void:
	_views_by_actor[view.actor_id] = view
	if not view.movement_completed.is_connected(_on_character_movement_completed):
		view.movement_completed.connect(_on_character_movement_completed)
	if not view.ranged_released.is_connected(_on_ranged_released):
		view.ranged_released.connect(_on_ranged_released)
	if not view.jump_landed.is_connected(_on_jump_landed):
		view.jump_landed.connect(_on_jump_landed)


func play_events(events: Array[Event]) -> void:
	last_played_events = events.duplicate()
	if not _pending_shot.is_empty():
		# Never narrate past an arrow still in the air: queue behind it.
		(_pending_shot["events"] as Array).append_array(events)
		return
	if not _pending_flight.is_empty():
		(_pending_flight["events"] as Array).append_array(events)
		return
	_play_from(events.duplicate(), 0)


## True while a ranged attack's narration waits for its arrow, or a jump's for
## its landing. The composition root holds the next command behind this, as it
## does behind a walking view.
func is_busy() -> bool:
	return not _pending_shot.is_empty() or not _pending_flight.is_empty()


## Narrates events[index..] in order. A ranged attack with a projectile to show
## stops here; the arrow's arrival resumes the rest of the batch, so the
## target's dodge, damage, and downing (and anything after them) wait for it.
## A ledge jump or a fall stops here the same way until the flier lands.
func _play_from(events: Array, index: int) -> void:
	for i in range(index, events.size()):
		var event := events[i] as Event
		if _starts_shot(event):
			_begin_shot(event, events, i + 1)
			return
		if _starts_flight(event, events, i):
			_begin_flight(event, events, i + 1)
			return
		_narrate_event(event)


## A jump always flies; forced movement flies only when a fall follows it (a
## level push stays a straight shove).
func _starts_flight(event: Event, events: Array, index: int) -> bool:
	if get_character_view(int(event.data.get("actor_id", -1))) == null:
		return false
	if event.type == &"jump_performed":
		return true
	return event.type == &"forced_movement" and _fall_follows(events, index)


## The fall_started, if any, that narrates this event's landing.
func _fall_follows(events: Array, index: int) -> bool:
	var actor_id := int((events[index] as Event).data.get("actor_id", -1))
	return index + 1 < events.size() and (events[index + 1] as Event).type == &"fall_started" and int((events[index + 1] as Event).data.get("actor_id", -2)) == actor_id


func _begin_flight(event: Event, events: Array, next_index: int) -> void:
	_flight_serial += 1
	var actor_id := int(event.data.get("actor_id", -1))
	_pending_flight = {"serial": _flight_serial, "actor_id": actor_id, "events": events, "next_index": next_index}
	if is_inside_tree():
		get_tree().create_timer(FLIGHT_WATCHDOG_SECONDS).timeout.connect(_finish_flight.bind(_flight_serial))
	var view := get_character_view(actor_id)
	var from: Vector3 = event.data.get("from", view.global_position)
	var to: Vector3 = event.data.get("to", view.global_position)
	_last_paths[actor_id] = PackedVector3Array([from, to])
	# May land (and so emit jump_landed) synchronously.
	view.play_jump(from, to, _fall_follows(events, next_index - 1), event.type == &"forced_movement")


func _on_jump_landed(actor_id: int) -> void:
	if not _pending_flight.is_empty() and int(_pending_flight["actor_id"]) == actor_id:
		_finish_flight(int(_pending_flight["serial"]))


## Landing (or the watchdog): resume the batch the flight held.
func _finish_flight(serial: int) -> void:
	if _pending_flight.is_empty() or int(_pending_flight["serial"]) != serial:
		return
	var flight := _pending_flight
	_pending_flight = {}
	_play_from(flight["events"], flight["next_index"])


func _starts_shot(event: Event) -> bool:
	if event.type != &"attack_rolled" or not bool(event.data.get("is_ranged", false)):
		return false
	var attacker := get_character_view(int(event.data.get("actor_id", -1)))
	var target := get_character_view(int(event.data.get("target_id", -1)))
	return attacker != null and target != null and attacker.can_present_ranged_attack()


func _begin_shot(event: Event, events: Array, next_index: int) -> void:
	_shot_serial += 1
	_pending_shot = {"serial": _shot_serial, "event": event, "events": events, "next_index": next_index, "arrow": null}
	if is_inside_tree():
		get_tree().create_timer(SHOT_WATCHDOG_SECONDS).timeout.connect(_finish_shot.bind(_shot_serial))
	var attacker := get_character_view(int(event.data.get("actor_id", -1)))
	var target := get_character_view(int(event.data.get("target_id", -1)))
	# May loose (and so emit ranged_released) synchronously.
	attacker.present_ranged_attack(target.global_position)


func _on_ranged_released(actor_id: int) -> void:
	if _pending_shot.is_empty() or _pending_shot["arrow"] != null:
		return
	var event := _pending_shot["event"] as Event
	if int(event.data.get("actor_id", -1)) != actor_id:
		return
	var serial: int = _pending_shot["serial"]
	var attacker := get_character_view(actor_id)
	var target := get_character_view(int(event.data.get("target_id", -1)))
	if attacker == null or target == null or not attacker.is_inside_tree():
		_finish_shot(serial)
		return
	var hit := bool(event.data.get("hit", false))
	var from := attacker.projectile_origin()
	var to := target.global_position + Vector3.UP * ARROW_TARGET_HEIGHT if hit else _miss_landing(from, target.global_position)
	var arrow := ArrowProjectile.new()
	arrow.name = "Arrow"
	_pending_shot["arrow"] = arrow
	attacker.get_parent().add_child(arrow)
	arrow.arrived.connect(_finish_shot.bind(serial))
	arrow.launch(load(attacker.projectile_model_path) as PackedScene, from, to, not hit)


## The ground point short of the target, on the line from the bow.
func _miss_landing(from: Vector3, target_position: Vector3) -> Vector3:
	var landing := target_position - Vector3.UP * VIEW_ORIGIN_HEIGHT
	var approach := Vector3(landing.x - from.x, 0.0, landing.z - from.z)
	if approach.length() > MISS_DROP_SHORT_METERS * 2.0:
		landing -= approach.normalized() * MISS_DROP_SHORT_METERS
	return landing


## Arrival (or the watchdog): react on the target, then resume the batch.
func _finish_shot(serial: int) -> void:
	if _pending_shot.is_empty() or int(_pending_shot["serial"]) != serial:
		return
	var shot := _pending_shot
	_pending_shot = {}
	var arrow: Variant = shot["arrow"]
	if is_instance_valid(arrow) and not (arrow as ArrowProjectile).has_arrived:
		(arrow as Node).queue_free()
	_present_attack_reaction(shot["event"])
	_play_from(shot["events"], shot["next_index"])


func _narrate_event(event: Event) -> void:
	var actor_id := int(event.data.get("actor_id", -1))
	var view := get_character_view(actor_id)
	match event.type:
		&"combat_started":
			for character_view in _views_by_actor.values():
				(character_view as CharacterView).present_combat_ready()
		&"combat_ended":
			for character_view in _views_by_actor.values():
				(character_view as CharacterView).present_combat_ended()
		&"movement_segment":
			if view == null:
				return
			var path_data: Variant = event.data.get("presentation_path", event.data.get("path", PackedVector3Array()))
			if not (path_data is PackedVector3Array):
				return
			var path: PackedVector3Array = path_data
			_last_paths[actor_id] = path.duplicate()
			if view.play_movement(path, event.data["to"]):
				movement_started.emit(actor_id, path.duplicate())
		&"forced_movement":
			if view != null:
				var forced_path := PackedVector3Array([event.data.get("from", view.global_position), event.data.get("to", view.global_position)])
				view.play_movement(forced_path, event.data.get("to", view.global_position))
		&"fall_started":
			# Narrated once the flight has landed, so the fall hits at once. Out
			# of combat no Prone follows: the creature gets straight back up.
			if view != null:
				view.present_knockdown(event.data.get("from", view.global_position), true)
				if not bool(event.data.get("prone", true)):
					view.present_stand_up()
		&"mastery_triggered", &"hidden_revealed":
			if view != null:
				_present_floating_feedback(view, event)
		&"forced_movement_blocked":
			var blocked_target := get_character_view(int(event.data.get("target_id", -1)))
			if blocked_target != null:
				_present_floating_feedback(blocked_target, event)
		&"sneaking_changed":
			if view != null:
				view.present_sneaking(bool(event.data.get("sneaking", false)))
				_present_floating_feedback(view, event)
		&"detection_changed":
			if view != null:
				_present_floating_feedback(view, event)
		&"attack_rolled":
			if view != null:
				view.present_attack()
			_present_attack_reaction(event)
		&"damage_taken":
			if view != null:
				view.present_hit()
				_present_floating_feedback(view, event)
		&"healing_received":
			if view != null:
				_present_floating_feedback(view, event)
		&"item_consumed":
			if view != null:
				_present_floating_feedback(view, event)
		&"interaction_completed":
			if view != null:
				view.present_interaction()
		&"actor_downed":
			# A downed actor is no longer an active combatant in this runtime.
			# Keep the simulation's unconscious/dead distinction, but use the
			# shared death presentation for every character prefab so enemies do
			# not remain standing after reaching 0 HP.
			if view != null:
				view.present_death()
				_present_floating_feedback(view, event)
		&"action_spent":
			var ability := DefinitionLibrary.get_default().get_ability(StringName(event.data.get("action", &"")))
			if view != null and ability != null and ability.animation_verb != &"":
				var ability_target_view := get_character_view(int(event.data.get("target_id", -1)))
				view.present_ability(ability.animation_verb, ability_target_view.global_position if ability_target_view != null else view.global_position)
		&"d20_test_rolled":
			# Only a save forced by another actor (a shove) has someone to resist.
			var save_source_view := get_character_view(int(event.data.get("source_actor_id", -1)))
			if view != null and save_source_view != null and event.data.get("test_type") == &"saving_throw" and bool(event.data.get("success", false)):
				view.present_resisted()
				_present_floating_feedback(view, event)
		&"condition_added", &"condition_removed", &"condition_consumed", &"command_rejected":
			if view != null:
				if event.type == &"condition_added" and event.data.get("condition") == PRONE_CONDITION:
					var source_view := get_character_view(int(event.data.get("source_actor_id", -1)))
					view.present_knockdown(source_view.global_position if source_view != null else view.global_position)
				elif event.type == &"condition_removed" and event.data.get("condition") == PRONE_CONDITION:
					view.present_stand_up()
				_present_floating_feedback(view, event)
		&"actor_died":
			if view != null:
				view.present_death()
		&"game_over":
			for defeated_id in event.data.get("defeated_actor_ids", []):
				var defeated_view := get_character_view(int(defeated_id))
				if defeated_view != null:
					defeated_view.present_death()


## A miss is narrated on its target (a hit's reaction is its damage_taken).
func _present_attack_reaction(event: Event) -> void:
	if bool(event.data.get("hit", false)):
		return
	var target_view := get_character_view(int(event.data.get("target_id", -1)))
	if target_view != null:
		target_view.present_dodge()
		_present_floating_feedback(target_view, event)


func get_resolved_path(actor_id: int) -> PackedVector3Array:
	if not _last_paths.has(actor_id):
		return PackedVector3Array()
	return (_last_paths[actor_id] as PackedVector3Array).duplicate()


func get_character_view(actor_id: int) -> CharacterView:
	return _views_by_actor.get(actor_id) as CharacterView


func reset_views(state: BattleState) -> void:
	_last_paths.clear()
	last_played_events.clear()
	# The restored state already contains whatever the shot did; drop its
	# deferred narration rather than replay it over the restored views.
	var arrow: Variant = _pending_shot.get("arrow")
	if is_instance_valid(arrow):
		(arrow as Node).queue_free()
	_pending_shot = {}
	_pending_flight = {}
	for actor_id in _views_by_actor:
		var view := _views_by_actor[actor_id] as CharacterView
		if view != null and state.actors.has(actor_id):
			view.reset_presentation(state.actors[actor_id], state.phase == &"combat")


## A CharacterView is the anchor because it follows the interpolated world
## position. This deliberately creates no command and never reads or mutates
## BattleState: EncounterSession has already applied the event before playback.
func _present_floating_feedback(view: CharacterView, event: Event) -> void:
	var feedback := FLOATING_COMBAT_TEXT_SCENE.instantiate() as FloatingCombatText
	if feedback == null:
		return
	view.add_child(feedback)
	feedback.show_event(event)
	if feedback.text.is_empty():
		feedback.queue_free()
		return
	feedback_presented.emit(event, feedback)


func _on_character_movement_completed(actor_id: int) -> void:
	movement_completed.emit(actor_id)
