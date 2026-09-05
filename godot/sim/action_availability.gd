class_name ActionAvailability
extends RefCounted

## Pure, read-only HUD data: for a given actor and ability id, reports
## whether Resolver.resolve() would currently accept the routed command, and
## if not, exactly which rejection reason it would give. It reuses the same
## shared rules Resolver itself calls (CommandPhaseRules, AbilityCostRules,
## RejectionReason) instead of re-deriving the checks, so the two can never
## silently drift apart -- see tests/unit/test_action_availability.gd, which
## asserts agreement against actual Resolver.resolve() results.
##
## This never calls Resolver.resolve() and takes no NavProvider/LosProvider:
## it only covers the phase/turn/consciousness/cost gates shared by every
## untargeted ability (Dash, Disengage, ...). Targeted abilities (Basic
## Attack) additionally depend on target validity, line of sight, and range,
## which need an actual target and LosProvider to evaluate -- Resolver.
## resolve() remains the sole authority for those and for command acceptance
## in general; nothing here rejects or accepts a command.

const RejectionReasonRules = preload("res://sim/rules/rejection_reason.gd")
const AbilityRoutingRules = preload("res://sim/rules/ability_routing.gd")
const CommandPhaseRulesScript = preload("res://sim/rules/command_phase_rules.gd")
const AbilityCostRulesScript = preload("res://sim/rules/ability_cost_rules.gd")


## {ability_id, command_type, available, reason}. `reason` is &"" when
## `available` is true.
static func evaluate(state: BattleState, actor_id: int, ability_id: StringName, defs: DefinitionLibrary = null) -> Dictionary:
	var definitions := defs if defs != null else DefinitionLibrary.get_default()
	if not state.actors.has(actor_id):
		return _result(ability_id, false, RejectionReasonRules.UNKNOWN_ACTOR)
	var phase_rejection := CommandPhaseRulesScript.rejection_for_combat_turn(state, actor_id)
	if phase_rejection != &"":
		return _result(ability_id, false, phase_rejection)
	var actor: ActorState = state.actors[actor_id]
	var conscious_rejection := CommandPhaseRulesScript.rejection_for_conscious(actor)
	if conscious_rejection != &"":
		return _result(ability_id, false, conscious_rejection)
	var ability := definitions.get_ability(ability_id)
	if ability == null:
		return _result(ability_id, false, RejectionReasonRules.UNKNOWN_ABILITY_DEFINITION)
	var cost_rejection := AbilityCostRulesScript.rejection_for_cost(actor, ability)
	if cost_rejection != &"":
		return _result(ability_id, false, cost_rejection)
	return _result(ability_id, true, &"")


## Ordered evaluation for a list of ability ids (typically an actor's own
## ActorState.ability_ids). Order is preserved from `ability_ids` as given.
static func evaluate_all(state: BattleState, actor_id: int, ability_ids: Array[StringName], defs: DefinitionLibrary = null) -> Array[Dictionary]:
	var evaluations: Array[Dictionary] = []
	for ability_id in ability_ids:
		evaluations.append(evaluate(state, actor_id, ability_id, defs))
	return evaluations


static func _result(ability_id: StringName, available: bool, reason: StringName) -> Dictionary:
	return {
		"ability_id": ability_id,
		"command_type": AbilityRoutingRules.command_type_for_ability(ability_id),
		"available": available,
		"reason": reason,
	}
