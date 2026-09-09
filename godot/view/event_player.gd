class_name EventPlayer
extends Node

## Narrates accepted simulation events. It is intentionally unable to resolve
## commands or change BattleState; the controller applies state before calling
## play_events().

signal movement_started(actor_id: int, path: PackedVector3Array)
signal movement_completed(actor_id: int)
signal feedback_presented(event: Event, feedback: FloatingCombatText)

const FLOATING_COMBAT_TEXT_SCENE := preload("res://view/ui/floating_combat_text.tscn")

var _views_by_actor: Dictionary = {}
var _last_paths: Dictionary = {}
var last_played_events: Array[Event] = []


func register_character_view(view: CharacterView) -> void:
	_views_by_actor[view.actor_id] = view
	if not view.movement_completed.is_connected(_on_character_movement_completed):
		view.movement_completed.connect(_on_character_movement_completed)


func play_events(events: Array[Event]) -> void:
	last_played_events = events.duplicate()
	for event in events:
		_narrate_event(event)


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
		&"attack_rolled":
			if view != null:
				view.present_attack()
			if not bool(event.data.get("hit", false)):
				var target_view := get_character_view(int(event.data.get("target_id", -1)))
				if target_view != null:
					target_view.present_dodge()
					_present_floating_feedback(target_view, event)
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
		&"condition_added", &"condition_removed", &"command_rejected":
			if view != null:
				_present_floating_feedback(view, event)
		&"actor_died":
			if view != null:
				view.present_death()
		&"game_over":
			for defeated_id in event.data.get("defeated_actor_ids", []):
				var defeated_view := get_character_view(int(defeated_id))
				if defeated_view != null:
					defeated_view.present_death()


func get_resolved_path(actor_id: int) -> PackedVector3Array:
	if not _last_paths.has(actor_id):
		return PackedVector3Array()
	return (_last_paths[actor_id] as PackedVector3Array).duplicate()


func get_character_view(actor_id: int) -> CharacterView:
	return _views_by_actor.get(actor_id) as CharacterView


func reset_views(state: BattleState) -> void:
	_last_paths.clear()
	last_played_events.clear()
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
