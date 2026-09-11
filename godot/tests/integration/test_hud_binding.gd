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
	_expect(hp_label.text == "HP 30/30", "HUD bind did not project actor health", failures)
	# Seven is also the hotbar's hard cap (AbilityHotbar._actions is clamped to 7),
	# so this doubles as the guard against a loadout that would silently truncate.
	_expect(hud.hotbar.get_child_count() == 7, "HUD hotbar should contain the knight's seven combat actions, without contextual Talk or inventory consumables", failures)
	_expect(_ability_button(hud, &"talk") == null, "contextual Talk action appeared in the persistent hotbar", failures)
	var end_turn: Button = hud.get_node("Margin/Layout/EndTurn")
	_expect(hud.hotbar.mouse_filter == Control.MOUSE_FILTER_IGNORE, "empty hotbar space should remain pass-through", failures)
	_expect(end_turn.mouse_filter == Control.MOUSE_FILTER_STOP, "end-turn button must consume pointer input", failures)
	_expect(end_turn.get_theme_constant(&"icon_max_width") == 28, "end-turn icon size was not constrained", failures)
	_expect(end_turn.icon_alignment == HORIZONTAL_ALIGNMENT_CENTER, "end-turn icon was not centered in its button", failures)
	_expect(hud.hotbar.columns == 5, "common skills should be laid out in a five-column grid", failures)
	for button in hud.hotbar.get_children():
		_expect((button as Control).mouse_filter == Control.MOUSE_FILTER_STOP, "hotbar button must consume pointer input", failures)
		_expect((button as Button).get_theme_constant(&"icon_max_width") == 24, "hotbar icon size was not constrained", failures)
		_expect((button as Button).icon_alignment == HORIZONTAL_ALIGNMENT_CENTER, "hotbar icon was not centered in its button", failures)
	var attack_button := _ability_button(hud, &"basic_attack")
	_expect(attack_button.tooltip_text.contains("Make a melee weapon attack") and attack_button.tooltip_text.contains("Damage 1d8 + 2 slashing"), "hotbar button did not receive the authored description and live equipment mechanics", failures)
	var help_button := _ability_button(hud, &"help")
	_expect(help_button != null and help_button.tooltip_text.contains("Aid an ally's next attack") and help_button.tooltip_text.contains("Target: ally") and help_button.tooltip_text.contains("next attack has Advantage"), "Help button did not receive its authored tooltip mechanics", failures)
	var potion_slot: Button = hud.get_node("Margin/Layout/HotbarPanel/PanelMargin/Rows/Groups/ItemSlots/ItemSlot1")
	var spell_slot: Button = hud.get_node("Margin/Layout/HotbarPanel/PanelMargin/Rows/Groups/SpellSlots/Slot1")
	_expect(spell_slot.size == Vector2(48, 48) and potion_slot.size == Vector2(48, 48), "class-specific and inventory slots should match the common skill size", failures)
	_expect(hud.get_node("Margin/Layout/HotbarPanel/PanelMargin/Rows/Groups/ItemSlots").columns == 3, "inventory should use a three-column grid", failures)
	_expect(hud.get_node("Margin/Layout/HotbarPanel/PanelMargin/Rows/Groups/ItemSlots").get_child_count() == 6, "inventory should provide a two-by-three grid", failures)
	var character_button: Button = hud.get_node("Margin/Layout/MovementControls/Character")
	var settings_button: Button = hud.get_node("Margin/TopRightControls/Settings")
	_expect(character_button.size == Vector2(28, 28) and settings_button.size == Vector2(32, 32), "character and settings controls should use compact circles", failures)
	_expect(character_button.icon != null and character_button.get_theme_constant(&"icon_max_width") == 14 and settings_button.icon != null and settings_button.get_theme_constant(&"icon_max_width") == 18, "character and settings controls should use appropriately sized icons", failures)
	_expect(hud.get_node("Margin/Layout/MovementControls/Character").get_parent().get_node("ResourcePips").get_index() > hud.get_node("Margin/Layout/MovementControls/Character").get_index(), "character info control should sit above the movement bar", failures)
	_expect(potion_slot.icon == hud.hotbar.icon_set.texture_for(&"healing_potion"), "inventory slot did not receive the mapped item icon", failures)
	_expect(potion_slot.expand_icon and potion_slot.get_theme_constant(&"icon_max_width") == 24, "inventory icon was not constrained to the common skill icon size", failures)
	_expect(potion_slot.text == "×1", "inventory slot should show only its compact stack count beside the icon", failures)
	_expect(potion_slot.tooltip_text.contains("Drink a healing potion") and potion_slot.tooltip_text.contains("Heal 2d4 + 2 HP") and potion_slot.tooltip_text.contains("Double-click to use"), "inventory slot did not reuse the potion action tooltip", failures)
	for button in hud.hotbar.get_children():
		_expect((button as Button).icon != null, "visible hotbar action is missing its mapped icon", failures)
	for item_id in hud.definitions.ordered_item_ids():
		_expect(hud.hotbar.icon_set.texture_for(item_id) != null, "HUD icon set omitted item '%s'" % item_id, failures)
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
	var dash_button := _ability_button(hud, &"dash")
	_expect(dash_button.disabled, "HUD did not synchronize action availability after session state_changed", failures)
	_expect(dash_button.tooltip_text.contains("Gain extra movement") and dash_button.tooltip_text.contains("Unavailable: Action already used this turn."), "disabled hotbar tooltip did not preserve the description and append a readable reason", failures)
	_expect(hud.combat_log.get_parsed_text().contains("Knight uses an action."), "HUD did not narrate resolved events in the combat log", failures)


func _send_action(hud: HudRoot, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	hud._unhandled_input(event)


func _ability_button(hud: HudRoot, ability_id: StringName) -> AbilityButton:
	for child in hud.hotbar.get_children():
		var button := child as AbilityButton
		if button != null and button.ability_id == ability_id:
			return button
	return null


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
