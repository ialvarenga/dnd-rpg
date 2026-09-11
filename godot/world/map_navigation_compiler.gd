class_name MapNavigationCompiler
extends RefCounted

## B9 single-map navigation source. A 256m map is deliberately one region;
## this compact grid is also the deterministic validation/reachability model.

const TerrainScript = preload("res://world/procedural_terrain_provider.gd")
const JumpRulesScript = preload("res://sim/rules/jump_rules.gd")
const JumpLinkCompilerScript = preload("res://world/jump_link_compiler.gd")

const CELL_SIZE_M := 1.0
const CHARACTER_CLEARANCE_M := 0.45
## Spatial hash for walkable-surface lookups; covers the terrain's 2 m cells.
const SURFACE_CELL_M := 2.0
## How far from a jumpable hill's edge a triangle can still straddle the ledge.
const LEDGE_BAND_M := 2.5

var bounds := Vector2.ZERO
var terrain: TerrainProvider
var blocked: Array[Dictionary] = []
var navigation_region: NavigationRegion3D
## ADR-009 ledge jumps, as JumpLinkCompiler dictionaries. GodotNavProvider reads
## them to recognise jump segments; the NavigationLink3D nodes route them.
var jump_links: Array[Dictionary] = []
var _ledge_hills: Array[Dictionary] = []
var _surface_triangles: Dictionary = {}
var _link_edges: Dictionary = {}


## `ledge_hills` are the jumpable hills (see JumpLinkCompiler.compile): the
## navmesh drops the triangles straddling their edges, and jump links bridge
## the gap instead.
func build(source_terrain: TerrainProvider, blocked_areas: Array[Dictionary], parent: Node3D = null, ledge_hills: Array[Dictionary] = []) -> NavigationRegion3D:
	terrain = source_terrain
	bounds = terrain.bounds
	blocked = blocked_areas.duplicate(true)
	_ledge_hills = ledge_hills.duplicate(true)
	navigation_region = NavigationRegion3D.new()
	navigation_region.name = "CompiledNavigation"
	var mesh := NavigationMesh.new()
	# The engine navigation surface uses the same triangle field as terrain
	# rendering/collision. Rivers are removed from the walkable surface here as
	# well as from the deterministic reachability grid below.
	var vertices := PackedVector3Array()
	for triangle in terrain.export_navigation_geometry():
		if triangle.size() != 3:
			continue
		if _triangle_is_blocked(triangle) or _triangle_exceeds_slope(triangle) or _triangle_straddles_ledge(triangle):
			continue
		var offset := vertices.size()
		vertices.append_array(triangle)
		mesh.add_polygon(PackedInt32Array([offset, offset + 1, offset + 2]))
		_index_surface_triangle(triangle)
	mesh.vertices = vertices
	navigation_region.navigation_mesh = mesh
	_build_jump_links()
	if parent != null:
		parent.add_child(navigation_region)
	return navigation_region


## Walkable navigation height at a point, or NAN where the navmesh has no
## polygon (blocked, too steep, or a dropped ledge cell).
func surface_height_at(point: Vector2) -> float:
	var cell := Vector2i(floori(point.x / SURFACE_CELL_M), floori(point.y / SURFACE_CELL_M))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for triangle in _surface_triangles.get(cell + Vector2i(dx, dz), []):
				var height := _height_in_triangle(point, triangle)
				if not is_nan(height):
					return height
	return NAN


func _build_jump_links() -> void:
	jump_links.clear()
	_link_edges.clear()
	if _ledge_hills.is_empty():
		return
	jump_links = JumpLinkCompilerScript.new().compile(_ledge_hills, surface_height_at)
	for index in range(jump_links.size()):
		var link: Dictionary = jump_links[index]
		var node := NavigationLink3D.new()
		node.name = "JumpLink_%s_%d" % [link.get("hill_id", &"hill"), index]
		node.bidirectional = false
		node.start_position = link["from"]
		node.end_position = link["to"]
		node.navigation_layers = int(link["layers"])
		node.enter_cost = float(link["enter_cost"])
		navigation_region.add_child(node)
		# The walking grid's slope test is coarser than the navmesh, so a link
		# end hugging a ledge may sit in a grid cell it calls unwalkable. Any
		# neighbouring cell may therefore take the link.
		var from_cell := _grid_cell(Vector2(link["from"].x, link["from"].z))
		var to_cell := _grid_cell(Vector2(link["to"].x, link["to"].z))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var edges: Array = _link_edges.get(from_cell + Vector2i(dx, dz), [])
				edges.append(to_cell)
				_link_edges[from_cell + Vector2i(dx, dz)] = edges


func _triangle_straddles_ledge(triangle: PackedVector3Array) -> bool:
	if _ledge_hills.is_empty():
		return false
	var low := minf(triangle[0].y, minf(triangle[1].y, triangle[2].y))
	var high := maxf(triangle[0].y, maxf(triangle[1].y, triangle[2].y))
	if high - low <= JumpRulesScript.STEP_HEIGHT_M:
		return false
	for hill in _ledge_hills:
		for vertex in triangle:
			if _near_ledge(Vector2(vertex.x, vertex.z), hill):
				return true
	return false


## True inside the band around a jumpable hill's edge, except on its ramp.
func _near_ledge(point: Vector2, hill: Dictionary) -> bool:
	var size: Vector3 = hill["size"]
	var half := Vector2(size.x, size.z) * 0.5
	var local := TerrainScript.hill_world_to_local(hill["center"], float(hill["rotation_y"]), point)
	if bool(hill.get("navigable", false)) and local.y >= half.y and absf(local.x) <= half.x + TerrainScript.HILL_SKIRT_M:
		return false
	var q := Vector2(absf(local.x) - half.x, absf(local.y) - half.y)
	var sdf := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)
	return absf(sdf) <= LEDGE_BAND_M


func _index_surface_triangle(triangle: PackedVector3Array) -> void:
	var centroid := Vector2((triangle[0].x + triangle[1].x + triangle[2].x) / 3.0, (triangle[0].z + triangle[1].z + triangle[2].z) / 3.0)
	var cell := Vector2i(floori(centroid.x / SURFACE_CELL_M), floori(centroid.y / SURFACE_CELL_M))
	var cell_triangles: Array = _surface_triangles.get(cell, [])
	cell_triangles.append(triangle)
	_surface_triangles[cell] = cell_triangles


func _height_in_triangle(point: Vector2, triangle: PackedVector3Array) -> float:
	var a := Vector2(triangle[0].x, triangle[0].z)
	var b := Vector2(triangle[1].x, triangle[1].z)
	var c := Vector2(triangle[2].x, triangle[2].z)
	var denominator := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
	if is_zero_approx(denominator):
		return NAN
	var wa := ((b.y - c.y) * (point.x - c.x) + (c.x - b.x) * (point.y - c.y)) / denominator
	var wb := ((c.y - a.y) * (point.x - c.x) + (a.x - c.x) * (point.y - c.y)) / denominator
	var wc := 1.0 - wa - wb
	if wa < -0.0001 or wb < -0.0001 or wc < -0.0001:
		return NAN
	return wa * triangle[0].y + wb * triangle[1].y + wc * triangle[2].y


func _grid_cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CELL_SIZE_M), floori(point.y / CELL_SIZE_M))


func _triangle_is_blocked(triangle: PackedVector3Array) -> bool:
	var samples := PackedVector2Array([
		Vector2(triangle[0].x, triangle[0].z),
		Vector2(triangle[1].x, triangle[1].z),
		Vector2(triangle[2].x, triangle[2].z),
		Vector2((triangle[0].x + triangle[1].x + triangle[2].x) / 3.0, (triangle[0].z + triangle[1].z + triangle[2].z) / 3.0),
	])
	for area in blocked:
		for sample in samples:
			if _area_blocks(sample, area):
				return true
		if area.get("kind", &"") != &"river":
			continue
		# A narrow diagonal river can cut an edge without containing a vertex.
		var points: PackedVector2Array = area.get("points", PackedVector2Array())
		for edge in range(3):
			var a := samples[edge]
			var b := samples[(edge + 1) % 3]
			for segment in range(1, points.size()):
				if Geometry2D.segment_intersects_segment(a, b, points[segment - 1], points[segment]) != null:
					var midpoint := (a + b) * 0.5
					if _river_blocks(midpoint, area):
						return true
	return false


func is_reachable(from: Vector2, to: Vector2) -> bool:
	if not _walkable(from) or not _walkable(to):
		return false
	var start := Vector2i(floori(from.x / CELL_SIZE_M), floori(from.y / CELL_SIZE_M))
	var target := Vector2i(floori(to.x / CELL_SIZE_M), floori(to.y / CELL_SIZE_M))
	var frontier: Array[Vector2i] = [start]
	var visited := {start: true}
	var cursor := 0
	while cursor < frontier.size():
		var current: Vector2i = frontier[cursor]
		cursor += 1
		if current == target:
			return true
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next_cell: Vector2i = current + offset
			if not visited.has(next_cell) and _walkable(Vector2((float(next_cell.x) + 0.5) * CELL_SIZE_M, (float(next_cell.y) + 0.5) * CELL_SIZE_M)):
				visited[next_cell] = true
				frontier.append(next_cell)
		# Ledge jumps (ADR-009) connect surfaces the walking grid cannot. Any
		# Strength's link counts: this validates the map, not one creature.
		for linked_cell in _link_edges.get(current, []):
			if not visited.has(linked_cell):
				visited[linked_cell] = true
				frontier.append(linked_cell)
	return false


func _walkable(point: Vector2) -> bool:
	if point.x < 0.0 or point.y < 0.0 or point.x > bounds.x or point.y > bounds.y:
		return false
	if terrain.slope_at(point.x, point.y) > _slope_limit():
		return false
	for area in blocked:
		if _area_blocks(point, area):
			return false
	return true


func _area_blocks(point: Vector2, area: Dictionary) -> bool:
	if area.get("kind", &"") == &"river":
		return _river_blocks(point, area)
	if area.get("kind", &"") == &"box":
		var size: Vector3 = area.get("size", Vector3.ZERO)
		var center: Vector2 = area.get("point", Vector2.ZERO)
		var offset := point - center
		var rotation := -float(area.get("rotation_y", 0.0))
		var local := Vector2(
			offset.x * cos(rotation) - offset.y * sin(rotation),
			offset.x * sin(rotation) + offset.y * cos(rotation)
		)
		return absf(local.x) < size.x * 0.5 + CHARACTER_CLEARANCE_M and absf(local.y) < size.z * 0.5 + CHARACTER_CLEARANCE_M
	return point.distance_to(area.get("point", Vector2.ZERO)) < float(area.get("radius", 0.0)) + CHARACTER_CLEARANCE_M


func _triangle_exceeds_slope(triangle: PackedVector3Array) -> bool:
	var normal := (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0]).normalized()
	return rad_to_deg(acos(clampf(absf(normal.y), 0.0, 1.0))) > _slope_limit()


func _slope_limit() -> float:
	return float(terrain.call("navigation_slope_limit")) if terrain.has_method("navigation_slope_limit") else 35.0


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
