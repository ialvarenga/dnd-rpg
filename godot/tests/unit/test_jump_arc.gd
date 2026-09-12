class_name TestJumpArc
extends RefCounted

## The presentation arc of a jump (ADR-009). The rules settle the endpoints;
## this covers what the player actually watches between them -- an arc that
## grows with the leap, clears the ledge it lands on, and falls under a single
## constant gravity rather than at a fixed height and a fixed pace.

const Arc = preload("res://view/jump_arc.gd")


static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_endpoints_are_exact(failures)
	_test_apex_grows_with_the_leap(failures)
	_test_a_climb_clears_the_lip_it_lands_on(failures)
	_test_a_drop_pushes_off_its_ledge(failures)
	_test_flight_is_ballistic(failures)
	_test_duration_stays_within_its_bounds(failures)
	return {"name": "unit/test_jump_arc", "failures": failures}


static func _test_endpoints_are_exact(failures: Array[String]) -> void:
	var from := Vector3(1, 2, 3)
	var to := Vector3(5, 0.5, 3)
	_expect(Arc.point(from, to, 0.0).is_equal_approx(from), "the arc did not start at the takeoff", failures)
	_expect(Arc.point(from, to, 1.0).is_equal_approx(to), "the arc did not end at the landing", failures)
	var line: PackedVector3Array = Arc.polyline(from, to)
	_expect(line.size() == Arc.DRAW_SEGMENTS + 1 and line[0].is_equal_approx(from) and line[line.size() - 1].is_equal_approx(to), "the drawn polyline did not match the flown arc's ends", failures)


## The old arc peaked a fixed 0.4 m no matter how far the jump went, which on
## a two-heads-tall rig with half-metre legs read as a shuffle.
static func _test_apex_grows_with_the_leap(failures: Array[String]) -> void:
	var short_hop: float = Arc.apex_height(Vector3.ZERO, Vector3(1.5, 0, 0))
	var long_jump: float = Arc.apex_height(Vector3.ZERO, Vector3(4.2, 0, 0))
	_expect(long_jump > short_hop, "a longer leap did not arc higher than a short hop", failures)
	_expect(is_equal_approx(long_jump, Arc.APEX_PER_METER * 4.2), "a level leap's apex did not scale with its distance", failures)
	_expect(is_equal_approx(short_hop, Arc.MIN_APEX_M), "a short hop did not keep the minimum apex", failures)
	_expect(is_equal_approx(Arc.apex_height(Vector3.ZERO, Vector3(20, 0, 0)), Arc.MAX_APEX_M), "a very long leap was not capped to the maximum apex", failures)


static func _test_a_climb_clears_the_lip_it_lands_on(failures: Array[String]) -> void:
	for rise in [0.8, 1.5, 3.0]:
		var to := Vector3(2, rise, 0)
		var clearance: float = Arc.apex_height(Vector3.ZERO, to) - rise
		_expect(clearance > 0.0 and is_equal_approx(clearance, Arc.CLIMB_CLEARANCE_M), "a %.1f m climb passed %.2f m above its landing, not the authored clearance" % [rise, clearance], failures)


static func _test_a_drop_pushes_off_its_ledge(failures: Array[String]) -> void:
	for depth in [1.5, 4.2, 8.0]:
		var lift: float = Arc.apex_height(Vector3(0, depth, 0), Vector3(2, 0, 0))
		_expect(is_equal_approx(lift, Arc.DROP_LIFT_M), "a %.1f m drop rose %.2f m off its ledge, not the authored lift" % [depth, lift], failures)


## The arc is quadratic in the weight and the weight is linear in time, so the
## flight has one constant vertical acceleration: the duration is what sets it,
## and it must come out as the authored gravity rather than drifting with the
## shape of the jump.
static func _test_flight_is_ballistic(failures: Array[String]) -> void:
	var from := Vector3.ZERO
	var to := Vector3(4.2, 0, 0)
	var duration: float = Arc.duration(from, to)
	var bulge: float = Arc.bulge_for(from, to)
	var implied_gravity: float = 8.0 * bulge / (duration * duration)
	_expect(is_equal_approx(implied_gravity, Arc.GRAVITY), "a level leap fell under %.1f m/s², not the authored gravity" % implied_gravity, failures)
	_expect(Arc.duration(from, Vector3(2.1, 0, 0)) < duration, "a shorter leap did not spend less time in the air", failures)


static func _test_duration_stays_within_its_bounds(failures: Array[String]) -> void:
	var hop: float = Arc.duration(Vector3.ZERO, Vector3(0.6, 0, 0))
	var plunge: float = Arc.duration(Vector3(0, 40, 0), Vector3(2, 0, 0))
	_expect(hop >= Arc.MIN_DURATION_S, "a tiny hop flicked past faster than the minimum flight", failures)
	_expect(plunge <= Arc.MAX_DURATION_S, "a long plunge stalled the turn past the maximum flight", failures)


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
