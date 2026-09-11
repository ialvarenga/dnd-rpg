class_name TestJumping
extends RefCounted

## ADR-009 ledge jumps: SRD 5.2.1 Long/High Jump and Falling numbers, and how
## the resolver spends, clamps, and lands a jump that a NavProvider reports.

const DROP := &"drop"
const CLIMB := &"climb"


static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_jump_distances_follow_strength(failures)
	_test_drop_and_fall_outcomes(failures)
	_test_minimum_strengths_and_costs(failures)
	_test_safe_drop_costs_its_planar_distance(failures)
	_test_hard_landing_hurts_knocks_prone_and_ends_the_move(failures)
	_test_climb_costs_its_rise_and_needs_a_run_up(failures)
	_test_clamp_never_stops_mid_jump(failures)
	_test_opportunity_attack_resolves_at_takeoff(failures)
	_test_exploration_hard_landing_skips_prone(failures)
	_test_push_fall_leaves_the_target_prone(failures)
	_test_move_routes_with_the_movers_strength(failures)
	_test_jump_action_needs_a_run_up_for_full_distance(failures)
	_test_jump_action_climbs_and_drops(failures)
	_test_jump_action_needs_somewhere_to_land(failures)
	_test_run_up_is_movement_immediately_before(failures)
	_test_jump_action_outside_combat_is_free(failures)
	_test_shove_opens_combat_from_exploration(failures)
	return {"name": "unit/test_jumping", "failures": failures}


static func _test_jump_distances_follow_strength(failures: Array[String]) -> void:
	# {strength: [running long, standing long, running high, standing high, safe drop]}
	var table := {
		10: [3.0, 1.5, 0.9, 0.45, 3.9],
		12: [3.6, 1.8, 1.2, 0.6, 4.2],
		14: [4.2, 2.1, 1.5, 0.75, 4.5],
		20: [6.0, 3.0, 2.4, 1.2, 5.4],
	}
	for strength in table:
		var expected: Array = table[strength]
		var actual := [JumpRules.long_jump_m(strength), JumpRules.long_jump_m(strength, false), JumpRules.high_jump_m(strength), JumpRules.high_jump_m(strength, false), JumpRules.safe_drop_m(strength)]
		for index in range(expected.size()):
			_expect(is_equal_approx(actual[index], expected[index]), "STR %d jump value %d was %.3f, expected %.3f" % [strength, index, actual[index], expected[index]], failures)
	_expect(is_zero_approx(JumpRules.high_jump_m(1)), "a negative High Jump did not clamp to 0 feet", failures)


static func _test_drop_and_fall_outcomes(failures: Array[String]) -> void:
	_expect(int(JumpRules.drop_outcome(14, 4.49)["dice"]) == 0, "a Knight dropping just under 4.5 m should land safely", failures)
	var knight_edge := JumpRules.drop_outcome(14, 4.5)
	_expect(int(knight_edge["dice"]) == 1 and bool(knight_edge["prone"]), "a Knight dropping 4.5 m should take 1d6 and land Prone", failures)
	_expect(int(JumpRules.drop_outcome(10, 3.89)["dice"]) == 0 and int(JumpRules.drop_outcome(10, 3.9)["dice"]) == 1, "the Archer's safe drop should end at 3.9 m", failures)
	var archer_face := JumpRules.drop_outcome(10, 4.2)
	_expect(int(archer_face["dice"]) == 1 and is_equal_approx(float(archer_face["effective_m"]), 3.3), "the Archer should absorb 0.9 m of a 4.2 m drop", failures)
	_expect(int(JumpRules.drop_outcome(30, 500.0)["dice"]) == JumpRules.MAX_FALL_DICE, "fall damage did not cap at 20d6", failures)
	_expect(int(JumpRules.forced_fall_outcome(2.4)["dice"]) == 0, "a push below 2.5 m should not count as a fall", failures)
	var pushed := JumpRules.forced_fall_outcome(2.5)
	_expect(int(pushed["dice"]) == 1 and bool(pushed["prone"]), "a 2.5 m push fall should deal 1d6 and leave the target Prone", failures)
	_expect(int(JumpRules.forced_fall_outcome(6.0)["dice"]) == 2, "a push fall should not absorb any height", failures)


static func _test_minimum_strengths_and_costs(failures: Array[String]) -> void:
	_expect(JumpRules.min_strength_for_climb(1.5, true) == 14 and JumpRules.min_strength_for_climb(1.5, false) == 24, "a 1.5 m ledge should need STR 14 running or 24 standing", failures)
	_expect(JumpRules.min_strength_for_climb(1.2, true) == 12, "a 1.2 m ledge should need STR 12 running", failures)
	_expect(JumpRules.min_strength_for_climb(10.0, true) == -1, "an impossible climb should report no Strength", failures)
	_expect(JumpRules.min_strength_for_safe_drop(4.2) == 14 and JumpRules.min_strength_for_safe_drop(1.2) == 1 and JumpRules.min_strength_for_safe_drop(7.0) == -1, "safe-drop Strength thresholds are wrong", failures)
	_expect(is_equal_approx(JumpRules.jump_cost(DROP, Vector3(0, 5, 0), Vector3(2, 1, 0)), 2.0), "a drop should cost only its horizontal distance", failures)
	_expect(is_equal_approx(JumpRules.jump_cost(CLIMB, Vector3(0, 0, 0), Vector3(2, 1.5, 0)), 3.5), "a climb should cost its horizontal distance plus the rise", failures)


## Mover (actor 1) on a 4 m ledge at x 0..1, landing at x 3, walking on to x 4.
static func _ledge_battle(definition: StringName, phase: StringName = &"combat") -> BattleState:
	var definitions := DefinitionLibrary.get_default()
	var state := BattleState.new()
	state.phase = phase
	state.rng_seed = 7
	state.rng_state = 7
	if phase == &"combat":
		state.initiative_order = [1, 2]
		state.active_combatant_ids = [1, 2]
	state.actors[1] = ActorState.from_definition(definitions.get_actor(definition), 1, &"heroes", Vector3(0, 5, 0))
	state.actors[2] = ActorState.from_definition(definitions.get_actor(&"raider"), 2, &"enemies", Vector3(30, 1, 30))
	return state


static func _drop_nav(state: BattleState) -> FakeNavProvider:
	var nav := FakeNavProvider.new()
	var start := (state.actors[1] as ActorState).position
	nav.set_path(start, Vector3(4, 1, 0), PackedVector3Array([start, Vector3(1, 5, 0), Vector3(3, 1, 0), Vector3(4, 1, 0)]))
	nav.set_jump(Vector3(1, 5, 0), Vector3(3, 1, 0), DROP)
	return nav


static func _move(target: Vector3) -> Command:
	var move := Command.create(&"move", 1)
	move.target_pos = target
	return move


static func _test_safe_drop_costs_its_planar_distance(failures: Array[String]) -> void:
	var state := _ledge_battle(&"knight")
	var result := Resolver.resolve(state, _move(Vector3(4, 1, 0)), _drop_nav(state), FakeLosProvider.new())
	var jump := _event(result, &"jump_performed")
	_expect(jump != null and StringName(jump.data["kind"]) == DROP and is_equal_approx(float(jump.data["height"]), 4.0), "a ledge segment was not resolved as a 4 m drop", failures)
	_expect(jump != null and is_equal_approx(float(jump.data["movement_cost"]), 2.0), "a drop charged more than its horizontal distance", failures)
	_expect(not _has_event(result, &"fall_started"), "a Knight's 4 m drop should land safely", failures)
	_expect(is_equal_approx(_movement_spent(result), 4.0), "the move should spend 1 + 2 + 1 m of movement", failures)
	TestHelpers.apply_result(state, result)
	_expect((state.actors[1] as ActorState).position.is_equal_approx(Vector3(4, 1, 0)), "the mover did not continue walking after a safe landing", failures)


static func _test_hard_landing_hurts_knocks_prone_and_ends_the_move(failures: Array[String]) -> void:
	var state := _ledge_battle(&"archer")
	var result := Resolver.resolve(state, _move(Vector3(4, 1, 0)), _drop_nav(state), FakeLosProvider.new())
	var fall := _event(result, &"fall_started")
	_expect(fall != null and bool(fall.data.get("deliberate", false)) and bool(fall.data.get("prone", false)), "the Archer's 4 m drop did not narrate a deliberate, Prone-causing hard landing", failures)
	_expect(result.events.any(func(event: Event): return event.type == &"damage_taken" and event.data.get("damage_type") == &"fall" and int(event.data.get("source_actor_id", -1)) == 1), "a hard landing did not deal self-inflicted fall damage", failures)
	_expect(result.events.any(func(event: Event): return event.type == &"condition_added" and event.data.get("condition") == &"prone"), "a hard landing did not leave the jumper Prone", failures)
	var jump_index := result.events.find(_event(result, &"jump_performed"))
	_expect(not result.events.slice(jump_index).any(func(event: Event): return event.type == &"movement_segment"), "the move kept walking after a hard landing", failures)
	_expect(result.next_rng_state != state.rng_state, "fall damage dice did not advance the RNG", failures)
	TestHelpers.apply_result(state, result)
	var archer := state.actors[1] as ActorState
	_expect(archer.position.is_equal_approx(Vector3(3, 1, 0)) and archer.is_prone(), "the Archer should lie Prone where it landed", failures)


static func _test_climb_costs_its_rise_and_needs_a_run_up(failures: Array[String]) -> void:
	var state := _ledge_battle(&"knight")
	(state.actors[1] as ActorState).position = Vector3(0, 1, 0)
	var nav := FakeNavProvider.new()
	nav.set_path(Vector3(0, 1, 0), Vector3(4, 2.5, 0), PackedVector3Array([Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(3, 2.5, 0), Vector3(4, 2.5, 0)]))
	nav.set_jump(Vector3(1, 1, 0), Vector3(3, 2.5, 0), CLIMB)
	var result := Resolver.resolve(state, _move(Vector3(4, 2.5, 0)), nav, FakeLosProvider.new())
	var jump := _event(result, &"jump_performed")
	_expect(jump != null and StringName(jump.data["kind"]) == CLIMB and is_equal_approx(float(jump.data["movement_cost"]), 3.5), "a 1.5 m climb should cost 2 m across plus the 1.5 m rise", failures)
	_expect(jump != null and bool(jump.data["running"]), "a Knight's 1.5 m climb exceeds its standing High Jump, so it must be a running jump", failures)
	_expect(is_equal_approx(_movement_spent(result), 5.5), "the climb move should spend 1 + 3.5 + 1 m", failures)


static func _test_clamp_never_stops_mid_jump(failures: Array[String]) -> void:
	var state := _ledge_battle(&"knight")
	(state.actors[1] as ActorState).movement_remaining = 2.0
	var result := Resolver.resolve(state, _move(Vector3(4, 1, 0)), _drop_nav(state), FakeLosProvider.new())
	_expect(not _has_event(result, &"jump_performed"), "a jump was taken without the movement to finish it", failures)
	var segment := _event(result, &"movement_segment")
	_expect(segment != null and (segment.data["to"] as Vector3).is_equal_approx(Vector3(1, 5, 0)), "an unaffordable jump should leave the mover at its takeoff", failures)
	var clamped := _drop_nav(state).clamp_path(PackedVector3Array([Vector3(0, 5, 0), Vector3(1, 5, 0), Vector3(3, 1, 0), Vector3(4, 1, 0)]), 3.5)
	_expect(clamped.size() == 4 and clamped[3].is_equal_approx(Vector3(3.5, 1, 0)), "clamping should cross an affordable jump and stop partway along the next walk", failures)


static func _test_opportunity_attack_resolves_at_takeoff(failures: Array[String]) -> void:
	var state := _ledge_battle(&"knight")
	(state.actors[2] as ActorState).position = Vector3(1.5, 5, 0)
	TestHelpers.guarantee_hits(state.actors[2])
	var result := Resolver.resolve(state, _move(Vector3(4, 1, 0)), _drop_nav(state), FakeLosProvider.new())
	var reaction := result.events.find(_event(result, &"reaction_triggered"))
	var jump := result.events.find(_event(result, &"jump_performed"))
	_expect(reaction >= 0, "jumping out of an enemy's reach did not provoke an opportunity attack", failures)
	_expect(reaction >= 0 and (jump < 0 or reaction < jump), "the opportunity attack did not resolve before the jump left the ledge", failures)


static func _test_exploration_hard_landing_skips_prone(failures: Array[String]) -> void:
	var state := _ledge_battle(&"archer", &"exploration")
	var result := Resolver.resolve(state, _move(Vector3(4, 1, 0)), _drop_nav(state), FakeLosProvider.new())
	var fall := _event(result, &"fall_started")
	_expect(fall != null and not bool(fall.data.get("prone", true)), "an exploration hard landing should say no Prone follows", failures)
	_expect(_has_event(result, &"damage_taken") and not result.events.any(func(event: Event): return event.type == &"condition_added"), "an exploration hard landing should hurt but not apply Prone", failures)
	_expect(not _has_event(result, &"movement_spent"), "exploration movement charged a budget", failures)


static func _test_push_fall_leaves_the_target_prone(failures: Array[String]) -> void:
	var definitions := DefinitionLibrary.get_default()
	var state := BattleState.new()
	state.phase = &"combat"
	state.rng_state = 42
	state.initiative_order = [1, 2]
	state.active_combatant_ids = [1, 2]
	state.actors[1] = ActorState.from_definition(definitions.get_actor(&"knight"), 1, &"heroes", Vector3.ZERO)
	state.actors[2] = ActorState.from_definition(definitions.get_actor(&"raider"), 2, &"enemies", Vector3.RIGHT)
	(state.actors[1] as ActorState).strength = 30
	(state.actors[2] as ActorState).strength = 1
	(state.actors[2] as ActorState).dexterity = 1
	var push := Command.create(&"shove", 1)
	push.target_id = 2
	push.metadata["mode"] = &"push"
	var nav := FakeNavProvider.new()
	nav.set_push_result(Vector3.RIGHT, Vector3.RIGHT, 3.0, {"landing_position": Vector3(4, -4, 0), "blocked": false, "fell": true, "fall_distance": 4.0})
	var result := Resolver.resolve(state, push, nav, FakeLosProvider.new())
	var fall := _event(result, &"fall_started")
	_expect(fall != null and not bool(fall.data.get("deliberate", true)), "a Shove fall should be narrated as involuntary", failures)
	_expect(result.events.any(func(event: Event): return event.type == &"condition_added" and event.data.get("condition") == &"prone" and int(event.data.get("actor_id", -1)) == 2), "SRD Falling: a damaging Shove fall should leave the target Prone", failures)


static func _test_move_routes_with_the_movers_strength(failures: Array[String]) -> void:
	var state := _ledge_battle(&"archer")
	var nav := _drop_nav(state)
	Resolver.resolve(state, _move(Vector3(4, 1, 0)), nav, FakeLosProvider.new())
	_expect(nav.jumper_strengths.size() == 1 and nav.jumper_strengths[0] == 10, "the move did not route through the Archer's Strength-scoped navigation", failures)


static func _jump_command(target: Vector3) -> Command:
	var jump := Command.create(&"jump", 1)
	jump.target_pos = target
	return jump


static func _test_jump_action_needs_a_run_up_for_full_distance(failures: Array[String]) -> void:
	var state := _ledge_battle(&"knight")
	var knight := state.actors[1] as ActorState
	knight.position = Vector3(0, 1, 0)
	var standing := Resolver.resolve(state, _jump_command(Vector3(2.5, 1, 0)), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_reason(standing) == &"jump_too_far", "a Knight's standing Long Jump (2.1 m) should not reach 2.5 m", failures)
	knight.run_up_m = 3.0
	var running := Resolver.resolve(state, _jump_command(Vector3(2.5, 1, 0)), FakeNavProvider.new(), FakeLosProvider.new())
	var jump := _event(running, &"jump_performed")
	_expect(jump != null and StringName(jump.data["kind"]) == JumpRules.LEAP and bool(jump.data["running"]), "after a 3 m run-up the Knight should leap 2.5 m", failures)
	_expect(is_equal_approx(_movement_spent(running), 2.5) and not _has_event(running, &"action_spent"), "a Jump should cost its distance in movement and never an action", failures)
	var too_far := Resolver.resolve(state, _jump_command(Vector3(4.5, 1, 0)), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_reason(too_far) == &"jump_too_far", "even running, the Knight's Long Jump stops at 4.2 m", failures)
	knight.movement_remaining = 2.0
	_expect(_reason(Resolver.resolve(state, _jump_command(Vector3(2.5, 1, 0)), FakeNavProvider.new(), FakeLosProvider.new())) == &"insufficient_movement", "a Jump needs the movement to pay for it", failures)


static func _test_jump_action_climbs_and_drops(failures: Array[String]) -> void:
	var state := _ledge_battle(&"knight")
	var knight := state.actors[1] as ActorState
	knight.position = Vector3(0, 1, 0)
	_expect(_reason(Resolver.resolve(state, _jump_command(Vector3(1.5, 2.2, 0)), FakeNavProvider.new(), FakeLosProvider.new())) == &"jump_too_high", "a standing Knight should not jump up 1.2 m", failures)
	knight.run_up_m = 3.0
	var climb := Resolver.resolve(state, _jump_command(Vector3(1.5, 2.2, 0)), FakeNavProvider.new(), FakeLosProvider.new())
	var up := _event(climb, &"jump_performed")
	_expect(up != null and StringName(up.data["kind"]) == JumpRules.CLIMB and is_equal_approx(float(up.data["movement_cost"]), 2.7), "a running Knight should jump up 1.2 m for 1.5 + 1.2 m of movement", failures)
	var archer_state := _ledge_battle(&"archer")
	var drop := Resolver.resolve(archer_state, _jump_command(Vector3(1.0, 0.8, 0)), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_has_event(drop, &"fall_started") and drop.events.any(func(event: Event): return event.type == &"condition_added" and event.data.get("condition") == &"prone"), "the Archer jumping off a 4.2 m ledge should land hard and Prone", failures)


static func _test_jump_action_needs_somewhere_to_land(failures: Array[String]) -> void:
	var state := _ledge_battle(&"knight")
	var nav := FakeNavProvider.new()
	nav.blocked_destinations.append(Vector3(1, 5, 0))
	_expect(_reason(Resolver.resolve(state, _jump_command(Vector3(1, 5, 0)), nav, FakeLosProvider.new())) == &"no_landing", "a Jump onto unwalkable ground should be rejected", failures)
	var walled := FakeLosProvider.new()
	walled.block(Vector3(0, 5, 0), Vector3(1, 5, 0))
	_expect(_reason(Resolver.resolve(state, _jump_command(Vector3(1, 5, 0)), FakeNavProvider.new(), walled)) == &"no_line_of_sight", "a Jump through a wall should be rejected", failures)


static func _test_run_up_is_movement_immediately_before(failures: Array[String]) -> void:
	var state := _ledge_battle(&"knight")
	var knight := state.actors[1] as ActorState
	Resolver.apply(state, Event.create(&"movement_segment", {"actor_id": 1, "from": knight.position, "to": Vector3(2, 5, 0), "path": PackedVector3Array([knight.position, Vector3(2, 5, 0)])}))
	Resolver.apply(state, Event.create(&"movement_segment", {"actor_id": 1, "from": Vector3(2, 5, 0), "to": Vector3(3, 5, 0), "path": PackedVector3Array([Vector3(2, 5, 0), Vector3(3, 5, 0)])}))
	_expect(is_equal_approx(knight.run_up_m, 3.0), "consecutive walking should add up to a 3 m run-up", failures)
	Resolver.apply(state, Event.create(&"action_spent", {"actor_id": 1, "action": &"dodge"}))
	_expect(is_zero_approx(knight.run_up_m), "stopping to act should break the run-up", failures)
	knight.run_up_m = 4.0
	Resolver.apply(state, Event.create(&"jump_performed", {"actor_id": 1, "from": knight.position, "to": Vector3(4, 5, 0)}))
	_expect(is_zero_approx(knight.run_up_m), "a jump should need a fresh run-up after it", failures)
	knight.run_up_m = 2.5
	_expect(is_equal_approx(knight.clone().run_up_m, 2.5) and is_equal_approx(ActorState.from_dict(knight.to_dict()).run_up_m, 2.5), "run_up_m should survive clone and save round-trips", failures)


static func _test_jump_action_outside_combat_is_free(failures: Array[String]) -> void:
	var state := _ledge_battle(&"knight", &"exploration")
	(state.actors[1] as ActorState).position = Vector3(0, 1, 0)
	var result := Resolver.resolve(state, _jump_command(Vector3(2.0, 1, 0)), FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_has_event(result, &"jump_performed") and not _has_event(result, &"movement_spent"), "a Jump outside combat should resolve without spending movement", failures)


static func _test_shove_opens_combat_from_exploration(failures: Array[String]) -> void:
	var state := _ledge_battle(&"knight", &"exploration")
	(state.actors[2] as ActorState).position = Vector3(1, 5, 0)
	var shove := Command.create(&"shove", 1)
	shove.target_id = 2
	shove.metadata = {"mode": &"prone", "encounter_id": "camp", "participant_actor_ids": [1, 2]}
	var result := Resolver.resolve(state, shove, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(_has_event(result, &"combat_started") and _has_event(result, &"d20_test_rolled"), "a Shove outside combat should open the fight and then resolve", failures)


static func _reason(result: ResolutionResult) -> StringName:
	var rejection := _event(result, &"command_rejected")
	return StringName(str(rejection.data.get("reason", ""))) if rejection != null else &""


static func _movement_spent(result: ResolutionResult) -> float:
	var total := 0.0
	for event in result.events:
		if event.type == &"movement_spent":
			total += float(event.data["amount"])
	return total


static func _event(result: ResolutionResult, type: StringName) -> Event:
	for event in result.events:
		if event.type == type:
			return event
	return null


static func _has_event(result: ResolutionResult, type: StringName) -> bool:
	return _event(result, type) != null


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
