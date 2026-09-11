class_name CharacterSheet
extends Control

const TAB_STATS := 0
const TAB_EQUIPMENT := 1
const TAB_INVENTORY := 2
const InventorySlotScene = preload("res://view/ui/inventory_slot_button.tscn")

signal item_use_requested(item_id: StringName)
signal closed

@export var icon_set: IconSet
var _tab := TAB_STATS
var _selected_item_id: StringName = &""
var _view: Dictionary = {}

@onready var tab_buttons: Array[Button] = [$Shade/Anchor/Panel/Margin/Rows/Tabs/Stats, $Shade/Anchor/Panel/Margin/Rows/Tabs/Equipment, $Shade/Anchor/Panel/Margin/Rows/Tabs/Inventory]
@onready var pages: Array[Control] = [$Shade/Anchor/Panel/Margin/Rows/Pages/StatsPage, $Shade/Anchor/Panel/Margin/Rows/Pages/EquipmentPage, $Shade/Anchor/Panel/Margin/Rows/Pages/InventoryPage]
@onready var inventory_grid: GridContainer = $Shade/Anchor/Panel/Margin/Rows/Pages/InventoryPage/Body/Grid
@onready var detail: VBoxContainer = $Shade/Anchor/Panel/Margin/Rows/Pages/InventoryPage/Body/Detail


func _ready() -> void:
	visible = false
	for index in tab_buttons.size():
		tab_buttons[index].focus_mode = Control.FOCUS_NONE
		tab_buttons[index].pressed.connect(func(): show_tab(index))
	$Shade/Anchor/Panel/Margin/Rows/Header/Close.focus_mode = Control.FOCUS_NONE
	$Shade/Anchor/Panel/Margin/Rows/Header/Close.pressed.connect(close)
	$Shade.gui_input.connect(_on_shade_input)
	$Shade/Anchor/Panel/Margin/Rows/Pages/InventoryPage/Body/Detail/Use.focus_mode = Control.FOCUS_NONE
	$Shade/Anchor/Panel/Margin/Rows/Pages/InventoryPage/Body/Detail/Use.pressed.connect(_use_selected)


func present(view: Dictionary) -> void:
	_view = view
	if view.is_empty():
		return
	var header: Dictionary = view.get("header", {})
	$Shade/Anchor/Panel/Margin/Rows/Header/Name.text = String(header.get("name", "Character")).to_upper()
	$Shade/Anchor/Panel/Margin/Rows/Header/HP.text = "HP %d/%d" % [int(header.get("hp", 0)), int(header.get("max_hp", 0))]
	$Shade/Anchor/Panel/Margin/Rows/Header/HPBar.value = float(header.get("hp_fraction", 0.0)) * 100.0
	$Shade/Anchor/Panel/Margin/Rows/Header/AC.text = "AC %d" % int(header.get("armor_class", 0))
	$Shade/Anchor/Panel/Margin/Rows/Header/Coins.text = "◎ %d" % int(header.get("coins", 0))
	_render_stats(view.get("stats", {}))
	_render_equipment(view.get("equipment", {}))
	_render_inventory(view.get("inventory", {}))
	show_tab(_tab)


func open(tab: int) -> void:
	visible = true
	show_tab(tab)


func show_tab(tab: int) -> void:
	_tab = clampi(tab, TAB_STATS, TAB_INVENTORY)
	for index in pages.size():
		pages[index].visible = index == _tab
		tab_buttons[index].set_pressed_no_signal(index == _tab)


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func current_tab() -> int:
	return _tab


func _render_stats(stats: Dictionary) -> void:
	var cards := $Shade/Anchor/Panel/Margin/Rows/Pages/StatsPage/Body/Abilities as GridContainer
	_clear(cards)
	for ability in stats.get("abilities", []):
		var card := _card("%s\n%s  (%d)\n%s Save %s\n%s" % [ability["abbr"], ability["modifier_text"], ability["score"], "●" if ability["save_proficient"] else "○", ability["save_text"], ", ".join(ability["skills"])], Vector2(145, 130))
		cards.add_child(card)
	var derived := $Shade/Anchor/Panel/Margin/Rows/Pages/StatsPage/Body/Derived as VBoxContainer
	_clear(derived)
	for entry in stats.get("derived", []):
		var label := Label.new()
		label.text = "%s  %s" % [entry["label"], entry["value"]]
		label.tooltip_text = String(entry.get("detail", ""))
		derived.add_child(label)
	for use in stats.get("limited_uses", []):
		derived.add_child(_label("%s  %s" % [use["name"], use["text"]]))
	var condition_names: Array[String] = []
	for condition in stats.get("conditions", []): condition_names.append(String(condition["name"]))
	derived.add_child(_label("Conditions  %s" % [", ".join(condition_names) if not condition_names.is_empty() else "—"]))


func _render_equipment(equipment: Dictionary) -> void:
	var slots := $Shade/Anchor/Panel/Margin/Rows/Pages/EquipmentPage/Body/Slots as VBoxContainer
	_clear(slots)
	for slot in equipment.get("slots", []):
		slots.add_child(_card("%s · %s\n%s" % [String(slot["slot"]).to_upper(), slot["name"], " · ".join(slot["lines"])]))
	var combat: Dictionary = equipment.get("combat", {})
	$Shade/Anchor/Panel/Margin/Rows/Pages/EquipmentPage/Body/Combat.text = "COMBAT SUMMARY\nAttack  %s\nDamage  %s\nRange  %s\nAC  %d" % [combat.get("attack", "—"), combat.get("damage", "—"), combat.get("range", "—"), int(combat.get("armor_class", 0))]


func _render_inventory(inventory: Dictionary) -> void:
	_clear(inventory_grid)
	var stacks: Array = inventory.get("stacks", [])
	if _selected_item_id != &"":
		var exists := false
		for stack in stacks: exists = exists or StringName(stack["item_id"]) == _selected_item_id
		if not exists: _selected_item_id = &""
	if _selected_item_id == &"" and not stacks.is_empty(): _selected_item_id = StringName(stacks[0]["item_id"])
	for stack in stacks:
		var slot := InventorySlotScene.instantiate()
		inventory_grid.add_child(slot)
		slot.call("configure", stack, icon_set)
		slot.call("set_selected", StringName(stack["item_id"]) == _selected_item_id)
		slot.connect(&"selected", _select_item)
		slot.connect(&"activated", func(item_id): _selected_item_id = item_id; _use_selected())
	for _index in range(int(inventory.get("display_slots", 20)) - stacks.size()):
		var empty := InventorySlotScene.instantiate()
		inventory_grid.add_child(empty)
		empty.call("clear")
	_render_detail(stacks)


func _render_detail(stacks: Array) -> void:
	var title := detail.get_node("Title") as Label
	var body := detail.get_node("Body") as Label
	var use := detail.get_node("Use") as Button
	for stack in stacks:
		if StringName(stack["item_id"]) == _selected_item_id:
			title.text = "%s  %s" % [stack["name"], stack["kind"]]
			body.text = "%s\n%s\n%s" % [" · ".join(stack["lines"]), stack.get("description", ""), stack["unavailable_reason"]]
			use.disabled = not bool(stack["usable"]) or not bool(stack["available"])
			use.visible = bool(stack["usable"])
			return
	title.text = "Your pack is empty."
	body.text = "Select an item to see its details."
	use.visible = false


func _select_item(item_id: StringName) -> void:
	_selected_item_id = item_id
	_render_inventory(_view.get("inventory", {}))


func _use_selected() -> void:
	if _selected_item_id == &"": return
	for stack in _view.get("inventory", {}).get("stacks", []):
		if StringName(stack["item_id"]) == _selected_item_id and bool(stack["usable"]) and bool(stack["available"]):
			item_use_requested.emit(_selected_item_id)
			return


func _on_shade_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		close()


func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _card(text: String, minimum_size := Vector2(0, 0)) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = minimum_size
	panel.theme_type_variation = &"SheetCard"
	var label := _label(text)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
