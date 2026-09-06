class_name EncounterSession
extends RefCounted

## Shared world-side command pipeline. It owns no Nodes, leaving each scene to
## decide how accepted events are presented.
signal state_changed
signal events_resolved(events: Array[Event])
signal command_rejected(command_type: StringName, reason: StringName)

const MovePreviewScript = preload("res://world/move_preview.gd")

var battle_state: BattleState
var nav: NavProvider
var los: LosProvider


func configure(state: BattleState, nav_provider: NavProvider, los_provider: LosProvider) -> void:
	battle_state = state
	nav = nav_provider
	los = los_provider


func preview_move(actor_id: int, target: Vector3):
	var preview = MovePreviewScript.new()
	preview.ignores_budget = battle_state != null and battle_state.phase != &"combat"
	var command := Command.create(&"move", actor_id)
	command.target_pos = target
	preview.resolution = Resolver.resolve(battle_state, command, nav, los)
	for event in preview.resolution.events:
		if event.type == &"movement_segment":
			preview.accepted = true
			preview.path = (event.data["path"] as PackedVector3Array).duplicate()
			preview.cost = float(event.data["path_cost"])
			preview.destination = event.data["to"]
			var actor: ActorState = battle_state.actors[actor_id]
			preview.remaining = maxf(0.0, actor.movement_remaining - preview.cost)
		elif event.type == &"command_rejected":
			preview.rejection_reason = event.data["reason"]
	return preview


func submit_move(actor_id: int, target: Vector3, view_position: Vector3) -> ResolutionResult:
	var command := Command.create(&"move", actor_id)
	command.target_pos = target
	return _submit(command, view_position)


func submit_interact(actor_id: int, interactable_id: String) -> ResolutionResult:
	var command := Command.create(&"interact", actor_id)
	command.target_interactable_id = interactable_id
	return _submit(command, Vector3.INF)


func submit_ability(actor_id: int, ability_id: StringName, target_id: int, target_pos: Vector3) -> ResolutionResult:
	var command := Command.create(ability_id, actor_id)
	command.target_id = target_id
	command.target_pos = target_pos
	return _submit(command, Vector3.INF)


func end_turn(actor_id: int) -> ResolutionResult:
	return _submit(Command.create(&"end_turn", actor_id), Vector3.INF)


## Encounter triggers and computer-controlled actors submit through the same
## authoritative pipeline as player input. Keeping this public avoids a
## second, view-owned combat state machine.
func submit_command(command: Command, view_position: Vector3 = Vector3.INF) -> ResolutionResult:
	return _submit(command, view_position)


## Advisory HUD data only (Fase C2): reports whether Resolver.resolve() would
## currently accept each of the actor's abilities, and why not when it
## wouldn't. Resolver remains the sole authority for command acceptance.
func available_actions(actor_id: int) -> Array[Dictionary]:
	if battle_state == null or not battle_state.actors.has(actor_id):
		return []
	var actor: ActorState = battle_state.actors[actor_id]
	return ActionAvailability.evaluate_all(battle_state, actor_id, actor.ability_ids)


func _submit(command: Command, view_position: Vector3) -> ResolutionResult:
	var result := Resolver.resolve(battle_state, command, nav, los)
	_prepare_presentation_paths(result, view_position)
	_apply(result)
	events_resolved.emit(result.events)
	for event in result.events:
		if event.type == &"command_rejected":
			command_rejected.emit(command.type, event.data["reason"])
	state_changed.emit()
	return result


func _apply(result: ResolutionResult) -> void:
	for event in result.events:
		Resolver.apply(battle_state, event)
	battle_state.rng_state = result.next_rng_state


func _prepare_presentation_paths(result: ResolutionResult, view_position: Vector3) -> void:
	if view_position == Vector3.INF:
		return
	for event in result.events:
		if event.type != &"movement_segment":
			continue
		var presentation_path := nav.find_path(view_position, event.data["to"])
		if not presentation_path.is_empty():
			event.data["presentation_path"] = presentation_path
