class_name MapRuntimeBlocker
extends StaticBody3D

static func create(id: StringName, point: Vector3, radius: float) -> MapRuntimeBlocker:
	var blocker := MapRuntimeBlocker.new()
	blocker.name = "%s_Blocker" % id
	blocker.position = point + Vector3.UP * 1.0
	blocker.collision_layer = 8
	blocker.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 2.0
	collision.shape = shape
	blocker.add_child(collision)
	return blocker
