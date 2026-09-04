class_name TurnOrder
extends RefCounted

## Turn eligibility is intentionally owned by the simulation. Presentation
## never decides whose turn is next.

static func is_actor_eligible(actor: ActorState) -> bool:
	return actor.is_conscious()


static func eligible_actor_ids(state: BattleState) -> Array[int]:
	var actor_ids: Array = state.actors.keys()
	actor_ids.sort()
	var eligible: Array[int] = []
	for actor_id_variant in actor_ids:
		var actor_id: int = actor_id_variant
		var actor: ActorState = state.actors[actor_id]
		if is_actor_eligible(actor):
			eligible.append(actor_id)
	return eligible


static func next_eligible_index(state: BattleState, current_index: int) -> int:
	if state.initiative_order.is_empty():
		return -1
	for offset in range(1, state.initiative_order.size() + 1):
		var index := posmod(current_index + offset, state.initiative_order.size())
		var actor_id := state.initiative_order[index]
		if state.actors.has(actor_id) and is_actor_eligible(state.actors[actor_id]):
			return index
	return -1
