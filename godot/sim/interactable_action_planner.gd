class_name InteractableActionPlanner
extends RefCounted

## Finds the least-cost reachable position from which Resolver accepts an
## interaction. Candidate moves are resolved against a cloned state so combat
## movement budgets, standing, opportunity attacks, turn order, and action
## costs remain authoritative without planning mutating the live encounter.

const PolylineUtil = preload("res://sim/polyline.gd")
const RejectionReasonRules = preload("res://sim/rules/rejection_reason.gd")
const InteractableActionPlanScript = preload("res://sim/interactable_action_plan.gd")

const PATH_SAMPLE_STEP_M := 0.25
const RADIAL_SAMPLE_COUNT := 24
const RADIAL_RATIOS := [0.9, 0.7, 0.5, 0.3]
const BINARY_REFINEMENT_STEPS := 10
const EPSILON := 0.001


static func plan(state: BattleState, actor_id: int, interactable_id: String, nav: NavProvider, los: LosProvider):
	var result = InteractableActionPlanScript.new()
	if state == null or nav == null or los == null or not state.actors.has(actor_id):
		result.rejection_reason = RejectionReasonRules.UNKNOWN_ACTOR
		return result
	if not state.interactables.has(interactable_id):
		result.rejection_reason = RejectionReasonRules.UNKNOWN_INTERACTABLE
		return result

	var interact_command := _interact_command(actor_id, interactable_id)
	var immediate := Resolver.resolve(state, interact_command, nav, los)
	var immediate_rejection := _rejection_reason(immediate)
	if immediate_rejection == &"":
		result.can_execute = true
		result.destination = (state.actors[actor_id] as ActorState).position
		return result
	result.rejection_reason = immediate_rejection
	if immediate_rejection != RejectionReasonRules.OUT_OF_RANGE:
		return result

	var actor: ActorState = state.actors[actor_id]
	if state.phase == &"combat" and actor.movement_remaining <= EPSILON:
		return result
	var interactable: InteractableState = state.interactables[interactable_id]
	var best := _best_direct_path_candidate(state, interact_command, actor, interactable, nav, los)
	var radial := _best_radial_candidate(state, interact_command, actor, interactable, nav, los)
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


static func _best_direct_path_candidate(state: BattleState, interact_command: Command, actor: ActorState, interactable: InteractableState, nav: NavProvider, los: LosProvider) -> Dictionary:
	# An interactable normally owns a navigation blocker, so its center is not a
	# legal destination. Snap first, then stop at the first point along that path
	# from which the authoritative interaction succeeds.
	var requested := nav.snap_to_navmesh(interactable.position)
	var path := PolylineUtil.with_start(nav.find_path(actor.position, requested), actor.position)
	if path.size() < 2:
		return {}
	var path_length := PolylineUtil.length(path)
	var search_limit := path_length if state.phase != &"combat" else minf(path_length, actor.movement_remaining)
	var previous_distance := 0.0
	var distance := minf(PATH_SAMPLE_STEP_M, search_limit)
	while distance > previous_distance + EPSILON:
		var candidate := _point_at_distance(path, distance)
		var evaluation := _evaluate_candidate(state, interact_command, candidate, nav, los)
		if not evaluation.is_empty():
			var low := previous_distance
			var high := distance
			var best := evaluation
			for _step in range(BINARY_REFINEMENT_STEPS):
				var midpoint := (low + high) * 0.5
				var refined := _evaluate_candidate(state, interact_command, _point_at_distance(path, midpoint), nav, los)
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


static func _best_radial_candidate(state: BattleState, interact_command: Command, actor: ActorState, interactable: InteractableState, nav: NavProvider, los: LosProvider) -> Dictionary:
	var best: Dictionary = {}
	for ratio in RADIAL_RATIOS:
		var radius := interactable.interact_range * float(ratio)
		for sample in range(RADIAL_SAMPLE_COUNT):
			var angle := TAU * float(sample) / float(RADIAL_SAMPLE_COUNT)
			var requested := interactable.position + Vector3(cos(angle) * radius, actor.position.y - interactable.position.y, sin(angle) * radius)
			requested = nav.snap_to_navmesh(requested)
			var path := PolylineUtil.with_start(nav.find_path(actor.position, requested), actor.position)
			if path.size() < 2:
				continue
			if state.phase == &"combat" and PolylineUtil.length(path) > actor.movement_remaining + EPSILON:
				continue
			var candidate := path[path.size() - 1]
			var evaluation := _evaluate_candidate(state, interact_command, candidate, nav, los)
			if not evaluation.is_empty() and (best.is_empty() or float(evaluation["movement_cost"]) < float(best["movement_cost"])):
				best = evaluation
	return best


static func _evaluate_candidate(state: BattleState, interact_command: Command, movement_target: Vector3, nav: NavProvider, los: LosProvider) -> Dictionary:
	var move_command := Command.create(&"move", interact_command.actor_id)
	move_command.target_pos = movement_target
	var move_result := Resolver.resolve(state, move_command, nav, los)
	if _rejection_reason(move_result) != &"":
		return {}
	var projected := state.clone()
	for event in move_result.events:
		Resolver.apply(projected, event)
	projected.rng_state = move_result.next_rng_state
	var moved_actor: ActorState = projected.actors[interact_command.actor_id]
	if moved_actor.position.distance_to((state.actors[interact_command.actor_id] as ActorState).position) <= EPSILON:
		return {}
	var interact_result := Resolver.resolve(projected, interact_command, nav, los)
	if _rejection_reason(interact_result) != &"":
		return {}
	return {
		"movement_target": movement_target,
		"destination": moved_actor.position,
		"movement_cost": _movement_cost(move_result),
	}


static func _movement_cost(result: ResolutionResult) -> float:
	var cost := 0.0
	for event in result.events:
		if event.type == &"movement_spent":
			cost += float(event.data.get("amount", 0.0))
	if cost > EPSILON:
		return cost
	for event in result.events:
		if event.type == &"movement_segment":
			cost += float(event.data.get("path_cost", 0.0))
	return cost


static func _point_at_distance(path: PackedVector3Array, distance: float) -> Vector3:
	var prefix := PolylineUtil.clamp(path, distance)
	return prefix[prefix.size() - 1] if not prefix.is_empty() else path[0]


static func _interact_command(actor_id: int, interactable_id: String) -> Command:
	var command := Command.create(&"interact", actor_id)
	command.target_interactable_id = interactable_id
	return command


static func _rejection_reason(resolution: ResolutionResult) -> StringName:
	for event in resolution.events:
		if event.type == &"command_rejected":
			return event.data.get("reason", &"")
	return &""
