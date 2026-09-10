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
# The forward shield-arm thrust reads as a push; there is no dedicated shove.
@export var shove: StringName = &"Melee_Block_Attack"
# Death_A falls onto the back, the same side Lie_Idle lies on, so the fall
# blends into the prone loop; Lie_StandUp starts exactly at Lie_Idle's pose.
@export var knockdown: StringName = &"Death_A"
@export var prone: StringName = &"Lie_Idle"
@export var stand_up: StringName = &"Lie_StandUp"

## Seconds from the start of the shove clip to the moment it makes contact, so
## the target's fall (or stagger) lands on the push rather than with its windup.
@export_range(0.0, 2.0, 0.01) var shove_impact_seconds := 0.4

## verb -> playback speed. Lie_StandUp is paced for idle scenes, which is too
## slow to hold up an enemy's turn.
@export var clip_speed_scales: Dictionary = {&"stand_up": 1.4}

## MovementBasic ships Jump_Idle even when the optional General idle clip is
## unavailable.  Individual actor resources can replace this safe fallback.
@export var idle_fallback_clips := PackedStringArray(["Jump_Idle", "T-Pose"])

## Paths are loaded lazily.  General, MovementAdvanced, CombatMelee, and
## Simulation are optional KayKit downloads, so their absence must not make a
## scene invalid.
@export var animation_library_paths := PackedStringArray([
	"res://assets/kaykit_character_animations/Rig_Medium_General.glb",
	"res://assets/kaykit_character_animations/Rig_Medium_MovementAdvanced.glb",
	"res://assets/kaykit_character_animations/Rig_Medium_CombatMelee.glb",
	"res://assets/kaykit_character_animations/Rig_Medium_MovementBasic.glb",
	"res://assets/kaykit_character_animations/Rig_Medium_Simulation.glb",
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
		&"shove": return shove
		&"knockdown": return knockdown
		&"prone": return prone
		&"stand_up": return stand_up
	return &""


func speed_scale_for(verb: StringName) -> float:
	return float(clip_speed_scales.get(verb, 1.0))
