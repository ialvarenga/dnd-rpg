class_name ScreenPicker
extends RefCounted

## World-side screen picking. Simulation receives only the resolved targets.
static func terrain_point(camera: Camera3D, space: PhysicsDirectSpaceState3D, screen_position: Vector2) -> Variant:
	var hit := _raycast(camera, space, screen_position, 1)
	return hit.get("position") if not hit.is_empty() else null


static func interactable_id(camera: Camera3D, space: PhysicsDirectSpaceState3D, screen_position: Vector2) -> String:
	var hit := _raycast(camera, space, screen_position, 1 << 2)
	if hit.is_empty():
		return ""
	var collider: Object = hit.get("collider")
	if collider is Node and (collider as Node).has_meta("interactable_id"):
		return str((collider as Node).get_meta("interactable_id"))
	return ""


static func actor_id_at(camera: Camera3D, space: PhysicsDirectSpaceState3D, screen_position: Vector2) -> int:
	var hit := _raycast(camera, space, screen_position, 1 << 1)
	if hit.is_empty():
		return -1
	var collider: Object = hit.get("collider")
	if collider is CharacterView:
		return (collider as CharacterView).actor_id
	if collider is Node and (collider as Node).has_meta("actor_id"):
		return int((collider as Node).get_meta("actor_id"))
	return -1


static func _raycast(camera: Camera3D, space: PhysicsDirectSpaceState3D, screen_position: Vector2, mask: int) -> Dictionary:
	if camera == null or space == null:
		return {}
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_end := ray_origin + camera.project_ray_normal(screen_position) * 500.0
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, mask)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space.intersect_ray(query)
