class_name GodotNavProvider
extends NavProvider

## Engine adapter for the pure NavProvider port. The resolver only receives the
## port; NavigationServer3D and the NavigationRegion3D remain on this side of
## the simulation boundary.

var navigation_region: NavigationRegion3D
var navigation_layers: int = 1
var snap_tolerance := 0.35


func _init(region: NavigationRegion3D = null, layers: int = 1) -> void:
	navigation_region = region
	navigation_layers = layers


func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not is_reachable(from, to):
		return PackedVector3Array()
	var map := _navigation_map()
	var closest_from := NavigationServer3D.map_get_closest_point(map, from)
	var closest_to := NavigationServer3D.map_get_closest_point(map, to)
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
		cost += path[index - 1].distance_to(path[index])
	return cost


func is_reachable(from: Vector3, to: Vector3) -> bool:
	if not _is_finite_vector(from) or not _is_finite_vector(to) or not _has_navigation_map():
		return false
	var map := _navigation_map()
	var closest_from := NavigationServer3D.map_get_closest_point(map, from)
	var closest_to := NavigationServer3D.map_get_closest_point(map, to)
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


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
