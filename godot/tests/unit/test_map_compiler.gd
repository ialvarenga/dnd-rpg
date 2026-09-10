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
	_test_hills_are_compiled_and_present_in_navmesh(failures)
	_test_hill_excludes_generated_vegetation(failures)
	_test_hill_rejects_overlapping_placement(failures)
	_test_walkover_scatter_has_no_blocker(failures)
	_test_collision_is_measured_at_walk_height(failures)
	_test_dense_forest_stays_walkable(failures)
	_test_scatter_respects_poisson_spacing(failures)
	_test_scatter_density_is_patchy(failures)
	_test_dialog_and_stat_block_cross_references(failures)
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


## The authored map this suite loads is the one the game ships as its main
## scene, so resolving it is not enough: compile it too. Every spatial rule
## (bounds, slope, overlap, river crossings, spawn clearance, objective and
## encounter reachability) is only ever enforced here.
static func _test_external_map_spec_path(failures: Array[String]) -> void:
	var source := MapSpecSourceScript.new("../world_authoring/maps/test_map.json")
	var spec: Dictionary = source.load_spec()
	var map: Dictionary = spec.get("map", {})
	var bounds: Dictionary = map.get("bounds", {})
	_expect(not spec.is_empty() and bounds.get("width_m", 0) == 176, "external authoring MapSpec did not resolve: %s" % source.last_error, failures)
	if spec.is_empty():
		return
	var compilation: MapCompilationResult = CompilerScript.new().compile(spec)
	_expect(compilation.is_valid(), "authored test map failed to compile: %s" % str(compilation.error_dicts()), failures)
	if compilation.root != null:
		compilation.root.free()


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
	var generator := VegetationScript.new()
	var first: Array[Dictionary] = []
	for profile in ["temperate_sparse", "temperate_dense", "old_growth", "meadow", "rocky_scrub", "thicket"]:
		var region := {"id": "grove", "polygon": [[0, 0], [32, 0], [32, 32], [0, 32]], "vegetation": {"profile": profile, "density": 0.4}}
		var run_a := generator.generate(region, 99, terrain, [{"point": Vector2(16, 16), "radius": 10.0}])
		var run_b := generator.generate(region, 99, terrain, [{"point": Vector2(16, 16), "radius": 10.0}])
		_expect(run_a == run_b and not run_a.is_empty(), "vegetation placement is not deterministic for profile %s" % profile, failures)
		if profile == "temperate_sparse":
			first = run_a
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


## The JSON Schema can check a dialog's shape but not that its references
## resolve, so these are the checks that stop an authored conversation from
## silently jumping nowhere or pacifying nobody.
static func _dialog_spec(dialogs: Array, actors: Array, encounters: Array = []) -> Dictionary:
	return {
		"map": {"id": "dialog_map", "seed": 1, "bounds": {"width_m": 64, "height_m": 64}},
		"terrain": {"profile": "flat"},
		"actors": actors,
		"encounters": encounters,
		"dialogs": dialogs,
	}


static func _compile_codes(spec: Dictionary) -> Array[StringName]:
	var result := CompilerScript.new().compile(spec)
	var codes: Array[StringName] = []
	for error in result.errors:
		codes.append(error.code)
	if result.root != null:
		result.root.free()
	return codes


static func _test_dialog_and_stat_block_cross_references(failures: Array[String]) -> void:
	var talker := {"id": "chief", "archetype": "character_knight_01", "position": [32, 16], "dialog": "toll"}
	var encounters := [{"id": "ambush", "position": [32, 16], "actor_ids": ["chief"]}]
	var good_dialog := [{"id": "toll", "root": "greeting", "nodes": [
		{"id": "greeting", "text": "Pay up.", "options": [
			{"text": "Bluff", "check": {"ability": "charisma", "dc": 12}, "outcome": {"next": "aside"}, "failure_outcome": {"effect": "start_combat"}},
		]},
		{"id": "aside", "text": "Go on.", "options": [{"text": "Go", "outcome": {"effect": "pacify_encounter"}}]},
	]}]
	_expect(_compile_codes(_dialog_spec(good_dialog, [talker], encounters)).is_empty(), "a well-formed dialog should compile without errors", failures)

	var bad_root := [{"id": "toll", "root": "nowhere", "nodes": [{"id": "greeting", "text": "Pay up."}]}]
	_expect(_compile_codes(_dialog_spec(bad_root, [talker], encounters)).has(&"UNKNOWN_DIALOG_NODE"), "a dialog opening on a missing node should be rejected", failures)

	var bad_jump := [{"id": "toll", "root": "greeting", "nodes": [
		{"id": "greeting", "text": "Pay up.", "options": [{"text": "Go", "outcome": {"next": "missing"}}]},
	]}]
	_expect(_compile_codes(_dialog_spec(bad_jump, [talker], encounters)).has(&"UNKNOWN_DIALOG_NODE"), "an option jumping to a missing node should be rejected", failures)

	var duplicate_nodes := [{"id": "toll", "root": "greeting", "nodes": [
		{"id": "greeting", "text": "Pay up."}, {"id": "greeting", "text": "Again."},
	]}]
	_expect(_compile_codes(_dialog_spec(duplicate_nodes, [talker], encounters)).has(&"DUPLICATE_DIALOG_NODE"), "a dialog declaring one node id twice should be rejected", failures)

	var malformed_node := [{"id": "toll", "root": "greeting", "nodes": [
		{"id": "greeting", "text": "Pay up."}, {"id": "Not An Id", "text": "..."},
	]}]
	_expect(_compile_codes(_dialog_spec(malformed_node, [talker], encounters)).has(&"MALFORMED_ID"), "a malformed node id should be rejected", failures)

	var checkless_failure := [{"id": "toll", "root": "greeting", "nodes": [
		{"id": "greeting", "text": "Pay up.", "options": [{"text": "Bluff", "check": {"ability": "charisma", "dc": 12}, "outcome": {"effect": "end"}}]},
	]}]
	_expect(_compile_codes(_dialog_spec(checkless_failure, [talker], encounters)).has(&"INVALID_DIALOG_OPTION"), "a check with no failure_outcome should be rejected", failures)

	var paid_passage := [{"id": "toll", "root": "greeting", "nodes": [
		{"id": "greeting", "text": "Pay up.", "options": [{"text": "Pay", "coin_cost": 10, "outcome": {"effect": "pacify_encounter"}}]},
	]}]
	_expect(_compile_codes(_dialog_spec(paid_passage, [talker], encounters)).is_empty(), "a positive, check-free coin cost should compile", failures)
	var free_payment := [{"id": "toll", "root": "greeting", "nodes": [
		{"id": "greeting", "text": "Pay up.", "options": [{"text": "Pay", "coin_cost": 0, "outcome": {"effect": "end"}}]},
	]}]
	_expect(_compile_codes(_dialog_spec(free_payment, [talker], encounters)).has(&"INVALID_DIALOG_OPTION"), "a non-positive coin cost should be rejected", failures)
	var checked_payment := [{"id": "toll", "root": "greeting", "nodes": [
		{"id": "greeting", "text": "Pay up.", "options": [{"text": "Pay", "coin_cost": 1, "check": {"ability": "charisma", "dc": 10}, "outcome": {"effect": "end"}, "failure_outcome": {"effect": "end"}}]},
	]}]
	_expect(_compile_codes(_dialog_spec(checked_payment, [talker], encounters)).has(&"INVALID_DIALOG_OPTION"), "a coin cost combined with a check should be rejected", failures)

	var stranger := {"id": "chief", "archetype": "character_knight_01", "position": [32, 16], "dialog": "missing_dialog"}
	_expect(_compile_codes(_dialog_spec(good_dialog, [stranger], encounters)).has(&"UNKNOWN_DIALOG"), "an actor naming a missing dialog should be rejected", failures)

	# The one that actually bites in play: pacify_encounter has nothing to act
	# on when the speaker belongs to no encounter, so it would silently no-op.
	_expect(_compile_codes(_dialog_spec(good_dialog, [talker], [])).has(&"DIALOG_WITHOUT_ENCOUNTER"), "a dialog that pacifies an encounter its speaker is not in should be rejected", failures)

	# The hole that shipped once already: a camp made neutral so it can be
	# approached, but with nothing to say, is scenery the player walks past.
	var mute := {"id": "chief", "archetype": "character_knight_01", "position": [32, 16], "initial_disposition": "neutral"}
	_expect(_compile_codes(_dialog_spec([], [mute], encounters)).has(&"INERT_ENCOUNTER"), "an all-neutral encounter with no dialog should be rejected", failures)
	var mute_but_hostile := {"id": "chief", "archetype": "character_knight_01", "position": [32, 16]}
	_expect(not _compile_codes(_dialog_spec([], [mute_but_hostile], encounters)).has(&"INERT_ENCOUNTER"), "a hostile encounter needs no dialog to be reachable", failures)
	_expect(not _compile_codes(_dialog_spec(good_dialog, [talker], encounters)).has(&"INERT_ENCOUNTER"), "a neutral encounter with a dialog is reachable by talking", failures)

	var bad_block := {"id": "chief", "archetype": "character_knight_01", "position": [32, 16], "stat_block": "not_a_stat_block"}
	_expect(_compile_codes(_dialog_spec([], [bad_block])).has(&"UNKNOWN_STAT_BLOCK"), "an actor naming a missing stat block should be rejected", failures)
	var good_block := {"id": "chief", "archetype": "character_knight_01", "position": [32, 16], "stat_block": "bandit_scout"}
	_expect(not _compile_codes(_dialog_spec([], [good_block])).has(&"UNKNOWN_STAT_BLOCK"), "a real stat block should compile", failures)


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


## ADR-007: a hill reshapes the heightfield before anything else compiles, so
## the stamp must already be visible in the baked navmesh's source geometry,
## and the reachability grid must exclude the hill's footprint (via its
## slope profile and navigation-blocker box acting together).
static func _test_hills_are_compiled_and_present_in_navmesh(failures: Array[String]) -> void:
	var compiler := CompilerScript.new()
	var spec := {"map": {"id": "hill_map", "seed": 1, "bounds": {"width_m": 32, "height_m": 32}}, "terrain": {"profile": "flat"}, "hills": [{"id": "mound", "asset": "forest_hill_4x4x4", "position": [16, 16]}], "spawn_points": [{"id": "start", "position": [2, 2]}]}
	var result := compiler.compile(spec)
	_expect(result.is_valid(), "hill fixture did not compile: %s" % (result.errors[0].message if not result.errors.is_empty() else ""), failures)
	if not result.is_valid():
		return
	_expect(result.placements.size() == 1 and result.placements[0].id == &"mound", "hill did not compile into a placement", failures)
	_expect(is_equal_approx(result.placements[0].position.y, 0.0), "hill placement did not anchor at the pre-stamp base elevation", failures)
	var stamped_present := false
	for triangle in result.terrain.export_navigation_geometry():
		for vertex in triangle:
			if is_equal_approx(vertex.x, 16.0) and is_equal_approx(vertex.z, 16.0) and is_equal_approx(vertex.y, 4.0):
				stamped_present = true
	_expect(stamped_present, "stamped hill elevation is not present in the baked navmesh source geometry", failures)
	_expect(not result.navigation.is_reachable(Vector2(2, 2), Vector2(16, 16)), "hill did not exclude its footprint from the reachability grid", failures)
	_expect(result.navigation.is_reachable(Vector2(2, 2), Vector2(30, 30)), "hill over-blocked space beyond its footprint", failures)
	if result.root != null:
		result.root.free()


static func _test_hill_excludes_generated_vegetation(failures: Array[String]) -> void:
	var compiler := CompilerScript.new()
	var spec := {
		"map": {"id": "hill_vegetation_map", "seed": 3, "bounds": {"width_m": 32, "height_m": 32}},
		"terrain": {"profile": "flat"},
		"hills": [{"id": "mound", "asset": "forest_hill_4x4x4", "position": [16, 16]}],
		"regions": [{"id": "grove", "polygon": [[0, 0], [32, 0], [32, 32], [0, 32]], "vegetation": {"profile": "temperate_dense", "density": 1.0}}],
		"spawn_points": [{"id": "start", "position": [2, 2]}],
	}
	var result := compiler.compile(spec)
	_expect(result.is_valid(), "hill + vegetation fixture did not compile", failures)
	if not result.is_valid():
		return
	var hill_radius := AssetCatalog.get_definition(&"forest_hill_4x4x4").footprint_radius
	var checked_any := false
	for placement in result.placements:
		if placement.id == &"mound":
			continue
		checked_any = true
		var flat := Vector2(placement.position.x, placement.position.z)
		_expect(flat.distance_to(Vector2(16, 16)) >= hill_radius + placement.radius, "generated vegetation spawned inside the hill's footprint", failures)
	_expect(checked_any, "dense vegetation profile generated nothing to check against the hill", failures)
	if result.root != null:
		result.root.free()


static func _test_hill_rejects_overlapping_placement(failures: Array[String]) -> void:
	var compiler := CompilerScript.new()
	var spec := {"map": {"id": "hill_overlap_map", "seed": 1, "bounds": {"width_m": 32, "height_m": 32}}, "terrain": {"profile": "flat"}, "hills": [{"id": "mound", "asset": "forest_hill_4x4x4", "position": [16, 16]}], "vegetation": [{"id": "too_close", "asset": "tree_oak_01", "position": [17, 16]}]}
	var result := compiler.compile(spec)
	_expect(not result.is_valid() and not result.errors.is_empty() and result.errors[0].code == &"OVERLAP", "vegetation placed inside a hill's footprint was not rejected", failures)


## Grass and low rocks must leave no physics body behind: a walk-over prop that
## still owns a layer-8 cylinder stops the player and eats line-of-sight rays.
static func _test_walkover_scatter_has_no_blocker(failures: Array[String]) -> void:
	var compiler := CompilerScript.new()
	var spec := {
		"map": {"id": "walkover_map", "seed": 11, "bounds": {"width_m": 48, "height_m": 48}},
		"terrain": {"profile": "flat"},
		"regions": [{"id": "grove", "polygon": [[0, 0], [48, 0], [48, 48], [0, 48]], "vegetation": {"profile": "temperate_dense", "density": 0.9}}],
	}
	var result := compiler.compile(spec)
	_expect(result.is_valid(), "walk-over fixture did not compile", failures)
	if not result.is_valid():
		return
	var walkover := 0
	for placement in result.placements:
		var definition := AssetCatalog.get_definition(placement.asset)
		if definition == null or definition.asset_type != &"vegetation" or definition.blocks_navigation:
			continue
		walkover += 1
		_expect(result.root.get_node_or_null("%s_Blocker" % placement.id) == null, "walk-over scatter '%s' still owns a physics blocker" % placement.id, failures)
	_expect(walkover > 0, "dense fixture generated no walk-over scatter to check", failures)
	result.root.free()


static func _test_collision_is_measured_at_walk_height(failures: Array[String]) -> void:
	var canopy := AssetCatalog.get_definition(&"forest_tree_1_c")
	_expect(canopy != null and canopy.blocking_radius() < canopy.footprint_radius * 0.25, "tree collision still uses the canopy footprint instead of the trunk", failures)
	var pebble := AssetCatalog.get_definition(&"forest_rock_5_a")
	_expect(pebble != null and not pebble.blocks_navigation, "a 9cm pebble is still a navigation obstacle", failures)
	for definition in AssetCatalog.find_matching(&"vegetation", PackedStringArray(["forest"])):
		_expect(definition.collision_radius > 0.0 and definition.collision_height > 0.0, "catalog asset '%s' has no measured collision" % definition.id, failures)
		if definition.tags.has("grass") or definition.tags.has("bush"):
			_expect(not definition.blocks_navigation, "foliage '%s' blocks navigation" % definition.id, failures)


## The regression test for the original complaint: a dense stand has to stay
## crossable now that trunks, not canopies, carve the navmesh.
static func _test_dense_forest_stays_walkable(failures: Array[String]) -> void:
	var compiler := CompilerScript.new()
	var spec := {
		"map": {"id": "dense_walk_map", "seed": 5, "bounds": {"width_m": 48, "height_m": 48}},
		"terrain": {"profile": "flat"},
		"regions": [{"id": "grove", "polygon": [[0, 0], [48, 0], [48, 48], [0, 48]], "vegetation": {"profile": "temperate_dense", "density": 1.0}}],
		"spawn_points": [{"id": "start", "position": [2, 2]}],
	}
	var result := compiler.compile(spec)
	_expect(result.is_valid(), "dense forest fixture did not compile", failures)
	if not result.is_valid():
		return
	_expect(result.navigation.is_reachable(Vector2(2, 2), Vector2(46, 46)), "a dense forest is not crossable", failures)
	result.root.free()


static func _test_scatter_respects_poisson_spacing(failures: Array[String]) -> void:
	var terrain := TerrainScript.new()
	terrain.generate(&"flat", 21, Vector2(64, 64))
	var region := {"id": "grove", "polygon": [[0, 0], [64, 0], [64, 64], [0, 64]], "vegetation": {"profile": "temperate_sparse", "density": 0.6}}
	var placements := VegetationScript.new().generate(region, 21, terrain, [])
	_expect(placements.size() > 20, "sparse scatter produced too few samples to test spacing", failures)
	var settings := VegetationScript.load_profile("temperate_sparse")
	var scale := lerpf(1.6, 0.75, 0.6) * (1.0 - settings.canopy_overlap)
	for index in placements.size():
		var here: Dictionary = placements[index]
		var here_gap := maxf(settings.min_spacing_m, float(here.radius) * scale)
		for other_index in range(index + 1, placements.size()):
			var other: Dictionary = placements[other_index]
			var gap := here_gap + maxf(settings.min_spacing_m, float(other.radius) * scale)
			if Vector2(here.position.x, here.position.z).distance_to(Vector2(other.position.x, other.position.z)) < gap - 0.001:
				_expect(false, "Poisson-disk minimum spacing was violated between '%s' and '%s'" % [here.id, other.id], failures)
				return


## The density field has to carve real clearings, and the stand still has to
## cover the whole region. Variance-to-mean is the wrong statistic here: a
## Poisson-disk process is under-dispersed, so blue noise alone would push it
## below 1 and mask the field entirely. The low tail of cell occupancy is the
## property that actually distinguishes a stand with clearings from a flat one.
static func _test_scatter_density_is_patchy(failures: Array[String]) -> void:
	var terrain := TerrainScript.new()
	terrain.generate(&"flat", 33, Vector2(96, 96))
	var region := {"id": "grove", "polygon": [[0, 0], [96, 0], [96, 96], [0, 96]], "vegetation": {"profile": "temperate_dense", "density": 0.8}}
	var placements := VegetationScript.new().generate(region, 33, terrain, [])
	_expect(placements.size() > 100, "dense scatter produced too few samples to measure patchiness", failures)
	var buckets := {}
	for placement in placements:
		buckets[Vector2i(floori(placement.position.x / 12.0), floori(placement.position.z / 12.0))] = 0
	for placement in placements:
		var key := Vector2i(floori(placement.position.x / 12.0), floori(placement.position.z / 12.0))
		buckets[key] = int(buckets[key]) + 1
	var counts: Array[int] = []
	for x_index in 8:
		for z_index in 8:
			counts.append(int(buckets.get(Vector2i(x_index, z_index), 0)))
	counts.sort()
	_expect(counts[0] > 0, "the stand left whole cells bare; the instance cap is truncating instead of coarsening", failures)
	var median := float(counts[counts.size() / 2])
	_expect(float(counts[counts.size() / 10]) < median * 0.8, "scatter density is flat; the noise field is not carving clearings", failures)


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
