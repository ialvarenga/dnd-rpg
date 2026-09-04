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
		if event.type != &"movement_segment":
			continue
		var actor_id := int(event.data["actor_id"])
		if not _views_by_actor.has(actor_id):
			continue
		var path_data: Variant = event.data.get("presentation_path", event.data["path"])
		if not (path_data is PackedVector3Array):
			continue
		var path: PackedVector3Array = path_data
		_last_paths[actor_id] = path.duplicate()
		var view: CharacterView = _views_by_actor[actor_id]
		if view.play_movement(path, event.data["to"]):
			movement_started.emit(actor_id, path.duplicate())


func get_resolved_path(actor_id: int) -> PackedVector3Array:
	if not _last_paths.has(actor_id):
		return PackedVector3Array()
	return (_last_paths[actor_id] as PackedVector3Array).duplicate()


func get_character_view(actor_id: int) -> CharacterView:
	return _views_by_actor.get(actor_id) as CharacterView


func _on_character_movement_completed(actor_id: int) -> void:
	movement_completed.emit(actor_id)
