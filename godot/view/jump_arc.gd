extends RefCounted

## Presentation-only flight of a ledge jump (ADR-009). The path preview draws
## this arc and CharacterView flies it, so the leap the player is shown is the
## leap they then watch. The authoritative jump is only its two endpoints.

## Height the arc peaks above the higher of its two ends.
const APEX_LIFT_M := 0.4
## Share of the height difference added to the arc's bulge, so a long drop
## still rises off the ledge before it falls.
const HEIGHT_BULGE := 0.3
const GRAVITY := 9.8
const MIN_DURATION_S := 0.35
const MAX_DURATION_S := 1.0
const DRAW_SEGMENTS := 10


## Position `weight` (0..1) of the way along the jump.
static func point(from: Vector3, to: Vector3, weight: float) -> Vector3:
	var bulge := APEX_LIFT_M + absf(from.y - to.y) * HEIGHT_BULGE
	var flat := from.lerp(to, weight)
	return flat + Vector3.UP * (4.0 * bulge * weight * (1.0 - weight))


## Seconds a jump takes: free-fall time from its peak, clamped so a short hop
## still reads and a tall drop does not stall the turn.
static func duration(from: Vector3, to: Vector3) -> float:
	var fall_height := absf(from.y - to.y) + APEX_LIFT_M
	return clampf(sqrt(2.0 * fall_height / GRAVITY) + 0.15, MIN_DURATION_S, MAX_DURATION_S)


## Polyline of the arc, endpoints exact, for line drawing.
static func polyline(from: Vector3, to: Vector3) -> PackedVector3Array:
	var points := PackedVector3Array()
	for step in range(DRAW_SEGMENTS + 1):
		points.append(point(from, to, float(step) / float(DRAW_SEGMENTS)))
	return points
