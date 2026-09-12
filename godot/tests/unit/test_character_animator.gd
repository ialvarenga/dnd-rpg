class_name TestCharacterAnimator
extends RefCounted

static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_stable_verb_vocabulary(failures)
	_test_selects_stable_verb_clip(failures)
	_test_missing_verb_falls_back_to_idle(failures)
	_test_missing_idle_uses_safe_fallback(failures)
	_test_missing_idle_uses_available_safe_clip(failures)
	_test_no_available_clip_is_safe(failures)
	_test_state_finished_reports_only_the_current_clip(failures)
	_test_hold_pose_relabels_without_changing_clip(failures)
	_test_ranged_stance_selects_bow_ready(failures)
	_test_jump_verbs_resolve_to_real_rig_clips(failures)
	_test_locomotion_is_paced_by_the_view_speed(failures)
	_test_locomotion_falls_back_to_the_clip_the_rig_ships(failures)
	return {"name": "unit/test_character_animator", "failures": failures}


## A clip played at its own pace while the view slides along at metres per
## second is what reads as skating: the walk covers 0.75 m/s and the run
## 1.8 m/s, so the view's speed has to pick between them and stretch the one it
## picks. Without a speed (0) nothing is stretched.
static func _test_locomotion_is_paced_by_the_view_speed(failures: Array[String]) -> void:
	var animation_set := ActorAnimationSet.new()
	var strolling: Dictionary = animation_set.locomotion_for(0.8)[0]
	_expect(strolling["clip"] == animation_set.locomotion and is_equal_approx(float(strolling["speed_scale"]), 0.8 / animation_set.locomotion_meters_per_second), "a stroll did not walk at its own pace", failures)
	var travelling: Dictionary = animation_set.locomotion_for(4.0)[0]
	_expect(travelling["clip"] == animation_set.locomotion_run and is_equal_approx(float(travelling["speed_scale"]), 4.0 / animation_set.locomotion_run_meters_per_second), "travelling at 4 m/s did not pick the run and pace it to the ground", failures)
	var sprinting: Dictionary = animation_set.locomotion_for(40.0)[0]
	_expect(is_equal_approx(float(sprinting["speed_scale"]), animation_set.locomotion_speed_scale_limits.y), "an absurd speed was not capped to the authored stretch limit", failures)

	var animator := _animator_with(PackedStringArray(["Idle", "Walk", "Run"]))
	animator.locomotion_speed_mps = 4.0
	animator.locomotion_started()
	_expect(animator.current_state == &"locomotion" and animator.current_clip == &"Run", "a view moving at 4 m/s did not run", failures)
	animator.locomotion_stopped()
	animator.locomotion_speed_mps = 0.8
	animator.locomotion_started()
	_expect(animator.current_state == &"locomotion" and animator.current_clip == &"Walk", "a view moving at 0.8 m/s did not walk", failures)


static func _test_locomotion_falls_back_to_the_clip_the_rig_ships(failures: Array[String]) -> void:
	var walk_only := _animator_with(PackedStringArray(["Idle", "Walk"]))
	walk_only.locomotion_speed_mps = 4.0
	walk_only.locomotion_started()
	_expect(walk_only.current_state == &"locomotion" and walk_only.current_clip == &"Walk", "a rig without a run clip did not keep moving on its walk", failures)
	var unpaced := _animator_with(PackedStringArray(["Idle", "Walk", "Run"]))
	unpaced.locomotion_started()
	_expect(unpaced.current_state == &"locomotion" and unpaced.current_clip == &"Walk", "a view with no speed set did not keep the authored locomotion clip", failures)


static func _test_ranged_stance_selects_bow_ready(failures: Array[String]) -> void:
	var melee := _animator_with(PackedStringArray(["Idle", "CombatReady", "BowReady"]))
	melee.present_combat_ready()
	_expect(melee.current_state == &"combat_ready" and melee.current_clip == &"CombatReady", "a melee wielder should keep the melee guard as its combat stance", failures)
	var archer := _animator_with(PackedStringArray(["Idle", "CombatReady", "BowReady"]))
	archer.ranged_stance = true
	archer.present_combat_ready()
	_expect(archer.current_state == &"ranged_ready" and archer.current_clip == &"BowReady", "a ranged wielder should hold the bow at the ready in combat", failures)
	var archer_without_clip := _animator_with(PackedStringArray(["Idle", "CombatReady"]))
	archer_without_clip.ranged_stance = true
	archer_without_clip.present_combat_ready()
	_expect(archer_without_clip.current_state == &"combat_ready", "a ranged wielder without the bow clip should fall back to the melee guard", failures)


static func _test_stable_verb_vocabulary(failures: Array[String]) -> void:
	var animation_set := ActorAnimationSet.new()
	for verb in [&"idle", &"locomotion", &"jump", &"jump_start", &"jump_air", &"jump_land", &"crouch", &"dodge", &"interact", &"attack", &"combat_ready", &"block", &"hit", &"death", &"shove", &"knockdown", &"prone", &"stand_up", &"ranged_ready", &"ranged_draw", &"ranged_release"]:
		_expect(animation_set.clip_for(verb) != &"", "animation set has no clip mapping for %s" % verb, failures)
	_expect(animation_set.clip_for(&"unknown") == &"", "animation set mapped an unknown verb", failures)
	_expect(is_equal_approx(animation_set.speed_scale_for(&"stand_up"), 1.4) and is_equal_approx(animation_set.speed_scale_for(&"idle"), 1.0), "animation set did not scale only the stand-up clip", failures)
	_expect(animation_set.clip_for(&"ranged_ready") == &"Ranged_Bow_Idle" and animation_set.clip_for(&"ranged_draw") == &"Ranged_Bow_Draw" and animation_set.clip_for(&"ranged_release") == &"Ranged_Bow_Release", "the ranged verbs should map to KayKit's bow clips", failures)
	_expect(animation_set.animation_library_paths.has("res://assets/kaykit_character_animations/Rig_Medium_CombatRanged.glb"), "the default set should load the CombatRanged library for the bow clips", failures)


## ADR-009: the jump verbs must name clips the MovementBasic rig really ships
## (the old "Jump_A" existed in none), and the airborne hang must loop so a
## tall drop never freezes on its last frame.
static func _test_jump_verbs_resolve_to_real_rig_clips(failures: Array[String]) -> void:
	var scene := load("res://assets/kaykit_character_animations/Rig_Medium_MovementBasic.glb") as PackedScene
	_expect(scene != null, "the MovementBasic rig did not load", failures)
	if scene == null:
		return
	var root := scene.instantiate()
	var player := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var animation_set := ActorAnimationSet.new()
	var clips := {}
	for name in player.get_animation_list():
		clips[String(name).get_file()] = player.get_animation(name)
	for verb in [&"jump_start", &"jump_air", &"jump_land"]:
		_expect(clips.has(String(animation_set.clip_for(verb))), "jump verb %s maps to a clip the rig does not ship" % verb, failures)
	var hang: Animation = clips.get(String(animation_set.clip_for(&"jump_air")))
	_expect(hang != null and hang.loop_mode != Animation.LOOP_NONE, "the airborne jump clip does not loop", failures)
	root.free()


static func _test_state_finished_reports_only_the_current_clip(failures: Array[String]) -> void:
	var animator := _animator_with(PackedStringArray(["Idle", "Fall", "Lie"]))
	var finished: Array[StringName] = []
	animator.state_finished.connect(func(state: StringName): finished.append(state))
	var player: AnimationPlayer = animator._players[0]
	animator.present(&"knockdown")
	player.animation_finished.emit(&"test/Idle")
	_expect(finished.is_empty(), "a clip that is no longer current reported a finished state", failures)
	player.animation_finished.emit(&"test/Fall")
	_expect(finished == [&"knockdown"], "the current knockdown clip did not report its finished state", failures)


static func _test_hold_pose_relabels_without_changing_clip(failures: Array[String]) -> void:
	var animator := _animator_with(PackedStringArray(["Idle", "Lie"]))
	animator.present(&"prone")
	animator.hold_pose(&"death")
	_expect(animator.current_state == &"death" and animator.current_clip == &"Lie", "hold_pose did not keep the lying clip under the death state", failures)


static func _test_selects_stable_verb_clip(failures: Array[String]) -> void:
	var animator := _animator_with(PackedStringArray(["Idle", "Walk", "Attack", "CombatReady"]))
	animator.locomotion_started()
	_expect(animator.current_state == &"locomotion" and animator.current_clip == &"Walk", "locomotion did not select its mapped clip", failures)
	animator.present_attack()
	_expect(animator.current_state == &"attack" and animator.current_clip == &"Attack", "attack did not select its mapped clip", failures)
	animator.present_combat_ready()
	_expect(animator.current_state == &"combat_ready" and animator.current_clip == &"CombatReady", "combat entry did not select its mapped clip", failures)


static func _test_missing_verb_falls_back_to_idle(failures: Array[String]) -> void:
	var animator := _animator_with(PackedStringArray(["Idle"]))
	animator.present_hit()
	_expect(animator.current_state == &"idle" and animator.current_clip == &"Idle", "missing hit clip did not fall back to idle", failures)


static func _test_no_available_clip_is_safe(failures: Array[String]) -> void:
	var animator := _animator_with(PackedStringArray())
	animator.present_death()
	_expect(animator.current_state == &"idle" and animator.current_clip == &"", "missing libraries did not degrade safely", failures)


static func _test_missing_idle_uses_safe_fallback(failures: Array[String]) -> void:
	var animator := _animator_with(PackedStringArray(["Jump_Idle"]))
	animator.locomotion_stopped()
	_expect(animator.current_state == &"idle" and animator.current_clip == &"Jump_Idle", "missing idle did not use a safe fallback clip", failures)


static func _test_missing_idle_uses_available_safe_clip(failures: Array[String]) -> void:
	var animator := _animator_with(PackedStringArray(["Walk"]))
	animator.present_hit()
	_expect(animator.current_state == &"idle" and animator.current_clip == &"Walk", "missing idle did not use the available locomotion clip", failures)


static func _animator_with(clips: PackedStringArray) -> CharacterAnimator:
	var animation_set := ActorAnimationSet.new()
	animation_set.idle = &"Idle"
	animation_set.locomotion = &"Walk"
	animation_set.locomotion_run = &"Run"
	animation_set.attack = &"Attack"
	animation_set.combat_ready = &"CombatReady"
	animation_set.hit = &"Hit"
	animation_set.death = &"Death"
	animation_set.knockdown = &"Fall"
	animation_set.prone = &"Lie"
	animation_set.ranged_ready = &"BowReady"
	var player := AnimationPlayer.new()
	var library := AnimationLibrary.new()
	for clip in clips:
		library.add_animation(clip, Animation.new())
	player.add_animation_library(&"test", library)
	var animator := CharacterAnimator.new()
	animator.animation_set = animation_set
	animator.configure_players([player])
	return animator


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
