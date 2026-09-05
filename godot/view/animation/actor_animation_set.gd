class_name ActorAnimationSet
extends Resource

## View-side vocabulary for a humanoid's animation clips.  These names are
## deliberately independent of actor definitions and simulation rules.

@export var idle: StringName = &"Idle_A"
@export var locomotion: StringName = &"Walking_A"
@export var jump: StringName = &"Jump_A"
@export var crouch: StringName = &"Crouch_A"
@export var dodge: StringName = &"Dodge_A"
@export var interact: StringName = &"Interact_A"
@export var attack: StringName = &"Attack_A"
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
		&"block": return block
		&"hit": return hit
		&"death": return death
	return &""
