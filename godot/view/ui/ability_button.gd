class_name AbilityButton
extends Button

signal ability_pressed(ability_id: StringName)
var ability_id: StringName

func configure(data: Dictionary, slot: int) -> void:
	ability_id = StringName(data.get("ability_id", ""))
	text = "%d: %s" % [slot + 1, String(ability_id).replace("_", " ").capitalize()]
	disabled = not data.get("available", false)
	tooltip_text = String(data.get("reason", "")) if disabled else String(ability_id)
	shortcut = Shortcut.new()
	var input := InputEventAction.new()
	input.action = StringName("hotbar_%d" % (slot + 1))
	shortcut.events = [input]

func _ready() -> void:
	pressed.connect(func(): ability_pressed.emit(ability_id))
