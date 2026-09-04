class_name EnemyAI
extends RefCounted

## Utility AI over the authoritative command pipeline. It receives a BattleState
## snapshot and returns one Command; callers resolve/apply that command before
## asking again, which keeps every decision incremental and replayable.

const ResolverRules = preload("res://sim/resolver.gd")
const ATTACK_RANGE_METERS := 1.5
const MAX_TARGET_CANDIDATES := 2
const SCORE_EPSILON := 0.001


func choose_command(snapshot: BattleState, actor_id: int, nav: NavProvider, los: LosProvider, budget: AIQueryBudget = null) -> Command:
	var evaluated := _evaluate_candidates(snapshot, actor_id, nav, los, _ensure_budget(budget))
	if evaluated.is_empty():
		return null
	var best: Dictionary = evaluated[0]
	for candidate in evaluated.slice(1):
		if float(candidate["score"]) > float(best["score"]) + SCORE_EPSILON:
			best = candidate
	return best["command"] as Command


func enumerate_legal_commands(snapshot: BattleState, actor_id: int, nav: NavProvider, los: LosProvider, budget: AIQueryBudget = null) -> Array[Command]:
	var commands: Array[Command] = []
	for candidate in _evaluate_candidates(snapshot, actor_id, nav, los, _ensure_budget(budget)):
		commands.append(candidate["command"])
	return commands


func _evaluate_candidates(snapshot: BattleState, actor_id: int, nav: NavProvider, los: LosProvider, budget: AIQueryBudget) -> Array[Dictionary]:
	if snapshot.phase != &"combat" or snapshot.current_actor_id() != actor_id or not snapshot.actors.has(actor_id):
		return []
	var actor: ActorState = snapshot.actors[actor_id]
	if not actor.is_conscious():
		return []
	var targets := _prioritized_targets(snapshot, actor)
	var candidate_commands := _candidate_commands(actor, targets)
	var evaluations: Array[Dictionary] = []
	var bounded_nav := BudgetedNavProvider.new(nav, budget)
	var bounded_los := BudgetedLosProvider.new(los, budget)
	for command in candidate_commands:
		var nav_denials_before := budget.navigation_denials
		var los_denials_before := budget.line_of_sight_denials
		var result := ResolverRules.resolve(snapshot, command, bounded_nav, bounded_los)
		# Do not select a command whose legality/risk check was only partial.
		if budget.navigation_denials != nav_denials_before or budget.line_of_sight_denials != los_denials_before:
			continue
		if not _is_accepted(result):
			continue
		var resulting_state := snapshot.clone()
		_apply_result(resulting_state, result)
		evaluations.append({
			"command": command,
			"result": result,
			"score": _score(snapshot, resulting_state, actor, command, result),
		})
	return evaluations


func _candidate_commands(actor: ActorState, targets: Array[ActorState]) -> Array[Command]:
	var commands: Array[Command] = []
	if actor.action_available:
		for target in targets:
			if actor.position.distance_to(target.position) <= ATTACK_RANGE_METERS + SCORE_EPSILON:
				var attack := Command.create(&"basic_attack", actor.id)
				attack.target_id = target.id
				commands.append(attack)
	for target in targets:
		var destination: Variant = _useful_approach_destination(actor, target)
		if destination != null:
			var move := Command.create(&"move", actor.id)
			move.target_pos = destination
			move.target_id = target.id
			commands.append(move)
	commands.append(Command.create(&"end_turn", actor.id))
	return commands


func _prioritized_targets(snapshot: BattleState, actor: ActorState) -> Array[ActorState]:
	var targets: Array[ActorState] = []
	for actor_id_variant in snapshot.actors.keys():
		var target: ActorState = snapshot.actors[actor_id_variant]
		if target.side != actor.side and target.is_alive():
			targets.append(target)
	targets.sort_custom(func(a: ActorState, b: ActorState) -> bool:
		var a_distance := actor.position.distance_to(a.position)
		var b_distance := actor.position.distance_to(b.position)
		return a.id < b.id if is_equal_approx(a_distance, b_distance) else a_distance < b_distance
	)
	var limited: Array[ActorState] = []
	for index in range(mini(MAX_TARGET_CANDIDATES, targets.size())):
		limited.append(targets[index])
	return limited


func _useful_approach_destination(actor: ActorState, target: ActorState) -> Variant:
	if actor.movement_remaining <= SCORE_EPSILON:
		return null
	var distance := actor.position.distance_to(target.position)
	if distance <= ATTACK_RANGE_METERS + SCORE_EPSILON:
		return null
	var direction := actor.position.direction_to(target.position)
	var desired_distance := maxf(0.0, distance - ATTACK_RANGE_METERS * 0.9)
	var step := minf(actor.movement_remaining, desired_distance)
	if step <= SCORE_EPSILON:
		return null
	return actor.position + direction * step


func _score(before: BattleState, after: BattleState, actor: ActorState, command: Command, result: ResolutionResult) -> float:
	var score := 0.0
	match command.type:
		&"basic_attack", &"attack":
			var target: ActorState = before.actors[command.target_id]
			score += 1000.0 + _expected_damage(actor, target) * 10.0
			var resulting_target: ActorState = after.actors[command.target_id]
			score += float(target.hp - resulting_target.hp) * 10.0
			if not resulting_target.is_alive():
				score += 10000.0
		&"move":
			score += _nearest_enemy_distance(before, actor) * 100.0
			score -= _nearest_enemy_distance(after, after.actors[actor.id]) * 100.0
			if (after.actors[actor.id] as ActorState).action_available:
				score += 25.0
		&"end_turn": score = 0.0
	for event in result.events:
		if event.type == &"reaction_triggered" and int(event.data.get("target_id", -1)) == actor.id:
			score -= 10000.0
		elif event.type == &"damage_taken" and int(event.data.get("actor_id", -1)) == actor.id:
			score -= float(event.data["amount"]) * 200.0
		elif (event.type == &"actor_downed" or event.type == &"actor_died") and int(event.data.get("actor_id", -1)) == actor.id:
			score -= 1000000.0
	return score


func _expected_damage(attacker: ActorState, target: ActorState) -> float:
	var hit_faces := clampi(21 - target.armor_class + attacker.attack_bonus, 1, 19)
	var hit_chance := float(hit_faces) / 20.0
	var average_damage := (float(attacker.damage_die) + 1.0) * 0.5 + attacker.damage_modifier
	return maxf(1.0, average_damage) * hit_chance


func _nearest_enemy_distance(state: BattleState, actor: ActorState) -> float:
	var nearest := INF
	for actor_id_variant in state.actors.keys():
		var other: ActorState = state.actors[actor_id_variant]
		if other.side != actor.side and other.is_alive():
			nearest = minf(nearest, actor.position.distance_to(other.position))
	return 0.0 if is_inf(nearest) else nearest


func _is_accepted(result: ResolutionResult) -> bool:
	return not result.events.is_empty() and result.events[0].type != &"command_rejected"


func _apply_result(state: BattleState, result: ResolutionResult) -> void:
	for event in result.events:
		ResolverRules.apply(state, event)
	state.rng_state = result.next_rng_state


func _ensure_budget(budget: AIQueryBudget) -> AIQueryBudget:
	return budget if budget != null else AIQueryBudget.new()
