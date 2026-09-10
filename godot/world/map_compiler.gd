class_name MapCompiler
extends RefCounted

## B7-B10 compiler entry point. Python/schema validation remains canonical;
## this layer owns critical engine, spatial, and reachability sanity checks.

const ID_PATTERN := "^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$"
## Floor kept clear around a spawn or an actor so procedural scatter never grows
## on top of a character. Validating this after the fact instead made a dense
## region impossible to author.
const CHARACTER_CLEARANCE_M := 0.75

var terrain_factory: Callable = func() -> TerrainProvider: return ProceduralTerrainProvider.new()


func compile(spec: Dictionary) -> MapCompilationResult:
	var result := MapCompilationResult.new()
	_validate_required_data(spec, result.errors)
	if not result.errors.is_empty():
		return result
	# Dialog/stat-block references are pure data cross-checks with no terrain or
	# navigation dependency, so they fail before any compilation cost is paid.
	_validate_dialog_references(spec, result.errors)
	if not result.errors.is_empty():
		return result
	result.music = spec.get("music", {}).duplicate()
	var map: Dictionary = spec["map"]
	var bounds_data: Dictionary = map["bounds"]
	var bounds := Vector2(float(bounds_data["width_m"]), float(bounds_data["height_m"]))
	var terrain: TerrainProvider = terrain_factory.call()
	var terrain_data: Dictionary = spec.get("terrain", {"profile": "flat"})
	if not terrain.generate(StringName(terrain_data.get("profile", "")), int(map["seed"]), bounds):
		_add(result.errors, &"INVALID_TERRAIN", "terrain profile, seed, or bounds are invalid", &"terrain")
		return result
	result.terrain = terrain
	var hill_reserved: Array[Dictionary] = _compile_hills(spec.get("hills", []), terrain, bounds, result)
	var reserved: Array[Dictionary] = _compile_paths(spec, terrain, bounds, result)
	reserved.append_array(hill_reserved)
	_compile_bridges(spec.get("bridges", []), terrain, bounds, result)
	var occupied: Array[Dictionary] = reserved.duplicate(true)
	_compile_walls(spec.get("walls", []), terrain, bounds, occupied, result)
	_compile_placements(spec.get("structures", []), &"structure", terrain, bounds, occupied, result)
	_compile_placements(spec.get("vegetation", []), &"vegetation", terrain, bounds, occupied, result)
	_compile_placements(spec.get("pickups", []), &"pickup", terrain, bounds, occupied, result)
	_compile_placements(spec.get("interactables", []), &"prop", terrain, bounds, occupied, result)
	_compile_actor_visuals(spec.get("actors", []), terrain, bounds, result)
	if not result.errors.is_empty():
		return result
	# Character footprints reserve space from the scatter generator only. They
	# stay out of `occupied` so _validate_spawns does not read a spawn's own
	# reservation as the structure it is standing in.
	var scatter_reserved: Array[Dictionary] = occupied.duplicate(true)
	for spawn in spec.get("spawn_points", []):
		scatter_reserved.append({"point": _point(spawn.get("position", [])), "radius": CHARACTER_CLEARANCE_M, "id": StringName(spawn.get("id", "spawn"))})
	for actor in spec.get("actors", []):
		scatter_reserved.append({"point": _point(actor.get("position", [])), "radius": CHARACTER_CLEARANCE_M, "id": StringName(actor.get("id", "actor"))})
	var generator := VegetationGenerator.new()
	for region in spec.get("regions", []):
		var generated := generator.generate(region, int(map["seed"]), terrain, scatter_reserved)
		for placement in generated:
			var entry := {"point": Vector2(placement.position.x, placement.position.z), "radius": placement.radius, "id": placement.id}
			scatter_reserved.append(entry)
			occupied.append(entry)
			result.placements.append(placement)
	_validate_spawns(spec.get("spawn_points", []), bounds, occupied, result.errors)
	if not result.errors.is_empty():
		return result
	result.root = Node3D.new()
	result.root.name = "CompiledMap_%s" % map["id"]
	result.root.add_child(CompiledTerrain.create(terrain, StringName(terrain_data.get("surface", "grass"))))
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
		var definition := AssetCatalog.get_definition(placement.asset)
		node.position = placement.position + (definition.display_offset if definition != null else Vector3.ZERO)
		node.rotation.y = placement.rotation_y + (definition.display_rotation_y if definition != null else 0.0)
		node.scale = placement.get("visual_scale", Vector3.ONE)
		result.root.add_child(node)
		# Hills reshape the terrain collision mesh itself (ADR-007), so a
		# separate runtime blocker would only duplicate collision. Authored
		# characters are visual anchors that the composition root replaces with
		# CharacterView instances; leaving a static blocker at the same position
		# would make every line-of-sight ray hit the target's hidden anchor.
		# Scatter that a character walks through or steps over gets no physics
		# body at all: a grass tuft must not stop the player or eat a
		# line-of-sight ray. Props and structures stay solid regardless, since
		# blocks_navigation is off for chests and barrels that are still objects.
		if definition != null and definition.asset_type not in [&"terrain_feature", &"character"] and (definition.asset_type != &"vegetation" or definition.blocks_navigation):
			result.root.add_child(MapRuntimeBlocker.create(placement.id, placement.position, definition, placement.rotation_y, placement.get("collision_size", Vector3.ZERO)))
	if not result.errors.is_empty():
		result.root.queue_free()
		result.root = null
		return result
	result.navigation = MapNavigationCompiler.new()
	result.navigation.build(terrain, _navigation_blockers(result.placements, result.paths, result.bridges), result.root)
	_validate_reachability(spec, result.navigation, result.errors)
	if not result.errors.is_empty():
		result.root.queue_free()
		result.root = null
		return result
	var quality := MapQualityAnalyzer.new().analyze(terrain, result.placements, result.navigation, spec)
	result.warnings = quality.warnings
	result.scorecard = quality.scorecard
	return result


## Hills reshape the heightfield rather than sit on it (ADR-007), so they are
## compiled before anything else that reads terrain -- paths, walls, other
## placements, and vegetation all see the stamped result for free. Unlike
## _compile_placements, there is no slope gate: a hill's whole purpose is to
## override the terrain it is placed on, not be rejected by it.
func _compile_hills(raw_hills: Array, terrain: TerrainProvider, bounds: Vector2, result: MapCompilationResult) -> Array[Dictionary]:
	var reserved: Array[Dictionary] = []
	for raw in raw_hills:
		var id := StringName(raw.get("id", ""))
		var asset := StringName(raw.get("asset", ""))
		var definition := AssetCatalog.get_definition(asset)
		if definition == null or not definition.is_usable() or definition.asset_type != &"terrain_feature":
			_add(result.errors, &"UNKNOWN_ASSET", "'%s' references unknown catalog hill asset '%s'" % [id, asset], id, {"asset": asset})
			continue
		var point := _point(raw.get("position", []))
		if not _fits_bounds(point, definition.footprint_radius, bounds):
			_add(result.errors, &"OUT_OF_BOUNDS", "'%s' footprint is outside map bounds" % id, id)
			continue
		for other in reserved:
			if point.distance_to(other.point) < definition.footprint_radius + float(other.radius):
				_add(result.errors, &"OVERLAP", "'%s' overlaps reserved area '%s'" % [id, other.get("id", "area")], id)
				break
		if not result.errors.is_empty() and result.errors.back().entity_id == id:
			continue
		var rotation_y := deg_to_rad(float(raw.get("rotation_deg", 0.0)))
		var base_elevation := terrain.height_at(point.x, point.y)
		if terrain.has_method("stamp_hill"):
			terrain.call("stamp_hill", point, rotation_y, definition.collision_size, base_elevation)
		reserved.append({"point": point, "radius": definition.footprint_radius, "id": id})
		result.placements.append({"id": id, "asset": asset, "position": Vector3(point.x, base_elevation, point.y), "rotation_y": rotation_y, "radius": definition.footprint_radius})
	return reserved


func _compile_placements(raw_placements: Array, expected_type: StringName, terrain: TerrainProvider, bounds: Vector2, occupied: Array[Dictionary], result: MapCompilationResult) -> void:
	for raw in raw_placements:
		var id := StringName(raw.get("id", ""))
		var asset := StringName(raw.get("asset", ""))
		var definition := AssetCatalog.get_definition(asset)
		if definition == null or not definition.is_usable():
			_add(result.errors, &"UNKNOWN_ASSET", "'%s' references unknown catalog asset '%s'" % [id, asset], id, {"asset": asset})
			continue
		if definition.asset_type != expected_type:
			_add(result.errors, &"INVALID_ASSET_TYPE", "'%s' must use a %s asset" % [id, expected_type], id, {"asset": asset})
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


## MapSpec actors are authored as catalog archetype IDs.  This compiler only
## creates their visual anchors; encounter ownership and BattleState remain
## outside the map-presentation compiler.
func _compile_actor_visuals(raw_actors: Array, terrain: TerrainProvider, bounds: Vector2, result: MapCompilationResult) -> void:
	for raw in raw_actors:
		var id := StringName(raw.get("id", ""))
		var asset := StringName(raw.get("archetype", ""))
		var definition := AssetCatalog.get_definition(asset)
		if definition == null or not definition.is_usable() or definition.asset_type != &"character":
			_add(result.errors, &"INVALID_ACTOR_ASSET", "actor '%s' requires a catalog character archetype" % id, id, {"asset": asset})
			continue
		var point := _point(raw.get("position", []))
		if not _fits_bounds(point, definition.footprint_radius, bounds):
			_add(result.errors, &"OUT_OF_BOUNDS", "actor '%s' footprint is outside map bounds" % id, id)
			continue
		result.placements.append({"id": id, "asset": asset, "position": Vector3(point.x, terrain.height_at(point.x, point.y), point.y), "rotation_y": deg_to_rad(float(raw.get("rotation_deg", 0.0))), "radius": definition.footprint_radius})


func _compile_walls(raw_walls: Array, terrain: TerrainProvider, bounds: Vector2, occupied: Array[Dictionary], result: MapCompilationResult) -> void:
	for raw in raw_walls:
		var id := StringName(raw.get("id", ""))
		var definition := AssetCatalog.get_definition(StringName(raw.get("asset", "")))
		var points := _points(raw.get("control_points", []))
		if definition == null or not definition.is_usable() or not definition.has_box_collision():
			_add(result.errors, &"INVALID_WALL_ASSET", "wall '%s' requires a catalog asset with box collision" % id, id)
			continue
		if points.size() != 2 or points[0].distance_to(points[1]) <= 0.001:
			_add(result.errors, &"INVALID_WALL", "wall '%s' needs two distinct control points" % id, id)
			continue
		if not _fits_bounds(points[0], 0.0, bounds) or not _fits_bounds(points[1], 0.0, bounds):
			_add(result.errors, &"OUT_OF_BOUNDS", "wall '%s' endpoint is outside map bounds" % id, id)
			continue
		var direction := (points[1] - points[0]).normalized()
		var length := points[0].distance_to(points[1])
		var offset := 0.0
		var part := 0
		while offset < length - 0.001:
			var part_length := minf(definition.collision_size.x, length - offset)
			var center := points[0] + direction * (offset + part_length * 0.5)
			var radius := Vector2(part_length * 0.5, definition.collision_size.z * 0.5).length()
			occupied.append({"point": center, "radius": radius, "id": id})
			var collision_size := Vector3(part_length, definition.collision_size.y, definition.collision_size.z)
			result.placements.append({"id": &"%s_%d" % [id, part + 1], "asset": definition.id, "position": Vector3(center.x, terrain.height_at(center.x, center.y), center.y), "rotation_y": atan2(-direction.y, direction.x), "radius": radius, "collision_size": collision_size, "visual_scale": Vector3(part_length / definition.collision_size.x, 1.0, 1.0)})
			offset += part_length
			part += 1


func _compile_paths(spec: Dictionary, terrain: TerrainProvider, bounds: Vector2, result: MapCompilationResult) -> Array[Dictionary]:
	var reserved: Array[Dictionary] = []
	for collection in [&"rivers", &"roads"]:
		var kind := &"river" if collection == &"rivers" else &"road"
		for raw in spec.get(collection, []):
			# MapSpec control points are `[x, z]` meters. Adjacent duplicate points
			# are removed so every remaining segment is safe to render and query.
			var points := _non_degenerate_points(_points(raw.get("control_points", [])))
			var id := StringName(raw.get("id", ""))
			if points.size() < 2:
				_add(result.errors, &"MISSING_REQUIRED_DATA", "'%s' needs at least two control points" % id, id)
				continue
			for point in points:
				if not _fits_bounds(point, 0.0, bounds):
					_add(result.errors, &"OUT_OF_BOUNDS", "'%s' control point is outside map bounds" % id, id)
			var width := float(raw.get("width_m", 2.0)) * 0.5
			if width <= 0.0:
				_add(result.errors, &"MISSING_REQUIRED_DATA", "'%s' needs a positive width_m" % id, id)
				continue
			if kind == &"road" and terrain.has_method("add_flattening_path"):
				terrain.call("add_flattening_path", points, width)
			var path := {"id": id, "kind": kind, "points": points, "width": width}
			if kind == &"river" and bool(spec.get("debug_rivers", false)):
				path["debug_rivers"] = true
			if kind == &"river" and terrain.has_method("add_riverbed_path"):
				path["water_height"] = terrain.call("add_riverbed_path", points, width)
			result.paths.append(path)
			for point in points:
				reserved.append({"point": point, "radius": width, "id": id})
	for river in result.paths.filter(func(path: Dictionary) -> bool: return path.kind == &"river"):
		for road in result.paths.filter(func(path: Dictionary) -> bool: return path.kind == &"road"):
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
	for group in ["structures", "walls", "vegetation", "hills", "pickups", "interactables", "actors", "spawn_points", "regions", "rivers", "roads", "bridges", "objectives", "encounters", "doors", "dialogs"]:
		if spec.has(group) and not spec[group] is Array:
			_add(errors, &"MISSING_REQUIRED_DATA", "'%s' must be an array" % group, StringName(group))
	var id_regex := RegEx.new()
	id_regex.compile(ID_PATTERN)
	for group in ["structures", "walls", "vegetation", "hills", "pickups", "interactables", "actors", "spawn_points", "regions", "rivers", "roads", "bridges", "objectives", "encounters", "doors", "dialogs"]:
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


func _non_degenerate_points(points: PackedVector2Array) -> PackedVector2Array:
	var cleaned := PackedVector2Array()
	for point in points:
		if cleaned.is_empty() or cleaned[-1].distance_squared_to(point) > 0.000001:
			cleaned.append(point)
	return cleaned


func _fits_bounds(point: Vector2, radius: float, bounds: Vector2) -> bool:
	return is_finite(point.x) and is_finite(point.y) and point.x - radius >= 0.0 and point.y - radius >= 0.0 and point.x + radius <= bounds.x and point.y + radius <= bounds.y


## Cross-references the schema cannot express: a dialog id an actor names must
## exist, every node id an outcome jumps to must exist inside that same dialog,
## a stat_block must be real content, and a dialog that pacifies or starts a
## fight needs an encounter to act on -- otherwise those outcomes silently
## no-op at runtime.
func _validate_dialog_references(spec: Dictionary, errors: Array[MapValidationError]) -> void:
	var id_regex := RegEx.new()
	id_regex.compile(ID_PATTERN)
	var node_ids_by_dialog: Dictionary = {}
	var group_effects_by_dialog: Dictionary = {}
	for dialog in spec.get("dialogs", []):
		var dialog_id := String(dialog.get("id", ""))
		var node_ids: Array[String] = []
		var uses_encounter := false
		for node in dialog.get("nodes", []):
			var node_id := String(node.get("id", ""))
			var matched := id_regex.search(node_id)
			if matched == null or matched.get_string() != node_id:
				_add(errors, &"MALFORMED_ID", "dialog '%s' has malformed node id '%s'" % [dialog_id, node_id], StringName(dialog_id))
				continue
			if node_ids.has(node_id):
				_add(errors, &"DUPLICATE_DIALOG_NODE", "dialog '%s' declares node '%s' twice" % [dialog_id, node_id], StringName(dialog_id))
				continue
			node_ids.append(node_id)
		node_ids_by_dialog[dialog_id] = node_ids
		var root := String(dialog.get("root", ""))
		if not node_ids.has(root):
			_add(errors, &"UNKNOWN_DIALOG_NODE", "dialog '%s' opens on unknown node '%s'" % [dialog_id, root], StringName(dialog_id))
		for node in dialog.get("nodes", []):
			for option in node.get("options", []):
				if option.has("check") and not option.has("failure_outcome"):
					_add(errors, &"INVALID_DIALOG_OPTION", "dialog '%s' node '%s' has a check with no failure_outcome" % [dialog_id, node.get("id", "")], StringName(dialog_id))
				if option.has("coin_cost"):
					var coin_cost: Variant = option.get("coin_cost")
					# JSON parsing represents numeric literals as floats in Godot; accept
					# only positive whole values so the runtime agrees with the schema's
					# integer contract without rejecting valid authored map data.
					var is_positive_integer := (typeof(coin_cost) == TYPE_INT or (typeof(coin_cost) == TYPE_FLOAT and is_equal_approx(float(coin_cost), floorf(float(coin_cost))))) and float(coin_cost) > 0.0
					if not is_positive_integer:
						_add(errors, &"INVALID_DIALOG_OPTION", "dialog '%s' node '%s' has a non-positive coin_cost" % [dialog_id, node.get("id", "")], StringName(dialog_id))
					if option.has("check"):
						_add(errors, &"INVALID_DIALOG_OPTION", "dialog '%s' node '%s' combines coin_cost with check" % [dialog_id, node.get("id", "")], StringName(dialog_id))
				for key in ["outcome", "failure_outcome"]:
					var outcome: Dictionary = option.get(key, {})
					var next := String(outcome.get("next", ""))
					if not next.is_empty() and not node_ids.has(next):
						_add(errors, &"UNKNOWN_DIALOG_NODE", "dialog '%s' node '%s' jumps to unknown node '%s'" % [dialog_id, node.get("id", ""), next], StringName(dialog_id))
					var effect := String(outcome.get("effect", "none"))
					uses_encounter = uses_encounter or effect == "pacify_encounter" or effect == "start_combat"
		group_effects_by_dialog[dialog_id] = uses_encounter
	var encountered_actor_ids: Array[String] = []
	for encounter in spec.get("encounters", []):
		for actor_id in encounter.get("actor_ids", []):
			encountered_actor_ids.append(str(actor_id))
	# An encounter whose members are all neutral and none of whom carry a dialog
	# can never start (detection only fires on a hostile actor) and can never be
	# parleyed. It is scenery the player will walk past with no feedback at all.
	var actors_by_id: Dictionary = {}
	for actor in spec.get("actors", []):
		actors_by_id[String(actor.get("id", ""))] = actor
	for encounter in spec.get("encounters", []):
		var members: Array = encounter.get("actor_ids", [])
		if members.is_empty():
			continue
		var can_trigger := false
		var can_talk := false
		for member_id in members:
			var member: Dictionary = actors_by_id.get(str(member_id), {})
			can_trigger = can_trigger or String(member.get("initial_disposition", "hostile")) == "hostile"
			can_talk = can_talk or not String(member.get("dialog", "")).is_empty()
		if not can_trigger and not can_talk:
			_add(errors, &"INERT_ENCOUNTER", "encounter '%s' is all-neutral and has no dialog, so it can never start or be talked to" % encounter.get("id", "encounter"), StringName(encounter.get("id", "")))
	var definitions := DefinitionLibrary.get_default()
	for actor in spec.get("actors", []):
		var actor_id := String(actor.get("id", ""))
		var stat_block := String(actor.get("stat_block", ""))
		if not stat_block.is_empty() and not definitions.has_actor(StringName(stat_block)):
			_add(errors, &"UNKNOWN_STAT_BLOCK", "actor '%s' names unknown stat_block '%s'" % [actor_id, stat_block], StringName(actor_id))
		var dialog_id := String(actor.get("dialog", ""))
		if dialog_id.is_empty():
			continue
		if not node_ids_by_dialog.has(dialog_id):
			_add(errors, &"UNKNOWN_DIALOG", "actor '%s' names unknown dialog '%s'" % [actor_id, dialog_id], StringName(actor_id))
		elif bool(group_effects_by_dialog.get(dialog_id, false)) and not encountered_actor_ids.has(actor_id):
			_add(errors, &"DIALOG_WITHOUT_ENCOUNTER", "actor '%s' runs dialog '%s', which pacifies or starts an encounter, but belongs to none" % [actor_id, dialog_id], StringName(actor_id))


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
		result.bridges.append({"id": id, "asset": StringName(raw.get("asset", "")), "position": Vector3(point.x, terrain.height_at(point.x, point.y) + 0.12, point.y), "radius": definition.footprint_radius, "river_id": StringName(raw.get("river_id", "")), "road_id": StringName(raw.get("road_id", ""))})


func _has_compatible_bridge(bridges: Array, river: Dictionary, road: Dictionary) -> bool:
	for bridge in bridges:
		if StringName(bridge.get("river_id", "")) == river.id and StringName(bridge.get("road_id", "")) == road.id:
			var definition := AssetCatalog.get_definition(StringName(bridge.get("asset", "")))
			if definition != null and definition.asset_type == &"bridge":
				return true
	return false


func _navigation_blockers(placements: Array[Dictionary], paths: Array[Dictionary] = [], bridges: Array[Dictionary] = []) -> Array[Dictionary]:
	var blockers: Array[Dictionary] = []
	for placement in placements:
		var definition := AssetCatalog.get_definition(placement.asset)
		if definition != null and definition.blocks_navigation:
			var blocker := {"point": Vector2(placement.position.x, placement.position.z), "radius": definition.blocking_radius(), "id": placement.id}
			if definition.has_box_collision():
				blocker["kind"] = &"box"
				blocker["size"] = placement.get("collision_size", definition.collision_size)
				blocker["rotation_y"] = placement.rotation_y
			blockers.append(blocker)
	for river in paths:
		if river.kind != &"river":
			continue
		var crossings: Array[Dictionary] = []
		for bridge in bridges:
			if bridge.get("river_id", &"") == river.id and _bridge_crosses_river(bridge, river, paths):
				crossings.append({"point": Vector2(bridge.position.x, bridge.position.z), "radius": bridge.radius})
		blockers.append({"kind": &"river", "points": river.points, "width": river.width, "crossings": crossings, "id": river.id})
	return blockers


func _bridge_crosses_river(bridge: Dictionary, river: Dictionary, paths: Array[Dictionary]) -> bool:
	for road in paths:
		if road.kind == &"road" and road.id == bridge.get("road_id", &"") and _paths_cross(river.points, road.points):
			return true
	return false
