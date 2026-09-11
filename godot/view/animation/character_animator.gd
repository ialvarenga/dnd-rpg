class_name CharacterAnimator
extends Node

const DEFAULT_ANIMATION_SET: ActorAnimationSet = preload("res://data/animations/knight_animation_set.tres")

## Explicit presentation state machine.  It owns no simulation references and
## accepts only already-narrated view intents from CharacterView/EventPlayer.

## Emitted when the clip playing for `state` reaches its end, so a view can
## chain one-shot clips (knockdown -> prone, stand_up -> ready). Looping clips
## never finish, and a clip interrupted by another request never reports.
signal state_finished(state: StringName)

@export var animation_set: ActorAnimationSet = DEFAULT_ANIMATION_SET
@export_range(0.0, 1.0, 0.01) var blend_seconds := 0.15

## Set by CharacterView from the wielded weapon: a ranged wielder's combat
## stance is the bow at the ready rather than the melee guard.
var ranged_stance := false
var current_state: StringName = &"idle"
var current_clip: StringName = &""
var _players: Array[AnimationPlayer] = []
var _current_player: AnimationPlayer
var _current_player_clip: StringName = &""


func _ready() -> void:
	if animation_set == null:
		animation_set = ActorAnimationSet.new()


func configure_model(model_root: Node) -> void:
	if animation_set == null:
		animation_set = ActorAnimationSet.new()
	_players.clear()
	var model_player := _find_animation_player(model_root)
	if model_player != null:
		_players.append(model_player)
	for path in animation_set.animation_library_paths:
		_add_optional_library(model_root, path)
	_connect_finished_signals()
	request_state(&"idle")


## Public for focused tests and custom actor prefabs.  The supplied players are
## treated as one merged library catalogue while retaining their original
## AnimationPlayer root bindings.
func configure_players(players: Array[AnimationPlayer]) -> void:
	_players = players.duplicate()
	_connect_finished_signals()
	request_state(&"idle")


func locomotion_started() -> void:
	request_state(&"locomotion")


func locomotion_stopped() -> void:
	request_state(&"idle")


func present_attack() -> void:
	request_state(&"attack")


func present_combat_ready() -> void:
	request_state(&"ranged_ready" if ranged_stance and has_clip(&"ranged_ready") else &"combat_ready")


func present_combat_ended() -> void:
	request_state(&"idle")


func present_dodge() -> void:
	request_state(&"dodge")


func present_hit() -> void:
	request_state(&"hit")


func present_interaction() -> void:
	request_state(&"interact")


func present_death() -> void:
	request_state(&"death")


## For view-only input affordances such as jump, crouch, dodge, and block.
## Gameplay code should narrate resolved events through the typed helpers above.
func present(verb: StringName) -> void:
	request_state(verb)


## Freezes whatever pose is showing and relabels it, e.g. a prone actor that
## dies stays where it lies instead of standing back up to replay a fall.
func hold_pose(state: StringName) -> void:
	current_state = state
	if _current_player != null and _current_player.is_playing():
		_current_player.pause()


func request_state(verb: StringName) -> void:
	var requested_clip := animation_set.clip_for(verb) if animation_set != null else &""
	var resolved := _resolve_clip(requested_clip)
	var resolved_state := verb
	if resolved.is_empty() and verb != &"idle":
		resolved = _resolve_idle_clip()
		resolved_state = &"idle"
	elif resolved.is_empty():
		resolved = _resolve_idle_clip()
	if resolved.is_empty():
		current_state = &"idle"
		current_clip = &""
		_stop_all()
		return
	current_state = resolved_state
	var selected: AnimationPlayer = resolved["player"]
	var selected_clip: StringName = resolved["name"]
	# AnimationPlayer keys may be qualified (for example "movement/Walk"),
	# while this component exposes the data-facing clip name to views and tests.
	current_clip = StringName(String(selected_clip).get_file())
	_play(selected, selected_clip, animation_set.speed_scale_for(resolved_state) if animation_set != null else 1.0)


func has_clip(verb: StringName) -> bool:
	return not _resolve_clip(animation_set.clip_for(verb) if animation_set != null else &"").is_empty()


func _resolve_idle_clip() -> Dictionary:
	if animation_set == null:
		return {}
	var resolved := _resolve_clip(animation_set.idle)
	if not resolved.is_empty():
		return resolved
	for fallback_clip in animation_set.idle_fallback_clips:
		resolved = _resolve_clip(StringName(fallback_clip))
		if not resolved.is_empty():
			return resolved
	# An actor may only ship a movement library.  Keep it animated in that
	# case instead of assuming the optional General library supplied idle.
	resolved = _resolve_clip(animation_set.locomotion)
	if not resolved.is_empty():
		return resolved
	# Custom actor libraries need not use KayKit names at all.  Last, select a
	# deterministic first clip from the configured players rather than failing
	# presentation because a non-authoritative asset package is incomplete.
	for player in _players:
		var available := player.get_animation_list()
		if not available.is_empty():
			return {"player": player, "name": available[0]}
	return {}


func _add_optional_library(model_root: Node, path: String) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var scene := load(path) as PackedScene
	if scene == null:
		return
	var source_root := scene.instantiate()
	var source_player := _find_animation_player(source_root)
	if source_player == null:
		source_root.queue_free()
		return
	source_player.owner = null
	source_player.reparent(model_root)
	source_player.name = "AnimationLibrary_%d" % _players.size()
	source_player.root_node = NodePath("..")
	_players.append(source_player)
	source_root.queue_free()


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	return root.find_child("AnimationPlayer", true, false) as AnimationPlayer


func _resolve_clip(clip: StringName) -> Dictionary:
	if clip == &"":
		return {}
	for player in _players:
		for available_name in player.get_animation_list():
			var available_text := String(available_name)
			if available_name == clip or available_text.get_file() == String(clip):
				return {"player": player, "name": available_name}
	return {}


func _play(selected: AnimationPlayer, clip: StringName, speed_scale: float = 1.0) -> void:
	for player in _players:
		if player != selected and player.is_playing():
			player.stop()
	_current_player = selected
	_current_player_clip = clip
	if selected.current_animation != clip or not selected.is_playing():
		selected.play(clip, blend_seconds, speed_scale)


func _stop_all() -> void:
	_current_player = null
	_current_player_clip = &""
	for player in _players:
		if player.is_playing():
			player.stop()


func _connect_finished_signals() -> void:
	for player in _players:
		var callback := _on_player_animation_finished.bind(player)
		if not player.animation_finished.is_connected(callback):
			player.animation_finished.connect(callback)


func _on_player_animation_finished(clip: StringName, player: AnimationPlayer) -> void:
	if player == _current_player and clip == _current_player_clip:
		state_finished.emit(current_state)
