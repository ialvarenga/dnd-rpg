class_name PathPreviewRenderer
extends RefCounted

## Presentation-only movement-path rendering. The authoritative navigation path
## remains untouched; this helper trims the already-travelled prefix and rounds
## visual corners before writing the line mesh.

const LINE_LIFT := 0.12
const CORNER_RADIUS := 0.45
const CORNER_SEGMENTS := 5
const POINT_EPSILON_SQUARED := 0.000001


static func draw(line_mesh: ImmediateMesh, path: PackedVector3Array, origin: Vector3) -> void:
	line_mesh.clear_surfaces()
	var display_path := smooth_path(rebase_path(path, origin))
	if display_path.size() < 2:
		return
	line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in display_path:
		line_mesh.surface_add_vertex(point + Vector3.UP * LINE_LIFT)
	line_mesh.surface_end()


## Starts the displayed path at the live character and drops waypoints that are
## already behind it. This keeps a path attached to a moving view even though
## BattleState has already accepted and applied the destination.
static func rebase_path(path: PackedVector3Array, origin: Vector3) -> PackedVector3Array:
	if path.size() < 2:
		return PackedVector3Array()
	var nearest_segment := 0
	var nearest_distance_squared := INF
	for index in range(path.size() - 1):
		var closest := _closest_point_on_segment(origin, path[index], path[index + 1])
		var distance_squared := origin.distance_squared_to(closest)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_segment = index
	var rebased := PackedVector3Array([origin])
	for index in range(nearest_segment + 1, path.size()):
		if rebased[rebased.size() - 1].distance_squared_to(path[index]) > POINT_EPSILON_SQUARED:
			rebased.append(path[index])
	return rebased


## Replaces each sharp navigation corner with a small quadratic arc. Endpoints
## remain exact, while the limited radius avoids visibly cutting across nearby
## obstacles on tight routes.
static func smooth_path(path: PackedVector3Array) -> PackedVector3Array:
	if path.size() < 3:
		return path.duplicate()
	var smoothed := PackedVector3Array([path[0]])
	for index in range(1, path.size() - 1):
		var previous := path[index - 1]
		var corner := path[index]
		var following := path[index + 1]
		var incoming_length := previous.distance_to(corner)
		var outgoing_length := corner.distance_to(following)
		if incoming_length <= 0.001 or outgoing_length <= 0.001:
			continue
		var radius := minf(CORNER_RADIUS, minf(incoming_length, outgoing_length) * 0.3)
		var corner_start := corner.move_toward(previous, radius)
		var corner_end := corner.move_toward(following, radius)
		_append_distinct(smoothed, corner_start)
		for step in range(1, CORNER_SEGMENTS + 1):
			var weight := float(step) / float(CORNER_SEGMENTS)
			var first_lerp := corner_start.lerp(corner, weight)
			var second_lerp := corner.lerp(corner_end, weight)
			_append_distinct(smoothed, first_lerp.lerp(second_lerp, weight))
	_append_distinct(smoothed, path[path.size() - 1])
	return smoothed


static func _closest_point_on_segment(point: Vector3, start: Vector3, end: Vector3) -> Vector3:
	var segment := end - start
	var length_squared := segment.length_squared()
	if length_squared <= POINT_EPSILON_SQUARED:
		return start
	return start + segment * clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)


static func _append_distinct(path: PackedVector3Array, point: Vector3) -> void:
	if path.is_empty() or path[path.size() - 1].distance_squared_to(point) > POINT_EPSILON_SQUARED:
		path.append(point)
