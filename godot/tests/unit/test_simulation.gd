class_name TestSimulation
extends RefCounted

static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_clone_is_independent(failures)
	_test_equal_inputs_produce_equal_resolution(failures)
	_test_resolve_does_not_mutate_input(failures)
	_test_apply_changes_only_event_fields(failures)
	_test_rejections_are_non_mutating(failures)
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
	var before := JSON.stringify(state.stable_snapshot())
	var command := Command.create(&"attack", 1)
	command.target_id = 2
	Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(JSON.stringify(state.stable_snapshot()) == before, "resolve mutated BattleState", failures)


static func _test_apply_changes_only_event_fields(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var untouched_position := (state.actors[2] as ActorState).position
	Resolver.apply(state, Event.create(&"damage_taken", {"actor_id": 1, "source_actor_id": 2, "amount": 4}))
	_expect((state.actors[1] as ActorState).hp == 16, "damage event did not change HP", failures)
	_expect((state.actors[2] as ActorState).position == untouched_position, "damage event changed unrelated actor", failures)
	_expect(state.rng_state == 42, "damage event changed RNG", failures)


static func _test_rejections_are_non_mutating(failures: Array[String]) -> void:
	var state := TestHelpers.make_battle()
	var command := Command.create(&"move", 1)
	command.target_pos = Vector3(20.0, 0.0, 0.0)
	var result := Resolver.resolve(state, command, FakeNavProvider.new(), FakeLosProvider.new())
	_expect(result.events.size() == 1 and result.events[0].type == &"command_rejected", "illegal move was not rejected", failures)
	_expect((state.actors[1] as ActorState).position == Vector3.ZERO, "rejected move changed position", failures)


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
