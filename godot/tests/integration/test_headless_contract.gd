class_name TestHeadlessContract
extends RefCounted

static func run() -> Dictionary:
	var failures: Array[String] = []
	var state := TestHelpers.make_battle()
	var move := Command.create(&"move", 1)
	move.target_pos = Vector3(3.0, 0.0, 0.0)
	var result := Resolver.resolve(state, move, FakeNavProvider.new(), FakeLosProvider.new())
	TestHelpers.apply_result(state, result)
	_expect((state.actors[1] as ActorState).position == Vector3(3.0, 0.0, 0.0), "headless move did not apply", failures)
	_expect((state.actors[1] as ActorState).movement_remaining == 6.0, "movement budget is incorrect", failures)
	return {"name": "integration/test_headless_contract", "failures": failures}


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)

