class_name NavProvider
extends RefCounted

const PolylineUtil = preload("res://sim/polyline.gd")

func find_path(_from: Vector3, _to: Vector3) -> PackedVector3Array:
	push_error("NavProvider.find_path must be implemented by an adapter")
	return PackedVector3Array()


func path_cost(_path: PackedVector3Array) -> float:
	push_error("NavProvider.path_cost must be implemented by an adapter")
	return INF


## Stable prefix whose weighted cost does not exceed budget. Walks the path one
## segment at a time (path_cost is additive per segment) and binary-searches
## only inside the walking segment the budget runs out in. A jump segment is
## atomic: a creature cannot stop in mid-air, so an unaffordable jump ends the
## prefix at its takeoff point.
func clamp_path(path: PackedVector3Array, budget: float) -> PackedVector3Array:
	if path.size() < 2 or budget <= 0.0:
		return PackedVector3Array()
	if path_cost(path) <= budget:
		return path.duplicate()
	var clamped := PackedVector3Array([path[0]])
	var spent := 0.0
	for index in range(1, path.size()):
		var segment := PackedVector3Array([path[index - 1], path[index]])
		var segment_cost := path_cost(segment)
		if spent + segment_cost <= budget:
			clamped.append(path[index])
			spent += segment_cost
			continue
		if jump_between(path[index - 1], path[index]).is_empty():
			var length := path[index - 1].distance_to(path[index])
			var low := 0.0
			var high := length
			for _iteration in range(24):
				var middle := (low + high) * 0.5
				if spent + path_cost(PolylineUtil.clamp(segment, middle)) <= budget:
					low = middle
				else:
					high = middle
			if low > PolylineUtil.EPSILON:
				clamped.append(path[index - 1].lerp(path[index], low / length))
		break
	return clamped if clamped.size() >= 2 else PackedVector3Array()


## Jump metadata when the path segment from -> to is a ledge jump rather than
## walking, else {}. Key: kind (JumpRules.DROP or CLIMB). The resolver reads
## the height from the segment itself and the rest from JumpRules (ADR-009).
func jump_between(_from: Vector3, _to: Vector3) -> Dictionary:
	return {}


## The navigation view for a creature of this Strength: it only routes across
## the ledges that creature can physically take. Providers without ledges are
## Strength-independent and return themselves.
func for_jumper(_strength: int) -> NavProvider:
	return self


## Forced movement projection result keys: landing_position, blocked, fell,
## fall_distance. No movement resource is charged for this query.
func project_push(from: Vector3, direction: Vector3, distance: float) -> Dictionary:
	var planar := Vector3(direction.x, 0.0, direction.z).normalized()
	return {"landing_position": from + planar * distance, "blocked": false, "fell": false, "fall_distance": 0.0}


## Walkable ground under a point (navigation surface height, no body
## clearance), or Vector3.INF when nothing there can be stood on.
func surface_point(pos: Vector3) -> Vector3:
	return pos


func is_reachable(_from: Vector3, _to: Vector3) -> bool:
	return false


func snap_to_navmesh(pos: Vector3) -> Vector3:
	return pos
