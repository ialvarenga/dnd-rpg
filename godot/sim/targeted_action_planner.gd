class_name TargetedActionPlanner
extends RefCounted

## Finds the least-cost reachable position from which Resolver accepts an
## actor-targeted ability. Candidate moves are resolved against a cloned state,
## so movement budgets, standing, opportunity attacks, LOS, range, and ability
## costs stay authoritative without planning mutating the live encounter.

const PolylineUtil = preload("res://sim/polyline.gd")
const RejectionReasonRules = preload("res://sim/rules/rejection_reason.gd")
const AbilityTargetingRules = preload("res://sim/ability_targeting.gd")
const TargetedActionPlanScript = preload("res://sim/targeted_action_plan.gd")

const PATH_SAMPLE_STEP_M := 0.25
const RANGE_MARGIN_M := 0.025
const RADIAL_SAMPLE_COUNT := 24
const BINARY_REFINEMENT_STEPS := 10
const EPSILON := 0.001


static func plan(state: BattleState, actor_id: int, ability_id: StringName, target_id: int, nav: NavProvider, los: LosProvider, definitions: DefinitionLibrary = null):
	var result = TargetedActionPlanScript.new()
	var defs := definitions if definitions != null else DefinitionLibrary.get_default()
	if state == null or nav == null or los == null or not state.actors.has(actor_id):
		result.rejection_reason = RejectionReasonRules.UNKNOWN_ACTOR
		return result
	if not state.actors.has(target_id):
		result.rejection_reason = RejectionReasonRules.UNKNOWN_TARGET
		return result
	var ability := defs.get_ability(ability_id)
	if ability == null:
		result.rejection_reason = RejectionReasonRules.UNKNOWN_ABILITY_DEFINITION
		return result
	if ability.targeting != &"actor":
		result.rejection_reason = RejectionReasonRules.INVALID_TARGET
		return result
	var actor: ActorState = state.actors[actor_id]
	var target: ActorState = state.actors[target_id]
	if not AbilityTargetingRules.is_valid_target(actor, target, ability):
		result.rejection_reason = RejectionReasonRules.INVALID_TARGET
		return result

	var ability_command := _ability_command(actor_id, ability_id, target_id)
	var immediate := Resolver.resolve(state, ability_command, nav, los, defs)
	var immediate_rejection := _rejection_reason(immediate)
	if immediate_rejection == &"":
		result.can_execute = true
		result.destination = (state.actors[actor_id] as ActorState).position
		return result
	result.rejection_reason = immediate_rejection
	if immediate_rejection not in [RejectionReasonRules.TARGET_OUT_OF_RANGE, RejectionReasonRules.OUT_OF_RANGE, RejectionReasonRules.NO_LINE_OF_SIGHT]:
		return result

	var target_range := AbilityTargetingRules.target_range(defs, ability_id)
	if target_range < 0.0:
		return result
	# Exploration moves ignore the combat movement budget (Resolver does too),
	# so walking up to talk is limited only by navigation, like interactables.
	if state.phase == &"combat" and actor.movement_remaining <= EPSILON:
		return result
	# Approach the way the resolver will route this creature: across only the
	# ledges its Strength can take (ADR-009).
	nav = nav.for_jumper(actor.strength)
	var best := _best_direct_path_candidate(state, ability_command, actor, target, nav, los, defs)
	var radial := _best_radial_candidate(state, ability_command, actor, target, target_range, nav, los, defs)
	if not radial.is_empty() and (best.is_empty() or float(radial["movement_cost"]) < float(best["movement_cost"])):
		best = radial
	if best.is_empty():
		return result

	result.can_execute = true
	result.requires_movement = true
	result.movement_target = best["movement_target"]
	result.destination = best["destination"]
	result.movement_cost = best["movement_cost"]
	result.rejection_reason = &""
	return result


static func _best_direct_path_candidate(state: BattleState, ability_command: Command, actor: ActorState, target: ActorState, nav: NavProvider, los: LosProvider, definitions: DefinitionLibrary) -> Dictionary:
	var path := PolylineUtil.with_start(nav.find_path(actor.position, target.position), actor.position)
	if path.size() < 2:
		return {}
	var path_length := PolylineUtil.length(path)
	var search_limit := path_length if state.phase != &"combat" else minf(path_length, actor.movement_remaining)
	var previous_distance := 0.0
	var distance := minf(PATH_SAMPLE_STEP_M, search_limit)
	while distance > previous_distance + EPSILON:
		var candidate := _point_at_distance(path, distance)
		var evaluation := _evaluate_candidate(state, ability_command, candidate, nav, los, definitions)
		if not evaluation.is_empty():
			var low := previous_distance
			var high := distance
			var best := evaluation
			for _step in range(BINARY_REFINEMENT_STEPS):
				var midpoint := (low + high) * 0.5
				var refined := _evaluate_candidate(state, ability_command, _point_at_distance(path, midpoint), nav, los, definitions)
				if refined.is_empty():
					low = midpoint
				else:
					high = midpoint
					best = refined
			return best
		previous_distance = distance
		if is_equal_approx(distance, search_limit):
			break
		distance = minf(distance + PATH_SAMPLE_STEP_M, search_limit)
	return {}


static func _best_radial_candidate(state: BattleState, ability_command: Command, actor: ActorState, target: ActorState, target_range: float, nav: NavProvider, los: LosProvider, definitions: DefinitionLibrary) -> Dictionary:
	var best: Dictionary = {}
	var radius := maxf(0.0, target_range - RANGE_MARGIN_M)
	for sample in range(RADIAL_SAMPLE_COUNT):
		var angle := TAU * float(sample) / float(RADIAL_SAMPLE_COUNT)
		var requested := target.position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		requested = nav.snap_to_navmesh(requested)
		var path := PolylineUtil.with_start(nav.find_path(actor.position, requested), actor.position)
		if path.size() < 2 or (state.phase == &"combat" and nav.path_cost(path) > actor.movement_remaining + EPSILON):
			continue
		var candidate := path[path.size() - 1]
		var evaluation := _evaluate_candidate(state, ability_command, candidate, nav, los, definitions)
		if not evaluation.is_empty() and (best.is_empty() or float(evaluation["movement_cost"]) < float(best["movement_cost"])):
			best = evaluation
	return best


static func _evaluate_candidate(state: BattleState, ability_command: Command, movement_target: Vector3, nav: NavProvider, los: LosProvider, definitions: DefinitionLibrary) -> Dictionary:
	var move_command := Command.create(&"move", ability_command.actor_id)
	move_command.target_pos = movement_target
	var move_result := Resolver.resolve(state, move_command, nav, los, definitions)
	if _rejection_reason(move_result) != &"":
		return {}
	var projected := state.clone()
	for event in move_result.events:
		Resolver.apply(projected, event)
	projected.rng_state = move_result.next_rng_state
	var moved_actor: ActorState = projected.actors[ability_command.actor_id]
	if moved_actor.position.distance_to((state.actors[ability_command.actor_id] as ActorState).position) <= EPSILON:
		return {}
	var ability_result := Resolver.resolve(projected, ability_command, nav, los, definitions)
	if _rejection_reason(ability_result) != &"":
		return {}
	var original_actor: ActorState = state.actors[ability_command.actor_id]
	return {
		"movement_target": movement_target,
		"destination": moved_actor.position,
		"movement_cost": maxf(0.0, original_actor.movement_remaining - moved_actor.movement_remaining),
	}


static func _point_at_distance(path: PackedVector3Array, distance: float) -> Vector3:
	var prefix := PolylineUtil.clamp(path, distance)
	return prefix[prefix.size() - 1] if not prefix.is_empty() else path[0]


static func _ability_command(actor_id: int, ability_id: StringName, target_id: int) -> Command:
	var command := Command.create(ability_id, actor_id)
	command.target_id = target_id
	command.target_pos = Vector3.INF
	return command


static func _rejection_reason(resolution: ResolutionResult) -> StringName:
	for event in resolution.events:
		if event.type == &"command_rejected":
			return event.data.get("reason", &"")
	return &""
