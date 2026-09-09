class_name TestDialogSession
extends RefCounted

## DialogSession walks the graph and nothing else: it must never roll, never
## touch BattleState, and never resolve a check on its own. These tests drive
## it entirely through its signals, the way the controller does.

const DialogCatalogScript = preload("res://world/dialog_catalog.gd")
const DialogSessionScript = preload("res://world/dialog_session.gd")

static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_begin_presents_the_root_node(failures)
	_test_unknown_dialog_does_not_begin(failures)
	_test_plain_option_advances_to_next_node(failures)
	_test_check_option_waits_for_the_simulation(failures)
	_test_check_outcome_follows_success_and_failure(failures)
	_test_terminal_effects_finish_the_conversation(failures)
	_test_missing_next_ends_cleanly(failures)
	_test_dangling_next_ends_instead_of_crashing(failures)
	_test_cancel_is_silent(failures)
	_test_speaker_falls_back_to_the_actor_name(failures)
	return {"name": "unit/test_dialog_session", "failures": failures}


static func _spec() -> Dictionary:
	return {"dialogs": [{
		"id": "toll",
		"root": "greeting",
		"nodes": [
			{"id": "greeting", "speaker": "Chieftain", "text": "Pay the toll.", "options": [
				{"text": "Ask why", "outcome": {"next": "why"}},
				{"text": "Bluff", "check": {"ability": "charisma", "skill": "persuasion", "dc": 12, "proficient": true},
					"outcome": {"next": "aside"}, "failure_outcome": {"effect": "start_combat"}},
				{"text": "Draw", "outcome": {"effect": "start_combat"}},
				{"text": "Leave", "outcome": {"effect": "end"}},
				{"text": "Nowhere", "outcome": {"next": "deleted_node"}},
				{"text": "Silence", "outcome": {}},
			]},
			{"id": "why", "text": "Because we hold the road.", "options": []},
			{"id": "aside", "text": "Walk on.", "options": [
				{"text": "Go", "outcome": {"effect": "pacify_encounter"}},
			]},
		],
	}]}


static func _session() -> DialogSessionScript:
	var catalog := DialogCatalogScript.new()
	catalog.configure(_spec())
	var session := DialogSessionScript.new()
	session.configure(catalog)
	return session


## Records everything the session emits, so a test can assert on what the panel
## and the controller would actually have seen.
class Recorder extends RefCounted:
	var views: Array[Dictionary] = []
	var checks: Array[Dictionary] = []
	var effects: Array[StringName] = []

	func bind(session: DialogSessionScript) -> void:
		session.presented.connect(func(view: Dictionary): views.append(view))
		session.check_requested.connect(func(index: int, ability: StringName, skill: StringName, dc: int, proficient: bool):
			checks.append({"index": index, "ability": ability, "skill": skill, "dc": dc, "proficient": proficient}))
		session.finished.connect(func(effect: StringName): effects.append(effect))


static func _begun(recorder: Recorder) -> DialogSessionScript:
	var session := _session()
	recorder.bind(session)
	session.begin(&"toll", 7, "Bandit Chieftain")
	return session


static func _test_begin_presents_the_root_node(failures: Array[String]) -> void:
	var recorder := Recorder.new()
	var session := _begun(recorder)
	_expect(session.is_active(), "begin() should activate the session", failures)
	_expect(session.speaker_actor_id() == 7, "the session should remember who is speaking", failures)
	_expect(recorder.views.size() == 1, "begin() should present exactly one node", failures)
	_expect(recorder.views[0]["text"] == "Pay the toll.", "begin() should present the authored root node", failures)
	_expect((recorder.views[0]["options"] as Array).size() == 6, "the presented node should carry every authored option", failures)
	var second_option: Dictionary = recorder.views[0]["options"][1]
	_expect(second_option["index"] == 1, "an option should carry its own index for the panel to send back", failures)
	_expect(not (second_option["check"] as Dictionary).is_empty(), "an option with a check should advertise it to the panel", failures)


static func _test_unknown_dialog_does_not_begin(failures: Array[String]) -> void:
	var recorder := Recorder.new()
	var session := _session()
	recorder.bind(session)
	_expect(not session.begin(&"no_such_dialog", 7, "Nobody"), "begin() should report an unknown dialog", failures)
	_expect(not session.is_active(), "an unknown dialog must leave the session inactive", failures)
	_expect(recorder.views.is_empty(), "an unknown dialog must present nothing", failures)


static func _test_plain_option_advances_to_next_node(failures: Array[String]) -> void:
	var recorder := Recorder.new()
	var session := _begun(recorder)
	session.choose(0)
	_expect(recorder.views.size() == 2, "a check-free option should present the next node", failures)
	_expect(recorder.views[1]["text"] == "Because we hold the road.", "the option should follow its authored `next`", failures)
	_expect(recorder.checks.is_empty(), "a check-free option must not request a roll", failures)
	_expect(session.is_active(), "advancing to another node keeps the conversation open", failures)


static func _test_check_option_waits_for_the_simulation(failures: Array[String]) -> void:
	var recorder := Recorder.new()
	var session := _begun(recorder)
	session.choose(1)
	_expect(recorder.checks.size() == 1, "an option with a check should request exactly one roll", failures)
	_expect(recorder.checks[0]["ability"] == &"charisma" and recorder.checks[0]["skill"] == &"persuasion", "the request should carry the authored ability and skill", failures)
	_expect(int(recorder.checks[0]["dc"]) == 12 and bool(recorder.checks[0]["proficient"]), "the request should carry the authored DC and proficiency", failures)
	# The whole point: the graph does not move until the resolver has spoken.
	_expect(recorder.views.size() == 1, "a check option must not advance before its roll is resolved", failures)
	_expect(recorder.effects.is_empty(), "a check option must not finish before its roll is resolved", failures)


static func _test_check_outcome_follows_success_and_failure(failures: Array[String]) -> void:
	var passed := Recorder.new()
	var passing_session := _begun(passed)
	passing_session.choose(1)
	passing_session.resolve_check(1, true)
	_expect(passed.views.size() == 2 and passed.views[1]["text"] == "Walk on.", "a passed check should take the option's outcome", failures)

	var failed := Recorder.new()
	var failing_session := _begun(failed)
	failing_session.choose(1)
	failing_session.resolve_check(1, false)
	_expect(failed.effects == [&"start_combat"], "a failed check should take the failure_outcome", failures)
	_expect(not failing_session.is_active(), "a terminal failure_outcome should close the conversation", failures)


static func _test_terminal_effects_finish_the_conversation(failures: Array[String]) -> void:
	var recorder := Recorder.new()
	var session := _begun(recorder)
	session.choose(2)
	_expect(recorder.effects == [&"start_combat"], "drawing should finish with start_combat", failures)
	_expect(not session.is_active(), "a terminal effect should deactivate the session", failures)
	# A finished session ignores further input rather than resuming.
	session.choose(0)
	_expect(recorder.views.size() == 1, "a finished session must not present anything more", failures)

	var pacified := Recorder.new()
	var pacify_session := _begun(pacified)
	pacify_session.choose(1)
	pacify_session.resolve_check(1, true)
	pacify_session.choose(0)
	_expect(pacified.effects == [&"pacify_encounter"], "the peaceful branch should finish with pacify_encounter", failures)


static func _test_missing_next_ends_cleanly(failures: Array[String]) -> void:
	var explicit := Recorder.new()
	var explicit_session := _begun(explicit)
	explicit_session.choose(3)
	_expect(explicit.effects == [&"end"], "an explicit `end` effect should finish the conversation", failures)

	var implicit := Recorder.new()
	var implicit_session := _begun(implicit)
	implicit_session.choose(5)
	_expect(implicit.effects == [&"end"], "an outcome with neither next nor effect should end the conversation", failures)


static func _test_dangling_next_ends_instead_of_crashing(failures: Array[String]) -> void:
	var recorder := Recorder.new()
	var session := _begun(recorder)
	session.choose(4)
	_expect(recorder.effects == [&"end"], "a jump to a missing node should end the conversation", failures)
	_expect(not session.is_active(), "a dangling jump must not leave the session stuck open", failures)


static func _test_cancel_is_silent(failures: Array[String]) -> void:
	var recorder := Recorder.new()
	var session := _begun(recorder)
	session.cancel()
	_expect(not session.is_active(), "cancel() should deactivate the session", failures)
	# Silence matters: the controller must not mistake walking away for an
	# authored ending and start pacifying anybody.
	_expect(recorder.effects.is_empty(), "cancel() must not emit an outcome", failures)


static func _test_speaker_falls_back_to_the_actor_name(failures: Array[String]) -> void:
	var recorder := Recorder.new()
	var session := _begun(recorder)
	_expect(recorder.views[0]["speaker"] == "Chieftain", "an authored speaker should win", failures)
	session.choose(0)
	_expect(recorder.views[1]["speaker"] == "Bandit Chieftain", "a node with no speaker should fall back to the actor's name", failures)


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
