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
	for event_type in _event_types():
		var line := HudViewModel.narrate(Event.create(event_type, {"actor_id": 1, "target_id": 2, "amount": 2, "roll": 12, "hit": true, "condition": &"poisoned", "reason": &"not_current_actor"}), state, DefinitionLibrary.get_default())
		_expect(not line.strip_edges().is_empty(), "narration must be non-empty for %s" % event_type, failures)
	return {"name": "unit/test_hud_view_model", "failures": failures}

static func _event_types() -> Array[StringName]:
	return [&"combat_started", &"initiative_established", &"combat_ending", &"combat_ended", &"movement_segment", &"movement_spent", &"movement_gained", &"action_spent", &"bonus_action_spent", &"reaction_triggered", &"disengage_applied", &"attack_rolled", &"damage_taken", &"actor_downed", &"actor_died", &"condition_added", &"condition_removed", &"interaction_completed", &"turn_ended", &"turn_started", &"command_rejected"]

static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition: failures.append(message)
