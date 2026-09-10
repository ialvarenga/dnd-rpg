class_name FloatingCombatText
extends Label3D

const LIFETIME_SECONDS := 1.1
const RISE_DISTANCE := 0.55

func show_event(event: Event) -> void:
	match event.type:
		&"damage_taken":
			text = "-%d" % int(event.data.get("amount", 0))
			modulate = Color("ef625d")
		&"healing_received":
			text = "+%d" % int(event.data.get("amount", 0))
			modulate = Color("76e887")
		&"item_consumed":
			text = "USED %s" % String(event.data.get("item_id", "item")).replace("_", " ").to_upper()
			modulate = Color("c9d3e6")
		&"actor_downed":
			text = "DOWNED"
			modulate = Color("efb35d")
		&"condition_added":
			text = "+%s" % _condition_name(event)
			modulate = Color("efb35d")
		&"condition_removed":
			text = "-%s" % _condition_name(event)
			modulate = Color("c9d3e6")
		&"command_rejected":
			text = "REJECTED: %s" % String(event.data.get("reason", "unavailable")).replace("_", " ")
			modulate = Color("ef625d")
		&"attack_rolled":
			text = "HIT" if event.data.get("hit", false) else "MISS"
			modulate = Color.WHITE
		&"d20_test_rolled":
			# A failed save is already told by its effect (e.g. "+PRONE").
			text = "RESISTED" if event.data.get("success", false) else ""
			modulate = Color("c9d3e6")
		_:
			text = ""
	if not text.is_empty():
		_play_lifetime()


func _condition_name(event: Event) -> String:
	return String(event.data.get("condition", "condition")).replace("_", " ").to_upper()


func _play_lifetime() -> void:
	var tween := create_tween()
	tween.tween_property(self, "position:y", position.y + RISE_DISTANCE, LIFETIME_SECONDS)
	tween.parallel().tween_property(self, "modulate:a", 0.0, LIFETIME_SECONDS)
	tween.tween_callback(queue_free)
