class_name ResourcePips
extends HBoxContainer

func set_resources(data: Dictionary) -> void:
	$Move.value = float(data.get("movement_fraction", 0.0)) * 100.0
	$Move.tooltip_text = "Movement budget ignored in exploration" if data.get("movement_budget_ignored", false) else "%.1f / %.1f movement" % [data.get("movement_remaining", 0.0), data.get("movement_speed", 0.0)]
