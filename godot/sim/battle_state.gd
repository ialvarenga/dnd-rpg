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

## Interactable world objects (door/chest/lever -- Fase A9), keyed by stable
## string id. Authoritative: only Resolver.apply() mutates entries, same as
## actors.
var interactables: Dictionary = {}

## Identifies which AbilityDefinition/ConditionDefinition content this state
## was produced under (see DefinitionLibrary.CONTENT_VERSION), so a future
## save/load pass (A8) can validate compatibility alongside rules_version.
var content_version: int = DefinitionLibrary.CONTENT_VERSION


func clone() -> BattleState:
	var copy := BattleState.new()
	var actor_ids: Array = actors.keys()
	actor_ids.sort()
	for actor_id_variant in actor_ids:
		var actor_id: int = actor_id_variant
		copy.actors[actor_id] = (actors[actor_id] as ActorState).clone()
	var interactable_ids: Array = interactables.keys()
	interactable_ids.sort()
	for interactable_id in interactable_ids:
		copy.interactables[interactable_id] = (interactables[interactable_id] as InteractableState).clone()
	copy.initiative_order = initiative_order.duplicate()
	copy.current_turn_index = current_turn_index
	copy.round_number = round_number
	copy.phase = phase
	copy.rng_seed = rng_seed
	copy.rng_state = rng_state
	copy.world_flags = world_flags.duplicate(true)
	copy.content_version = content_version
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
	var interactable_snapshots: Array[Dictionary] = []
	var interactable_ids: Array = interactables.keys()
	interactable_ids.sort()
	for interactable_id in interactable_ids:
		var interactable: InteractableState = interactables[interactable_id]
		interactable_snapshots.append({
			"id": interactable.id,
			"type": String(interactable.type),
			"state": String(interactable.state),
		})
	return {
		"actors": actor_snapshots,
		"interactables": interactable_snapshots,
		"initiative_order": initiative_order,
		"current_turn_index": current_turn_index,
		"round_number": round_number,
		"phase": String(phase),
		"rng_seed": rng_seed,
		"rng_state": rng_state,
		"world_flags": SimulationSerialization.value_to_data(world_flags),
		"content_version": content_version,
	}


func to_dict() -> Dictionary:
	var actor_data: Array[Dictionary] = []
	var actor_ids: Array = actors.keys()
	actor_ids.sort()
	for actor_id_variant in actor_ids:
		actor_data.append((actors[actor_id_variant] as ActorState).to_dict())
	var interactable_data: Array[Dictionary] = []
	var interactable_ids: Array = interactables.keys()
	interactable_ids.sort()
	for interactable_id in interactable_ids:
		interactable_data.append((interactables[interactable_id] as InteractableState).to_dict())
	return {
		"actors": actor_data,
		"interactables": interactable_data,
		"initiative_order": initiative_order.duplicate(),
		"current_turn_index": current_turn_index,
		"round_number": round_number,
		"phase": String(phase),
		"rng_seed": rng_seed,
		"rng_state": rng_state,
		"world_flags": SimulationSerialization.value_to_data(world_flags),
		"content_version": content_version,
	}


static func from_dict(data: Dictionary) -> BattleState:
	var state := BattleState.new()
	for actor_data in data.get("actors", []):
		if actor_data is Dictionary:
			var actor := ActorState.from_dict(actor_data)
			state.actors[actor.id] = actor
	for interactable_data in data.get("interactables", []):
		if interactable_data is Dictionary:
			var interactable := InteractableState.from_dict(interactable_data)
			state.interactables[interactable.id] = interactable
	for actor_id in data.get("initiative_order", []):
		state.initiative_order.append(int(actor_id))
	state.current_turn_index = int(data.get("current_turn_index", 0))
	state.round_number = int(data.get("round_number", 1))
	state.phase = StringName(str(data.get("phase", "exploration")))
	state.rng_seed = int(data.get("rng_seed", 0))
	state.rng_state = int(data.get("rng_state", 0))
	state.content_version = int(data.get("content_version", DefinitionLibrary.CONTENT_VERSION))
	var restored_flags: Variant = SimulationSerialization.data_to_value(data.get("world_flags", {}))
	if restored_flags is Dictionary:
		state.world_flags = restored_flags
	return state
