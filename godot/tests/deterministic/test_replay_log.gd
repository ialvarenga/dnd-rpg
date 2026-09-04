class_name TestReplayLog
extends RefCounted

static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_replay_matches_recorded_hashes(failures)
	_test_replay_detects_a_tampered_hash(failures)
	_test_serialization_round_trip_still_replays_clean(failures)
	return {"name": "deterministic/test_replay_log", "failures": failures}


static func _recorded_log() -> ReplayLog:
	var state := TestHelpers.make_battle(42)
	var log := ReplayLog.start(state)
	var nav := FakeNavProvider.new()
	var los := FakeLosProvider.new()

	var attack := Command.create(&"attack", 1)
	attack.target_id = 2
	var commands: Array[Command] = [attack, Command.create(&"end_turn", 1)]
	var move := Command.create(&"move", 2)
	move.target_pos = Vector3(0.5, 0.0, 0.0)
	commands.append(move)
	commands.append(Command.create(&"end_turn", 2))

	for command in commands:
		var result := Resolver.resolve(state, command, nav, los)
		log.append_command(command, result)
		for event in result.events:
			Resolver.apply(state, event)
		state.rng_state = result.next_rng_state
	return log


static func _test_replay_matches_recorded_hashes(failures: Array[String]) -> void:
	var log := _recorded_log()
	var divergences := log.find_divergences(FakeNavProvider.new(), FakeLosProvider.new())
	_expect(divergences.is_empty(), "clean replay reported divergences: %s" % [divergences], failures)


static func _test_replay_detects_a_tampered_hash(failures: Array[String]) -> void:
	var log := _recorded_log()
	log.event_hashes[0] = "not-a-real-hash"
	var divergences := log.find_divergences(FakeNavProvider.new(), FakeLosProvider.new())
	_expect(divergences == [0], "tampered hash at index 0 should be the only divergence, got %s" % [divergences], failures)


static func _test_serialization_round_trip_still_replays_clean(failures: Array[String]) -> void:
	var original := _recorded_log()
	var restored := ReplayLog.from_dict(original.to_dict())
	_expect(restored.commands.size() == original.commands.size(), "command count did not round-trip", failures)
	_expect(restored.event_hashes == original.event_hashes, "event hashes did not round-trip", failures)
	_expect(restored.rules_version == Resolver.RULES_VERSION, "rules_version did not round-trip", failures)
	_expect(restored.content_version == DefinitionLibrary.CONTENT_VERSION, "content_version did not round-trip", failures)
	var divergences := restored.find_divergences(FakeNavProvider.new(), FakeLosProvider.new())
	_expect(divergences.is_empty(), "restored log replay reported divergences: %s" % [divergences], failures)


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
