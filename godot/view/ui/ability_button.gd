class_name AbilityButton
extends Button

signal ability_pressed(ability_id: StringName)
var ability_id: StringName

@onready var hotkey_label: Label = $Hotkey

func configure(data: Dictionary, slot: int, icon_set: IconSet) -> void:
	ability_id = StringName(data.get("ability_id", ""))
	text = ""
	hotkey_label.text = str(slot + 1)
	icon = icon_set.texture_for(ability_id) if icon_set != null else null
	disabled = not data.get("available", false)
	var display_name := String(ability_id).replace("_", " ").capitalize()
	tooltip_text = String(data.get("reason", "")) if disabled else display_name


func set_selected(selected: bool) -> void:
	button_pressed = selected

func _ready() -> void:
	pressed.connect(func(): ability_pressed.emit(ability_id))
