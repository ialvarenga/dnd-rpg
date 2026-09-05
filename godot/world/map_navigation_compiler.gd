class_name MapNavigationCompiler
extends RefCounted

## B9 single-map navigation source. A 256m map is deliberately one region;
## this compact grid is also the deterministic validation/reachability model.

const CELL_SIZE_M := 1.0

var bounds := Vector2.ZERO
var terrain: TerrainProvider
var blocked: Array[Dictionary] = []
var navigation_region: NavigationRegion3D


func build(source_terrain: TerrainProvider, blocked_areas: Array[Dictionary], parent: Node3D = null) -> NavigationRegion3D:
	terrain = source_terrain
	bounds = terrain.bounds
	blocked = blocked_areas.duplicate(true)
	navigation_region = NavigationRegion3D.new()
	navigation_region.name = "CompiledNavigation"
	var mesh := NavigationMesh.new()
	# The engine navigation surface uses the same triangle field as terrain
	# rendering/collision. Obstacle circles remain shared with validation.
	var vertices := PackedVector3Array()
	for triangle in terrain.export_navigation_geometry():
		if triangle.size() != 3:
			continue
		var offset := vertices.size()
		vertices.append_array(triangle)
		mesh.add_polygon(PackedInt32Array([offset, offset + 1, offset + 2]))
	mesh.vertices = vertices
	navigation_region.navigation_mesh = mesh
	if parent != null:
		parent.add_child(navigation_region)
	return navigation_region


func is_reachable(from: Vector2, to: Vector2) -> bool:
	if not _walkable(from) or not _walkable(to):
		return false
	var start := Vector2i(floori(from.x / CELL_SIZE_M), floori(from.y / CELL_SIZE_M))
	var target := Vector2i(floori(to.x / CELL_SIZE_M), floori(to.y / CELL_SIZE_M))
	var frontier: Array[Vector2i] = [start]
	var visited := {start: true}
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		if current == target:
			return true
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next_cell: Vector2i = current + offset
			if not visited.has(next_cell) and _walkable(Vector2((float(next_cell.x) + 0.5) * CELL_SIZE_M, (float(next_cell.y) + 0.5) * CELL_SIZE_M)):
				visited[next_cell] = true
				frontier.append(next_cell)
	return false


func _walkable(point: Vector2) -> bool:
	if point.x < 0.0 or point.y < 0.0 or point.x > bounds.x or point.y > bounds.y:
		return false
	for area in blocked:
		if area.get("kind", &"") == &"river":
			if _river_blocks(point, area):
				return false
			continue
		if point.distance_to(area.get("point", Vector2.ZERO)) < float(area.get("radius", 0.0)):
			return false
	return true


func _river_blocks(point: Vector2, river: Dictionary) -> bool:
	var points: PackedVector2Array = river.get("points", PackedVector2Array())
	if _distance_to_segments(point, points) >= float(river.get("width", 0.0)):
		return false
	for crossing in river.get("crossings", []):
		if point.distance_to(crossing.point) <= crossing.radius:
			return false
	return true


func _distance_to_segments(point: Vector2, points: PackedVector2Array) -> float:
	var nearest := INF
	for index in range(1, points.size()):
		nearest = minf(nearest, point.distance_to(Geometry2D.get_closest_point_to_segment(point, points[index - 1], points[index])))
	return nearest
