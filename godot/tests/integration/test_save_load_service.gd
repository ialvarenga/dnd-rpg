class_name TestSaveLoadService
extends RefCounted

## Exercises real FileAccess/DirAccess under user:// -- the one place saves
## touch disk (see world/save_load_service.gd). Each test cleans up the slot
## it wrote so repeated headless runs stay hermetic.

const SLOT := "__test_a8_save__"
const REPLAY_SLOT := "__test_a8_replay__"

static func run() -> Dictionary:
	var failures: Array[String] = []
	_test_save_and_load_round_trip(failures)
	_test_missing_slot_reports_absent_and_loads_null(failures)
	_test_replay_save_and_load_round_trip(failures)
	return {"name": "integration/test_save_load_service", "failures": failures}


static func _test_save_and_load_round_trip(failures: Array[String]) -> void:
	SaveLoadService.delete_save(SLOT)
	var state := TestHelpers.make_battle(99)
	(state.actors[1] as ActorState).hp = 7
	var save_game := SaveGame.create(state, "test_arena")

	var write_error := SaveLoadService.save(SLOT, save_game)
	_expect(write_error == OK, "saving to disk failed with error %d" % write_error, failures)
	_expect(SaveLoadService.has_save(SLOT), "has_save should be true right after saving", failures)

	var loaded := SaveLoadService.load_save(SLOT)
	_expect(loaded != null, "loading a saved slot should not return null", failures)
	if loaded != null:
		_expect(loaded.map_id == "test_arena", "loaded map_id did not match what was saved", failures)
		_expect((loaded.battle_state.actors[1] as ActorState).hp == 7, "loaded HP did not match what was saved", failures)
		_expect(loaded.is_compatible(), "freshly written save should be compatible with current versions", failures)

	SaveLoadService.delete_save(SLOT)
	_expect(not SaveLoadService.has_save(SLOT), "delete_save should remove the slot", failures)


static func _test_missing_slot_reports_absent_and_loads_null(failures: Array[String]) -> void:
	SaveLoadService.delete_save(SLOT)
	_expect(not SaveLoadService.has_save(SLOT), "a never-written slot should not be reported as present", failures)
	_expect(SaveLoadService.load_save(SLOT) == null, "loading a missing slot should return null", failures)


static func _test_replay_save_and_load_round_trip(failures: Array[String]) -> void:
	SaveLoadService.delete_replay(REPLAY_SLOT)
	var state := TestHelpers.make_battle(7)
	var log := ReplayLog.start(state)
	var attack := Command.create(&"attack", 1)
	attack.target_id = 2
	var result := Resolver.resolve(state, attack, FakeNavProvider.new(), FakeLosProvider.new())
	log.append_command(attack, result)

	var write_error := SaveLoadService.save_replay(REPLAY_SLOT, log)
	_expect(write_error == OK, "saving a replay log failed with error %d" % write_error, failures)

	var loaded := SaveLoadService.load_replay(REPLAY_SLOT)
	_expect(loaded != null, "loading a saved replay log should not return null", failures)
	if loaded != null:
		_expect(loaded.commands.size() == 1, "loaded replay log lost its recorded commands", failures)
		var divergences := loaded.find_divergences(FakeNavProvider.new(), FakeLosProvider.new())
		_expect(divergences.is_empty(), "replay log loaded from disk should still replay clean", failures)

	SaveLoadService.delete_replay(REPLAY_SLOT)


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
