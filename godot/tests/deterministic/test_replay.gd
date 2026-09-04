class_name TestReplay
extends RefCounted

const RUNS := 1000

static func run() -> Dictionary:
	var failures: Array[String] = []
	var baseline := _simulate(42)
	for index in range(RUNS):
		var replay := _simulate(42)
		if replay != baseline:
			failures.append("same seed replay diverged on run %d" % (index + 1))
			break
	_expect(_simulate(43) != baseline, "different seed did not change an event log with attacks", failures)
	return {"name": "deterministic/test_replay", "failures": failures}


static func _simulate(seed: int) -> String:
	var state := TestHelpers.make_battle(seed)
	var nav := FakeNavProvider.new()
	var los := FakeLosProvider.new()
	var commands: Array[Command] = []
	var attack_one := Command.create(&"attack", 1)
	attack_one.target_id = 2
	commands.append(attack_one)
	commands.append(Command.create(&"end_turn", 1))
	var attack_two := Command.create(&"attack", 2)
	attack_two.target_id = 1
	commands.append(attack_two)
	commands.append(Command.create(&"end_turn", 2))
	var move := Command.create(&"move", 1)
	move.target_pos = Vector3(0.5, 0.0, 0.0)
	commands.append(move)
	commands.append(Command.create(&"end_turn", 1))

	var log: Array[String] = []
	for command in commands:
		var result := Resolver.resolve(state, command, nav, los)
		log.append(TestHelpers.event_log_entry(result))
		TestHelpers.apply_result(state, result)
	return "\n".join(log).md5_text()


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)

