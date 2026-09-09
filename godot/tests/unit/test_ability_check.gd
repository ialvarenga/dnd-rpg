class_name TestAbilityCheck
extends RefCounted

## AbilityCheck is a façade, so these tests mostly prove it delegates rather
## than re-implements: the modifier comes from ActorState, the roll from
## D20Test, and the rng_state is threaded like every other roll.

const AbilityCheckRules = preload("res://sim/rules/ability_check.gd")


static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_ability_score_vocabulary(failures)
	_test_skill_to_ability_mapping(failures)
	_test_modifier_adds_proficiency_only_when_proficient(failures)
	_test_modifier_delegates_to_actor_state(failures)
	_test_roll_is_deterministic_and_threads_rng(failures)
	_test_success_compares_total_against_dc(failures)
	return {"name": "unit/test_ability_check", "failures": failures}


static func _actor(charisma: int = 16, proficiency_bonus: int = 2) -> ActorState:
	var actor := ActorState.new()
	actor.id = 1
	actor.charisma = charisma
	actor.proficiency_bonus = proficiency_bonus
	return actor


static func _test_ability_score_vocabulary(failures: Array[String]) -> void:
	for ability in [&"strength", &"dexterity", &"constitution", &"intelligence", &"wisdom", &"charisma"]:
		_expect(AbilityCheckRules.is_ability_score(ability), "'%s' should be a recognized ability score" % ability, failures)
	# A skill is not an ability score: this is what stops a command carrying
	# "persuasion" where the resolver expects a score.
	_expect(not AbilityCheckRules.is_ability_score(&"persuasion"), "a skill name must not pass as an ability score", failures)
	_expect(not AbilityCheckRules.is_ability_score(&""), "an empty ability must not pass as an ability score", failures)


static func _test_skill_to_ability_mapping(failures: Array[String]) -> void:
	_expect(AbilityCheckRules.ability_for_skill(&"persuasion") == &"charisma", "persuasion should map to charisma", failures)
	_expect(AbilityCheckRules.ability_for_skill(&"deception") == &"charisma", "deception should map to charisma", failures)
	_expect(AbilityCheckRules.ability_for_skill(&"intimidation") == &"charisma", "intimidation should map to charisma", failures)
	_expect(AbilityCheckRules.ability_for_skill(&"insight") == &"wisdom", "insight should map to wisdom", failures)
	_expect(AbilityCheckRules.ability_for_skill(&"athletics") == &"strength", "athletics should map to strength", failures)
	_expect(AbilityCheckRules.ability_for_skill(&"lockpicking") == &"", "an unknown skill should map to no ability", failures)


static func _test_modifier_adds_proficiency_only_when_proficient(failures: Array[String]) -> void:
	var actor := _actor(16, 3)
	_expect(AbilityCheckRules.modifier(actor, &"charisma", false) == 3, "unproficient charisma 16 should be +3", failures)
	_expect(AbilityCheckRules.modifier(actor, &"charisma", true) == 6, "proficient charisma 16 should be +3 plus the +3 proficiency bonus", failures)


static func _test_modifier_delegates_to_actor_state(failures: Array[String]) -> void:
	# Guards against a second, drifting copy of the score-to-modifier rule.
	for score in range(1, 31):
		var actor := _actor(score, 2)
		_expect(AbilityCheckRules.modifier(actor, &"charisma", false) == actor.ability_modifier(&"charisma"), "modifier() disagreed with ActorState.ability_modifier at charisma %d" % score, failures)


static func _test_roll_is_deterministic_and_threads_rng(failures: Array[String]) -> void:
	var actor := _actor()
	var first := AbilityCheckRules.resolve(1234, actor, &"charisma", 12, true)
	var second := AbilityCheckRules.resolve(1234, actor, &"charisma", 12, true)
	_expect(first["roll"] == second["roll"] and first["total"] == second["total"], "the same rng_state must produce the same check", failures)
	_expect(int(first["next_rng_state"]) != 1234, "resolve() must advance the rng_state", failures)
	_expect(int(first["roll"]) >= 1 and int(first["roll"]) <= 20, "a check must roll a d20", failures)
	_expect(first["ability"] == &"charisma" and bool(first["proficient"]), "resolve() should carry the check's own vocabulary for narration", failures)


static func _test_success_compares_total_against_dc(failures: Array[String]) -> void:
	var actor := _actor()
	var rng_state := 77
	for _attempt in range(40):
		var roll := AbilityCheckRules.resolve(rng_state, actor, &"charisma", 13, false)
		_expect(bool(roll["success"]) == (int(roll["total"]) >= 13), "success must be total >= dc", failures)
		_expect(int(roll["total"]) == int(roll["roll"]) + int(roll["modifier"]), "total must be the roll plus the modifier", failures)
		rng_state = int(roll["next_rng_state"])


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
