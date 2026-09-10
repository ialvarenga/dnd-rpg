class_name TestAbilityUses
extends RefCounted

## Covers the per-ability use pool (AbilityDefinition.max_uses) and the
## encounter/turn recharge that stands in for the SRD short rest.

static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_unlimited_abilities_are_never_gated(failures)
	_test_pool_is_spent_then_exhausted(failures)
	_test_availability_agrees_with_resolver(failures)
	_test_encounter_recharges_the_pool(failures)
	_test_turn_recharge_only_touches_per_turn_pools(failures)
	_test_second_wind_content(failures)
	return {"name": "unit/test_ability_uses", "failures": failures}


static func _test_unlimited_abilities_are_never_gated(failures: Array[String]) -> void:
	var definitions := _library(_limited_ability(&"limited", 1))
	var actor := (_battle(definitions).actors[1] as ActorState)
	actor.ability_uses_spent[&"dash"] = 99
	var dash := definitions.get_ability(&"dash")
	_expect(AbilityCostRules.remaining_uses(actor, dash) > 0, "an unlimited ability reported a bounded pool", failures)
	_expect(AbilityCostRules.rejection_for_cost(actor, dash, definitions) == &"", "an unlimited ability was gated by a stale uses entry", failures)


static func _test_pool_is_spent_then_exhausted(failures: Array[String]) -> void:
	var definitions := _library(_limited_ability(&"limited", 2))
	var state := _battle(definitions)
	for index in range(2):
		var result := Resolver.resolve(state, Command.create(&"limited", 1), FakeNavProvider.new(), FakeLosProvider.new(), definitions)
		var spend := _event(result, &"ability_use_spent")
		_expect(spend != null, "activation %d did not emit ability_use_spent" % (index + 1), failures)
		if spend != null:
			_expect(int(spend.data["uses_remaining"]) == 1 - index, "ability_use_spent reported the wrong remaining count", failures)
		TestHelpers.apply_result(state, result)
		# Free the bonus action so the pool, not the economy, is what runs out.
		(state.actors[1] as ActorState).bonus_action_available = true
	_expect(int((state.actors[1] as ActorState).ability_uses_spent.get(&"limited", 0)) == 2, "spent activations were not accumulated on the actor", failures)

	var exhausted := Resolver.resolve(state, Command.create(&"limited", 1), FakeNavProvider.new(), FakeLosProvider.new(), definitions)
	_expect(exhausted.events[0].type == &"command_rejected", "a third activation past a 2-use pool was accepted", failures)
	_expect(exhausted.events[0].data["reason"] == RejectionReason.ABILITY_USES_EXHAUSTED, "an exhausted pool did not report ability_uses_exhausted", failures)


## An exhausted pool must outrank a spent bonus action, so the HUD explains the
## reason the player can actually do something about.
static func _test_availability_agrees_with_resolver(failures: Array[String]) -> void:
	var definitions := _library(_limited_ability(&"limited", 1))
	var state := _battle(definitions)
	var actor: ActorState = state.actors[1]
	actor.ability_uses_spent[&"limited"] = 1
	actor.bonus_action_available = false
	var availability := ActionAvailability.evaluate(state, 1, &"limited", definitions)
	var result := Resolver.resolve(state, Command.create(&"limited", 1), FakeNavProvider.new(), FakeLosProvider.new(), definitions)
	_expect(not availability["available"] and availability["reason"] == RejectionReason.ABILITY_USES_EXHAUSTED, "availability preferred the spent bonus action over the exhausted pool", failures)
	_expect(result.events[0].data["reason"] == availability["reason"], "Resolver and ActionAvailability diverged on an exhausted pool", failures)


static func _test_encounter_recharges_the_pool(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var actor: ActorState = state.actors[1]
	actor.ability_uses_spent[&"second_wind"] = 2
	Resolver.apply(state, Event.create(&"combat_started", {
		"initiator_actor_id": 1,
		"phase": &"combat_starting",
		"encounter_id": "encounter_a",
		"combatant_ids": [1, 2],
	}))
	_expect(actor.ability_uses_spent.is_empty(), "entering an encounter did not refill the per-encounter pool", failures)


## The turn boundary reads the process-wide library (the apply path takes no
## definitions parameter), so the per-turn ability is registered there and
## reset_default() puts the singleton back for later suites.
static func _test_turn_recharge_only_touches_per_turn_pools(failures: Array[String]) -> void:
	var per_turn := _limited_ability(&"test_per_turn", 1)
	per_turn.uses_recharge = &"turn"
	DefinitionLibrary.get_default().add_ability(per_turn)
	var state := TestHelpers.make_battle()
	var actor: ActorState = state.actors[1]
	actor.ability_uses_spent[&"test_per_turn"] = 1
	actor.ability_uses_spent[&"second_wind"] = 1
	Resolver.apply(state, Resolver._turn_started_event(actor, 0, 1))
	_expect(not actor.ability_uses_spent.has(&"test_per_turn"), "a per-turn pool did not refill at the start of the turn", failures)
	_expect(actor.ability_uses_spent.has(&"second_wind"), "a per-encounter pool was wrongly refilled at the start of the turn", failures)
	DefinitionLibrary.reset_default()


static func _test_second_wind_content(failures: Array[String]) -> void:
	var definitions := DefinitionLibrary.get_default()
	var ability := definitions.get_ability(&"second_wind")
	_expect(ability != null, "second_wind is missing from the ability manifest", failures)
	if ability == null:
		return
	_expect(ability.costs_bonus_action and not ability.costs_action, "second_wind is not a Bonus Action", failures)
	_expect(ability.max_uses == 2 and ability.uses_recharge == &"encounter", "second_wind did not declare two per-encounter uses", failures)
	var knight := definitions.get_actor(&"knight")
	_expect(knight != null and knight.ability_ids.has(&"second_wind"), "the knight loadout does not carry Second Wind", failures)
	_expect(knight != null and knight.ability_ids.size() <= 6, "the knight loadout exceeded the six-slot hotbar", failures)

	var state := TestHelpers.make_battle()
	var actor: ActorState = state.actors[1]
	actor.max_hp = 30
	actor.hp = 5
	var result := Resolver.resolve(state, Command.create(&"second_wind", 1), FakeNavProvider.new(), FakeLosProvider.new())
	var healing := _event(result, &"healing_received")
	_expect(healing != null and int(healing.data["amount"]) >= 3, "second_wind did not heal at least 1d10 + 2 worth of HP", failures)
	_expect(_event(result, &"ability_use_spent") != null, "second_wind did not decrement its use pool", failures)


static func _limited_ability(id: StringName, max_uses: int) -> AbilityDefinition:
	var effect := AbilityEffect.new()
	effect.type = &"heal"
	effect.heal_die = 4
	var ability := AbilityDefinition.new()
	ability.id = id
	ability.display_name = String(id)
	ability.costs_bonus_action = true
	ability.max_uses = max_uses
	ability.effects = [effect]
	return ability


static func _library(ability: AbilityDefinition) -> DefinitionLibrary:
	var definitions := DefinitionLibrary.new()
	definitions.add_ability(ability)
	definitions.add_ability(DefinitionLibrary.get_default().get_ability(&"dash"))
	return definitions


static func _battle(definitions: DefinitionLibrary) -> BattleState:
	var state := TestHelpers.make_battle()
	var actor: ActorState = state.actors[1]
	actor.max_hp = 30
	actor.hp = 5
	actor.ability_ids = definitions.ordered_ability_ids()
	return state


static func _event(result: ResolutionResult, event_type: StringName) -> Event:
	for candidate in result.events:
		if candidate.type == event_type:
			return candidate
	return null


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
