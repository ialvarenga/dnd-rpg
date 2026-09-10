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
const RULES_VERSION: int = 8

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

const EFFECT_ADD_BASE_MOVEMENT := &"add_base_movement"
const EFFECT_APPLY_CONDITION := &"apply_condition"
const EFFECT_REMOVE_CONDITION := &"remove_condition"
const EFFECT_APPLY_DISENGAGE := &"apply_disengage"
const EFFECT_PERFORM_ATTACK := &"perform_attack"
const EFFECT_SAVING_THROW := &"saving_throw"
const EFFECT_HEAL := &"heal"
const EFFECT_CONSUME_ITEM := &"consume_item"
const EFFECT_START_DIALOG := &"start_dialog"

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
	# Abilities resolve their own phase gate, because one may declare
	# usable_in_exploration. Everything else stays behind the combat turn gate,
	# in the same order as before.
	var ability_id := AbilityRoutingRules.ability_id_for_command(cmd.type) if AbilityRoutingRules.is_ability_command(cmd.type) else (cmd.type if definitions.has_ability(cmd.type) else &"")
	if ability_id != &"":
		var ability_rejection := CommandPhaseRulesScript.rejection_for_ability(state, cmd.actor_id, definitions.get_ability(ability_id))
		if ability_rejection != &"":
			return _rejected(result, cmd, ability_rejection)
		return _resolve_ability_command(state, cmd, los, definitions, result, ability_id)
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
	var initiative := InitiativeRules.resolve_for_actor_ids(state, requested_participants)
	var order: Array[int] = initiative["order"]
	if order.is_empty():
		return _rejected(result, cmd, RejectionReasonRules.NO_ELIGIBLE_ACTORS)
	var first_actor: ActorState = state.actors[order[0]]
	result.events.append(Event.create(&"combat_started", {
		"initiator_actor_id": cmd.actor_id,
		"phase": EncounterRules.COMBAT_STARTING,
		"encounter_id": encounter_id,
		"combatant_ids": requested_participants.duplicate(),
	}))
	result.events.append(Event.create(&"initiative_established", {"initiative_order": order, "initiative_rolls": initiative["entries"], "current_turn_index": 0, "round_number": 1}))
	result.events.append(_turn_started_event(first_actor, 0, 1))
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
	if not interactable.contents.is_empty():
		result.events.append(Event.create(&"items_looted", {"actor_id": actor.id, "interactable_id": interactable.id, "item_ids": interactable.contents.duplicate()}))
	return result


static func _resolve_ability_command(state: BattleState, cmd: Command, los: LosProvider, definitions: DefinitionLibrary, result: ResolutionResult, ability_id: StringName) -> ResolutionResult:
	var actor: ActorState = state.actors[cmd.actor_id]
	var conscious_rejection := CommandPhaseRulesScript.rejection_for_conscious(actor)
	if conscious_rejection != &"": return _rejected(result, cmd, conscious_rejection)
	var ability := definitions.get_ability(ability_id)
	if ability == null: return _rejected(result, cmd, RejectionReasonRules.UNKNOWN_ABILITY_DEFINITION)
	var cost_rejection := AbilityCostRulesScript.rejection_for_cost(actor, ability, definitions)
	if cost_rejection != &"": return _rejected(result, cmd, cost_rejection)
	var target: ActorState = null
	if ability.targeting == &"actor":
		if not state.actors.has(cmd.target_id): return _rejected(result, cmd, RejectionReasonRules.UNKNOWN_TARGET)
		target = state.actors[cmd.target_id]
		if cmd.target_id == cmd.actor_id or actor.side == target.side or not target.is_alive():
			return _rejected(result, cmd, RejectionReasonRules.INVALID_TARGET)
		var authored_range := AbilityTargetingRules.target_range(definitions, ability.id)
		var command_range := maxf(authored_range, float(cmd.metadata.get("range_meters", authored_range)))
		if actor.position.distance_to(target.position) > command_range + MOVEMENT_EPSILON:
			return _rejected(result, cmd, RejectionReasonRules.TARGET_OUT_OF_RANGE)
		if los.cover_between(actor.position, target.position) == LosProvider.COVER_TOTAL:
			return _rejected(result, cmd, RejectionReasonRules.NO_LINE_OF_SIGHT)
	var has_attack := ability.effects.any(func(effect: AbilityEffect): return effect.type == EFFECT_PERFORM_ATTACK)
	# Effects only ever append events, so "this actor has nothing to say" has to
	# be a rejection here. Keyed off the effect type, never off an ability id.
	if ability.effects.any(func(effect: AbilityEffect): return effect.type == EFFECT_START_DIALOG) and (target == null or target.dialog_id == &""):
		return _rejected(result, cmd, RejectionReasonRules.TARGET_HAS_NO_DIALOG)
	_spend_ability_cost(result, actor, ability, not has_attack, not has_attack, target.id if target != null else -1)
	var working := state.clone()
	var source: ActorState = working.actors[actor.id]
	var working_target: ActorState = working.actors.get(cmd.target_id) as ActorState
	var context := {"attack_hit": false, "save_succeeded": false}
	for effect in ability.effects:
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
			_:
				_apply_generic_effect(result, working, source, working_target, effect, context, definitions)
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


static func _spend_ability_cost(result: ResolutionResult, actor: ActorState, ability: AbilityDefinition, include_action: bool = true, include_reaction: bool = true, target_id: int = -1) -> void:
	# Unlike the action/bonus-action flags this is emitted for attacks too: the
	# attack_rolled event carries only the action/reaction spend flags, so a
	# limited-use attack would otherwise never decrement its pool.
	if ability.max_uses >= 0:
		var spent := int(actor.ability_uses_spent.get(ability.id, 0)) + 1
		result.events.append(Event.create(&"ability_use_spent", {
			"actor_id": actor.id, "ability_id": ability.id,
			"uses_spent": spent, "uses_remaining": maxi(0, ability.max_uses - spent),
		}))
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


static func _apply_generic_effect(result: ResolutionResult, working: BattleState, actor: ActorState, target: ActorState, effect: AbilityEffect, context: Dictionary, definitions: DefinitionLibrary) -> void:
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
			_append_and_apply(result, working, Event.create(&"condition_added", {
				"actor_id": recipient.id,
				"condition": effect.condition_id,
				"source_actor_id": actor.id,
				"remaining_triggers": duration,
				"expiration_timing": expiration,
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
		_:
			push_error("Unknown ability effect type: %s" % effect.type)


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


static func _resolve_attack_between(working: BattleState, attacker: ActorState, target: ActorState, los: LosProvider, definitions: DefinitionLibrary, result: ResolutionResult, spends_action: bool, spends_reaction: bool, attack_kind: StringName, attack_range: float = ATTACK_RANGE_METERS, is_ranged: bool = false, normal_range: float = ATTACK_RANGE_METERS) -> bool:
	if not los.has_line_of_sight(attacker.position, target.position) or attacker.position.distance_to(target.position) > attack_range + MOVEMENT_EPSILON:
		return false
	var attack_bonus := EquipmentRules.aggregate_attack_bonus(attacker, definitions)
	var cover := los.cover_between(attacker.position, target.position)
	var cover_bonus := 2 if cover == LosProvider.COVER_HALF else (5 if cover == LosProvider.COVER_THREE_QUARTERS else 0)
	var armor_class := EquipmentRules.aggregate_armor_class(target, definitions) + cover_bonus
	var range_disadvantage := is_ranged and attacker.position.distance_to(target.position) > normal_range + MOVEMENT_EPSILON
	var roll_result := _roll_attack_d20(working.rng_state, attacker, target, is_ranged, definitions, range_disadvantage, _has_adjacent_hostile(working, attacker))
	var roll: int = roll_result["roll"]
	var critical := roll == 20
	var hit := roll != 1 and (critical or (roll + attack_bonus >= armor_class))
	_append_and_apply(result, working, Event.create(&"attack_rolled", {
		"actor_id": attacker.id, "target_id": target.id, "attack_kind": attack_kind,
		"roll": roll, "rolls": roll_result["rolls"], "total": roll + attack_bonus,
		"critical": critical, "hit": hit, "advantage": roll_result["advantage"], "disadvantage": roll_result["disadvantage"], "is_ranged": is_ranged,
		"cover": cover, "cover_bonus": cover_bonus,
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
		_append_and_apply(result, working, Event.create(&"damage_taken", {"actor_id": target.id, "source_actor_id": attacker.id, "amount": damage, "damage_type": EquipmentRules.aggregate_damage_type(attacker, definitions)}))
		if hp_before - damage <= -target.max_hp:
			_append_and_apply(result, working, Event.create(&"actor_died", {"actor_id": target.id}))
		elif hp_before - damage <= 0:
			_append_and_apply(result, working, Event.create(&"actor_downed", {"actor_id": target.id}))
	result.next_rng_state = working.rng_state
	return hit


static func _roll_attack_d20(rng_state: int, attacker: ActorState, target: ActorState, is_ranged: bool, definitions: DefinitionLibrary, range_disadvantage: bool = false, nearby_hostile: bool = false) -> Dictionary:
	var target_is_close := attacker.position.distance_to(target.position) <= ATTACK_RANGE_METERS + MOVEMENT_EPSILON
	var attacker_flags := _condition_flags(attacker, definitions)
	var target_flags := _condition_flags(target, definitions)
	var advantage: bool = not is_ranged and target_flags["melee_advantage_when_close"] and target_is_close
	var disadvantage: bool = attacker_flags["attack_roll_disadvantage"] or target_flags["attacks_against_disadvantage"] or range_disadvantage or (is_ranged and nearby_hostile) or (is_ranged and target_flags["ranged_disadvantage_when_not_close"] and not target_is_close)
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


static func _has_adjacent_hostile(state: BattleState, actor: ActorState) -> bool:
	for actor_id in state.actors:
		if not state.active_combatant_ids.is_empty() and not state.active_combatant_ids.has(int(actor_id)):
			continue
		var candidate := state.actors[actor_id] as ActorState
		if candidate.id != actor.id and candidate.side != actor.side and candidate.is_conscious() and candidate.position.distance_to(actor.position) <= THREAT_RANGE_METERS + MOVEMENT_EPSILON:
			return true
	return false


static func _resolve_end_turn(state: BattleState, cmd: Command, result: ResolutionResult, definitions: DefinitionLibrary) -> ResolutionResult:
	if state.initiative_order.is_empty(): return _rejected(result, cmd, RejectionReasonRules.NO_INITIATIVE_ORDER)
	var next_index := TurnOrderRules.next_eligible_index(state, state.current_turn_index)
	if next_index < 0: return _rejected(result, cmd, RejectionReasonRules.NO_ELIGIBLE_ACTORS)
	var next_round := state.round_number + (1 if next_index <= state.current_turn_index else 0)
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


static func _condition_flags(actor: ActorState, definitions: DefinitionLibrary) -> Dictionary:
	var flags := {"attack_roll_disadvantage": false, "melee_advantage_when_close": false, "ranged_disadvantage_when_not_close": false, "attacks_against_disadvantage": false}
	for condition_id in actor.condition_ids():
		var definition := definitions.get_condition(condition_id)
		if definition == null: continue
		flags["attack_roll_disadvantage"] = flags["attack_roll_disadvantage"] or definition.attack_roll_disadvantage
		flags["melee_advantage_when_close"] = flags["melee_advantage_when_close"] or definition.melee_advantage_when_close
		flags["ranged_disadvantage_when_not_close"] = flags["ranged_disadvantage_when_not_close"] or definition.ranged_disadvantage_when_not_close
		flags["attacks_against_disadvantage"] = flags["attacks_against_disadvantage"] or definition.attacks_against_disadvantage
	return flags


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
	_append_and_apply(result, working, Event.create(&"movement_spent", {"actor_id": actor_id, "amount": amount, "path_cost": amount, "movement_remaining_before": actor.movement_remaining, "movement_remaining_after": maxf(0.0, actor.movement_remaining - amount)}))


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
		&"movement_segment": (state.actors[event.data["actor_id"]] as ActorState).position = event.data["to"]
		&"movement_spent":
			var moving_actor: ActorState = state.actors[event.data["actor_id"]]
			moving_actor.movement_remaining = maxf(0.0, moving_actor.movement_remaining - event.data["amount"])
		&"movement_gained": (state.actors[event.data["actor_id"]] as ActorState).movement_remaining += event.data["amount"]
		&"action_spent": (state.actors[event.data["actor_id"]] as ActorState).action_available = false
		&"bonus_action_spent": (state.actors[event.data["actor_id"]] as ActorState).bonus_action_available = false
		&"disengage_applied": (state.actors[event.data["actor_id"]] as ActorState).disengaged = true
		&"disposition_changed": (state.actors[event.data["actor_id"]] as ActorState).disposition = StringName(str(event.data["disposition"]))
		&"reaction_triggered": (state.actors[event.data["actor_id"]] as ActorState).reaction_available = false
		&"attack_rolled":
			var attacking_actor: ActorState = state.actors[event.data["actor_id"]]
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
			)
		&"condition_duration_advanced":
			var duration_actor: ActorState = state.actors[event.data["actor_id"]]
			var duration_state := duration_actor.condition_state(StringName(str(event.data["condition"])))
			if duration_state != null:
				duration_state.remaining_triggers = int(event.data["remaining_triggers"])
		&"condition_removed": (state.actors[event.data["actor_id"]] as ActorState).remove_condition(StringName(str(event.data["condition"])))
		&"interaction_completed":
			var interactable: InteractableState = state.interactables[event.data["interactable_id"]]
			interactable.state = event.data["new_state"]
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
