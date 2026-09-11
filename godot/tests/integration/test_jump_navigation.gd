class_name TestJumpNavigation
extends Node

## ADR-009 against the real NavigationServer: the shipped Emberwatch terraces
## route every creature by its own Strength. The Archer (STR 10) comes down the
## staircase instead of the 4.2 m face that would floor it, but cannot climb
## back up; the Knight (STR 14) climbs every step with a run-up.

const MapSpecSourceScript = preload("res://world/map_spec_source.gd")
const PolylineUtil = preload("res://sim/polyline.gd")
const SYNC_FRAME_LIMIT := 180
const SUMMIT := Vector3(160, 5.2, 96)
const CAMP := Vector3(164, 1.0, 72)
const BELOW_TERRACES := Vector3(146, 1.0, 76)


func run() -> Dictionary:
	var failures: Array[String] = []
	var spec: Dictionary = MapSpecSourceScript.new("../world_authoring/maps/test_map.json").load_spec()
	var compilation: MapCompilationResult = MapCompiler.new().compile(spec)
	if not compilation.is_valid():
		failures.append("shipped map did not compile: %s" % str(compilation.error_dicts()))
		return {"name": "integration/test_jump_navigation", "failures": failures}
	add_child(compilation.root)
	var map := compilation.navigation.navigation_region.get_navigation_map()
	# Navigation maps synchronise asynchronously; wait until the summit exists.
	for _frame in range(SYNC_FRAME_LIMIT):
		await get_tree().physics_frame
		if NavigationServer3D.map_get_closest_point(map, SUMMIT).distance_to(Vector3(SUMMIT.x, 4.2, SUMMIT.z)) < 0.1:
			break
	var nav := GodotNavProvider.new(compilation.navigation.navigation_region, 1, compilation.movement_regions, compilation.navigation.jump_links)
	_test_archer_takes_the_staircase_down(nav, failures)
	_test_knight_climbs_and_archer_cannot(nav, failures)
	_test_walking_alone_cannot_leave_the_summit(nav, failures)
	compilation.root.queue_free()
	return {"name": "integration/test_jump_navigation", "failures": failures}


func _test_archer_takes_the_staircase_down(nav: GodotNavProvider, failures: Array[String]) -> void:
	var archer := nav.for_jumper(10)
	var path := archer.find_path(SUMMIT, CAMP)
	_expect(archer.is_reachable(SUMMIT, CAMP) and not path.is_empty(), "the Archer cannot get down from its perch", failures)
	var drops := _jumps(archer, path, JumpRules.DROP)
	_expect(drops.size() == 3, "the Archer should step down all three terraces, took %d drops" % drops.size(), failures)
	for height in drops:
		_expect(int(JumpRules.drop_outcome(10, height)["dice"]) == 0, "the Archer's route took a %.1f m drop that would hurt it" % height, failures)
	if not path.is_empty():
		_expect(archer.path_cost(path) < PolylineUtil.length(path), "a route with drops should cost less than its 3D length", failures)


func _test_knight_climbs_and_archer_cannot(nav: GodotNavProvider, failures: Array[String]) -> void:
	var knight := nav.for_jumper(14)
	var up := knight.find_path(BELOW_TERRACES, SUMMIT)
	_expect(knight.is_reachable(BELOW_TERRACES, SUMMIT), "the Knight cannot climb to the Archer's perch", failures)
	_expect(_jumps(knight, up, JumpRules.CLIMB).size() == 3, "the Knight should climb the three terrace steps", failures)
	var archer := nav.for_jumper(10)
	_expect(not archer.is_reachable(BELOW_TERRACES, SUMMIT) and archer.find_path(BELOW_TERRACES, SUMMIT).is_empty(), "the Archer's STR 10 High Jump (0.9 m) should not climb the 1.5 m terrace steps", failures)
	var down := knight.find_path(SUMMIT, Vector3(164, 1.0, 86))
	var knight_drops := _jumps(knight, down, JumpRules.DROP)
	_expect(knight_drops.size() == 1 and is_equal_approx(knight_drops[0], 4.2), "the Knight should drop the 4.2 m face it can land safely", failures)


func _test_walking_alone_cannot_leave_the_summit(nav: GodotNavProvider, failures: Array[String]) -> void:
	_expect(not nav.is_reachable(SUMMIT, CAMP), "without ledge links the summit should be an island", failures)


func _jumps(nav: NavProvider, path: PackedVector3Array, kind: StringName) -> Array[float]:
	var heights: Array[float] = []
	for index in range(1, path.size()):
		var jump := nav.jump_between(path[index - 1], path[index])
		if not jump.is_empty() and StringName(jump["kind"]) == kind:
			heights.append(snappedf(absf(path[index - 1].y - path[index].y), 0.01))
	return heights


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
