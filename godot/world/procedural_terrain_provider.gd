class_name ProceduralTerrainProvider
extends "res://world/terrain_provider.gd"

## A cached, deterministic heightfield. Every terrain query and baked terrain
## triangle reads this field, so path deformation is performed once rather than
## being repeated by every height query.

const GRID_CELL_SIZE_M := 1.0
const NAVIGATION_STEP_M := 2.0
const PROFILE_PATHS := {
	&"flat": "res://data/terrain/flat.tres",
	&"rolling_hills": "res://data/terrain/rolling_hills.tres",
	&"valley": "res://data/terrain/valley.tres",
}

var _grid := PackedFloat32Array()
var _grid_width := 0
var _grid_height := 0
var _settings: TerrainProfileSettings
var _noise := FastNoiseLite.new()


func generate(terrain_profile: StringName, terrain_seed: int, terrain_bounds: Vector2) -> bool:
	if not super.generate(terrain_profile, terrain_seed, terrain_bounds):
		return false
	_settings = load(PROFILE_PATHS[profile]) as TerrainProfileSettings
	if _settings == null:
		push_error("ProceduralTerrainProvider could not load settings for '%s'" % profile)
		is_initialized = false
		return false
	_configure_noise()
	_grid_width = ceili(bounds.x / GRID_CELL_SIZE_M) + 1
	_grid_height = ceili(bounds.y / GRID_CELL_SIZE_M) + 1
	_grid.resize(_grid_width * _grid_height)
	for z_index in range(_grid_height):
		for x_index in range(_grid_width):
			_set_grid(x_index, z_index, _base_height(float(x_index) * GRID_CELL_SIZE_M, float(z_index) * GRID_CELL_SIZE_M))
	return true


func height_at(x: float, z: float) -> float:
	if not is_query_in_bounds(x, z):
		return NAN
	return _sample_grid(x, z)


func normal_at(x: float, z: float) -> Vector3:
	if not is_query_in_bounds(x, z):
		return Vector3(NAN, NAN, NAN)
	var left_x := maxf(0.0, x - GRID_CELL_SIZE_M)
	var right_x := minf(bounds.x, x + GRID_CELL_SIZE_M)
	var south_z := maxf(0.0, z - GRID_CELL_SIZE_M)
	var north_z := minf(bounds.y, z + GRID_CELL_SIZE_M)
	var dx := _sample_grid(right_x, z) - _sample_grid(left_x, z)
	var dz := _sample_grid(x, north_z) - _sample_grid(x, south_z)
	return Vector3(-dx / maxf(right_x - left_x, 0.001), 1.0, -dz / maxf(north_z - south_z, 0.001)).normalized()


func slope_at(x: float, z: float) -> float:
	var normal := normal_at(x, z)
	if not is_finite(normal.x):
		return NAN
	return rad_to_deg(acos(clampf(normal.y, -1.0, 1.0)))


func navigation_slope_limit() -> float:
	return _settings.hard_slope_deg if _settings != null else 35.0


func export_navigation_geometry() -> Array[PackedVector3Array]:
	if not is_initialized:
		return []
	var triangles: Array[PackedVector3Array] = []
	for x in range(0, ceili(bounds.x), ceili(NAVIGATION_STEP_M)):
		for z in range(0, ceili(bounds.y), ceili(NAVIGATION_STEP_M)):
			var x1 := minf(float(x) + NAVIGATION_STEP_M, bounds.x)
			var z1 := minf(float(z) + NAVIGATION_STEP_M, bounds.y)
			var a := Vector3(float(x), _sample_grid(float(x), float(z)), float(z))
			var b := Vector3(x1, _sample_grid(x1, float(z)), float(z))
			var c := Vector3(x1, _sample_grid(x1, z1), z1)
			var d := Vector3(float(x), _sample_grid(float(x), z1), z1)
			triangles.append(PackedVector3Array([a, b, c]))
			triangles.append(PackedVector3Array([a, c, d]))
	return triangles


## Baked path deformation keeps roads smooth enough for the shared navigation
## slope gate. The target elevation follows the path rather than using a single
## average height, preventing ramps from becoming walls on rolling terrain.
func add_flattening_path(points: PackedVector2Array, half_width: float) -> void:
	if points.size() < 2 or half_width <= 0.0:
		return
	var shoulder_m := maxf(1.5, half_width * 0.8)
	var source := _grid.duplicate()
	_apply_path_deformation(points, half_width + shoulder_m, func(_point: Vector2, nearest: Dictionary) -> float:
		var a: Vector2 = nearest.a
		var b: Vector2 = nearest.b
		return lerpf(_sample_array(source, a.x, a.y), _sample_array(source, b.x, b.y), nearest.t), func(distance: float) -> float:
		return 1.0 - smoothstep(half_width, half_width + shoulder_m, distance))


func add_riverbed_path(points: PackedVector2Array, half_width: float) -> float:
	if points.size() < 2 or half_width <= 0.0:
		return NAN
	var depth := clampf(half_width * 0.22, 0.22, 0.65)
	var source := _grid.duplicate()
	_apply_path_deformation(points, half_width + maxf(0.6, half_width * 0.55), func(_point: Vector2, nearest: Dictionary) -> float:
		var a: Vector2 = nearest.a
		var b: Vector2 = nearest.b
		return lerpf(_sample_array(source, a.x, a.y), _sample_array(source, b.x, b.y), nearest.t) - depth, func(distance: float) -> float:
		return 1.0 - smoothstep(half_width * 0.72, half_width + maxf(0.6, half_width * 0.55), distance))
	var water_sum := 0.0
	for point in points:
		water_sum += _sample_grid(point.x, point.y) + depth * 0.18
	return water_sum / float(points.size())


func _configure_noise() -> void:
	_noise.seed = seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = _settings.octaves
	_noise.fractal_lacunarity = _settings.lacunarity
	_noise.fractal_gain = _settings.persistence
	_noise.frequency = 1.0 / _settings.feature_size_m
	_noise.domain_warp_enabled = _settings.warp_amplitude_m > 0.0
	_noise.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	_noise.domain_warp_amplitude = _settings.warp_amplitude_m
	_noise.domain_warp_frequency = 1.0 / _settings.feature_size_m


func _base_height(x: float, z: float) -> float:
	if profile == &"flat":
		return 0.0
	var detail := _noise.get_noise_2d(x, z) * _settings.amplitude_m
	if profile != &"valley":
		return detail
	var nx := x / bounds.x
	return pow((nx - 0.5) * 2.0, 2.0) * 5.0 + detail


func _apply_path_deformation(points: PackedVector2Array, radius: float, target: Callable, strength: Callable) -> void:
	for z_index in range(_grid_height):
		for x_index in range(_grid_width):
			var point := Vector2(float(x_index) * GRID_CELL_SIZE_M, float(z_index) * GRID_CELL_SIZE_M)
			var nearest := _nearest_segment(point, points)
			if nearest.distance >= radius:
				continue
			var blend := float(strength.call(nearest.distance))
			_set_grid(x_index, z_index, lerpf(_grid_at(x_index, z_index), float(target.call(point, nearest)), blend))


func _nearest_segment(point: Vector2, points: PackedVector2Array) -> Dictionary:
	var best := {"distance": INF, "a": Vector2.ZERO, "b": Vector2.ZERO, "t": 0.0}
	for index in range(1, points.size()):
		var a := points[index - 1]
		var b := points[index]
		var segment := b - a
		var t := clampf((point - a).dot(segment) / maxf(segment.length_squared(), 0.000001), 0.0, 1.0)
		var distance := point.distance_to(a.lerp(b, t))
		if distance < best.distance:
			best = {"distance": distance, "a": a, "b": b, "t": t}
	return best


func _sample_grid(x: float, z: float) -> float:
	return _sample_array(_grid, x, z)


func _sample_array(values: PackedFloat32Array, x: float, z: float) -> float:
	var grid_x := clampf(x / GRID_CELL_SIZE_M, 0.0, float(_grid_width - 1))
	var grid_z := clampf(z / GRID_CELL_SIZE_M, 0.0, float(_grid_height - 1))
	var x0 := floori(grid_x)
	var z0 := floori(grid_z)
	var x1 := mini(x0 + 1, _grid_width - 1)
	var z1 := mini(z0 + 1, _grid_height - 1)
	var tx := grid_x - float(x0)
	var tz := grid_z - float(z0)
	return lerpf(lerpf(_array_at(values, x0, z0), _array_at(values, x1, z0), tx), lerpf(_array_at(values, x0, z1), _array_at(values, x1, z1), tx), tz)


func _grid_at(x_index: int, z_index: int) -> float:
	return _array_at(_grid, x_index, z_index)


func _array_at(values: PackedFloat32Array, x_index: int, z_index: int) -> float:
	return values[z_index * _grid_width + x_index]


func _set_grid(x_index: int, z_index: int, value: float) -> void:
	_grid[z_index * _grid_width + x_index] = value
