class_name MapRuntimeBlocker
extends StaticBody3D

static func create(id: StringName, point: Vector3, definition: AssetDefinition, rotation_y := 0.0, collision_size := Vector3.ZERO) -> MapRuntimeBlocker:
	var blocker := MapRuntimeBlocker.new()
	blocker.name = "%s_Blocker" % id
	blocker.collision_layer = 8
	blocker.collision_mask = 0
	var collision := CollisionShape3D.new()
	if definition.has_box_collision():
		var box := BoxShape3D.new()
		box.size = collision_size if collision_size != Vector3.ZERO else definition.collision_size
		collision.shape = box
		blocker.position = point + Vector3.UP * (box.size.y * 0.5)
		blocker.rotation.y = rotation_y
	else:
		var cylinder := CylinderShape3D.new()
		cylinder.radius = definition.footprint_radius
		cylinder.height = 2.0
		collision.shape = cylinder
		blocker.position = point + Vector3.UP * 1.0
	blocker.add_child(collision)
	return blocker
