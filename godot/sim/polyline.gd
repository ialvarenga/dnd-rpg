extends RefCounted

## Engine-independent geometry helpers for authoritative movement paths.
## Paths retain every navigation waypoint; their accumulated 3D segment length
## is the only movement cost used by the simulation.

const EPSILON := 0.0001


static func length(path: PackedVector3Array) -> float:
	var total := 0.0
	for index in range(1, path.size()):
		total += path[index - 1].distance_to(path[index])
	return total


static func with_start(path: PackedVector3Array, start: Vector3) -> PackedVector3Array:
	var normalized := path.duplicate()
	if normalized.is_empty():
		return normalized
	if normalized[0].distance_to(start) > EPSILON:
		normalized.insert(0, start)
	return normalized


static func clamp(path: PackedVector3Array, maximum_distance: float) -> PackedVector3Array:
	var clamped := PackedVector3Array()
	if path.is_empty() or maximum_distance <= EPSILON:
		return clamped

	clamped.append(path[0])
	var remaining := maximum_distance
	for index in range(1, path.size()):
		var segment_start := path[index - 1]
		var segment_end := path[index]
		var segment_length := segment_start.distance_to(segment_end)
		if segment_length <= EPSILON:
			continue
		if segment_length <= remaining + EPSILON:
			clamped.append(segment_end)
			remaining -= segment_length
			continue
		var ratio := remaining / segment_length
		clamped.append(segment_start.lerp(segment_end, ratio))
		return clamped
	return clamped


static func distance_to_polyline(point: Vector2, path: PackedVector2Array) -> float:
	var nearest := INF
	for index in range(1, path.size()):
		nearest = minf(nearest, Geometry2D.get_closest_point_to_segment(point, path[index - 1], path[index]).distance_to(point))
	return nearest
