class_name TestArenaRuntime
extends Node


func run() -> Dictionary:
	var failures: Array[String] = []
	var arena := preload("res://scenes/test_arena.tscn").instantiate()
	get_tree().root.add_child(arena)
	for _frame in range(5):
		await get_tree().physics_frame
	var player: PrototypeCharacterController = arena.get_node("PlayerCharacter")
	player.set_destination(Vector3(12.0, 0.1, 0.0))
	for _frame in range(500):
		await get_tree().physics_frame
		if player.destination_state == &"reached":
			break
	var path := player.get_navigation_path()
	var routed_around_barrier := false
	for point in path:
		if absf(point.z) > 6.5:
			routed_around_barrier = true
			break
	if player.destination_state != &"reached" or player.global_position.distance_to(Vector3(12.0, 1.0, 0.0)) > 0.5 or not routed_around_barrier:
		failures.append("main-scene obstacle route failed: state=%s position=%s path=%s" % [player.destination_state, player.global_position, path])
	arena.queue_free()
	return {"name": "integration/test_arena_runtime", "failures": failures}
