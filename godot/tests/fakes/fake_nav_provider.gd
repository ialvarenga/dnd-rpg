class_name FakeNavProvider
extends NavProvider

var blocked_destinations: Array[Vector3] = []
var paths: Dictionary = {}
var snapped_destinations: Dictionary = {}


func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if blocked_destinations.has(to):
		return PackedVector3Array()
	var key := _key(from, to)
	if paths.has(key):
		return (paths[key] as PackedVector3Array).duplicate()
	return PackedVector3Array([from, to])


func path_cost(path: PackedVector3Array) -> float:
	if path.size() < 2:
		return INF
	var cost := 0.0
	for index in range(1, path.size()):
		cost += path[index - 1].distance_to(path[index])
	return cost


func is_reachable(_from: Vector3, to: Vector3) -> bool:
	return not blocked_destinations.has(to)


func snap_to_navmesh(pos: Vector3) -> Vector3:
	return snapped_destinations.get(pos, pos)


func set_path(from: Vector3, to: Vector3, path: PackedVector3Array) -> void:
	paths[_key(from, to)] = path.duplicate()


func _key(from: Vector3, to: Vector3) -> String:
	return "%s>%s" % [from, to]
