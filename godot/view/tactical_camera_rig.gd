class_name TacticalCameraRig
extends Node3D

@export var pan_speed := 14.0
@export var rotation_speed := 1.45
@export var smoothing_speed := 9.0
@export var minimum_zoom := 10.0
@export var maximum_zoom := 30.0
@export var pan_limit := 27.0

@onready var pivot: Node3D = $Pivot
@onready var camera: Camera3D = $Pivot/Camera3D

var target_focus := Vector3.ZERO
var target_yaw := deg_to_rad(35.0)
var target_zoom := 20.0
var _middle_dragging := false


func _ready() -> void:
	target_focus = global_position
	target_zoom = clampf(camera.position.z, minimum_zoom, maximum_zoom)
	rotation.y = target_yaw
	camera.current = true


func _process(delta: float) -> void:
	var input_vector := Input.get_vector(&"camera_pan_left", &"camera_pan_right", &"camera_pan_forward", &"camera_pan_back")
	if input_vector.length_squared() > 0.0:
		var forward := Vector3(-sin(target_yaw), 0.0, -cos(target_yaw))
		var right := Vector3(forward.z, 0.0, -forward.x)
		# Input.get_vector's forward/back pair is (negative_y, positive_y), so
		# holding "camera_pan_forward" yields input_vector.y == -1 -- negate it
		# so pressing forward actually moves toward `forward`, not away from it.
		target_focus += (right * input_vector.x - forward * input_vector.y) * pan_speed * delta
		_clamp_focus()
	if Input.is_action_pressed(&"camera_rotate_left"):
		target_yaw -= rotation_speed * delta
	if Input.is_action_pressed(&"camera_rotate_right"):
		target_yaw += rotation_speed * delta

	var weight := 1.0 - exp(-smoothing_speed * delta)
	global_position = global_position.lerp(target_focus, weight)
	rotation.y = lerp_angle(rotation.y, target_yaw, weight)
	camera.position.z = lerpf(camera.position.z, target_zoom, weight)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_middle_dragging = event.pressed
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_zoom = clampf(target_zoom - 2.0, minimum_zoom, maximum_zoom)
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_zoom = clampf(target_zoom + 2.0, minimum_zoom, maximum_zoom)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _middle_dragging:
		pan_by_screen_delta(event.relative)
		get_viewport().set_input_as_handled()


func pan_by_screen_delta(relative: Vector2) -> void:
	var forward := Vector3(-sin(target_yaw), 0.0, -cos(target_yaw))
	var right := Vector3(forward.z, 0.0, -forward.x)
	var scale := target_zoom * 0.0018
	target_focus += (-right * relative.x + forward * relative.y) * scale
	_clamp_focus()


func _clamp_focus() -> void:
	target_focus.x = clampf(target_focus.x, -pan_limit, pan_limit)
	target_focus.z = clampf(target_focus.z, -pan_limit, pan_limit)
