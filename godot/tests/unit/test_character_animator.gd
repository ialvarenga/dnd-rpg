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
	return {"name": "unit/test_character_animator", "failures": failures}


static func _test_stable_verb_vocabulary(failures: Array[String]) -> void:
	var animation_set := ActorAnimationSet.new()
	for verb in [&"idle", &"locomotion", &"jump", &"crouch", &"dodge", &"interact", &"attack", &"block", &"hit", &"death"]:
		_expect(animation_set.clip_for(verb) != &"", "animation set has no clip mapping for %s" % verb, failures)
	_expect(animation_set.clip_for(&"unknown") == &"", "animation set mapped an unknown verb", failures)


static func _test_selects_stable_verb_clip(failures: Array[String]) -> void:
	var animator := _animator_with(PackedStringArray(["Idle", "Walk", "Attack"]))
	animator.locomotion_started()
	_expect(animator.current_state == &"locomotion" and animator.current_clip == &"Walk", "locomotion did not select its mapped clip", failures)
	animator.present_attack()
	_expect(animator.current_state == &"attack" and animator.current_clip == &"Attack", "attack did not select its mapped clip", failures)


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
	animation_set.attack = &"Attack"
	animation_set.hit = &"Hit"
	animation_set.death = &"Death"
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
