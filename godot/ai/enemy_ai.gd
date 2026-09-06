class_name EnemyAI
extends RefCounted

## Utility AI over the authoritative command pipeline. It receives a BattleState
## snapshot and returns one Command; callers resolve/apply that command before
## asking again, which keeps every decision incremental and replayable.

const ResolverRules = preload("res://sim/resolver.gd")
const EquipmentRules = preload("res://sim/equipment.gd")
## Keep combatants far enough apart that their silhouettes and attack motion
## remain readable. This matches basic_attack.tres's presentation-friendly
## attack range; a future animation can bridge the visible gap.
const ATTACK_RANGE_METERS := 2.4
## CharacterBody3D capsules have a 0.45 m radius. Leave a visible gap between
## allies so their models never occupy the same staging position.
const FORMATION_SEPARATION_METERS := 1.2
const FORMATION_ANGLES := [0.0, 45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0]
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
	var candidate_commands := _candidate_commands(snapshot, actor, targets)
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


func _candidate_commands(snapshot: BattleState, actor: ActorState, targets: Array[ActorState]) -> Array[Command]:
	var commands: Array[Command] = []
	if actor.action_available:
		for target in targets:
			if actor.position.distance_to(target.position) <= ATTACK_RANGE_METERS + SCORE_EPSILON and _has_formation_space(snapshot, actor):
				var attack := Command.create(&"basic_attack", actor.id)
				attack.target_id = target.id
				commands.append(attack)
	for target in targets:
		var destination: Variant = _useful_approach_destination(snapshot, actor, target)
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


func _useful_approach_destination(snapshot: BattleState, actor: ActorState, target: ActorState) -> Variant:
	if actor.movement_remaining <= SCORE_EPSILON:
		return null
	var distance := actor.position.distance_to(target.position)
	if distance <= ATTACK_RANGE_METERS + SCORE_EPSILON and _has_formation_space(snapshot, actor):
		return null
	var desired_position := _formation_position(snapshot, actor, target)
	var direction := actor.position.direction_to(desired_position)
	var step := minf(actor.movement_remaining, actor.position.distance_to(desired_position))
	if step <= SCORE_EPSILON:
		return null
	return actor.position + direction * step


func _formation_position(snapshot: BattleState, actor: ActorState, target: ActorState) -> Vector3:
	var outward := actor.position - target.position
	outward.y = 0.0
	if outward.length_squared() <= SCORE_EPSILON:
		outward = Vector3.FORWARD
	else:
		outward = outward.normalized()
	var best_position := target.position + outward * ATTACK_RANGE_METERS
	best_position.y = actor.position.y
	var best_clearance := -INF
	var best_travel := INF
	var found_clear_slot := false
	for angle in FORMATION_ANGLES:
		var candidate := target.position + outward.rotated(Vector3.UP, deg_to_rad(angle)) * ATTACK_RANGE_METERS
		candidate.y = actor.position.y
		var clearance := _nearest_ally_distance(snapshot, actor, candidate)
		var travel := actor.position.distance_to(candidate)
		var is_clear := clearance + SCORE_EPSILON >= FORMATION_SEPARATION_METERS
		if (is_clear and (not found_clear_slot or travel < best_travel)) or (not found_clear_slot and not is_clear and (clearance > best_clearance + SCORE_EPSILON or (is_equal_approx(clearance, best_clearance) and travel < best_travel))):
			best_position = candidate
			best_clearance = clearance
			best_travel = travel
			found_clear_slot = is_clear
	return best_position


func _has_formation_space(snapshot: BattleState, actor: ActorState) -> bool:
	return _nearest_ally_distance(snapshot, actor, actor.position) + SCORE_EPSILON >= FORMATION_SEPARATION_METERS


func _nearest_ally_distance(snapshot: BattleState, actor: ActorState, position: Vector3) -> float:
	var nearest := INF
	for other_id in snapshot.actors:
		var other: ActorState = snapshot.actors[other_id]
		if other.id != actor.id and other.side == actor.side and other.is_alive():
			nearest = minf(nearest, _planar_distance(position, other.position))
	return nearest


func _planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


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


## Reads through Equipment (sim/equipment.gd), the same way Resolver's attack
## resolution does, so scoring reflects an actor's actual equipped weapon/
## armor instead of only their unarmed/unarmored base stats. An actor with no
## equipment aggregates back to exactly its base fields.
func _expected_damage(attacker: ActorState, target: ActorState) -> float:
	var definitions := DefinitionLibrary.get_default()
	var attack_bonus := EquipmentRules.aggregate_attack_bonus(attacker, definitions)
	var armor_class := EquipmentRules.aggregate_armor_class(target, definitions)
	var damage_die := EquipmentRules.aggregate_damage_die(attacker, definitions)
	var damage_modifier := EquipmentRules.aggregate_damage_modifier(attacker, definitions)
	var hit_faces := clampi(21 - armor_class + attack_bonus, 1, 19)
	var hit_chance := float(hit_faces) / 20.0
	var average_damage := (float(damage_die) + 1.0) * 0.5 + damage_modifier
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
