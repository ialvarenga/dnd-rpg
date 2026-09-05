class_name EventPlayer
extends Node

## Narrates accepted simulation events. It is intentionally unable to resolve
## commands or change BattleState; the controller applies state before calling
## play_events().

signal movement_started(actor_id: int, path: PackedVector3Array)
signal movement_completed(actor_id: int)

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
		&"damage_taken":
			if view != null:
				view.present_hit()
		&"interaction_completed":
			if view != null:
				view.present_interaction()
		&"actor_died":
			if view != null:
				view.present_death()


func get_resolved_path(actor_id: int) -> PackedVector3Array:
	if not _last_paths.has(actor_id):
		return PackedVector3Array()
	return (_last_paths[actor_id] as PackedVector3Array).duplicate()


func get_character_view(actor_id: int) -> CharacterView:
	return _views_by_actor.get(actor_id) as CharacterView


func _on_character_movement_completed(actor_id: int) -> void:
	movement_completed.emit(actor_id)
