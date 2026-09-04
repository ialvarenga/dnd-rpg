class_name BattleState
extends RefCounted

var actors: Dictionary = {}
var initiative_order: Array[int] = []
var current_turn_index: int = 0
var round_number: int = 1
var phase: StringName = &"exploration"
var rng_seed: int = 0
var rng_state: int = 0
var world_flags: Dictionary = {}


func clone() -> BattleState:
	var copy := BattleState.new()
	var actor_ids: Array = actors.keys()
	actor_ids.sort()
	for actor_id_variant in actor_ids:
		var actor_id: int = actor_id_variant
		copy.actors[actor_id] = (actors[actor_id] as ActorState).clone()
	copy.initiative_order = initiative_order.duplicate()
	copy.current_turn_index = current_turn_index
	copy.round_number = round_number
	copy.phase = phase
	copy.rng_seed = rng_seed
	copy.rng_state = rng_state
	copy.world_flags = world_flags.duplicate(true)
	return copy


func current_actor_id() -> int:
	if initiative_order.is_empty() or current_turn_index < 0 or current_turn_index >= initiative_order.size():
		return -1
	return initiative_order[current_turn_index]


func stable_snapshot() -> Dictionary:
	var actor_snapshots: Array[Dictionary] = []
	var actor_ids: Array = actors.keys()
	actor_ids.sort()
	for actor_id_variant in actor_ids:
		var actor: ActorState = actors[actor_id_variant]
		actor_snapshots.append({
			"id": actor.id,
			"position": [actor.position.x, actor.position.y, actor.position.z],
			"hp": actor.hp,
			"movement_remaining": actor.movement_remaining,
			"action_available": actor.action_available,
			"bonus_action_available": actor.bonus_action_available,
			"reaction_available": actor.reaction_available,
			"disengaged": actor.disengaged,
			"conditions": actor.conditions,
		})
	return {
		"actors": actor_snapshots,
		"initiative_order": initiative_order,
		"current_turn_index": current_turn_index,
		"round_number": round_number,
		"phase": String(phase),
		"rng_seed": rng_seed,
		"rng_state": rng_state,
	}

