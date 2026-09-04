class_name GodotLosProvider
extends LosProvider

## Engine adapter for line-of-sight. It deliberately owns the physics query so
## the sim layer never depends on a World3D, collision layers, or raycasts.

var world_3d: World3D
var blocking_collision_mask: int = 8


func _init(source_world: World3D = null, collision_mask: int = 8) -> void:
	world_3d = source_world
	blocking_collision_mask = collision_mask


func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	if not _is_finite_vector(from) or not _is_finite_vector(to) or not is_instance_valid(world_3d):
		return false
	if from.distance_to(to) <= 0.001:
		return true
	var query := PhysicsRayQueryParameters3D.create(from, to, blocking_collision_mask)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return world_3d.direct_space_state.intersect_ray(query).is_empty()


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
