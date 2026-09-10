class_name BattleState
extends RefCounted

var actors: Dictionary = {}
var initiative_order: Array[int] = []
var current_turn_index: int = 0
var round_number: int = 1
var phase: StringName = &"exploration"
var active_encounter_id: String = ""
var active_combatant_ids: Array[int] = []
var cleared_encounter_ids: Array[String] = []
var last_encounter_outcome: StringName = &"none"
var game_outcome: StringName = &"ongoing"
var rng_seed: int = 0
var rng_state: int = 0
var world_flags: Dictionary = {}

## Interactable world objects (door/chest/lever -- Fase A9), keyed by stable
## string id. Authoritative: only Resolver.apply() mutates entries, same as
## actors.
var interactables: Dictionary = {}
var objectives: Dictionary = {}

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
	var objective_ids: Array = objectives.keys()
	objective_ids.sort()
	for objective_id in objective_ids:
		copy.objectives[objective_id] = (objectives[objective_id] as ObjectiveState).clone()
	copy.initiative_order = initiative_order.duplicate()
	copy.current_turn_index = current_turn_index
	copy.round_number = round_number
	copy.phase = phase
	copy.active_encounter_id = active_encounter_id
	copy.active_combatant_ids = active_combatant_ids.duplicate()
	copy.cleared_encounter_ids = cleared_encounter_ids.duplicate()
	copy.last_encounter_outcome = last_encounter_outcome
	copy.game_outcome = game_outcome
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
			"disposition": String(actor.disposition),
			"condition_states": actor.condition_states.map(func(condition: ConditionState): return condition.to_dict()),
			"inventory": actor.inventory,
			"ability_uses_spent": _sorted_ability_uses(actor.ability_uses_spent),
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
			"contents": interactable.contents,
		})
	var objective_snapshots: Array[Dictionary] = []
	var objective_ids: Array = objectives.keys()
	objective_ids.sort()
	for objective_id in objective_ids:
		objective_snapshots.append((objectives[objective_id] as ObjectiveState).to_dict())
	return {
		"actors": actor_snapshots,
		"interactables": interactable_snapshots,
		"objectives": objective_snapshots,
		"initiative_order": initiative_order,
		"current_turn_index": current_turn_index,
		"round_number": round_number,
		"phase": String(phase),
		"active_encounter_id": active_encounter_id,
		"active_combatant_ids": active_combatant_ids,
		"cleared_encounter_ids": cleared_encounter_ids,
		"last_encounter_outcome": String(last_encounter_outcome),
		"game_outcome": String(game_outcome),
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
	var objective_data: Array[Dictionary] = []
	var objective_ids: Array = objectives.keys()
	objective_ids.sort()
	for objective_id in objective_ids:
		objective_data.append((objectives[objective_id] as ObjectiveState).to_dict())
	return {
		"actors": actor_data,
		"interactables": interactable_data,
		"objectives": objective_data,
		"initiative_order": initiative_order.duplicate(),
		"current_turn_index": current_turn_index,
		"round_number": round_number,
		"phase": String(phase),
		"active_encounter_id": active_encounter_id,
		"active_combatant_ids": active_combatant_ids.duplicate(),
		"cleared_encounter_ids": cleared_encounter_ids.duplicate(),
		"last_encounter_outcome": String(last_encounter_outcome),
		"game_outcome": String(game_outcome),
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
	for objective_data in data.get("objectives", []):
		if objective_data is Dictionary:
			var objective := ObjectiveState.from_dict(objective_data)
			state.objectives[objective.id] = objective
	for actor_id in data.get("initiative_order", []):
		state.initiative_order.append(int(actor_id))
	state.current_turn_index = int(data.get("current_turn_index", 0))
	state.round_number = int(data.get("round_number", 1))
	state.phase = StringName(str(data.get("phase", "exploration")))
	state.active_encounter_id = str(data.get("active_encounter_id", ""))
	for actor_id in data.get("active_combatant_ids", []):
		state.active_combatant_ids.append(int(actor_id))
	for encounter_id in data.get("cleared_encounter_ids", []):
		state.cleared_encounter_ids.append(str(encounter_id))
	state.last_encounter_outcome = StringName(str(data.get("last_encounter_outcome", "none")))
	state.game_outcome = StringName(str(data.get("game_outcome", "ongoing")))
	state.rng_seed = int(data.get("rng_seed", 0))
	state.rng_state = int(data.get("rng_state", 0))
	state.content_version = int(data.get("content_version", DefinitionLibrary.CONTENT_VERSION))
	var restored_flags: Variant = SimulationSerialization.data_to_value(data.get("world_flags", {}))
	if restored_flags is Dictionary:
		state.world_flags = restored_flags
	return state


## Dictionary iteration follows insertion order, which depends on the order
## abilities happened to be spent. Sorting keeps the stable snapshot (and the
## determinism hash built from it) identical for equivalent states.
static func _sorted_ability_uses(uses: Dictionary) -> Dictionary:
	var sorted_uses := {}
	var ability_ids: Array = uses.keys()
	ability_ids.sort()
	for ability_id in ability_ids:
		sorted_uses[String(ability_id)] = int(uses[ability_id])
	return sorted_uses
