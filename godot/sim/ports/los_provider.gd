class_name LosProvider
extends RefCounted

func has_line_of_sight(_from: Vector3, _to: Vector3) -> bool:
	push_error("LosProvider.has_line_of_sight must be implemented by an adapter")
	return false

