class_name TestEventPlayerFeedback
extends Node


func run() -> Dictionary:
	var failures: Array[String] = []
	var player := EventPlayer.new()
	var actor := CharacterView.new()
	actor.actor_id = 7
	add_child(player)
	add_child(actor)
	player.register_character_view(actor)
	var target := CharacterView.new()
	target.actor_id = 8
	add_child(target)
	player.register_character_view(target)
	var presented: Array[String] = []
	player.feedback_presented.connect(func(event: Event, feedback: FloatingCombatText):
		presented.append(event.type)
		var expected_anchor: CharacterView = target if event.type == &"attack_rolled" else actor
		_expect(feedback.get_parent() == expected_anchor, "%s feedback was not anchored to the affected CharacterView" % event.type, failures)
	)

	var damage_events: Array[Event] = [
		Event.create(&"damage_taken", {"actor_id": actor.actor_id, "amount": 2}),
		Event.create(&"damage_taken", {"actor_id": actor.actor_id, "amount": 5}),
	]
	player.play_events(damage_events)
	_expect(_feedback_texts(actor) == ["-2", "-5"], "every damage_taken event should create its own floating text", failures)
	var missed_attack_events: Array[Event] = [Event.create(&"attack_rolled", {"actor_id": actor.actor_id, "target_id": target.actor_id, "hit": false})]
	player.play_events(missed_attack_events)
	_expect(_feedback_texts(target) == ["MISS"], "a missed attack should create floating feedback on its target", failures)

	var feedback_events: Array[Event] = [
		Event.create(&"healing_received", {"actor_id": actor.actor_id, "amount": 3}),
		Event.create(&"item_consumed", {"actor_id": actor.actor_id, "item_id": &"healing_potion"}),
		Event.create(&"actor_downed", {"actor_id": actor.actor_id}),
		Event.create(&"condition_added", {"actor_id": actor.actor_id, "condition": &"poisoned"}),
		Event.create(&"condition_removed", {"actor_id": actor.actor_id, "condition": &"poisoned"}),
		Event.create(&"command_rejected", {"actor_id": actor.actor_id, "reason": &"not_current_actor"}),
	]
	player.play_events(feedback_events)
	_expect(presented == ["damage_taken", "damage_taken", "attack_rolled", "healing_received", "item_consumed", "actor_downed", "condition_added", "condition_removed", "command_rejected"], "new feedback events did not all reach the presentation layer", failures)
	_expect(_feedback_texts(actor).slice(2) == ["+3", "USED HEALING POTION", "DOWNED", "+POISONED", "-POISONED", "REJECTED: not current actor"], "feedback text did not describe healing, consumption, downing, conditions, and rejection", failures)

	var before_missing_view := _feedback_texts(actor).size()
	var missing_view_events: Array[Event] = [Event.create(&"damage_taken", {"actor_id": 999, "amount": 1})]
	player.play_events(missing_view_events)
	_expect(_feedback_texts(actor).size() == before_missing_view, "an event for an unregistered actor should be ignored safely", failures)
	var unknown_events: Array[Event] = [Event.create(&"future_event", {"actor_id": actor.actor_id})]
	player.play_events(unknown_events)
	_expect(_feedback_texts(actor).size() == before_missing_view, "unknown events should be ignored safely", failures)

	player.queue_free()
	actor.queue_free()
	target.queue_free()
	return {"name": "integration/test_event_player_feedback", "failures": failures}


func _feedback_texts(actor: CharacterView) -> Array[String]:
	var texts: Array[String] = []
	for child in actor.get_children():
		if child is FloatingCombatText:
			texts.append((child as FloatingCombatText).text)
	return texts


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
