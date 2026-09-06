class_name AbilityCostRules
extends RefCounted

## Shared ability-affordability gate: the exact action/bonus_action/reaction/
## movement checks Resolver.resolve() runs for any AbilityDefinition, in the
## same order, regardless of whether the ability's effects include
## perform_attack. Extracting this closes a prior gap where an ability whose
## effects included perform_attack only ever checked costs_action, silently
## ignoring any costs_bonus_action/costs_reaction/movement_cost the same
## definition declared (see resolver.gd _resolve_attack_effect). No shipped
## ability currently combines perform_attack with those other costs, so this
## is behavior-preserving for existing content.

const RejectionReasonRules = preload("res://sim/rules/rejection_reason.gd")

## Mirrors Resolver.MOVEMENT_EPSILON. Duplicated locally (rather than
## preloaded from Resolver) to avoid a preload cycle, since Resolver already
## preloads sim/rules scripts.
const MOVEMENT_EPSILON := 0.0001


## Empty StringName means the ability's resources are affordable; the caller
## still has to look up/validate the ability and its targeting separately.
static func rejection_for_cost(actor: ActorState, ability: AbilityDefinition, definitions: DefinitionLibrary = null) -> StringName:
	if ability.costs_action and not actor.action_available:
		return RejectionReasonRules.ACTION_UNAVAILABLE
	if ability.costs_bonus_action and not actor.bonus_action_available:
		return RejectionReasonRules.BONUS_ACTION_UNAVAILABLE
	if ability.costs_reaction and not actor.reaction_available:
		return RejectionReasonRules.REACTION_UNAVAILABLE
	if ability.movement_cost > 0.0 and actor.movement_remaining + MOVEMENT_EPSILON < ability.movement_cost:
		return RejectionReasonRules.INSUFFICIENT_MOVEMENT
	# A consume effect is an ability cost too: validate it before any event is
	# emitted, so Resolver and advisory availability agree and never partially
	# spend an action for an absent item.
	for effect in ability.effects:
		if effect.type == &"consume_item" and effect.consumes_item_id != &"":
			var required_item := definitions.get_item(effect.consumes_item_id) if definitions != null else null
			if required_item == null or not actor.inventory.has(required_item.id):
				return RejectionReasonRules.ITEM_NOT_IN_INVENTORY
	return &""
