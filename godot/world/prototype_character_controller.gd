class_name PrototypeCharacterController
extends CharacterBody3D

@export var movement_speed := 5.0
@export var turn_speed := 12.0
@export var target_tolerance := 0.3

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D

var destination := Vector3.ZERO
var destination_state: StringName = &"idle"
var _locomotion := PrototypeLocomotion.new()
var _waiting_for_path := false
var _path_wait_frames := 0


func _ready() -> void:
	_locomotion.speed = movement_speed
	_locomotion.waypoint_tolerance = target_tolerance
	navigation_agent.path_desired_distance = target_tolerance
	navigation_agent.target_desired_distance = target_tolerance


func set_destination(target: Vector3) -> bool:
	if not _is_finite_vector(target):
		_cancel_destination(&"invalid_target")
		return false
	destination = target
	destination_state = &"querying"
	velocity = Vector3.ZERO
	_locomotion.stop()
	_waiting_for_path = true
	_path_wait_frames = 0
	navigation_agent.target_position = target
	return true


func cancel_destination(reason: StringName = &"cancelled") -> void:
	_cancel_destination(reason)


func get_navigation_path() -> PackedVector3Array:
	return _locomotion.get_path()


func get_debug_velocity() -> Vector3:
	return velocity


func _physics_process(delta: float) -> void:
	if _waiting_for_path:
		_try_begin_path()
	if not _locomotion.is_active():
		velocity = Vector3.ZERO
		return

	var step: Dictionary = _locomotion.step(global_position, delta)
	velocity = step["velocity"]
	if bool(step["finished"]):
		destination_state = &"reached"
		return
	if velocity.length_squared() > 0.0001:
		var desired_yaw := atan2(-velocity.x, -velocity.z)
		rotation.y = lerp_angle(rotation.y, desired_yaw, 1.0 - exp(-turn_speed * delta))
	move_and_slide()


func _try_begin_path() -> void:
	_path_wait_frames += 1
	if global_position.distance_to(destination) <= target_tolerance:
		_waiting_for_path = false
		destination_state = &"reached"
		return

	# This call updates NavigationAgent3D's internal path after the navigation
	# map has synchronized. The returned point is consumed by the local follower.
	navigation_agent.get_next_path_position()
	var path := navigation_agent.get_current_navigation_path()
	if navigation_agent.is_target_reachable() and path.size() >= 2:
		_waiting_for_path = false
		var result := _locomotion.begin_path(path, destination)
		if bool(result["accepted"]):
			destination_state = &"moving"
		else:
			_cancel_destination(result["reason"])
		return

	# Navigation maps synchronize asynchronously. Give the region several
	# physics frames, then reject instead of leaving a controller stalled.
	if _path_wait_frames >= 30 or (navigation_agent.is_navigation_finished() and not navigation_agent.is_target_reachable()):
		_cancel_destination(&"unreachable")


func _cancel_destination(reason: StringName) -> void:
	_waiting_for_path = false
	_locomotion.stop()
	velocity = Vector3.ZERO
	destination_state = reason


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
