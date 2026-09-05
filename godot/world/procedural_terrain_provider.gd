class_name ProceduralTerrainProvider
extends "res://world/terrain_provider.gd"

## B5 deterministic terrain implementation. It keeps MapSpec intent at the
## TerrainProvider boundary and evaluates an equivalent continuous heightfield.

const SAMPLE_STEP_M := 4.0

var _phase_x := 0.0
var _phase_z := 0.0
var _flattenings: Array[Dictionary] = []


func generate(terrain_profile: StringName, terrain_seed: int, terrain_bounds: Vector2) -> bool:

	if not super.generate(terrain_profile, terrain_seed, terrain_bounds):
		return false
	_phase_x = float(_mix_seed(seed, 17)) / 2147483647.0 * TAU
	_phase_z = float(_mix_seed(seed, 53)) / 2147483647.0 * TAU
	_flattenings.clear()
	return true


func height_at(x: float, z: float) -> float:
	if not is_query_in_bounds(x, z):
		return NAN
	return _height_unchecked(x, z)


func normal_at(x: float, z: float) -> Vector3:
	if not is_query_in_bounds(x, z):
		return Vector3(NAN, NAN, NAN)
	var epsilon := 0.05
	var left := _height_unchecked(maxf(0.0, x - epsilon), z)
	var right := _height_unchecked(minf(bounds.x, x + epsilon), z)
	var south := _height_unchecked(x, maxf(0.0, z - epsilon))
	var north := _height_unchecked(x, minf(bounds.y, z + epsilon))
	return Vector3(-(right - left) / maxf(epsilon * 2.0, 0.001), 1.0, -(north - south) / maxf(epsilon * 2.0, 0.001)).normalized()


func slope_at(x: float, z: float) -> float:
	var normal := normal_at(x, z)
	if not is_finite(normal.x):
		return NAN
	return rad_to_deg(acos(clampf(normal.y, -1.0, 1.0)))


func export_navigation_geometry() -> Array[PackedVector3Array]:
	if not is_initialized:
		return []
	var triangles: Array[PackedVector3Array] = []
	for x in range(0, ceili(bounds.x), ceili(SAMPLE_STEP_M)):
		for z in range(0, ceili(bounds.y), ceili(SAMPLE_STEP_M)):
			var x1 := minf(float(x) + SAMPLE_STEP_M, bounds.x)
			var z1 := minf(float(z) + SAMPLE_STEP_M, bounds.y)
			var a := Vector3(float(x), _height_unchecked(float(x), float(z)), float(z))
			var b := Vector3(x1, _height_unchecked(x1, float(z)), float(z))
			var c := Vector3(x1, _height_unchecked(x1, z1), z1)
			var d := Vector3(float(x), _height_unchecked(float(x), z1), z1)
			triangles.append(PackedVector3Array([a, b, c]))
			triangles.append(PackedVector3Array([a, c, d]))
	return triangles


func _height_unchecked(x: float, z: float) -> float:
	var base := _base_height(x, z)
	for flattening in _flattenings:
		var distance := _distance_to_segments(Vector2(x, z), flattening.points)
		if distance < flattening.width:
			var blend := 1.0 - smoothstep(flattening.width * 0.65, flattening.width, distance)
			base = lerpf(base, flattening.height, blend)
	return base


## B8-owned semantic deformation hook. It modifies this provider's equivalent
## heightfield; callers remain behind TerrainProvider for all queries.
func add_flattening_path(points: PackedVector2Array, half_width: float) -> void:
	if points.size() < 2 or half_width <= 0.0:
		return
	var sum := 0.0
	for point in points:
		sum += _base_height(point.x, point.y)
	_flattenings.append({"points": points.duplicate(), "width": half_width, "height": sum / points.size()})


func _base_height(x: float, z: float) -> float:
	if profile == &"flat":
		return 0.0
	var nx := x / bounds.x
	var nz := z / bounds.y
	if profile == &"rolling_hills":
		return sin(nx * TAU * 1.35 + _phase_x) * 1.8 + cos(nz * TAU * 1.15 + _phase_z) * 1.35 + sin((nx + nz) * TAU + _phase_x) * 0.55
	# A broad east-west valley: low in the center with deterministic gentle detail.
	var valley := pow((nx - 0.5) * 2.0, 2.0) * 5.0
	return valley + sin(nz * TAU + _phase_z) * 0.32 + sin(nx * TAU * 2.0 + _phase_x) * 0.18


func _distance_to_segments(point: Vector2, points: PackedVector2Array) -> float:
	var nearest := INF
	for index in range(1, points.size()):
		nearest = minf(nearest, Geometry2D.get_closest_point_to_segment(point, points[index - 1], points[index]).distance_to(point))
	return nearest


func _mix_seed(value: int, salt: int) -> int:
	return int(posmod(value * 48271 + salt * 69621 + 1, 2147483647))
