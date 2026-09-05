class_name Resolver
extends RefCounted

## A5 remains a pure command resolver. Movement reactions use a clone solely
## to determine subsequent events; callers change BattleState only via apply.

## Bumped whenever resolution/rule semantics change in a way that could alter
## outcomes for the same state+command, so saves and replay logs (A8) can
## detect an incompatible resolver instead of silently reinterpreting old
## commands/state under new rules.
## Fase C2 bump: attack/armor calculations now aggregate equipment, and a
## perform_attack-effect ability checks/spends its full ability cost
## (bonus_action/reaction/movement_cost), not only costs_action.
const RULES_VERSION: int = 2

const ATTACK_RANGE_METERS := 1.5
const THREAT_RANGE_METERS := 1.5
const MOVEMENT_EPSILON := 0.0001
const PolylineUtil = preload("res://sim/polyline.gd")
const EncounterRules = preload("res://sim/rules/encounter.gd")
const InitiativeRules = preload("res://sim/rules/initiative.gd")
const TurnOrderRules = preload("res://sim/rules/turn_order.gd")
const RejectionReasonRules = preload("res://sim/rules/rejection_reason.gd")
const AbilityRoutingRules = preload("res://sim/rules/ability_routing.gd")
const CommandPhaseRulesScript = preload("res://sim/rules/command_phase_rules.gd")
const AbilityCostRulesScript = preload("res://sim/rules/ability_cost_rules.gd")
const EquipmentRules = preload("res://sim/equipment.gd")

const EFFECT_ADD_BASE_MOVEMENT := &"add_base_movement"
const EFFECT_APPLY_CONDITION := &"apply_condition"
const EFFECT_REMOVE_CONDITION := &"remove_condition"
const EFFECT_APPLY_DISENGAGE := &"apply_disengage"
const EFFECT_PERFORM_ATTACK := &"perform_attack"

const INTERACT_RANGE_EPSILON := 0.0001

## Interactable type -> {current state: next state}. Small and fixed for V1
## (door/chest/lever, per implementation_plan.md Fase A9); Resolver reads
## InteractableState.type generically instead of branching on instance id, the
## same way ability effects avoid branching on ability id.
const INTERACTABLE_TRANSITIONS := {
	&"door": {&"closed": &"open", &"open": &"closed"},
	&"chest": {&"closed": &"open"},
	&"lever": {&"off": &"on", &"on": &"off"},
}


static func resolve(state: BattleState, cmd: Command, nav: NavProvider, los: LosProvider, defs: DefinitionLibrary = null) -> ResolutionResult:
	var definitions := defs if defs != null else DefinitionLibrary.get_default()
	var result := ResolutionResult.new()
	result.next_rng_state = state.rng_state
	if not state.actors.has(cmd.actor_id):
		return _rejected(result, cmd, RejectionReasonRules.UNKNOWN_ACTOR)
	if cmd.type == &"start_combat":
		return _resolve_start_combat(state, cmd, result)
	if cmd.type == &"end_combat":
		return _resolve_end_combat(state, cmd, result)
	if cmd.type == &"move" and state.phase == EncounterRules.EXPLORATION:
		return _resolve_move(state, cmd, nav, los, definitions, result)
	if cmd.type == &"interact" and state.phase == EncounterRules.EXPLORATION:
		return _resolve_interact(state, cmd, result, false)
	var phase_rejection := CommandPhaseRulesScript.rejection_for_combat_turn(state, cmd.actor_id)
	if phase_rejection != &"":
		return _rejected(result, cmd, phase_rejection)
	if cmd.type == &"move":
		return _resolve_move(state, cmd, nav, los, definitions, result)
	if cmd.type == &"interact":
		return _resolve_interact(state, cmd, result, true)
	if cmd.type == &"end_turn":
		return _resolve_end_turn(state, cmd, result)
	if AbilityRoutingRules.is_ability_command(cmd.type):
		return _resolve_ability_command(state, cmd, los, definitions, result, AbilityRoutingRules.ability_id_for_command(cmd.type))
	return _rejected(result, cmd, RejectionReasonRules.UNSUPPORTED_COMMAND)


static func _resolve_start_combat(state: BattleState, cmd: Command, result: ResolutionResult) -> ResolutionResult:
	if state.phase != EncounterRules.EXPLORATION:
		return _rejected(result, cmd, RejectionReasonRules.COMBAT_ALREADY_ACTIVE)
	if not TurnOrderRules.is_actor_eligible(state.actors[cmd.actor_id]):
		return _rejected(result, cmd, RejectionReasonRules.ACTOR_NOT_ELIGIBLE)
	var initiative := InitiativeRules.resolve(state)
	var order: Array[int] = initiative["order"]
	if order.is_empty():
		return _rejected(result, cmd, RejectionReasonRules.NO_ELIGIBLE_ACTORS)
	var first_actor: ActorState = state.actors[order[0]]
	result.events.append(Event.create(&"combat_started", {"initiator_actor_id": cmd.actor_id, "phase": EncounterRules.COMBAT_STARTING}))
	result.events.append(Event.create(&"initiative_established", {"initiative_order": order, "initiative_rolls": initiative["entries"], "current_turn_index": 0, "round_number": 1}))
	result.events.append(_turn_started_event(first_actor, 0, 1))
	result.next_rng_state = initiative["next_rng_state"]
	return result


static func _resolve_end_combat(state: BattleState, cmd: Command, result: ResolutionResult) -> ResolutionResult:
	if not EncounterRules.can_end(state):
		return _rejected(result, cmd, RejectionReasonRules.NOT_IN_COMBAT)
	if state.current_actor_id() != cmd.actor_id:
		return _rejected(result, cmd, RejectionReasonRules.NOT_CURRENT_ACTOR)
	result.events.append(Event.create(&"combat_ending", {"phase": EncounterRules.COMBAT_ENDING}))
	result.events.append(Event.create(&"combat_ended", {"phase": EncounterRules.EXPLORATION, "initiative_order": [], "current_turn_index": 0, "round_number": 1}))
	return result


static func _resolve_move(state: BattleState, cmd: Command, nav: NavProvider, los: LosProvider, definitions: DefinitionLibrary, result: ResolutionResult) -> ResolutionResult:
	var actor: ActorState = state.actors[cmd.actor_id]
	var conscious_rejection := CommandPhaseRulesScript.rejection_for_conscious(actor)
	if conscious_rejection != &"":
		return _rejected(result, cmd, conscious_rejection)
	var nav_path := nav.find_path(actor.position, cmd.target_pos)
	if nav_path.is_empty() or not nav.is_reachable(actor.position, cmd.target_pos):
		return _rejected(result, cmd, RejectionReasonRules.UNREACHABLE)
	var path := PolylineUtil.with_start(nav_path, actor.position)
	var requested_path_cost := PolylineUtil.length(path)
	if requested_path_cost <= MOVEMENT_EPSILON:
		return _rejected(result, cmd, RejectionReasonRules.NO_MOVEMENT)
	if state.phase == EncounterRules.EXPLORATION:
		_append_movement_event(result, actor.id, actor.position, path, requested_path_cost, requested_path_cost, false)
		return result

	var working := state.clone()
	var working_actor: ActorState = working.actors[cmd.actor_id]
	var standing_condition := _condition_requiring_stand(working_actor, definitions)
	if standing_condition != &"":
		var stand_cost := working_actor.movement_speed * 0.5
		if working_actor.movement_remaining + MOVEMENT_EPSILON < stand_cost:
			return _rejected(result, cmd, RejectionReasonRules.INSUFFICIENT_MOVEMENT_TO_STAND)
		_append_and_apply(result, working, Event.create(&"condition_removed", {"actor_id": working_actor.id, "condition": standing_condition}))
		_append_movement_spent(result, working, working_actor.id, stand_cost)

	var available := maxf(0.0, (working.actors[cmd.actor_id] as ActorState).movement_remaining)
	if available <= MOVEMENT_EPSILON:
		return _rejected(result, cmd, RejectionReasonRules.NO_MOVEMENT_REMAINING)
	var resolved_path := path
	var movement_cost := requested_path_cost
	var was_clamped := false
	if requested_path_cost > available + MOVEMENT_EPSILON:
		resolved_path = PolylineUtil.clamp(path, available)
		movement_cost = PolylineUtil.length(resolved_path)
		if resolved_path.size() < 2 or movement_cost <= MOVEMENT_EPSILON:
			return _rejected(result, cmd, RejectionReasonRules.NO_MOVEMENT_REMAINING)
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
		_resolve_attack_between(working, reactor, mover, los, definitions, result, false, true, &"opportunity")
		if not (working.actors[cmd.actor_id] as ActorState).is_alive():
			break
		# Remaining enemies at this same boundary have distance zero; their spent
		# reaction is filtered, so each other eligible enemy resolves once.
	return result


## exploration -> free (costs_action false); combat -> costs the actor's
## action, per implementation_plan.md Fase A9 "Combat: interaction cost".
static func _resolve_interact(state: BattleState, cmd: Command, result: ResolutionResult, costs_action: bool) -> ResolutionResult:
	var actor: ActorState = state.actors[cmd.actor_id]
	var conscious_rejection := CommandPhaseRulesScript.rejection_for_conscious(actor)
	if conscious_rejection != &"":
		return _rejected(result, cmd, conscious_rejection)
	if not state.interactables.has(cmd.target_interactable_id):
		return _rejected(result, cmd, RejectionReasonRules.UNKNOWN_INTERACTABLE)
	var interactable: InteractableState = state.interactables[cmd.target_interactable_id]
	if actor.position.distance_to(interactable.position) > interactable.interact_range + INTERACT_RANGE_EPSILON:
		return _rejected(result, cmd, RejectionReasonRules.OUT_OF_RANGE)
	if costs_action and not actor.action_available:
		return _rejected(result, cmd, RejectionReasonRules.ACTION_UNAVAILABLE)
	var transitions: Dictionary = INTERACTABLE_TRANSITIONS.get(interactable.type, {})
	var next_state: StringName = transitions.get(interactable.state, &"")
	if next_state == &"":
		return _rejected(result, cmd, RejectionReasonRules.INVALID_INTERACTABLE_STATE)
	if costs_action:
		result.events.append(Event.create(&"action_spent", {"actor_id": actor.id, "action": &"interact"}))
	result.events.append(Event.create(&"interaction_completed", {
		"actor_id": actor.id,
		"interactable_id": interactable.id,
		"interactable_type": interactable.type,
		"previous_state": interactable.state,
		"new_state": next_state,
	}))
	return result


static func _resolve_ability_command(state: BattleState, cmd: Command, los: LosProvider, definitions: DefinitionLibrary, result: ResolutionResult, ability_id: StringName) -> ResolutionResult:
	var actor: ActorState = state.actors[cmd.actor_id]
	var conscious_rejection := CommandPhaseRulesScript.rejection_for_conscious(actor)
	if conscious_rejection != &"": return _rejected(result, cmd, conscious_rejection)
	var ability := definitions.get_ability(ability_id)
	if ability == null: return _rejected(result, cmd, RejectionReasonRules.UNKNOWN_ABILITY_DEFINITION)
	for effect in ability.effects:
		if effect.type == EFFECT_PERFORM_ATTACK:
			return _resolve_attack_effect(state, cmd, ability, effect, los, definitions, result)
	var cost_rejection := AbilityCostRulesScript.rejection_for_cost(actor, ability)
	if cost_rejection != &"": return _rejected(result, cmd, cost_rejection)
	_spend_ability_cost(result, actor, ability)
	for effect in ability.effects:
		_apply_generic_effect(result, actor, effect)
	return result


static func _spend_ability_cost(result: ResolutionResult, actor: ActorState, ability: AbilityDefinition, include_action: bool = true, include_reaction: bool = true) -> void:
	if include_action and ability.costs_action:
		result.events.append(Event.create(&"action_spent", {"actor_id": actor.id, "action": ability.id}))
	if ability.costs_bonus_action:
		result.events.append(Event.create(&"bonus_action_spent", {"actor_id": actor.id, "action": ability.id}))
	if include_reaction and ability.costs_reaction:
		result.events.append(Event.create(&"reaction_triggered", {"actor_id": actor.id, "target_id": -1, "reaction": ability.id}))
	if ability.movement_cost > 0.0:
		result.events.append(Event.create(&"movement_spent", {
			"actor_id": actor.id, "amount": ability.movement_cost, "path_cost": ability.movement_cost,
			"movement_remaining_before": actor.movement_remaining,
			"movement_remaining_after": maxf(0.0, actor.movement_remaining - ability.movement_cost),
		}))


static func _apply_generic_effect(result: ResolutionResult, actor: ActorState, effect: AbilityEffect) -> void:
	match effect.type:
		EFFECT_ADD_BASE_MOVEMENT:
			var amount := actor.movement_speed * effect.multiplier
			result.events.append(Event.create(&"movement_gained", {"actor_id": actor.id, "amount": amount, "movement_remaining_before": actor.movement_remaining, "movement_remaining_after": actor.movement_remaining + amount}))
		EFFECT_APPLY_DISENGAGE:
			result.events.append(Event.create(&"disengage_applied", {"actor_id": actor.id}))
		EFFECT_APPLY_CONDITION:
			result.events.append(Event.create(&"condition_added", {"actor_id": actor.id, "condition": effect.condition_id}))
		EFFECT_REMOVE_CONDITION:
			result.events.append(Event.create(&"condition_removed", {"actor_id": actor.id, "condition": effect.condition_id}))
		_:
			push_error("Unknown ability effect type: %s" % effect.type)


static func _resolve_attack_effect(state: BattleState, cmd: Command, ability: AbilityDefinition, effect: AbilityEffect, los: LosProvider, definitions: DefinitionLibrary, result: ResolutionResult) -> ResolutionResult:
	if not state.actors.has(cmd.target_id): return _rejected(result, cmd, RejectionReasonRules.UNKNOWN_TARGET)
	var attacker: ActorState = state.actors[cmd.actor_id]
	var target: ActorState = state.actors[cmd.target_id]
	if cmd.target_id == cmd.actor_id or attacker.side == target.side or not attacker.is_conscious() or not target.is_alive():
		return _rejected(result, cmd, RejectionReasonRules.INVALID_TARGET)
	# Same shared cost gate _resolve_ability_command uses, so a perform_attack
	# effect ability that declares costs_bonus_action/costs_reaction/
	# movement_cost is rejected on an unaffordable one instead of only ever
	# checking costs_action.
	var cost_rejection := AbilityCostRulesScript.rejection_for_cost(attacker, ability)
	if cost_rejection != &"": return _rejected(result, cmd, cost_rejection)
	if not los.has_line_of_sight(attacker.position, target.position): return _rejected(result, cmd, RejectionReasonRules.NO_LINE_OF_SIGHT)
	var attack_range := maxf(effect.range_meters, float(cmd.metadata.get("range_meters", effect.range_meters)))
	var is_ranged := bool(cmd.metadata.get("is_ranged", effect.is_ranged))
	if attacker.position.distance_to(target.position) > attack_range + MOVEMENT_EPSILON:
		return _rejected(result, cmd, RejectionReasonRules.TARGET_OUT_OF_RANGE)
	# Action/reaction spending for this ability is carried by attack_rolled's
	# action_spent/reaction_spent flags below; only bonus_action/movement need
	# a distinct event here.
	_spend_ability_cost(result, attacker, ability, false, false)
	var working := state.clone()
	_resolve_attack_between(working, working.actors[attacker.id], working.actors[target.id], los, definitions, result, ability.costs_action, ability.costs_reaction, effect.attack_kind, attack_range, is_ranged)
	return result


static func _resolve_attack_between(working: BattleState, attacker: ActorState, target: ActorState, los: LosProvider, definitions: DefinitionLibrary, result: ResolutionResult, spends_action: bool, spends_reaction: bool, attack_kind: StringName, attack_range: float = ATTACK_RANGE_METERS, is_ranged: bool = false) -> void:
	if not los.has_line_of_sight(attacker.position, target.position) or attacker.position.distance_to(target.position) > attack_range + MOVEMENT_EPSILON:
		return
	var attack_bonus := EquipmentRules.aggregate_attack_bonus(attacker, definitions)
	var armor_class := EquipmentRules.aggregate_armor_class(target, definitions)
	var roll_result := _roll_attack_d20(working.rng_state, attacker, target, is_ranged, definitions)
	var roll: int = roll_result["roll"]
	var critical := roll == 20
	var hit := roll != 1 and (critical or (roll + attack_bonus >= armor_class))
	_append_and_apply(result, working, Event.create(&"attack_rolled", {
		"actor_id": attacker.id, "target_id": target.id, "attack_kind": attack_kind,
		"roll": roll, "rolls": roll_result["rolls"], "total": roll + attack_bonus,
		"critical": critical, "hit": hit, "advantage": roll_result["advantage"], "disadvantage": roll_result["disadvantage"], "is_ranged": is_ranged,
		"action_spent": spends_action, "reaction_spent": spends_reaction,
	}))
	working.rng_state = roll_result["next_rng_state"]
	if hit:
		var damage_die := EquipmentRules.aggregate_damage_die(attacker, definitions)
		var damage_modifier := EquipmentRules.aggregate_damage_modifier(attacker, definitions)
		var damage_roll := Dice.roll_die(working.rng_state, damage_die)
		var damage: int = int(damage_roll["value"]) + damage_modifier
		working.rng_state = damage_roll["next_rng_state"]
		if critical:
			var critical_roll := Dice.roll_die(working.rng_state, damage_die)
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


static func _roll_attack_d20(rng_state: int, attacker: ActorState, target: ActorState, is_ranged: bool, definitions: DefinitionLibrary) -> Dictionary:
	var target_is_close := attacker.position.distance_to(target.position) <= ATTACK_RANGE_METERS + MOVEMENT_EPSILON
	var attacker_flags := _condition_flags(attacker, definitions)
	var target_flags := _condition_flags(target, definitions)
	var advantage: bool = not is_ranged and target_flags["melee_advantage_when_close"] and target_is_close
	var disadvantage: bool = attacker_flags["attack_roll_disadvantage"] or (is_ranged and target_flags["ranged_disadvantage_when_not_close"] and not target_is_close)
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
	if state.initiative_order.is_empty(): return _rejected(result, cmd, RejectionReasonRules.NO_INITIATIVE_ORDER)
	var next_index := TurnOrderRules.next_eligible_index(state, state.current_turn_index)
	if next_index < 0: return _rejected(result, cmd, RejectionReasonRules.NO_ELIGIBLE_ACTORS)
	var next_round := state.round_number + (1 if next_index <= state.current_turn_index else 0)
	var next_actor: ActorState = state.actors[state.initiative_order[next_index]]
	result.events.append(Event.create(&"turn_ended", {"actor_id": cmd.actor_id}))
	result.events.append(_turn_started_event(next_actor, next_index, next_round))
	return result


static func _turn_started_event(actor: ActorState, turn_index: int, round_number: int) -> Event:
	return Event.create(&"turn_started", {"actor_id": actor.id, "turn_index": turn_index, "round_number": round_number, "phase": EncounterRules.COMBAT, "movement_remaining": actor.movement_speed, "action_available": true, "bonus_action_available": true, "reaction_available": true, "disengaged": false})


static func _condition_flags(actor: ActorState, definitions: DefinitionLibrary) -> Dictionary:
	var flags := {"attack_roll_disadvantage": false, "melee_advantage_when_close": false, "ranged_disadvantage_when_not_close": false}
	for condition_id in actor.conditions:
		var definition := definitions.get_condition(condition_id)
		if definition == null: continue
		flags["attack_roll_disadvantage"] = flags["attack_roll_disadvantage"] or definition.attack_roll_disadvantage
		flags["melee_advantage_when_close"] = flags["melee_advantage_when_close"] or definition.melee_advantage_when_close
		flags["ranged_disadvantage_when_not_close"] = flags["ranged_disadvantage_when_not_close"] or definition.ranged_disadvantage_when_not_close
	return flags


static func _condition_requiring_stand(actor: ActorState, definitions: DefinitionLibrary) -> StringName:
	for condition_id in actor.conditions:
		var definition := definitions.get_condition(condition_id)
		if definition != null and definition.half_speed_required_to_stand:
			return condition_id
	return &""


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
		&"bonus_action_spent": (state.actors[event.data["actor_id"]] as ActorState).bonus_action_available = false
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
		&"interaction_completed":
			var interactable: InteractableState = state.interactables[event.data["interactable_id"]]
			interactable.state = event.data["new_state"]
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
