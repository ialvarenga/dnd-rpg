class_name TestEnemyAI
extends RefCounted

static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_legal_command_enumeration(failures)
	_test_choice_is_deterministic_and_replayable(failures)
	_test_choice_does_not_depend_on_future_rolls(failures)
	_test_query_budget_enforcement(failures)
	_test_attack_selection(failures)
	_test_attack_scoring_reads_roll_mode(failures)
	_test_repeated_line_of_sight_query_spends_budget_once(failures)
	_test_approach_selection(failures)
	_test_formation_spacing(failures)
	_test_avoids_obvious_opportunity_attack(failures)
	_test_dodge_is_not_default_idle_action(failures)
	_test_rejected_candidates_are_not_selected(failures)
	_test_incremental_turn_decisions(failures)
	_test_a5_invariants_survive_ai_evaluation(failures)
	return {"name": "unit/test_enemy_ai", "failures": failures}


static func _test_legal_command_enumeration(failures: Array[String]) -> void:
	var state := _enemy_turn_state(8.0)
	var ai := EnemyAI.new()
	var commands := ai.enumerate_legal_commands(state, 2, FakeNavProvider.new(), FakeLosProvider.new(), AIQueryBudget.new(6, 8))
	_expect(not commands.is_empty(), "AI did not enumerate commands for a conscious current enemy", failures)
	var has_move := false
	var has_end_turn := false
	for command in commands:
		var resolved := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
		_expect(resolved.events[0].type != &"command_rejected", "AI enumerated a rejected command", failures)
		has_move = has_move or command.type == &"move"
		has_end_turn = has_end_turn or command.type == &"end_turn"
	_expect(has_move and has_end_turn, "AI legal enumeration omitted useful approach or end turn", failures)


static func _test_choice_is_deterministic_and_replayable(failures: Array[String]) -> void:
	var first := _run_ai_turn(42)
	var second := _run_ai_turn(42)
	_expect(first == second, "same snapshot and budget produced a different AI replay", failures)


## Candidate resolution still uses the authoritative Resolver for legality, but
## scoring must not read the speculative attack result. Changing only the next
## RNG state therefore cannot change the selected command.
static func _test_choice_does_not_depend_on_future_rolls(failures: Array[String]) -> void:
	var first := _enemy_turn_state(1.0)
	var second := first.clone()
	var alternate_target := ActorState.new()
	alternate_target.id = 3
	alternate_target.side = &"heroes"
	alternate_target.position = Vector3(1.2, 0.0, 0.0)
	alternate_target.hp = 20
	alternate_target.max_hp = 20
	first.actors[alternate_target.id] = alternate_target
	second.actors[alternate_target.id] = alternate_target.clone()
	first.rng_state = 1
	second.rng_state = 987654321
	var ai := EnemyAI.new()
	var first_command := ai.choose_command(first, 2, FakeNavProvider.new(), FakeLosProvider.new(), AIQueryBudget.new())
	var second_command := ai.choose_command(second, 2, FakeNavProvider.new(), FakeLosProvider.new(), AIQueryBudget.new())
	_expect(first_command != null and second_command != null, "AI did not produce commands for RNG-independence fixture", failures)
	if first_command != null and second_command != null:
		_expect(first_command.to_dict() == second_command.to_dict(), "AI selected a different command when only the future RNG state changed", failures)


static func _test_query_budget_enforcement(failures: Array[String]) -> void:
	var state := _enemy_turn_state(8.0)
	var budget := AIQueryBudget.new(1, 0)
	var commands := EnemyAI.new().enumerate_legal_commands(state, 2, FakeNavProvider.new(), FakeLosProvider.new(), budget)
	_expect(budget.navigation_queries <= 1 and budget.line_of_sight_queries <= 0, "AI exceeded its query budget", failures)
	_expect(budget.navigation_denials > 0, "AI did not record a refused speculative navigation query", failures)
	_expect(commands.size() == 1 and commands[0].type == &"end_turn", "AI selected an incomplete navigation candidate after budget exhaustion", failures)


static func _test_attack_selection(failures: Array[String]) -> void:
	var state := _enemy_turn_state(1.0)
	var command := EnemyAI.new().choose_command(state, 2, FakeNavProvider.new(), FakeLosProvider.new(), AIQueryBudget.new())
	_expect(command != null and command.type == &"basic_attack" and command.target_id == 1, "AI did not attack a legal adjacent enemy", failures)


## Two identical adjacent heroes tie, and the tie goes to the lower id. A
## Dodging hero imposes Disadvantage through AttackMath, so the AI switches.
static func _test_attack_scoring_reads_roll_mode(failures: Array[String]) -> void:
	var state := _enemy_turn_state(1.0)
	var twin := (state.actors[1] as ActorState).clone()
	twin.id = 3
	twin.position = Vector3(1.0, 0.0, 1.0)
	state.actors[twin.id] = twin
	var ai := EnemyAI.new()
	var untouched := ai.choose_command(state, 2, FakeNavProvider.new(), FakeLosProvider.new(), AIQueryBudget.new())
	_expect(untouched != null and untouched.type == &"basic_attack" and untouched.target_id == 1, "identical targets should tie toward the lower actor id", failures)
	(state.actors[1] as ActorState).add_condition(&"dodging")
	var dodged := ai.choose_command(state, 2, FakeNavProvider.new(), FakeLosProvider.new(), AIQueryBudget.new())
	_expect(dodged != null and dodged.type == &"basic_attack" and dodged.target_id == twin.id, "AI should prefer the target it can attack without Disadvantage", failures)


static func _test_repeated_line_of_sight_query_spends_budget_once(failures: Array[String]) -> void:
	var budget := AIQueryBudget.new(0, 1)
	var fake := FakeLosProvider.new()
	fake.set_cover(Vector3.ZERO, Vector3.RIGHT, LosProvider.COVER_HALF)
	var los := BudgetedLosProvider.new(fake, budget)
	var first := los.cover_between(Vector3.ZERO, Vector3.RIGHT)
	var repeated := los.cover_between(Vector3.ZERO, Vector3.RIGHT)
	_expect(first == LosProvider.COVER_HALF and repeated == first and los.has_line_of_sight(Vector3.ZERO, Vector3.RIGHT), "a repeated query should return the remembered answer", failures)
	_expect(budget.line_of_sight_queries == 1 and budget.line_of_sight_denials == 0, "a repeated query should spend the budget only once", failures)
	_expect(los.cover_between(Vector3.ZERO, Vector3.LEFT) == LosProvider.COVER_TOTAL and los.cover_between(Vector3.ZERO, Vector3.LEFT) == LosProvider.COVER_TOTAL, "a query past the budget should read as blocked", failures)
	_expect(budget.line_of_sight_denials == 2, "denials should never be remembered as answers", failures)


static func _test_approach_selection(failures: Array[String]) -> void:
	var state := _enemy_turn_state(10.0)
	var command := EnemyAI.new().choose_command(state, 2, FakeNavProvider.new(), FakeLosProvider.new(), AIQueryBudget.new())
	_expect(command != null and command.type == &"move", "AI did not approach an out-of-range target", failures)
	if command != null and command.type == &"move":
		_expect(command.target_pos.distance_to((state.actors[1] as ActorState).position) < (state.actors[2] as ActorState).position.distance_to((state.actors[1] as ActorState).position), "AI approach destination did not reduce target distance", failures)
		_expect(is_equal_approx(command.target_pos.distance_to((state.actors[1] as ActorState).position), EnemyAI.ATTACK_RANGE_METERS), "AI did not preserve the configured combat standoff distance", failures)


static func _test_formation_spacing(failures: Array[String]) -> void:
	var state := _enemy_turn_state(8.0)
	var ally := ActorState.new()
	ally.id = 3
	ally.side = &"enemies"
	ally.position = Vector3(EnemyAI.ATTACK_RANGE_METERS, 0.0, 0.0)
	ally.hp = 10
	ally.max_hp = 10
	state.actors[ally.id] = ally
	var command := EnemyAI.new().choose_command(state, 2, FakeNavProvider.new(), FakeLosProvider.new(), AIQueryBudget.new())
	_expect(command != null and command.type == &"move", "AI did not reposition away from an occupied attack slot", failures)
	if command != null and command.type == &"move":
		_expect(command.target_pos.distance_to(ally.position) >= EnemyAI.FORMATION_SEPARATION_METERS, "AI chose an overlapping enemy formation position", failures)


static func _test_avoids_obvious_opportunity_attack(failures: Array[String]) -> void:
	var state := _enemy_turn_state(0.0)
	var close_hero: ActorState = state.actors[1]
	close_hero.position = Vector3(1.0, 0.0, 0.0)
	TestHelpers.guarantee_hits(close_hero)
	TestHelpers.set_fixed_damage(close_hero, 100)
	var distant_hero := ActorState.new()
	distant_hero.id = 3
	distant_hero.side = &"heroes"
	distant_hero.position = Vector3(8.0, 0.0, 0.0)
	distant_hero.hp = 20
	distant_hero.max_hp = 20
	state.actors[distant_hero.id] = distant_hero
	state.initiative_order = [2, 1, 3]
	(state.actors[2] as ActorState).action_available = false
	var command := EnemyAI.new().choose_command(state, 2, FakeNavProvider.new(), FakeLosProvider.new(), AIQueryBudget.new())
	_expect(command != null and command.type == &"end_turn", "AI chose an obvious lethal opportunity-attack route over ending safely", failures)


static func _test_dodge_is_not_default_idle_action(failures: Array[String]) -> void:
	var state := _enemy_turn_state(8.0)
	var enemy: ActorState = state.actors[2]
	enemy.ability_ids = [&"basic_attack", &"dodge"]
	enemy.movement_remaining = 0.0
	var command := EnemyAI.new().choose_command(state, enemy.id, FakeNavProvider.new(), FakeLosProvider.new(), AIQueryBudget.new())
	_expect(command != null and command.type == &"end_turn", "full-health enemy used Dodge without an immediate threat", failures)


static func _test_rejected_candidates_are_not_selected(failures: Array[String]) -> void:
	var state := _enemy_turn_state(8.0)
	var nav := FakeNavProvider.new()
	var enemy: ActorState = state.actors[2]
	var hero: ActorState = state.actors[1]
	var blocked_destination := enemy.position + enemy.position.direction_to(hero.position) * minf(enemy.movement_remaining, enemy.position.distance_to(hero.position) - EnemyAI.ATTACK_RANGE_METERS)
	nav.blocked_destinations.append(blocked_destination)
	var command := EnemyAI.new().choose_command(state, 2, nav, FakeLosProvider.new(), AIQueryBudget.new())
	_expect(command != null and command.type == &"end_turn", "AI selected a candidate the resolver rejected", failures)


static func _test_incremental_turn_decisions(failures: Array[String]) -> void:
	var state := _enemy_turn_state(10.0)
	var ai := EnemyAI.new()
	var budget := AIQueryBudget.new(8, 8)
	var first := ai.choose_command(state, 2, FakeNavProvider.new(), FakeLosProvider.new(), budget)
	_expect(first != null and first.type == &"move", "AI did not make the first incremental approach decision", failures)
	if first == null:
		return
	TestHelpers.apply_result(state, Resolver.resolve(state, first, FakeNavProvider.new(), FakeLosProvider.new()))
	var second := ai.choose_command(state, 2, FakeNavProvider.new(), FakeLosProvider.new(), budget)
	_expect(second != null and second.type == &"basic_attack", "AI did not reconsider and attack after movement applied", failures)
	if second == null:
		return
	TestHelpers.apply_result(state, Resolver.resolve(state, second, FakeNavProvider.new(), FakeLosProvider.new()))
	var third := ai.choose_command(state, 2, FakeNavProvider.new(), FakeLosProvider.new(), budget)
	_expect(third != null and third.type == &"end_turn", "AI did not end the turn after spending useful resources", failures)


static func _test_a5_invariants_survive_ai_evaluation(failures: Array[String]) -> void:
	var state := _enemy_turn_state(8.0)
	var before_hash := JSON.stringify(state.stable_snapshot()).md5_text()
	var command := EnemyAI.new().choose_command(state, 2, FakeNavProvider.new(), FakeLosProvider.new(), AIQueryBudget.new())
	_expect(JSON.stringify(state.stable_snapshot()).md5_text() == before_hash, "AI evaluation mutated its BattleState snapshot", failures)
	_expect(command != null and command.type == &"move", "AI regression fixture did not choose movement", failures)
	if command == null:
		return
	var result := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
	TestHelpers.apply_result(state, result)
	var actor: ActorState = state.actors[2]
	_expect(actor.action_available and actor.movement_remaining < actor.movement_speed, "AI movement bypassed A5 action economy or movement spending", failures)


static func _enemy_turn_state(enemy_x: float) -> BattleState:
	var state := TestHelpers.make_battle(42)
	state.initiative_order = [2, 1]
	state.current_turn_index = 0
	var enemy: ActorState = state.actors[2]
	enemy.position = Vector3(enemy_x, 0.0, 0.0)
	return state


static func _run_ai_turn(seed: int) -> String:
	var state := _enemy_turn_state(10.0)
	state.rng_seed = seed
	state.rng_state = seed
	var ai := EnemyAI.new()
	var budget := AIQueryBudget.new(8, 8)
	var log: Array[String] = []
	for _step in range(3):
		var command := ai.choose_command(state, 2, FakeNavProvider.new(), FakeLosProvider.new(), budget)
		if command == null:
			break
		var result := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
		log.append("%s:%s" % [command.type, TestHelpers.event_log_entry(result)])
		TestHelpers.apply_result(state, result)
		if command.type == &"end_turn":
			break
	return "\n".join(log).md5_text()


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
