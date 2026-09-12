extends RefCounted

## Presentation-only flight of a ledge jump (ADR-009). The path preview draws
## this arc and CharacterView flies it, so the leap the player is shown is the
## leap they then watch. The authoritative jump is only its two endpoints.
##
## The arc is a true ballistic parabola: `point` is quadratic in the weight and
## `duration` picks the flight time that makes the implied gravity GRAVITY, so
## a longer leap arcs higher and hangs longer instead of skimming the ground at
## a fixed height. The KayKit characters are barely two heads tall with 0.5 m
## legs, so a fixed apex that clears their knees reads as a shuffle.

## Apex above the higher end of a level leap, per metre jumped.
const APEX_PER_METER := 0.25
## Even the shortest hop leaves the ground; the longest never becomes a lob.
const MIN_APEX_M := 0.6
const MAX_APEX_M := 1.6
## A climb passes this far above the lip it lands on rather than skimming it.
const CLIMB_CLEARANCE_M := 0.5
## A drop pushes off this far above the ledge it leaves, so stepping off one
## reads as jumping down rather than as walking into thin air.
const DROP_LIFT_M := 0.3
## Heavier than real gravity: a stylised leap that hangs for a full second
## reads as floaty and stalls the turn.
const GRAVITY := 17.6
const MIN_DURATION_S := 0.35
const MAX_DURATION_S := 1.0
const DRAW_SEGMENTS := 12


## Position `weight` (0..1) of the way along the jump.
static func point(from: Vector3, to: Vector3, weight: float) -> Vector3:
	var bulge := bulge_for(from, to)
	return from.lerp(to, weight) + Vector3.UP * (4.0 * bulge * weight * (1.0 - weight))


## How far the arc bulges above the straight line at its midpoint. The apex is
## higher than this on a climb and lower on a drop; use `apex_height` for that.
static func bulge_for(from: Vector3, to: Vector3) -> float:
	var distance := Vector2(from.x, from.z).distance_to(Vector2(to.x, to.z))
	var rise := to.y - from.y
	var bulge := clampf(APEX_PER_METER * distance, MIN_APEX_M, MAX_APEX_M)
	# Both ledge cases measure the same way -- the arc has to pass a set height
	# above whichever end is the higher one.
	if rise > 0.0:
		return maxf(bulge, _bulge_clearing(rise, CLIMB_CLEARANCE_M))
	return maxf(bulge, _bulge_clearing(-rise, DROP_LIFT_M))


## Peak of the arc, as a height above `from`.
static func apex_height(from: Vector3, to: Vector3) -> float:
	var bulge := bulge_for(from, to)
	var rise := to.y - from.y
	# Where the parabola turns over: clamped because a drop taller than the
	# bulge peaks at the takeoff itself.
	var peak := clampf((rise + 4.0 * bulge) / (8.0 * bulge), 0.0, 1.0)
	return rise * peak + 4.0 * bulge * peak * (1.0 - peak)


## Seconds a jump takes: the free-fall time up to its peak plus the time back
## down to the landing, clamped so a short hop still reads and a tall drop does
## not stall the turn.
static func duration(from: Vector3, to: Vector3) -> float:
	var apex := apex_height(from, to)
	var climb := maxf(0.0, apex)
	var fall := maxf(0.0, apex - (to.y - from.y))
	return clampf(sqrt(2.0 * climb / GRAVITY) + sqrt(2.0 * fall / GRAVITY), MIN_DURATION_S, MAX_DURATION_S)


## Polyline of the arc, endpoints exact, for line drawing.
static func polyline(from: Vector3, to: Vector3) -> PackedVector3Array:
	var points := PackedVector3Array()
	for step in range(DRAW_SEGMENTS + 1):
		points.append(point(from, to, float(step) / float(DRAW_SEGMENTS)))
	return points


## The smallest bulge whose apex passes `clearance` above the higher end of a
## ledge `rise` tall -- the landing lip of a climb, or the ledge a drop leaves.
## The larger root of 16b² - 8b(rise + 2·clearance) + rise², simplified.
static func _bulge_clearing(rise: float, clearance: float) -> float:
	return rise / 4.0 + clearance / 2.0 + sqrt(clearance * (rise + clearance)) / 2.0
