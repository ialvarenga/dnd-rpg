class_name TurnOrderBar
extends HBoxContainer

const CURRENT_TURN_COLOR := Color("ffd45c")

func set_turn_order(order: Array[Dictionary]) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for entry in order:
		add_child(_make_turn_card(entry))


func _make_turn_card(entry: Dictionary) -> PanelContainer:
	var is_current := bool(entry.get("is_current", false))
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(116, 62)
	card.tooltip_text = "Current turn: %s" % entry.get("name", "") if is_current else "Initiative %d: %s" % [int(entry.get("index", 0)) + 1, entry.get("name", "")]
	card.add_theme_stylebox_override("panel", _card_style(is_current))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 9)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 9)
	margin.add_theme_constant_override("margin_bottom", 6)
	card.add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 3)
	margin.add_child(rows)

	var name := Label.new()
	name.text = String(entry.get("name", "Unknown"))
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.add_theme_font_size_override("font_size", 13)
	name.add_theme_color_override("font_color", CURRENT_TURN_COLOR if is_current else Color("f4ead2"))
	rows.add_child(name)

	var health := ProgressBar.new()
	health.custom_minimum_size = Vector2(0, 7)
	health.show_percentage = false
	health.value = float(entry.get("hp_fraction", 0.0)) * 100.0
	health.theme_type_variation = &"HpBar"
	rows.add_child(health)

	var status := Label.new()
	status.text = "ATTACKING" if is_current else "INIT. %d" % (int(entry.get("index", 0)) + 1)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 10)
	status.add_theme_color_override("font_color", CURRENT_TURN_COLOR if is_current else Color("b9aa90"))
	rows.add_child(status)
	return card


func _card_style(is_current: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("241d16e8")
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = CURRENT_TURN_COLOR if is_current else Color("715a35")
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_right = 7
	style.corner_radius_bottom_left = 7
	return style
