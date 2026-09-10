class_name TestSimulation
extends RefCounted

const PolylineUtil = preload("res://sim/polyline.gd")
const InitiativeRules = preload("res://sim/rules/initiative.gd")

static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_clone_is_independent(failures)
	_test_equal_inputs_produce_equal_resolution(failures)
	_test_resolve_does_not_mutate_input(failures)
	_test_apply_changes_only_event_fields(failures)
	_test_rejections_are_non_mutating(failures)
	_test_navigation_rejection_is_non_mutating(failures)
	_test_action_economy_dash_and_disengage(failures)
	_test_basic_attack_targeting_and_outcomes(failures)
	_test_opportunity_attack_and_disengage(failures)
	_test_conditions_and_death(failures)
	_test_a5_resolution_is_pure(failures)
	_test_combat_move_below_budget_spends_polyline_cost(failures)
	_test_combat_move_beyond_budget_clamps_to_exact_distance(failures)
	_test_detour_clamp_uses_polyline_distance(failures)
	_test_exploration_move_ignores_budget(failures)
	_test_zero_budget_and_empty_segment_reject_without_mutation(failures)
	_test_move_preview_resolution_is_pure(failures)
	_test_initiative_is_deterministic_and_pure(failures)
	_test_initiative_ties_prefer_higher_dexterity(failures)
	_test_initiative_ties_use_stable_actor_id(failures)
	_test_combat_start_and_end_apply_lifecycle(failures)
	_test_only_current_actor_can_move_or_end_turn(failures)
	_test_end_turn_advances_wraps_and_restores_resources(failures)
	_test_serialization_round_trip(failures)
	_test_skill_check_rolls_in_any_phase(failures)
	_test_skill_check_rejects_malformed_metadata(failures)
	_test_set_disposition_applies_and_is_exploration_only(failures)
	_test_transfer_coins_is_atomic_and_exploration_only(failures)
	_test_clear_encounter_is_authoritative_and_exploration_only(failures)
	return {"name": "unit/test_simulation", "failures": failures}


static func _test_clone_is_independent(failures: Array[String]) -> void:
	var original := TestHelpers.make_battle()
	var clone := original.clone()
	(clone.actors[1] as ActorState).hp = 1
	clone.rng_state = 99
	_expect((original.actors[1] as ActorState).hp == 20, "clone changed original actor", failures)
	_expect(original.rng_state == 42, "clone changed original RNG", failures)


static func _test_equal_inputs_produce_equal_resolution(failures: Array[String]) -> void:
	var first_state := TestHelpers.make_battle(42)
	var second_state := TestHelpers.make_battle(42)
	var command := Command.create(&"attack", 1)
	command.target_id = 2
	var first_result := Resolver.resolve(first_state, command, FakeNavProvider.new(), FakeLosProvider.new())
	var second_result := Resolver.resolve(second_state, command, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(
		TestHelpers.event_log_entry(first_result) == TestHelpers.event_log_entry(second_result),
		"equal state, command, and providers produced different resolutions",
		failures,
	)


static func _test_resolve_does_not_mutate_input(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var before_hash := JSON.stringify(state.stable_snapshot()).md5_text()
	var command := Command.create(&"attack", 1)
	command.target_id = 2
	Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(JSON.stringify(state.stable_snapshot()).md5_text() == before_hash, "resolve mutated BattleState", failures)


static func _test_apply_changes_only_event_fields(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var untouched_position := (state.actors[2] as ActorState).position
	Resolver.apply(state, Event.create(&"damage_taken", {"actor_id": 1, "source_actor_id": 2, "amount": 4}))
	_expect((state.actors[1] as ActorState).hp == 16, "damage event did not change HP", failures)
	_expect((state.actors[2] as ActorState).position == untouched_position, "damage event changed unrelated actor", failures)
	_expect(state.rng_state == 42, "damage event changed RNG", failures)


static func _test_rejections_are_non_mutating(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var command := Command.create(&"unsupported", 1)
	var result := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(result.events.size() == 1 and result.events[0].type == &"command_rejected", "unsupported command was not rejected", failures)
	_expect((state.actors[1] as ActorState).position == Vector3.ZERO, "rejected command changed position", failures)


static func _test_navigation_rejection_is_non_mutating(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var command := Command.create(&"move", 1)
	command.target_pos = Vector3(7.0, 0.0, 7.0)
	var nav := FakeNavProvider.new()
	nav.blocked_destinations.append(command.target_pos)
	var before_hash := JSON.stringify(state.stable_snapshot()).md5_text()
	var result := Resolver.resolve(state, command, nav, FakeLosProvider.new())
	_expect(result.events.size() == 1 and result.events[0].type == &"command_rejected", "non-navigable target was accepted", failures)
	_expect(result.events[0].data["reason"] == &"unreachable", "non-navigable target used the wrong rejection reason", failures)
	_expect(JSON.stringify(state.stable_snapshot()).md5_text() == before_hash, "navigation rejection changed BattleState", failures)


static func _test_action_economy_dash_and_disengage(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var dash := Resolver.resolve(state, Command.create(&"dash", 1), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(dash.events.size() == 2 and dash.events[0].type == &"action_spent" and dash.events[1].type == &"movement_gained", "dash did not emit action and movement events", failures)
	TestHelpers.apply_result(state, dash)
	var hero: ActorState = state.actors[1]
	_expect(not hero.action_available and is_equal_approx(hero.movement_remaining, 18.0), "dash did not consume action and grant base speed", failures)
	var second_action := Resolver.resolve(state, Command.create(&"disengage", 1), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(second_action.events[0].data["reason"] == &"action_unavailable", "second action in one turn was accepted", failures)
	# The bonus-action resource remains represented and reset by A4 even though
	# A5 intentionally supplies no bonus-action ability yet.
	_expect(hero.bonus_action_available and hero.reaction_available, "unused economy resources changed during dash", failures)
	var fresh := TestHelpers.make_battle()
	var disengage := Resolver.resolve(fresh, Command.create(&"disengage", 1), FakeNavProvider.new(), FakeLosProvider.new())
	TestHelpers.apply_result(fresh, disengage)
	_expect(not (fresh.actors[1] as ActorState).action_available and (fresh.actors[1] as ActorState).disengaged, "disengage did not consume action for the turn", failures)


static func _test_basic_attack_targeting_and_outcomes(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle(42)
	var attack := Command.create(&"basic_attack", 1)
	attack.target_id = 2
	var result := Resolver.resolve(state, attack, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(result.events.size() >= 1 and result.events[0].type == &"attack_rolled" and result.events[0].data["attack_kind"] == &"basic", "basic attack did not target one actor", failures)
	TestHelpers.apply_result(state, result)
	_expect(not (state.actors[1] as ActorState).action_available, "basic attack did not consume action", failures)
	var no_los_state := TestHelpers.make_battle()
	var blocked_los := FakeLosProvider.new()
	blocked_los.block((no_los_state.actors[1] as ActorState).position, (no_los_state.actors[2] as ActorState).position)
	var blocked := Resolver.resolve(no_los_state, attack, FakeNavProvider.new(), blocked_los)
	_expect(blocked.events[0].data["reason"] == &"no_line_of_sight", "attack did not reject line-of-sight failure", failures)
	var out_of_range_state := TestHelpers.make_battle()
	(out_of_range_state.actors[2] as ActorState).position = Vector3(9.0, 0.0, 0.0)
	var far := Resolver.resolve(out_of_range_state, attack, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(far.events[0].data["reason"] == &"target_out_of_range", "attack did not reject out-of-range actor target", failures)


static func _test_opportunity_attack_and_disengage(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle(5)
	var hero: ActorState = state.actors[1]
	hero.armor_class = 1
	var enemy: ActorState = state.actors[2]
	enemy.attack_bonus = 20
	var move := Command.create(&"move", 1)
	move.target_pos = Vector3(4.0, 0.0, 0.0)
	var result := Resolver.resolve(state, move, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_event_count(result, &"reaction_triggered") == 1 and _event_count(result, &"attack_rolled") == 1, "leaving a visible enemy threat range did not trigger one opportunity attack", failures)
	_expect(_event_count(result, &"movement_segment") == 2, "opportunity attack did not split the authoritative move path", failures)
	var before_hash := JSON.stringify(state.stable_snapshot()).md5_text()
	_expect(before_hash == JSON.stringify(state.stable_snapshot()).md5_text(), "opportunity attack resolve mutated state", failures)
	TestHelpers.apply_result(state, result)
	_expect(not (state.actors[2] as ActorState).reaction_available and (state.actors[1] as ActorState).position == move.target_pos, "opportunity resolution did not spend reaction or complete surviving move", failures)

	var disengaged_state := TestHelpers.make_battle(5)
	var disengaged_hero: ActorState = disengaged_state.actors[1]
	disengaged_hero.disengaged = true
	var safe_move := Command.create(&"move", 1)
	safe_move.target_pos = Vector3(4.0, 0.0, 0.0)
	var safe_result := Resolver.resolve(disengaged_state, safe_move, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_event_count(safe_result, &"reaction_triggered") == 0 and _event_count(safe_result, &"movement_segment") == 1, "disengage did not protect against opportunity attacks", failures)

	var hidden_state := TestHelpers.make_battle(5)
	var hidden_los := FakeLosProvider.new()
	hidden_los.block((hidden_state.actors[2] as ActorState).position, (hidden_state.actors[1] as ActorState).position)
	var hidden_result := Resolver.resolve(hidden_state, safe_move, FakeNavProvider.new(), hidden_los)
	_expect(_event_count(hidden_result, &"reaction_triggered") == 0, "enemy without visibility triggered an opportunity attack", failures)

	# BG3-style Prone: a creature lying on the ground cannot react, so walking
	# away from a shoved enemy provokes nothing (its reaction stays unspent).
	var prone_threat_state := TestHelpers.make_battle(5)
	(prone_threat_state.actors[2] as ActorState).add_condition(&"prone", 1)
	var prone_threat_result := Resolver.resolve(prone_threat_state, safe_move, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_event_count(prone_threat_result, &"reaction_triggered") == 0 and _event_count(prone_threat_result, &"movement_segment") == 1, "a prone enemy made an opportunity attack", failures)
	_expect((prone_threat_state.actors[2] as ActorState).reaction_available and not (prone_threat_state.actors[2] as ActorState).can_take_reactions(), "Prone did not block reactions while leaving the reaction unspent", failures)

	var fatal_state := TestHelpers.make_battle(5)
	var fatal_hero: ActorState = fatal_state.actors[1]
	fatal_hero.hp = 1
	var fatal_enemy: ActorState = fatal_state.actors[2]
	fatal_enemy.attack_bonus = 100
	fatal_enemy.damage_die = 1
	fatal_enemy.damage_modifier = 100
	var fatal_result := Resolver.resolve(fatal_state, safe_move, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_event_count(fatal_result, &"actor_died") == 1 and _event_count(fatal_result, &"movement_segment") == 1, "fatal opportunity attack did not stop the remaining resolved path", failures)
	TestHelpers.apply_result(fatal_state, fatal_result)
	_expect((fatal_state.actors[1] as ActorState).position.distance_to(Vector3(2.5, 0.0, 0.0)) < 0.001, "fatal opportunity attack moved actor past threat boundary", failures)


static func _test_conditions_and_death(failures: Array[String]) -> void:
	var prone_state := TestHelpers.make_battle()
	_remove_opportunity_threat(prone_state)
	(prone_state.actors[1] as ActorState).add_condition(&"prone")
	var prone_move := Command.create(&"move", 1)
	prone_move.target_pos = Vector3(3.0, 0.0, 0.0)
	var prone_result := Resolver.resolve(prone_state, prone_move, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(prone_result.events[0].type == &"condition_removed" and prone_result.events[1].type == &"movement_spent" and is_equal_approx(float(prone_result.events[1].data["amount"]), 4.5), "prone did not spend half base movement to stand", failures)
	TestHelpers.apply_result(prone_state, prone_result)
	_expect(not (prone_state.actors[1] as ActorState).has_condition(&"prone") and is_equal_approx((prone_state.actors[1] as ActorState).movement_remaining, 1.5), "prone standing movement did not apply", failures)
	var prone_target_state := TestHelpers.make_battle()
	(prone_target_state.actors[2] as ActorState).add_condition(&"prone")
	var prone_attack := Command.create(&"attack", 1)
	prone_attack.target_id = 2
	var prone_attack_result := Resolver.resolve(prone_target_state, prone_attack, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(prone_attack_result.events[0].data["advantage"] and (prone_attack_result.events[0].data["rolls"] as Array).size() == 2, "melee attack against prone target did not use advantage", failures)
	var ranged_prone_state := TestHelpers.make_battle()
	(ranged_prone_state.actors[2] as ActorState).position = Vector3(3.0, 0.0, 0.0)
	(ranged_prone_state.actors[2] as ActorState).add_condition(&"prone")
	var ranged_prone_attack := Command.create(&"attack", 1)
	ranged_prone_attack.target_id = 2
	ranged_prone_attack.metadata = {"is_ranged": true, "range_meters": 9.0}
	var ranged_prone_result := Resolver.resolve(ranged_prone_state, ranged_prone_attack, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(ranged_prone_result.events[0].data["disadvantage"] and not ranged_prone_result.events[0].data["advantage"], "ranged attack beyond close range against prone target did not use disadvantage", failures)
	var prone_attacker_state := TestHelpers.make_battle()
	(prone_attacker_state.actors[1] as ActorState).add_condition(&"prone")
	var prone_attacker_attack := Command.create(&"attack", 1)
	prone_attacker_attack.target_id = 2
	var prone_attacker_result := Resolver.resolve(prone_attacker_state, prone_attacker_attack, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(prone_attacker_result.events[0].data["disadvantage"] and (prone_attacker_result.events[0].data["rolls"] as Array).size() == 2, "a prone attacker did not roll with disadvantage", failures)

	var poisoned_state := TestHelpers.make_battle()
	(poisoned_state.actors[1] as ActorState).add_condition(&"poisoned")
	var poison_attack := Command.create(&"attack", 1)
	poison_attack.target_id = 2
	var poison_result := Resolver.resolve(poisoned_state, poison_attack, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(poison_result.events[0].data["disadvantage"] and (poison_result.events[0].data["rolls"] as Array).size() == 2, "poisoned attack did not use deterministic disadvantage", failures)

	var unconscious_state := TestHelpers.make_battle()
	(unconscious_state.actors[1] as ActorState).add_condition(&"unconscious")
	var unconscious_move := Resolver.resolve(unconscious_state, Command.create(&"move", 1), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(unconscious_move.events[0].data["reason"] == &"actor_cannot_act", "unconscious actor was allowed to move", failures)

	var lethal_state := TestHelpers.make_battle()
	var lethal_attacker: ActorState = lethal_state.actors[1]
	lethal_attacker.attack_bonus = 100
	lethal_attacker.damage_die = 1
	lethal_attacker.damage_modifier = 100
	var lethal_attack := Command.create(&"attack", 1)
	lethal_attack.target_id = 2
	var lethal_result := Resolver.resolve(lethal_state, lethal_attack, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_event_count(lethal_result, &"actor_died") == 1, "massive damage did not produce the dead condition event", failures)
	TestHelpers.apply_result(lethal_state, lethal_result)
	_expect((lethal_state.actors[2] as ActorState).has_condition(&"dead"), "actor_died did not apply dead condition", failures)


static func _test_a5_resolution_is_pure(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var before_hash := JSON.stringify(state.stable_snapshot()).md5_text()
	var command := Command.create(&"move", 1)
	command.target_pos = Vector3(4.0, 0.0, 0.0)
	Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(JSON.stringify(state.stable_snapshot()).md5_text() == before_hash, "A5 move/reaction resolution mutated BattleState", failures)


static func _test_combat_move_below_budget_spends_polyline_cost(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	_remove_opportunity_threat(state)
	var actor: ActorState = state.actors[1]
	actor.movement_remaining = 5.0
	var command := Command.create(&"move", 1)
	command.target_pos = Vector3(4.0, 0.0, 0.0)
	var nav := FakeNavProvider.new()
	nav.set_path(actor.position, command.target_pos, PackedVector3Array([
		actor.position, Vector3(1.0, 0.0, 0.0), command.target_pos,
	]))
	var result := Resolver.resolve(state, command, nav, FakeLosProvider.new())
	_expect(result.events.size() == 2, "below-budget combat move did not emit movement and spending", failures)
	var segment: Event = result.events[0]
	var spent: Event = result.events[1]
	_expect(segment.data["to"] == command.target_pos and not segment.data["clamped"], "below-budget combat move was not fully accepted", failures)
	_expect(is_equal_approx(float(segment.data["path_cost"]), 4.0) and is_equal_approx(float(spent.data["amount"]), 4.0), "below-budget combat move did not use exact polyline cost", failures)
	TestHelpers.apply_result(state, result)
	_expect(actor.position == command.target_pos and is_equal_approx(actor.movement_remaining, 1.0), "below-budget combat move did not apply exact position and spending", failures)


static func _test_combat_move_beyond_budget_clamps_to_exact_distance(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	_remove_opportunity_threat(state)
	var actor: ActorState = state.actors[1]
	actor.movement_remaining = 5.0
	var command := Command.create(&"move", 1)
	command.target_pos = Vector3(8.0, 0.0, 0.0)
	var nav := FakeNavProvider.new()
	nav.set_path(actor.position, command.target_pos, PackedVector3Array([
		actor.position, Vector3(3.0, 0.0, 0.0), command.target_pos,
	]))
	var result := Resolver.resolve(state, command, nav, FakeLosProvider.new())
	_expect(result.events.size() == 2 and result.events[0].type == &"movement_segment", "over-budget combat move was rejected instead of clamped", failures)
	var segment: Event = result.events[0]
	var clamped_path: PackedVector3Array = segment.data["path"]
	_expect(segment.data["clamped"] and segment.data["to"] == Vector3(5.0, 0.0, 0.0), "combat clamp did not find the exact polyline point", failures)
	_expect(is_equal_approx(PolylineUtil.length(clamped_path), 5.0) and is_equal_approx(float(result.events[1].data["amount"]), 5.0), "combat clamp did not spend the exact available distance", failures)
	TestHelpers.apply_result(state, result)
	_expect(actor.position == Vector3(5.0, 0.0, 0.0) and is_zero_approx(actor.movement_remaining), "clamped combat move did not exhaust movement", failures)


static func _test_detour_clamp_uses_polyline_distance(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	_remove_opportunity_threat(state)
	var actor: ActorState = state.actors[1]
	actor.movement_remaining = 8.0
	var command := Command.create(&"move", 1)
	command.target_pos = Vector3(4.0, 0.0, 0.0)
	var detour := PackedVector3Array([
		actor.position, Vector3(0.0, 0.0, 6.0), Vector3(4.0, 0.0, 6.0), command.target_pos,
	])
	var nav := FakeNavProvider.new()
	nav.set_path(actor.position, command.target_pos, detour)
	var result := Resolver.resolve(state, command, nav, FakeLosProvider.new())
	var segment: Event = result.events[0]
	_expect(segment.data["to"] == Vector3(2.0, 0.0, 6.0), "detour clamp used direct target distance instead of path distance", failures)
	_expect(is_equal_approx(float(segment.data["requested_path_cost"]), 16.0) and is_equal_approx(float(segment.data["path_cost"]), 8.0), "detour clamp recorded inaccurate polyline costs", failures)


static func _test_exploration_move_ignores_budget(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	state.phase = &"exploration"
	var actor: ActorState = state.actors[1]
	actor.movement_remaining = 0.0
	var command := Command.create(&"move", 1)
	command.target_pos = Vector3(12.0, 0.0, 0.0)
	var result := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(result.events.size() == 1 and result.events[0].type == &"movement_segment", "exploration move incorrectly enforced budget", failures)
	TestHelpers.apply_result(state, result)
	_expect(actor.position == command.target_pos and is_zero_approx(actor.movement_remaining), "exploration move changed movement budget", failures)


static func _test_zero_budget_and_empty_segment_reject_without_mutation(failures: Array[String]) -> void:
	var zero_budget_state := TestHelpers.make_battle()
	_remove_opportunity_threat(zero_budget_state)
	(zero_budget_state.actors[1] as ActorState).movement_remaining = 0.0
	var zero_budget_command := Command.create(&"move", 1)
	zero_budget_command.target_pos = Vector3(3.0, 0.0, 0.0)
	var before_hash := JSON.stringify(zero_budget_state.stable_snapshot()).md5_text()
	var zero_budget_result := Resolver.resolve(zero_budget_state, zero_budget_command, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(zero_budget_result.events.size() == 1 and zero_budget_result.events[0].data["reason"] == &"no_movement_remaining", "zero budget did not reject cleanly", failures)
	_expect(JSON.stringify(zero_budget_state.stable_snapshot()).md5_text() == before_hash, "zero-budget rejection changed BattleState", failures)

	var empty_segment_state := TestHelpers.make_battle()
	_remove_opportunity_threat(empty_segment_state)
	var empty_segment_command := Command.create(&"move", 1)
	empty_segment_command.target_pos = Vector3.ZERO
	var empty_result := Resolver.resolve(empty_segment_state, empty_segment_command, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(empty_result.events.size() == 1 and empty_result.events[0].data["reason"] == &"no_movement", "empty usable segment did not reject cleanly", failures)
	_expect((empty_segment_state.actors[1] as ActorState).position == Vector3.ZERO, "empty usable segment moved the actor", failures)


static func _test_move_preview_resolution_is_pure(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	_remove_opportunity_threat(state)
	var command := Command.create(&"move", 1)
	command.target_pos = Vector3(6.0, 0.0, 0.0)
	var before_hash := JSON.stringify(state.stable_snapshot()).md5_text()
	var preview_result := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(preview_result.events.size() == 2 and preview_result.events[0].type == &"movement_segment", "movement preview did not resolve a usable result", failures)
	_expect(JSON.stringify(state.stable_snapshot()).md5_text() == before_hash, "movement preview resolution mutated BattleState", failures)


static func _test_initiative_is_deterministic_and_pure(failures: Array[String]) -> void:
	var first_state := TestHelpers.make_battle(42)
	first_state.phase = &"exploration"
	var second_state := first_state.clone()
	var before_hash := JSON.stringify(first_state.stable_snapshot()).md5_text()
	var command := Command.create(&"start_combat", 1)
	var first_result := Resolver.resolve(first_state, command, FakeNavProvider.new(), FakeLosProvider.new())
	var second_result := Resolver.resolve(second_state, command, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(first_result.events.size() == 3, "combat start did not emit lifecycle and first-turn events", failures)
	_expect(first_result.events[1].type == &"initiative_established", "combat start did not establish initiative", failures)
	_expect(TestHelpers.event_log_entry(first_result) == TestHelpers.event_log_entry(second_result), "same seed produced different initiative events", failures)
	_expect(JSON.stringify(first_state.stable_snapshot()).md5_text() == before_hash, "initiative resolution mutated BattleState", failures)


static func _test_initiative_ties_prefer_higher_dexterity(failures: Array[String]) -> void:
	var entries: Array[Dictionary] = [{
		"actor_id": 1, "roll": 12, "dexterity": 12, "dexterity_modifier": 1, "total": 13,
	}, {
		"actor_id": 2, "roll": 10, "dexterity": 16, "dexterity_modifier": 3, "total": 13,
	}]
	var sorted_entries := InitiativeRules.sort_entries(entries)
	_expect(sorted_entries[0]["actor_id"] == 2, "initiative tie did not prefer higher DEX", failures)


static func _test_initiative_ties_use_stable_actor_id(failures: Array[String]) -> void:
	var entries: Array[Dictionary] = [{
		"actor_id": 9, "roll": 12, "dexterity": 14, "dexterity_modifier": 2, "total": 14,
	}, {
		"actor_id": 4, "roll": 12, "dexterity": 14, "dexterity_modifier": 2, "total": 14,
	}]
	var sorted_entries := InitiativeRules.sort_entries(entries)
	_expect(sorted_entries[0]["actor_id"] == 4, "initiative tie did not use stable actor ID", failures)


static func _test_combat_start_and_end_apply_lifecycle(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	state.phase = &"exploration"
	var start_result := Resolver.resolve(state, Command.create(&"start_combat", 1), FakeNavProvider.new(), FakeLosProvider.new())
	Resolver.apply(state, start_result.events[0])
	_expect(state.phase == &"combat_starting", "combat_started did not apply combat_starting phase", failures)
	for event_index in range(1, start_result.events.size()):
		Resolver.apply(state, start_result.events[event_index])
	state.rng_state = start_result.next_rng_state
	_expect(state.phase == &"combat" and state.initiative_order.size() == 2 and state.current_actor_id() != -1, "combat start did not apply initiative and active turn", failures)
	var end_result := Resolver.resolve(state, Command.create(&"end_combat", state.current_actor_id()), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(end_result.events.size() == 1 and end_result.events[0].type == &"command_rejected", "unresolved combat did not reject end_combat", failures)
	_expect(end_result.events[0].data["reason"] == &"combat_unresolved", "unresolved combat returned the wrong rejection reason", failures)
	_expect(state.phase == &"combat" and not state.initiative_order.is_empty(), "rejected combat end changed lifecycle state", failures)


static func _test_only_current_actor_can_move_or_end_turn(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var before_hash := JSON.stringify(state.stable_snapshot()).md5_text()
	var other_move := Command.create(&"move", 2)
	other_move.target_pos = Vector3(2.0, 0.0, 0.0)
	var move_result := Resolver.resolve(state, other_move, FakeNavProvider.new(), FakeLosProvider.new())
	var end_result := Resolver.resolve(state, Command.create(&"end_turn", 2), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(move_result.events[0].data["reason"] == &"not_current_actor", "non-current actor moved in combat", failures)
	_expect(end_result.events[0].data["reason"] == &"not_current_actor", "non-current actor ended turn in combat", failures)
	_expect(JSON.stringify(state.stable_snapshot()).md5_text() == before_hash, "rejected non-current commands mutated BattleState", failures)


static func _test_end_turn_advances_wraps_and_restores_resources(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var next_actor: ActorState = state.actors[2]
	next_actor.movement_remaining = 0.0
	next_actor.action_available = false
	next_actor.bonus_action_available = false
	next_actor.reaction_available = false
	next_actor.disengaged = true
	var first_result := Resolver.resolve(state, Command.create(&"end_turn", 1), FakeNavProvider.new(), FakeLosProvider.new())
	TestHelpers.apply_result(state, first_result)
	_expect(state.current_actor_id() == 2 and state.current_turn_index == 1 and state.round_number == 1, "end turn did not advance exactly one actor", failures)
	_expect(is_equal_approx(next_actor.movement_remaining, next_actor.movement_speed) and next_actor.action_available and next_actor.bonus_action_available and next_actor.reaction_available and not next_actor.disengaged, "turn start did not restore all per-turn resources", failures)
	var second_result := Resolver.resolve(state, Command.create(&"end_turn", 2), FakeNavProvider.new(), FakeLosProvider.new())
	TestHelpers.apply_result(state, second_result)
	_expect(state.current_actor_id() == 1 and state.current_turn_index == 0 and state.round_number == 2, "turn order did not wrap and increment the round", failures)


static func _test_serialization_round_trip(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	state.world_flags = {"checkpoint": Vector3(2.0, 0.0, -3.0), "opened": true}
	var command := Command.create(&"move", 1)
	command.target_pos = Vector3(3.0, 0.0, -2.0)
	command.metadata = {"source": &"click", "sequence": 4}
	var result := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
	var restored_state := BattleState.from_dict(_json_dictionary(state.to_dict()))
	var restored_command := Command.from_dict(_json_dictionary(command.to_dict()))
	var restored_result := ResolutionResult.from_dict(_json_dictionary(result.to_dict()))
	_expect(restored_state.to_dict() == state.to_dict(), "BattleState serialization changed semantic data", failures)
	_expect(restored_command.to_dict() == command.to_dict(), "Command serialization changed semantic data", failures)
	_expect(TestHelpers.event_log_entry(restored_result) == TestHelpers.event_log_entry(result), "ResolutionResult/Event serialization changed event semantics", failures)
	var applied_original := state.clone()
	var applied_restored := state.clone()
	TestHelpers.apply_result(applied_original, result)
	TestHelpers.apply_result(applied_restored, restored_result)
	_expect(applied_restored.to_dict() == applied_original.to_dict(), "restored ResolutionResult applied different state", failures)


static func _json_dictionary(data: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	if parsed is Dictionary:
		return parsed
	return {}


## A check is not an action: it is legal on either side of the phase boundary
## and spends nothing, because a conversation happens outside the turn economy.
static func _test_skill_check_rolls_in_any_phase(failures: Array[String]) -> void:
	for phase in [&"exploration", &"combat"]:
		var state := TestHelpers.make_battle()
		state.phase = phase
		var actor: ActorState = state.actors[1]
		actor.charisma = 16
		actor.proficiency_bonus = 2
		var command := Command.create(&"skill_check", 1)
		command.target_id = 2
		command.metadata = {"ability": &"charisma", "skill": &"persuasion", "dc": 12, "proficient": true}
		var result := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
		var rolled := _first_event(result, &"skill_check_rolled")
		_expect(rolled != null, "skill_check should resolve during %s" % phase, failures)
		if rolled == null:
			continue
		_expect(int(rolled.data["modifier"]) == 5, "the check should use the actor's charisma plus proficiency", failures)
		_expect(int(rolled.data["total"]) == int(rolled.data["roll"]) + 5, "total should be the roll plus the modifier", failures)
		_expect(bool(rolled.data["success"]) == (int(rolled.data["total"]) >= 12), "success should compare the total against the DC", failures)
		_expect(rolled.data["skill"] == &"persuasion" and int(rolled.data["target_id"]) == 2, "the event should carry its narration context", failures)
		_expect(result.next_rng_state != state.rng_state, "a check must advance the rng_state", failures)
		# A check costs nothing, so applying it must leave the turn economy alone.
		TestHelpers.apply_result(state, result)
		_expect(actor.action_available and is_equal_approx(actor.movement_remaining, actor.movement_speed), "a check must not spend an action or movement", failures)


static func _test_skill_check_rejects_malformed_metadata(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	# A skill name is not an ability score; this is the guard that keeps the
	# resolver from silently treating one as the other.
	for metadata in [{"ability": &"persuasion", "dc": 12}, {"ability": &"", "dc": 12}]:
		var bad_ability := Command.create(&"skill_check", 1)
		bad_ability.metadata = metadata
		var rejection := _first_event(Resolver.resolve(state, bad_ability, FakeNavProvider.new(), FakeLosProvider.new()), &"command_rejected")
		_expect(rejection != null and rejection.data["reason"] == &"invalid_ability_score", "a non-ability-score check should be rejected", failures)
	var bad_dc := Command.create(&"skill_check", 1)
	bad_dc.metadata = {"ability": &"charisma", "dc": 0}
	var dc_rejection := _first_event(Resolver.resolve(state, bad_dc, FakeNavProvider.new(), FakeLosProvider.new()), &"command_rejected")
	_expect(dc_rejection != null and dc_rejection.data["reason"] == &"invalid_difficulty_class", "a DC below 1 should be rejected", failures)


static func _test_set_disposition_applies_and_is_exploration_only(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	state.phase = &"exploration"
	var enemy: ActorState = state.actors[2]
	_expect(enemy.disposition == &"hostile", "an actor should default to a hostile stance", failures)
	var pacify := Command.create(&"set_disposition", 2)
	pacify.metadata = {"disposition": &"neutral"}
	var result := Resolver.resolve(state, pacify, FakeNavProvider.new(), FakeLosProvider.new())
	var changed := _first_event(result, &"disposition_changed")
	_expect(changed != null and changed.data["previous_disposition"] == &"hostile", "the event should record the stance it replaced", failures)
	TestHelpers.apply_result(state, result)
	_expect(enemy.disposition == &"neutral", "apply() should be the only thing that changes the stance", failures)

	var garbage := Command.create(&"set_disposition", 2)
	garbage.metadata = {"disposition": &"furious"}
	var garbage_rejection := _first_event(Resolver.resolve(state, garbage, FakeNavProvider.new(), FakeLosProvider.new()), &"command_rejected")
	_expect(garbage_rejection != null and garbage_rejection.data["reason"] == &"invalid_disposition", "an unknown stance should be rejected", failures)

	# V1 rule: you cannot talk a fight down once it has started.
	state.phase = &"combat"
	var mid_combat := Command.create(&"set_disposition", 2)
	mid_combat.metadata = {"disposition": &"neutral"}
	var combat_rejection := _first_event(Resolver.resolve(state, mid_combat, FakeNavProvider.new(), FakeLosProvider.new()), &"command_rejected")
	_expect(combat_rejection != null and combat_rejection.data["reason"] == &"combat_already_active", "set_disposition should be rejected during combat", failures)


static func _test_transfer_coins_is_atomic_and_exploration_only(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	state.phase = &"exploration"
	(state.actors[1] as ActorState).coins = 10
	(state.actors[2] as ActorState).coins = 3
	var command := Command.create(&"transfer_coins", 1)
	command.target_id = 2
	command.metadata = {"amount": 10}
	var before := JSON.stringify(state.stable_snapshot())
	var result := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
	var transfer := _first_event(result, &"coins_transferred")
	_expect(transfer != null and int(transfer.data["amount"]) == 10, "an affordable transfer should emit one coin event", failures)
	_expect(JSON.stringify(state.stable_snapshot()) == before, "coin transfer resolution mutated its input", failures)
	TestHelpers.apply_result(state, result)
	_expect((state.actors[1] as ActorState).coins == 0 and (state.actors[2] as ActorState).coins == 13, "applying a transfer should debit and credit atomically", failures)

	var insufficient := Command.create(&"transfer_coins", 1)
	insufficient.target_id = 2
	insufficient.metadata = {"amount": 1}
	var rejected := _first_event(Resolver.resolve(state, insufficient, FakeNavProvider.new(), FakeLosProvider.new()), &"command_rejected")
	_expect(rejected != null and rejected.data["reason"] == &"insufficient_coins", "an overdrawn transfer should be rejected", failures)
	for bad_amount in [0, -1, 1.5]:
		var malformed := Command.create(&"transfer_coins", 1)
		malformed.target_id = 2
		malformed.metadata = {"amount": bad_amount}
		var amount_rejection := _first_event(Resolver.resolve(state, malformed, FakeNavProvider.new(), FakeLosProvider.new()), &"command_rejected")
		_expect(amount_rejection != null and amount_rejection.data["reason"] == &"invalid_coin_amount", "coin amount %s should be rejected" % bad_amount, failures)
	var self_transfer := Command.create(&"transfer_coins", 1)
	self_transfer.target_id = 1
	self_transfer.metadata = {"amount": 1}
	var self_rejection := _first_event(Resolver.resolve(state, self_transfer, FakeNavProvider.new(), FakeLosProvider.new()), &"command_rejected")
	_expect(self_rejection != null and self_rejection.data["reason"] == &"invalid_target", "a transfer to oneself should be rejected", failures)
	state.phase = &"combat"
	var mid_combat := Command.create(&"transfer_coins", 1)
	mid_combat.target_id = 2
	mid_combat.metadata = {"amount": 1}
	var combat_rejection := _first_event(Resolver.resolve(state, mid_combat, FakeNavProvider.new(), FakeLosProvider.new()), &"command_rejected")
	_expect(combat_rejection != null and combat_rejection.data["reason"] == &"combat_already_active", "transfers should be exploration-only", failures)


static func _test_clear_encounter_is_authoritative_and_exploration_only(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	state.phase = &"exploration"
	var clear := Command.create(&"clear_encounter", 1)
	clear.metadata = {"encounter_id": "ambush"}
	var before := JSON.stringify(state.stable_snapshot())
	var result := Resolver.resolve(state, clear, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_first_event(result, &"encounter_cleared") != null, "a peaceful encounter clear should emit an authoritative event", failures)
	_expect(JSON.stringify(state.stable_snapshot()) == before, "clearing an encounter mutated state during resolution", failures)
	TestHelpers.apply_result(state, result)
	_expect(state.cleared_encounter_ids == ["ambush"], "applying an encounter clear should unlock its objective gate", failures)
	TestHelpers.apply_result(state, result)
	_expect(state.cleared_encounter_ids == ["ambush"], "applying the same encounter clear twice should remain idempotent", failures)
	var missing_id := Command.create(&"clear_encounter", 1)
	var missing_rejection := _first_event(Resolver.resolve(state, missing_id, FakeNavProvider.new(), FakeLosProvider.new()), &"command_rejected")
	_expect(missing_rejection != null and missing_rejection.data["reason"] == &"invalid_encounter", "an encounter clear needs an authored encounter id", failures)
	state.phase = &"combat"
	var combat_clear := Command.create(&"clear_encounter", 1)
	combat_clear.metadata = {"encounter_id": "ambush"}
	var combat_rejection := _first_event(Resolver.resolve(state, combat_clear, FakeNavProvider.new(), FakeLosProvider.new()), &"command_rejected")
	_expect(combat_rejection != null and combat_rejection.data["reason"] == &"combat_already_active", "encounter clears should be exploration-only", failures)


static func _first_event(result: ResolutionResult, type: StringName) -> Event:
	for event in result.events:
		if event.type == type:
			return event
	return null


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


static func _event_count(result: ResolutionResult, event_type: StringName) -> int:
	var count := 0
	for event in result.events:
		if event.type == event_type:
			count += 1
	return count


static func _remove_opportunity_threat(state: BattleState) -> void:
	(state.actors[2] as ActorState).position = Vector3(30.0, 0.0, 0.0)
