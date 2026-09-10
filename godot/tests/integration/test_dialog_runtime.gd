class_name TestDialogRuntime
extends Node

const DialogSessionScript = preload("res://world/dialog_session.gd")

## End-to-end proof that the authored Emberwatch conversation actually works in
## the compiled map: the camp does not ambush you on approach, talking opens the
## authored graph, a check rolls in the simulation, and each ending changes the
## world the way the option promised.


func run() -> Dictionary:
	var failures: Array[String] = []
	var map := preload("res://scenes/compiled_forest_map.tscn").instantiate() as CompiledMapController
	get_tree().root.add_child(map)
	for _frame in range(8):
		await get_tree().process_frame
	if map.session == null or map.character == null:
		failures.append("compiled map did not finish encounter setup")
		map.queue_free()
		return {"name": "integration/test_dialog_runtime", "failures": failures}

	_test_authored_stat_blocks_and_stances(map, failures)
	_test_neutral_camp_does_not_ambush(map, failures)
	_test_talk_opens_the_authored_graph(map, failures)
	_test_underlings_defer_instead_of_negotiating(map, failures)
	_test_coin_toll_transfers_and_pacifies(map, failures)
	await _test_persuasion_can_pacify_the_camp(map, failures)
	_test_drawing_starts_the_encounter(map, failures)
	map.queue_free()
	return {"name": "integration/test_dialog_runtime", "failures": failures}


func _talker(map: CompiledMapController) -> int:
	for actor_id in map.hostile_views:
		if (map.battle_state.actors[int(actor_id)] as ActorState).dialog_id != &"":
			return int(actor_id)
	return -1


## Walks the player next to `actor_id` and opens its conversation, so a test can
## inspect what that particular bandit actually offers.
func _open_dialog(map: CompiledMapController, actor_id: int) -> bool:
	if map._dialog_session.is_active():
		map._dialog_session.cancel()
		map.hud.dialog_panel.close()
	var player := map.battle_state.actors[map.character.actor_id] as ActorState
	var target := map.battle_state.actors[actor_id] as ActorState
	player.position = target.position + Vector3(1.5, 0.0, 0.0)
	map.character.synchronize_to_authoritative_position(player.position)
	map.session.submit_ability(map.character.actor_id, &"talk", actor_id, Vector3.INF)
	return map._dialog_session.is_active()


## The bandit who actually negotiates is the one whose greeting offers a roll.
## Found by inspection rather than by hardcoding the chieftain, so re-authoring
## which NPC holds the parley does not silently skip this test.
func _negotiator(map: CompiledMapController) -> int:
	for actor_id in map.hostile_views:
		if _open_dialog(map, int(actor_id)) and _first_check_option(map) != -1:
			return int(actor_id)
	if map._dialog_session.is_active():
		map._dialog_session.cancel()
		map.hud.dialog_panel.close()
	return -1


## Every enemy used to share one hardcoded stat block; the map now authors them.
func _test_authored_stat_blocks_and_stances(map: CompiledMapController, failures: Array[String]) -> void:
	var definition_ids: Array[StringName] = []
	for actor_id in map.hostile_views:
		var actor := map.battle_state.actors[int(actor_id)] as ActorState
		definition_ids.append(actor.definition_id)
		_expect(actor.disposition == &"neutral", "camp actor '%s' should start neutral so it can be approached" % actor.definition_id, failures)
	_expect(definition_ids.size() >= 3, "the Emberwatch camp should still spawn its three bandits", failures)
	_expect(definition_ids.size() == _unique(definition_ids).size(), "the camp should use distinct authored stat blocks, not one repeated block", failures)
	for actor_id in map.hostile_views:
		var actor := map.battle_state.actors[int(actor_id)] as ActorState
		# The sentry is the first thing the player meets on the road. A neutral
		# actor with nothing to say neither ambushes nor talks, so every member
		# of a neutral camp needs a way in.
		_expect(actor.dialog_id != &"", "camp actor '%s' is neutral but has no dialog, so walking up to it does nothing" % actor.definition_id, failures)
	var player := map.battle_state.actors[map.character.actor_id] as ActorState
	_expect(player.coins == 10, "the Knight should begin the Emberwatch map with the authored 10-coin wallet", failures)


## The reason disposition exists: detection fires at encounter range, which is
## further than talk range, so a hostile camp could never be addressed.
func _test_neutral_camp_does_not_ambush(map: CompiledMapController, failures: Array[String]) -> void:
	var talker_id := _talker(map)
	if talker_id == -1:
		return
	var talker := map.battle_state.actors[talker_id] as ActorState
	var player := map.battle_state.actors[map.character.actor_id] as ActorState
	player.position = talker.position + Vector3(1.5, 0.0, 0.0)
	map.character.synchronize_to_authoritative_position(player.position)
	map._check_hostile_detection()
	_expect(map.battle_state.phase == &"exploration", "a neutral camp must not start combat when the player walks in", failures)


func _test_talk_opens_the_authored_graph(map: CompiledMapController, failures: Array[String]) -> void:
	var talker_id := _talker(map)
	if talker_id == -1:
		return
	var result: ResolutionResult = map.session.submit_ability(map.character.actor_id, &"talk", talker_id, Vector3.INF)
	_expect(result.events.any(func(event: Event): return event.type == &"dialog_started"), "talking to an adjacent NPC should open its dialog", failures)
	_expect(map._dialog_session.is_active(), "the dialog session should be walking the authored graph", failures)
	_expect(map.hud.dialog_panel.visible, "the dialog panel should be showing the opened conversation", failures)
	_expect(map.hud.dialog_panel.option_list.get_child_count() > 1, "the authored greeting should offer the player a choice", failures)

	# An actor with nothing to say is rejected by the resolver, not by the view.
	var silent_id := -1
	for actor_id in map.hostile_views:
		if int(actor_id) != talker_id:
			silent_id = int(actor_id)
			break
	if silent_id != -1:
		# Every camp member is talkable now, so silence has to be constructed
		# rather than borrowed from the map.
		var silent_actor := map.battle_state.actors[silent_id] as ActorState
		var restored_dialog_id := silent_actor.dialog_id
		silent_actor.dialog_id = &""
		silent_actor.position = (map.battle_state.actors[map.character.actor_id] as ActorState).position
		var silent: ResolutionResult = map.session.submit_ability(map.character.actor_id, &"talk", silent_id, Vector3.INF)
		_expect(silent.events.any(func(event: Event): return event.type == &"command_rejected" and event.data.get("reason") == &"target_has_no_dialog"), "talking to an NPC with no dialog should be rejected", failures)
		silent_actor.dialog_id = restored_dialog_id


## Every camp member answers, but only one of them can be bargained with. The
## rest brush you off and point at the chief, which is what tells the player
## where to go instead of leaving them clicking an unresponsive bandit.
func _test_underlings_defer_instead_of_negotiating(map: CompiledMapController, failures: Array[String]) -> void:
	var negotiator := _negotiator(map)
	_expect(negotiator != -1, "no camp actor offers a check to bargain with", failures)
	var deferred := 0
	for actor_id in map.hostile_views:
		if int(actor_id) == negotiator:
			continue
		_expect(_open_dialog(map, int(actor_id)), "an underling should still answer when talked to", failures)
		_expect(_first_check_option(map) == -1, "only the negotiator should offer a roll", failures)
		_expect(map.hud.dialog_panel.option_list.get_child_count() > 1, "an underling should still offer the player a way onward", failures)
		_expect(map.hud.dialog_panel.text_label.text.length() > 0, "an underling should say something rather than open an empty panel", failures)
		deferred += 1
	_expect(deferred >= 2, "the camp should have underlings that defer to the chief", failures)
	if map._dialog_session.is_active():
		map._dialog_session.cancel()
		map.hud.dialog_panel.close()


func _test_coin_toll_transfers_and_pacifies(map: CompiledMapController, failures: Array[String]) -> void:
	var talker_id := _negotiator(map)
	if talker_id == -1 or not map._dialog_session.is_active():
		failures.append("could not open the negotiation to test the coin toll")
		return
	var payment_option := _payment_option(map)
	_expect(payment_option != -1, "the chief should offer the authored 10-coin toll", failures)
	if payment_option == -1:
		return
	var payment_button := map.hud.dialog_panel.option_list.get_child(payment_option) as Button
	_expect(not payment_button.disabled, "the 10-coin toll should be enabled for the Knight's exact starting balance", failures)
	var normal_style := payment_button.get_theme_stylebox(&"normal")
	_expect(normal_style != null and is_equal_approx(normal_style.get_content_margin(SIDE_LEFT), 12.0), "dialog choice text should have a 12 px left inset", failures)
	map._dialog_session.choose(payment_option)
	var player := map.battle_state.actors[map.character.actor_id] as ActorState
	var chieftain := map.battle_state.actors[talker_id] as ActorState
	_expect(player.coins == 0 and chieftain.coins == 10, "paying the toll should debit the Knight and credit the speaking chieftain", failures)
	_expect(map.hud.coins_label.text == "COINS: 0", "the HUD should refresh after the coin transfer", failures)
	_expect(map._dialog_session.is_active() and map.hud.dialog_panel.text_label.text.contains("Ten coins buys you the road"), "the chief should answer the paid toll with a threatening warning", failures)
	map._dialog_session.choose(0)
	for actor_id in map.hostile_views:
		_expect((map.battle_state.actors[int(actor_id)] as ActorState).disposition == &"neutral", "paying the toll should safely pacify the entire camp", failures)
	_expect(map.battle_state.cleared_encounter_ids.has("emberwatch_ambush"), "a peaceful toll resolution should clear the encounter that gates the objective", failures)
	_expect(not map._dialog_session.is_active() and not map.hud.dialog_panel.visible, "the chief's final passage response should close the dialog", failures)
	var objective := map.battle_state.objectives.get("emberwatch_camp") as ObjectiveState
	_expect(objective != null and objective.requirements_met(map.battle_state.cleared_encounter_ids), "a paid peaceful resolution should unlock the objective marker for the player's next move", failures)
	_expect(_open_dialog(map, talker_id), "the chieftain should remain talkable after granting passage", failures)
	var unaffordable_option := _payment_option(map)
	_expect(unaffordable_option != -1 and (map.hud.dialog_panel.option_list.get_child(unaffordable_option) as Button).disabled, "a payment option should disable once the player lacks its coins", failures)
	if map._dialog_session.is_active():
		map._dialog_session.cancel()
		map.hud.dialog_panel.close()


## The whole camp stands down, not just the bandit who was spoken to -- the
## encounter is the social unit.
func _test_persuasion_can_pacify_the_camp(map: CompiledMapController, failures: Array[String]) -> void:
	var talker_id := _negotiator(map)
	if talker_id == -1 or not map._dialog_session.is_active():
		failures.append("could not open the negotiation to test its peaceful ending")
		return
	for actor_id in map.hostile_views:
		var command := Command.create(&"set_disposition", int(actor_id))
		command.metadata = {"disposition": &"hostile"}
		map.session.submit_command(command)
	# Drive the authored persuasion option and force the roll to succeed, so the
	# assertion is about the outcome wiring rather than about the dice.
	var check_option := _first_check_option(map)
	_expect(check_option != -1, "the authored greeting should offer a check to talk past the camp", failures)
	if check_option == -1:
		return
	map._dialog_session.resolve_check(check_option, true)
	# A passed check leads to the bandit's reply, not straight to the outcome.
	# Walk the remaining single-option nodes the way a player clicking through
	# them would, so the test follows the authored graph rather than assuming
	# its shape.
	var steps := 0
	while map._dialog_session.is_active() and steps < 8:
		map._dialog_session.choose(0)
		steps += 1
	await get_tree().process_frame
	_expect(steps > 0 and not map._dialog_session.is_active(), "the peaceful branch should reach an ending", failures)
	for actor_id in map.hostile_views:
		var actor := map.battle_state.actors[int(actor_id)] as ActorState
		_expect(actor.disposition == &"neutral", "a successful check should stand the whole camp down, not just the speaker", failures)
	_expect(not map.hud.dialog_panel.visible, "the panel should close once the conversation reaches an ending", failures)
	map._check_hostile_detection()
	_expect(map.battle_state.phase == &"exploration", "a pacified camp must let the player walk through", failures)


func _test_drawing_starts_the_encounter(map: CompiledMapController, failures: Array[String]) -> void:
	var talker_id := _talker(map)
	if talker_id == -1:
		return
	if not _open_dialog(map, talker_id):
		failures.append("could not reopen the conversation to test its violent ending")
		return
	map._on_dialog_finished(DialogSessionScript.EFFECT_START_COMBAT)
	_expect(map.battle_state.phase != &"exploration", "choosing to draw should start the encounter", failures)
	_expect(not map.battle_state.active_encounter_id.is_empty(), "combat started from a dialog should be scoped to the authored encounter", failures)
	for actor_id in map.hostile_views:
		_expect((map.battle_state.actors[int(actor_id)] as ActorState).disposition == &"hostile", "drawing should make the whole camp hostile again", failures)


func _first_check_option(map: CompiledMapController) -> int:
	var index := 0
	for button in map.hud.dialog_panel.option_list.get_children():
		if (button as Button).text.begins_with("["):
			return index
		index += 1
	return -1


func _payment_option(map: CompiledMapController) -> int:
	var index := 0
	for button in map.hud.dialog_panel.option_list.get_children():
		if (button as Button).text.contains("Pay 10 coins"):
			return index
		index += 1
	return -1


func _unique(values: Array[StringName]) -> Array[StringName]:
	var seen: Array[StringName] = []
	for value in values:
		if not seen.has(value):
			seen.append(value)
	return seen


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
