class_name TestActionAvailability
extends RefCounted

## Fase C2: proves ActionAvailability.evaluate() agrees with what
## Resolver.resolve() actually does for the same BattleState/actor/ability,
## across turn ownership, phase, consciousness, and every ability-cost
## resource -- action, bonus_action, reaction, and movement. Every case here
## also resolves the equivalent Command through the real Resolver (with the
## same DefinitionLibrary) so a passing suite is proof of agreement, not just
## of ActionAvailability's own internal logic.

static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_available_ability_agrees_with_resolver(failures)
	_test_not_current_actor_agrees_with_resolver(failures)
	_test_not_in_combat_agrees_with_resolver(failures)
	_test_unconscious_actor_agrees_with_resolver(failures)
	_test_action_resource_agrees_with_resolver(failures)
	_test_bonus_action_resource_agrees_with_resolver(failures)
	_test_reaction_resource_agrees_with_resolver(failures)
	_test_movement_resource_agrees_with_resolver(failures)
	_test_unknown_ability_agrees_with_resolver(failures)
	_test_unknown_actor_is_unavailable(failures)
	_test_exploration_ability_is_available_and_agrees_with_resolver(failures)
	_test_exploration_only_ability_is_rejected_in_combat(failures)
	return {"name": "unit/test_action_availability", "failures": failures}


static func _test_available_ability_agrees_with_resolver(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var evaluation := ActionAvailability.evaluate(state, 1, &"dash")
	_expect(evaluation["available"] and evaluation["reason"] == &"", "dash should be available on a fresh current-actor turn", failures)
	var result := Resolver.resolve(state, Command.create(&"dash", 1), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(result.events[0].type != &"command_rejected", "Resolver rejected dash even though ActionAvailability reported it available", failures)


static func _test_not_current_actor_agrees_with_resolver(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var evaluation := ActionAvailability.evaluate(state, 2, &"dash")
	_assert_agrees_with_resolver(state, 2, &"dash", evaluation, "not_current_actor", failures)


## Shipped actions are all usable outside combat now, so the combat-only gate
## is exercised through an ability that does not declare usable_in_exploration.
static func _test_not_in_combat_agrees_with_resolver(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	state.phase = &"exploration"
	var library := _custom_library_with_full_cost_dash()
	var evaluation := ActionAvailability.evaluate(state, 1, &"dash", library)
	_assert_agrees_with_resolver(state, 1, &"dash", evaluation, "not_in_combat", failures, library)


static func _test_unconscious_actor_agrees_with_resolver(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	(state.actors[1] as ActorState).add_condition(&"unconscious")
	var evaluation := ActionAvailability.evaluate(state, 1, &"dash")
	_assert_agrees_with_resolver(state, 1, &"dash", evaluation, "actor_cannot_act", failures)


static func _test_action_resource_agrees_with_resolver(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	(state.actors[1] as ActorState).action_available = false
	var evaluation := ActionAvailability.evaluate(state, 1, &"dash")
	_assert_agrees_with_resolver(state, 1, &"dash", evaluation, "action_unavailable", failures)


static func _test_bonus_action_resource_agrees_with_resolver(failures: Array[String]) -> void:
	var defs := _custom_library_with_full_cost_dash()
	var state := TestHelpers.make_battle()
	(state.actors[1] as ActorState).bonus_action_available = false
	var evaluation := ActionAvailability.evaluate(state, 1, &"dash", defs)
	_assert_agrees_with_resolver(state, 1, &"dash", evaluation, "bonus_action_unavailable", failures, defs)


static func _test_reaction_resource_agrees_with_resolver(failures: Array[String]) -> void:
	var defs := _custom_library_with_full_cost_dash()
	var state := TestHelpers.make_battle()
	(state.actors[1] as ActorState).reaction_available = false
	var evaluation := ActionAvailability.evaluate(state, 1, &"dash", defs)
	_assert_agrees_with_resolver(state, 1, &"dash", evaluation, "reaction_unavailable", failures, defs)


static func _test_movement_resource_agrees_with_resolver(failures: Array[String]) -> void:
	var defs := _custom_library_with_full_cost_dash()
	var state := TestHelpers.make_battle()
	(state.actors[1] as ActorState).movement_remaining = 1.0
	var evaluation := ActionAvailability.evaluate(state, 1, &"dash", defs)
	_assert_agrees_with_resolver(state, 1, &"dash", evaluation, "insufficient_movement", failures, defs)


static func _test_unknown_ability_agrees_with_resolver(failures: Array[String]) -> void:
	var empty_library := DefinitionLibrary.new()
	var state := TestHelpers.make_battle()
	var evaluation := ActionAvailability.evaluate(state, 1, &"dash", empty_library)
	_assert_agrees_with_resolver(state, 1, &"dash", evaluation, "unknown_ability_definition", failures, empty_library)


static func _test_unknown_actor_is_unavailable(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var evaluation := ActionAvailability.evaluate(state, 999, &"dash")
	_expect(not evaluation["available"] and evaluation["reason"] == &"unknown_actor", "an unknown actor id should be unavailable with reason unknown_actor", failures)


## Builds a "dash" whose AbilityDefinition also costs a bonus action, a
## reaction, and 5m of movement -- on top of its normal action cost -- so
## every resource gate AbilityCostRules checks can be exercised through a
## routed command type without changing AbilityRouting's fixed vocabulary.
static func _custom_library_with_full_cost_dash() -> DefinitionLibrary:
	var library := DefinitionLibrary.new()
	var effect := AbilityEffect.new()
	effect.type = &"add_base_movement"
	effect.multiplier = 1.0
	var dash := AbilityDefinition.new()
	dash.id = &"dash"
	dash.costs_action = true
	dash.costs_bonus_action = true
	dash.costs_reaction = true
	dash.movement_cost = 5.0
	dash.effects = [effect]
	library.add_ability(dash)
	return library


## An ability that declares usable_in_exploration must be offered outside
## combat, and the resolver must actually accept it. Outside combat there is no
## action economy: Dash stays available with its action already spent, and
## resolving it spends nothing.
static func _test_exploration_ability_is_available_and_agrees_with_resolver(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	state.phase = &"exploration"
	var talker: ActorState = state.actors[1]
	talker.ability_ids = [&"talk", &"dash"]
	(state.actors[2] as ActorState).dialog_id = &"emberwatch_toll"
	(state.actors[2] as ActorState).position = talker.position + Vector3(1.0, 0.0, 0.0)

	var talk_evaluation := ActionAvailability.evaluate(state, 1, &"talk")
	_expect(bool(talk_evaluation["available"]), "an ability marked usable_in_exploration should be offered outside combat", failures)
	var talk_command := Command.create(&"talk", 1)
	talk_command.target_id = 2
	var talk_result := Resolver.resolve(state, talk_command, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(talk_result.events.any(func(event: Event): return event.type == &"dialog_started"), "the resolver should accept the ability ActionAvailability reported available", failures)

	talker.action_available = false
	var dash_evaluation := ActionAvailability.evaluate(state, 1, &"dash")
	_expect(bool(dash_evaluation["available"]), "a spent action should not gate an ability outside combat", failures)
	var dash_result := Resolver.resolve(state, Command.create(&"dash", 1), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(dash_result.events[0].type != &"command_rejected", "the resolver should accept Dash outside combat", failures)
	_expect(not dash_result.events.any(func(event: Event): return event.type in [&"action_spent", &"bonus_action_spent", &"movement_spent"]), "an exploration action should not spend the combat economy", failures)


static func _test_exploration_only_ability_is_rejected_in_combat(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	(state.actors[2] as ActorState).dialog_id = &"emberwatch_toll"
	var talk_evaluation := ActionAvailability.evaluate(state, 1, &"talk")
	_assert_agrees_with_resolver(state, 1, &"talk", talk_evaluation, &"combat_already_active", failures)


static func _assert_agrees_with_resolver(state: BattleState, actor_id: int, ability_id: StringName, evaluation: Dictionary, expected_reason: StringName, failures: Array[String], defs: DefinitionLibrary = null) -> void:
	_expect(not evaluation["available"] and evaluation["reason"] == expected_reason, "ActionAvailability did not report reason '%s' for actor %d" % [expected_reason, actor_id], failures)
	var command := Command.create(AbilityRouting.command_type_for_ability(ability_id), actor_id)
	var result := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new(), defs)
	_expect(result.events[0].type == &"command_rejected", "Resolver accepted a command ActionAvailability reported unavailable (actor %d, reason '%s')" % [actor_id, expected_reason], failures)
	if result.events[0].type == &"command_rejected":
		_expect(result.events[0].data["reason"] == expected_reason, "Resolver's rejection reason ('%s') did not match ActionAvailability's ('%s')" % [result.events[0].data["reason"], expected_reason], failures)


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
