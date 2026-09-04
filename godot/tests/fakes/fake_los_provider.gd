class_name FakeLosProvider
extends LosProvider

var blocked_pairs: Dictionary = {}


func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	return not blocked_pairs.has(_key(from, to))


func block(from: Vector3, to: Vector3) -> void:
	blocked_pairs[_key(from, to)] = true


func _key(from: Vector3, to: Vector3) -> String:
	return "%s>%s" % [from, to]

