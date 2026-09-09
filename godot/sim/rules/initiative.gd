class_name Initiative
extends RefCounted

## Pure initiative calculation. Actors are rolled in stable ID order so the
## supplied RNG stream produces the same order on every replay.

const TurnOrderRules = preload("res://sim/rules/turn_order.gd")

static func dexterity_modifier(dexterity: int) -> int:
	return floori(float(dexterity - 10) / 2.0)


static func resolve(state: BattleState) -> Dictionary:
	return resolve_for_actor_ids(state, TurnOrderRules.eligible_actor_ids(state))


static func resolve_for_actor_ids(state: BattleState, requested_actor_ids: Array[int]) -> Dictionary:
	var actor_ids: Array[int] = []
	for actor_id in requested_actor_ids:
		if state.actors.has(actor_id) and TurnOrderRules.is_actor_eligible(state.actors[actor_id]):
			actor_ids.append(actor_id)
	actor_ids.sort()
	var next_rng_state := state.rng_state
	var entries: Array[Dictionary] = []
	for actor_id in actor_ids:
		var actor: ActorState = state.actors[actor_id]
		var roll_result := Dice.roll_die(next_rng_state, 20)
		var roll: int = roll_result["value"]
		next_rng_state = roll_result["next_rng_state"]
		var dex_modifier := dexterity_modifier(actor.dexterity)
		entries.append({
			"actor_id": actor.id,
			"roll": roll,
			"dexterity": actor.dexterity,
			"dexterity_modifier": dex_modifier,
			"total": roll + dex_modifier,
		})
	entries = sort_entries(entries)
	var order: Array[int] = []
	for entry in entries:
		order.append(entry["actor_id"])
	return {
		"entries": entries,
		"order": order,
		"next_rng_state": next_rng_state,
	}


static func sort_entries(entries: Array[Dictionary]) -> Array[Dictionary]:
	var sorted_entries := entries.duplicate(true)
	sorted_entries.sort_custom(_sort_entries)
	return sorted_entries


static func _sort_entries(first: Dictionary, second: Dictionary) -> bool:
	if first["total"] != second["total"]:
		return first["total"] > second["total"]
	if first["dexterity"] != second["dexterity"]:
		return first["dexterity"] > second["dexterity"]
	return first["actor_id"] < second["actor_id"]
