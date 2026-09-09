class_name DestinationClickMarker
extends MeshInstance3D

## Brief exploration-mode feedback for a confirmed terrain click.

const MARKER_COLOR := Color("f5d742")
const GROUND_LIFT := 0.07
const DISPLAY_DURATION := 1.15
const FADE_START := 0.55

var _elapsed := 0.0
var _material: StandardMaterial3D


func _ready() -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.42
	ring.outer_radius = 0.56
	ring.rings = 32
	ring.ring_segments = 8
	mesh = ring
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = Color(MARKER_COLOR, 0.9)
	_material.emission_enabled = true
	_material.emission = MARKER_COLOR
	material_override = _material
	hide_marker()


func show_at(world_position: Vector3) -> void:
	global_position = world_position + Vector3.UP * GROUND_LIFT
	_elapsed = 0.0
	scale = Vector3(0.72, 1.0, 0.72)
	_set_alpha(0.9)
	visible = true
	set_process(true)


func hide_marker() -> void:
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	_elapsed += delta
	var progress := clampf(_elapsed / DISPLAY_DURATION, 0.0, 1.0)
	var reveal := smoothstep(0.0, 0.18, progress)
	var marker_scale := lerpf(0.72, 1.0, reveal)
	scale = Vector3(marker_scale, 1.0, marker_scale)
	_set_alpha(0.9 * (1.0 - smoothstep(FADE_START, 1.0, progress)))
	if progress >= 1.0:
		hide_marker()


func _set_alpha(alpha: float) -> void:
	if _material != null:
		_material.albedo_color = Color(MARKER_COLOR, alpha)
