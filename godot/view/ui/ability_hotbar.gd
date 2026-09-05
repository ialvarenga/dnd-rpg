class_name AbilityHotbar
extends HBoxContainer

signal ability_requested(ability_id: StringName)
const BUTTON_SCENE = preload("res://view/ui/ability_button.tscn")

func set_actions(actions: Array) -> void:
	for child in get_children(): child.queue_free()
	for index in mini(actions.size(), 6):
		var button: AbilityButton = BUTTON_SCENE.instantiate()
		add_child(button)
		button.configure(actions[index], index)
		button.ability_pressed.connect(func(id): ability_requested.emit(id))
