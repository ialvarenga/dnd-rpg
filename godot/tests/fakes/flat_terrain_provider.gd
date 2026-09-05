class_name FlatTerrainProvider
extends "res://world/terrain_provider.gd"

## Test/support implementation only. It intentionally does not generate mesh
## or navigation data: every valid query is a level surface at elevation zero.

func height_at(x: float, z: float) -> float:
	if not is_query_in_bounds(x, z):
		return NAN
	return 0.0


func normal_at(x: float, z: float) -> Vector3:
	if not is_query_in_bounds(x, z):
		return Vector3(NAN, NAN, NAN)
	return Vector3.UP


func slope_at(x: float, z: float) -> float:
	if not is_query_in_bounds(x, z):
		return NAN
	return 0.0


func export_navigation_geometry() -> Array[PackedVector3Array]:
	return []
