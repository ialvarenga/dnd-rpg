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
## Bump 3: actor-targeted abilities may author their range at the ability
## boundary, shared by resolution, targeting previews, and approach planning.
## Bump 5: adds skill_check and set_disposition commands, the start_dialog
## ability effect, and lets an ability opt into resolving outside combat
## (usable_in_exploration) instead of every ability being combat-gated.
## Bump 6: a prone actor stands automatically at the start of its turn (and
## when combat ends), a targeted ability's action_spent carries target_id, and
## a condition may block reactions (no opportunity attacks while prone).
## Bump 7: actors have wallets and can transfer coins during exploration.
## Bump 8: peaceful social resolutions can clear an authored encounter.
## Bump 9: attack events carry their complete, already-resolved roll breakdown
## for combat-log narration and replay inspection.
## Bump 10: attack bonus, damage, and armor class are derived by AttackMath from
## ability scores, proficiency, and equipment instead of authored per actor;
## unarmed strikes deal 1 + Strength; attack events name their modifier parts
## and every advantage/disadvantage source.
## Bump 11: actor-targeted abilities apply their authored target_filter while
## preserving the living-target requirement.
## Bump 12: exploration_only abilities, including Talk, are rejected in combat.
## Bump 13: attack-triggered condition modifiers are resolved and consumed
## through explicit events after the relevant attack.
## Bump 14: weapon masteries, ability modes, forced movement/falls, elevation,
## weighted paths, area saves, stealth/surprise, and surrender are authoritative.
## Bump 15: moves route per Strength across ledge jumps (JumpRules), a hard
## landing deals SRD fall damage and leaves the jumper Prone, and a Shove fall
## now leaves its target Prone too.
## Bump 16: the Jump action leaps to a point, reading the on-foot run-up that
## movement now tracks; outside combat every ability resolves with no action
## economy, and any ability aimed at the other side opens combat.
const RULES_VERSION: int = 16

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
const AbilityTargetingRules = preload("res://sim/ability_targeting.gd")
const EquipmentRules = preload("res://sim/equipment.gd")
const AbilityCheckRules = preload("res://sim/rules/ability_check.gd")
const AttackMathRules = preload("res://sim/rules/attack_math.gd")
const MasteryRulesScript = preload("res://sim/rules/mastery_rules.gd")
const DetectionRulesScript = preload("res://sim/rules/detection_rules.gd")
const JumpRulesScript = preload("res://sim/rules/jump_rules.gd")

const EFFECT_ADD_BASE_MOVEMENT := &"add_base_movement"
const EFFECT_APPLY_CONDITION := &"apply_condition"
const EFFECT_REMOVE_CONDITION := &"remove_condition"
const EFFECT_APPLY_DISENGAGE := &"apply_disengage"
const EFFECT_PERFORM_ATTACK := &"perform_attack"
const EFFECT_SAVING_THROW := &"saving_throw"
const EFFECT_HEAL := &"heal"
const EFFECT_CONSUME_ITEM := &"consume_item"
const EFFECT_START_DIALOG := &"start_dialog"
const EFFECT_FORCED_MOVEMENT := &"forced_movement"
const EFFECT_AREA_DAMAGE := &"area_damage"
const EFFECT_TOGGLE_SNEAK := &"toggle_sneak"
const EFFECT_LEAP := &"leap"

## Every social stance set_disposition accepts. Kept beside the interactable
## transition table: a small fixed vocabulary the resolver validates against
## rather than trusting whatever a caller puts in metadata.
const DISPOSITIONS: Array[StringName] = [&"hostile", &"neutral"]

const INTERACT_RANGE_EPSILON := 0.0001

## Interactable type -> {current state: next state}. Small and fixed for V1
## (door/chest/lever/barrel, per implementation_plan.md Fase A9); Resolver reads
## InteractableState.type generically instead of branching on instance id, the
## same way ability effects avoid branching on ability id.
const INTERACTABLE_TRANSITIONS := {
	&"door": {&"closed": &"open", &"open": &"closed"},
	&"chest": {&"closed": &"open"},
	&"barrel": {&"closed": &"open"},
	&"lever": {&"off": &"on", &"on": &"off"},
	&"pickup": {&"ready": &"collected"},
}


static func resolve(state: BattleState, cmd: Command, nav: NavProvider, los: LosProvider, defs: DefinitionLibrary = null) -> ResolutionResult:
	var result := _resolve_command(state, cmd, nav, los, defs)
	return _finalize_resolution(state, cmd, result, defs if defs != null else DefinitionLibrary.get_default())


static func _resolve_command(state: BattleState, cmd: Command, nav: NavProvider, los: LosProvider, defs: DefinitionLibrary = null) -> ResolutionResult:
	var definitions := defs if defs != null else DefinitionLibrary.get_default()
	var result := ResolutionResult.new()
	result.next_rng_state = state.rng_state
	if state.phase == EncounterRules.GAME_OVER:
		return _rejected(result, cmd, RejectionReasonRules.GAME_OVER)
	if not state.actors.has(cmd.actor_id):
		return _rejected(result, cmd, RejectionReasonRules.UNKNOWN_ACTOR)
	if cmd.type == &"start_combat":
		return _resolve_start_combat(state, cmd, result)
	if cmd.type == &"end_combat":
		return _resolve_end_combat(state, cmd, result, definitions)
	if cmd.type == &"move" and state.phase == EncounterRules.EXPLORATION:
		return _resolve_move(state, cmd, nav, los, definitions, result)
	if cmd.type == &"interact" and state.phase == EncounterRules.EXPLORATION:
		return _resolve_interact(state, cmd, result, false)
	if cmd.type == &"skill_check":
		return _resolve_skill_check(state, cmd, result)
	if cmd.type == &"set_disposition":
		return _resolve_set_disposition(state, cmd, result)
	if cmd.type == &"transfer_coins":
		return _resolve_transfer_coins(state, cmd, result)
	if cmd.type == &"clear_encounter":
		return _resolve_clear_encounter(state, cmd, result)
	if cmd.type == &"surrender":
		return _resolve_surrender(state, cmd, result)
	# Abilities resolve their own phase gate, because one may declare
	# usable_in_exploration. Everything else stays behind the combat turn gate,
	# in the same order as before.
	var ability_id := AbilityRoutingRules.ability_id_for_command(cmd.type) if AbilityRoutingRules.is_ability_command(cmd.type) else (cmd.type if definitions.has_ability(cmd.type) else &"")
	if ability_id != &"":
		var ability_rejection := CommandPhaseRulesScript.rejection_for_ability(state, cmd.actor_id, definitions.get_ability(ability_id))
		if ability_rejection != &"":
			return _rejected(result, cmd, ability_rejection)
		return _resolve_ability_command(state, cmd, nav, los, definitions, result, ability_id)
	var phase_rejection := CommandPhaseRulesScript.rejection_for_combat_turn(state, cmd.actor_id)
	if phase_rejection != &"":
		return _rejected(result, cmd, phase_rejection)
	if cmd.type == &"move":
		return _resolve_move(state, cmd, nav, los, definitions, result)
	if cmd.type == &"interact":
		return _resolve_interact(state, cmd, result, true)
	if cmd.type == &"end_turn":
		return _resolve_end_turn(state, cmd, result, definitions)
	return _rejected(result, cmd, RejectionReasonRules.UNSUPPORTED_COMMAND)


static func _resolve_start_combat(state: BattleState, cmd: Command, result: ResolutionResult) -> ResolutionResult:
	if state.phase != EncounterRules.EXPLORATION:
		return _rejected(result, cmd, RejectionReasonRules.COMBAT_ALREADY_ACTIVE)
	if not TurnOrderRules.is_actor_eligible(state.actors[cmd.actor_id]):
		return _rejected(result, cmd, RejectionReasonRules.ACTOR_NOT_ELIGIBLE)
	var requested_participants: Array[int] = []
	for actor_id in cmd.metadata.get("participant_actor_ids", []):
		var parsed_id := int(actor_id)
		if not requested_participants.has(parsed_id):
			requested_participants.append(parsed_id)
	if requested_participants.is_empty():
		requested_participants = TurnOrderRules.eligible_actor_ids(state)
	requested_participants.sort()
	var encounter_id := str(cmd.metadata.get("encounter_id", ""))
	if not encounter_id.is_empty() and (
		not requested_participants.has(cmd.actor_id)
		or not _all_participants_eligible(state, requested_participants)
		or not _has_opposing_sides(state, requested_participants)
	):
		return _rejected(result, cmd, RejectionReasonRules.INVALID_ENCOUNTER)
	var disadvantaged: Array[int] = []
	for actor_id in cmd.metadata.get("initiative_disadvantage_actor_ids", []):
		disadvantaged.append(int(actor_id))
	var initiative := InitiativeRules.resolve_for_actor_ids(state, requested_participants, disadvantaged)
	var order: Array[int] = initiative["order"]
	if order.is_empty():
		return _rejected(result, cmd, RejectionReasonRules.NO_ELIGIBLE_ACTORS)
	var first_index := 0
	if bool(cmd.metadata.get("skip_surprised_round_one", false)):
		while first_index < order.size() and disadvantaged.has(order[first_index]):
			first_index += 1
		if first_index >= order.size():
			first_index = 0
	var first_actor: ActorState = state.actors[order[first_index]]
	result.events.append(Event.create(&"combat_started", {
		"initiator_actor_id": cmd.actor_id,
		"phase": EncounterRules.COMBAT_STARTING,
		"encounter_id": encounter_id,
		"combatant_ids": requested_participants.duplicate(),
	}))
	result.events.append(Event.create(&"initiative_established", {"initiative_order": order, "initiative_rolls": initiative["entries"], "current_turn_index": first_index, "round_number": 1, "skip_round_one_actor_ids": disadvantaged if bool(cmd.metadata.get("skip_surprised_round_one", false)) else []}))
	if bool(cmd.metadata.get("skip_surprised_round_one", false)):
		for skipped_index in range(first_index):
			result.events.append(Event.create(&"surprise_turn_skipped", {"actor_id": order[skipped_index], "round_number": 1}))
	result.events.append(_turn_started_event(first_actor, first_index, 1))
	result.next_rng_state = initiative["next_rng_state"]
	return result


static func _resolve_end_combat(state: BattleState, cmd: Command, result: ResolutionResult, definitions: DefinitionLibrary) -> ResolutionResult:
	if not EncounterRules.can_end(state):
		return _rejected(result, cmd, RejectionReasonRules.NOT_IN_COMBAT)
	if state.current_actor_id() != cmd.actor_id:
		return _rejected(result, cmd, RejectionReasonRules.NOT_CURRENT_ACTOR)
	if EncounterRules.resolved_outcome(state) == EncounterRules.OUTCOME_NONE:
		return _rejected(result, cmd, RejectionReasonRules.COMBAT_UNRESOLVED)
	_append_combat_end_stand_ups(result, state, definitions)
	result.events.append(Event.create(&"combat_ending", {"phase": EncounterRules.COMBAT_ENDING}))
	result.events.append(Event.create(&"combat_ended", {"phase": EncounterRules.EXPLORATION, "initiative_order": [], "current_turn_index": 0, "round_number": 1}))
	return result


static func _has_opposing_sides(state: BattleState, actor_ids: Array[int]) -> bool:
	var heroes := false
	var enemies := false
	for actor_id in actor_ids:
		if not state.actors.has(actor_id):
			continue
		var actor: ActorState = state.actors[actor_id]
		heroes = heroes or actor.side == &"heroes"
		enemies = enemies or actor.side == &"enemies"
	return heroes and enemies


static func _all_participants_eligible(state: BattleState, actor_ids: Array[int]) -> bool:
	for actor_id in actor_ids:
		if not state.actors.has(actor_id) or not TurnOrderRules.is_actor_eligible(state.actors[actor_id]):
			return false
	return true


static func _resolve_move(state: BattleState, cmd: Command, nav: NavProvider, los: LosProvider, definitions: DefinitionLibrary, result: ResolutionResult) -> ResolutionResult:
	var actor: ActorState = state.actors[cmd.actor_id]
	var conscious_rejection := CommandPhaseRulesScript.rejection_for_conscious(actor)
	if conscious_rejection != &"":
		return _rejected(result, cmd, conscious_rejection)
	# Routing, reachability, and clamping only see the ledges this creature's
	# Strength can take (ADR-009).
	nav = nav.for_jumper(actor.strength)
	var nav_path := nav.find_path(actor.position, cmd.target_pos)
	if nav_path.is_empty() or not nav.is_reachable(actor.position, cmd.target_pos):
		return _rejected(result, cmd, RejectionReasonRules.UNREACHABLE)
	var path := PolylineUtil.with_start(nav_path, actor.position)
	var requested_path_cost := nav.path_cost(path)
	if requested_path_cost <= MOVEMENT_EPSILON:
		return _rejected(result, cmd, RejectionReasonRules.NO_MOVEMENT)
	if state.phase == EncounterRules.EXPLORATION:
		var detection_state := state.clone()
		for leg in _movement_legs(path, nav):
			if leg["kind"] == &"walk":
				var leg_path: PackedVector3Array = leg["path"]
				var leg_cost := requested_path_cost if leg_path.size() == path.size() else nav.path_cost(leg_path)
				_append_movement_event(result, actor.id, (detection_state.actors[actor.id] as ActorState).position, leg_path, leg_cost, requested_path_cost, false)
				apply(detection_state, result.events.back())
			elif not _append_jump_leg(result, detection_state, actor.id, leg, false):
				break
		result.next_rng_state = detection_state.rng_state
		if actor.sneaking:
			var moved_actor := detection_state.actors[actor.id] as ActorState
			var observer_ids: Array = detection_state.actors.keys()
			observer_ids.sort()
			for observer_id in observer_ids:
				var observer := detection_state.actors[observer_id] as ActorState
				if not moved_actor.hidden_from.has(observer.id):
					continue
				if observer.side != moved_actor.side and observer.is_conscious() and observer.disposition == &"hostile" and observer.position.distance_to(moved_actor.position) <= DetectionRulesScript.DETECTION_RANGE_METERS and los.has_line_of_sight(observer.position, moved_actor.position) and DetectionRulesScript.detected_by(observer, moved_actor.stealth_total):
					result.events.append(Event.create(&"detection_changed", {"actor_id": moved_actor.id, "observer_id": observer.id, "hidden": false, "stealth_total": moved_actor.stealth_total, "passive_perception": observer.passive_perception(), "reason": &"moved_into_view"}))
		return result

	var working := state.clone()
	var working_actor: ActorState = working.actors[cmd.actor_id]
	var standing_condition := _condition_requiring_stand(working_actor, definitions)
	if standing_condition != &"":
		if working_actor.movement_remaining + MOVEMENT_EPSILON < _stand_cost(working_actor):
			return _rejected(result, cmd, RejectionReasonRules.INSUFFICIENT_MOVEMENT_TO_STAND)
		_append_stand_up(result, working, working_actor.id, standing_condition)

	var available := maxf(0.0, (working.actors[cmd.actor_id] as ActorState).movement_remaining)
	if available <= MOVEMENT_EPSILON:
		return _rejected(result, cmd, RejectionReasonRules.NO_MOVEMENT_REMAINING)
	var resolved_path := path
	var movement_cost := requested_path_cost
	var was_clamped := false
	if requested_path_cost > available + MOVEMENT_EPSILON:
		resolved_path = nav.clamp_path(path, available)
		movement_cost = nav.path_cost(resolved_path)
		if resolved_path.size() < 2 or movement_cost <= MOVEMENT_EPSILON:
			return _rejected(result, cmd, RejectionReasonRules.NO_MOVEMENT_REMAINING)
		was_clamped = true

	for leg in _movement_legs(resolved_path, nav):
		if not (working.actors[cmd.actor_id] as ActorState).is_alive():
			break
		if leg["kind"] == &"walk":
			_resolve_walking_leg(result, working, cmd.actor_id, leg["path"], nav, los, definitions, requested_path_cost, was_clamped)
			continue
		_resolve_jump_reactions(result, working, cmd.actor_id, leg, los, definitions)
		if not (working.actors[cmd.actor_id] as ActorState).is_alive() or not _append_jump_leg(result, working, cmd.actor_id, leg, true):
			break
	result.next_rng_state = working.rng_state
	return result


## Splits a path into walking polylines and single ledge-jump segments, in
## travel order. A jump is a segment the NavProvider reports through
## jump_between; everything between jumps is ordinary walking.
static func _movement_legs(path: PackedVector3Array, nav: NavProvider) -> Array[Dictionary]:
	var legs: Array[Dictionary] = []
	var walk := PackedVector3Array([path[0]])
	for index in range(1, path.size()):
		var jump := nav.jump_between(path[index - 1], path[index])
		if jump.is_empty():
			walk.append(path[index])
			continue
		if walk.size() >= 2:
			legs.append({"kind": &"walk", "path": walk})
		legs.append({"kind": &"jump", "from": path[index - 1], "to": path[index], "jump": jump})
		walk = PackedVector3Array([path[index]])
	if walk.size() >= 2:
		legs.append({"kind": &"walk", "path": walk})
	return legs


static func _resolve_walking_leg(result: ResolutionResult, working: BattleState, mover_id: int, leg_path: PackedVector3Array, nav: NavProvider, los: LosProvider, definitions: DefinitionLibrary, requested_path_cost: float, was_clamped: bool) -> void:
	var traversed_distance := 0.0
	var leg_distance := PolylineUtil.length(leg_path)
	while traversed_distance + MOVEMENT_EPSILON < leg_distance and (working.actors[mover_id] as ActorState).is_alive():
		var remaining_path := _path_from_distance(leg_path, traversed_distance)
		var remaining_distance := PolylineUtil.length(remaining_path)
		var reaction := _next_opportunity_reaction(working, mover_id, remaining_path, los)
		var segment_distance := remaining_distance if reaction.is_empty() else float(reaction["distance"])
		if segment_distance > MOVEMENT_EPSILON:
			var segment_path := PolylineUtil.clamp(remaining_path, segment_distance)
			var segment_cost := nav.path_cost(segment_path)
			_append_movement_event(result, mover_id, (working.actors[mover_id] as ActorState).position, segment_path, segment_cost, requested_path_cost, was_clamped)
			# Apply only to the private working clone so following reactions see the
			# exact authoritative boundary position.
			apply(working, result.events.back())
			_append_movement_spent(result, working, mover_id, segment_cost)
			traversed_distance += segment_distance
		if reaction.is_empty():
			break
		var reactor_id := int(reaction["actor_id"])
		var reactor: ActorState = working.actors[reactor_id]
		var mover: ActorState = working.actors[mover_id]
		_append_and_apply(result, working, Event.create(&"reaction_triggered", {"actor_id": reactor_id, "target_id": mover.id, "reaction": &"opportunity_attack"}))
		_resolve_attack_between(working, reactor, mover, los, definitions, result, false, true, &"opportunity")
		if not (working.actors[mover_id] as ActorState).is_alive():
			break
		# Remaining enemies at this same boundary have distance zero; their spent
		# reaction is filtered, so each other eligible enemy resolves once.


## Jumping out of a threatened space still provokes. Every eligible reaction
## resolves at the takeoff point, before the creature is airborne, so a jump is
## never split mid-air.
static func _resolve_jump_reactions(result: ResolutionResult, working: BattleState, mover_id: int, leg: Dictionary, los: LosProvider, definitions: DefinitionLibrary) -> void:
	var jump_path := PackedVector3Array([leg["from"], leg["to"]])
	while (working.actors[mover_id] as ActorState).is_alive():
		var reaction := _next_opportunity_reaction(working, mover_id, jump_path, los)
		if reaction.is_empty():
			return
		var reactor: ActorState = working.actors[int(reaction["actor_id"])]
		_append_and_apply(result, working, Event.create(&"reaction_triggered", {"actor_id": reactor.id, "target_id": mover_id, "reaction": &"opportunity_attack"}))
		_resolve_attack_between(working, reactor, working.actors[mover_id], los, definitions, result, false, true, &"opportunity")


## Emits one ledge jump and its landing. Returns false when the move must end
## here: a hard landing (fall damage, and Prone in combat) stops the creature
## wherever it came down. Exploration charges no movement and applies no Prone.
static func _append_jump_leg(result: ResolutionResult, working: BattleState, actor_id: int, leg: Dictionary, in_combat: bool) -> bool:
	var jump: Dictionary = leg["jump"]
	var from: Vector3 = leg["from"]
	var to: Vector3 = leg["to"]
	var kind := StringName(jump.get("kind", JumpRulesScript.DROP))
	var cost := JumpRulesScript.jump_cost(kind, from, to)
	var height := absf(from.y - to.y)
	var jumper: ActorState = working.actors[actor_id]
	# The Jump action knows whether it had its run-up. A routed ledge climb was
	# only offered if the jumper can make it, so one beyond its standing High
	# Jump must be the running jump, taken after a 3 m run-up.
	var running := bool(jump["running"]) if jump.has("running") else (kind == JumpRulesScript.CLIMB and JumpRulesScript.high_jump_m(jumper.strength, false) + JumpRulesScript.EPSILON < height)
	_append_and_apply(result, working, Event.create(&"jump_performed", {
		"actor_id": actor_id,
		"kind": kind,
		"from": from,
		"to": to,
		"height": height,
		"running": running,
		"movement_cost": cost,
	}))
	if in_combat:
		_append_movement_spent(result, working, actor_id, cost)
	if kind != JumpRulesScript.DROP:
		return true
	var actor: ActorState = working.actors[actor_id]
	var outcome := JumpRulesScript.drop_outcome(actor.strength, height)
	if int(outcome["dice"]) <= 0:
		return true
	_append_fall(result, working, actor, actor_id, from, to, height, outcome, in_combat, true)
	return false


## The Jump action (ADR-009): one straight leap to cmd.target_pos -- across a
## gap, down a ledge, or up onto one -- limited by the jumper's own Long and
## High Jump, halved without a 3 m run-up (ActorState.run_up_m). It costs
## movement like any jump and never an action; a prone jumper stands first,
## and leaving an enemy's reach provokes at the takeoff.
static func _resolve_leap(state: BattleState, cmd: Command, nav: NavProvider, los: LosProvider, definitions: DefinitionLibrary, result: ResolutionResult) -> ResolutionResult:
	var actor: ActorState = state.actors[cmd.actor_id]
	if not is_finite(cmd.target_pos.x) or not is_finite(cmd.target_pos.y) or not is_finite(cmd.target_pos.z):
		return _rejected(result, cmd, RejectionReasonRules.INVALID_TARGET_POINT)
	var ground := nav.surface_point(cmd.target_pos)
	if not is_finite(ground.x):
		return _rejected(result, cmd, RejectionReasonRules.NO_LANDING)
	# Positions carry the body's height above the ground; keep it on landing.
	var standing_on := nav.surface_point(actor.position)
	var clearance := actor.position.y - standing_on.y if is_finite(standing_on.x) else 0.0
	var landing := ground + Vector3.UP * clearance
	var running := actor.run_up_m + JumpRulesScript.EPSILON >= JumpRulesScript.RUN_UP_M
	var leap := JumpRulesScript.leap_check(actor.strength, running, actor.position, landing)
	if not bool(leap["ok"]):
		return _rejected(result, cmd, StringName(leap["reason"]))
	if los.cover_between(actor.position, landing) == LosProvider.COVER_TOTAL:
		return _rejected(result, cmd, RejectionReasonRules.NO_LINE_OF_SIGHT)
	var in_combat := state.phase == EncounterRules.COMBAT
	var working := state.clone()
	if in_combat:
		var standing_condition := _condition_requiring_stand(actor, definitions)
		var stand_cost := _stand_cost(actor) if standing_condition != &"" else 0.0
		if actor.movement_remaining + MOVEMENT_EPSILON < stand_cost + float(leap["cost"]):
			return _rejected(result, cmd, RejectionReasonRules.INSUFFICIENT_MOVEMENT)
		if standing_condition != &"":
			_append_stand_up(result, working, actor.id, standing_condition)
	var leg := {"from": actor.position, "to": landing, "jump": {"kind": leap["kind"], "running": running}}
	_resolve_jump_reactions(result, working, actor.id, leg, los, definitions)
	if (working.actors[actor.id] as ActorState).is_alive():
		_append_jump_leg(result, working, actor.id, leg, in_combat)
	result.next_rng_state = working.rng_state
	return result


## Shared by a hard landing and a Shove fall: SRD Falling damage, then Prone
## when the fall hurt a creature that is still conscious and standing. The
## fall_started event says whether Prone follows, so presentation outside
## combat can knock the creature down and stand it straight back up.
static func _append_fall(result: ResolutionResult, working: BattleState, target: ActorState, source_actor_id: int, from: Vector3, to: Vector3, fall_distance: float, outcome: Dictionary, applies_prone: bool, deliberate: bool) -> void:
	var fall_roll := Dice.roll_dice(working.rng_state, int(outcome["dice"]), JumpRulesScript.FALL_DIE_SIDES)
	working.rng_state = int(fall_roll["next_rng_state"])
	var knocks_prone := applies_prone and bool(outcome["prone"])
	_append_and_apply(result, working, Event.create(&"fall_started", {"actor_id": target.id, "from": from, "to": to, "fall_distance": fall_distance, "effective_fall": float(outcome["effective_m"]), "deliberate": deliberate, "prone": knocks_prone}))
	_append_damage_and_consequence(result, working, target, source_actor_id, int(fall_roll["total"]), &"fall", {"rolls": fall_roll["values"]})
	if knocks_prone and target.is_conscious() and not target.is_prone():
		_append_and_apply(result, working, Event.create(&"condition_added", {"actor_id": target.id, "condition": &"prone", "source_actor_id": source_actor_id, "remaining_triggers": -1, "expiration_timing": &"none", "related_actor_id": -1}))


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
	if not interactable.contents.is_empty():
		result.events.append(Event.create(&"items_looted", {"actor_id": actor.id, "interactable_id": interactable.id, "item_ids": interactable.contents.duplicate()}))
	return result


static func _resolve_ability_command(state: BattleState, cmd: Command, nav: NavProvider, los: LosProvider, definitions: DefinitionLibrary, result: ResolutionResult, ability_id: StringName) -> ResolutionResult:
	var actor: ActorState = state.actors[cmd.actor_id]
	var conscious_rejection := CommandPhaseRulesScript.rejection_for_conscious(actor)
	if conscious_rejection != &"": return _rejected(result, cmd, conscious_rejection)
	var ability := definitions.get_ability(ability_id)
	if ability == null: return _rejected(result, cmd, RejectionReasonRules.UNKNOWN_ABILITY_DEFINITION)
	var in_combat := state.phase == EncounterRules.COMBAT
	var cost_rejection := AbilityCostRulesScript.rejection_for_cost(actor, ability, definitions, in_combat)
	if cost_rejection != &"": return _rejected(result, cmd, cost_rejection)
	if ability.effects.any(func(effect: AbilityEffect): return effect.type == EFFECT_LEAP):
		return _resolve_leap(state, cmd, nav, los, definitions, result)
	var selected_mode := StringName(str(cmd.metadata.get("mode", "")))
	if not ability.modes.is_empty() and not ability.modes.has(selected_mode):
		return _rejected(result, cmd, RejectionReasonRules.INVALID_ABILITY_MODE)
	var target: ActorState = null
	var target_interactable: InteractableState = null
	if ability.targeting == &"actor":
		if not state.actors.has(cmd.target_id): return _rejected(result, cmd, RejectionReasonRules.UNKNOWN_TARGET)
		target = state.actors[cmd.target_id]
		if not AbilityTargetingRules.is_valid_target(actor, target, ability):
			return _rejected(result, cmd, RejectionReasonRules.INVALID_TARGET)
		var authored_range := AbilityTargetingRules.target_range(definitions, ability.id)
		var command_range := maxf(authored_range, float(cmd.metadata.get("range_meters", authored_range)))
		if actor.position.distance_to(target.position) > command_range + MOVEMENT_EPSILON:
			return _rejected(result, cmd, RejectionReasonRules.TARGET_OUT_OF_RANGE)
		if los.cover_between(actor.position, target.position) == LosProvider.COVER_TOTAL:
			return _rejected(result, cmd, RejectionReasonRules.NO_LINE_OF_SIGHT)
	elif ability.targeting == &"interactable":
		if not state.interactables.has(cmd.target_interactable_id):
			return _rejected(result, cmd, RejectionReasonRules.UNKNOWN_INTERACTABLE)
		target_interactable = state.interactables[cmd.target_interactable_id]
		if target_interactable.destroyed or not target_interactable.tags.has(&"explosive"):
			return _rejected(result, cmd, RejectionReasonRules.INVALID_INTERACTABLE_STATE)
		if actor.position.distance_to(target_interactable.position) > ability.target_range_meters + MOVEMENT_EPSILON:
			return _rejected(result, cmd, RejectionReasonRules.TARGET_OUT_OF_RANGE)
		if los.cover_between(actor.position, target_interactable.position) == LosProvider.COVER_TOTAL:
			return _rejected(result, cmd, RejectionReasonRules.NO_LINE_OF_SIGHT)
	elif ability.targeting == &"ground_point":
		if not is_finite(cmd.target_pos.x) or not is_finite(cmd.target_pos.y) or not is_finite(cmd.target_pos.z):
			return _rejected(result, cmd, RejectionReasonRules.INVALID_TARGET_POINT)
		if actor.position.distance_to(cmd.target_pos) > ability.target_range_meters + MOVEMENT_EPSILON:
			return _rejected(result, cmd, RejectionReasonRules.TARGET_OUT_OF_RANGE)
		if los.cover_between(actor.position, cmd.target_pos) == LosProvider.COVER_TOTAL:
			return _rejected(result, cmd, RejectionReasonRules.NO_LINE_OF_SIGHT)
	var has_attack := ability.effects.any(func(effect: AbilityEffect): return effect.type == EFFECT_PERFORM_ATTACK)
	# Effects only ever append events, so "this actor has nothing to say" has to
	# be a rejection here. Keyed off the effect type, never off an ability id.
	if ability.effects.any(func(effect: AbilityEffect): return effect.type == EFFECT_START_DIALOG) and (target == null or target.dialog_id == &""):
		return _rejected(result, cmd, RejectionReasonRules.TARGET_HAS_NO_DIALOG)
	var working := state.clone()
	# Out of combat, an attack or anything else aimed at the other side opens
	# the fight; every other action just resolves, with no economy to spend.
	var opens_combat := state.phase == EncounterRules.EXPLORATION and CommandPhaseRulesScript.opens_combat_from_exploration(ability)
	if opens_combat:
		var start := Command.create(&"start_combat", actor.id)
		start.metadata = {
			"encounter_id": str(cmd.metadata.get("encounter_id", "")),
			"participant_actor_ids": cmd.metadata.get("participant_actor_ids", []),
			"initiative_disadvantage_actor_ids": [],
		}
		if target != null and actor.hidden_from.has(target.id):
			for participant_id in start.metadata["participant_actor_ids"]:
				var participant := state.actors.get(int(participant_id)) as ActorState
				if participant != null and participant.side == target.side:
					start.metadata["initiative_disadvantage_actor_ids"].append(participant.id)
		_resolve_start_combat(state, start, result)
		if not result.events.is_empty() and result.events[0].type == &"command_rejected":
			return result
		for opening_event in result.events:
			apply(working, opening_event)
		working.rng_state = result.next_rng_state
		result.events.append(Event.create(&"exploration_attack_opened", {"actor_id": actor.id, "target_id": target.id if target != null else -1, "surprise": target != null and actor.hidden_from.has(target.id)}))
	_spend_ability_cost(result, actor, ability, not has_attack, not has_attack, target.id if target != null else -1, in_combat or opens_combat)
	var source: ActorState = working.actors[actor.id]
	var working_target: ActorState = working.actors.get(cmd.target_id) as ActorState
	var context := {
		"attack_hit": false,
		"save_succeeded": false,
		"command_metadata": cmd.metadata,
		"target_position": target.position if target != null else (target_interactable.position if target_interactable != null else cmd.target_pos),
		"target_radius": target_interactable.blast_radius_meters if target_interactable != null and target_interactable.blast_radius_meters > 0.0 else ability.target_radius_meters,
		"target_interactable_id": target_interactable.id if target_interactable != null else "",
		"damage_die_override": target_interactable.blast_damage_die if target_interactable != null else 0,
		"damage_dice_count_override": target_interactable.blast_damage_dice_count if target_interactable != null else 0,
	}
	var has_forced_movement := ability.effects.any(func(effect: AbilityEffect): return effect.type == EFFECT_FORCED_MOVEMENT and (effect.mode == &"" or effect.mode == selected_mode))
	if has_forced_movement:
		_append_and_apply(result, working, Event.create(&"forced_movement_attempted", {"actor_id": source.id, "target_id": working_target.id, "mode": selected_mode}))
	for effect in ability.effects:
		if effect.mode != &"" and effect.mode != selected_mode:
			continue
		match effect.type:
			EFFECT_PERFORM_ATTACK:
				var authored_range := AbilityTargetingRules.target_range(definitions, ability.id)
				var maximum_range := maxf(authored_range, float(cmd.metadata.get("range_meters", authored_range)))
				var is_ranged := bool(cmd.metadata.get("is_ranged", effect.is_ranged or EquipmentRules.is_ranged_weapon(source, definitions)))
				var normal_range := EquipmentRules.normal_range(source, definitions, maximum_range) if is_ranged else maximum_range
				var long_range := EquipmentRules.long_range(source, definitions, maximum_range) if is_ranged else maximum_range
				context["attack_hit"] = _resolve_attack_between(
					working, source, working_target, los, definitions, result,
					ability.costs_action, ability.costs_reaction, effect.attack_kind,
					long_range, is_ranged, normal_range,
				)
			EFFECT_SAVING_THROW:
				context["save_succeeded"] = _resolve_saving_throw(working, source, working_target, effect, result)
				if has_forced_movement and bool(context["save_succeeded"]):
					_append_and_apply(result, working, Event.create(&"forced_movement_resisted", {"actor_id": source.id, "target_id": working_target.id, "mode": selected_mode}))
			_:
				_apply_generic_effect(result, working, source, working_target, effect, context, definitions, nav, los)
	result.next_rng_state = working.rng_state
	return result


## Generic d20 check against a DC. Every parameter arrives in cmd.metadata --
## ability, skill, dc, proficient -- so the resolver never learns who is being
## persuaded or why; the dialog layer owns that. Legal in any phase and spends
## nothing, because a check is not an action.
static func _resolve_skill_check(state: BattleState, cmd: Command, result: ResolutionResult) -> ResolutionResult:
	var actor: ActorState = state.actors[cmd.actor_id]
	var conscious_rejection := CommandPhaseRulesScript.rejection_for_conscious(actor)
	if conscious_rejection != &"":
		return _rejected(result, cmd, conscious_rejection)
	var ability := StringName(str(cmd.metadata.get("ability", "")))
	if not AbilityCheckRules.is_ability_score(ability):
		return _rejected(result, cmd, RejectionReasonRules.INVALID_ABILITY_SCORE)
	var difficulty_class := int(cmd.metadata.get("dc", 0))
	if difficulty_class < 1:
		return _rejected(result, cmd, RejectionReasonRules.INVALID_DIFFICULTY_CLASS)
	var proficient := bool(cmd.metadata.get("proficient", false))
	var roll := AbilityCheckRules.resolve(state.rng_state, actor, ability, difficulty_class, proficient)
	result.events.append(Event.create(&"skill_check_rolled", {
		"actor_id": actor.id,
		"target_id": cmd.target_id,
		"ability": ability,
		"skill": StringName(str(cmd.metadata.get("skill", ""))),
		"difficulty_class": difficulty_class,
		"modifier": int(roll["modifier"]),
		"roll": int(roll["roll"]),
		"rolls": roll["rolls"],
		"total": int(roll["total"]),
		"success": bool(roll["success"]),
		"advantage": bool(roll["advantage"]),
		"disadvantage": bool(roll["disadvantage"]),
	}))
	result.next_rng_state = int(roll["next_rng_state"])
	return result


## cmd.actor_id is the subject whose stance changes, so the shared
## UNKNOWN_ACTOR guard already covers it. Exploration only: talking a fight
## down mid-combat is out of scope for V1.
static func _resolve_set_disposition(state: BattleState, cmd: Command, result: ResolutionResult) -> ResolutionResult:
	if state.phase != EncounterRules.EXPLORATION:
		return _rejected(result, cmd, RejectionReasonRules.COMBAT_ALREADY_ACTIVE)
	var disposition := StringName(str(cmd.metadata.get("disposition", "")))
	if not DISPOSITIONS.has(disposition):
		return _rejected(result, cmd, RejectionReasonRules.INVALID_DISPOSITION)
	var actor: ActorState = state.actors[cmd.actor_id]
	result.events.append(Event.create(&"disposition_changed", {
		"actor_id": actor.id,
		"previous_disposition": actor.disposition,
		"disposition": disposition,
	}))
	return result


## Currency exchanges are authoritative simulation commands even though the
## current caller is dialogue. Keeping the recipient in target_id lets events,
## replay, and saves record a real transfer instead of a disappearing cost.
## There is no action cost, but transfers are exploration-only so a dialog
## cannot change wallets after combat has started.
static func _resolve_transfer_coins(state: BattleState, cmd: Command, result: ResolutionResult) -> ResolutionResult:
	if state.phase != EncounterRules.EXPLORATION:
		return _rejected(result, cmd, RejectionReasonRules.COMBAT_ALREADY_ACTIVE)
	if not state.actors.has(cmd.target_id) or cmd.target_id == cmd.actor_id:
		return _rejected(result, cmd, RejectionReasonRules.INVALID_TARGET if state.actors.has(cmd.target_id) else RejectionReasonRules.UNKNOWN_TARGET)
	var amount_value: Variant = cmd.metadata.get("amount", 0)
	if typeof(amount_value) != TYPE_INT or int(amount_value) <= 0:
		return _rejected(result, cmd, RejectionReasonRules.INVALID_COIN_AMOUNT)
	var payer: ActorState = state.actors[cmd.actor_id]
	var conscious_rejection := CommandPhaseRulesScript.rejection_for_conscious(payer)
	if conscious_rejection != &"":
		return _rejected(result, cmd, conscious_rejection)
	var amount := int(amount_value)
	if payer.coins < amount:
		return _rejected(result, cmd, RejectionReasonRules.INSUFFICIENT_COINS)
	var recipient: ActorState = state.actors[cmd.target_id]
	result.events.append(Event.create(&"coins_transferred", {
		"actor_id": payer.id,
		"target_id": recipient.id,
		"amount": amount,
		"payer_coins_before": payer.coins,
		"payer_coins_after": payer.coins - amount,
		"recipient_coins_before": recipient.coins,
		"recipient_coins_after": recipient.coins + amount,
	}))
	return result


## Social resolutions use this instead of pretending the player won a combat.
## Encounter membership remains world-owned data, so the controller supplies
## the authored id after settling every member's disposition.
static func _resolve_clear_encounter(state: BattleState, cmd: Command, result: ResolutionResult) -> ResolutionResult:
	if state.phase != EncounterRules.EXPLORATION:
		return _rejected(result, cmd, RejectionReasonRules.COMBAT_ALREADY_ACTIVE)
	var actor: ActorState = state.actors[cmd.actor_id]
	var conscious_rejection := CommandPhaseRulesScript.rejection_for_conscious(actor)
	if conscious_rejection != &"":
		return _rejected(result, cmd, conscious_rejection)
	var encounter_id := str(cmd.metadata.get("encounter_id", ""))
	if encounter_id.is_empty():
		return _rejected(result, cmd, RejectionReasonRules.INVALID_ENCOUNTER)
	result.events.append(Event.create(&"encounter_cleared", {"actor_id": actor.id, "encounter_id": encounter_id}))
	return result


static func _resolve_surrender(state: BattleState, cmd: Command, result: ResolutionResult) -> ResolutionResult:
	var rejection := CommandPhaseRulesScript.rejection_for_combat_turn(state, cmd.actor_id)
	if rejection != &"":
		return _rejected(result, cmd, rejection)
	var actor := state.actors[cmd.actor_id] as ActorState
	result.events.append(Event.create(&"actor_surrendered", {"actor_id": actor.id, "previous_disposition": actor.disposition, "disposition": &"neutral"}))
	return result


## `spends_economy` is false outside combat, where only the use pool drains.
static func _spend_ability_cost(result: ResolutionResult, actor: ActorState, ability: AbilityDefinition, include_action: bool = true, include_reaction: bool = true, target_id: int = -1, spends_economy: bool = true) -> void:
	# Unlike the action/bonus-action flags this is emitted for attacks too: the
	# attack_rolled event carries only the action/reaction spend flags, so a
	# limited-use attack would otherwise never decrement its pool.
	if ability.max_uses >= 0:
		var spent := int(actor.ability_uses_spent.get(ability.id, 0)) + 1
		result.events.append(Event.create(&"ability_use_spent", {
			"actor_id": actor.id, "ability_id": ability.id,
			"uses_spent": spent, "uses_remaining": maxi(0, ability.max_uses - spent),
		}))
	if not spends_economy:
		return
	if include_action and ability.costs_action:
		var action_data := {"actor_id": actor.id, "action": ability.id}
		# Presentation needs the recipient before any save/effect event names it
		# (a push is narrated toward its target even when the save succeeds).
		if target_id >= 0:
			action_data["target_id"] = target_id
		result.events.append(Event.create(&"action_spent", action_data))
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


static func _apply_generic_effect(result: ResolutionResult, working: BattleState, actor: ActorState, target: ActorState, effect: AbilityEffect, context: Dictionary, definitions: DefinitionLibrary, nav: NavProvider = null, los: LosProvider = null) -> void:
	if not _effect_should_apply(effect.apply_when, context):
		return
	var recipient := target if target != null else actor
	match effect.type:
		EFFECT_ADD_BASE_MOVEMENT:
			var amount := actor.movement_speed * effect.multiplier
			result.events.append(Event.create(&"movement_gained", {"actor_id": actor.id, "amount": amount, "movement_remaining_before": actor.movement_remaining, "movement_remaining_after": actor.movement_remaining + amount}))
		EFFECT_START_DIALOG:
			# Opening a conversation changes no state; the dialog layer reads
			# this event and drives the graph. dialog_id comes off the target's
			# authoritative state, not off caller metadata.
			result.events.append(Event.create(&"dialog_started", {"actor_id": actor.id, "target_id": recipient.id, "dialog_id": recipient.dialog_id}))
		EFFECT_APPLY_DISENGAGE:
			result.events.append(Event.create(&"disengage_applied", {"actor_id": actor.id}))
		EFFECT_APPLY_CONDITION:
			var duration := effect.condition_duration_triggers
			var expiration := effect.condition_expiration_timing
			if duration == -2:
				var condition_definition := definitions.get_condition(effect.condition_id)
				if condition_definition != null:
					duration = condition_definition.default_duration_triggers
					expiration = condition_definition.default_expiration_timing
				else:
					duration = -1
			var related_actor_id := -1
			if effect.condition_related_actor_metadata != &"":
				related_actor_id = int((context.get("command_metadata", {}) as Dictionary).get(effect.condition_related_actor_metadata, -1))
			_append_and_apply(result, working, Event.create(&"condition_added", {
				"actor_id": recipient.id,
				"condition": effect.condition_id,
				"source_actor_id": actor.id,
				"remaining_triggers": duration,
				"expiration_timing": expiration,
				"related_actor_id": related_actor_id,
			}))
		EFFECT_REMOVE_CONDITION:
			_append_and_apply(result, working, Event.create(&"condition_removed", {"actor_id": recipient.id, "condition": effect.condition_id}))
		EFFECT_HEAL:
			var roll := Dice.roll_dice(working.rng_state, effect.heal_dice_count, effect.heal_die)
			working.rng_state = int(roll["next_rng_state"])
			var amount: int = max(0, int(roll["total"]) + effect.heal_modifier)
			var hp_before := actor.hp
			var hp_after := mini(actor.max_hp, hp_before + amount)
			_append_and_apply(result, working, Event.create(&"healing_received", {"actor_id": actor.id, "amount": hp_after - hp_before, "hp_before": hp_before, "hp_after": hp_after, "rolls": roll["values"]}))
		EFFECT_CONSUME_ITEM:
			_append_and_apply(result, working, Event.create(&"item_consumed", {"actor_id": actor.id, "item_id": effect.consumes_item_id}))
		EFFECT_FORCED_MOVEMENT:
			if target == null or nav == null:
				return
			var direction := actor.position.direction_to(target.position)
			var projection := nav.project_push(target.position, direction, effect.forced_distance_meters)
			if bool(projection.get("blocked", true)):
				_append_and_apply(result, working, Event.create(&"forced_movement_blocked", {"actor_id": actor.id, "target_id": target.id, "from": target.position, "mode": effect.mode}))
				return
			var landing: Vector3 = projection.get("landing_position", target.position)
			_append_and_apply(result, working, Event.create(&"forced_movement", {"actor_id": target.id, "source_actor_id": actor.id, "from": target.position, "to": landing, "distance": target.position.distance_to(landing)}))
			var fall_distance := float(projection.get("fall_distance", 0.0))
			var fall := JumpRulesScript.forced_fall_outcome(fall_distance)
			if bool(projection.get("fell", false)) and int(fall["dice"]) > 0:
				_append_fall(result, working, target, actor.id, target.position, landing, fall_distance, fall, true, false)
		EFFECT_TOGGLE_SNEAK:
			if actor.sneaking:
				_append_and_apply(result, working, Event.create(&"sneaking_changed", {"actor_id": actor.id, "sneaking": false, "stealth_total": 0}))
				for observer_id in actor.hidden_from.duplicate():
					_append_and_apply(result, working, Event.create(&"detection_changed", {"actor_id": actor.id, "observer_id": observer_id, "hidden": false, "reason": &"sneak_ended"}))
				return
			var roll := AbilityCheckRules.resolve(working.rng_state, actor, &"dexterity", 1, actor.skill_proficiencies.has(&"stealth"))
			working.rng_state = int(roll["next_rng_state"])
			var stealth_total := int(roll["total"])
			_append_and_apply(result, working, Event.create(&"stealth_rolled", {"actor_id": actor.id, "roll": roll["roll"], "rolls": roll["rolls"], "modifier": roll["modifier"], "total": stealth_total, "proficient": actor.skill_proficiencies.has(&"stealth")}))
			_append_and_apply(result, working, Event.create(&"sneaking_changed", {"actor_id": actor.id, "sneaking": true, "stealth_total": stealth_total}))
			if los != null:
				var observer_ids: Array = working.actors.keys()
				observer_ids.sort()
				for observer_id in observer_ids:
					var observer := working.actors[observer_id] as ActorState
					if observer.id == actor.id or observer.side == actor.side or not observer.is_conscious() or observer.disposition != &"hostile":
						continue
					var can_contest := observer.position.distance_to(actor.position) <= DetectionRulesScript.DETECTION_RANGE_METERS and los.has_line_of_sight(observer.position, actor.position)
					var hidden := not can_contest or not DetectionRulesScript.detected_by(observer, stealth_total)
					_append_and_apply(result, working, Event.create(&"detection_changed", {"actor_id": actor.id, "observer_id": observer.id, "hidden": hidden, "stealth_total": stealth_total, "passive_perception": observer.passive_perception()}))
		EFFECT_AREA_DAMAGE:
			_resolve_area_damage(result, working, actor, effect, context)
		_:
			push_error("Unknown ability effect type: %s" % effect.type)


static func _resolve_area_damage(result: ResolutionResult, working: BattleState, source: ActorState, effect: AbilityEffect, context: Dictionary) -> void:
	var center: Vector3 = context.get("target_position", source.position)
	var radius := float(context.get("target_radius", 0.0))
	var interactable_id := str(context.get("target_interactable_id", ""))
	var damage_die := int(context.get("damage_die_override", 0))
	var damage_dice_count := int(context.get("damage_dice_count_override", 0))
	if damage_die <= 0:
		damage_die = effect.damage_die
	if damage_dice_count <= 0:
		damage_dice_count = effect.damage_dice_count
	var damage_roll := Dice.roll_dice(working.rng_state, damage_dice_count, damage_die)
	working.rng_state = int(damage_roll["next_rng_state"])
	var rolled_damage := maxi(0, int(damage_roll["total"]) + effect.damage_modifier)
	_append_and_apply(result, working, Event.create(&"explosion_triggered", {"actor_id": source.id, "interactable_id": interactable_id, "position": center, "radius": radius, "damage_die": damage_die, "damage_dice_count": damage_dice_count, "damage_rolls": damage_roll["values"], "damage": rolled_damage}))
	if not interactable_id.is_empty():
		_append_and_apply(result, working, Event.create(&"interactable_destroyed", {"actor_id": source.id, "interactable_id": interactable_id, "reason": &"explosion"}))
	var actor_ids: Array = working.actors.keys()
	actor_ids.sort()
	for actor_id in actor_ids:
		var target := working.actors[actor_id] as ActorState
		if not target.is_alive() or target.position.distance_to(center) > radius + MOVEMENT_EPSILON:
			continue
		var difficulty_class := effect.save_dc_base + source.proficiency_bonus + source.ability_modifier(effect.save_dc_ability)
		var modifier := target.saving_throw_modifier(&"dexterity")
		var save := D20Test.roll(working.rng_state, modifier, difficulty_class)
		working.rng_state = int(save["next_rng_state"])
		_append_and_apply(result, working, Event.create(&"d20_test_rolled", {"test_type": &"saving_throw", "actor_id": target.id, "source_actor_id": source.id, "ability": &"dexterity", "difficulty_class": difficulty_class, "roll": save["roll"], "rolls": save["rolls"], "modifier": modifier, "ability_modifier": target.ability_modifier(&"dexterity"), "proficient": target.saving_throw_proficiencies.has(&"dexterity"), "proficiency_bonus": target.proficiency_bonus if target.saving_throw_proficiencies.has(&"dexterity") else 0, "total": save["total"], "success": save["success"], "advantage": false, "disadvantage": false}))
		var damage := floori(float(rolled_damage) * 0.5) if bool(save["success"]) and effect.half_damage_on_save else rolled_damage
		_append_damage_and_consequence(result, working, target, source.id, damage, effect.damage_type, {"area": true, "saved": save["success"]})


static func _effect_should_apply(requirement: StringName, context: Dictionary) -> bool:
	match requirement:
		&"failed_save": return not bool(context.get("save_succeeded", false))
		&"successful_save": return bool(context.get("save_succeeded", false))
		&"attack_hit": return bool(context.get("attack_hit", false))
		&"attack_miss": return not bool(context.get("attack_hit", false))
		_: return true


static func _resolve_saving_throw(working: BattleState, source: ActorState, target: ActorState, effect: AbilityEffect, result: ResolutionResult) -> bool:
	if target == null or effect.save_abilities.is_empty():
		return false
	var selected_ability: StringName = effect.save_abilities[0]
	var modifier := target.saving_throw_modifier(selected_ability)
	for ability in effect.save_abilities.slice(1):
		var candidate_modifier := target.saving_throw_modifier(ability)
		if candidate_modifier > modifier:
			selected_ability = ability
			modifier = candidate_modifier
	var difficulty_class := effect.save_dc_base + source.proficiency_bonus + source.ability_modifier(effect.save_dc_ability)
	var ability_modifier := target.ability_modifier(selected_ability)
	var proficient := target.saving_throw_proficiencies.has(selected_ability)
	var rng_state_before := working.rng_state
	var rolled := D20Test.roll(working.rng_state, modifier, difficulty_class)
	working.rng_state = int(rolled["next_rng_state"])
	_append_and_apply(result, working, Event.create(&"d20_test_rolled", {
		"test_type": &"saving_throw", "actor_id": target.id, "source_actor_id": source.id,
		"ability": selected_ability, "difficulty_class": difficulty_class,
		"roll": rolled["roll"], "rolls": rolled["rolls"], "modifier": modifier,
		"ability_modifier": ability_modifier, "proficient": proficient,
		"proficiency_bonus": target.proficiency_bonus if proficient else 0,
		"total": rolled["total"], "success": rolled["success"],
		"advantage": rolled["advantage"], "disadvantage": rolled["disadvantage"],
		"rng_state_before": rng_state_before, "next_rng_state": working.rng_state,
	}))
	return bool(rolled["success"])


static func _resolve_attack_between(working: BattleState, attacker: ActorState, target: ActorState, los: LosProvider, definitions: DefinitionLibrary, result: ResolutionResult, spends_action: bool, spends_reaction: bool, attack_kind: StringName, attack_range: float = ATTACK_RANGE_METERS, is_ranged: bool = false, normal_range: float = ATTACK_RANGE_METERS, weapon_override: ItemDefinition = null, offhand_attack: bool = false) -> bool:
	if not los.has_line_of_sight(attacker.position, target.position) or attacker.position.distance_to(target.position) > attack_range + MOVEMENT_EPSILON:
		return false
	var cover := los.cover_between(attacker.position, target.position)
	var attack := AttackMathRules.evaluate(working, attacker, target, definitions, cover, is_ranged, normal_range, weapon_override, offhand_attack)
	var roll_result := _roll_attack_d20(working.rng_state, attack["advantage"], attack["disadvantage"])
	var roll: int = roll_result["roll"]
	var attack_bonus: int = attack["attack_bonus"]
	var critical := AttackMathRules.is_critical(roll)
	var hit := AttackMathRules.is_hit(roll, attack_bonus, attack["armor_class"])
	_append_and_apply(result, working, Event.create(&"attack_rolled", {
		"actor_id": attacker.id, "target_id": target.id, "attack_kind": attack_kind,
		"roll": roll, "rolls": roll_result["rolls"], "attack_bonus": attack_bonus, "total": roll + attack_bonus,
		"weapon_id": attack["weapon_id"], "attack_ability": attack["attack_ability"],
		"ability_modifier": attack["ability_modifier"], "proficiency_bonus": attack["proficiency_bonus"], "magic_bonus": attack["magic_bonus"],
		"armor_class": attack["armor_class"], "target_armor_class": attack["target_armor_class"],
		"critical": critical, "hit": hit, "advantage": attack["advantage"], "disadvantage": attack["disadvantage"],
		"advantage_sources": attack["advantage_sources"], "disadvantage_sources": attack["disadvantage_sources"], "is_ranged": is_ranged,
		"cover": cover, "cover_bonus": attack["cover_bonus"],
		"elevation_modifier": attack["elevation_modifier"], "elevation_source": attack["elevation_source"],
		"condition_consumptions": attack["condition_consumptions"].duplicate(true),
		"action_spent": spends_action, "reaction_spent": spends_reaction,
	}))
	working.rng_state = roll_result["next_rng_state"]
	if hit:
		var dice_count := AttackMathRules.damage_dice_count(attack, critical)
		var die_values: Array = []
		if dice_count > 0:
			var damage_roll := Dice.roll_dice(working.rng_state, dice_count, attack["damage_die"])
			working.rng_state = int(damage_roll["next_rng_state"])
			die_values = damage_roll["values"]
		var damage := AttackMathRules.damage_total(die_values, attack["damage_modifier"])
		_append_damage_and_consequence(result, working, target, attacker.id, damage, attack["damage_type"])
	for consumption in attack["condition_consumptions"]:
		if not _should_consume_attack_condition(StringName(str(consumption["consumption"])), hit):
			continue
		_append_and_apply(result, working, Event.create(&"condition_consumed", {
			"actor_id": int(consumption["condition_actor_id"]),
			"condition_actor_id": int(consumption["condition_actor_id"]),
			"condition": consumption["condition"],
			"source_actor_id": int(consumption.get("source_actor_id", -1)),
			"related_actor_id": int(consumption.get("related_actor_id", -1)),
			"attack_actor_id": attacker.id,
			"attack_target_id": target.id,
			"attack_hit": hit,
		}))
	if attacker.hidden_from.has(target.id):
		_append_and_apply(result, working, Event.create(&"hidden_revealed", {"actor_id": attacker.id, "target_id": target.id, "reason": &"attack"}))
	_resolve_weapon_mastery(working, attacker, target, attack, hit, los, definitions, result, attack_kind)
	result.next_rng_state = working.rng_state
	return hit


static func _resolve_weapon_mastery(working: BattleState, attacker: ActorState, target: ActorState, attack: Dictionary, hit: bool, los: LosProvider, definitions: DefinitionLibrary, result: ResolutionResult, attack_kind: StringName) -> void:
	var weapon := definitions.get_item(StringName(str(attack.get("weapon_id", ""))))
	if weapon == null or weapon.mastery == &"":
		return
	match weapon.mastery:
		MasteryRulesScript.SAP:
			if hit:
				_append_and_apply(result, working, Event.create(&"mastery_triggered", {"actor_id": attacker.id, "target_id": target.id, "mastery": weapon.mastery, "weapon_id": weapon.id}))
				_append_and_apply(result, working, Event.create(&"condition_added", {"actor_id": target.id, "condition": &"sapped", "source_actor_id": attacker.id, "remaining_triggers": -1, "expiration_timing": &"none", "related_actor_id": -1}))
		MasteryRulesScript.VEX:
			if hit:
				_append_and_apply(result, working, Event.create(&"mastery_triggered", {"actor_id": attacker.id, "target_id": target.id, "mastery": weapon.mastery, "weapon_id": weapon.id}))
				_append_and_apply(result, working, Event.create(&"condition_added", {"actor_id": target.id, "condition": &"vexed", "source_actor_id": attacker.id, "remaining_triggers": -1, "expiration_timing": &"none", "related_actor_id": attacker.id}))
		MasteryRulesScript.GRAZE:
			if not hit:
				var graze_damage := maxi(0, int(attack.get("ability_modifier", 0)))
				_append_and_apply(result, working, Event.create(&"mastery_triggered", {"actor_id": attacker.id, "target_id": target.id, "mastery": weapon.mastery, "weapon_id": weapon.id, "amount": graze_damage}))
				if graze_damage > 0:
					_append_damage_and_consequence(result, working, target, attacker.id, graze_damage, weapon.damage_type, {"mastery": weapon.mastery})
		MasteryRulesScript.TOPPLE:
			if hit and target.is_alive():
				_append_and_apply(result, working, Event.create(&"mastery_triggered", {"actor_id": attacker.id, "target_id": target.id, "mastery": weapon.mastery, "weapon_id": weapon.id}))
				var save_effect := AbilityEffect.new()
				save_effect.save_abilities = [&"constitution"]
				save_effect.save_dc_base = 8
				save_effect.save_dc_ability = StringName(str(attack.get("attack_ability", "strength")))
				if not _resolve_saving_throw(working, attacker, target, save_effect, result):
					_append_and_apply(result, working, Event.create(&"condition_added", {"actor_id": target.id, "condition": &"prone", "source_actor_id": attacker.id, "remaining_triggers": -1, "expiration_timing": &"none", "related_actor_id": -1}))
		MasteryRulesScript.NICK:
			pass
	if attack_kind != &"nick" and MasteryRulesScript.can_nick_attack(attacker, definitions) and target.is_alive():
		var offhand := EquipmentRules.offhand(attacker, definitions)
		_append_and_apply(result, working, Event.create(&"ability_use_spent", {"actor_id": attacker.id, "ability_id": &"nick_attack", "uses_spent": 1, "uses_remaining": 0}))
		_append_and_apply(result, working, Event.create(&"mastery_triggered", {"actor_id": attacker.id, "target_id": target.id, "mastery": MasteryRulesScript.NICK, "weapon_id": offhand.id}))
		_resolve_attack_between(working, attacker, target, los, definitions, result, false, false, &"nick", ATTACK_RANGE_METERS, false, ATTACK_RANGE_METERS, offhand, true)


static func _should_consume_attack_condition(consumption: StringName, hit: bool) -> bool:
	match consumption:
		&"attack_hit": return hit
		&"attack_miss": return not hit
		_: return true


## Damage consequences are shared by weapon hits, masteries, falls, and area
## effects so a new damage source cannot silently leave a zero-HP actor active.
static func _append_damage_and_consequence(result: ResolutionResult, working: BattleState, target: ActorState, source_actor_id: int, amount: int, damage_type: StringName, extra: Dictionary = {}) -> void:
	var hp_before := target.hp
	var damage_data := {"actor_id": target.id, "source_actor_id": source_actor_id, "amount": amount, "damage_type": damage_type}
	damage_data.merge(extra, true)
	_append_and_apply(result, working, Event.create(&"damage_taken", damage_data))
	if hp_before - amount <= -target.max_hp:
		_append_and_apply(result, working, Event.create(&"actor_died", {"actor_id": target.id}))
	elif hp_before - amount <= 0:
		_append_and_apply(result, working, Event.create(&"actor_downed", {"actor_id": target.id}))


## Rolls the attack d20, twice when the already-evaluated roll mode calls for
## Advantage or Disadvantage. Which mode applies is AttackMath's decision.
static func _roll_attack_d20(rng_state: int, advantage: bool, disadvantage: bool) -> Dictionary:
	var first_roll := Dice.roll_die(rng_state, 20)
	var rolls: Array[int] = [int(first_roll["value"])]
	var next_rng_state: int = first_roll["next_rng_state"]
	var selected_roll: int = rolls[0]
	if advantage or disadvantage:
		var second_roll := Dice.roll_die(next_rng_state, 20)
		rolls.append(int(second_roll["value"]))
		next_rng_state = second_roll["next_rng_state"]
		selected_roll = maxi(rolls[0], rolls[1]) if advantage else mini(rolls[0], rolls[1])
	return {"roll": selected_roll, "rolls": rolls, "next_rng_state": next_rng_state}


static func _resolve_end_turn(state: BattleState, cmd: Command, result: ResolutionResult, definitions: DefinitionLibrary) -> ResolutionResult:
	if state.initiative_order.is_empty(): return _rejected(result, cmd, RejectionReasonRules.NO_INITIATIVE_ORDER)
	var next_index := TurnOrderRules.next_eligible_index(state, state.current_turn_index)
	if next_index < 0: return _rejected(result, cmd, RejectionReasonRules.NO_ELIGIBLE_ACTORS)
	var next_round := state.round_number + (1 if next_index <= state.current_turn_index else 0)
	var skipped := 0
	while next_round == 1 and state.skip_round_one_actor_ids.has(state.initiative_order[next_index]) and skipped < state.initiative_order.size():
		result.events.append(Event.create(&"surprise_turn_skipped", {"actor_id": state.initiative_order[next_index], "round_number": 1}))
		next_index = TurnOrderRules.next_eligible_index(state, next_index)
		next_round = state.round_number + (1 if next_index <= state.current_turn_index else 0)
		skipped += 1
	var next_actor: ActorState = state.actors[state.initiative_order[next_index]]
	result.events.append(Event.create(&"turn_ended", {"actor_id": cmd.actor_id}))
	_append_condition_boundary_events(result, next_actor, &"turn_start")
	result.events.append(_turn_started_event(next_actor, next_index, next_round))
	# BG3-style: a prone actor rights itself as soon as its turn starts, paying
	# the same half-Speed cost a move would, so it never fights from the ground.
	# With no Speed it cannot stand and simply stays prone (SRD Prone).
	var standing_condition := _condition_requiring_stand(next_actor, definitions)
	if standing_condition != &"" and next_actor.movement_speed > MOVEMENT_EPSILON:
		var working := state.clone()
		for resolved_event in result.events:
			apply(working, resolved_event)
		_append_stand_up(result, working, next_actor.id, standing_condition)
	return result


## Emits the stand-up pair shared by a prone move and a prone turn start: the
## condition ends, then half the actor's Speed is spent. Callers check the cost.
static func _append_stand_up(result: ResolutionResult, working: BattleState, actor_id: int, condition_id: StringName) -> void:
	_append_and_apply(result, working, Event.create(&"condition_removed", {"actor_id": actor_id, "condition": condition_id}))
	_append_movement_spent(result, working, actor_id, _stand_cost(working.actors[actor_id]))


static func _stand_cost(actor: ActorState) -> float:
	return actor.movement_speed * 0.5


## Exploration moves never pay the stand cost, so a conscious combatant still
## prone when combat ends gets up for free rather than staying down forever.
static func _append_combat_end_stand_ups(result: ResolutionResult, state: BattleState, definitions: DefinitionLibrary) -> void:
	for actor_id in state.active_combatant_ids:
		var actor := state.actors.get(actor_id) as ActorState
		if actor == null or not actor.is_conscious():
			continue
		var standing_condition := _condition_requiring_stand(actor, definitions)
		if standing_condition != &"":
			result.events.append(Event.create(&"condition_removed", {"actor_id": actor.id, "condition": standing_condition}))


static func _append_condition_boundary_events(result: ResolutionResult, actor: ActorState, timing: StringName) -> void:
	for condition in actor.condition_states:
		if condition.expiration_timing != timing or condition.remaining_triggers < 0:
			continue
		if condition.remaining_triggers <= 1:
			result.events.append(Event.create(&"condition_removed", {"actor_id": actor.id, "condition": condition.definition_id}))
		else:
			result.events.append(Event.create(&"condition_duration_advanced", {
				"actor_id": actor.id,
				"condition": condition.definition_id,
				"remaining_triggers": condition.remaining_triggers - 1,
			}))


static func _turn_started_event(actor: ActorState, turn_index: int, round_number: int) -> Event:
	return Event.create(&"turn_started", {"actor_id": actor.id, "turn_index": turn_index, "round_number": round_number, "phase": EncounterRules.COMBAT, "movement_remaining": actor.movement_speed, "action_available": true, "bonus_action_available": true, "reaction_available": true, "disengaged": false})


static func _condition_requiring_stand(actor: ActorState, definitions: DefinitionLibrary) -> StringName:
	for condition_id in actor.condition_ids():
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
		if not state.active_combatant_ids.is_empty() and not state.active_combatant_ids.has(int(actor_id_variant)):
			continue
		var enemy: ActorState = state.actors[actor_id_variant]
		if enemy.id == mover.id or enemy.side == mover.side or not enemy.can_take_reactions() or not enemy.reaction_available: continue
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
	var stable_amount := snappedf(amount, 0.000001)
	_append_and_apply(result, working, Event.create(&"movement_spent", {"actor_id": actor_id, "amount": stable_amount, "path_cost": stable_amount, "movement_remaining_before": snappedf(actor.movement_remaining, 0.000001), "movement_remaining_after": snappedf(maxf(0.0, actor.movement_remaining - stable_amount), 0.000001)}))


static func _append_and_apply(result: ResolutionResult, working: BattleState, event: Event) -> void:
	result.events.append(event)
	apply(working, event)


static func _rejected(result: ResolutionResult, cmd: Command, reason: StringName) -> ResolutionResult:
	result.events.append(Event.create(&"command_rejected", {"actor_id": cmd.actor_id, "command_type": cmd.type, "reason": reason}))
	return result


static func _finalize_resolution(state: BattleState, cmd: Command, result: ResolutionResult, definitions: DefinitionLibrary) -> ResolutionResult:
	if result.events.is_empty() or result.events[0].type == &"command_rejected":
		return result
	var working := state.clone()
	for resolved_event in result.events:
		apply(working, resolved_event)
	working.rng_state = result.next_rng_state
	if state.phase == EncounterRules.COMBAT and working.phase == EncounterRules.COMBAT:
		var outcome := EncounterRules.resolved_outcome(working)
		if outcome != EncounterRules.OUTCOME_NONE:
			_append_combat_end_stand_ups(result, working, definitions)
			_append_encounter_outcome(result, working, outcome)
			return result
	if cmd.type == &"move" and working.phase == EncounterRules.EXPLORATION and working.game_outcome == &"ongoing":
		_append_reached_objectives(result, working, cmd.actor_id)
	return result


static func _append_encounter_outcome(result: ResolutionResult, working: BattleState, outcome: StringName) -> void:
	var defeated_actor_ids: Array[int] = []
	for actor_id in working.active_combatant_ids:
		if working.actors.has(actor_id) and not (working.actors[actor_id] as ActorState).is_conscious():
			defeated_actor_ids.append(actor_id)
	var winning_side := &"enemies" if outcome == EncounterRules.OUTCOME_DEFEAT else &"heroes"
	result.events.append(Event.create(&"encounter_resolved", {
		"encounter_id": working.active_encounter_id,
		"outcome": outcome,
		"winning_side": winning_side,
		"defeated_actor_ids": defeated_actor_ids,
	}))
	result.events.append(Event.create(&"combat_ending", {"phase": EncounterRules.COMBAT_ENDING}))
	var next_phase := EncounterRules.GAME_OVER if outcome == EncounterRules.OUTCOME_DEFEAT else EncounterRules.EXPLORATION
	result.events.append(Event.create(&"combat_ended", {
		"phase": next_phase,
		"next_phase": next_phase,
		"outcome": outcome,
		"initiative_order": [],
		"current_turn_index": 0,
		"round_number": 1,
	}))
	if outcome == EncounterRules.OUTCOME_DEFEAT:
		result.events.append(Event.create(&"game_over", {"outcome": outcome, "defeated_actor_ids": defeated_actor_ids}))


static func _append_reached_objectives(result: ResolutionResult, working: BattleState, actor_id: int) -> void:
	if not working.actors.has(actor_id) or (working.actors[actor_id] as ActorState).side != &"heroes":
		return
	var actor: ActorState = working.actors[actor_id]
	var objective_ids: Array = working.objectives.keys()
	objective_ids.sort()
	for objective_id in objective_ids:
		var objective: ObjectiveState = working.objectives[objective_id]
		if objective.completed or not objective.requirements_met(working.cleared_encounter_ids):
			continue
		if actor.position.distance_to(objective.position) > objective.radius_m:
			continue
		var completed := Event.create(&"objective_completed", {"objective_id": objective.id, "actor_id": actor_id})
		result.events.append(completed)
		apply(working, completed)
	if working.objectives.is_empty():
		return
	for objective in working.objectives.values():
		if not (objective as ObjectiveState).completed:
			return
	result.events.append(Event.create(&"game_completed", {"outcome": EncounterRules.OUTCOME_VICTORY, "phase": EncounterRules.GAME_OVER}))


static func apply(state: BattleState, event: Event) -> void:
	match event.type:
		&"movement_segment":
			var walker := state.actors[event.data["actor_id"]] as ActorState
			walker.run_up_m += PolylineUtil.length(event.data.get("path", PackedVector3Array([walker.position, event.data["to"]])))
			walker.position = event.data["to"]
		&"forced_movement", &"jump_performed":
			# Landing from a leap or a shove is not movement on foot: the next
			# jump needs a fresh run-up.
			var flier := state.actors[event.data["actor_id"]] as ActorState
			flier.position = event.data["to"]
			flier.run_up_m = 0.0
		&"hidden_revealed": (state.actors[event.data["actor_id"]] as ActorState).hidden_from.erase(int(event.data["target_id"]))
		&"sneaking_changed":
			var sneaking_actor := state.actors[event.data["actor_id"]] as ActorState
			sneaking_actor.sneaking = bool(event.data["sneaking"])
			sneaking_actor.stealth_total = int(event.data.get("stealth_total", 0))
		&"detection_changed":
			var detected_actor := state.actors[event.data["actor_id"]] as ActorState
			var observer_id := int(event.data["observer_id"])
			if bool(event.data.get("hidden", false)):
				if not detected_actor.hidden_from.has(observer_id):
					detected_actor.hidden_from.append(observer_id)
					detected_actor.hidden_from.sort()
			else:
				detected_actor.hidden_from.erase(observer_id)
		&"movement_spent":
			var moving_actor: ActorState = state.actors[event.data["actor_id"]]
			moving_actor.movement_remaining = maxf(0.0, moving_actor.movement_remaining - event.data["amount"])
		&"movement_gained": (state.actors[event.data["actor_id"]] as ActorState).movement_remaining += event.data["amount"]
		# Stopping to act breaks a run-up: the SRD wants the 3 m immediately
		# before the jump.
		&"action_spent":
			(state.actors[event.data["actor_id"]] as ActorState).action_available = false
			(state.actors[event.data["actor_id"]] as ActorState).run_up_m = 0.0
		&"bonus_action_spent":
			(state.actors[event.data["actor_id"]] as ActorState).bonus_action_available = false
			(state.actors[event.data["actor_id"]] as ActorState).run_up_m = 0.0
		&"disengage_applied": (state.actors[event.data["actor_id"]] as ActorState).disengaged = true
		&"disposition_changed": (state.actors[event.data["actor_id"]] as ActorState).disposition = StringName(str(event.data["disposition"]))
		&"actor_surrendered":
			var surrendering_actor := state.actors[event.data["actor_id"]] as ActorState
			surrendering_actor.disposition = &"neutral"
			surrendering_actor.surrendered = true
			surrendering_actor.action_available = false
		&"reaction_triggered": (state.actors[event.data["actor_id"]] as ActorState).reaction_available = false
		&"attack_rolled":
			var attacking_actor: ActorState = state.actors[event.data["actor_id"]]
			attacking_actor.run_up_m = 0.0
			if event.data["action_spent"]: attacking_actor.action_available = false
			if event.data.get("reaction_spent", false): attacking_actor.reaction_available = false
		&"damage_taken": (state.actors[event.data["actor_id"]] as ActorState).hp = max(0, (state.actors[event.data["actor_id"]] as ActorState).hp - event.data["amount"])
		&"healing_received": (state.actors[event.data["actor_id"]] as ActorState).hp = mini((state.actors[event.data["actor_id"]] as ActorState).max_hp, (state.actors[event.data["actor_id"]] as ActorState).hp + int(event.data["amount"]))
		&"item_consumed": (state.actors[event.data["actor_id"]] as ActorState).inventory.erase(StringName(str(event.data["item_id"])))
		&"coins_transferred":
			(state.actors[event.data["actor_id"]] as ActorState).coins = int(event.data["payer_coins_after"])
			(state.actors[event.data["target_id"]] as ActorState).coins = int(event.data["recipient_coins_after"])
		&"ability_use_spent": (state.actors[event.data["actor_id"]] as ActorState).ability_uses_spent[StringName(str(event.data["ability_id"]))] = int(event.data["uses_spent"])
		&"actor_downed":
			var downed_actor: ActorState = state.actors[event.data["actor_id"]]
			downed_actor.add_condition(&"unconscious")
		&"actor_died":
			var dead_actor: ActorState = state.actors[event.data["actor_id"]]
			dead_actor.hp = 0
			dead_actor.add_condition(&"dead")
		&"condition_added":
			var conditioned_actor: ActorState = state.actors[event.data["actor_id"]]
			var added := StringName(str(event.data["condition"]))
			conditioned_actor.add_condition(
				added,
				int(event.data.get("source_actor_id", -1)),
				int(event.data.get("remaining_triggers", -1)),
				StringName(str(event.data.get("expiration_timing", "none"))),
				int(event.data.get("related_actor_id", -1)),
				)
		&"condition_consumed":
			var consumed_actor: ActorState = state.actors[event.data["condition_actor_id"]]
			var consumed_condition := StringName(str(event.data["condition"]))
			var consumed_state := consumed_actor.condition_state(consumed_condition)
			if consumed_state != null and (
				int(event.data.get("related_actor_id", -1)) < 0
				or consumed_state.related_actor_id == int(event.data.get("related_actor_id", -1))
			):
				consumed_actor.remove_condition(consumed_condition)
		&"condition_duration_advanced":
			var duration_actor: ActorState = state.actors[event.data["actor_id"]]
			var duration_state := duration_actor.condition_state(StringName(str(event.data["condition"])))
			if duration_state != null:
				duration_state.remaining_triggers = int(event.data["remaining_triggers"])
		&"condition_removed": (state.actors[event.data["actor_id"]] as ActorState).remove_condition(StringName(str(event.data["condition"])))
		&"interaction_completed":
			var interactable: InteractableState = state.interactables[event.data["interactable_id"]]
			interactable.state = event.data["new_state"]
		&"interactable_destroyed":
			var destroyed_interactable := state.interactables[event.data["interactable_id"]] as InteractableState
			destroyed_interactable.destroyed = true
			destroyed_interactable.state = &"destroyed"
		&"items_looted":
			var looter: ActorState = state.actors[event.data["actor_id"]]
			for item_id in event.data["item_ids"]:
				looter.inventory.append(StringName(str(item_id)))
			(state.interactables[event.data["interactable_id"]] as InteractableState).contents.clear()
		&"combat_started":
			state.phase = event.data["phase"]
			state.active_encounter_id = str(event.data.get("encounter_id", ""))
			state.active_combatant_ids = _actor_ids(event.data.get("combatant_ids", []))
			state.last_encounter_outcome = EncounterRules.OUTCOME_NONE
			# There is no rest system, so entering an encounter stands in for the
			# SRD short rest and refills every per-encounter pool. Recorded as a
			# deviation in docs/third_party/NOTICE.md.
			for combatant_id in state.active_combatant_ids:
				if state.actors.has(combatant_id):
					(state.actors[combatant_id] as ActorState).ability_uses_spent.clear()
		&"combat_ending": state.phase = event.data["phase"]
		&"encounter_resolved":
			state.last_encounter_outcome = StringName(str(event.data["outcome"]))
			var resolved_encounter_id := str(event.data.get("encounter_id", ""))
			if state.last_encounter_outcome == EncounterRules.OUTCOME_VICTORY and not resolved_encounter_id.is_empty() and not state.cleared_encounter_ids.has(resolved_encounter_id):
				state.cleared_encounter_ids.append(resolved_encounter_id)
		&"encounter_cleared":
			var cleared_encounter_id := str(event.data.get("encounter_id", ""))
			if not cleared_encounter_id.is_empty() and not state.cleared_encounter_ids.has(cleared_encounter_id):
				state.cleared_encounter_ids.append(cleared_encounter_id)
		&"initiative_established":
			state.initiative_order = _actor_ids(event.data["initiative_order"])
			state.current_turn_index = event.data["current_turn_index"]
			state.round_number = event.data["round_number"]
			state.skip_round_one_actor_ids = _actor_ids(event.data.get("skip_round_one_actor_ids", []))
		&"game_over": state.game_outcome = StringName(str(event.data.get("outcome", "defeat")))
		&"objective_completed":
			var objective := state.objectives.get(str(event.data["objective_id"])) as ObjectiveState
			if objective != null:
				objective.completed = true
		&"game_completed":
			state.game_outcome = StringName(str(event.data.get("outcome", "victory")))
			state.phase = StringName(str(event.data.get("phase", EncounterRules.GAME_OVER)))
		&"combat_ended":
			state.phase = event.data["phase"]
			state.initiative_order = _actor_ids(event.data["initiative_order"])
			state.current_turn_index = event.data["current_turn_index"]
			state.round_number = event.data["round_number"]
			state.active_encounter_id = ""
			state.active_combatant_ids.clear()
			state.skip_round_one_actor_ids.clear()
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
			turn_actor.run_up_m = 0.0
			turn_actor.ability_uses_spent.erase(&"nick_attack")
			_recharge_per_turn_uses(turn_actor)


## Drops the spent entries for abilities whose pool refills every turn, leaving
## per-encounter pools alone. Reads definitions the same way ActorState does for
## condition flags, so the apply path stays free of a definitions parameter.
static func _recharge_per_turn_uses(actor: ActorState) -> void:
	if actor.ability_uses_spent.is_empty():
		return
	var definitions := DefinitionLibrary.get_default()
	for ability_id in actor.ability_uses_spent.keys():
		var ability := definitions.get_ability(ability_id)
		if ability != null and ability.uses_recharge == &"turn":
			actor.ability_uses_spent.erase(ability_id)


static func _actor_ids(data: Array) -> Array[int]:
	var actor_ids: Array[int] = []
	for actor_id in data: actor_ids.append(int(actor_id))
	return actor_ids
