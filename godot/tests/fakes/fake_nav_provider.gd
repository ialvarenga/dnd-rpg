class_name FakeNavProvider
extends NavProvider

var blocked_destinations: Array[Vector3] = []
var paths: Dictionary = {}
var snapped_destinations: Dictionary = {}
var find_path_calls: int = 0
var cost_multiplier: float = 1.0
var push_results: Dictionary = {}
var jumps: Dictionary = {}
var jumper_strengths: Array[int] = []


func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	find_path_calls += 1
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
	var jump_cost := 0.0
	for index in range(1, path.size()):
		var jump := jump_between(path[index - 1], path[index])
		if jump.is_empty():
			cost += path[index - 1].distance_to(path[index])
		else:
			jump_cost += JumpRules.jump_cost(StringName(jump["kind"]), path[index - 1], path[index])
	return cost * cost_multiplier + jump_cost


func jump_between(from: Vector3, to: Vector3) -> Dictionary:
	var jump: Dictionary = jumps.get(_key(from, to), {})
	return jump.duplicate()


func for_jumper(strength: int) -> NavProvider:
	jumper_strengths.append(strength)
	return self


func set_jump(from: Vector3, to: Vector3, kind: StringName) -> void:
	jumps[_key(from, to)] = {"kind": kind}


func project_push(from: Vector3, direction: Vector3, distance: float) -> Dictionary:
	var key := "%s>%s>%.3f" % [from, direction.normalized(), distance]
	if push_results.has(key):
		return (push_results[key] as Dictionary).duplicate(true)
	return super.project_push(from, direction, distance)


func set_push_result(from: Vector3, direction: Vector3, distance: float, result: Dictionary) -> void:
	push_results["%s>%s>%.3f" % [from, direction.normalized(), distance]] = result.duplicate(true)


func surface_point(pos: Vector3) -> Vector3:
	return Vector3.INF if blocked_destinations.has(pos) else pos


func is_reachable(_from: Vector3, to: Vector3) -> bool:
	return not blocked_destinations.has(to)


func snap_to_navmesh(pos: Vector3) -> Vector3:
	return snapped_destinations.get(pos, pos)


func set_path(from: Vector3, to: Vector3, path: PackedVector3Array) -> void:
	paths[_key(from, to)] = path.duplicate()


func _key(from: Vector3, to: Vector3) -> String:
	return "%s>%s" % [from, to]
