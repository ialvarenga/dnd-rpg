class_name HudViewModel
extends RefCounted

const AbilityTargetingRules = preload("res://sim/ability_targeting.gd")
const EquipmentRules = preload("res://sim/equipment.gd")
const AbilityCostRules = preload("res://sim/rules/ability_cost_rules.gd")

const AVAILABILITY_REASON_TEXT := {
	&"unknown_actor": "Unknown character.",
	&"not_current_actor": "It is not this character's turn.",
	&"not_in_combat": "Only available during combat.",
	&"combat_already_active": "Not available during combat.",
	&"actor_cannot_act": "This character cannot act.",
	&"unknown_ability_definition": "Action definition is missing.",
	&"action_unavailable": "Action already used this turn.",
	&"bonus_action_unavailable": "Bonus action already used this turn.",
	&"ability_uses_exhausted": "No uses remaining until the next encounter.",
	&"reaction_unavailable": "Reaction already used this round.",
	&"insufficient_movement": "Not enough movement remaining.",
}


static func objective_prompt(state: BattleState) -> String:
	if state == null:
		return "Explore the area"
	if state.game_outcome == &"victory":
		return "Adventure complete"
	if state.game_outcome == &"defeat":
		return "The hero has fallen"
	if state.phase == &"combat":
		return "Defeat the encounter"
	var objective_ids: Array = state.objectives.keys()
	objective_ids.sort()
	for objective_id in objective_ids:
		var objective := state.objectives[objective_id] as ObjectiveState
		if objective == null or objective.completed:
			continue
		if objective.requirements_met(state.cleared_encounter_ids):
			return "Reach %s" % String(objective.id).replace("_", " ").capitalize()
		for encounter_id in objective.requires_encounter_ids:
			if not state.cleared_encounter_ids.has(encounter_id):
				return "Clear %s" % String(encounter_id).replace("_", " ").capitalize()
	return "Explore the area"

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
	if name.is_empty():
		# Actors spawned without a definition still need a label for narration
		# and the turn tracker.
		name = "Actor %d" % actor_id
	if actions.is_empty():
		# Carried items are inventory interactions, not combat-hotbar actions.
		actions = ActionAvailability.evaluate_all(state, actor_id, actor.ability_ids, defs)
	return {
		"actor_id": actor_id, "name": name, "hp": actor.hp, "max_hp": actor.max_hp,
		"hp_fraction": clampf(float(actor.hp) / maxf(1.0, actor.max_hp), 0.0, 1.0),
		"armor_class": actor.armor_class, "movement_remaining": actor.movement_remaining,
		"movement_speed": actor.movement_speed, "movement_fraction": clampf(actor.movement_remaining / maxf(0.01, actor.movement_speed), 0.0, 1.0),
		"action_available": actor.action_available, "bonus_action_available": actor.bonus_action_available,
		"reaction_available": actor.reaction_available, "conditions": actor.condition_ids(),
		"is_current_turn": state.current_actor_id() == actor_id, "phase": state.phase,
		"movement_budget_ignored": state.phase == &"exploration", "action_availability": _present_actions(actor, actions, defs),
	}


## Adds presentation-only metadata to ActionAvailability's resolver-facing
## evaluation. Live mechanics are projected from the same actor, equipment,
## and ability resources the resolver reads, so tooltip numbers cannot drift
## from combat resolution when a loadout changes.
static func action_presentation(actor: ActorState, availability: Dictionary, defs: DefinitionLibrary) -> Dictionary:
	var data := availability.duplicate(true)
	var ability_id := StringName(str(data.get("ability_id", "")))
	var generated_name := String(ability_id).replace("_", " ").capitalize()
	var ability := defs.get_ability(ability_id) if defs != null else null
	var display_name := ability.display_name if ability != null and not ability.display_name.is_empty() else generated_name
	var description := ability.description if ability != null else ""
	var mechanics: Array[String] = _action_mechanics(actor, ability, defs)
	var sections: Array[String] = [display_name]
	if not description.is_empty():
		sections.append(description)
	if not mechanics.is_empty():
		sections.append(" • ".join(mechanics))
	if not bool(data.get("available", false)):
		sections.append("Unavailable: %s" % _availability_reason(StringName(str(data.get("reason", "")))))
	data["display_name"] = display_name
	data["description"] = description
	data["tooltip"] = "\n\n".join(sections)
	return data


static func _present_actions(actor: ActorState, actions: Array[Dictionary], defs: DefinitionLibrary) -> Array[Dictionary]:
	var presented: Array[Dictionary] = []
	for action in actions:
		presented.append(action_presentation(actor, action, defs))
	return presented


static func _action_mechanics(actor: ActorState, ability: AbilityDefinition, defs: DefinitionLibrary) -> Array[String]:
	var mechanics: Array[String] = []
	if ability == null:
		return mechanics
	if ability.costs_action:
		mechanics.append("Action")
	if ability.costs_bonus_action:
		mechanics.append("Bonus action")
	if ability.costs_reaction:
		mechanics.append("Reaction")
	if ability.movement_cost > 0.0:
		mechanics.append("%s m movement" % _format_number(ability.movement_cost))
	if mechanics.is_empty():
		mechanics.append("No action cost")

	var has_attack := false
	var has_self_effect := false
	for effect in ability.effects:
		match effect.type:
			&"perform_attack":
				has_attack = true
				_append_attack_mechanics(mechanics, actor, ability, effect, defs)
			&"add_base_movement":
				mechanics.append("Gain %s m movement" % _format_number(actor.movement_speed * effect.multiplier))
			&"saving_throw":
				var difficulty_class := effect.save_dc_base + actor.proficiency_bonus + actor.ability_modifier(effect.save_dc_ability)
				mechanics.append("Save DC %d" % difficulty_class)
				if not effect.save_abilities.is_empty():
					var ability_names: Array[String] = []
					for save_ability in effect.save_abilities:
						ability_names.append(String(save_ability).capitalize())
					mechanics.append(" or ".join(ability_names))
			&"heal":
				has_self_effect = true
				mechanics.append("Heal %s HP" % _format_roll(effect.heal_dice_count, effect.heal_die, effect.heal_modifier))
			&"apply_condition":
				mechanics.append(_condition_mechanic(effect, defs))
			&"apply_disengage":
				mechanics.append("No opportunity attacks this turn")

	if not has_attack and ability.targeting == &"actor" and ability.target_range_meters >= 0.0:
		mechanics.append("Range %s m" % _format_number(AbilityTargetingRules.target_range(defs, ability.id)))
	if has_self_effect and ability.targeting == &"none":
		mechanics.insert(1, "Self")
	if ability.usable_in_exploration:
		mechanics.append("Exploration")
	if ability.max_uses >= 0:
		mechanics.append("Uses %d/%d" % [AbilityCostRules.remaining_uses(actor, ability), ability.max_uses])
	mechanics = mechanics.filter(func(entry: String): return not entry.is_empty())
	return mechanics


static func _append_attack_mechanics(mechanics: Array[String], actor: ActorState, ability: AbilityDefinition, effect: AbilityEffect, defs: DefinitionLibrary) -> void:
	var maximum_range := AbilityTargetingRules.target_range(defs, ability.id)
	var is_ranged := effect.is_ranged or EquipmentRules.is_ranged_weapon(actor, defs)
	if is_ranged:
		var normal_range := EquipmentRules.normal_range(actor, defs, maximum_range)
		var long_range := EquipmentRules.long_range(actor, defs, maximum_range)
		mechanics.append("Ranged")
		mechanics.append("Range %s m / %s m long" % [_format_number(normal_range), _format_number(long_range)])
	else:
		mechanics.append("Melee")
		mechanics.append("Range %s m" % _format_number(maximum_range))
	mechanics.append("Attack %s" % _format_modifier(EquipmentRules.aggregate_attack_bonus(actor, defs)))
	var damage := _format_roll(1, EquipmentRules.aggregate_damage_die(actor, defs), EquipmentRules.aggregate_damage_modifier(actor, defs))
	var damage_type := String(EquipmentRules.aggregate_damage_type(actor, defs))
	mechanics.append("Damage %s%s" % [damage, " " + damage_type if not damage_type.is_empty() else ""])


static func _condition_mechanic(effect: AbilityEffect, defs: DefinitionLibrary) -> String:
	var condition := defs.get_condition(effect.condition_id) if defs != null else null
	var label := condition.display_name if condition != null and not condition.display_name.is_empty() else String(effect.condition_id).replace("_", " ").capitalize()
	var suffix := ""
	if effect.apply_when == &"failed_save":
		suffix = " on failed save"
	elif condition != null and condition.default_duration_triggers == 1 and condition.default_expiration_timing == &"turn_start":
		suffix = " until next turn"
	return label + suffix


static func _format_roll(count: int, sides: int, modifier: int) -> String:
	var roll := "%dd%d" % [count, sides]
	if modifier != 0:
		roll += " %s %d" % ["+" if modifier > 0 else "-", absi(modifier)]
	return roll


static func _format_modifier(modifier: int) -> String:
	return "+%d" % modifier if modifier >= 0 else str(modifier)


static func _format_number(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value


static func _availability_reason(reason: StringName) -> String:
	if AVAILABILITY_REASON_TEXT.has(reason):
		return AVAILABILITY_REASON_TEXT[reason]
	var fallback := String(reason).replace("_", " ").capitalize()
	return fallback + "." if not fallback.is_empty() else "Not currently available."


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
		&"encounter_resolved": return "Encounter won." if d.get("outcome") == &"victory" else "The party was defeated."
		&"game_over": return "Defeat."
		&"objective_completed": return "Objective completed: %s." % String(d.get("objective_id", "objective")).replace("_", " ").capitalize()
		&"game_completed": return "Adventure complete."
		&"movement_segment": return "%s moves." % actor_name
		&"movement_spent": return "%s spends %.1f movement." % [actor_name, float(d.get("amount", 0.0))]
		&"movement_gained": return "%s gains %.1f movement." % [actor_name, float(d.get("amount", 0.0))]
		&"action_spent": return "%s uses an action." % actor_name
		&"bonus_action_spent": return "%s uses a bonus action." % actor_name
		# The ability's own narration already names what happened; this would only
		# repeat it, so the accounting stays silent in the log.
		&"ability_use_spent": return ""
		&"reaction_triggered": return "%s reacts." % actor_name
		&"disengage_applied": return "%s disengages." % actor_name
		&"attack_rolled": return "%s %s %s (roll %d)." % [actor_name, "hits" if d.get("hit", false) else "misses", target_name, int(d.get("roll", 0))]
		&"damage_taken":
			var damage_type := String(d.get("damage_type", ""))
			return "%s takes %d%s damage." % [actor_name, int(d.get("amount", 0)), " " + damage_type if not damage_type.is_empty() else ""]
		&"d20_test_rolled": return "%s %s a %s save (%d vs DC %d)." % [actor_name, "passes" if d.get("success", false) else "fails", String(d.get("ability", "ability")), int(d.get("total", 0)), int(d.get("difficulty_class", 0))]
		&"healing_received": return "%s recovers %d HP." % [actor_name, int(d.get("amount", 0))]
		&"item_consumed": return "%s consumes %s." % [actor_name, String(d.get("item_id", "an item")).replace("_", " ")]
		&"actor_downed": return "%s is downed." % actor_name
		&"actor_died": return "%s dies." % actor_name
		&"condition_added": return "%s gains %s." % [actor_name, String(d.get("condition", "a condition"))]
		&"condition_removed": return "%s loses %s." % [actor_name, String(d.get("condition", "a condition"))]
		&"interaction_completed": return "%s interacts with %s." % [actor_name, String(d.get("interactable_id", "the object"))]
		&"skill_check_rolled":
			var skill := String(d.get("skill", ""))
			var label := skill.replace("_", " ").capitalize() if not skill.is_empty() else String(d.get("ability", "check")).capitalize()
			return "%s rolls %s: %d vs DC %d - %s." % [actor_name, label, int(d.get("total", 0)), int(d.get("difficulty_class", 0)), "success" if d.get("success", false) else "failure"]
		&"disposition_changed":
			return "%s stands down." % actor_name if String(d.get("disposition", "")) == "neutral" else "%s turns hostile." % actor_name
		&"dialog_started": return "%s speaks with %s." % [actor_name, target_name]
		&"turn_ended": return "%s ends their turn." % actor_name
		&"turn_started": return "%s's turn." % actor_name
		&"command_rejected": return "%s rejected: %s." % [String(d.get("command_type", "Command")), String(d.get("reason", "unavailable"))]
		_: return "Combat event: %s." % String(event.type)


static func _actor_name(state: BattleState, actor_id: int, defs: DefinitionLibrary) -> String:
	var data := for_actor(state, actor_id, defs)
	return String(data.get("name", "Actor %d" % actor_id))
