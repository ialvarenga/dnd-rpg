class_name NavProvider
extends RefCounted

const PolylineUtil = preload("res://sim/polyline.gd")

func find_path(_from: Vector3, _to: Vector3) -> PackedVector3Array:
	push_error("NavProvider.find_path must be implemented by an adapter")
	return PackedVector3Array()


func path_cost(_path: PackedVector3Array) -> float:
	push_error("NavProvider.path_cost must be implemented by an adapter")
	return INF


## Stable prefix whose weighted cost does not exceed budget. Providers may
## override, but the binary search works for every monotonic path_cost.
func clamp_path(path: PackedVector3Array, budget: float) -> PackedVector3Array:
	if path.size() < 2 or budget <= 0.0:
		return PackedVector3Array()
	if path_cost(path) <= budget:
		return path.duplicate()
	var geometric_length := PolylineUtil.length(path)
	var low := 0.0
	var high := geometric_length
	for _iteration in range(24):
		var middle := (low + high) * 0.5
		var candidate := PolylineUtil.clamp(path, middle)
		if path_cost(candidate) <= budget:
			low = middle
		else:
			high = middle
	return PolylineUtil.clamp(path, low)


## Forced movement projection result keys: landing_position, blocked, fell,
## fall_distance. No movement resource is charged for this query.
func project_push(from: Vector3, direction: Vector3, distance: float) -> Dictionary:
	var planar := Vector3(direction.x, 0.0, direction.z).normalized()
	return {"landing_position": from + planar * distance, "blocked": false, "fell": false, "fall_distance": 0.0}


func is_reachable(_from: Vector3, _to: Vector3) -> bool:
	return false


func snap_to_navmesh(pos: Vector3) -> Vector3:
	return pos
