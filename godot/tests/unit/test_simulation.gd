class_name TestSimulation
extends RefCounted

const PolylineUtil = preload("res://sim/polyline.gd")

static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_clone_is_independent(failures)
	_test_equal_inputs_produce_equal_resolution(failures)
	_test_resolve_does_not_mutate_input(failures)
	_test_apply_changes_only_event_fields(failures)
	_test_rejections_are_non_mutating(failures)
	_test_navigation_rejection_is_non_mutating(failures)
	_test_combat_move_below_budget_spends_polyline_cost(failures)
	_test_combat_move_beyond_budget_clamps_to_exact_distance(failures)
	_test_detour_clamp_uses_polyline_distance(failures)
	_test_exploration_move_ignores_budget(failures)
	_test_zero_budget_and_empty_segment_reject_without_mutation(failures)
	_test_move_preview_resolution_is_pure(failures)
	_test_serialization_round_trip(failures)
	return {"name": "unit/test_simulation", "failures": failures}


static func _test_clone_is_independent(failures: Array[String]) -> void:
	var original := TestHelpers.make_battle()
	var clone := original.clone()
	(clone.actors[1] as ActorState).hp = 1
	clone.rng_state = 99
	_expect((original.actors[1] as ActorState).hp == 20, "clone changed original actor", failures)
	_expect(original.rng_state == 42, "clone changed original RNG", failures)


static func _test_equal_inputs_produce_equal_resolution(failures: Array[String]) -> void:
	var first_state := TestHelpers.make_battle(42)
	var second_state := TestHelpers.make_battle(42)
	var command := Command.create(&"attack", 1)
	command.target_id = 2
	var first_result := Resolver.resolve(first_state, command, FakeNavProvider.new(), FakeLosProvider.new())
	var second_result := Resolver.resolve(second_state, command, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(
		TestHelpers.event_log_entry(first_result) == TestHelpers.event_log_entry(second_result),
		"equal state, command, and providers produced different resolutions",
		failures,
	)


static func _test_resolve_does_not_mutate_input(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var before_hash := JSON.stringify(state.stable_snapshot()).md5_text()
	var command := Command.create(&"attack", 1)
	command.target_id = 2
	Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(JSON.stringify(state.stable_snapshot()).md5_text() == before_hash, "resolve mutated BattleState", failures)


static func _test_apply_changes_only_event_fields(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var untouched_position := (state.actors[2] as ActorState).position
	Resolver.apply(state, Event.create(&"damage_taken", {"actor_id": 1, "source_actor_id": 2, "amount": 4}))
	_expect((state.actors[1] as ActorState).hp == 16, "damage event did not change HP", failures)
	_expect((state.actors[2] as ActorState).position == untouched_position, "damage event changed unrelated actor", failures)
	_expect(state.rng_state == 42, "damage event changed RNG", failures)


static func _test_rejections_are_non_mutating(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var command := Command.create(&"unsupported", 1)
	var result := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(result.events.size() == 1 and result.events[0].type == &"command_rejected", "unsupported command was not rejected", failures)
	_expect((state.actors[1] as ActorState).position == Vector3.ZERO, "rejected command changed position", failures)


static func _test_navigation_rejection_is_non_mutating(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var command := Command.create(&"move", 1)
	command.target_pos = Vector3(7.0, 0.0, 7.0)
	var nav := FakeNavProvider.new()
	nav.blocked_destinations.append(command.target_pos)
	var before_hash := JSON.stringify(state.stable_snapshot()).md5_text()
	var result := Resolver.resolve(state, command, nav, FakeLosProvider.new())
	_expect(result.events.size() == 1 and result.events[0].type == &"command_rejected", "non-navigable target was accepted", failures)
	_expect(result.events[0].data["reason"] == &"unreachable", "non-navigable target used the wrong rejection reason", failures)
	_expect(JSON.stringify(state.stable_snapshot()).md5_text() == before_hash, "navigation rejection changed BattleState", failures)


static func _test_combat_move_below_budget_spends_polyline_cost(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var actor: ActorState = state.actors[1]
	actor.movement_remaining = 5.0
	var command := Command.create(&"move", 1)
	command.target_pos = Vector3(4.0, 0.0, 0.0)
	var nav := FakeNavProvider.new()
	nav.set_path(actor.position, command.target_pos, PackedVector3Array([
		actor.position, Vector3(1.0, 0.0, 0.0), command.target_pos,
	]))
	var result := Resolver.resolve(state, command, nav, FakeLosProvider.new())
	_expect(result.events.size() == 2, "below-budget combat move did not emit movement and spending", failures)
	var segment: Event = result.events[0]
	var spent: Event = result.events[1]
	_expect(segment.data["to"] == command.target_pos and not segment.data["clamped"], "below-budget combat move was not fully accepted", failures)
	_expect(is_equal_approx(float(segment.data["path_cost"]), 4.0) and is_equal_approx(float(spent.data["amount"]), 4.0), "below-budget combat move did not use exact polyline cost", failures)
	TestHelpers.apply_result(state, result)
	_expect(actor.position == command.target_pos and is_equal_approx(actor.movement_remaining, 1.0), "below-budget combat move did not apply exact position and spending", failures)


static func _test_combat_move_beyond_budget_clamps_to_exact_distance(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var actor: ActorState = state.actors[1]
	actor.movement_remaining = 5.0
	var command := Command.create(&"move", 1)
	command.target_pos = Vector3(8.0, 0.0, 0.0)
	var nav := FakeNavProvider.new()
	nav.set_path(actor.position, command.target_pos, PackedVector3Array([
		actor.position, Vector3(3.0, 0.0, 0.0), command.target_pos,
	]))
	var result := Resolver.resolve(state, command, nav, FakeLosProvider.new())
	_expect(result.events.size() == 2 and result.events[0].type == &"movement_segment", "over-budget combat move was rejected instead of clamped", failures)
	var segment: Event = result.events[0]
	var clamped_path: PackedVector3Array = segment.data["path"]
	_expect(segment.data["clamped"] and segment.data["to"] == Vector3(5.0, 0.0, 0.0), "combat clamp did not find the exact polyline point", failures)
	_expect(is_equal_approx(PolylineUtil.length(clamped_path), 5.0) and is_equal_approx(float(result.events[1].data["amount"]), 5.0), "combat clamp did not spend the exact available distance", failures)
	TestHelpers.apply_result(state, result)
	_expect(actor.position == Vector3(5.0, 0.0, 0.0) and is_zero_approx(actor.movement_remaining), "clamped combat move did not exhaust movement", failures)


static func _test_detour_clamp_uses_polyline_distance(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var actor: ActorState = state.actors[1]
	actor.movement_remaining = 8.0
	var command := Command.create(&"move", 1)
	command.target_pos = Vector3(4.0, 0.0, 0.0)
	var detour := PackedVector3Array([
		actor.position, Vector3(0.0, 0.0, 6.0), Vector3(4.0, 0.0, 6.0), command.target_pos,
	])
	var nav := FakeNavProvider.new()
	nav.set_path(actor.position, command.target_pos, detour)
	var result := Resolver.resolve(state, command, nav, FakeLosProvider.new())
	var segment: Event = result.events[0]
	_expect(segment.data["to"] == Vector3(2.0, 0.0, 6.0), "detour clamp used direct target distance instead of path distance", failures)
	_expect(is_equal_approx(float(segment.data["requested_path_cost"]), 16.0) and is_equal_approx(float(segment.data["path_cost"]), 8.0), "detour clamp recorded inaccurate polyline costs", failures)


static func _test_exploration_move_ignores_budget(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	state.phase = &"exploration"
	var actor: ActorState = state.actors[1]
	actor.movement_remaining = 0.0
	var command := Command.create(&"move", 1)
	command.target_pos = Vector3(12.0, 0.0, 0.0)
	var result := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(result.events.size() == 1 and result.events[0].type == &"movement_segment", "exploration move incorrectly enforced budget", failures)
	TestHelpers.apply_result(state, result)
	_expect(actor.position == command.target_pos and is_zero_approx(actor.movement_remaining), "exploration move changed movement budget", failures)


static func _test_zero_budget_and_empty_segment_reject_without_mutation(failures: Array[String]) -> void:
	var zero_budget_state := TestHelpers.make_battle()
	(zero_budget_state.actors[1] as ActorState).movement_remaining = 0.0
	var zero_budget_command := Command.create(&"move", 1)
	zero_budget_command.target_pos = Vector3(3.0, 0.0, 0.0)
	var before_hash := JSON.stringify(zero_budget_state.stable_snapshot()).md5_text()
	var zero_budget_result := Resolver.resolve(zero_budget_state, zero_budget_command, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(zero_budget_result.events.size() == 1 and zero_budget_result.events[0].data["reason"] == &"no_movement_remaining", "zero budget did not reject cleanly", failures)
	_expect(JSON.stringify(zero_budget_state.stable_snapshot()).md5_text() == before_hash, "zero-budget rejection changed BattleState", failures)

	var empty_segment_state := TestHelpers.make_battle()
	var empty_segment_command := Command.create(&"move", 1)
	empty_segment_command.target_pos = Vector3.ZERO
	var empty_result := Resolver.resolve(empty_segment_state, empty_segment_command, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(empty_result.events.size() == 1 and empty_result.events[0].data["reason"] == &"no_movement", "empty usable segment did not reject cleanly", failures)
	_expect((empty_segment_state.actors[1] as ActorState).position == Vector3.ZERO, "empty usable segment moved the actor", failures)


static func _test_move_preview_resolution_is_pure(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var command := Command.create(&"move", 1)
	command.target_pos = Vector3(6.0, 0.0, 0.0)
	var before_hash := JSON.stringify(state.stable_snapshot()).md5_text()
	var preview_result := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(preview_result.events.size() == 2 and preview_result.events[0].type == &"movement_segment", "movement preview did not resolve a usable result", failures)
	_expect(JSON.stringify(state.stable_snapshot()).md5_text() == before_hash, "movement preview resolution mutated BattleState", failures)


static func _test_serialization_round_trip(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	state.world_flags = {"checkpoint": Vector3(2.0, 0.0, -3.0), "opened": true}
	var command := Command.create(&"move", 1)
	command.target_pos = Vector3(3.0, 0.0, -2.0)
	command.metadata = {"source": &"click", "sequence": 4}
	var result := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
	var restored_state := BattleState.from_dict(_json_dictionary(state.to_dict()))
	var restored_command := Command.from_dict(_json_dictionary(command.to_dict()))
	var restored_result := ResolutionResult.from_dict(_json_dictionary(result.to_dict()))
	_expect(restored_state.to_dict() == state.to_dict(), "BattleState serialization changed semantic data", failures)
	_expect(restored_command.to_dict() == command.to_dict(), "Command serialization changed semantic data", failures)
	_expect(TestHelpers.event_log_entry(restored_result) == TestHelpers.event_log_entry(result), "ResolutionResult/Event serialization changed event semantics", failures)
	var applied_original := state.clone()
	var applied_restored := state.clone()
	TestHelpers.apply_result(applied_original, result)
	TestHelpers.apply_result(applied_restored, restored_result)
	_expect(applied_restored.to_dict() == applied_original.to_dict(), "restored ResolutionResult applied different state", failures)


static func _json_dictionary(data: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(data))
	if parsed is Dictionary:
		return parsed
	return {}


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
