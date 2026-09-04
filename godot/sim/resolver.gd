class_name Resolver
extends RefCounted

const ATTACK_RANGE_METERS := 1.5


static func resolve(state: BattleState, cmd: Command, nav: NavProvider, los: LosProvider) -> ResolutionResult:
	var result := ResolutionResult.new()
	result.next_rng_state = state.rng_state

	if not state.actors.has(cmd.actor_id):
		return _rejected(result, cmd, "unknown_actor")
	if state.phase != &"combat":
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


static func _resolve_move(state: BattleState, cmd: Command, nav: NavProvider, result: ResolutionResult) -> ResolutionResult:
	var actor: ActorState = state.actors[cmd.actor_id]
	if not actor.is_alive():
		return _rejected(result, cmd, "actor_not_alive")
	var path := nav.find_path(actor.position, cmd.target_pos)
	if path.is_empty() or not nav.is_reachable(actor.position, cmd.target_pos):
		return _rejected(result, cmd, "unreachable")
	var cost := nav.path_cost(path)
	if cost > actor.movement_remaining + 0.0001:
		return _rejected(result, cmd, "insufficient_movement")
	result.events.append(Event.create(&"movement_segment", {
		"actor_id": actor.id,
		"from": actor.position,
		"to": cmd.target_pos,
		"path": path,
	}))
	result.events.append(Event.create(&"movement_spent", {
		"actor_id": actor.id,
		"amount": cost,
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
	if state.initiative_order.is_empty():
		return _rejected(result, cmd, "no_initiative_order")
	var next_index := (state.current_turn_index + 1) % state.initiative_order.size()
	var next_round := state.round_number
	if next_index == 0:
		next_round += 1
	var next_actor_id := state.initiative_order[next_index]
	var next_actor: ActorState = state.actors[next_actor_id]
	result.events.append(Event.create(&"turn_ended", {"actor_id": cmd.actor_id}))
	result.events.append(Event.create(&"turn_started", {
		"actor_id": next_actor_id,
		"turn_index": next_index,
		"round_number": next_round,
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
		&"turn_started":
			state.current_turn_index = event.data["turn_index"]
			state.round_number = event.data["round_number"]
			var turn_actor: ActorState = state.actors[event.data["actor_id"]]
			turn_actor.movement_remaining = event.data["movement_remaining"]
			turn_actor.action_available = event.data["action_available"]
			turn_actor.bonus_action_available = event.data["bonus_action_available"]
			turn_actor.reaction_available = event.data["reaction_available"]
			turn_actor.disengaged = event.data["disengaged"]

