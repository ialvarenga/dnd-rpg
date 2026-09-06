class_name HudViewModel
extends RefCounted

## Pure projection of authoritative state for Canvas UI.  It never stores or
## changes BattleState, and availability is advisory only.
static func for_actor(state: BattleState, actor_id: int, defs: DefinitionLibrary, actions: Array[Dictionary] = []) -> Dictionary:
	if state == null or not state.actors.has(actor_id):
		return {}
	var actor: ActorState = state.actors[actor_id]
	var actor_def: ActorDefinition = defs.get_actor(actor.definition_id) if defs != null else null
	var name := String(actor.definition_id).capitalize().replace("_", " ")
	if actor_def != null and not actor_def.display_name.is_empty():
		name = actor_def.display_name
	if actions.is_empty():
		# Carried items are inventory interactions, not combat-hotbar actions.
		actions = ActionAvailability.evaluate_all(state, actor_id, actor.ability_ids, defs)
	return {
		"actor_id": actor_id, "name": name, "hp": actor.hp, "max_hp": actor.max_hp,
		"hp_fraction": clampf(float(actor.hp) / maxf(1.0, actor.max_hp), 0.0, 1.0),
		"armor_class": actor.armor_class, "movement_remaining": actor.movement_remaining,
		"movement_speed": actor.movement_speed, "movement_fraction": clampf(actor.movement_remaining / maxf(0.01, actor.movement_speed), 0.0, 1.0),
		"action_available": actor.action_available, "bonus_action_available": actor.bonus_action_available,
		"reaction_available": actor.reaction_available, "conditions": actor.conditions.duplicate(),
		"is_current_turn": state.current_actor_id() == actor_id, "phase": state.phase,
		"movement_budget_ignored": state.phase == &"exploration", "action_availability": actions.duplicate(true),
	}


static func turn_order(state: BattleState, defs: DefinitionLibrary) -> Array[Dictionary]:
	var order: Array[Dictionary] = []
	if state == null:
		return order
	for index in state.initiative_order.size():
		var actor_id := state.initiative_order[index]
		if not state.actors.has(actor_id) or not state.actors[actor_id].is_alive():
			continue
		var data := for_actor(state, actor_id, defs)
		if not data.is_empty():
			order.append({"actor_id": actor_id, "name": data.name, "hp_fraction": data.hp_fraction, "hp": data.hp, "max_hp": data.max_hp, "is_current": index == state.current_turn_index, "index": index})
	return order


static func narrate(event: Event, state: BattleState, defs: DefinitionLibrary) -> String:
	if event == null:
		return "Combat updated."
	var d := event.data
	var actor_name := _actor_name(state, int(d.get("actor_id", -1)), defs)
	var target_name := _actor_name(state, int(d.get("target_id", -1)), defs)
	match event.type:
		&"combat_started": return "%s starts combat." % actor_name
		&"initiative_established": return "Initiative order established."
		&"combat_ending": return "Combat is ending."
		&"combat_ended": return "Combat ended."
		&"movement_segment": return "%s moves." % actor_name
		&"movement_spent": return "%s spends %.1f movement." % [actor_name, float(d.get("amount", 0.0))]
		&"movement_gained": return "%s gains %.1f movement." % [actor_name, float(d.get("amount", 0.0))]
		&"action_spent": return "%s uses an action." % actor_name
		&"bonus_action_spent": return "%s uses a bonus action." % actor_name
		&"reaction_triggered": return "%s reacts." % actor_name
		&"disengage_applied": return "%s disengages." % actor_name
		&"attack_rolled": return "%s %s %s (roll %d)." % [actor_name, "hits" if d.get("hit", false) else "misses", target_name, int(d.get("roll", 0))]
		&"damage_taken": return "%s takes %d damage." % [actor_name, int(d.get("amount", 0))]
		&"healing_received": return "%s recovers %d HP." % [actor_name, int(d.get("amount", 0))]
		&"item_consumed": return "%s consumes %s." % [actor_name, String(d.get("item_id", "an item")).replace("_", " ")]
		&"actor_downed": return "%s is downed." % actor_name
		&"actor_died": return "%s dies." % actor_name
		&"condition_added": return "%s gains %s." % [actor_name, String(d.get("condition", "a condition"))]
		&"condition_removed": return "%s loses %s." % [actor_name, String(d.get("condition", "a condition"))]
		&"interaction_completed": return "%s interacts with %s." % [actor_name, String(d.get("interactable_id", "the object"))]
		&"turn_ended": return "%s ends their turn." % actor_name
		&"turn_started": return "%s's turn." % actor_name
		&"command_rejected": return "%s rejected: %s." % [String(d.get("command_type", "Command")), String(d.get("reason", "unavailable"))]
		_: return "Combat event: %s." % String(event.type)


static func _actor_name(state: BattleState, actor_id: int, defs: DefinitionLibrary) -> String:
	var data := for_actor(state, actor_id, defs)
	return String(data.get("name", "Actor %d" % actor_id))
