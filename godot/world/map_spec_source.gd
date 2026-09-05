class_name MapSpecSource
extends RefCounted

var source_path: String
var _cached_spec: Dictionary


func _init(path: String = "") -> void:
	source_path = path


func load_spec() -> Dictionary:
	if _cached_spec != null:
		return _cached_spec
	var resolved_path := source_path
	if resolved_path.begins_with("../"):
		resolved_path = ProjectSettings.globalize_path("res://").path_join(resolved_path)
	var file := FileAccess.open(resolved_path, FileAccess.READ)
	if file == null:
		_cached_spec = {}
		return _cached_spec
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_cached_spec = parsed if parsed is Dictionary else {}
	return _cached_spec
