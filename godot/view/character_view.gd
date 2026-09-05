class_name CharacterView
extends CharacterBody3D

## Presentation-only movement. It receives already-resolved movement paths and
## never creates commands, performs navigation queries, or mutates BattleState.

signal movement_completed(actor_id: int)

@export var actor_id := 1
@export var movement_speed := 5.0
@export var turn_speed := 12.0
@export var target_tolerance := 0.3

var destination := Vector3.ZERO
var destination_state: StringName = &"idle"
var _locomotion := PrototypeLocomotion.new()
@onready var animator: CharacterAnimator = get_node_or_null("CharacterAnimator") as CharacterAnimator


func _ready() -> void:
	_locomotion.speed = movement_speed
	_locomotion.waypoint_tolerance = target_tolerance
	# AssetCatalog dresses the character from its parent's _ready. Deferring lets
	# this presentation layer find the KayKit model after that replacement.
	call_deferred("_initialize_animations")


func play_movement(path: PackedVector3Array, target: Vector3) -> bool:
	_locomotion.speed = movement_speed
	_locomotion.waypoint_tolerance = target_tolerance
	destination = target
	var result: Dictionary = _locomotion.begin_path(path, target)
	if not bool(result["accepted"]):
		velocity = Vector3.ZERO
		destination_state = result["reason"]
		_notify_locomotion_stopped()
		return false
	if global_position.distance_to(target) <= target_tolerance:
		_finish_movement()
		return true
	destination_state = &"moving"
	_notify_locomotion_started()
	return true


func get_resolved_path() -> PackedVector3Array:
	return _locomotion.get_path()


func get_debug_velocity() -> Vector3:
	return velocity


func is_moving() -> bool:
	return _locomotion.is_active()


func synchronize_to_authoritative_position(position: Vector3) -> void:
	global_position = position
	velocity = Vector3.ZERO
	_notify_locomotion_stopped()


func _physics_process(delta: float) -> void:
	if not _locomotion.is_active():
		velocity = Vector3.ZERO
		_notify_locomotion_stopped()
		return
	var step: Dictionary = _locomotion.step(global_position, delta)
	velocity = step["velocity"]
	if bool(step["finished"]):
		_finish_movement()
		return
	if velocity.length_squared() > 0.0001:
		var desired_yaw := atan2(-velocity.x, -velocity.z)
		rotation.y = lerp_angle(rotation.y, desired_yaw, 1.0 - exp(-turn_speed * delta))
		_notify_locomotion_started()
	move_and_slide()


func _finish_movement() -> void:
	_locomotion.stop()
	velocity = Vector3.ZERO
	destination_state = &"reached"
	global_position = destination
	_notify_locomotion_stopped()
	movement_completed.emit(actor_id)


func _initialize_animations() -> void:
	var model_root := _find_model_root()
	if model_root == null:
		return
	if animator != null:
		animator.configure_model(model_root)
		if _locomotion.is_active():
			animator.locomotion_started()


func _find_model_root() -> Node:
	for child in get_children():
		if child is Node and (child as Node).find_child("Skeleton3D", true, false) != null:
			return child as Node
	return null


func present_attack() -> void:
	if animator != null:
		animator.present_attack()


func present_hit() -> void:
	if animator != null:
		animator.present_hit()


func present_interaction() -> void:
	if animator != null:
		animator.present_interaction()


func present_death() -> void:
	if animator != null:
		animator.present_death()


func _notify_locomotion_started() -> void:
	if animator != null:
		animator.locomotion_started()


func _notify_locomotion_stopped() -> void:
	if animator != null:
		animator.locomotion_stopped()
