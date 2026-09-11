class_name CharacterView
extends CharacterBody3D

## Presentation-only movement. It receives already-resolved movement paths and
## never creates commands, performs navigation queries, or mutates BattleState.

signal movement_completed(actor_id: int)
## The bow was loosed: EventPlayer launches the arrow from projectile_origin().
signal ranged_released(actor_id: int)

@export var actor_id := 1
@export var movement_speed := 5.0
@export var turn_speed := 12.0
@export var target_tolerance := 0.3

## Set by the composition root through configure_weapon_presentation() before
## this node's deferred _initialize_animations runs. Empty means unarmed.
## The model itself is only attached once combat starts (present_combat_ready).
@export var held_weapon_model_path: String = ""
@export var held_weapon_bone: StringName = &"handslot.r"
@export var held_weapon_rotation_degrees: Vector3 = Vector3.ZERO
## The wielded weapon's projectile (the shortbow's arrow). Empty means a ranged
## attack from this actor is narrated like a melee one, with nothing in flight.
@export var projectile_model_path: String = ""
@export var wields_ranged_weapon := false

const ATTACK_SOUNDS: Array[AudioStream] = [
	preload("res://assets/sfx/combat/Sword_Swing_Long_01.ogg"),
	preload("res://assets/sfx/combat/Sword_Swing_Long_03.ogg"),
	preload("res://assets/sfx/combat/Sword_Swing_Long_05.ogg"),
]
const BOW_DRAW_SOUNDS: Array[AudioStream] = [
	preload("res://assets/sfx/combat/Bow_Draw_01.ogg"),
	preload("res://assets/sfx/combat/Bow_Draw_03.ogg"),
	preload("res://assets/sfx/combat/Bow_Draw_05.ogg"),
]
const BOW_RELEASE_SOUNDS: Array[AudioStream] = [
	preload("res://assets/sfx/combat/Bow_Release_01.ogg"),
	preload("res://assets/sfx/combat/Bow_Release_03.ogg"),
	preload("res://assets/sfx/combat/Bow_Release_05.ogg"),
]
## Where the arrow leaves from when no bow is attached to aim it from.
const PROJECTILE_FALLBACK_HEIGHT := 0.4
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
var _in_combat := false
# Knockdown sequence: a shove's impact is delayed (_knockdown_pending), then
# the fall plays, then the prone loop holds (_is_prone) until the simulation
# stands the actor up (_standing_up). A stand-up narrated mid-fall waits for
# the fall to land (_stand_pending), and a walk narrated before the actor is on
# its feet waits for the stand-up (_pending_movement).
var _is_prone := false
var _knockdown_pending := false
var _stand_pending := false
var _standing_up := false
var _pending_movement: Dictionary = {}
# A bow is being drawn; cleared at the loose (_on_release).
var _shot_pending := false
# Bumped whenever presentation is reset or ends in death, so a delayed impact
# or loose scheduled against the previous presentation never fires into the
# new one.
var _presentation_generation := 0
@onready var animator: CharacterAnimator = get_node_or_null("CharacterAnimator") as CharacterAnimator
@onready var combat_sfx: AudioStreamPlayer3D = get_node_or_null("CombatSfx") as AudioStreamPlayer3D


func _ready() -> void:
	_locomotion.speed = movement_speed
	_locomotion.waypoint_tolerance = target_tolerance
	if animator != null:
		animator.state_finished.connect(_on_animator_state_finished)
	# AssetCatalog dresses the character from its parent's _ready. Deferring lets
	# this presentation layer find the KayKit model after that replacement.
	call_deferred("_initialize_animations")


func play_movement(path: PackedVector3Array, target: Vector3) -> bool:
	if _is_grounded():
		# A prone move narrates its stand-up first; walking must not stomp that
		# clip, so the path waits until the actor is on its feet. Movement with
		# no stand-up narrated still needs one visually, so start it here.
		_pending_movement = {"path": path.duplicate(), "target": target}
		destination = target
		destination_state = &"standing_up"
		if not (_knockdown_pending or _stand_pending or _standing_up):
			present_stand_up()
		return true
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
	return _locomotion.is_active() or not _pending_movement.is_empty()


## True while this view still lags the simulation in a way the next command
## must wait for: a walk, or a fall/stand-up an attack clip would stomp. Lying
## still in the prone loop is not busy -- an actor with no Speed stays there.
func is_presentation_busy() -> bool:
	return is_moving() or _shot_pending or _knockdown_pending or _stand_pending or _standing_up or (animator != null and animator.current_state == &"knockdown")


func synchronize_to_authoritative_position(position: Vector3) -> void:
	global_position = position
	velocity = Vector3.ZERO
	_locomotion_was_active = false
	_notify_locomotion_stopped()


func reset_presentation(actor: ActorState, in_combat: bool = false) -> void:
	_locomotion.stop()
	_is_dead = false
	_clear_knockdown_sequence()
	destination = actor.position
	destination_state = &"idle"
	global_position = actor.position
	velocity = Vector3.ZERO
	_locomotion_was_active = false
	set_target_highlight(false)
	if in_combat:
		present_combat_ready()
	else:
		_in_combat = false
		_detach_held_weapon()
		if animator != null:
			animator.present_combat_ended()
	# A restored checkpoint/save can hold a prone actor: show it already lying
	# down rather than replaying a fall that happened before the restore.
	if actor.has_condition(&"prone"):
		_is_prone = true
		if animator != null:
			animator.request_state(&"prone")


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
		rotation.y = lerp_angle(rotation.y, _yaw_toward(velocity), 1.0 - exp(-turn_speed * delta))
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
		animator.ranged_stance = wields_ranged_weapon
		animator.configure_model(model_root)
		if _locomotion.is_active():
			animator.locomotion_started()


## Everything the view shows of a weapon comes from the wielded item, never
## from the character art: a MapSpec archetype only picks the model, and the
## same model can carry any stat block. `weapon` may be null (unarmed).
func configure_weapon_presentation(weapon: ItemDefinition) -> void:
	held_weapon_model_path = weapon.held_model_path if weapon != null else ""
	held_weapon_bone = weapon.held_bone if weapon != null else &"handslot.r"
	held_weapon_rotation_degrees = weapon.held_rotation_degrees if weapon != null else Vector3.ZERO
	projectile_model_path = weapon.projectile_model_path if weapon != null else ""
	wields_ranged_weapon = weapon != null and weapon.is_ranged_weapon
	if animator != null:
		animator.ranged_stance = wields_ranged_weapon


func present_sneaking(enabled: bool) -> void:
	if animator == null:
		return
	animator.request_state(&"crouch" if enabled else (&"combat_ready" if _in_combat else &"idle"))


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
	attachment.bone_name = held_weapon_bone
	skeleton.add_child(attachment)
	var weapon_model := weapon_scene.instantiate()
	if weapon_model is Node3D:
		(weapon_model as Node3D).rotation_degrees = held_weapon_rotation_degrees
	attachment.add_child(weapon_model)
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


## Only an actor whose weapon has a projectile model can narrate a shot; any
## other ranged attack (say, a thrown dagger) keeps the melee presentation.
func can_present_ranged_attack() -> bool:
	return not projectile_model_path.is_empty() and not _is_dead


## The simulation already settled the attack. Turn toward the target, draw,
## and loose after ranged_release_seconds, emitting ranged_released so the
## EventPlayer can launch the arrow. Without an animator it looses at once.
func present_ranged_attack(target_position: Vector3) -> void:
	if not can_present_ranged_attack():
		return
	_shot_pending = true
	# A prone archer still looses, but a standing draw would pop it upright.
	if not _is_grounded():
		_face_toward(target_position)
		if animator != null:
			animator.present(&"ranged_draw")
	_play_combat_sound(BOW_DRAW_SOUNDS)
	var delay := animator.animation_set.ranged_release_seconds if animator != null and animator.animation_set != null else 0.0
	if delay <= 0.0 or not is_inside_tree():
		_on_release(_presentation_generation)
		return
	get_tree().create_timer(delay).timeout.connect(_on_release.bind(_presentation_generation))


## Where the arrow leaves from: the bow hand once the bow is attached.
func projectile_origin() -> Vector3:
	var skeleton := _model_root.find_child("Skeleton3D", true, false) as Skeleton3D if _model_root != null else null
	var attachment := skeleton.find_child("HeldWeapon", true, false) as Node3D if skeleton != null else null
	if attachment != null:
		return attachment.global_position
	return global_position + Vector3.UP * PROJECTILE_FALLBACK_HEIGHT


func _on_release(generation: int) -> void:
	if generation != _presentation_generation or _is_dead:
		return
	_shot_pending = false
	if animator != null and not _is_grounded():
		animator.present(&"ranged_release")
	_play_combat_sound(BOW_RELEASE_SOUNDS)
	ranged_released.emit(actor_id)


func present_combat_ready() -> void:
	_in_combat = true
	if animator != null and not _is_grounded():
		animator.present_combat_ready()
	_attach_held_weapon()


func present_combat_ended() -> void:
	# A dead actor stays exactly as it fell -- combat wrapping up must not
	# raise a corpse back to its idle/weapon-ready presentation.
	if _is_dead:
		return
	_in_combat = false
	_detach_held_weapon()
	# A stand-up narrated just before combat ended settles into idle itself.
	if animator != null and not _is_grounded():
		animator.present_combat_ended()


func present_dodge() -> void:
	if animator != null and not _is_grounded():
		animator.present_dodge()


func present_hit() -> void:
	# A standing hit reaction would pop a prone actor back onto its feet.
	if animator != null and not _is_grounded():
		animator.present_hit()
	_play_combat_sound(HURT_SOUNDS)


func present_interaction() -> void:
	if animator != null:
		animator.present_interaction()


## Plays an ability's dedicated animation (AbilityDefinition.animation_verb)
## turned toward its target, e.g. the shove's push.
func present_ability(verb: StringName, target_position: Vector3) -> void:
	if _is_dead:
		return
	_face_toward(target_position)
	if animator != null:
		animator.present(verb)


## The simulation already applied Prone. Face the shover so the backward fall
## lands away from it, and hold the fall until the push connects.
func present_knockdown(source_position: Vector3) -> void:
	if _is_dead or (_is_prone and not _standing_up):
		return
	_is_prone = true
	_standing_up = false
	_stand_pending = false
	_knockdown_pending = true
	_face_toward(source_position)
	_after_impact(&"knockdown")


## A successful save against a push: stagger in place once the push connects.
func present_resisted() -> void:
	if not _is_dead and not _is_grounded():
		_after_impact(&"resisted")


func present_stand_up() -> void:
	if _is_dead:
		return
	if _knockdown_pending or (animator != null and animator.current_state == &"knockdown"):
		_stand_pending = true
		return
	if _is_prone:
		_begin_stand_up()


func present_death() -> void:
	# Mid-fall the death clip simply continues the knockdown's Death_A.
	var lying_down := _is_prone and not _knockdown_pending and (animator == null or animator.current_state != &"knockdown")
	_is_dead = true
	_clear_knockdown_sequence()
	_locomotion.stop()
	velocity = Vector3.ZERO
	destination_state = &"dead"
	_locomotion_was_active = false
	set_target_highlight(false)
	if animator == null:
		return
	if lying_down:
		# Already on the ground: replaying the fall would stand the body up
		# first. Freeze the prone pose where it lies instead.
		animator.hold_pose(&"death")
	else:
		animator.present_death()


func _is_grounded() -> bool:
	return _is_prone or _knockdown_pending or _stand_pending or _standing_up


func _clear_knockdown_sequence() -> void:
	_presentation_generation += 1
	# The generation bump orphans a pending loose too.
	_shot_pending = false
	_is_prone = false
	_knockdown_pending = false
	_stand_pending = false
	_standing_up = false
	_pending_movement = {}


## Runs `impact` once the shove clip reaches contact. Bound to this node (not
## a lambda) so a freed view silently drops the timer instead of erroring.
func _after_impact(impact: StringName) -> void:
	var delay := animator.animation_set.shove_impact_seconds if animator != null and animator.animation_set != null else 0.0
	if delay <= 0.0 or not is_inside_tree():
		_on_impact(_presentation_generation, impact)
		return
	get_tree().create_timer(delay).timeout.connect(_on_impact.bind(_presentation_generation, impact))


func _on_impact(generation: int, impact: StringName) -> void:
	if generation != _presentation_generation or _is_dead:
		return
	match impact:
		&"knockdown":
			_knockdown_pending = false
			_play_combat_sound(HURT_SOUNDS)
			if animator == null:
				return
			animator.request_state(&"knockdown")
			# Without a fall clip there is nothing to wait for.
			if animator.current_state != &"knockdown":
				_on_knockdown_landed()
		&"resisted":
			if animator != null and not _is_grounded():
				animator.present_hit()


func _on_animator_state_finished(state: StringName) -> void:
	if _is_dead:
		return
	match state:
		&"knockdown":
			_on_knockdown_landed()
		&"stand_up":
			_finish_stand_up()
		&"ranged_release":
			# Settle back into the bow at the ready once the follow-through ends.
			if _in_combat and animator != null and not _is_grounded():
				animator.present_combat_ready()


func _on_knockdown_landed() -> void:
	if _stand_pending:
		_begin_stand_up()
	elif animator != null:
		animator.request_state(&"prone")


func _begin_stand_up() -> void:
	_is_prone = false
	_stand_pending = false
	_standing_up = true
	if animator != null:
		animator.request_state(&"stand_up")
	# Without a stand-up clip no finish signal will come.
	if animator == null or animator.current_state != &"stand_up":
		_finish_stand_up()


func _finish_stand_up() -> void:
	_standing_up = false
	if animator != null:
		if _in_combat:
			animator.present_combat_ready()
		else:
			animator.present_combat_ended()
	if not _pending_movement.is_empty():
		var pending := _pending_movement
		_pending_movement = {}
		play_movement(pending["path"], pending["target"])


func _face_toward(point: Vector3) -> void:
	var direction := point - global_position
	if Vector2(direction.x, direction.z).length_squared() > 0.0001:
		rotation.y = _yaw_toward(direction)


func _yaw_toward(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


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
	if animator != null and not _is_dead and not _is_grounded():
		animator.locomotion_started()


## Guarded against _is_dead too: every locomotion call site (movement
## rejection, synchronize_to_authoritative_position, _finish_movement, plus
## the physics-process branches) shares this one path, so guarding it here
## once keeps a dead actor's death presentation from being overwritten no
## matter which of those still runs after the fatal blow lands. The same holds
## for a fall, the prone loop, and a stand-up.
func _notify_locomotion_stopped() -> void:
	if animator != null and not _is_dead and not _is_grounded():
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
