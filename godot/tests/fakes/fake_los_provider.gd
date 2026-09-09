class_name FakeLosProvider
extends LosProvider

var blocked_pairs: Dictionary = {}
var covered_pairs: Dictionary = {}


func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	return cover_between(from, to) != COVER_TOTAL


func cover_between(from: Vector3, to: Vector3) -> StringName:
	if blocked_pairs.has(_key(from, to)):
		return COVER_TOTAL
	return covered_pairs.get(_key(from, to), COVER_NONE)


func block(from: Vector3, to: Vector3) -> void:
	blocked_pairs[_key(from, to)] = true


func set_cover(from: Vector3, to: Vector3, cover: StringName) -> void:
	covered_pairs[_key(from, to)] = cover


func _key(from: Vector3, to: Vector3) -> String:
	return "%s>%s" % [from, to]
