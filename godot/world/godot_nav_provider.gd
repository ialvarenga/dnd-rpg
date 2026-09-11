class_name GodotNavProvider
extends NavProvider

## Engine adapter for the pure NavProvider port. The resolver only receives the
## port; NavigationServer3D and the NavigationRegion3D remain on this side of
## the simulation boundary.

const JumpRulesScript = preload("res://sim/rules/jump_rules.gd")
const JumpLinkCompilerScript = preload("res://world/jump_link_compiler.gd")

var navigation_region: NavigationRegion3D
var navigation_layers: int = 1
var snap_tolerance := 0.35
var movement_regions: Array[Dictionary] = []
## ADR-009 ledge jumps. Segment keys (planar, see _segment_key) map to
## {"kind"}; a running climb's link also maps to the ground point at the ledge
## base, where its run-up ends and the jump itself begins.
var _jump_segments: Dictionary = {}
var _run_up_ends: Dictionary = {}


func _init(region: NavigationRegion3D = null, layers: int = 1, weighted_regions: Array[Dictionary] = [], jump_links: Array[Dictionary] = []) -> void:
	navigation_region = region
	navigation_layers = layers
	movement_regions = weighted_regions.duplicate(true)
	for link in jump_links:
		var jump_from: Vector3 = link.get("via", link["from"])
		_jump_segments[_segment_key(jump_from, link["to"])] = {"kind": link["kind"]}
		if link.has("via"):
			_run_up_ends[_segment_key(link["from"], link["to"])] = link["via"]


## Same navmesh and ledges, restricted to the links this Strength can take.
func for_jumper(strength: int) -> NavProvider:
	if _jump_segments.is_empty():
		return self
	var scoped := GodotNavProvider.new(navigation_region, JumpLinkCompilerScript.layers_for_strength(strength))
	scoped.snap_tolerance = snap_tolerance
	scoped.movement_regions = movement_regions
	scoped._jump_segments = _jump_segments
	scoped._run_up_ends = _run_up_ends
	return scoped


func jump_between(from: Vector3, to: Vector3) -> Dictionary:
	var jump: Dictionary = _jump_segments.get(_segment_key(from, to), {})
	return jump.duplicate()


func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not is_reachable(from, to):
		return PackedVector3Array()
	var map := _navigation_map()
	var closest_from := _vertical_closest_point(map, from)
	var closest_to := _vertical_closest_point(map, to)
	var raw_path := NavigationServer3D.map_get_path(map, closest_from, closest_to, true, navigation_layers)
	if raw_path.is_empty():
		return PackedVector3Array()
	# Navigation geometry describes the walkable *surface*. CharacterBody3D
	# transforms, on the other hand, are normally at the center of their
	# collision shape. Preserve that clearance while projecting every waypoint
	# onto generated heightfields; otherwise a terrain click ends with the
	# character's center snapped to the terrain surface.
	var surface_clearance := from.y - closest_from.y
	var path := PackedVector3Array()
	for index in range(raw_path.size()):
		# A traversed link appears as its exact start and end points. A running
		# climb's link starts one run-up out; split it so the run-up is walked
		# and only the leap from the ledge base is a jump.
		if index > 0 and _run_up_ends.has(_segment_key(raw_path[index - 1], raw_path[index])):
			var run_up_end: Vector3 = _run_up_ends[_segment_key(raw_path[index - 1], raw_path[index])]
			path.append(run_up_end + Vector3.UP * surface_clearance)
		path.append(raw_path[index] + Vector3.UP * surface_clearance)
	if path.size() == 1 and from.distance_to(path[0]) > 0.001:
		path.insert(0, from)
	return path


func path_cost(path: PackedVector3Array) -> float:
	if path.is_empty():
		return INF
	var cost := 0.0
	for index in range(1, path.size()):
		var start := path[index - 1]
		var finish := path[index]
		var jump := jump_between(start, finish)
		if not jump.is_empty():
			cost += JumpRulesScript.jump_cost(StringName(jump["kind"]), start, finish)
			continue
		var length := start.distance_to(finish)
		var steps := maxi(1, ceili(length / 0.25))
		for step in range(steps):
			var midpoint := start.lerp(finish, (float(step) + 0.5) / float(steps))
			cost += length / float(steps) * _movement_multiplier(Vector2(midpoint.x, midpoint.z))
	return cost


func project_push(from: Vector3, direction: Vector3, distance: float) -> Dictionary:
	var planar := Vector3(direction.x, 0.0, direction.z)
	if planar.length_squared() <= 0.000001 or distance <= 0.0 or not _has_navigation_map():
		return {"landing_position": from, "blocked": true, "fell": false, "fall_distance": 0.0}
	var desired := from + planar.normalized() * distance
	var map := _navigation_map()
	var surface_from := _vertical_closest_point(map, from)
	var surface_to := _vertical_closest_point(map, desired)
	var achieved := _planar_distance(surface_from, surface_to)
	var blocked := achieved < minf(distance * 0.5, 0.75)
	var surface_drop := surface_from.y - surface_to.y
	# A wall/nav cutout may still have perfectly walkable ground on its far
	# side, so closest-point projection alone would tunnel through it. When the
	# destination is not below a ledge, require the navmesh route to stay on the
	# requested straight segment and reach the full distance. A real drop is
	# allowed to cross a disconnected edge and lands on the lower surface.
	if not blocked and surface_drop < 2.5:
		var direct_path := NavigationServer3D.map_get_path(map, surface_from, surface_to, true, navigation_layers)
		blocked = achieved < distance - snap_tolerance or not _path_stays_on_push_line(direct_path, surface_from, surface_to, distance)
	if blocked:
		return {"landing_position": from, "blocked": true, "fell": false, "fall_distance": 0.0}
	var clearance := from.y - surface_from.y
	var landing := surface_to + Vector3.UP * clearance
	var fall_distance := maxf(0.0, from.y - landing.y)
	return {"landing_position": landing, "blocked": false, "fell": fall_distance >= 2.5, "fall_distance": fall_distance}


func is_reachable(from: Vector3, to: Vector3) -> bool:
	if not _is_finite_vector(from) or not _is_finite_vector(to) or not _has_navigation_map():
		return false
	var map := _navigation_map()
	var closest_from := _vertical_closest_point(map, from)
	var closest_to := _vertical_closest_point(map, to)
	if _planar_distance(from, closest_from) > snap_tolerance or _planar_distance(to, closest_to) > snap_tolerance:
		return false
	var path := NavigationServer3D.map_get_path(map, closest_from, closest_to, true, navigation_layers)
	# The server answers an unreachable target with a path to the nearest point
	# it can reach. On the same level that is the long-standing "get as close as
	# you can" behaviour (a chest inside its blocker). A summit only ledge jumps
	# connect is another level entirely, an island for anyone who cannot make
	# them, so a route ending a storey away from its target has not arrived.
	return not path.is_empty() and absf(path[path.size() - 1].y - closest_to.y) <= JumpRulesScript.STEP_HEIGHT_M


func surface_point(pos: Vector3) -> Vector3:
	if not _is_finite_vector(pos) or not _has_navigation_map():
		return Vector3.INF
	var surface := _vertical_closest_point(_navigation_map(), pos)
	return surface if _planar_distance(pos, surface) <= snap_tolerance else Vector3.INF


func snap_to_navmesh(pos: Vector3) -> Vector3:
	if not _has_navigation_map():
		return pos
	var snapped := NavigationServer3D.map_get_closest_point(_navigation_map(), pos)
	return Vector3(snapped.x, pos.y, snapped.z)


func _navigation_map() -> RID:
	if not is_instance_valid(navigation_region):
		return RID()
	return navigation_region.get_navigation_map()


func _has_navigation_map() -> bool:
	var map := _navigation_map()
	if not map.is_valid():
		return false
	# The first terrain click can arrive before the regular navigation update.
	# Force this world-side map to synchronize before the pure resolver queries it.
	NavigationServer3D.map_force_update(map)
	return true


func _planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _path_stays_on_push_line(path: PackedVector3Array, from: Vector3, to: Vector3, requested_distance: float) -> bool:
	if path.is_empty():
		return false
	var from_2d := Vector2(from.x, from.z)
	var to_2d := Vector2(to.x, to.z)
	var path_length := 0.0
	for index in range(path.size()):
		var point := Vector2(path[index].x, path[index].z)
		if Geometry2D.get_closest_point_to_segment(point, from_2d, to_2d).distance_to(point) > snap_tolerance:
			return false
		if index > 0:
			path_length += _planar_distance(path[index - 1], path[index])
	return path_length <= requested_distance + snap_tolerance


## Planar, centimetre-snapped key: path points carry the character's height
## above the surface, but a ledge's horizontal endpoints are exact.
func _segment_key(from: Vector3, to: Vector3) -> String:
	return "%.2f,%.2f>%.2f,%.2f" % [from.x, from.z, to.x, to.z]


func _vertical_closest_point(map: RID, point: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point_to_segment(map, point + Vector3.UP * 1000.0, point + Vector3.DOWN * 1000.0)


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _movement_multiplier(point: Vector2) -> float:
	var multiplier := 1.0
	for region in movement_regions:
		var contains := false
		if region.get("shape", &"polygon") == &"path":
			contains = PolylineUtil.distance_to_polyline(point, region.get("points", PackedVector2Array())) <= float(region.get("width", 0.0))
		else:
			contains = Geometry2D.is_point_in_polygon(point, region.get("polygon", PackedVector2Array()))
		if contains:
			multiplier = maxf(multiplier, float(region.get("movement_cost", 1.0)))
	return multiplier
