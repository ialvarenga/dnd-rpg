class_name AbilityHotbar
extends GridContainer

signal ability_requested(ability_id: StringName)
const BUTTON_SCENE = preload("res://view/ui/ability_button.tscn")

@export var icon_set: IconSet
var _actions: Array[Dictionary] = []
var _selected_ability_id: StringName = &""

func set_actions(actions: Array[Dictionary]) -> void:
	_actions = actions.duplicate(true)
	# queue_free() alone keeps the outgoing buttons in the tree until the end of
	# the frame, so a caller reading the hotbar right after a rebuild would see
	# stale slots. Detach first, then free.
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for index in mini(_actions.size(), 8):
		var button: AbilityButton = BUTTON_SCENE.instantiate()
		add_child(button)
		button.configure(_actions[index], index, icon_set)
		button.set_selected(StringName(_actions[index].get("ability_id", "")) == _selected_ability_id)
		button.ability_pressed.connect(func(id): ability_requested.emit(id))


func set_selected_ability(ability_id: StringName) -> void:
	_selected_ability_id = ability_id
	for child in get_children():
		var button := child as AbilityButton
		if button != null:
			button.set_selected(button.ability_id == ability_id)


## Called by HudRoot so keyboard bindings remain a presentation concern rather
## than Button shortcuts that may outlive a rebuilt action bar.
func request_slot(slot: int) -> void:
	if slot < 0 or slot >= _actions.size() or slot >= get_child_count():
		return
	var button := get_child(slot) as AbilityButton
	if button == null or button.disabled:
		return
	ability_requested.emit(StringName(_actions[slot].get("ability_id", "")))
