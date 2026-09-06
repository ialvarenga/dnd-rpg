class_name TestHudBinding
extends Node

## Verifies the HUD as a session-bound presentation read model.  It observes
## session signals and emits intent signals only; commands remain the owning
## controller's responsibility.

func run() -> Dictionary:
	var failures: Array[String] = []
	var state := TestHelpers.make_battle()
	state.actors[1] = ActorState.from_definition(DefinitionLibrary.get_default().get_actor(&"knight"), 1, &"heroes", Vector3.ZERO)
	var session := EncounterSession.new()
	session.configure(state, FakeNavProvider.new(), FakeLosProvider.new())
	var hud := preload("res://scenes/ui/hud_root.tscn").instantiate() as HudRoot
	get_tree().root.add_child(hud)
	await get_tree().process_frame
	hud.bind(session, 1)

	_test_initial_binding(hud, failures)
	_test_input_intents(hud, failures)
	_test_session_synchronization(session, hud, state, failures)
	hud.queue_free()
	return {"name": "integration/test_hud_binding", "failures": failures}


func _test_initial_binding(hud: HudRoot, failures: Array[String]) -> void:
	var hp_label: Label = hud.get_node("Margin/Layout/ActorPortrait/Margin/Rows/HPText")
	_expect(hp_label.text == "HP 20/20", "HUD bind did not project actor health", failures)
	_expect(hud.hotbar.get_child_count() == 3, "HUD bind did not project the knight's ordered abilities", failures)
	var end_turn: Button = hud.get_node("Margin/Layout/EndTurn")
	_expect(hud.hotbar.mouse_filter == Control.MOUSE_FILTER_IGNORE, "empty hotbar space should remain pass-through", failures)
	_expect(end_turn.mouse_filter == Control.MOUSE_FILTER_STOP, "end-turn button must consume pointer input", failures)
	_expect(end_turn.get_theme_constant(&"icon_max_width") == 28, "end-turn icon size was not constrained", failures)
	for button in hud.hotbar.get_children():
		_expect((button as Control).mouse_filter == Control.MOUSE_FILTER_STOP, "hotbar button must consume pointer input", failures)
		_expect((button as Button).get_theme_constant(&"icon_max_width") == 28, "hotbar icon size was not constrained", failures)
	hud.set_selected_ability(&"basic_attack")
	_expect((hud.hotbar.get_child(0) as AbilityButton).button_pressed and not (hud.hotbar.get_child(1) as AbilityButton).button_pressed, "HUD did not keep only the selected action visually pressed", failures)
	hud.set_selected_ability(&"")
	_expect(not (hud.hotbar.get_child(0) as AbilityButton).button_pressed, "HUD did not clear selected action styling", failures)


func _test_input_intents(hud: HudRoot, failures: Array[String]) -> void:
	var ability_requests: Array[StringName] = []
	var end_turn_requests := [0]
	var cancel_requests := [0]
	hud.ability_requested.connect(func(ability_id: StringName): ability_requests.append(ability_id))
	hud.end_turn_requested.connect(func(): end_turn_requests[0] += 1)
	hud.cancel_requested.connect(func(): cancel_requests[0] += 1)
	var first_button := hud.hotbar.get_child(0) as AbilityButton
	first_button.disabled = false
	_send_action(hud, &"hotbar_1")
	_send_action(hud, &"tactical_end_turn")
	_send_action(hud, &"tactical_cancel")
	_expect(ability_requests == [&"basic_attack"], "hotbar shortcut did not emit the selected ability intent", failures)
	_expect(end_turn_requests[0] == 1, "end-turn shortcut did not emit its presentation intent", failures)
	_expect(cancel_requests[0] == 1, "cancel shortcut did not emit its presentation intent", failures)


func _test_session_synchronization(session: EncounterSession, hud: HudRoot, state: BattleState, failures: Array[String]) -> void:
	var result := session.submit_ability(1, &"dash", -1, Vector3.INF)
	_expect(not result.events.is_empty() and result.events[0].type == &"action_spent", "session did not resolve dash through Resolver", failures)
	_expect(not (state.actors[1] as ActorState).action_available, "dash result was not applied before HUD synchronization", failures)
	var dash_button := hud.hotbar.get_child(1) as AbilityButton
	_expect(dash_button.disabled, "HUD did not synchronize action availability after session state_changed", failures)


func _send_action(hud: HudRoot, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	hud._unhandled_input(event)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
