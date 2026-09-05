class_name MapSpecSource
extends RefCounted

var source_path: String
var _cached_spec: Dictionary
var _has_cached_spec := false
var last_error := ""
var last_resolved_path := ""


func _init(path: String = "") -> void:
	source_path = path


func load_spec() -> Dictionary:
	if _has_cached_spec:
		return _cached_spec
	var resolved_path := _resolve_path(source_path)
	last_resolved_path = resolved_path
	var exists := FileAccess.file_exists(resolved_path)
	print("[MapSpecSource] requested='%s' resolved='%s' project_root='%s' exists=%s" % [source_path, resolved_path, ProjectSettings.globalize_path("res://"), exists])
	var file := FileAccess.open(resolved_path, FileAccess.READ)
	if file == null:
		last_error = "could not open '%s' (resolved to '%s')" % [source_path, resolved_path]
		push_error("[MapSpecSource] %s" % last_error)
		_cached_spec = {}
		_has_cached_spec = true
		return _cached_spec
	var text := file.get_as_text()
	print("[MapSpecSource] read %d bytes from '%s'" % [text.length(), resolved_path])
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		last_error = "'%s' does not contain a JSON object" % resolved_path
		push_error("[MapSpecSource] %s" % last_error)
		_cached_spec = {}
		_has_cached_spec = true
		return _cached_spec
	last_error = ""
	_cached_spec = parsed
	_has_cached_spec = true
	print("[MapSpecSource] parsed top-level keys: %s" % _cached_spec.keys())
	return _cached_spec


func _resolve_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://") or path.is_absolute_path():
		return path
	# Map authoring lives next to the Godot project.  Simplifying the resulting
	# absolute path is essential on Windows, where FileAccess does not reliably
	# traverse a literal `..` segment from a project-globalized path.
	return ProjectSettings.globalize_path("res://").path_join(path).simplify_path()
