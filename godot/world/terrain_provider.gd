class_name TerrainProvider
extends RefCounted

## Boundary between MapSpec terrain intent and a future terrain implementation.
## Coordinates are absolute meters from the southwest map corner: x is east and
## z is north. B5 supplies procedural profiles; B9 owns navigation baking.

const SUPPORTED_PROFILES := [&"flat", &"rolling_hills", &"valley"]
const MAX_SEED := 2147483647
const MAX_BOUND_M := 256.0

var profile: StringName
var seed: int
var bounds: Vector2
var is_initialized := false


## Initializes this provider from MapSpec v1 terrain intent. `bounds.x` is
## width_m and `bounds.y` is height_m. Returns false and reports an error when
## the input is not valid MapSpec-compatible terrain input.
func generate(terrain_profile: StringName, terrain_seed: int, terrain_bounds: Vector2) -> bool:
	if not SUPPORTED_PROFILES.has(terrain_profile):
		push_error("TerrainProvider.generate received unsupported profile '%s'" % terrain_profile)
		return false
	if terrain_seed < 0 or terrain_seed > MAX_SEED:
		push_error("TerrainProvider.generate requires a seed from 0 to %s" % MAX_SEED)
		return false
	if terrain_bounds.x <= 0.0 or terrain_bounds.y <= 0.0 or terrain_bounds.x > MAX_BOUND_M or terrain_bounds.y > MAX_BOUND_M:
		push_error("TerrainProvider.generate requires width_m and height_m bounds from 0 (exclusive) to %s" % MAX_BOUND_M)
		return false
	profile = terrain_profile
	seed = terrain_seed
	bounds = terrain_bounds
	is_initialized = true
	return true


## Returns terrain elevation in meters. Implementations must return NAN and
## report an error for an uninitialized or out-of-bounds query.
func height_at(_x: float, _z: float) -> float:
	push_error("TerrainProvider.height_at must be implemented by a terrain provider")
	return NAN


## Returns the normalized surface normal. Implementations must return a vector
## of NAN values and report an error for an invalid query.
func normal_at(_x: float, _z: float) -> Vector3:
	push_error("TerrainProvider.normal_at must be implemented by a terrain provider")
	return Vector3(NAN, NAN, NAN)


## Returns the surface slope in degrees. Implementations must return NAN and
## report an error for an invalid query.
func slope_at(_x: float, _z: float) -> float:
	push_error("TerrainProvider.slope_at must be implemented by a terrain provider")
	return NAN


## Returns terrain triangles as PackedVector3Array values for future B9
## navigation baking. An empty array means navigation geometry is deferred.
func export_navigation_geometry() -> Array[PackedVector3Array]:
	return []


func is_query_in_bounds(x: float, z: float) -> bool:
	if not is_initialized:
		push_error("TerrainProvider query requires generate() to succeed first")
		return false
	if x < 0.0 or x > bounds.x or z < 0.0 or z > bounds.y:
		push_error("TerrainProvider query (%s, %s) is outside bounds (%s, %s)" % [x, z, bounds.x, bounds.y])
		return false
	return true
