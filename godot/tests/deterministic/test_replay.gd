class_name TestReplay
extends RefCounted

const RUNS := 1000

static func run() -> Dictionary:
	var failures: Array[String] = []
	var baseline := _simulate(42)
	var turn_baseline := _simulate_turns(42)
	var action_baseline := _simulate_actions_and_reactions(42)
	var definitions_baseline := _simulate_definitions(42)
	var social_baseline := _simulate_social(42)
	for index in range(RUNS):
		var replay := _simulate(42)
		if replay != baseline:
			failures.append("same seed replay diverged on run %d" % (index + 1))
			break
		if _simulate_turns(42) != turn_baseline:
			failures.append("same seed turn replay diverged on run %d" % (index + 1))
			break
		if _simulate_actions_and_reactions(42) != action_baseline:
			failures.append("same seed A5 action/reaction replay diverged on run %d" % (index + 1))
			break
		if _simulate_definitions(42) != definitions_baseline:
			failures.append("same seed A7 definition-driven replay diverged on run %d" % (index + 1))
			break
		if _simulate_social(42) != social_baseline:
			failures.append("same seed social replay diverged on run %d" % (index + 1))
			break
	_expect(_simulate(43) != baseline, "different seed did not change an event log with attacks", failures)
	_expect(_simulate_turns(43) != turn_baseline, "different seed did not change an initiative event log", failures)
	_expect(_simulate_actions_and_reactions(43) != action_baseline, "different seed did not change an A5 reaction event log", failures)
	_expect(_simulate_definitions(43) != definitions_baseline, "different seed did not change an A7 definition-driven event log", failures)
	_expect(_simulate_social(43) != social_baseline, "different seed did not change a skill-check event log", failures)
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


## Skill checks consume rng_state like any other roll, so a conversation has to
## replay byte-for-byte on the same seed and diverge on a different one. Two
## checks bracket the disposition change, which proves the second roll picks up
## the state the first one advanced.
static func _simulate_social(seed: int) -> String:
	var state := TestHelpers.make_battle(seed)
	state.phase = &"exploration"
	var nav := FakeNavProvider.new()
	var los := FakeLosProvider.new()
	var persuade := Command.create(&"skill_check", 1)
	persuade.target_id = 2
	persuade.metadata = {"ability": &"charisma", "skill": &"persuasion", "dc": 12, "proficient": true}
	var pacify := Command.create(&"set_disposition", 2)
	pacify.metadata = {"disposition": &"neutral"}
	var second_look := Command.create(&"skill_check", 1)
	second_look.target_id = 2
	second_look.metadata = {"ability": &"wisdom", "skill": &"insight", "dc": 10, "proficient": false}

	var log: Array[String] = []
	for command in [persuade, pacify, second_look]:
		var result := Resolver.resolve(state, command, nav, los)
		log.append(TestHelpers.event_log_entry(result))
		TestHelpers.apply_result(state, result)
	return "\n".join(log).md5_text()


static func _simulate_turns(seed: int) -> String:
	var state := TestHelpers.make_battle(seed)
	state.phase = &"exploration"
	var nav := FakeNavProvider.new()
	var los := FakeLosProvider.new()
	var log: Array[String] = []
	var start := Resolver.resolve(state, Command.create(&"start_combat", 1), nav, los)
	log.append(TestHelpers.event_log_entry(start))
	TestHelpers.apply_result(state, start)
	for _turn in range(2):
		var end_turn := Resolver.resolve(state, Command.create(&"end_turn", state.current_actor_id()), nav, los)
		log.append(TestHelpers.event_log_entry(end_turn))
		TestHelpers.apply_result(state, end_turn)
	return "\n".join(log).md5_text()


static func _simulate_actions_and_reactions(seed: int) -> String:
	var state := TestHelpers.make_battle(seed)
	var nav := FakeNavProvider.new()
	var los := FakeLosProvider.new()
	var move := Command.create(&"move", 1)
	move.target_pos = Vector3(4.0, 0.0, 0.0)
	var commands: Array[Command] = [move, Command.create(&"end_turn", 1), Command.create(&"end_turn", 2), Command.create(&"dash", 1)]
	var log: Array[String] = []
	for command in commands:
		var result := Resolver.resolve(state, command, nav, los)
		log.append(TestHelpers.event_log_entry(result))
		TestHelpers.apply_result(state, result)
	return "\n".join(log).md5_text()


static func _simulate_definitions(seed: int) -> String:
	# Exercises the A7 data-driven paths (dash's add_base_movement effect and
	# poisoned's attack-roll disadvantage modifier) through the same replay
	# harness as A3-A6, using the default DefinitionLibrary content.
	var state := TestHelpers.make_battle(seed)
	(state.actors[2] as ActorState).add_condition(&"poisoned")
	var nav := FakeNavProvider.new()
	var los := FakeLosProvider.new()
	var commands: Array[Command] = [Command.create(&"dash", 1), Command.create(&"end_turn", 1)]
	var attack := Command.create(&"attack", 2)
	attack.target_id = 1
	commands.append(attack)
	commands.append(Command.create(&"end_turn", 2))

	var log: Array[String] = []
	for command in commands:
		var result := Resolver.resolve(state, command, nav, los)
		log.append(TestHelpers.event_log_entry(result))
		TestHelpers.apply_result(state, result)
	return "\n".join(log).md5_text()


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
