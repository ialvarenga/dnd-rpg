class_name TurnOrderBar
extends HBoxContainer

func set_turn_order(order: Array[Dictionary]) -> void:
	for child in get_children(): child.queue_free()
	for entry in order:
		var label := Label.new()
		label.text = String(entry.name)
		label.tooltip_text = "Current turn" if entry.is_current else "Initiative %d" % (int(entry.index) + 1)
		if entry.is_current: label.modulate = Color("ffd45c")
		add_child(label)
