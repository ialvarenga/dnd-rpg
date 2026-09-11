class_name ResourcePips
extends HBoxContainer

func set_resources(data: Dictionary) -> void:
	$Move.value = float(data.get("movement_fraction", 0.0)) * 100.0
	$Move.tooltip_text = "Movement budget ignored in exploration" if data.get("movement_budget_ignored", false) else "%.1f / %.1f movement" % [data.get("movement_remaining", 0.0), data.get("movement_speed", 0.0)]


func set_movement_preview(cost: float, remaining: float, ignores_budget: bool) -> void:
	$Move.tooltip_text = "Path %.1f weighted movement (budget ignored in exploration)" % cost if ignores_budget else "Path costs %.1f weighted movement; %.1f remains" % [cost, remaining]
