class_name GodotNavProvider
extends NavProvider

## Engine adapter for the pure NavProvider port. The resolver only receives the
## port; NavigationServer3D and the NavigationRegion3D remain on this side of
## the simulation boundary.

var navigation_region: NavigationRegion3D
var navigation_layers: int = 1
var snap_tolerance := 0.35
var movement_regions: Array[Dictionary] = []


func _init(region: NavigationRegion3D = null, layers: int = 1, weighted_regions: Array[Dictionary] = []) -> void:
	navigation_region = region
	navigation_layers = layers
	movement_regions = weighted_regions.duplicate(true)


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
	for point in raw_path:
		path.append(point + Vector3.UP * surface_clearance)
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
	return not path.is_empty()


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
