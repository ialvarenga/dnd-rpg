class_name TestTargetedActionPlanner
extends RefCounted

const TargetedActionPlannerScript = preload("res://sim/targeted_action_planner.gd")
const AbilityTargetingRules = preload("res://sim/ability_targeting.gd")


static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_in_range_action_needs_no_movement(failures)
	_test_out_of_range_action_plans_minimum_approach(failures)
	_test_ability_level_range_supports_future_targeted_actions(failures)
	_test_plan_reserves_declared_ability_movement_cost(failures)
	_test_planning_does_not_mutate_state(failures)
	return {"name": "unit/test_targeted_action_planner", "failures": failures}


static func _test_in_range_action_needs_no_movement(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var plan = TargetedActionPlannerScript.plan(state, 1, &"basic_attack", 2, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(plan.can_execute and not plan.requires_movement, "an in-range targeted action planned unnecessary movement", failures)


static func _test_out_of_range_action_plans_minimum_approach(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var hero: ActorState = state.actors[1]
	var target: ActorState = state.actors[2]
	target.position = Vector3(6.0, 0.0, 0.0)
	var plan = TargetedActionPlannerScript.plan(state, hero.id, &"basic_attack", target.id, FakeNavProvider.new(), FakeLosProvider.new())
	var range := AbilityTargetingRules.target_range(DefinitionLibrary.get_default(), &"basic_attack")
	_expect(plan.can_execute and plan.requires_movement, "an approachable out-of-range target produced no movement plan", failures)
	_expect(plan.destination.distance_to(target.position) <= range + AbilityTargetingRules.RANGE_EPSILON, "planned destination remained outside the ability range", failures)
	_expect(plan.movement_cost < hero.position.distance_to(target.position), "planner walked all the way onto the target instead of stopping at range", failures)
	_expect(absf(plan.movement_cost - (hero.position.distance_to(target.position) - range)) <= 0.01, "planner did not choose the closest valid position along the approach path", failures)


static func _test_ability_level_range_supports_future_targeted_actions(failures: Array[String]) -> void:
	var definitions := DefinitionLibrary.new()
	var effect := AbilityEffect.new()
	effect.type = &"perform_attack"
	effect.range_meters = 1.0
	var spell := AbilityDefinition.new()
	spell.id = &"test_spell"
	spell.targeting = &"actor"
	spell.target_range_meters = 3.0
	spell.costs_action = true
	spell.effects = [effect]
	definitions.add_ability(spell)
	var state := TestHelpers.make_battle()
	(state.actors[2] as ActorState).position = Vector3(6.0, 0.0, 0.0)
	var plan = TargetedActionPlannerScript.plan(state, 1, spell.id, 2, FakeNavProvider.new(), FakeLosProvider.new(), definitions)
	_expect(plan.can_execute and plan.requires_movement, "a future actor-targeted ability could not use the general approach planner", failures)
	_expect(plan.destination.distance_to((state.actors[2] as ActorState).position) <= spell.target_range_meters + AbilityTargetingRules.RANGE_EPSILON, "planner ignored ability-level target range", failures)


static func _test_plan_reserves_declared_ability_movement_cost(failures: Array[String]) -> void:
	var definitions := DefinitionLibrary.new()
	var effect := AbilityEffect.new()
	effect.type = &"perform_attack"
	var costly := AbilityDefinition.new()
	costly.id = &"costly_attack"
	costly.targeting = &"actor"
	costly.target_range_meters = 3.0
	costly.costs_action = true
	costly.movement_cost = 2.0
	costly.effects = [effect]
	definitions.add_ability(costly)
	var state := TestHelpers.make_battle()
	var hero: ActorState = state.actors[1]
	hero.movement_remaining = 5.0
	(state.actors[2] as ActorState).position = Vector3(7.0, 0.0, 0.0)
	var plan = TargetedActionPlannerScript.plan(state, hero.id, costly.id, 2, FakeNavProvider.new(), FakeLosProvider.new(), definitions)
	_expect(not plan.can_execute, "planner spent movement needed by the queued ability itself", failures)


static func _test_planning_does_not_mutate_state(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	(state.actors[2] as ActorState).position = Vector3(6.0, 0.0, 0.0)
	var before := JSON.stringify(state.stable_snapshot())
	TargetedActionPlannerScript.plan(state, 1, &"basic_attack", 2, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(JSON.stringify(state.stable_snapshot()) == before, "targeted-action planning mutated BattleState", failures)


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
