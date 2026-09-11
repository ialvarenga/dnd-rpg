class_name EncounterSession
extends RefCounted

## Shared world-side command pipeline. It owns no Nodes, leaving each scene to
## decide how accepted events are presented.
signal state_changed
signal events_resolved(events: Array[Event])
signal command_rejected(command_type: StringName, reason: StringName)

const MovePreviewScript = preload("res://world/move_preview.gd")
const TargetedActionPlannerScript = preload("res://sim/targeted_action_planner.gd")
const InteractableActionPlannerScript = preload("res://sim/interactable_action_planner.gd")
const JumpRulesScript = preload("res://sim/rules/jump_rules.gd")

var battle_state: BattleState
var nav: NavProvider
var los: LosProvider


func configure(state: BattleState, nav_provider: NavProvider, los_provider: LosProvider) -> void:
	battle_state = state
	nav = nav_provider
	los = los_provider


func replace_state(state: BattleState) -> void:
	battle_state = state
	state_changed.emit()


func preview_move(actor_id: int, target: Vector3, view_position: Vector3 = Vector3.INF):
	var preview = MovePreviewScript.new()
	preview.ignores_budget = battle_state != null and battle_state.phase != &"combat"
	var command := Command.create(&"move", actor_id)
	command.target_pos = target
	# Accepted commands update BattleState before CharacterView finishes its
	# presentation. Resolve previews on a clone rebased to the live view so a new
	# pointer path starts at the character, not at the previous clicked target.
	var preview_state := battle_state
	if view_position != Vector3.INF and battle_state != null and battle_state.actors.has(actor_id):
		preview_state = battle_state.clone()
		(preview_state.actors[actor_id] as ActorState).position = view_position
	preview.resolution = Resolver.resolve(preview_state, command, nav, los)
	# A move is walking legs joined by ledge jumps (ADR-009); the preview is
	# their concatenation, costed as the resolver charges it.
	for event in preview.resolution.events:
		match event.type:
			&"movement_segment":
				preview.accepted = true
				preview.path = _appended(preview.path, event.data["path"])
				preview.cost += float(event.data["path_cost"])
				preview.destination = event.data["to"]
			&"jump_performed":
				preview.accepted = true
				preview.path = _appended(preview.path, PackedVector3Array([event.data["from"], event.data["to"]]))
				preview.cost += float(event.data["movement_cost"])
				preview.destination = event.data["to"]
				var jumper: ActorState = preview_state.actors[actor_id]
				var landing := JumpRulesScript.drop_outcome(jumper.strength, float(event.data["height"])) if StringName(event.data["kind"]) == JumpRulesScript.DROP else {"dice": 0, "prone": false}
				preview.jumps.append({
					"from": event.data["from"], "to": event.data["to"],
					"kind": event.data["kind"], "height": float(event.data["height"]),
					"dice": int(landing["dice"]), "prone": bool(landing["prone"]),
				})
			&"command_rejected":
				preview.rejection_reason = event.data["reason"]
	if preview.accepted:
		var actor: ActorState = preview_state.actors[actor_id]
		preview.remaining = maxf(0.0, actor.movement_remaining - preview.cost)
	return preview


## Non-mutating read-model for aiming the Jump action (ADR-009): whether a
## leap to `target` would resolve, where it lands and what it costs, and how
## far this jumper reaches right now. {accepted, reason, running,
## max_distance, remaining, ignores_budget, jump: {from, to, kind, height,
## distance, dice, prone, cost}}.
func preview_jump(actor_id: int, target: Vector3, view_position: Vector3 = Vector3.INF) -> Dictionary:
	var preview_state := battle_state
	if view_position != Vector3.INF and battle_state != null and battle_state.actors.has(actor_id):
		preview_state = battle_state.clone()
		(preview_state.actors[actor_id] as ActorState).position = view_position
	var actor: ActorState = preview_state.actors[actor_id]
	var running := actor.run_up_m + JumpRulesScript.EPSILON >= JumpRulesScript.RUN_UP_M
	var preview := {
		"accepted": false, "reason": &"", "running": running,
		"max_distance": JumpRulesScript.long_jump_m(actor.strength, running),
		"remaining": actor.movement_remaining, "ignores_budget": preview_state.phase != &"combat",
		"jump": {},
	}
	var command := Command.create(&"jump", actor_id)
	command.target_pos = target
	for event in Resolver.resolve(preview_state, command, nav, los).events:
		match event.type:
			&"jump_performed":
				var height := float(event.data["height"])
				var kind := StringName(event.data["kind"])
				var landing := JumpRulesScript.drop_outcome(actor.strength, height) if kind == JumpRulesScript.DROP else {"dice": 0, "prone": false}
				var from: Vector3 = event.data["from"]
				var to: Vector3 = event.data["to"]
				preview["accepted"] = true
				preview["remaining"] = maxf(0.0, actor.movement_remaining - float(event.data["movement_cost"]))
				preview["jump"] = {
					"from": from, "to": to, "kind": kind, "height": height,
					"distance": Vector2(from.x, from.z).distance_to(Vector2(to.x, to.z)),
					"dice": int(landing["dice"]), "prone": bool(landing["prone"]),
					"cost": float(event.data["movement_cost"]),
				}
			&"command_rejected":
				preview["reason"] = StringName(event.data["reason"])
	return preview


## Packed arrays are passed by value, so the joined path is returned.
func _appended(combined: PackedVector3Array, segment: PackedVector3Array) -> PackedVector3Array:
	var joined := combined.duplicate()
	for point in segment:
		if joined.is_empty() or joined[joined.size() - 1].distance_squared_to(point) > 0.000001:
			joined.append(point)
	return joined


func submit_move(actor_id: int, target: Vector3, view_position: Vector3) -> ResolutionResult:
	var command := Command.create(&"move", actor_id)
	command.target_pos = target
	return _submit(command, view_position)


func submit_interact(actor_id: int, interactable_id: String) -> ResolutionResult:
	var command := Command.create(&"interact", actor_id)
	command.target_interactable_id = interactable_id
	return _submit(command, Vector3.INF)


func submit_ability(actor_id: int, ability_id: StringName, target_id: int, target_pos: Vector3, metadata: Dictionary = {}) -> ResolutionResult:
	var command := Command.create(ability_id, actor_id)
	command.target_id = target_id
	command.target_pos = target_pos
	command.metadata = metadata.duplicate(true)
	return _submit(command, Vector3.INF)


func submit_interactable_ability(actor_id: int, ability_id: StringName, interactable_id: String) -> ResolutionResult:
	var command := Command.create(ability_id, actor_id)
	command.target_interactable_id = interactable_id
	return _submit(command, Vector3.INF)


## Non-mutating plan for the general actor-targeted "approach, then act"
## workflow. Controllers decide when presentation movement has completed and
## submit the actual ability afterward.
func plan_targeted_ability(actor_id: int, ability_id: StringName, target_id: int):
	return TargetedActionPlannerScript.plan(battle_state, actor_id, ability_id, target_id, nav, los)


## Non-mutating plan for clicking an out-of-range world item. The plan stops
## at interaction range instead of trying to walk onto the item's blocker.
func plan_interaction(actor_id: int, interactable_id: String):
	return InteractableActionPlannerScript.plan(battle_state, actor_id, interactable_id, nav, los)


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
		# Past a ledge jump the view is re-synchronised by the jump itself, and a
		# walking-only path from the old view position could not follow it.
		if event.type == &"jump_performed":
			return
		if event.type != &"movement_segment":
			continue
		var presentation_path := nav.find_path(view_position, event.data["to"])
		if not presentation_path.is_empty():
			event.data["presentation_path"] = presentation_path
