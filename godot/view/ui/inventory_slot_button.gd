class_name InventorySlotButton
extends Button

signal selected(item_id: StringName)
signal activated(item_id: StringName)

var item_id: StringName = &""
@onready var count_label: Label = $Count


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	pressed.connect(func():
		if item_id != &"":
			selected.emit(item_id)
	)
	gui_input.connect(_on_gui_input)


func configure(stack: Dictionary, icon_set: IconSet) -> void:
	item_id = StringName(stack.get("item_id", &""))
	icon = icon_set.texture_for(item_id) if icon_set != null else null
	count_label.text = "×%d" % int(stack.get("count", 1)) if int(stack.get("count", 1)) > 1 else ""
	tooltip_text = String(stack.get("name", "Item"))
	disabled = false


func clear() -> void:
	item_id = &""
	icon = null
	count_label.text = ""
	tooltip_text = "Empty slot"
	disabled = true


func set_selected(is_selected: bool) -> void:
	button_pressed = is_selected


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click and item_id != &"":
		activated.emit(item_id)
		get_viewport().set_input_as_handled()
