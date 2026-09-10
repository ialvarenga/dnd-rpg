class_name TestGameplayRules
extends RefCounted

const EncounterRules = preload("res://sim/rules/encounter.gd")


static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_ordinary_zero_hp_is_immediate_defeat(failures)
	_test_massive_damage_preserves_death(failures)
	_test_victory_is_scoped_to_encounter_participants(failures)
	_test_terminal_precedence_and_game_over_gate(failures)
	_test_encounter_start_validation_and_scope(failures)
	_test_objective_prerequisites_and_completion(failures)
	_test_shove_uses_better_save_and_applies_prone(failures)
	_test_prone_actor_stands_at_turn_start(failures)
	_test_combat_end_stands_prone_survivors(failures)
	_test_dodge_expires_at_owner_turn_start(failures)
	_test_ranged_bands_nearby_hostile_cover_and_damage_type(failures)
	_test_archer_ai_creates_standoff(failures)
	_test_attack_continues_into_secondary_effects(failures)
	_test_new_state_round_trip(failures)
	return {"name": "unit/test_gameplay_rules", "failures": failures}


static func _test_ordinary_zero_hp_is_immediate_defeat(failures: Array[String]) -> void:
	var state := _active_battle([2, 1])
	var hero: ActorState = state.actors[1]
	var enemy: ActorState = state.actors[2]
	hero.hp = 5
	enemy.attack_bonus = 100
	enemy.damage_die = 1
	enemy.damage_modifier = 5
	var command := Command.create(&"basic_attack", enemy.id)
	command.target_id = hero.id
	var result := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_has_event(result, &"actor_downed"), "ordinary zero HP did not emit actor_downed", failures)
	_expect(not _has_event(result, &"actor_died"), "ordinary zero HP was incorrectly classified as massive-damage death", failures)
	_expect(_event_types(result).slice(-4) == [&"encounter_resolved", &"combat_ending", &"combat_ended", &"game_over"], "decisive attack did not carry the complete defeat lifecycle", failures)
	TestHelpers.apply_result(state, result)
	_expect(state.phase == &"game_over" and state.game_outcome == &"defeat" and state.last_encounter_outcome == &"defeat", "defeat events did not produce authoritative game-over state", failures)
	_expect(hero.has_condition(&"unconscious") and not hero.has_condition(&"dead"), "ordinary defeat did not preserve unconscious versus dead", failures)
	var resolved := _event(result, &"encounter_resolved")
	_expect(resolved != null and resolved.data.get("winning_side") == &"enemies" and resolved.data.get("defeated_actor_ids") == [1], "defeat payload did not identify the winning side and defeated hero", failures)


static func _test_massive_damage_preserves_death(failures: Array[String]) -> void:
	var state := _active_battle([2, 1])
	var enemy: ActorState = state.actors[2]
	enemy.attack_bonus = 100
	enemy.damage_die = 1
	enemy.damage_modifier = 100
	var command := Command.create(&"basic_attack", enemy.id)
	command.target_id = 1
	var result := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_has_event(result, &"actor_died") and _has_event(result, &"game_over"), "massive damage did not preserve death while ending the run", failures)
	TestHelpers.apply_result(state, result)
	_expect((state.actors[1] as ActorState).has_condition(&"dead"), "massive-damage death was not serialized as a condition instance", failures)


static func _test_victory_is_scoped_to_encounter_participants(failures: Array[String]) -> void:
	var state := _active_battle([1, 2])
	var unrelated := ActorState.new()
	unrelated.id = 3
	unrelated.side = &"enemies"
	unrelated.hp = 20
	unrelated.max_hp = 20
	unrelated.position = Vector3(20.0, 0.0, 0.0)
	state.actors[3] = unrelated
	var hero: ActorState = state.actors[1]
	var target: ActorState = state.actors[2]
	hero.attack_bonus = 100
	hero.damage_die = 1
	hero.damage_modifier = 100
	var command := Command.create(&"basic_attack", hero.id)
	command.target_id = target.id
	var result := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
	var resolved := _event(result, &"encounter_resolved")
	_expect(resolved != null and resolved.data.get("outcome") == &"victory" and resolved.data.get("winning_side") == &"heroes", "last encounter enemy did not resolve a hero victory", failures)
	TestHelpers.apply_result(state, result)
	_expect(state.phase == &"exploration" and state.game_outcome == &"ongoing", "encounter victory incorrectly ended the whole adventure", failures)
	_expect(state.cleared_encounter_ids == ["encounter_a"] and unrelated.is_conscious(), "unrelated living enemy affected participant-only victory", failures)


static func _test_terminal_precedence_and_game_over_gate(failures: Array[String]) -> void:
	var state := _active_battle([1, 2])
	(state.actors[1] as ActorState).add_condition(&"unconscious")
	(state.actors[2] as ActorState).add_condition(&"unconscious")
	_expect(EncounterRules.resolved_outcome(state) == &"defeat", "simultaneous terminal state did not give hero defeat precedence", failures)
	state.phase = &"game_over"
	state.game_outcome = &"defeat"
	var rejected := Resolver.resolve(state, Command.create(&"move", 999), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(rejected.events.size() == 1 and rejected.events[0].data.get("reason") == &"game_over", "a command after game over was not rejected before actor lookup", failures)


static func _test_encounter_start_validation_and_scope(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle(77)
	state.phase = &"exploration"
	var outsider := ActorState.new()
	outsider.id = 3
	outsider.side = &"enemies"
	outsider.hp = 10
	outsider.max_hp = 10
	state.actors[3] = outsider
	var invalid := Command.create(&"start_combat", 2)
	invalid.metadata = {"encounter_id": "encounter_a", "participant_actor_ids": [1, 3]}
	var invalid_result := Resolver.resolve(state, invalid, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(invalid_result.events[0].data.get("reason") == &"invalid_encounter", "encounter accepted an initiator outside its participants", failures)
	var valid := Command.create(&"start_combat", 2)
	valid.metadata = {"encounter_id": "encounter_a", "participant_actor_ids": [2, 1, 2]}
	var valid_result := Resolver.resolve(state, valid, FakeNavProvider.new(), FakeLosProvider.new())
	TestHelpers.apply_result(state, valid_result)
	var sorted_active := state.active_combatant_ids.duplicate()
	sorted_active.sort()
	_expect(state.active_encounter_id == "encounter_a" and sorted_active == [1, 2] and not state.initiative_order.has(3), "start_combat did not retain its stable, scoped participant set", failures)
	var unresolved := Resolver.resolve(state, Command.create(&"end_combat", state.current_actor_id()), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(unresolved.events[0].data.get("reason") == &"combat_unresolved", "manual end_combat did not reject a live two-sided encounter", failures)


static func _test_objective_prerequisites_and_completion(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	state.phase = &"exploration"
	state.initiative_order.clear()
	var objective := ObjectiveState.new()
	objective.id = "emberwatch_camp"
	objective.position = Vector3(3.0, 0.0, 0.0)
	objective.radius_m = 2.0
	objective.requires_encounter_ids = ["emberwatch_ambush"]
	state.objectives[objective.id] = objective
	var move := Command.create(&"move", 1)
	move.target_pos = objective.position
	var blocked := Resolver.resolve(state, move, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(not _has_event(blocked, &"objective_completed"), "objective completed before its required encounter", failures)
	state.cleared_encounter_ids.append("emberwatch_ambush")
	var completed := Resolver.resolve(state, move, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_event_types(completed).slice(-2) == [&"objective_completed", &"game_completed"], "eligible objective movement did not complete the map in one resolution", failures)
	TestHelpers.apply_result(state, completed)
	_expect(objective.completed and state.phase == &"game_over" and state.game_outcome == &"victory", "objective completion events did not create authoritative map victory", failures)


static func _test_shove_uses_better_save_and_applies_prone(failures: Array[String]) -> void:
	var state := _active_battle([1, 2])
	var hero: ActorState = state.actors[1]
	var target: ActorState = state.actors[2]
	hero.strength = 30
	target.strength = 1
	target.dexterity = 3
	target.saving_throw_proficiencies.clear()
	var command := Command.create(&"shove", hero.id)
	command.target_id = target.id
	var first := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
	var second := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
	var test_event := _event(first, &"d20_test_rolled")
	_expect(test_event != null and test_event.data.get("ability") == &"dexterity", "Shove did not use the defender's better Strength or Dexterity save", failures)
	_expect(test_event != null and test_event.data.get("difficulty_class") == 20 and not test_event.data.get("success"), "Shove did not use 8 + proficiency + Strength modifier or resolve failure", failures)
	_expect(test_event != null and test_event.data.get("ability_modifier") == -4 and not test_event.data.get("proficient") and test_event.data.get("proficiency_bonus") == 0, "saving throw event did not expose its ability and proficiency components", failures)
	_expect(test_event != null and test_event.data.get("rng_state_before") == state.rng_state and test_event.data.get("next_rng_state") == first.next_rng_state, "saving throw event did not expose its deterministic RNG transition", failures)
	_expect(TestHelpers.event_log_entry(first) == TestHelpers.event_log_entry(second), "saving throw and RNG advance were not deterministic", failures)
	var action_event := _event(first, &"action_spent")
	_expect(action_event != null and action_event.data.get("action") == &"shove" and action_event.data.get("target_id") == target.id, "Shove's action_spent did not name its target for presentation", failures)
	TestHelpers.apply_result(state, first)
	_expect(target.has_condition(&"prone") and target.condition_state(&"prone").source_actor_id == hero.id, "failed Shove did not apply a sourced permanent Prone condition", failures)


static func _test_prone_actor_stands_at_turn_start(failures: Array[String]) -> void:
	var state := _active_battle([1, 2])
	var target: ActorState = state.actors[2]
	target.movement_speed = 9.0
	target.add_condition(&"prone", 1)
	var result := Resolver.resolve(state, Command.create(&"end_turn", 1), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_event_types(result) == [&"turn_ended", &"turn_started", &"condition_removed", &"movement_spent"], "prone turn start did not stand up after its turn_started reset", failures)
	var removed := _event(result, &"condition_removed")
	var spent := _event(result, &"movement_spent")
	_expect(removed != null and removed.data.get("actor_id") == target.id and removed.data.get("condition") == &"prone", "turn-start stand-up did not remove the new actor's Prone", failures)
	_expect(spent != null and is_equal_approx(float(spent.data.get("amount")), 4.5) and is_equal_approx(float(spent.data.get("movement_remaining_after")), 4.5), "standing up did not cost half Speed", failures)
	TestHelpers.apply_result(state, result)
	_expect(not target.has_condition(&"prone") and is_equal_approx(target.movement_remaining, 4.5), "applied turn-start stand-up left the actor prone or with full movement", failures)

	var immobile_state := _active_battle([1, 2])
	var immobile: ActorState = immobile_state.actors[2]
	immobile.movement_speed = 0.0
	immobile.add_condition(&"prone", 1)
	var immobile_result := Resolver.resolve(immobile_state, Command.create(&"end_turn", 1), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(not _has_event(immobile_result, &"condition_removed"), "an actor with no Speed stood up from Prone", failures)
	TestHelpers.apply_result(immobile_state, immobile_result)
	_expect(immobile.has_condition(&"prone"), "an actor with no Speed did not stay prone", failures)


static func _test_combat_end_stands_prone_survivors(failures: Array[String]) -> void:
	var state := _active_battle([1, 2])
	var hero: ActorState = state.actors[1]
	var enemy: ActorState = state.actors[2]
	hero.add_condition(&"prone", 2)
	hero.attack_bonus = 100
	hero.damage_die = 1
	hero.damage_modifier = 5
	enemy.hp = 1
	var command := Command.create(&"basic_attack", hero.id)
	command.target_id = enemy.id
	var result := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
	var types := _event_types(result)
	var removed := _event(result, &"condition_removed")
	_expect(removed != null and removed.data.get("actor_id") == hero.id and types.find(&"condition_removed") < types.find(&"encounter_resolved"), "a prone survivor did not stand up before combat ended", failures)
	TestHelpers.apply_result(state, result)
	_expect(state.phase == &"exploration" and not hero.has_condition(&"prone"), "combat ended with its survivor still prone", failures)


static func _test_dodge_expires_at_owner_turn_start(failures: Array[String]) -> void:
	var state := _active_battle([1, 2])
	var dodge := Resolver.resolve(state, Command.create(&"dodge", 1), FakeNavProvider.new(), FakeLosProvider.new())
	TestHelpers.apply_result(state, dodge)
	var condition := (state.actors[1] as ActorState).condition_state(&"dodging")
	_expect(condition != null and condition.remaining_triggers == 1 and condition.expiration_timing == &"turn_start", "Dodge did not author its timed condition instance", failures)
	state.initiative_order = [2, 1]
	state.current_turn_index = 0
	var incoming := Command.create(&"basic_attack", 2)
	incoming.target_id = 1
	var incoming_result := Resolver.resolve(state, incoming, FakeNavProvider.new(), FakeLosProvider.new())
	var incoming_roll := _event(incoming_result, &"attack_rolled")
	_expect(incoming_roll != null and incoming_roll.data.get("disadvantage"), "Dodge did not impose disadvantage on an incoming attack", failures)
	state.initiative_order = [1, 2]
	state.current_turn_index = 0
	TestHelpers.apply_result(state, Resolver.resolve(state, Command.create(&"end_turn", 1), FakeNavProvider.new(), FakeLosProvider.new()))
	_expect((state.actors[1] as ActorState).has_condition(&"dodging"), "Dodge expired before the owner's next turn", failures)
	var back_to_owner := Resolver.resolve(state, Command.create(&"end_turn", 2), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_has_event(back_to_owner, &"condition_removed"), "Dodge did not expire through a turn-boundary event", failures)
	TestHelpers.apply_result(state, back_to_owner)
	_expect(not (state.actors[1] as ActorState).has_condition(&"dodging"), "Dodge remained after the owner's next turn began", failures)


static func _test_ranged_bands_nearby_hostile_cover_and_damage_type(failures: Array[String]) -> void:
	var state := _archer_battle(Vector3(20.0, 0.0, 0.0))
	var normal := _ranged_attack(state, FakeLosProvider.new())
	_expect(not normal.events[0].data.get("disadvantage") and (normal.events[0].data.get("rolls") as Array).size() == 1, "Shortbow normal range incorrectly imposed disadvantage", failures)
	(state.actors[1] as ActorState).position = Vector3(30.0, 0.0, 0.0)
	var long_range := _ranged_attack(state, FakeLosProvider.new())
	_expect(long_range.events[0].data.get("disadvantage") and (long_range.events[0].data.get("rolls") as Array).size() == 2, "Shortbow long range did not impose deterministic disadvantage", failures)
	(state.actors[1] as ActorState).position = Vector3(97.0, 0.0, 0.0)
	var beyond := _ranged_attack(state, FakeLosProvider.new())
	_expect(beyond.events[0].data.get("reason") == &"target_out_of_range", "Shortbow attack beyond long range was not rejected", failures)
	(state.actors[1] as ActorState).position = Vector3(20.0, 0.0, 0.0)
	var nearby := ActorState.new()
	nearby.id = 3
	nearby.side = &"heroes"
	nearby.hp = 10
	nearby.max_hp = 10
	nearby.position = Vector3(1.0, 0.0, 0.0)
	state.actors[3] = nearby
	state.active_combatant_ids.append(3)
	var threatened := _ranged_attack(state, FakeLosProvider.new())
	_expect(threatened.events[0].data.get("disadvantage"), "nearby hostile did not impose disadvantage on a ranged attack", failures)
	state.actors.erase(3)
	state.active_combatant_ids.erase(3)
	var cover_los := FakeLosProvider.new()
	cover_los.set_cover((state.actors[2] as ActorState).position, (state.actors[1] as ActorState).position, LosProvider.COVER_HALF)
	var half_cover := _ranged_attack(state, cover_los)
	_expect(half_cover.events[0].data.get("cover_bonus") == 2, "half cover did not add +2 AC", failures)
	cover_los.set_cover((state.actors[2] as ActorState).position, (state.actors[1] as ActorState).position, LosProvider.COVER_THREE_QUARTERS)
	var three_quarters := _ranged_attack(state, cover_los)
	_expect(three_quarters.events[0].data.get("cover_bonus") == 5, "three-quarters cover did not add +5 AC", failures)
	cover_los.set_cover((state.actors[2] as ActorState).position, (state.actors[1] as ActorState).position, LosProvider.COVER_TOTAL)
	var total_cover := _ranged_attack(state, cover_los)
	_expect(total_cover.events[0].data.get("reason") == &"no_line_of_sight", "total cover did not reject direct targeting", failures)
	var damage_state := _archer_battle(Vector3(20.0, 0.0, 0.0))
	(damage_state.actors[2] as ActorState).attack_bonus = 100
	var damage_result := _ranged_attack(damage_state, FakeLosProvider.new())
	var damage_event := _event(damage_result, &"damage_taken")
	_expect(damage_event != null and damage_event.data.get("damage_type") == &"piercing", "Shortbow damage event omitted piercing damage type", failures)


static func _test_attack_continues_into_secondary_effects(failures: Array[String]) -> void:
	var definitions := DefinitionLibrary.new()
	var ability := AbilityDefinition.new()
	ability.id = &"test_follow_through"
	ability.costs_action = true
	ability.targeting = &"actor"
	ability.target_range_meters = 2.4
	var attack_effect := AbilityEffect.new()
	attack_effect.type = &"perform_attack"
	var condition_effect := AbilityEffect.new()
	condition_effect.type = &"apply_condition"
	condition_effect.condition_id = &"prone"
	condition_effect.apply_when = &"attack_hit"
	ability.effects = [attack_effect, condition_effect]
	definitions.add_ability(ability)
	definitions.add_condition(DefinitionLibrary.get_default().get_condition(&"prone"))
	var state := _active_battle([1, 2])
	(state.actors[1] as ActorState).attack_bonus = 100
	var command := Command.create(ability.id, 1)
	command.target_id = 2
	var result := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new(), definitions)
	_expect(_has_event(result, &"attack_rolled") and _has_event(result, &"condition_added"), "perform_attack returned before its ordered secondary effect", failures)


static func _test_archer_ai_creates_standoff(failures: Array[String]) -> void:
	var state := _archer_battle(Vector3(1.0, 0.0, 0.0))
	var ai := EnemyAI.new()
	var first := ai.choose_command(state, 2, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(first != null and first.type == &"disengage", "adjacent archer did not prefer Disengage before retreating", failures)
	if first == null:
		return
	TestHelpers.apply_result(state, Resolver.resolve(state, first, FakeNavProvider.new(), FakeLosProvider.new()))
	var second := ai.choose_command(state, 2, FakeNavProvider.new(), FakeLosProvider.new())
	var old_distance := (state.actors[2] as ActorState).position.distance_to((state.actors[1] as ActorState).position)
	_expect(second != null and second.type == &"move" and second.target_pos.distance_to((state.actors[1] as ActorState).position) > old_distance, "disengaged archer did not move outward to create useful range", failures)
	if second != null and second.type == &"move":
		TestHelpers.apply_result(state, Resolver.resolve(state, second, FakeNavProvider.new(), FakeLosProvider.new()))
		var third := ai.choose_command(state, 2, FakeNavProvider.new(), FakeLosProvider.new())
		_expect(third != null and third.type == &"end_turn", "archer with its action spent did not finish the turn after retreating", failures)


static func _test_new_state_round_trip(failures: Array[String]) -> void:
	var state := _active_battle([1, 2])
	state.cleared_encounter_ids = ["old_encounter"]
	state.last_encounter_outcome = &"victory"
	var objective := ObjectiveState.new()
	objective.id = "camp"
	objective.position = Vector3(4.0, 0.0, 5.0)
	objective.radius_m = 3.0
	objective.requires_encounter_ids = ["old_encounter"]
	state.objectives[objective.id] = objective
	(state.actors[1] as ActorState).add_condition(&"dodging", 1, 1, &"turn_start")
	var restored := BattleState.from_dict(state.to_dict())
	_expect(restored.active_encounter_id == "encounter_a" and restored.active_combatant_ids == [1, 2], "active encounter state did not round-trip", failures)
	_expect(restored.cleared_encounter_ids == ["old_encounter"] and restored.last_encounter_outcome == &"victory" and restored.game_outcome == &"ongoing", "outcome state did not round-trip", failures)
	var restored_objective := restored.objectives.get("camp") as ObjectiveState
	var restored_condition := (restored.actors[1] as ActorState).condition_state(&"dodging")
	_expect(restored_objective != null and restored_objective.position == objective.position and restored_objective.radius_m == 3.0, "objective state did not round-trip", failures)
	_expect(restored_condition != null and restored_condition.expiration_timing == &"turn_start", "condition state did not round-trip", failures)
	_expect(JSON.stringify(state.stable_snapshot()) == JSON.stringify(restored.stable_snapshot()), "new gameplay state was not snapshot-stable after serialization", failures)


static func _active_battle(order: Array[int]) -> BattleState:
	var state := TestHelpers.make_battle(42)
	state.phase = &"combat"
	state.initiative_order = order.duplicate()
	state.current_turn_index = 0
	state.active_encounter_id = "encounter_a"
	state.active_combatant_ids = [1, 2]
	return state


static func _archer_battle(target_position: Vector3) -> BattleState:
	var state := _active_battle([2, 1])
	var definitions := DefinitionLibrary.get_default()
	var archer := ActorState.from_definition(definitions.get_actor(&"archer"), 2, &"enemies", Vector3.ZERO)
	archer.action_available = true
	state.actors[2] = archer
	(state.actors[1] as ActorState).position = target_position
	return state


static func _ranged_attack(state: BattleState, los: LosProvider) -> ResolutionResult:
	var command := Command.create(&"ranged_attack", 2)
	command.target_id = 1
	return Resolver.resolve(state, command, FakeNavProvider.new(), los)


static func _event(result: ResolutionResult, event_type: StringName) -> Event:
	for candidate in result.events:
		if candidate.type == event_type:
			return candidate
	return null


static func _has_event(result: ResolutionResult, event_type: StringName) -> bool:
	return _event(result, event_type) != null


static func _event_types(result: ResolutionResult) -> Array[StringName]:
	var types: Array[StringName] = []
	for event in result.events:
		types.append(event.type)
	return types


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
