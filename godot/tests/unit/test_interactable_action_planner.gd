class_name TestInteractableActionPlanner
extends RefCounted

const InteractableActionPlannerScript = preload("res://sim/interactable_action_planner.gd")


static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_in_range_interaction_needs_no_movement(failures)
	_test_out_of_range_interaction_stops_at_use_range(failures)
	_test_blocked_item_center_uses_snapped_destination(failures)
	_test_combat_movement_budget_is_respected(failures)
	_test_exploration_ignores_combat_movement_budget(failures)
	_test_planning_does_not_mutate_state(failures)
	return {"name": "unit/test_interactable_action_planner", "failures": failures}


static func _test_in_range_interaction_needs_no_movement(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var interactable := _add_pickup(state, Vector3(1.5, 0.0, 0.0))
	var plan = InteractableActionPlannerScript.plan(state, 1, interactable.id, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(plan.can_execute and not plan.requires_movement, "an in-range interaction planned unnecessary movement", failures)


static func _test_out_of_range_interaction_stops_at_use_range(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var actor: ActorState = state.actors[1]
	var interactable := _add_pickup(state, Vector3(6.0, 0.0, 0.0))
	var plan = InteractableActionPlannerScript.plan(state, actor.id, interactable.id, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(plan.can_execute and plan.requires_movement, "an approachable out-of-range item produced no movement plan", failures)
	_expect(plan.destination.distance_to(interactable.position) <= interactable.interact_range + 0.001, "planned destination remained outside interaction range", failures)
	_expect(plan.movement_cost < actor.position.distance_to(interactable.position), "planner walked onto the item instead of stopping at interaction range", failures)
	_expect(absf(plan.movement_cost - 4.0) <= 0.01, "planner did not choose the closest valid point along the approach path", failures)


static func _test_blocked_item_center_uses_snapped_destination(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var interactable := _add_pickup(state, Vector3(6.0, 0.0, 0.0))
	var nav := FakeNavProvider.new()
	nav.blocked_destinations.append(interactable.position)
	nav.snapped_destinations[interactable.position] = Vector3(5.0, 0.0, 0.0)
	var plan = InteractableActionPlannerScript.plan(state, 1, interactable.id, nav, FakeLosProvider.new())
	_expect(plan.can_execute and plan.requires_movement, "an item with an occupied center could not be approached", failures)
	_expect(plan.movement_target != interactable.position, "planner still targeted the occupied item center", failures)


static func _test_combat_movement_budget_is_respected(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	(state.actors[1] as ActorState).movement_remaining = 2.0
	var interactable := _add_pickup(state, Vector3(6.0, 0.0, 0.0))
	var plan = InteractableActionPlannerScript.plan(state, 1, interactable.id, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(not plan.can_execute, "combat planner exceeded remaining movement to reach an item", failures)


static func _test_exploration_ignores_combat_movement_budget(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	state.phase = &"exploration"
	(state.actors[1] as ActorState).movement_remaining = 0.0
	var interactable := _add_pickup(state, Vector3(6.0, 0.0, 0.0))
	var plan = InteractableActionPlannerScript.plan(state, 1, interactable.id, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(plan.can_execute and plan.requires_movement, "exploration interaction incorrectly used the combat movement budget", failures)


static func _test_planning_does_not_mutate_state(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var interactable := _add_pickup(state, Vector3(6.0, 0.0, 0.0))
	var before := JSON.stringify(state.stable_snapshot())
	InteractableActionPlannerScript.plan(state, 1, interactable.id, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(JSON.stringify(state.stable_snapshot()) == before, "interaction planning mutated BattleState", failures)


static func _add_pickup(state: BattleState, position: Vector3) -> InteractableState:
	var pickup := InteractableState.new()
	pickup.id = "test_pickup"
	pickup.type = &"pickup"
	pickup.state = &"ready"
	pickup.position = position
	pickup.interact_range = 2.0
	pickup.contents = [&"healing_potion"]
	state.interactables[pickup.id] = pickup
	return pickup


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
