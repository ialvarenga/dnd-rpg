class_name CharacterView
extends CharacterBody3D

## Presentation-only movement. It receives already-resolved movement paths and
## never creates commands, performs navigation queries, or mutates BattleState.

signal movement_completed(actor_id: int)

@export var actor_id := 1
@export var movement_speed := 5.0
@export var turn_speed := 12.0
@export var target_tolerance := 0.3

## Set by the composition root (from Equipment.held_weapon_model_path) before
## this node's deferred _initialize_animations runs. Empty means unarmed.
## The model itself is only attached once combat starts (present_combat_ready).
@export var held_weapon_model_path: String = ""

const WEAPON_HAND_BONE := &"handslot.r"
const ATTACK_SOUNDS: Array[AudioStream] = [
	preload("res://assets/sfx/combat/Sword_Swing_Long_01.ogg"),
	preload("res://assets/sfx/combat/Sword_Swing_Long_03.ogg"),
	preload("res://assets/sfx/combat/Sword_Swing_Long_05.ogg"),
]
const HURT_SOUNDS: Array[AudioStream] = [
	preload("res://assets/sfx/characters/hurt_01.mp3"),
	preload("res://assets/sfx/characters/hurt_05.mp3"),
]

var destination := Vector3.ZERO
var destination_state: StringName = &"idle"
var _locomotion := PrototypeLocomotion.new()
var _locomotion_was_active := false
var _target_highlight: MeshInstance3D
var _target_highlight_material: StandardMaterial3D
var _model_root: Node
var _weapon_attached := false
var _is_dead := false
@onready var animator: CharacterAnimator = get_node_or_null("CharacterAnimator") as CharacterAnimator
@onready var combat_sfx: AudioStreamPlayer3D = get_node_or_null("CombatSfx") as AudioStreamPlayer3D


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
	_locomotion_was_active = false
	_notify_locomotion_stopped()


func reset_presentation(actor: ActorState, in_combat: bool = false) -> void:
	_locomotion.stop()
	_is_dead = false
	destination = actor.position
	destination_state = &"idle"
	global_position = actor.position
	velocity = Vector3.ZERO
	_locomotion_was_active = false
	set_target_highlight(false)
	if in_combat:
		present_combat_ready()
	else:
		_detach_held_weapon()
		if animator != null:
			animator.present_combat_ended()


func _physics_process(delta: float) -> void:
	if not _locomotion.is_active():
		velocity = Vector3.ZERO
		# A combat event can arrive just as an actor finishes visual movement.
		# In that case, only locomotion/idle may transition back to idle; otherwise
		# the cleanup would immediately hide attack, hit, or death presentation.
		if _locomotion_was_active:
			_locomotion_was_active = false
			if animator == null or animator.current_state in [&"locomotion", &"idle"]:
				_notify_locomotion_stopped()
		return
	_locomotion_was_active = true
	var step: Dictionary = _locomotion.step(global_position, delta)
	velocity = step["velocity"]
	if bool(step["finished"]):
		_finish_movement()
		return
	if velocity.length_squared() > 0.0001:
		var desired_yaw := atan2(-velocity.x, -velocity.z)
		rotation.y = lerp_angle(rotation.y, desired_yaw, 1.0 - exp(-turn_speed * delta))
		# Same guard as the stopped branch above: a death/attack/hit narrated
		# while this actor's walk is still interpolating must not be stomped
		# back to locomotion on the very next tick.
		if animator == null or animator.current_state in [&"locomotion", &"idle"]:
			_notify_locomotion_started()
	move_and_slide()


func _finish_movement() -> void:
	_locomotion.stop()
	velocity = Vector3.ZERO
	destination_state = &"reached"
	global_position = destination
	_locomotion_was_active = false
	_notify_locomotion_stopped()
	movement_completed.emit(actor_id)


func _initialize_animations() -> void:
	var model_root := _find_model_root()
	if model_root == null:
		return
	_model_root = model_root
	if animator != null:
		animator.configure_model(model_root)
		if _locomotion.is_active():
			animator.locomotion_started()


## Sheathed until combat starts: called from present_combat_ready() rather
## than dress-time, and idempotent so a later encounter's combat_started
## doesn't attach a second copy. There is no equip command in this milestone
## (Equipment), so the held model never needs to change once drawn.
func _attach_held_weapon() -> void:
	if _weapon_attached or held_weapon_model_path.is_empty() or _model_root == null:
		return
	var weapon_scene := load(held_weapon_model_path) as PackedScene
	if weapon_scene == null:
		return
	var skeleton := _model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = "HeldWeapon"
	attachment.bone_name = WEAPON_HAND_BONE
	skeleton.add_child(attachment)
	attachment.add_child(weapon_scene.instantiate())
	_weapon_attached = true


func _detach_held_weapon() -> void:
	if not _weapon_attached or _model_root == null:
		return
	var skeleton := _model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var attachment := skeleton.find_child("HeldWeapon", true, false) if skeleton != null else null
	if attachment != null:
		attachment.queue_free()
	_weapon_attached = false


func _find_model_root() -> Node:
	for child in get_children():
		if child is Node and (child as Node).find_child("Skeleton3D", true, false) != null:
			return child as Node
	return null


func present_attack() -> void:
	if animator != null:
		animator.present_attack()
	_play_combat_sound(ATTACK_SOUNDS)


func present_combat_ready() -> void:
	if animator != null:
		animator.present_combat_ready()
	_attach_held_weapon()


func present_combat_ended() -> void:
	# A dead actor stays exactly as it fell -- combat wrapping up must not
	# raise a corpse back to its idle/weapon-ready presentation.
	if _is_dead:
		return
	_detach_held_weapon()
	if animator != null:
		animator.present_combat_ended()


func present_dodge() -> void:
	if animator != null:
		animator.present_dodge()


func present_hit() -> void:
	if animator != null:
		animator.present_hit()
	_play_combat_sound(HURT_SOUNDS)


func present_interaction() -> void:
	if animator != null:
		animator.present_interaction()


func present_death() -> void:
	_is_dead = true
	_locomotion.stop()
	velocity = Vector3.ZERO
	destination_state = &"dead"
	_locomotion_was_active = false
	set_target_highlight(false)
	if animator != null:
		animator.present_death()


func set_target_highlight(active: bool, in_range: bool = true) -> void:
	if _target_highlight == null:
		_target_highlight = MeshInstance3D.new()
		_target_highlight.name = "TargetHighlight"
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.72
		mesh.bottom_radius = 0.72
		mesh.height = 0.035
		mesh.radial_segments = 32
		_target_highlight.mesh = mesh
		_target_highlight.position = Vector3(0.0, -0.88, 0.0)
		_target_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_target_highlight_material = StandardMaterial3D.new()
		_target_highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_target_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_target_highlight_material.emission_enabled = true
		_target_highlight.material_override = _target_highlight_material
		add_child(_target_highlight)
	_target_highlight.visible = active
	if active:
		var color := Color("76e887") if in_range else Color("ef625d")
		_target_highlight_material.albedo_color = Color(color.r, color.g, color.b, 0.58)
		_target_highlight_material.emission = color


func _notify_locomotion_started() -> void:
	if animator != null and not _is_dead:
		animator.locomotion_started()


## Guarded against _is_dead too: every locomotion call site (movement
## rejection, synchronize_to_authoritative_position, _finish_movement, plus
## the physics-process branches) shares this one path, so guarding it here
## once keeps a dead actor's death presentation from being overwritten no
## matter which of those still runs after the fatal blow lands.
func _notify_locomotion_stopped() -> void:
	if animator != null and not _is_dead:
		animator.locomotion_stopped()


## Each actor owns its playback node, so the attack comes from the attacker
## and the hurt sound comes from the target. The event presenter calls these
## methods only after combat has been resolved, keeping this strictly view-side.
func _play_combat_sound(sounds: Array[AudioStream]) -> void:
	if combat_sfx == null or sounds.is_empty():
		return
	combat_sfx.stream = sounds.pick_random()
	combat_sfx.pitch_scale = randf_range(0.96, 1.04)
	combat_sfx.play()
