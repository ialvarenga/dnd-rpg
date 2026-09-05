class_name FloatingCombatText
extends Label

func show_event(event: Event) -> void:
	if event.type == &"damage_taken": text = "-%d" % int(event.data.get("amount", 0))
	elif event.type == &"attack_rolled": text = "HIT" if event.data.get("hit", false) else "MISS"
	else: text = ""
