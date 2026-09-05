class_name ConditionStrip
extends HBoxContainer

func set_conditions(conditions: Array) -> void:
	for child in get_children(): child.queue_free()
	for condition in conditions:
		var icon := Label.new()
		icon.text = String(condition).left(1).to_upper()
		icon.tooltip_text = String(condition).replace("_", " ").capitalize()
		add_child(icon)
