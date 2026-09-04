class_name SaveLoadService
extends RefCounted

## Godot-facing adapter around the pure SaveGame/ReplayLog data classes
## (sim/save_game.gd, sim/replay_log.gd). File I/O is deliberately kept out
## of sim/ -- this is the only place that touches FileAccess for saves, the
## same separation GodotNavProvider/GodotLosProvider keep for their ports.

const SAVE_DIRECTORY := "user://saves"
const REPLAY_DIRECTORY := "user://replays"


static func save_path(slot: String) -> String:
	return "%s/%s.json" % [SAVE_DIRECTORY, slot]


static func replay_path(slot: String) -> String:
	return "%s/%s.json" % [REPLAY_DIRECTORY, slot]


static func has_save(slot: String) -> bool:
	return FileAccess.file_exists(save_path(slot))


static func has_replay(slot: String) -> bool:
	return FileAccess.file_exists(replay_path(slot))


static func save(slot: String, save_game: SaveGame) -> Error:
	DirAccess.make_dir_recursive_absolute(SAVE_DIRECTORY)
	var file := FileAccess.open(save_path(slot), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(save_game.to_dict()))
	return OK


static func load_save(slot: String) -> SaveGame:
	var file := FileAccess.open(save_path(slot), FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return null
	return SaveGame.from_dict(parsed)


static func delete_save(slot: String) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(save_path(slot))


static func save_replay(slot: String, replay_log: ReplayLog) -> Error:
	DirAccess.make_dir_recursive_absolute(REPLAY_DIRECTORY)
	var file := FileAccess.open(replay_path(slot), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(replay_log.to_dict()))
	return OK


static func load_replay(slot: String) -> ReplayLog:
	var file := FileAccess.open(replay_path(slot), FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return null
	return ReplayLog.from_dict(parsed)


static func delete_replay(slot: String) -> void:
	if has_replay(slot):
		DirAccess.remove_absolute(replay_path(slot))
