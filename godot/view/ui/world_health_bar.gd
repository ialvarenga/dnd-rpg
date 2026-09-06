class_name WorldHealthBar
extends Node3D

@export var fraction := 1.0:
	set(value):
		fraction = clampf(value, 0.0, 1.0)
		if is_inside_tree():
			_redraw()

func _ready() -> void:
	_redraw()

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null: look_at(camera.global_position, Vector3.UP, true)

func _redraw() -> void:
	for child in get_children(): child.queue_free()
	var back := MeshInstance3D.new(); back.mesh = _quad(Color(0.12, 0.02, 0.02), 1.0); add_child(back)
	var fill := MeshInstance3D.new(); fill.mesh = _quad(Color(0.1, 0.9, 0.2), fraction); fill.position.x = -(1.0 - fraction) * 0.5; add_child(fill)

func _quad(color: Color, width: float) -> QuadMesh:
	var mesh := QuadMesh.new(); mesh.size = Vector2(width, 0.12)
	var material := StandardMaterial3D.new(); material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; material.albedo_color = color; mesh.material = material
	return mesh
