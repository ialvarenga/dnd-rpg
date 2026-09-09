class_name DialogPanel
extends Control

## Presentation for one DialogSession view dictionary. It renders whatever it
## is handed and reports which button was pressed; it never reads BattleState,
## never walks the graph, and never decides an outcome.

signal option_chosen(option_index: int)
signal dismissed

const CHECK_LABEL_COLOR := Color(0.62, 0.82, 0.98)

@onready var speaker_label: Label = $Shade/Anchor/Panel/Margin/Rows/Speaker
@onready var text_label: Label = $Shade/Anchor/Panel/Margin/Rows/Body
@onready var option_list: VBoxContainer = $Shade/Anchor/Panel/Margin/Rows/Options
@onready var roll_label: Label = $Shade/Anchor/Panel/Margin/Rows/Roll


func _ready() -> void:
	hide()


func present(view: Dictionary) -> void:
	speaker_label.text = str(view.get("speaker", ""))
	text_label.text = str(view.get("text", ""))
	roll_label.text = ""
	roll_label.hide()
	_rebuild_options(view.get("options", []))
	show()


## Shown between choosing a check option and the outcome landing, so the player
## sees the number the simulation actually rolled rather than only its result.
func present_check(skill: StringName, difficulty_class: int, total: int, success: bool) -> void:
	var label := String(skill).replace("_", " ").capitalize() if String(skill) != "" else "Check"
	roll_label.text = "%s: rolled %d vs DC %d — %s" % [label, total, difficulty_class, "success" if success else "failure"]
	roll_label.show()
	for button in option_list.get_children():
		(button as Button).disabled = true


func close() -> void:
	hide()
	_clear_options()


func _rebuild_options(options: Array) -> void:
	_clear_options()
	for option in options:
		var button := Button.new()
		button.text = _option_text(option)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 34)
		var check: Dictionary = option.get("check", {})
		if not check.is_empty():
			button.add_theme_color_override(&"font_color", CHECK_LABEL_COLOR)
		var index := int(option.get("index", 0))
		button.pressed.connect(func() -> void: option_chosen.emit(index))
		option_list.add_child(button)
	if not option_list.get_children().is_empty():
		(option_list.get_child(0) as Button).grab_focus()


## A check option advertises its skill and DC up front, so choosing it is an
## informed gamble rather than a hidden dice roll.
func _option_text(option: Dictionary) -> String:
	var text := str(option.get("text", ""))
	var check: Dictionary = option.get("check", {})
	if check.is_empty():
		return text
	var skill := String(check.get("skill", ""))
	var label := skill.replace("_", " ").capitalize() if not skill.is_empty() else String(check.get("ability", "")).capitalize()
	return "[%s DC %d] %s" % [label, int(check.get("dc", 0)), text]


func _clear_options() -> void:
	for child in option_list.get_children():
		option_list.remove_child(child)
		child.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"tactical_cancel"):
		dismissed.emit()
		get_viewport().set_input_as_handled()
