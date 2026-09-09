class_name TestHudViewModel
extends RefCounted

static func run() -> Dictionary:
	var failures: Array[String] = []
	var state := TestHelpers.make_battle()
	var actor: ActorState = state.actors[1]
	actor.definition_id = &"knight"
	actor.ability_ids = [&"dash"]
	actor.hp = 10
	var data := HudViewModel.for_actor(state, 1, DefinitionLibrary.get_default())
	_expect(is_equal_approx(data.hp_fraction, 0.5), "actor projection should expose HP fraction", failures)
	_expect(data.is_current_turn, "actor projection should expose current turn", failures)
	_expect(data.action_availability.size() == 1, "actor projection should preserve available action order", failures)
	var order := HudViewModel.turn_order(state, DefinitionLibrary.get_default())
	_expect(order.size() == 2 and order[0].actor_id == 1, "turn order should follow authoritative initiative order", failures)
	state.actors[2].hp = 0
	state.actors[2].condition_states.clear()
	state.actors[2].add_condition(&"dead")
	order = HudViewModel.turn_order(state, DefinitionLibrary.get_default())
	_expect(order.size() == 1 and order[0].actor_id == 1, "turn order should remove dead actors", failures)
	for event_type in _event_narration_expectations():
		var line := HudViewModel.narrate(Event.create(event_type, {"actor_id": 1, "target_id": 2, "amount": 2, "roll": 12, "hit": true, "condition": &"poisoned", "reason": &"not_current_actor"}), state, DefinitionLibrary.get_default())
		_expect(line == _event_narration_expectations()[event_type], "narration did not match the supported %s event" % event_type, failures)
	return {"name": "unit/test_hud_view_model", "failures": failures}

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
		&"attack_rolled": "Knight hits Actor 2 (roll 12).",
		&"damage_taken": "Knight takes 2 damage.",
		&"healing_received": "Knight recovers 2 HP.",
		&"item_consumed": "Knight consumes an item.",
		&"actor_downed": "Knight is downed.",
		&"actor_died": "Knight dies.",
		&"condition_added": "Knight gains poisoned.",
		&"condition_removed": "Knight loses poisoned.",
		&"interaction_completed": "Knight interacts with the object.",
		&"turn_ended": "Knight ends their turn.",
		&"turn_started": "Knight's turn.",
		&"command_rejected": "Command rejected: not_current_actor.",
	}

static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition: failures.append(message)
