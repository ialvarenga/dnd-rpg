class_name CharacterView
extends CharacterBody3D

## Presentation-only movement. It receives already-resolved movement paths and
## never creates commands, performs navigation queries, or mutates BattleState.

signal movement_completed(actor_id: int)

const MOVEMENT_ANIMATION_SCENE: PackedScene = preload("res://assets/kaykit_character_animations/Rig_Medium_MovementBasic.glb")

@export var actor_id := 1
@export var movement_speed := 5.0
@export var turn_speed := 12.0
@export var target_tolerance := 0.3
@export var walk_animation: StringName = &"Walking_A"
@export_range(0.0, 1.0, 0.01) var animation_blend_seconds := 0.15

var destination := Vector3.ZERO
var destination_state: StringName = &"idle"
var _locomotion := PrototypeLocomotion.new()
var _animation_player: AnimationPlayer
var _resolved_walk_animation: StringName = &""


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
	var result := _locomotion.begin_path(path, target)
	if not bool(result["accepted"]):
		velocity = Vector3.ZERO
		destination_state = result["reason"]
		_stop_walk_animation()
		return false
	if global_position.distance_to(target) <= target_tolerance:
		_finish_movement()
		return true
	destination_state = &"moving"
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
	_stop_walk_animation()


func _physics_process(delta: float) -> void:
	if not _locomotion.is_active():
		velocity = Vector3.ZERO
		_stop_walk_animation()
		return
	var step: Dictionary = _locomotion.step(global_position, delta)
	velocity = step["velocity"]
	if bool(step["finished"]):
		_finish_movement()
		return
	if velocity.length_squared() > 0.0001:
		var desired_yaw := atan2(-velocity.x, -velocity.z)
		rotation.y = lerp_angle(rotation.y, desired_yaw, 1.0 - exp(-turn_speed * delta))
		_play_walk_animation()
	move_and_slide()


func _finish_movement() -> void:
	_locomotion.stop()
	velocity = Vector3.ZERO
	destination_state = &"reached"
	global_position = destination
	_stop_walk_animation()
	movement_completed.emit(actor_id)


func _initialize_animations() -> void:
	var model_root := _find_model_root()
	if model_root == null:
		return
	_animation_player = _find_animation_player(model_root)
	if not _has_animation(_animation_player, walk_animation):
		var animation_source := MOVEMENT_ANIMATION_SCENE.instantiate()
		var source_player := _find_animation_player(animation_source)
		if source_player == null:
			push_error("KayKit movement animation scene has no AnimationPlayer")
			animation_source.queue_free()
			return
		source_player.owner = null
		source_player.reparent(model_root)
		source_player.name = "MovementAnimationPlayer"
		source_player.root_node = NodePath("..")
		animation_source.queue_free()
		_animation_player = source_player
	_resolved_walk_animation = _resolve_animation_name(_animation_player, walk_animation)
	if _locomotion.is_active():
		_play_walk_animation()


func _find_model_root() -> Node:
	for child in get_children():
		if child is Node and (child as Node).find_child("Skeleton3D", true, false) != null:
			return child as Node
	return null


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	return root.find_child("AnimationPlayer", true, false) as AnimationPlayer


func _has_animation(player: AnimationPlayer, animation_name: StringName) -> bool:
	return _resolve_animation_name(player, animation_name) != &""


func _resolve_animation_name(player: AnimationPlayer, animation_name: StringName) -> StringName:
	if player == null:
		return &""
	for available_name in player.get_animation_list():
		var available_text := String(available_name)
		if available_name == animation_name or available_text.get_file() == String(animation_name):
			return available_name
	return &""


func _play_walk_animation() -> void:
	if _animation_player == null or _resolved_walk_animation == &"":
		return
	if _animation_player.current_animation != _resolved_walk_animation or not _animation_player.is_playing():
		_animation_player.play(_resolved_walk_animation, animation_blend_seconds)


func _stop_walk_animation() -> void:
	if _animation_player != null and _animation_player.is_playing():
		_animation_player.stop()
