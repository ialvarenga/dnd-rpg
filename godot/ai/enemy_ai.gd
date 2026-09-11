class_name EnemyAI
extends RefCounted

## Utility AI over the authoritative command pipeline. It receives a BattleState
## snapshot and returns one Command; callers resolve/apply that command before
## asking again, which keeps every decision incremental and replayable.

const ResolverRules = preload("res://sim/resolver.gd")
const EquipmentRules = preload("res://sim/equipment.gd")
const AttackMathRules = preload("res://sim/rules/attack_math.gd")
## SRD melee reach is 5 feet, represented as 1.5 m in the simulation. The
## resolver, targeting previews, and AI all use this same authored distance.
const ATTACK_RANGE_METERS := 1.5
const MINIMUM_RANGED_STANDOFF_METERS := 6.0
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
		if not _is_accepted(result):
			continue
		# Resolution above establishes legality only. Its dice events must never
		# influence scoring: otherwise the AI can select the action that happens
		# to succeed against the current RNG state before it commits to it.
		var score := _score(snapshot, actor, command, result, bounded_los)
		# Do not select a command whose legality/risk check or scoring cover read
		# was only partial.
		if budget.navigation_denials != nav_denials_before or budget.line_of_sight_denials != los_denials_before:
			continue
		evaluations.append({"command": command, "result": result, "score": score})
	return evaluations


func _candidate_commands(snapshot: BattleState, actor: ActorState, targets: Array[ActorState]) -> Array[Command]:
	var commands: Array[Command] = []
	# Candidate generation is deliberately permissive; Resolver validates the
	# actual inventory/costs for every candidate before it can be selected.
	var definitions := DefinitionLibrary.get_default()
	var ability_ids := ActionAvailability.effective_ability_ids(actor, definitions)
	if ability_ids.is_empty():
		ability_ids.append(&"basic_attack")
	for ability_id in ability_ids:
		var ability := DefinitionLibrary.get_default().get_ability(ability_id)
		if ability != null and _has_heal_effect(ability):
			commands.append(Command.create(ability_id, actor.id))
		elif ability != null and ability.targeting == &"none" and ability_id in [&"dodge", &"dash", &"disengage"]:
			commands.append(Command.create(ability_id, actor.id))
	for ability_id in ability_ids:
		var ability := definitions.get_ability(ability_id)
		if ability == null or not _has_attack_effect(ability):
			continue
		var attack_range := AbilityTargeting.attack_range(definitions, ability_id)
		var is_ranged := _ability_is_ranged(ability) or EquipmentRules.is_ranged_weapon(actor, definitions)
		var ability_targets := _prioritized_targets(snapshot, actor, ability)
		for target in ability_targets:
			if actor.position.distance_to(target.position) <= attack_range + SCORE_EPSILON and (is_ranged or _has_formation_space(snapshot, actor)):
				var attack := Command.create(ability_id, actor.id)
				attack.target_id = target.id
				commands.append(attack)
	for ability_id in ability_ids:
		var ability := definitions.get_ability(ability_id)
		if ability == null or ability.targeting != &"actor" or not _has_next_attack_condition_effect(ability, definitions):
			continue
		for target in _prioritized_targets(snapshot, actor, ability):
			if actor.position.distance_to(target.position) <= AbilityTargeting.target_range(definitions, ability.id) + SCORE_EPSILON:
				var support := Command.create(ability_id, actor.id)
				support.target_id = target.id
				commands.append(support)
	for target in targets:
		var destination: Variant = _useful_approach_destination(snapshot, actor, target, definitions)
		if destination != null:
			var move := Command.create(&"move", actor.id)
			move.target_pos = destination
			move.target_id = target.id
			commands.append(move)
	commands.append(Command.create(&"end_turn", actor.id))
	return commands


func _has_next_attack_condition_effect(ability: AbilityDefinition, definitions: DefinitionLibrary) -> bool:
	for effect in ability.effects:
		if effect.type != &"apply_condition":
			continue
		var condition := definitions.get_condition(effect.condition_id)
		if condition == null:
			continue
		if condition.next_attack_advantage or condition.next_attack_disadvantage or condition.next_attack_against_advantage or condition.next_attack_against_disadvantage:
			return true
	return false


func _has_heal_effect(ability: AbilityDefinition) -> bool:
	for effect in ability.effects:
		if effect.type == &"heal":
			return true
	return false


func _has_attack_effect(ability: AbilityDefinition) -> bool:
	for effect in ability.effects:
		if effect.type == &"perform_attack":
			return true
	return false


func _ability_is_ranged(ability: AbilityDefinition) -> bool:
	for effect in ability.effects:
		if effect.type == &"perform_attack" and effect.is_ranged:
			return true
	return false


func _prioritized_targets(snapshot: BattleState, actor: ActorState, ability: AbilityDefinition = null) -> Array[ActorState]:
	var targets: Array[ActorState] = []
	for actor_id_variant in snapshot.actors.keys():
		if not snapshot.active_combatant_ids.is_empty() and not snapshot.active_combatant_ids.has(int(actor_id_variant)):
			continue
		var target: ActorState = snapshot.actors[actor_id_variant]
		# A null ability is the generic enemy approach query, whose existing
		# behavior is nearest living opposing actor. Actor-targeted abilities
		# always take the data-defined filter path below.
		var is_valid := target.side != actor.side and target.is_alive() if ability == null else AbilityTargeting.is_valid_target(actor, target, ability)
		if is_valid:
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


func _useful_approach_destination(snapshot: BattleState, actor: ActorState, target: ActorState, definitions: DefinitionLibrary) -> Variant:
	if actor.movement_remaining <= SCORE_EPSILON:
		return null
	var distance := actor.position.distance_to(target.position)
	var preferred_range := _preferred_attack_range(actor, definitions)
	if EquipmentRules.is_ranged_weapon(actor, definitions) and distance < MINIMUM_RANGED_STANDOFF_METERS - SCORE_EPSILON:
		var retreat_direction := target.position.direction_to(actor.position)
		retreat_direction.y = 0.0
		if retreat_direction.length_squared() <= SCORE_EPSILON:
			retreat_direction = Vector3.RIGHT
		var retreat_distance := minf(actor.movement_remaining, MINIMUM_RANGED_STANDOFF_METERS - distance)
		return actor.position + retreat_direction.normalized() * retreat_distance
	if distance <= preferred_range + SCORE_EPSILON and (EquipmentRules.is_ranged_weapon(actor, definitions) or _has_formation_space(snapshot, actor)):
		return null
	var desired_position := _formation_position(snapshot, actor, target, preferred_range)
	if actor.position.distance_to(desired_position) <= SCORE_EPSILON:
		return null
	# Let Resolver own pathfinding and movement clamping. Sending the complete
	# desired slot keeps real navigation from rejecting a hand-clamped point,
	# while the resolver still stops at the actor's remaining movement.
	return desired_position


func _formation_position(snapshot: BattleState, actor: ActorState, target: ActorState, preferred_range: float = ATTACK_RANGE_METERS) -> Vector3:
	var outward := actor.position - target.position
	outward.y = 0.0
	if outward.length_squared() <= SCORE_EPSILON:
		outward = Vector3.FORWARD
	else:
		outward = outward.normalized()
	var best_position := target.position + outward * preferred_range
	best_position.y = actor.position.y
	var best_clearance := -INF
	var best_travel := INF
	var found_clear_slot := false
	for angle in FORMATION_ANGLES:
		var candidate := target.position + outward.rotated(Vector3.UP, deg_to_rad(angle)) * preferred_range
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


func _preferred_attack_range(actor: ActorState, definitions: DefinitionLibrary) -> float:
	if EquipmentRules.is_ranged_weapon(actor, definitions):
		return minf(18.0, EquipmentRules.normal_range(actor, definitions, 18.0))
	for ability_id in actor.ability_ids:
		var ability := definitions.get_ability(ability_id)
		if ability != null and _has_attack_effect(ability):
			return AbilityTargeting.attack_range(definitions, ability_id)
	return ATTACK_RANGE_METERS


func _has_formation_space(snapshot: BattleState, actor: ActorState) -> bool:
	return _nearest_ally_distance(snapshot, actor, actor.position) + SCORE_EPSILON >= FORMATION_SEPARATION_METERS


func _nearest_ally_distance(snapshot: BattleState, actor: ActorState, position: Vector3) -> float:
	var nearest := INF
	for other_id in snapshot.actors:
		if not snapshot.active_combatant_ids.is_empty() and not snapshot.active_combatant_ids.has(int(other_id)):
			continue
		var other: ActorState = snapshot.actors[other_id]
		if other.id != actor.id and other.side == actor.side and other.is_alive():
			nearest = minf(nearest, _planar_distance(position, other.position))
	return nearest


func _planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _score(before: BattleState, actor: ActorState, command: Command, result: ResolutionResult, los: LosProvider) -> float:
	var score := 0.0
	var definitions := DefinitionLibrary.get_default()
	var ability := definitions.get_ability(command.type)
	if ability != null and _has_attack_effect(ability):
		var target: ActorState = before.actors[command.target_id]
		var attack := _attack_outcome(before, actor, target, ability, los, definitions)
		score += 1000.0 + float(attack.expected_damage) * 10.0
		score += float(attack.kill_probability) * 10000.0
		if EquipmentRules.is_ranged_weapon(actor, definitions) and AttackMathRules.is_threatened(before, actor):
			score -= 1000.0
	elif ability != null and _has_heal_effect(ability):
		var restored := _expected_healing(ability, actor)
		if restored <= 0.0:
			score = -10.0
		else:
			var missing_hp: int = max(0, actor.max_hp - actor.hp)
			# The same heal becomes increasingly valuable nearer to being downed.
			score += restored * (20.0 + 180.0 * float(missing_hp) / maxf(1.0, actor.max_hp))
	else:
		match command.type:
			&"move":
				var before_distance := _nearest_enemy_distance(before, actor)
				var after_distance := _nearest_enemy_distance_from(before, actor, command.target_pos)
				if EquipmentRules.is_ranged_weapon(actor, definitions) and before_distance < MINIMUM_RANGED_STANDOFF_METERS:
					score += (after_distance - before_distance) * 100.0
				else:
					score += (before_distance - after_distance) * 100.0
				if actor.action_available:
					score += 25.0
			&"dodge":
				# Dodge is a defensive fallback, not a default idle action. It is
				# useful when a badly wounded enemy is under imminent pressure and
				# has no better attack or approach candidate.
				var nearby_threat := _nearest_enemy_distance(before, actor)
				score = 180.0 if actor.hp * 2 <= actor.max_hp and nearby_threat <= 6.0 else -10.0
			&"disengage": score = 300.0 if AttackMathRules.is_threatened(before, actor) else -10.0
			&"dash": score = 100.0 if _nearest_enemy_distance(before, actor) > actor.movement_remaining else -10.0
			&"end_turn": score = 0.0
	# Opportunity attacks are deterministic to detect but stochastic to resolve.
	# Penalize their expected harm, never the damage emitted by the speculative
	# resolver call above. Each reaction is evaluated where it fires: at the
	# end of the movement segment that precedes it.
	var mover := actor.clone()
	for event in result.events:
		if event.type == &"movement_segment" and int(event.data.get("actor_id", -1)) == actor.id:
			mover.position = event.data["to"]
			continue
		if event.type != &"reaction_triggered" or int(event.data.get("target_id", -1)) != actor.id:
			continue
		var reactor := before.actors.get(int(event.data.get("actor_id", -1))) as ActorState
		if reactor == null:
			continue
		var reaction := _opportunity_attack_outcome(before, reactor, mover, los, definitions)
		score -= float(reaction.expected_damage) * 200.0
		score -= float(reaction.kill_probability) * 1000000.0
	return score


## Expected outcome of `ability` against `target` from the snapshot, through
## the same AttackMath evaluation, range bands, and cover Resolver uses. Only
## pre-roll facts are read; no speculative die result reaches the score.
func _attack_outcome(before: BattleState, attacker: ActorState, target: ActorState, ability: AbilityDefinition, los: LosProvider, definitions: DefinitionLibrary) -> Dictionary:
	var target_range := AbilityTargeting.target_range(definitions, ability.id)
	var is_ranged := _ability_is_ranged(ability) or EquipmentRules.is_ranged_weapon(attacker, definitions)
	var normal_range := EquipmentRules.normal_range(attacker, definitions, target_range) if is_ranged else target_range
	var cover := los.cover_between(attacker.position, target.position)
	var evaluation := AttackMathRules.evaluate(before, attacker, target, definitions, cover, is_ranged, normal_range)
	return AttackMathRules.expected_outcome(evaluation, target.hp)


## Opportunity attacks are melee attacks made at the reactor's reach.
func _opportunity_attack_outcome(before: BattleState, reactor: ActorState, mover: ActorState, los: LosProvider, definitions: DefinitionLibrary) -> Dictionary:
	var cover := los.cover_between(reactor.position, mover.position)
	var evaluation := AttackMathRules.evaluate(before, reactor, mover, definitions, cover, false, ATTACK_RANGE_METERS)
	return AttackMathRules.expected_outcome(evaluation, mover.hp)


func _expected_healing(ability: AbilityDefinition, actor: ActorState) -> float:
	var average := 0.0
	for effect in ability.effects:
		if effect.type == &"heal":
			average += (float(effect.heal_die) + 1.0) * 0.5 * float(effect.heal_dice_count) + effect.heal_modifier
	return minf(maxf(0.0, average), float(maxi(0, actor.max_hp - actor.hp)))


func _nearest_enemy_distance(state: BattleState, actor: ActorState) -> float:
	return _nearest_enemy_distance_from(state, actor, actor.position)


func _nearest_enemy_distance_from(state: BattleState, actor: ActorState, position: Vector3) -> float:
	var nearest := INF
	for actor_id_variant in state.actors.keys():
		if not state.active_combatant_ids.is_empty() and not state.active_combatant_ids.has(int(actor_id_variant)):
			continue
		var other: ActorState = state.actors[actor_id_variant]
		if other.side != actor.side and other.is_alive():
			nearest = minf(nearest, position.distance_to(other.position))
	return 0.0 if is_inf(nearest) else nearest


func _is_accepted(result: ResolutionResult) -> bool:
	return not result.events.is_empty() and result.events[0].type != &"command_rejected"


func _apply_result(state: BattleState, result: ResolutionResult) -> void:
	for event in result.events:
		ResolverRules.apply(state, event)
	state.rng_state = result.next_rng_state


func _ensure_budget(budget: AIQueryBudget) -> AIQueryBudget:
	return budget if budget != null else AIQueryBudget.new()
