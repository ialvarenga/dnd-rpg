class_name TestHudViewModel
extends RefCounted

static func run() -> Dictionary:
	var failures: Array[String] = []
	var state := TestHelpers.make_battle()
	var actor: ActorState = state.actors[1]
	actor.definition_id = &"knight"
	actor.ability_ids = [&"dash"]
	actor.hp = 10
	actor.coins = 7
	var data := HudViewModel.for_actor(state, 1, DefinitionLibrary.get_default())
	_expect(is_equal_approx(data.hp_fraction, 0.5), "actor projection should expose HP fraction", failures)
	_expect(data.is_current_turn, "actor projection should expose current turn", failures)
	_expect(data.action_availability.size() == 1, "actor projection should preserve available action order", failures)
	_expect(int(data.coins) == 7, "actor projection should expose the live coin balance", failures)
	var order := HudViewModel.turn_order(state, DefinitionLibrary.get_default())
	_expect(order.size() == 2 and order[0].actor_id == 1, "turn order should follow authoritative initiative order", failures)
	state.actors[2].hp = 0
	state.actors[2].condition_states.clear()
	state.actors[2].add_condition(&"dead")
	order = HudViewModel.turn_order(state, DefinitionLibrary.get_default())
	_expect(order.size() == 1 and order[0].actor_id == 1, "turn order should remove dead actors", failures)
	for event_type in _event_narration_expectations():
		var line := HudViewModel.narrate(Event.create(event_type, {"actor_id": 1, "target_id": 2, "amount": 2, "roll": 12, "hit": true, "condition": &"poisoned", "reason": &"not_current_actor", "skill": &"persuasion", "difficulty_class": 12, "total": 14, "success": true, "disposition": &"neutral", "dialog_id": &"emberwatch_toll", "encounter_id": &"emberwatch_ambush"}), state, DefinitionLibrary.get_default())
		_expect(line == _event_narration_expectations()[event_type], "narration did not match the supported %s event" % event_type, failures)
	_test_roll_breakdown_narration(state, failures)
	_test_action_tooltip_projection(failures)
	_test_action_tooltip_fallback(failures)
	return {"name": "unit/test_hud_view_model", "failures": failures}


static func _test_roll_breakdown_narration(state: BattleState, failures: Array[String]) -> void:
	var attack := Event.create(&"attack_rolled", {
		"actor_id": 1, "target_id": 2, "roll": 14, "attack_bonus": 4, "total": 18,
		"armor_class": 15, "hit": true, "advantage": true, "rolls": [7, 14],
		"cover": LosProvider.COVER_HALF, "cover_bonus": 2,
	})
	_expect(HudViewModel.narrate(attack, state, DefinitionLibrary.get_default()) == "Knight hits Actor 2 (14 +4 = 18 vs AC 15; advantage [7, 14], half cover +2 AC).", "attack narration omitted its full roll breakdown", failures)
	var sourced := Event.create(&"attack_rolled", {
		"actor_id": 1, "target_id": 2, "roll": 3, "attack_bonus": 4, "total": 7,
		"armor_class": 12, "hit": false, "disadvantage": true, "rolls": [3, 15],
		"disadvantage_sources": [{"source": AttackMath.SOURCE_LONG_RANGE, "actor_id": 1}, {"source": &"dodging", "actor_id": 2}],
	})
	_expect(HudViewModel.narrate(sourced, state, DefinitionLibrary.get_default()) == "Knight misses Actor 2 (3 +4 = 7 vs AC 12; disadvantage [3, 15] from long range and Actor 2 dodging).", "attack narration did not name its disadvantage sources: %s" % HudViewModel.narrate(sourced, state, DefinitionLibrary.get_default()), failures)
	var cancelled := Event.create(&"attack_rolled", {
		"actor_id": 1, "target_id": 2, "roll": 11, "attack_bonus": 4, "total": 15,
		"armor_class": 12, "hit": true, "rolls": [11],
		"advantage_sources": [{"source": &"prone", "actor_id": 2}],
		"disadvantage_sources": [{"source": &"poisoned", "actor_id": 1}],
	})
	_expect(HudViewModel.narrate(cancelled, state, DefinitionLibrary.get_default()) == "Knight hits Actor 2 (11 +4 = 15 vs AC 12; advantage and disadvantage cancel).", "attack narration did not report cancelled roll modes", failures)
	var save := Event.create(&"d20_test_rolled", {
		"actor_id": 1, "ability": &"dexterity", "roll": 6, "modifier": 3,
		"total": 9, "difficulty_class": 12, "success": false, "disadvantage": true,
		"rolls": [6, 17],
	})
	_expect(HudViewModel.narrate(save, state, DefinitionLibrary.get_default()) == "Knight fails a dexterity save (6 +3 = 9 vs DC 12; disadvantage [6, 17]).", "d20 narration omitted its roll modifier or disadvantage source", failures)


static func _test_action_tooltip_projection(failures: Array[String]) -> void:
	var definitions := DefinitionLibrary.get_default()
	var state := TestHelpers.make_battle()
	var knight := ActorState.from_definition(definitions.get_actor(&"knight"), 1, &"heroes", Vector3.ZERO)
	state.actors[1] = knight
	var data := HudViewModel.for_actor(state, 1, definitions)

	var attack := _action(data.action_availability, &"basic_attack")
	_expect(attack.get("display_name") == "Basic Attack", "action projection did not expose the authored display name", failures)
	_expect(String(attack.get("description", "")).contains("melee weapon attack"), "basic attack tooltip omitted its authored description", failures)
	_expect(String(attack.get("tooltip", "")).contains("Action • Melee • Range 1.5 m • Attack +4 (Str +2, Prof +2) • Damage 1d8 + 2 slashing"), "basic attack tooltip did not use the knight's live longsword statistics", failures)

	var dash := _action(data.action_availability, &"dash")
	_expect(String(dash.get("tooltip", "")).contains("Action • Gain 9 m movement"), "dash tooltip did not calculate movement from the actor's speed", failures)
	var shove := _action(data.action_availability, &"shove")
	_expect(String(shove.get("tooltip", "")).contains("Save DC 12 • Strength or Dexterity"), "shove tooltip did not calculate its save DC and alternatives", failures)
	_expect(String(shove.get("tooltip", "")).contains("Prone on failed save"), "shove tooltip omitted its failed-save result", failures)
	var dodge := _action(data.action_availability, &"dodge")
	_expect(String(dodge.get("tooltip", "")).contains("Dodging until next turn"), "dodge tooltip omitted its duration", failures)
	_expect(_action(data.action_availability, &"talk").is_empty(), "contextual Talk action leaked into the persistent HUD action list", failures)
	var talk_availability := ActionAvailability.evaluate(state, 1, &"talk", definitions)
	var talk := HudViewModel.action_presentation(knight, talk_availability, definitions)
	_expect(String(talk.get("tooltip", "")).contains("No action cost") and String(talk.get("tooltip", "")).contains("Range 3 m") and String(talk.get("tooltip", "")).contains("Exploration"), "talk tooltip omitted its cost, range, or phase", failures)
	var ally_ability := AbilityDefinition.new()
	ally_ability.id = &"ally_action"
	ally_ability.targeting = &"actor"
	ally_ability.target_filter = &"ally"
	ally_ability.target_range_meters = 3.0
	definitions.add_ability(ally_ability)
	var ally_presentation := HudViewModel.action_presentation(knight, ActionAvailability.evaluate(state, 1, ally_ability.id, definitions), definitions)
	_expect(String(ally_presentation.get("tooltip", "")).contains("Target: ally"), "non-hostile target filter was missing from the HUD tooltip", failures)
	ally_ability.target_filter = &"self"
	var self_presentation := HudViewModel.action_presentation(knight, ActionAvailability.evaluate(state, 1, ally_ability.id, definitions), definitions)
	_expect(String(self_presentation.get("tooltip", "")).contains("Self"), "self target filter was missing from the HUD tooltip", failures)

	var potion_availability := ActionAvailability.evaluate(state, 1, &"quaff_healing_potion", definitions)
	var potion := HudViewModel.action_presentation(knight, potion_availability, definitions)
	_expect(String(potion.get("tooltip", "")).contains("Bonus action • Self • Heal 2d4 + 2 HP"), "potion tooltip omitted its calculated healing roll", failures)

	knight.action_available = false
	data = HudViewModel.for_actor(state, 1, definitions)
	attack = _action(data.action_availability, &"basic_attack")
	var disabled_tooltip := String(attack.get("tooltip", ""))
	_expect(disabled_tooltip.contains("Make a melee weapon attack") and disabled_tooltip.contains("Unavailable: Action already used this turn."), "disabled action tooltip did not preserve its description and append a readable reason", failures)

	var archer := ActorState.from_definition(definitions.get_actor(&"archer"), 1, &"heroes", Vector3.ZERO)
	state.actors[1] = archer
	data = HudViewModel.for_actor(state, 1, definitions)
	var ranged := _action(data.action_availability, &"ranged_attack")
	_expect(String(ranged.get("tooltip", "")).contains("Ranged • Range 24 m / 96 m long • Attack +4 (Dex +2, Prof +2) • Damage 1d6 + 2 piercing"), "ranged attack tooltip did not use the archer's live shortbow statistics", failures)


static func _test_action_tooltip_fallback(failures: Array[String]) -> void:
	var actor := ActorState.new()
	var presentation := HudViewModel.action_presentation(actor, {"ability_id": &"missing_action", "available": true, "reason": &""}, DefinitionLibrary.new())
	_expect(presentation.get("display_name") == "Missing Action" and presentation.get("description") == "" and presentation.get("tooltip") == "Missing Action", "missing action definition did not degrade to its generated name", failures)


static func _action(actions: Array[Dictionary], ability_id: StringName) -> Dictionary:
	for action in actions:
		if action.get("ability_id") == ability_id:
			return action
	return {}

static func _event_narration_expectations() -> Dictionary:
	return {
		&"combat_started": "Knight starts combat.",
		&"initiative_established": "Initiative order established.",
		&"combat_ending": "Combat is ending.",
		&"combat_ended": "Combat ended.",
		&"movement_segment": "Knight moves.",
		&"movement_spent": "Knight spends 2.0 movement.",
		&"movement_gained": "Knight gains 2.0 movement.",
		&"action_spent": "Knight uses an action.",
		&"bonus_action_spent": "Knight uses a bonus action.",
		&"reaction_triggered": "Knight reacts.",
		&"disengage_applied": "Knight disengages.",
		&"attack_rolled": "Knight hits Actor 2 (12 +2 = 14).",
		&"damage_taken": "Knight takes 2 damage.",
		&"healing_received": "Knight recovers 2 HP.",
		&"item_consumed": "Knight consumes an item.",
		&"coins_transferred": "Knight pays 2 coins to Actor 2.",
		&"actor_downed": "Knight is downed.",
		&"actor_died": "Knight dies.",
		&"condition_added": "Knight gains poisoned.",
		&"condition_removed": "Knight loses poisoned.",
		&"interaction_completed": "Knight interacts with the object.",
		&"turn_ended": "Knight ends their turn.",
		&"turn_started": "Knight's turn.",
		&"command_rejected": "Command rejected: not_current_actor.",
		&"skill_check_rolled": "Knight rolls Persuasion: 14 vs DC 12 - success.",
		&"disposition_changed": "Knight stands down.",
		&"encounter_cleared": "Knight resolves emberwatch ambush peacefully.",
		&"dialog_started": "Knight speaks with Actor 2.",
	}

static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition: failures.append(message)
