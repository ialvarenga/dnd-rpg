class_name MapCompiler
extends RefCounted

## B7-B10 compiler entry point. Python/schema validation remains canonical;
## this layer owns critical engine, spatial, and reachability sanity checks.

const ID_PATTERN := "^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$"

var terrain_factory: Callable = func() -> TerrainProvider: return ProceduralTerrainProvider.new()


func compile(spec: Dictionary) -> MapCompilationResult:
	var result := MapCompilationResult.new()
	_validate_required_data(spec, result.errors)
	if not result.errors.is_empty():
		return result
	var map: Dictionary = spec["map"]
	var bounds_data: Dictionary = map["bounds"]
	var bounds := Vector2(float(bounds_data["width_m"]), float(bounds_data["height_m"]))
	var terrain: TerrainProvider = terrain_factory.call()
	var terrain_data: Dictionary = spec.get("terrain", {"profile": "flat"})
	if not terrain.generate(StringName(terrain_data.get("profile", "")), int(map["seed"]), bounds):
		_add(result.errors, &"INVALID_TERRAIN", "terrain profile, seed, or bounds are invalid", &"terrain")
		return result
	result.terrain = terrain
	var reserved: Array[Dictionary] = _compile_paths(spec, terrain, bounds, result)
	_compile_bridges(spec.get("bridges", []), terrain, bounds, result)
	var occupied: Array[Dictionary] = reserved.duplicate(true)
	_compile_placements(spec.get("structures", []), &"structure", terrain, bounds, occupied, result)
	_compile_placements(spec.get("vegetation", []), &"vegetation", terrain, bounds, occupied, result)
	if not result.errors.is_empty():
		return result
	var generator := VegetationGenerator.new()
	for region in spec.get("regions", []):
		var generated := generator.generate(region, int(map["seed"]), terrain, occupied)
		for placement in generated:
			occupied.append({"point": Vector2(placement.position.x, placement.position.z), "radius": placement.radius, "id": placement.id})
			result.placements.append(placement)
	_validate_spawns(spec.get("spawn_points", []), bounds, occupied, result.errors)
	if not result.errors.is_empty():
		return result
	result.root = Node3D.new()
	result.root.name = "CompiledMap_%s" % map["id"]
	result.root.add_child(CompiledTerrain.create(terrain))
	_instantiate_paths(result, terrain)
	for bridge in result.bridges:
		var bridge_node := AssetCatalog.instantiate(bridge.asset)
		if bridge_node == null:
			_add(result.errors, &"UNKNOWN_ASSET", "catalog bridge '%s' could not instantiate" % bridge.asset, bridge.id)
			continue
		bridge_node.name = String(bridge.id)
		bridge_node.position = bridge.position
		result.root.add_child(bridge_node)
	for placement in result.placements:
		var node := AssetCatalog.instantiate(placement.asset)
		if node == null:
			_add(result.errors, &"UNKNOWN_ASSET", "catalog asset '%s' could not instantiate" % placement.asset, placement.id, {"asset": placement.asset})
			continue
		node.name = String(placement.id)
		node.position = placement.position
		node.rotation.y = placement.rotation_y
		result.root.add_child(node)
		var definition := AssetCatalog.get_definition(placement.asset)
		if definition != null:
			result.root.add_child(MapRuntimeBlocker.create(placement.id, placement.position, placement.radius))
	if not result.errors.is_empty():
		result.root.queue_free()
		result.root = null
		return result
	result.navigation = MapNavigationCompiler.new()
	result.navigation.build(terrain, _navigation_blockers(result.placements), result.root)
	_validate_reachability(spec, result.navigation, result.errors)
	if not result.errors.is_empty():
		result.root.queue_free()
		result.root = null
	return result


func _compile_placements(raw_placements: Array, expected_type: StringName, terrain: TerrainProvider, bounds: Vector2, occupied: Array[Dictionary], result: MapCompilationResult) -> void:
	for raw in raw_placements:
		var id := StringName(raw.get("id", ""))
		var asset := StringName(raw.get("asset", ""))
		var definition := AssetCatalog.get_definition(asset)
		if definition == null or not definition.is_usable():
			_add(result.errors, &"UNKNOWN_ASSET", "'%s' references unknown catalog asset '%s'" % [id, asset], id, {"asset": asset})
			continue
		if expected_type == &"structure" and definition.asset_type != &"structure":
			_add(result.errors, &"INVALID_ASSET_TYPE", "'%s' must use a structure asset" % id, id, {"asset": asset})
			continue
		var point := _point(raw.get("position", []))
		if not _fits_bounds(point, definition.footprint_radius, bounds):
			_add(result.errors, &"OUT_OF_BOUNDS", "'%s' footprint is outside map bounds" % id, id)
			continue
		var slope := terrain.slope_at(point.x, point.y)
		if not definition.permits_slope(slope):
			_add(result.errors, &"IMPOSSIBLE_SLOPE", "'%s' requires slope <= %.1f° but terrain is %.1f°" % [id, definition.placement_max_slope_deg, slope], id)
			continue
		for other in occupied:
			if point.distance_to(other.point) < definition.footprint_radius + float(other.radius):
				_add(result.errors, &"OVERLAP", "'%s' overlaps reserved area '%s'" % [id, other.get("id", "area")], id)
				break
		if not result.errors.is_empty() and result.errors.back().entity_id == id:
			continue
		occupied.append({"point": point, "radius": definition.footprint_radius, "id": id})
		result.placements.append({"id": id, "asset": asset, "position": Vector3(point.x, terrain.height_at(point.x, point.y), point.y), "rotation_y": deg_to_rad(float(raw.get("rotation_deg", 0.0))), "radius": definition.footprint_radius})


func _compile_paths(spec: Dictionary, terrain: TerrainProvider, bounds: Vector2, result: MapCompilationResult) -> Array[Dictionary]:
	var reserved: Array[Dictionary] = []
	for kind in [&"rivers", &"roads"]:
		for raw in spec.get(kind, []):
			var points := _points(raw.get("control_points", []))
			var id := StringName(raw.get("id", ""))
			if points.size() < 2:
				_add(result.errors, &"MISSING_REQUIRED_DATA", "'%s' needs at least two control points" % id, id)
				continue
			for point in points:
				if not _fits_bounds(point, 0.0, bounds):
					_add(result.errors, &"OUT_OF_BOUNDS", "'%s' control point is outside map bounds" % id, id)
			var width := float(raw.get("width_m", 2.0)) * 0.5
			if kind == &"roads" and terrain.has_method("add_flattening_path"):
				terrain.call("add_flattening_path", points, width)
			result.paths.append({"id": id, "kind": kind, "points": points, "width": width})
			for point in points:
				reserved.append({"point": point, "radius": width, "id": id})
	for river in result.paths.filter(func(path: Dictionary) -> bool: return path.kind == &"rivers"):
		for road in result.paths.filter(func(path: Dictionary) -> bool: return path.kind == &"roads"):
			if _paths_cross(river.points, road.points) and not _has_compatible_bridge(spec.get("bridges", []), river, road):
				_add(result.errors, &"INVALID_RIVER_CROSSING", "river '%s' crosses road '%s' without a bridge" % [river.id, road.id], river.id, {"road_id": road.id})
	return reserved


func _instantiate_paths(result: MapCompilationResult, terrain: TerrainProvider) -> void:
	for path_data in result.paths:
		result.root.add_child(MapPathRenderer.create(path_data, terrain))


func _validate_spawns(spawns: Array, bounds: Vector2, occupied: Array[Dictionary], errors: Array[MapValidationError]) -> void:
	for spawn in spawns:
		var id := StringName(spawn.get("id", ""))
		var point := _point(spawn.get("position", []))
		if not _fits_bounds(point, 0.0, bounds):
			_add(errors, &"OUT_OF_BOUNDS", "spawn '%s' is outside map bounds" % id, id)
		for area in occupied:
			if point.distance_to(area.point) < float(area.radius):
				_add(errors, &"SPAWN_INSIDE_STRUCTURE", "spawn '%s' is inside '%s'" % [id, area.get("id", "reserved area")], id)


func _validate_reachability(spec: Dictionary, navigation: MapNavigationCompiler, errors: Array[MapValidationError]) -> void:
	var spawns: Array = spec.get("spawn_points", [])
	var objectives: Array = spec.get("objectives", [])
	if spawns.is_empty():
		return
	for objective in objectives:
		var target := _point(objective.get("position", []))
		var reachable := false
		for spawn in spawns:
			if navigation.is_reachable(_point(spawn.get("position", [])), target):
				reachable = true
		if not reachable:
			_add(errors, &"UNREACHABLE_OBJECTIVE", "objective '%s' cannot be reached from any spawn" % objective.get("id", "objective"), StringName(objective.get("id", "")))
	for encounter in spec.get("encounters", []):
		var target := _point(encounter.get("position", []))
		if not spawns.any(func(spawn: Dictionary) -> bool: return navigation.is_reachable(_point(spawn.get("position", [])), target)):
			_add(errors, &"UNREACHABLE_ENCOUNTER", "encounter '%s' cannot be reached from any spawn" % encounter.get("id", "encounter"), StringName(encounter.get("id", "")))


func _validate_required_data(spec: Dictionary, errors: Array[MapValidationError]) -> void:
	if not spec.has("map") or not spec.map is Dictionary or not spec.map.has("seed") or not spec.map.has("bounds"):
		_add(errors, &"MISSING_REQUIRED_DATA", "validated MapSpec requires map.seed and map.bounds", &"map")
		return
	for group in ["structures", "vegetation", "spawn_points", "regions", "rivers", "roads", "bridges", "objectives", "encounters", "doors"]:
		if spec.has(group) and not spec[group] is Array:
			_add(errors, &"MISSING_REQUIRED_DATA", "'%s' must be an array" % group, StringName(group))
	var id_regex := RegEx.new()
	id_regex.compile(ID_PATTERN)
	for group in ["structures", "vegetation", "spawn_points", "regions", "rivers", "roads", "bridges", "objectives", "encounters", "doors"]:
		for entity in spec.get(group, []):
			var id := String(entity.get("id", ""))
			if id_regex.search(id) == null or id_regex.search(id).get_string() != id:
				_add(errors, &"MALFORMED_ID", "'%s' has malformed stable id '%s'" % [group, id], StringName(id))


func _point(raw: Array) -> Vector2:
	return Vector2(float(raw[0]), float(raw[1])) if raw.size() == 2 else Vector2(INF, INF)


func _points(raw: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for value in raw:
		if value is Array:
			points.append(_point(value))
	return points


func _fits_bounds(point: Vector2, radius: float, bounds: Vector2) -> bool:
	return is_finite(point.x) and is_finite(point.y) and point.x - radius >= 0.0 and point.y - radius >= 0.0 and point.x + radius <= bounds.x and point.y + radius <= bounds.y


func _add(errors: Array[MapValidationError], code: StringName, message: String, id: StringName = &"", context: Dictionary = {}) -> void:
	errors.append(MapValidationError.new(code, message, id, context))


func _paths_cross(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	for ai in range(1, a.size()):
		for bi in range(1, b.size()):
			if Geometry2D.segment_intersects_segment(a[ai - 1], a[ai], b[bi - 1], b[bi]) != null:
				return true
	return false


func _compile_bridges(raw_bridges: Array, terrain: TerrainProvider, bounds: Vector2, result: MapCompilationResult) -> void:
	for raw in raw_bridges:
		var id := StringName(raw.get("id", ""))
		var point := _point(raw.get("position", []))
		var definition := AssetCatalog.get_definition(StringName(raw.get("asset", "")))
		if definition == null or definition.asset_type != &"bridge":
			_add(result.errors, &"INVALID_BRIDGE", "bridge '%s' must use a catalog bridge asset" % id, id)
			continue
		if not _fits_bounds(point, definition.footprint_radius, bounds):
			_add(result.errors, &"OUT_OF_BOUNDS", "bridge '%s' footprint is outside map bounds" % id, id)
			continue
		result.bridges.append({"id": id, "asset": StringName(raw.get("asset", "")), "position": Vector3(point.x, terrain.height_at(point.x, point.y) + 0.12, point.y), "radius": definition.footprint_radius})


func _has_compatible_bridge(bridges: Array, river: Dictionary, road: Dictionary) -> bool:
	for bridge in bridges:
		if StringName(bridge.get("river_id", "")) == river.id and StringName(bridge.get("road_id", "")) == road.id:
			var definition := AssetCatalog.get_definition(StringName(bridge.get("asset", "")))
			if definition != null and definition.asset_type == &"bridge":
				return true
	return false


func _navigation_blockers(placements: Array[Dictionary]) -> Array[Dictionary]:
	var blockers: Array[Dictionary] = []
	for placement in placements:
		var definition := AssetCatalog.get_definition(placement.asset)
		if definition != null and definition.blocks_navigation:
			blockers.append({"point": Vector2(placement.position.x, placement.position.z), "radius": placement.radius, "id": placement.id})
	return blockers
