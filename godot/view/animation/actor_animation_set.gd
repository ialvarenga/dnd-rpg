class_name ActorAnimationSet
extends Resource

## View-side vocabulary for a humanoid's animation clips.  These names are
## deliberately independent of actor definitions and simulation rules.

@export var idle: StringName = &"Idle_A"
@export var locomotion: StringName = &"Walking_A"
@export var jump: StringName = &"Jump_A"
@export var crouch: StringName = &"Crouch_A"
# MovementAdvanced has no plain "Dodge_A" -- Backward is the reactive step
# used to narrate a missed incoming attack.
@export var dodge: StringName = &"Dodge_Backward"
@export var interact: StringName = &"Interact"
# Knight's longsword uses the one-handed horizontal slice from KayKit's
# CombatMelee library.
@export var attack: StringName = &"Melee_1H_Attack_Slice_Horizontal"
# CombatMelee has no one-handed-only idle (only Melee_2H_Idle and
# Melee_Unarmed_Idle, both wrong-handed for a 1H weapon with no shield).
# Melee_Blocking -- the raised-guard loop -- is the closest available
# weapon-ready pose and is reused here rather than left unanimated.
@export var combat_ready: StringName = &"Melee_Blocking"
@export var block: StringName = &"Block_A"
@export var hit: StringName = &"Hit_A"
@export var death: StringName = &"Death_A"

## MovementBasic ships Jump_Idle even when the optional General idle clip is
## unavailable.  Individual actor resources can replace this safe fallback.
@export var idle_fallback_clips := PackedStringArray(["Jump_Idle", "T-Pose"])

## Paths are loaded lazily.  General, MovementAdvanced, and CombatMelee are
## optional KayKit downloads, so their absence must not make a scene invalid.
@export var animation_library_paths := PackedStringArray([
	"res://assets/kaykit_character_animations/Rig_Medium_General.glb",
	"res://assets/kaykit_character_animations/Rig_Medium_MovementAdvanced.glb",
	"res://assets/kaykit_character_animations/Rig_Medium_CombatMelee.glb",
	"res://assets/kaykit_character_animations/Rig_Medium_MovementBasic.glb",
])


func clip_for(verb: StringName) -> StringName:
	match verb:
		&"idle": return idle
		&"locomotion": return locomotion
		&"jump": return jump
		&"crouch": return crouch
		&"dodge": return dodge
		&"interact": return interact
		&"attack": return attack
		&"combat_ready": return combat_ready
		&"block": return block
		&"hit": return hit
		&"death": return death
	return &""
