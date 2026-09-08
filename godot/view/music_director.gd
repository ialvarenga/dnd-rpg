class_name MusicDirector
extends Node

## Presentation-only music routing. Combat state remains authoritative in the
## encounter session; this node simply follows that state with the chosen cue.

const AMBIENT_TRACKS := {
	&"ambient_light_1": preload("res://assets/music/ambient-light-1.ogg"),
	&"ambient_night_3": preload("res://assets/music/ambient-night-3.ogg"),
}
const BATTLE_TRACKS := {
	&"battle_action_1": preload("res://assets/music/battle-action-1.ogg"),
	&"battle_action_2": preload("res://assets/music/battle-action-2.ogg"),
}

var ambient_track_id: StringName = &"ambient_light_1"
var battle_track_id: StringName = &"battle_action_1"
var _phase: StringName = &"exploration"
@onready var _player: AudioStreamPlayer = $AudioStreamPlayer


func _ready() -> void:
	_player.finished.connect(_play_current_track)
	call_deferred("_play_current_track")


func set_phase(next_phase: StringName) -> void:
	if _phase == next_phase:
		return
	_phase = next_phase
	_play_current_track()


func configure(settings: Dictionary) -> void:
	var ambient := StringName(settings.get("ambient", ambient_track_id))
	var battle := StringName(settings.get("battle", battle_track_id))
	if AMBIENT_TRACKS.has(ambient):
		ambient_track_id = ambient
	if BATTLE_TRACKS.has(battle):
		battle_track_id = battle
	call_deferred("_play_current_track")


func select_ambient(track_id: StringName) -> void:
	if not AMBIENT_TRACKS.has(track_id):
		return
	ambient_track_id = track_id
	if _phase != &"combat":
		_play_current_track()


func select_battle(track_id: StringName) -> void:
	if not BATTLE_TRACKS.has(track_id):
		return
	battle_track_id = track_id
	if _phase == &"combat":
		_play_current_track()


func _play_current_track() -> void:
	var tracks: Dictionary = BATTLE_TRACKS if _phase == &"combat" else AMBIENT_TRACKS
	var track_id: StringName = battle_track_id if _phase == &"combat" else ambient_track_id
	var stream: AudioStream = tracks.get(track_id)
	if stream == null:
		return
	_player.stop()
	_player.stream = stream
	_player.play()
