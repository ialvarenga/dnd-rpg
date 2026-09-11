class_name TestAbilityTargeting
extends RefCounted

const AbilityTargetingRules = preload("res://sim/ability_targeting.gd")


static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_target_filter_matrix(failures)
	_test_resolver_uses_target_filter(failures)
	_test_definition_library_rejects_unknown_filter(failures)
	_test_default_filter_preserves_hostile_behavior(failures)
	return {"name": "unit/test_ability_targeting", "failures": failures}


static func _test_target_filter_matrix(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var actor: ActorState = state.actors[1]
	var ally := actor.clone()
	ally.id = 3
	ally.position = Vector3(1.0, 0.0, 1.0)
	var opposing: ActorState = state.actors[2]
	var dead := opposing.clone()
	dead.id = 4
	dead.hp = 0
	var candidates: Array[ActorState] = [actor, ally, opposing, dead]
	var expected := {
		&"hostile": [false, false, true, false],
		&"ally": [false, true, false, false],
		&"self": [true, false, false, false],
		&"any": [true, true, true, false],
	}
	for filter in AbilityTargetingRules.TARGET_FILTERS:
		var ability := _targeting_ability(&"matrix_%s" % filter, filter)
		for index in range(candidates.size()):
			_expect(AbilityTargetingRules.is_valid_target(actor, candidates[index], ability) == expected[filter][index], "target filter '%s' produced the wrong result for candidate %d" % [filter, index], failures)


static func _test_resolver_uses_target_filter(failures: Array[String]) -> void:
	var definitions := DefinitionLibrary.new()
	for filter in [&"ally", &"self", &"any"]:
		definitions.add_ability(_targeting_ability(&"resolver_%s" % filter, filter))
	var ally := (TestHelpers.make_battle().actors[1] as ActorState).clone()
	ally.id = 3
	ally.position = Vector3(1.0, 0.0, 1.0)
	for filter in [&"ally", &"self", &"any"]:
		var accepted_target := 1 if filter == &"self" else (3 if filter == &"ally" else 2)
		var accepted := _resolve_targeting_command(filter, accepted_target, definitions, ally)
		_expect(accepted.events[0].type != &"command_rejected", "Resolver rejected a valid '%s' target" % filter, failures)
		var rejected := _resolve_targeting_command(filter, 2, definitions, ally, true)
		_expect(rejected.events[0].type == &"command_rejected" and rejected.events[0].data["reason"] == &"invalid_target", "Resolver did not reject an invalid '%s' target with INVALID_TARGET" % filter, failures)


static func _resolve_targeting_command(filter: StringName, target_id: int, definitions: DefinitionLibrary, ally: ActorState, dead_target: bool = false) -> ResolutionResult:
	var state := TestHelpers.make_battle()
	state.actors[3] = ally.clone()
	if dead_target:
		var dead := (state.actors[target_id] as ActorState).clone()
		dead.hp = 0
		state.actors[target_id] = dead
	var command := Command.create(&"resolver_%s" % filter, 1)
	command.target_id = target_id
	return Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new(), definitions)


static func _test_definition_library_rejects_unknown_filter(failures: Array[String]) -> void:
	var definitions := DefinitionLibrary.new()
	var invalid := _targeting_ability(&"invalid_filter", &"not_a_filter")
	definitions.add_ability(invalid)
	_expect(not definitions.has_ability(invalid.id), "DefinitionLibrary accepted an unknown target_filter", failures)


static func _test_default_filter_preserves_hostile_behavior(failures: Array[String]) -> void:
	var ability := AbilityDefinition.new()
	_expect(ability.target_filter == &"hostile", "AbilityDefinition did not default target_filter to hostile", failures)
	var talk := DefinitionLibrary.get_default().get_ability(&"talk")
	_expect(talk != null and talk.target_filter == &"hostile", "Talk did not retain the default opposing-side target filter", failures)


static func _targeting_ability(id: StringName, filter: StringName) -> AbilityDefinition:
	var ability := AbilityDefinition.new()
	ability.id = id
	ability.targeting = &"actor"
	ability.target_filter = filter
	ability.target_range_meters = 10.0
	ability.costs_action = true
	return ability


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
