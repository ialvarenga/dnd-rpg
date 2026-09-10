class_name DialogSession
extends RefCounted

## Headless walker over one DialogCatalog graph. It owns no Nodes and touches
## no BattleState, so it unit-tests without a scene tree -- the same split as
## MovePreview and the action planners.
##
## The division of labour is deliberate: navigating from node to node is
## presentation, so it lives here, while the d20 roll, the disposition change,
## and starting a fight are authoritative and go through EncounterSession. This
## class therefore never rolls anything. It asks (check_requested), the owner
## submits the command, and the owner reports back (resolve_check).

const DialogCatalogScript = preload("res://world/dialog_catalog.gd")

## {speaker, text, options: [{index, text, check}]}
signal presented(view: Dictionary)
signal check_requested(option_index: int, ability: StringName, skill: StringName, difficulty_class: int, proficient: bool)
## A priced option pauses graph traversal until the owner reports whether its
## authoritative transfer command succeeded.
signal payment_requested(option_index: int, coin_cost: int)
## &"end" | &"start_combat" | &"pacify_encounter"
signal finished(effect: StringName)

const EFFECT_NONE := &"none"
const EFFECT_END := &"end"
const EFFECT_START_COMBAT := &"start_combat"
const EFFECT_PACIFY_ENCOUNTER := &"pacify_encounter"

## Effects that close the conversation and hand work back to the owner. An
## outcome carrying one of these ignores its `next`: you do not keep talking
## after the swords come out.
const TERMINAL_EFFECTS: Array[StringName] = [EFFECT_START_COMBAT, EFFECT_PACIFY_ENCOUNTER]

var _catalog: DialogCatalogScript
var _dialog_id: StringName = &""
var _node_id: StringName = &""
var _speaker_actor_id: int = -1
var _speaker_name: String = ""
var _active: bool = false
var _pending_payment_option_index: int = -1


func configure(catalog: DialogCatalogScript) -> void:
	_catalog = catalog


## False when the dialog or its root node is unknown, leaving the session
## inactive so the caller can fall back to its normal click handling.
func begin(dialog_id: StringName, speaker_actor_id: int, speaker_name: String) -> bool:
	if _catalog == null or not _catalog.has_dialog(dialog_id):
		return false
	var root := _catalog.root_node_id(dialog_id)
	if _catalog.node(dialog_id, root).is_empty():
		return false
	_dialog_id = dialog_id
	_speaker_actor_id = speaker_actor_id
	_speaker_name = speaker_name
	_active = true
	_present(root)
	return true


func is_active() -> bool:
	return _active


func speaker_actor_id() -> int:
	return _speaker_actor_id


## An option carrying a check does not advance here: it emits check_requested
## and waits for resolve_check, so the roll always happens in the simulation.
func choose(option_index: int) -> void:
	if _pending_payment_option_index >= 0:
		return
	var option := _option(option_index)
	if option.is_empty():
		return
	var coin_cost := int(option.get("coin_cost", 0))
	if coin_cost > 0:
		_pending_payment_option_index = option_index
		payment_requested.emit(option_index, coin_cost)
		return
	var check: Dictionary = option["check"]
	if check.is_empty():
		_advance(option["outcome"])
		return
	check_requested.emit(option_index, check["ability"], check["skill"], int(check["dc"]), bool(check["proficient"]))


func resolve_check(option_index: int, success: bool) -> void:
	var option := _option(option_index)
	if option.is_empty():
		return
	_advance(option["outcome"] if success else option["failure_outcome"])


## Failed or rejected transfers deliberately keep the player on the same
## node. The controller will re-project its current wallet into the view,
## which disables any newly unaffordable cost without trusting the UI as the
## source of truth.
func resolve_payment(option_index: int, succeeded: bool) -> void:
	if not _active or option_index != _pending_payment_option_index:
		return
	_pending_payment_option_index = -1
	var option := _option(option_index)
	if option.is_empty():
		return
	if succeeded:
		_advance(option["outcome"])
	else:
		_present(_node_id)


## Closes the conversation without any outcome -- the player walked away, or
## the owner is tearing the map down. Deliberately silent: no `finished`, so a
## cancel cannot be mistaken for an authored ending.
func cancel() -> void:
	_active = false
	_dialog_id = &""
	_node_id = &""
	_speaker_actor_id = -1
	_pending_payment_option_index = -1


func _option(option_index: int) -> Dictionary:
	if not _active:
		return {}
	var options: Array = _catalog.node(_dialog_id, _node_id).get("options", [])
	if option_index < 0 or option_index >= options.size():
		return {}
	return options[option_index]


func _advance(outcome: Dictionary) -> void:
	var effect: StringName = outcome.get("effect", EFFECT_NONE)
	if TERMINAL_EFFECTS.has(effect):
		_finish(effect)
		return
	var next: StringName = outcome.get("next", &"")
	# No destination, an explicit `end`, or a dangling id all mean the same
	# thing to the player: the conversation is over.
	if effect == EFFECT_END or next == &"" or _catalog.node(_dialog_id, next).is_empty():
		_finish(EFFECT_END)
		return
	_present(next)


func _present(node_id: StringName) -> void:
	_node_id = node_id
	var node := _catalog.node(_dialog_id, node_id)
	var options: Array[Dictionary] = []
	var index := 0
	for option in node.get("options", []):
		options.append({
			"index": index,
			"text": option["text"],
			"coin_cost": int(option.get("coin_cost", 0)),
			"check": (option["check"] as Dictionary).duplicate(),
		})
		index += 1
	presented.emit({
		"speaker": node.get("speaker", "") if not str(node.get("speaker", "")).is_empty() else _speaker_name,
		"text": node.get("text", ""),
		"options": options,
	})


func _finish(effect: StringName) -> void:
	_active = false
	_node_id = &""
	_pending_payment_option_index = -1
	finished.emit(effect)
