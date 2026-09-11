class_name TestHelpAndAttackConditions
extends RefCounted

static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_help_target_matrix(failures)
	_test_help_cost_and_gates(failures)
	_test_next_attack_consumes_on_hit(failures)
	_test_next_attack_consumption_policies(failures)
	_test_next_attack_scope_and_vex_sap(failures)
	_test_save_and_replay_round_trip(failures)
	return {"name": "unit/test_help_and_attack_conditions", "failures": failures}


static func _test_help_target_matrix(failures: Array[String]) -> void:
	var state := _help_state()
	var self_result := Resolver.resolve(state, _help_command(1, 1), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_rejection(self_result) == &"invalid_target", "Help accepted self targeting", failures)
	var ally_result := Resolver.resolve(state, _help_command(1, 3), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_rejection(ally_result) == &"" and _event(ally_result, &"condition_added").data["condition"] == &"helped", "Help did not accept a living ally and apply Helped", failures)
	TestHelpers.apply_result(state, ally_result)
	_expect((state.actors[3] as ActorState).has_condition(&"helped"), "Helped was not applied to the selected ally", failures)
	var hostile_result := Resolver.resolve(_help_state(), _help_command(1, 2), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_rejection(hostile_result) == &"invalid_target", "Help accepted a hostile target", failures)
	var dead_result := Resolver.resolve(_help_state_with_dead_ally(), _help_command(1, 4), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_rejection(dead_result) == &"invalid_target", "Help accepted a dead ally", failures)


static func _test_help_cost_and_gates(failures: Array[String]) -> void:
	var state := _help_state()
	var help := Resolver.resolve(state, _help_command(1, 3), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_event(help, &"action_spent") != null, "Help did not spend an Action", failures)
	TestHelpers.apply_result(state, help)
	var spent := Resolver.resolve(state, _help_command(1, 3), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_rejection(spent) == &"action_unavailable" and _event(spent, &"condition_added") == null, "Help bypassed Action economy on a second use", failures)
	var exploration := _help_state()
	exploration.phase = &"exploration"
	_expect(_rejection(Resolver.resolve(exploration, _help_command(1, 3), FakeNavProvider.new(), FakeLosProvider.new())) == &"not_in_combat", "Help bypassed its combat phase gate", failures)
	var blocked_los := FakeLosProvider.new()
	blocked_los.set_cover((state.actors[1] as ActorState).position, (state.actors[3] as ActorState).position, LosProvider.COVER_TOTAL)
	var los_result := Resolver.resolve(_help_state(), _help_command(1, 3), FakeNavProvider.new(), blocked_los)
	_expect(_rejection(los_result) == &"no_line_of_sight", "Help ignored total cover", failures)


static func _test_next_attack_consumes_on_hit(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle(42)
	var attacker: ActorState = state.actors[1]
	attacker.add_condition(&"helped", 3)
	TestHelpers.guarantee_hits(attacker)
	var result := _basic_attack(state, 1, 2)
	var rolled := _event(result, &"attack_rolled")
	_expect(rolled != null and rolled.data["advantage"] and rolled.data["condition_consumptions"].size() == 1, "Helped did not grant Advantage to the next attack", failures)
	_expect(_event(result, &"condition_consumed") != null, "a resolved Helped attack did not emit condition_consumed", failures)
	TestHelpers.apply_result(state, result)
	_expect(not attacker.has_condition(&"helped"), "Helped did not expire after its relevant attack", failures)
	attacker.action_available = true
	var next := _basic_attack(state, 1, 2)
	_expect(not _event(next, &"attack_rolled").data["advantage"], "a consumed Helped condition affected a second attack", failures)


static func _test_next_attack_consumption_policies(failures: Array[String]) -> void:
	var definitions := DefinitionLibrary.new()
	definitions.add_ability(DefinitionLibrary.get_default().get_ability(&"basic_attack"))
	var condition := ConditionDefinition.new()
	condition.id = &"hit_only"
	condition.next_attack_advantage = true
	condition.attack_consumption = &"attack_hit"
	definitions.add_condition(condition)
	var state := TestHelpers.make_battle(1)
	(state.actors[1] as ActorState).add_condition(&"hit_only")
	var miss_seed := _seed_for_noncritical_advantage()
	state.rng_state = miss_seed
	(state.actors[1] as ActorState).strength = 1
	(state.actors[2] as ActorState).dexterity = 50
	var missed := _basic_attack(state, 1, 2, definitions)
	var missed_roll := _event(missed, &"attack_rolled")
	_expect(missed_roll != null and not missed_roll.data["hit"] and _event(missed, &"condition_consumed") == null, "attack_hit consumption incorrectly removed a condition on a miss (%s)" % [missed_roll.data if missed_roll != null else missed.events], failures)
	TestHelpers.apply_result(state, missed)
	_expect((state.actors[1] as ActorState).has_condition(&"hit_only"), "attack_hit policy did not preserve a condition after a miss", failures)


static func _test_next_attack_scope_and_vex_sap(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle(42)
	var unrelated := (state.actors[2] as ActorState).clone()
	unrelated.id = 3
	unrelated.position = Vector3(1.0, 0.0, 1.0)
	state.actors[3] = unrelated
	var attacker: ActorState = state.actors[1]
	attacker.add_condition(&"helped", 3, -1, &"none", 999)
	var unrelated_target := _basic_attack(state, 1, 2)
	_expect(not _event(unrelated_target, &"attack_rolled").data["advantage"] and (attacker as ActorState).has_condition(&"helped"), "a related-target condition affected an unrelated target", failures)
	attacker.remove_condition(&"helped")
	(state.actors[2] as ActorState).add_condition(&"vexed", 1)
	var vexed := _basic_attack(state, 1, 2)
	_expect(_event(vexed, &"attack_rolled").data["advantage"] and _event(vexed, &"condition_consumed") != null, "Vexed did not grant and consume against-target Advantage", failures)
	TestHelpers.apply_result(state, vexed)
	attacker.action_available = true
	attacker.add_condition(&"sapped", 2)
	var sapped := _basic_attack(state, 1, 2)
	_expect(_event(sapped, &"attack_rolled").data["disadvantage"] and _event(sapped, &"condition_consumed") != null, "Sapped did not grant and consume next-attack Disadvantage", failures)


static func _test_save_and_replay_round_trip(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle(42)
	(state.actors[1] as ActorState).add_condition(&"helped", 3, -1, &"none", 2)
	var save := SaveGame.create(state)
	var restored := SaveGame.from_dict(JSON.parse_string(JSON.stringify(save.to_dict())))
	var restored_condition := (restored.battle_state.actors[1] as ActorState).condition_state(&"helped")
	_expect(restored_condition != null and restored_condition.related_actor_id == 2, "related one-attack condition scope did not survive SaveGame", failures)
	var log := ReplayLog.start(restored.battle_state)
	var attack := Command.create(&"basic_attack", 1)
	attack.target_id = 2
	var result := Resolver.resolve(restored.battle_state, attack, FakeNavProvider.new(), FakeLosProvider.new())
	log.append_command(attack, result)
	TestHelpers.apply_result(restored.battle_state, result)
	var replayed := ReplayLog.from_dict(JSON.parse_string(JSON.stringify(log.to_dict())))
	_expect(replayed.find_divergences(FakeNavProvider.new(), FakeLosProvider.new()).is_empty(), "condition consumption made replay diverge after serialization", failures)


static func _help_state() -> BattleState:
	var state := TestHelpers.make_battle(42)
	var ally := (state.actors[1] as ActorState).clone()
	ally.id = 3
	ally.position = Vector3(1.0, 0.0, 0.0)
	state.actors[3] = ally
	return state


static func _help_state_with_dead_ally() -> BattleState:
	var state := _help_state()
	var dead_ally := (state.actors[3] as ActorState).clone()
	dead_ally.id = 4
	dead_ally.hp = 0
	state.actors[4] = dead_ally
	return state


static func _help_command(actor_id: int, target_id: int) -> Command:
	var command := Command.create(&"help", actor_id)
	command.target_id = target_id
	return command


static func _basic_attack(state: BattleState, actor_id: int, target_id: int, definitions: DefinitionLibrary = null) -> ResolutionResult:
	var command := Command.create(&"basic_attack", actor_id)
	command.target_id = target_id
	return Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new(), definitions)


static func _seed_for_noncritical_advantage() -> int:
	for seed in range(1, 1000):
		var first := Dice.roll_die(seed, 20)
		var second := Dice.roll_die(int(first["next_rng_state"]), 20)
		if int(first["value"]) != 20 and int(second["value"]) != 20:
			return seed
	return 1


static func _event(result: ResolutionResult, event_type: StringName) -> Event:
	for event in result.events:
		if event.type == event_type:
			return event
	return null


static func _rejection(result: ResolutionResult) -> StringName:
	var event := _event(result, &"command_rejected")
	return StringName(str(event.data.get("reason", ""))) if event != null else &""


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
