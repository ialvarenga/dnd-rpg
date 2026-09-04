class_name Resolver
extends RefCounted

const ATTACK_RANGE_METERS := 1.5
const MOVEMENT_EPSILON := 0.0001
const PolylineUtil = preload("res://sim/polyline.gd")
const EncounterRules = preload("res://sim/rules/encounter.gd")
const InitiativeRules = preload("res://sim/rules/initiative.gd")
const TurnOrderRules = preload("res://sim/rules/turn_order.gd")


static func resolve(state: BattleState, cmd: Command, nav: NavProvider, los: LosProvider) -> ResolutionResult:
	var result := ResolutionResult.new()
	result.next_rng_state = state.rng_state

	if not state.actors.has(cmd.actor_id):
		return _rejected(result, cmd, "unknown_actor")
	if cmd.type == &"start_combat":
		return _resolve_start_combat(state, cmd, result)
	if cmd.type == &"end_combat":
		return _resolve_end_combat(state, cmd, result)
	if cmd.type == &"move" and state.phase == EncounterRules.EXPLORATION:
		return _resolve_move(state, cmd, nav, result)
	if state.phase != EncounterRules.COMBAT:
		return _rejected(result, cmd, "not_in_combat")
	if state.current_actor_id() != cmd.actor_id:
		return _rejected(result, cmd, "not_current_actor")

	match cmd.type:
		&"move":
			return _resolve_move(state, cmd, nav, result)
		&"attack":
			return _resolve_attack(state, cmd, los, result)
		&"end_turn":
			return _resolve_end_turn(state, cmd, result)
		_:
			return _rejected(result, cmd, "unsupported_command")


static func _resolve_start_combat(state: BattleState, cmd: Command, result: ResolutionResult) -> ResolutionResult:
	if state.phase != EncounterRules.EXPLORATION:
		return _rejected(result, cmd, "combat_already_active")
	if not TurnOrderRules.is_actor_eligible(state.actors[cmd.actor_id]):
		return _rejected(result, cmd, "actor_not_eligible")
	var initiative := InitiativeRules.resolve(state)
	var order: Array[int] = initiative["order"]
	if order.is_empty():
		return _rejected(result, cmd, "no_eligible_actors")
	var first_actor: ActorState = state.actors[order[0]]
	result.events.append(Event.create(&"combat_started", {
		"initiator_actor_id": cmd.actor_id,
		"phase": EncounterRules.COMBAT_STARTING,
	}))
	result.events.append(Event.create(&"initiative_established", {
		"initiative_order": order,
		"initiative_rolls": initiative["entries"],
		"current_turn_index": 0,
		"round_number": 1,
	}))
	result.events.append(Event.create(&"turn_started", {
		"actor_id": first_actor.id,
		"turn_index": 0,
		"round_number": 1,
		"phase": EncounterRules.COMBAT,
		"movement_remaining": first_actor.movement_speed,
		"action_available": true,
		"bonus_action_available": true,
		"reaction_available": true,
		"disengaged": false,
	}))
	result.next_rng_state = initiative["next_rng_state"]
	return result


static func _resolve_end_combat(state: BattleState, cmd: Command, result: ResolutionResult) -> ResolutionResult:
	if not EncounterRules.can_end(state):
		return _rejected(result, cmd, "not_in_combat")
	if state.current_actor_id() != cmd.actor_id:
		return _rejected(result, cmd, "not_current_actor")
	result.events.append(Event.create(&"combat_ending", {"phase": EncounterRules.COMBAT_ENDING}))
	result.events.append(Event.create(&"combat_ended", {
		"phase": EncounterRules.EXPLORATION,
		"initiative_order": [],
		"current_turn_index": 0,
		"round_number": 1,
	}))
	return result


static func _resolve_move(state: BattleState, cmd: Command, nav: NavProvider, result: ResolutionResult) -> ResolutionResult:
	var actor: ActorState = state.actors[cmd.actor_id]
	if not actor.is_alive():
		return _rejected(result, cmd, "actor_not_alive")
	var nav_path := nav.find_path(actor.position, cmd.target_pos)
	if nav_path.is_empty() or not nav.is_reachable(actor.position, cmd.target_pos):
		return _rejected(result, cmd, "unreachable")
	var path := PolylineUtil.with_start(nav_path, actor.position)
	var requested_path_cost := PolylineUtil.length(path)
	if requested_path_cost <= MOVEMENT_EPSILON:
		return _rejected(result, cmd, "no_movement")

	var resolved_path := path
	var movement_cost := requested_path_cost
	var was_clamped := false
	if state.phase == EncounterRules.COMBAT:
		var available_movement := maxf(0.0, actor.movement_remaining)
		if available_movement <= MOVEMENT_EPSILON:
			return _rejected(result, cmd, "no_movement_remaining")
		if requested_path_cost > available_movement + MOVEMENT_EPSILON:
			resolved_path = PolylineUtil.clamp(path, available_movement)
			movement_cost = PolylineUtil.length(resolved_path)
			if resolved_path.size() < 2 or movement_cost <= MOVEMENT_EPSILON:
				return _rejected(result, cmd, "no_movement_remaining")
			was_clamped = true

	var resolved_destination: Vector3 = resolved_path[resolved_path.size() - 1]
	result.events.append(Event.create(&"movement_segment", {
		"actor_id": actor.id,
		"from": actor.position,
		"to": resolved_destination,
		"path": resolved_path,
		"path_cost": movement_cost,
		"requested_path_cost": requested_path_cost,
		"clamped": was_clamped,
	}))
	if state.phase == EncounterRules.COMBAT:
		result.events.append(Event.create(&"movement_spent", {
			"actor_id": actor.id,
			"amount": movement_cost,
			"path_cost": movement_cost,
			"movement_remaining_before": actor.movement_remaining,
			"movement_remaining_after": maxf(0.0, actor.movement_remaining - movement_cost),
		}))
	return result


static func _resolve_attack(state: BattleState, cmd: Command, los: LosProvider, result: ResolutionResult) -> ResolutionResult:
	if not state.actors.has(cmd.target_id):
		return _rejected(result, cmd, "unknown_target")
	var attacker: ActorState = state.actors[cmd.actor_id]
	var target: ActorState = state.actors[cmd.target_id]
	if cmd.target_id == cmd.actor_id or not attacker.is_alive() or not target.is_alive():
		return _rejected(result, cmd, "invalid_target")
	if not attacker.action_available:
		return _rejected(result, cmd, "action_unavailable")
	if attacker.position.distance_to(target.position) > ATTACK_RANGE_METERS:
		return _rejected(result, cmd, "target_out_of_range")
	if not los.has_line_of_sight(attacker.position, target.position):
		return _rejected(result, cmd, "no_line_of_sight")

	var attack_roll := Dice.roll_die(state.rng_state, 20)
	var roll: int = attack_roll["value"]
	var next_rng_state: int = attack_roll["next_rng_state"]
	var critical := roll == 20
	var hit := critical or (roll + attacker.attack_bonus >= target.armor_class)
	result.events.append(Event.create(&"attack_rolled", {
		"actor_id": attacker.id,
		"target_id": target.id,
		"roll": roll,
		"total": roll + attacker.attack_bonus,
		"critical": critical,
		"hit": hit,
		"action_spent": true,
	}))
	if hit:
		var damage_roll := Dice.roll_die(next_rng_state, attacker.damage_die)
		var damage: int = damage_roll["value"] + attacker.damage_modifier
		next_rng_state = damage_roll["next_rng_state"]
		if critical:
			var critical_roll := Dice.roll_die(next_rng_state, attacker.damage_die)
			damage += critical_roll["value"]
			next_rng_state = critical_roll["next_rng_state"]
		damage = max(1, damage)
		result.events.append(Event.create(&"damage_taken", {
			"actor_id": target.id,
			"source_actor_id": attacker.id,
			"amount": damage,
		}))
		if target.hp - damage <= 0:
			result.events.append(Event.create(&"actor_downed", {"actor_id": target.id}))
	result.next_rng_state = next_rng_state
	return result


static func _resolve_end_turn(state: BattleState, cmd: Command, result: ResolutionResult) -> ResolutionResult:
	if state.initiative_order.is_empty() or not TurnOrderRules.is_actor_eligible(state.actors[cmd.actor_id]):
		return _rejected(result, cmd, "no_initiative_order")
	var next_index := TurnOrderRules.next_eligible_index(state, state.current_turn_index)
	if next_index < 0:
		return _rejected(result, cmd, "no_eligible_actors")
	var next_round := state.round_number
	if next_index <= state.current_turn_index:
		next_round += 1
	var next_actor_id := state.initiative_order[next_index]
	var next_actor: ActorState = state.actors[next_actor_id]
	result.events.append(Event.create(&"turn_ended", {"actor_id": cmd.actor_id}))
	result.events.append(Event.create(&"turn_started", {
		"actor_id": next_actor_id,
		"turn_index": next_index,
		"round_number": next_round,
		"phase": EncounterRules.COMBAT,
		"movement_remaining": next_actor.movement_speed,
		"action_available": true,
		"bonus_action_available": true,
		"reaction_available": true,
		"disengaged": false,
	}))
	return result


static func _rejected(result: ResolutionResult, cmd: Command, reason: StringName) -> ResolutionResult:
	result.events.append(Event.create(&"command_rejected", {
		"actor_id": cmd.actor_id,
		"command_type": cmd.type,
		"reason": reason,
	}))
	return result


static func apply(state: BattleState, event: Event) -> void:
	match event.type:
		&"movement_segment":
			var moved_actor: ActorState = state.actors[event.data["actor_id"]]
			moved_actor.position = event.data["to"]
		&"movement_spent":
			var moving_actor: ActorState = state.actors[event.data["actor_id"]]
			moving_actor.movement_remaining = maxf(0.0, moving_actor.movement_remaining - event.data["amount"])
		&"attack_rolled":
			var attacking_actor: ActorState = state.actors[event.data["actor_id"]]
			if event.data["action_spent"]:
				attacking_actor.action_available = false
		&"damage_taken":
			var damaged_actor: ActorState = state.actors[event.data["actor_id"]]
			damaged_actor.hp = max(0, damaged_actor.hp - event.data["amount"])
		&"actor_downed":
			var downed_actor: ActorState = state.actors[event.data["actor_id"]]
			if not downed_actor.conditions.has(&"unconscious"):
				downed_actor.conditions.append(&"unconscious")
		&"combat_started", &"combat_ending":
			state.phase = event.data["phase"]
		&"initiative_established":
			state.initiative_order = _actor_ids(event.data["initiative_order"])
			state.current_turn_index = event.data["current_turn_index"]
			state.round_number = event.data["round_number"]
		&"combat_ended":
			state.phase = event.data["phase"]
			state.initiative_order = _actor_ids(event.data["initiative_order"])
			state.current_turn_index = event.data["current_turn_index"]
			state.round_number = event.data["round_number"]
		&"turn_started":
			if event.data.has("phase"):
				state.phase = event.data["phase"]
			state.current_turn_index = event.data["turn_index"]
			state.round_number = event.data["round_number"]
			var turn_actor: ActorState = state.actors[event.data["actor_id"]]
			turn_actor.movement_remaining = event.data["movement_remaining"]
			turn_actor.action_available = event.data["action_available"]
			turn_actor.bonus_action_available = event.data["bonus_action_available"]
			turn_actor.reaction_available = event.data["reaction_available"]
			turn_actor.disengaged = event.data["disengaged"]


static func _actor_ids(data: Array) -> Array[int]:
	var actor_ids: Array[int] = []
	for actor_id in data:
		actor_ids.append(int(actor_id))
	return actor_ids
