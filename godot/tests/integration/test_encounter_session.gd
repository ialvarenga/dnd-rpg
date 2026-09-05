class_name TestEncounterSession
extends RefCounted

## Exercises the world-side session boundary without creating UI nodes.  The
## Resolver remains the command authority; this suite checks only the session
## configuration, signal, apply, and presentation-path responsibilities.

static func run() -> Dictionary:
	var failures: Array[String] = []
	var state := TestHelpers.make_battle()
	(state.actors[2] as ActorState).position = Vector3(99.0, 0.0, 0.0)
	var nav := FakeNavProvider.new()
	var los := FakeLosProvider.new()
	var session := EncounterSession.new()
	session.configure(state, nav, los)
	_expect(session.battle_state == state and session.nav == nav and session.los == los, "configure did not retain the supplied simulation ports", failures)

	var state_change_count := 0
	var resolved_events: Array[Event] = []
	var rejections: Array[Dictionary] = []
	session.state_changed.connect(func(): state_change_count += 1)
	session.events_resolved.connect(func(events: Array[Event]): resolved_events = events.duplicate())
	session.command_rejected.connect(func(command_type: StringName, reason: StringName): rejections.append({"command_type": command_type, "reason": reason}))

	var view_position := Vector3(-2.0, 0.0, 0.0)
	var accepted := session.submit_move(1, Vector3(2.0, 0.0, 0.0), view_position)
	_expect(not accepted.events.is_empty() and accepted.events[0].type == &"movement_segment", "accepted session submission did not expose Resolver movement events", failures)
	_expect(resolved_events == accepted.events, "accepted session submission did not emit its resolved events", failures)
	_expect((state.actors[1] as ActorState).position == Vector3(2.0, 0.0, 0.0), "accepted session submission did not apply Resolver events", failures)
	var movement: Event = accepted.events[0]
	var presentation_path: PackedVector3Array = movement.data.get("presentation_path", PackedVector3Array())
	_expect(presentation_path.size() == 2 and presentation_path[0] == view_position and presentation_path[1] == movement.data["to"], "session did not rebase the presentation path from the view position", failures)

	var rejected := session.end_turn(2)
	_expect(rejected.events.size() == 1 and rejected.events[0].type == &"command_rejected", "rejected session submission did not expose the Resolver rejection event", failures)
	_expect(rejections == [{"command_type": &"end_turn", "reason": &"not_current_actor"}], "session did not emit the authoritative rejection reason", failures)
	_expect(state_change_count == 2, "session did not emit state_changed once per submitted command", failures)
	return {"name": "integration/test_encounter_session", "failures": failures}


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
