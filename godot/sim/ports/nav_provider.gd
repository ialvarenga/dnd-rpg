class_name NavProvider
extends RefCounted

func find_path(_from: Vector3, _to: Vector3) -> PackedVector3Array:
	push_error("NavProvider.find_path must be implemented by an adapter")
	return PackedVector3Array()


func path_cost(_path: PackedVector3Array) -> float:
	push_error("NavProvider.path_cost must be implemented by an adapter")
	return INF


func is_reachable(_from: Vector3, _to: Vector3) -> bool:
	return false


func snap_to_navmesh(pos: Vector3) -> Vector3:
	return pos

