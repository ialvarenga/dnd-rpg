class_name TestPrototypeLocomotion
extends RefCounted

static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_straight_path(failures)
	_test_obstacle_path(failures)
	_test_unreachable_path(failures)
	_test_repeated_clicks(failures)
	_test_target_replacement(failures)
	_test_near_target(failures)
	_test_elevated_path(failures)
	_test_click_outside_terrain(failures)
	return {"name": "integration/test_prototype_locomotion", "failures": failures}


static func _test_straight_path(failures: Array[String]) -> void:
	var follower := _follower()
	var target := Vector3(5.0, 0.0, 0.0)
	_expect(bool(follower.begin_path(PackedVector3Array([Vector3.ZERO, target]), target)["accepted"]), "straight path was rejected", failures)
	_expect(_run_to_completion(follower, Vector3.ZERO).distance_to(target) < 0.25, "straight path did not reach its target", failures)


static func _test_obstacle_path(failures: Array[String]) -> void:
	var follower := _follower()
	var target := Vector3(5.0, 0.0, 0.0)
	var detour := PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.0, 3.0), Vector3(5.0, 0.0, 3.0), target])
	follower.begin_path(detour, target)
	_expect(_run_to_completion(follower, Vector3.ZERO).distance_to(target) < 0.25, "obstacle detour did not reach its target", failures)


static func _test_unreachable_path(failures: Array[String]) -> void:
	var follower := _follower()
	var result := follower.begin_path(PackedVector3Array(), Vector3(8.0, 0.0, 0.0))
	_expect(not bool(result["accepted"]) and result["reason"] == &"empty_path", "empty navigation path was not rejected", failures)
	_expect(not follower.is_active(), "unreachable path left movement active", failures)


static func _test_repeated_clicks(failures: Array[String]) -> void:
	var follower := _follower()
	follower.begin_path(PackedVector3Array([Vector3.ZERO, Vector3(3.0, 0.0, 0.0)]), Vector3(3.0, 0.0, 0.0))
	follower.begin_path(PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.0, 4.0)]), Vector3(0.0, 0.0, 4.0))
	_expect(_run_to_completion(follower, Vector3.ZERO).distance_to(Vector3(0.0, 0.0, 4.0)) < 0.25, "latest repeated click was not followed", failures)


static func _test_target_replacement(failures: Array[String]) -> void:
	var follower := _follower()
	follower.begin_path(PackedVector3Array([Vector3.ZERO, Vector3(8.0, 0.0, 0.0)]), Vector3(8.0, 0.0, 0.0))
	var before_replace: Dictionary = follower.step(Vector3.ZERO, 0.1)
	follower.begin_path(PackedVector3Array([Vector3(0.5, 0.0, 0.0), Vector3(0.5, 0.0, -4.0)]), Vector3(0.5, 0.0, -4.0))
	var after_replace: Dictionary = follower.step(Vector3(0.5, 0.0, 0.0), 0.1)
	_expect((before_replace["velocity"] as Vector3).x > 0.0, "initial target did not set forward velocity", failures)
	_expect((after_replace["velocity"] as Vector3).z < 0.0, "target replacement did not take effect immediately", failures)


static func _test_near_target(failures: Array[String]) -> void:
	var follower := _follower()
	follower.begin_path(PackedVector3Array([Vector3.ZERO, Vector3(0.1, 0.0, 0.0)]), Vector3(0.1, 0.0, 0.0))
	var step: Dictionary = follower.step(Vector3.ZERO, 0.1)
	_expect(bool(step["finished"]) and (step["velocity"] as Vector3).is_zero_approx(), "near target did not finish without jitter", failures)


static func _test_elevated_path(failures: Array[String]) -> void:
	var follower := _follower()
	var target := Vector3(4.0, 2.0, 0.0)
	follower.begin_path(PackedVector3Array([Vector3(0.0, 1.0, 0.0), target]), target)
	var final_position := _run_to_completion(follower, Vector3(0.0, 1.0, 0.0))
	_expect(final_position.distance_to(target) < 0.25, "elevated navigation path did not preserve terrain elevation", failures)


static func _test_click_outside_terrain(failures: Array[String]) -> void:
	_expect(not _is_inside_arena(Vector3(32.1, 0.0, 0.0)), "outside terrain click was accepted", failures)
	_expect(_is_inside_arena(Vector3(31.9, 0.0, -31.9)), "terrain edge click was rejected", failures)


static func _follower() -> PrototypeLocomotion:
	var follower := PrototypeLocomotion.new()
	follower.speed = 5.0
	follower.waypoint_tolerance = 0.2
	return follower


static func _run_to_completion(follower: PrototypeLocomotion, start: Vector3) -> Vector3:
	var position := start
	for _index in range(300):
		var step: Dictionary = follower.step(position, 0.05)
		position += (step["velocity"] as Vector3) * 0.05
		if bool(step["finished"]):
			break
	return position


static func _is_inside_arena(point: Vector3) -> bool:
	return absf(point.x) <= 32.0 and absf(point.z) <= 32.0


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
