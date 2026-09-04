class_name Resolver
extends RefCounted

## A5 remains a pure command resolver. Movement reactions use a clone solely
## to determine subsequent events; callers change BattleState only via apply.

const ATTACK_RANGE_METERS := 1.5
const THREAT_RANGE_METERS := 1.5
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
		return _resolve_move(state, cmd, nav, los, result)
	if state.phase != EncounterRules.COMBAT:
		return _rejected(result, cmd, "not_in_combat")
	if state.current_actor_id() != cmd.actor_id:
		return _rejected(result, cmd, "not_current_actor")
	match cmd.type:
		&"move": return _resolve_move(state, cmd, nav, los, result)
		&"attack", &"basic_attack": return _resolve_attack(state, cmd, los, result)
		&"dash": return _resolve_dash(state, cmd, result)
		&"disengage": return _resolve_disengage(state, cmd, result)
		&"end_turn": return _resolve_end_turn(state, cmd, result)
		_: return _rejected(result, cmd, "unsupported_command")


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
	result.events.append(Event.create(&"combat_started", {"initiator_actor_id": cmd.actor_id, "phase": EncounterRules.COMBAT_STARTING}))
	result.events.append(Event.create(&"initiative_established", {"initiative_order": order, "initiative_rolls": initiative["entries"], "current_turn_index": 0, "round_number": 1}))
	result.events.append(_turn_started_event(first_actor, 0, 1))
	result.next_rng_state = initiative["next_rng_state"]
	return result


static func _resolve_end_combat(state: BattleState, cmd: Command, result: ResolutionResult) -> ResolutionResult:
	if not EncounterRules.can_end(state):
		return _rejected(result, cmd, "not_in_combat")
	if state.current_actor_id() != cmd.actor_id:
		return _rejected(result, cmd, "not_current_actor")
	result.events.append(Event.create(&"combat_ending", {"phase": EncounterRules.COMBAT_ENDING}))
	result.events.append(Event.create(&"combat_ended", {"phase": EncounterRules.EXPLORATION, "initiative_order": [], "current_turn_index": 0, "round_number": 1}))
	return result


static func _resolve_move(state: BattleState, cmd: Command, nav: NavProvider, los: LosProvider, result: ResolutionResult) -> ResolutionResult:
	var actor: ActorState = state.actors[cmd.actor_id]
	if not actor.is_conscious():
		return _rejected(result, cmd, "actor_cannot_act")
	var nav_path := nav.find_path(actor.position, cmd.target_pos)
	if nav_path.is_empty() or not nav.is_reachable(actor.position, cmd.target_pos):
		return _rejected(result, cmd, "unreachable")
	var path := PolylineUtil.with_start(nav_path, actor.position)
	var requested_path_cost := PolylineUtil.length(path)
	if requested_path_cost <= MOVEMENT_EPSILON:
		return _rejected(result, cmd, "no_movement")
	if state.phase == EncounterRules.EXPLORATION:
		_append_movement_event(result, actor.id, actor.position, path, requested_path_cost, requested_path_cost, false)
		return result

	var working := state.clone()
	var working_actor: ActorState = working.actors[cmd.actor_id]
	if working_actor.is_prone():
		var stand_cost := working_actor.movement_speed * 0.5
		if working_actor.movement_remaining + MOVEMENT_EPSILON < stand_cost:
			return _rejected(result, cmd, "insufficient_movement_to_stand")
		_append_and_apply(result, working, Event.create(&"condition_removed", {"actor_id": working_actor.id, "condition": &"prone"}))
		_append_movement_spent(result, working, working_actor.id, stand_cost)

	var available := maxf(0.0, (working.actors[cmd.actor_id] as ActorState).movement_remaining)
	if available <= MOVEMENT_EPSILON:
		return _rejected(result, cmd, "no_movement_remaining")
	var resolved_path := path
	var movement_cost := requested_path_cost
	var was_clamped := false
	if requested_path_cost > available + MOVEMENT_EPSILON:
		resolved_path = PolylineUtil.clamp(path, available)
		movement_cost = PolylineUtil.length(resolved_path)
		if resolved_path.size() < 2 or movement_cost <= MOVEMENT_EPSILON:
			return _rejected(result, cmd, "no_movement_remaining")
		was_clamped = true

	var traversed := 0.0
	while traversed + MOVEMENT_EPSILON < movement_cost and (working.actors[cmd.actor_id] as ActorState).is_alive():
		var remaining_path := _path_from_distance(resolved_path, traversed)
		var remaining_cost := PolylineUtil.length(remaining_path)
		var reaction := _next_opportunity_reaction(working, cmd.actor_id, remaining_path, los)
		var segment_cost := remaining_cost if reaction.is_empty() else float(reaction["distance"])
		if segment_cost > MOVEMENT_EPSILON:
			var segment_path := PolylineUtil.clamp(remaining_path, segment_cost)
			_append_movement_event(result, cmd.actor_id, (working.actors[cmd.actor_id] as ActorState).position, segment_path, segment_cost, requested_path_cost, was_clamped)
			# Apply only to the private working clone so following reactions see the
			# exact authoritative boundary position.
			apply(working, result.events.back())
			_append_movement_spent(result, working, cmd.actor_id, segment_cost)
			traversed += segment_cost
		if reaction.is_empty():
			break
		var reactor_id := int(reaction["actor_id"])
		var reactor: ActorState = working.actors[reactor_id]
		var mover: ActorState = working.actors[cmd.actor_id]
		_append_and_apply(result, working, Event.create(&"reaction_triggered", {"actor_id": reactor_id, "target_id": mover.id, "reaction": &"opportunity_attack"}))
		_resolve_attack_between(working, reactor, mover, los, result, false, true, &"opportunity")
		if not (working.actors[cmd.actor_id] as ActorState).is_alive():
			break
		# Remaining enemies at this same boundary have distance zero; their spent
		# reaction is filtered, so each other eligible enemy resolves once.
	return result


static func _resolve_dash(state: BattleState, cmd: Command, result: ResolutionResult) -> ResolutionResult:
	var actor: ActorState = state.actors[cmd.actor_id]
	if not actor.is_conscious(): return _rejected(result, cmd, "actor_cannot_act")
	if not actor.action_available: return _rejected(result, cmd, "action_unavailable")
	result.events.append(Event.create(&"action_spent", {"actor_id": actor.id, "action": &"dash"}))
	result.events.append(Event.create(&"movement_gained", {"actor_id": actor.id, "amount": actor.movement_speed, "movement_remaining_before": actor.movement_remaining, "movement_remaining_after": actor.movement_remaining + actor.movement_speed}))
	return result


static func _resolve_disengage(state: BattleState, cmd: Command, result: ResolutionResult) -> ResolutionResult:
	var actor: ActorState = state.actors[cmd.actor_id]
	if not actor.is_conscious(): return _rejected(result, cmd, "actor_cannot_act")
	if not actor.action_available: return _rejected(result, cmd, "action_unavailable")
	result.events.append(Event.create(&"action_spent", {"actor_id": actor.id, "action": &"disengage"}))
	result.events.append(Event.create(&"disengage_applied", {"actor_id": actor.id}))
	return result


static func _resolve_attack(state: BattleState, cmd: Command, los: LosProvider, result: ResolutionResult) -> ResolutionResult:
	if not state.actors.has(cmd.target_id): return _rejected(result, cmd, "unknown_target")
	var attacker: ActorState = state.actors[cmd.actor_id]
	var target: ActorState = state.actors[cmd.target_id]
	if cmd.target_id == cmd.actor_id or attacker.side == target.side or not attacker.is_conscious() or not target.is_alive():
		return _rejected(result, cmd, "invalid_target")
	if not attacker.action_available: return _rejected(result, cmd, "action_unavailable")
	if not los.has_line_of_sight(attacker.position, target.position): return _rejected(result, cmd, "no_line_of_sight")
	var attack_range := maxf(ATTACK_RANGE_METERS, float(cmd.metadata.get("range_meters", ATTACK_RANGE_METERS)))
	var is_ranged := bool(cmd.metadata.get("is_ranged", false))
	if attacker.position.distance_to(target.position) > attack_range + MOVEMENT_EPSILON:
		return _rejected(result, cmd, "target_out_of_range")
	var working := state.clone()
	_resolve_attack_between(working, working.actors[attacker.id], working.actors[target.id], los, result, true, false, &"basic", attack_range, is_ranged)
	return result


static func _resolve_attack_between(working: BattleState, attacker: ActorState, target: ActorState, los: LosProvider, result: ResolutionResult, spends_action: bool, spends_reaction: bool, attack_kind: StringName, attack_range: float = ATTACK_RANGE_METERS, is_ranged: bool = false) -> void:
	if not los.has_line_of_sight(attacker.position, target.position) or attacker.position.distance_to(target.position) > attack_range + MOVEMENT_EPSILON:
		return
	var roll_result := _roll_attack_d20(working.rng_state, attacker, target, is_ranged)
	var roll: int = roll_result["roll"]
	var critical := roll == 20
	var hit := roll != 1 and (critical or (roll + attacker.attack_bonus >= target.armor_class))
	_append_and_apply(result, working, Event.create(&"attack_rolled", {
		"actor_id": attacker.id, "target_id": target.id, "attack_kind": attack_kind,
		"roll": roll, "rolls": roll_result["rolls"], "total": roll + attacker.attack_bonus,
		"critical": critical, "hit": hit, "advantage": roll_result["advantage"], "disadvantage": roll_result["disadvantage"], "is_ranged": is_ranged,
		"action_spent": spends_action, "reaction_spent": spends_reaction,
	}))
	working.rng_state = roll_result["next_rng_state"]
	if hit:
		var damage_roll := Dice.roll_die(working.rng_state, attacker.damage_die)
		var damage: int = int(damage_roll["value"]) + attacker.damage_modifier
		working.rng_state = damage_roll["next_rng_state"]
		if critical:
			var critical_roll := Dice.roll_die(working.rng_state, attacker.damage_die)
			damage += int(critical_roll["value"])
			working.rng_state = critical_roll["next_rng_state"]
		damage = max(1, damage)
		var hp_before := target.hp
		_append_and_apply(result, working, Event.create(&"damage_taken", {"actor_id": target.id, "source_actor_id": attacker.id, "amount": damage}))
		if hp_before - damage <= -target.max_hp:
			_append_and_apply(result, working, Event.create(&"actor_died", {"actor_id": target.id}))
		elif hp_before - damage <= 0:
			_append_and_apply(result, working, Event.create(&"actor_downed", {"actor_id": target.id}))
	result.next_rng_state = working.rng_state


static func _roll_attack_d20(rng_state: int, attacker: ActorState, target: ActorState, is_ranged: bool) -> Dictionary:
	var target_is_close := attacker.position.distance_to(target.position) <= ATTACK_RANGE_METERS + MOVEMENT_EPSILON
	var advantage := not is_ranged and target.is_prone() and target_is_close
	var disadvantage := attacker.conditions.has(&"poisoned") or (is_ranged and target.is_prone() and not target_is_close)
	if advantage and disadvantage:
		advantage = false
		disadvantage = false
	var first_roll := Dice.roll_die(rng_state, 20)
	var rolls: Array[int] = [int(first_roll["value"])]
	var next_rng_state: int = first_roll["next_rng_state"]
	var selected_roll: int = rolls[0]
	if advantage or disadvantage:
		var second_roll := Dice.roll_die(next_rng_state, 20)
		rolls.append(int(second_roll["value"]))
		next_rng_state = second_roll["next_rng_state"]
		selected_roll = maxi(rolls[0], rolls[1]) if advantage else mini(rolls[0], rolls[1])
	return {"roll": selected_roll, "rolls": rolls, "next_rng_state": next_rng_state, "advantage": advantage, "disadvantage": disadvantage}


static func _resolve_end_turn(state: BattleState, cmd: Command, result: ResolutionResult) -> ResolutionResult:
	if state.initiative_order.is_empty(): return _rejected(result, cmd, "no_initiative_order")
	var next_index := TurnOrderRules.next_eligible_index(state, state.current_turn_index)
	if next_index < 0: return _rejected(result, cmd, "no_eligible_actors")
	var next_round := state.round_number + (1 if next_index <= state.current_turn_index else 0)
	var next_actor: ActorState = state.actors[state.initiative_order[next_index]]
	result.events.append(Event.create(&"turn_ended", {"actor_id": cmd.actor_id}))
	result.events.append(_turn_started_event(next_actor, next_index, next_round))
	return result


static func _turn_started_event(actor: ActorState, turn_index: int, round_number: int) -> Event:
	return Event.create(&"turn_started", {"actor_id": actor.id, "turn_index": turn_index, "round_number": round_number, "phase": EncounterRules.COMBAT, "movement_remaining": actor.movement_speed, "action_available": true, "bonus_action_available": true, "reaction_available": true, "disengaged": false})


static func _next_opportunity_reaction(state: BattleState, mover_id: int, path: PackedVector3Array, los: LosProvider) -> Dictionary:
	var mover: ActorState = state.actors[mover_id]
	if mover.disengaged: return {}
	var candidate: Dictionary = {}
	var actor_ids: Array = state.actors.keys()
	actor_ids.sort()
	for actor_id_variant in actor_ids:
		var enemy: ActorState = state.actors[actor_id_variant]
		if enemy.id == mover.id or enemy.side == mover.side or not enemy.is_conscious() or not enemy.reaction_available: continue
		if not los.has_line_of_sight(enemy.position, mover.position): continue
		var exit_distance := _threat_exit_distance(path, enemy.position)
		if exit_distance < -MOVEMENT_EPSILON: continue
		if candidate.is_empty() or exit_distance < float(candidate["distance"]) - MOVEMENT_EPSILON or (is_equal_approx(exit_distance, float(candidate["distance"])) and enemy.id < int(candidate["actor_id"])):
			candidate = {"actor_id": enemy.id, "distance": maxf(0.0, exit_distance)}
	return candidate


static func _threat_exit_distance(path: PackedVector3Array, threat_position: Vector3) -> float:
	if path.size() < 2 or path[0].distance_to(threat_position) > THREAT_RANGE_METERS + MOVEMENT_EPSILON: return -1.0
	var traversed := 0.0
	for index in range(1, path.size()):
		var start := path[index - 1]
		var end := path[index]
		var length := start.distance_to(end)
		if length <= MOVEMENT_EPSILON: continue
		if end.distance_to(threat_position) > THREAT_RANGE_METERS + MOVEMENT_EPSILON:
			return traversed + length * _circle_exit_ratio(start, end, threat_position, THREAT_RANGE_METERS)
		traversed += length
	return -1.0


static func _circle_exit_ratio(start: Vector3, end: Vector3, center: Vector3, radius: float) -> float:
	var offset := start - center
	var direction := end - start
	var a := direction.dot(direction)
	if a <= MOVEMENT_EPSILON: return 0.0
	var b := 2.0 * offset.dot(direction)
	var c := offset.dot(offset) - radius * radius
	return clampf((-b + sqrt(maxf(0.0, b * b - 4.0 * a * c))) / (2.0 * a), 0.0, 1.0)


static func _path_from_distance(path: PackedVector3Array, distance: float) -> PackedVector3Array:
	if distance <= MOVEMENT_EPSILON: return path.duplicate()
	var consumed := 0.0
	for index in range(1, path.size()):
		var start := path[index - 1]
		var end := path[index]
		var length := start.distance_to(end)
		if consumed + length + MOVEMENT_EPSILON >= distance:
			var ratio := 0.0 if length <= MOVEMENT_EPSILON else (distance - consumed) / length
			var remaining := PackedVector3Array([start.lerp(end, clampf(ratio, 0.0, 1.0))])
			for tail_index in range(index, path.size()): remaining.append(path[tail_index])
			return remaining
		consumed += length
	return PackedVector3Array()


static func _append_movement_event(result: ResolutionResult, actor_id: int, from: Vector3, path: PackedVector3Array, path_cost: float, requested_path_cost: float, was_clamped: bool) -> void:
	result.events.append(Event.create(&"movement_segment", {"actor_id": actor_id, "from": from, "to": path[path.size() - 1], "path": path, "path_cost": path_cost, "requested_path_cost": requested_path_cost, "clamped": was_clamped}))


static func _append_movement_spent(result: ResolutionResult, working: BattleState, actor_id: int, amount: float) -> void:
	var actor: ActorState = working.actors[actor_id]
	_append_and_apply(result, working, Event.create(&"movement_spent", {"actor_id": actor_id, "amount": amount, "path_cost": amount, "movement_remaining_before": actor.movement_remaining, "movement_remaining_after": maxf(0.0, actor.movement_remaining - amount)}))


static func _append_and_apply(result: ResolutionResult, working: BattleState, event: Event) -> void:
	result.events.append(event)
	apply(working, event)


static func _rejected(result: ResolutionResult, cmd: Command, reason: StringName) -> ResolutionResult:
	result.events.append(Event.create(&"command_rejected", {"actor_id": cmd.actor_id, "command_type": cmd.type, "reason": reason}))
	return result


static func apply(state: BattleState, event: Event) -> void:
	match event.type:
		&"movement_segment": (state.actors[event.data["actor_id"]] as ActorState).position = event.data["to"]
		&"movement_spent":
			var moving_actor: ActorState = state.actors[event.data["actor_id"]]
			moving_actor.movement_remaining = maxf(0.0, moving_actor.movement_remaining - event.data["amount"])
		&"movement_gained": (state.actors[event.data["actor_id"]] as ActorState).movement_remaining += event.data["amount"]
		&"action_spent": (state.actors[event.data["actor_id"]] as ActorState).action_available = false
		&"disengage_applied": (state.actors[event.data["actor_id"]] as ActorState).disengaged = true
		&"reaction_triggered": (state.actors[event.data["actor_id"]] as ActorState).reaction_available = false
		&"attack_rolled":
			var attacking_actor: ActorState = state.actors[event.data["actor_id"]]
			if event.data["action_spent"]: attacking_actor.action_available = false
			if event.data.get("reaction_spent", false): attacking_actor.reaction_available = false
		&"damage_taken": (state.actors[event.data["actor_id"]] as ActorState).hp = max(0, (state.actors[event.data["actor_id"]] as ActorState).hp - event.data["amount"])
		&"actor_downed":
			var downed_actor: ActorState = state.actors[event.data["actor_id"]]
			if not downed_actor.conditions.has(&"unconscious"): downed_actor.conditions.append(&"unconscious")
		&"actor_died":
			var dead_actor: ActorState = state.actors[event.data["actor_id"]]
			dead_actor.hp = 0
			if not dead_actor.conditions.has(&"dead"): dead_actor.conditions.append(&"dead")
		&"condition_added":
			var conditioned_actor: ActorState = state.actors[event.data["actor_id"]]
			var added := StringName(str(event.data["condition"]))
			if not conditioned_actor.conditions.has(added): conditioned_actor.conditions.append(added)
		&"condition_removed": (state.actors[event.data["actor_id"]] as ActorState).conditions.erase(StringName(str(event.data["condition"])))
		&"combat_started", &"combat_ending": state.phase = event.data["phase"]
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
			if event.data.has("phase"): state.phase = event.data["phase"]
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
	for actor_id in data: actor_ids.append(int(actor_id))
	return actor_ids
