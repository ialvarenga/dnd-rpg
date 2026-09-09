class_name OutcomeOverlay
extends Control

signal retry_requested
signal restart_requested

@onready var title_label: Label = $Shade/Center/Panel/Margin/Rows/Title
@onready var detail_label: Label = $Shade/Center/Panel/Margin/Rows/Detail
@onready var action_button: Button = $Shade/Center/Panel/Margin/Rows/Action

var outcome: StringName = &"none"


func _ready() -> void:
	action_button.pressed.connect(_on_action_pressed)
	hide()


func present(next_outcome: StringName) -> void:
	outcome = next_outcome
	if outcome == &"defeat":
		title_label.text = "DEFEATED"
		detail_label.text = "The encounter has ended. Return to its opening moment and try a different tactic."
		action_button.text = "Retry Encounter"
	else:
		title_label.text = "ADVENTURE COMPLETE"
		detail_label.text = "Emberwatch is clear and the objective has been reached."
		action_button.text = "Restart Map"
	show()
	action_button.grab_focus()


func reset() -> void:
	outcome = &"none"
	hide()


func _on_action_pressed() -> void:
	if outcome == &"defeat":
		retry_requested.emit()
	else:
		restart_requested.emit()
