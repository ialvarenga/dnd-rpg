class_name TestMapCompiler
extends RefCounted

const TerrainScript = preload("res://world/procedural_terrain_provider.gd")
const VegetationScript = preload("res://world/vegetation_generator.gd")
const CompilerScript = preload("res://world/map_compiler.gd")


static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_terrain_profiles_and_queries(failures)
	_test_terrain_surface_materials(failures)
	_test_vegetation_is_deterministic_and_respects_clearance(failures)
	_test_compiler_places_reference_map_and_reports_spatial_errors(failures)
	_test_paths_are_deterministic_and_crossings_fail(failures)
	_test_navigation_reachability(failures)
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


static func _test_paths_are_deterministic_and_crossings_fail(failures: Array[String]) -> void:
	var compiler := CompilerScript.new()
	var base := {"map": {"id": "path_fixture", "seed": 1, "bounds": {"width_m": 32, "height_m": 32}}, "terrain": {"profile": "flat"}, "rivers": [{"id": "river", "control_points": [[0, 16], [32, 16]], "width_m": 3.0}]}
	var first := compiler.compile(base)
	var second := compiler.compile(base)
	_expect(first.is_valid() and first.paths == second.paths and first.root.get_node("river") is MapPathRenderer, "path ribbon did not compile deterministically", failures)
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
	if accepted.root != null:
		accepted.root.free()


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
