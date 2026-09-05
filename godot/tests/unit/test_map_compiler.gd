class_name TestMapCompiler
extends RefCounted

const TerrainScript = preload("res://world/procedural_terrain_provider.gd")
const VegetationScript = preload("res://world/vegetation_generator.gd")
const CompilerScript = preload("res://world/map_compiler.gd")
const MapSpecSourceScript = preload("res://world/map_spec_source.gd")


static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_terrain_profiles_and_queries(failures)
	_test_external_map_spec_path(failures)
	_test_terrain_seed_variation_and_edge_normals(failures)
	_test_terrain_surface_materials(failures)
	_test_vegetation_is_deterministic_and_respects_clearance(failures)
	_test_compiler_places_reference_map_and_reports_spatial_errors(failures)
	_test_compiler_places_actor_visuals(failures)
	_test_paths_are_deterministic_and_crossings_fail(failures)
	_test_navigation_reachability(failures)
	_test_wall_blockers_match_navigation(failures)
	_test_authored_wall_path_is_tiled(failures)
	_test_quality_scorecard_is_advisory_and_repeatable(failures)
	return {"name": "unit/test_map_compiler", "failures": failures}


static func _test_terrain_profiles_and_queries(failures: Array[String]) -> void:
	var a := TerrainScript.new()
	var b := TerrainScript.new()
	_expect(a.generate(&"rolling_hills", 42, Vector2(64, 64)) and b.generate(&"rolling_hills", 42, Vector2(64, 64)), "procedural terrain rejected valid input", failures)
	_expect(is_equal_approx(a.height_at(12, 31), b.height_at(12, 31)), "terrain is not repeatable", failures)
	_expect(not is_zero_approx(a.height_at(12, 31)), "rolling hills behaves as flat", failures)
	_expect(a.normal_at(12, 31).length() > 0.99 and a.slope_at(12, 31) > 0.0, "terrain normal/slope query is invalid", failures)
	var valley := TerrainScript.new()
	valley.generate(&"valley", 42, Vector2(64, 64))
	_expect(valley.height_at(32, 32) < valley.height_at(2, 32), "valley center is not lower than edge", failures)
	_expect(is_nan(a.height_at(-1, 0)), "terrain bounds failure did not return NAN", failures)


static func _test_external_map_spec_path(failures: Array[String]) -> void:
	var source := MapSpecSourceScript.new("../world_authoring/maps/test_map.json")
	var spec: Dictionary = source.load_spec()
	var map: Dictionary = spec.get("map", {})
	var bounds: Dictionary = map.get("bounds", {})
	_expect(not spec.is_empty() and bounds.get("width_m", 0) == 64, "external authoring MapSpec did not resolve: %s" % source.last_error, failures)


static func _test_terrain_seed_variation_and_edge_normals(failures: Array[String]) -> void:
	var first := TerrainScript.new()
	var second := TerrainScript.new()
	first.generate(&"rolling_hills", 17, Vector2(64, 64))
	second.generate(&"rolling_hills", 18, Vector2(64, 64))
	var differences := 0
	for x in range(4, 64, 8):
		for z in range(4, 64, 8):
			if not is_equal_approx(first.height_at(x, z), second.height_at(x, z)):
				differences += 1
	_expect(differences > 24, "different terrain seeds do not produce structurally different fields", failures)
	var edge_slope := first.slope_at(0, 32)
	var near_edge_slope := first.slope_at(1, 32)
	_expect(absf(edge_slope - near_edge_slope) < 12.0, "edge terrain normal is inconsistent with the cached heightfield", failures)


static func _test_terrain_surface_materials(failures: Array[String]) -> void:
	var terrain := TerrainScript.new()
	terrain.generate(&"flat", 7, Vector2(8, 8))
	var sand := CompiledTerrain.create(terrain, &"sand")
	var visual := sand.get_child(0) as MeshInstance3D
	var material := visual.mesh.surface_get_material(0) as ShaderMaterial
	_expect(material != null, "terrain surface does not use a tileable material", failures)
	_expect(material.get_shader_parameter(&"base_color") == Color("d9bc78"), "sand terrain did not select the sand palette", failures)
	sand.free()


static func _test_vegetation_is_deterministic_and_respects_clearance(failures: Array[String]) -> void:
	var terrain := TerrainScript.new()
	terrain.generate(&"flat", 7, Vector2(32, 32))
	var region := {"id": "grove", "polygon": [[0, 0], [32, 0], [32, 32], [0, 32]], "vegetation": {"profile": "temperate_sparse", "density": 0.4}}
	var generator := VegetationScript.new()
	var first := generator.generate(region, 99, terrain, [{"point": Vector2(16, 16), "radius": 10.0}])
	var second := generator.generate(region, 99, terrain, [{"point": Vector2(16, 16), "radius": 10.0}])
	_expect(first == second and not first.is_empty(), "vegetation placement is not deterministic", failures)
	for placement in first:
		_expect(placement.position.x >= 0 and placement.position.x <= 32 and placement.position.z >= 0 and placement.position.z <= 32, "vegetation escaped bounds", failures)
		_expect(Vector2(placement.position.x, placement.position.z).distance_to(Vector2(16, 16)) >= 10.0 + placement.radius, "vegetation ignored clearance", failures)
		_expect(AssetCatalog.get_definition(placement.asset) != null, "vegetation emitted invalid asset", failures)


static func _test_compiler_places_reference_map_and_reports_spatial_errors(failures: Array[String]) -> void:
	var compiler := CompilerScript.new()
	var valid := {"map": {"id": "test_map", "seed": 4, "bounds": {"width_m": 32, "height_m": 32}}, "terrain": {"profile": "flat"}, "structures": [{"id": "wall", "asset": "barrier_dungeon_01", "position": [20, 20]}], "spawn_points": [{"id": "start", "position": [2, 2]}]}
	var result := compiler.compile(valid)
	_expect(result.is_valid() and result.root != null and result.placements.size() == 1, "basic compiler path did not produce a map", failures)
	if result.root != null:
		result.root.free()
	var invalid := valid.duplicate(true)
	invalid.structures[0].position = [0, 0]
	var rejected := compiler.compile(invalid)
	_expect(not rejected.is_valid() and rejected.errors[0].code == &"OUT_OF_BOUNDS", "structure footprint failure lacks stable error", failures)


static func _test_navigation_reachability(failures: Array[String]) -> void:
	var compiler := CompilerScript.new()
	var spec := {"map": {"id": "path_map", "seed": 1, "bounds": {"width_m": 32, "height_m": 32}}, "terrain": {"profile": "flat"}, "structures": [{"id": "wall", "asset": "wall_run_dungeon_01", "position": [16, 16]}], "spawn_points": [{"id": "start", "position": [1, 1]}], "objectives": [{"id": "goal", "position": [31, 31]}]}
	var result := compiler.compile(spec)
	_expect(result.is_valid() and result.navigation.is_reachable(Vector2(1, 1), Vector2(31, 31)), "navigation did not preserve reachable route", failures)
	if result.root != null:
		result.root.free()


static func _test_compiler_places_actor_visuals(failures: Array[String]) -> void:
	var compiler := CompilerScript.new()
	var spec := {"map": {"id": "actor_visual_map", "seed": 1, "bounds": {"width_m": 64, "height_m": 64}}, "terrain": {"profile": "flat"}, "actors": [{"id": "guard", "archetype": "character_knight_01", "position": [32, 16]}]}
	var result := compiler.compile(spec)
	_expect(result.is_valid() and result.root != null and result.root.get_node_or_null("guard") != null, "actor archetype did not compile into a visual node", failures)
	if result.root != null:
		result.root.free()


static func _test_wall_blockers_match_navigation(failures: Array[String]) -> void:
	var compiler := CompilerScript.new()
	var spec := {"map": {"id": "wall_collision_map", "seed": 1, "bounds": {"width_m": 32, "height_m": 32}}, "terrain": {"profile": "flat"}, "structures": [{"id": "wall", "asset": "wall_dungeon_01", "position": [16, 16], "rotation_deg": 90}], "spawn_points": [{"id": "start", "position": [2, 2]}]}
	var result := compiler.compile(spec)
	_expect(result.is_valid(), "wall collision fixture did not compile", failures)
	if result.root == null:
		return
	var blocker := result.root.get_node_or_null("wall_Blocker") as MapRuntimeBlocker
	var collision := blocker.get_child(0) as CollisionShape3D if blocker != null else null
	var box := collision.shape as BoxShape3D if collision != null else null
	_expect(box != null and box.size == Vector3(4, 4, 1), "wall did not receive its authored box collider", failures)
	_expect(blocker != null and is_equal_approx(blocker.rotation.y, PI * 0.5), "wall collider did not retain placement rotation", failures)
	_expect(result.navigation._walkable(Vector2(16, 16)) == false, "navigation still treats the wall center as walkable", failures)
	_expect(result.navigation._walkable(Vector2(16, 18)) == false, "navigation did not preserve player clearance along the wall", failures)
	_expect(result.navigation._walkable(Vector2(16, 19)), "navigation over-blocked space beyond the wall", failures)
	result.root.free()


static func _test_authored_wall_path_is_tiled(failures: Array[String]) -> void:
	var compiler := CompilerScript.new()
	var spec := {"map": {"id": "authored_wall_map", "seed": 1, "bounds": {"width_m": 32, "height_m": 32}}, "terrain": {"profile": "flat"}, "walls": [{"id": "wall_path", "asset": "wall_dungeon_01", "control_points": [[4, 8], [14, 8]]}], "spawn_points": [{"id": "start", "position": [2, 2]}]}
	var result := compiler.compile(spec)
	_expect(result.is_valid() and result.placements.size() == 3, "authored wall was not split into visual/collision modules", failures)
	if result.root == null:
		return
	var final_blocker := result.root.get_node_or_null("wall_path_3_Blocker") as MapRuntimeBlocker
	var collision := final_blocker.get_child(0) as CollisionShape3D if final_blocker != null else null
	var shape := collision.shape as BoxShape3D if collision != null else null
	_expect(shape != null and is_equal_approx(shape.size.x, 2.0), "wall end module does not stop at point B", failures)
	_expect(result.navigation._walkable(Vector2(9, 8)) == false, "authored wall path does not block navigation", failures)
	result.root.free()


static func _test_paths_are_deterministic_and_crossings_fail(failures: Array[String]) -> void:
	var compiler := CompilerScript.new()
	var base := {"map": {"id": "path_fixture", "seed": 1, "bounds": {"width_m": 32, "height_m": 32}}, "terrain": {"profile": "flat"}, "rivers": [{"id": "river", "control_points": [[0, 16], [32, 16]], "width_m": 3.0}]}
	var first := compiler.compile(base)
	var second := compiler.compile(base)
	var river_renderer := first.root.get_node_or_null("river") as MapPathRenderer if first.root != null else null
	var river_visual := river_renderer.get_node_or_null("Water") as MeshInstance3D if river_renderer != null else null
	var river_material := river_visual.mesh.surface_get_material(0) as ShaderMaterial if river_visual != null else null
	_expect(first.is_valid() and first.paths == second.paths and river_renderer != null, "path ribbon did not compile deterministically", failures)
	_expect(first.paths.size() == 1 and first.paths[0].kind == &"river" and river_material != null and river_visual.mesh.get_surface_count() == 1, "river path did not compile with water rendering", failures)
	var boundary_a := MapPathRenderer.ribbon_boundaries(first.paths[0].points, first.paths[0].width)
	var boundary_b := MapPathRenderer.ribbon_boundaries(second.paths[0].points, second.paths[0].width)
	_expect(boundary_a == boundary_b and boundary_a.size() == 4, "river ribbon geometry is not deterministic", failures)
	_expect(first.terrain.height_at(16, 16) < first.terrain.height_at(16, 19), "riverbed is not lower than its bank", failures)
	_expect(not first.navigation.is_reachable(Vector2(16, 8), Vector2(16, 24)), "river did not block navigation", failures)
	if first.root != null:
		first.root.free()
	if second.root != null:
		second.root.free()
	var crossing := base.duplicate(true)
	crossing.roads = [{"id": "road", "control_points": [[16, 0], [16, 32]]}]
	var rejected := compiler.compile(crossing)
	_expect(not rejected.is_valid() and rejected.errors[0].code == &"INVALID_RIVER_CROSSING", "river crossing lacks stable validation error", failures)
	var bridged := crossing.duplicate(true)
	bridged.bridges = [{"id": "ford", "asset": "bridge_wood_01", "position": [16, 16], "river_id": "river", "road_id": "road"}]
	var accepted := compiler.compile(bridged)
	_expect(accepted.is_valid() and accepted.bridges.size() == 1, "catalog bridge did not permit a matching river crossing", failures)
	_expect(accepted.navigation.is_reachable(Vector2(16, 8), Vector2(16, 24)), "compatible bridge did not open a river crossing", failures)
	if accepted.root != null:
		accepted.root.free()
	var degenerate := base.duplicate(true)
	degenerate.rivers[0].control_points = [[8, 8], [8, 8]]
	var safely_rejected := compiler.compile(degenerate)
	_expect(not safely_rejected.is_valid() and safely_rejected.errors[0].code == &"MISSING_REQUIRED_DATA", "degenerate river was not safely rejected", failures)


static func _test_quality_scorecard_is_advisory_and_repeatable(failures: Array[String]) -> void:
	var compiler := CompilerScript.new()
	var spec := {"map": {"id": "quality_map", "seed": 9, "bounds": {"width_m": 32, "height_m": 32}}, "terrain": {"profile": "rolling_hills"}, "spawn_points": [{"id": "start", "position": [2, 2]}], "objectives": [{"id": "near_goal", "position": [3, 2]}]}
	var first := compiler.compile(spec)
	var second := compiler.compile(spec)
	_expect(first.is_valid() and not first.scorecard.is_empty(), "valid map did not receive an advisory quality scorecard", failures)
	_expect(not first.warnings.is_empty(), "degenerate tactical map did not receive advisory warnings", failures)
	_expect(first.scorecard == second.scorecard and first.warning_dicts() == second.warning_dicts(), "quality analysis is not deterministic", failures)
	if first.root != null:
		first.root.free()
	if second.root != null:
		second.root.free()


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
