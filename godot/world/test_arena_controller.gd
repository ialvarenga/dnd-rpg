class_name TestArenaController
extends Node3D

@onready var camera: Camera3D = $CameraRig/Pivot/Camera3D
@onready var character: PrototypeCharacterController = $PlayerCharacter
@onready var destination_marker: MeshInstance3D = $Debug/DestinationMarker
@onready var path_mesh: MeshInstance3D = $Debug/PathLine
@onready var debug_label: Label = $DebugOverlay/Panel/Label

var _line_mesh := ImmediateMesh.new()


func _ready() -> void:
	path_mesh.mesh = _line_mesh
	destination_marker.visible = false


func _process(_delta: float) -> void:
	_update_debug_view()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var destination: Variant = _terrain_position_from_screen(event.position)
		if destination == null:
			character.cancel_destination(&"outside_terrain")
			destination_marker.visible = false
		else:
			var target: Vector3 = destination
			destination_marker.global_position = target + Vector3.UP * 0.08
			destination_marker.visible = true
			character.set_destination(target)
		get_viewport().set_input_as_handled()


func _terrain_position_from_screen(screen_position: Vector2) -> Variant:
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_end := ray_origin + camera.project_ray_normal(screen_position) * 500.0
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, 1)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit["position"]


func _update_debug_view() -> void:
	var path := character.get_navigation_path()
	_line_mesh.clear_surfaces()
	if path.size() >= 2:
		_line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for point in path:
			_line_mesh.surface_add_vertex(point + Vector3.UP * 0.12)
		_line_mesh.surface_end()
	debug_label.text = "Destination: %s (%s)\nVelocity: %s" % [
		_format_vector(character.destination),
		character.destination_state,
		_format_vector(character.get_debug_velocity()),
	]


func _format_vector(value: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [value.x, value.y, value.z]
