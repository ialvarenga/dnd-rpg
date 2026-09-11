class_name HudRoot
extends CanvasLayer

const OutcomeOverlayScript = preload("res://view/ui/outcome_overlay.gd")
const DialogPanelScript = preload("res://view/ui/dialog_panel.gd")
const CharacterSheetScript = preload("res://view/ui/character_sheet.gd")
const CharacterSheetViewModelScript = preload("res://view/ui/character_sheet_view_model.gd")

## Presentation adapter. It listens to the shared session but never submits a
## command itself; the owning world controller decides targets and calls it.
signal ability_requested(ability_id: StringName)
signal end_turn_requested
signal cancel_requested
signal inventory_item_requested(item_id: StringName)
signal retry_requested
signal restart_requested
signal quicksave_requested
signal quickload_requested
signal world_pause_changed(paused: bool)

## DefinitionLibrary is a RefCounted catalog, not an inspector Resource.
## Controllers may inject it at runtime; otherwise _ready() uses the default.
var definitions: DefinitionLibrary
var session: EncounterSession
var actor_id := -1

@onready var portrait: ActorPortrait = $Margin/Layout/ActorPortrait
@onready var resources: ResourcePips = $Margin/Layout/ResourcePips
@onready var hotbar: AbilityHotbar = $Margin/Layout/HotbarPanel/PanelMargin/Rows/Groups/AbilityHotbar
@onready var turns: TurnOrderBar = $Margin/TopBar/TurnOrder
@onready var conditions: ConditionStrip = $Margin/TopBar/Conditions
@onready var combat_log: CombatLog = $CombatLog
@onready var tooltip_layer: TooltipLayer = $TooltipLayer
@onready var item_slots: GridContainer = $Margin/Layout/HotbarPanel/PanelMargin/Rows/Groups/ItemSlots
@onready var outcome_overlay: OutcomeOverlayScript = $OutcomeOverlay
@onready var objective_label: Label = $Margin/TopBar/ObjectiveLabel
@onready var coins_label: Label = $Margin/TopBar/CoinsLabel
@onready var dialog_panel: DialogPanelScript = $DialogPanel
@onready var pause_menu: Control = $PauseMenu
@onready var character_sheet: CharacterSheetScript = $CharacterSheet

func _ready() -> void:
	definitions = definitions if definitions != null else DefinitionLibrary.get_default()
	hotbar.ability_requested.connect(func(id): ability_requested.emit(id))
	$Margin/Layout/EndTurn.icon = hotbar.icon_set.texture_for(&"end_turn") if hotbar.icon_set != null else null
	$Margin/Layout/EndTurn.pressed.connect(func(): end_turn_requested.emit())
	$Margin/Layout/Settings.disabled = false
	$Margin/Layout/Settings.pressed.connect(_toggle_pause_menu)
	$Margin/Layout/Character.pressed.connect(func(): toggle_character_sheet(CharacterSheetScript.TAB_STATS))
	$PauseMenu/Panel/Rows/Resume.pressed.connect(func(): _set_pause_menu_visible(false))
	$PauseMenu/Panel/Rows/QuickSave.pressed.connect(func(): quicksave_requested.emit())
	$PauseMenu/Panel/Rows/QuickLoad.pressed.connect(func(): quickload_requested.emit())
	outcome_overlay.retry_requested.connect(func(): retry_requested.emit())
	outcome_overlay.restart_requested.connect(func(): restart_requested.emit())
	character_sheet.item_use_requested.connect(func(item_id): inventory_item_requested.emit(item_id))
	character_sheet.closed.connect(func(): world_pause_changed.emit(is_world_paused()))
	dialog_panel.visibility_changed.connect(_close_sheet_for_other_modal)
	outcome_overlay.visibility_changed.connect(_close_sheet_for_other_modal)

func bind(next_session: EncounterSession, next_actor_id: int) -> void:
	if session != null:
		if session.state_changed.is_connected(sync): session.state_changed.disconnect(sync)
		if session.events_resolved.is_connected(_on_events_resolved): session.events_resolved.disconnect(_on_events_resolved)
	session = next_session
	actor_id = next_actor_id
	if session != null:
		session.state_changed.connect(sync)
		session.events_resolved.connect(_on_events_resolved)
	sync()

func sync() -> void:
	if session == null or session.battle_state == null: return
	var data := HudViewModel.for_actor(session.battle_state, actor_id, definitions, session.available_actions(actor_id))
	if data.is_empty(): return
	portrait.set_actor(data)
	resources.set_resources(data)
	hotbar.set_actions(data.action_availability)
	turns.set_turn_order(HudViewModel.turn_order(session.battle_state, definitions))
	conditions.set_conditions(data.conditions)
	objective_label.text = "OBJECTIVE: %s" % HudViewModel.objective_prompt(session.battle_state)
	coins_label.text = "COINS: %d" % int(data.get("coins", 0))
	_sync_inventory(session.battle_state.actors[actor_id] as ActorState)
	if character_sheet.visible:
		character_sheet.present(CharacterSheetViewModelScript.for_actor(session.battle_state, actor_id, definitions))


func _sync_inventory(actor: ActorState) -> void:
	var stacks: Array[Dictionary] = CharacterSheetViewModelScript.inventory_stacks(session.battle_state, actor.id, definitions)
	var index := 0
	for stack in stacks:
		if index >= item_slots.get_child_count():
			break
		var button := item_slots.get_child(index) as Button
		var item_id := StringName(stack["item_id"])
		button.disabled = false
		button.text = "×%d" % int(stack["count"])
		button.icon = hotbar.icon_set.texture_for(StringName(str(item_id))) if hotbar.icon_set != null else null
		button.tooltip_text = _inventory_tooltip(actor, StringName(str(item_id)))
		button.set_meta("item_id", item_id)
		if not button.gui_input.is_connected(_on_item_slot_gui_input):
			button.gui_input.connect(_on_item_slot_gui_input.bind(button))
		index += 1
	for empty_index in range(index, item_slots.get_child_count()):
		var empty_button := item_slots.get_child(empty_index) as Button
		empty_button.disabled = true
		empty_button.text = ""
		empty_button.icon = null
		empty_button.tooltip_text = "No item"
		empty_button.remove_meta("item_id")


func _inventory_tooltip(actor: ActorState, item_id: StringName) -> String:
	var instruction := "Double-click to use"
	var item := definitions.get_item(item_id) if definitions != null else null
	if item == null or item.use_ability_id == &"" or session == null or session.battle_state == null:
		return instruction
	var availability := ActionAvailability.evaluate(session.battle_state, actor.id, item.use_ability_id, definitions)
	var presentation := HudViewModel.action_presentation(actor, availability, definitions)
	return "%s\n\n%s" % [String(presentation.get("tooltip", "")), instruction]


func _on_item_slot_gui_input(event: InputEvent, button: Button) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click and button.has_meta("item_id"):
		inventory_item_requested.emit(StringName(str(button.get_meta("item_id"))))
		get_viewport().set_input_as_handled()


## Events are applied before EncounterSession emits this signal, so narration
## remains a projection of authoritative state rather than a second rule path.
func _on_events_resolved(events: Array[Event]) -> void:
	if session == null or session.battle_state == null:
		return
	for event in events:
		combat_log.append_line(HudViewModel.narrate(event, session.battle_state, definitions))
		if event.type == &"game_over":
			present_outcome(&"defeat")


func set_selected_ability(ability_id: StringName) -> void:
	hotbar.set_selected_ability(ability_id)


func present_outcome(outcome: StringName) -> void:
	outcome_overlay.present(outcome)


func reset_outcome() -> void:
	outcome_overlay.reset()
	sync()


func is_pause_menu_open() -> bool:
	return pause_menu.visible


func is_world_paused() -> bool:
	return pause_menu.visible or character_sheet.visible


func toggle_character_sheet(tab: int) -> void:
	if outcome_overlay.visible or dialog_panel.visible or pause_menu.visible:
		return
	if character_sheet.visible:
		if character_sheet.current_tab() == tab:
			close_character_sheet()
		else:
			character_sheet.show_tab(tab)
		return
	if session == null or session.battle_state == null:
		return
	character_sheet.present(CharacterSheetViewModelScript.for_actor(session.battle_state, actor_id, definitions))
	character_sheet.open(tab)
	world_pause_changed.emit(true)


func close_character_sheet() -> void:
	character_sheet.close()


func _toggle_pause_menu() -> void:
	_set_pause_menu_visible(not pause_menu.visible)


func _set_pause_menu_visible(visible: bool) -> void:
	pause_menu.visible = visible
	world_pause_changed.emit(is_world_paused())
	if visible:
		combat_log.append_line("Game paused.")


func _close_sheet_for_other_modal() -> void:
	if dialog_panel.visible or outcome_overlay.visible:
		close_character_sheet()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F5:
			quicksave_requested.emit()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F9:
			quickload_requested.emit()
			get_viewport().set_input_as_handled()
			return
	if character_sheet.visible:
		if event.is_action_pressed(&"tactical_cancel"):
			close_character_sheet()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"hud_character_sheet"):
			toggle_character_sheet(CharacterSheetScript.TAB_STATS)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"hud_inventory"):
			toggle_character_sheet(CharacterSheetScript.TAB_INVENTORY)
			get_viewport().set_input_as_handled()
			return
		# The sheet is a modal: no hotbar/end-turn/cancel intent may leak to the
		# world while it owns the screen.
		return
	if outcome_overlay.visible or dialog_panel.visible or pause_menu.visible:
		return
	if event.is_action_pressed(&"hud_character_sheet"):
		toggle_character_sheet(CharacterSheetScript.TAB_STATS)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"hud_inventory"):
		toggle_character_sheet(CharacterSheetScript.TAB_INVENTORY)
		get_viewport().set_input_as_handled()
		return
	for slot in range(6):
		if event.is_action_pressed(StringName("hotbar_%d" % (slot + 1))):
			hotbar.request_slot(slot)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"tactical_end_turn"):
		end_turn_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"tactical_cancel"):
		cancel_requested.emit()
		get_viewport().set_input_as_handled()
