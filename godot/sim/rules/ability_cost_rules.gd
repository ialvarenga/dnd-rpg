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
## Outside combat there is no action economy: turn flags and movement never
## gate an ability there, only its use pool and any consumed item do.
static func rejection_for_cost(actor: ActorState, ability: AbilityDefinition, definitions: DefinitionLibrary = null, in_combat: bool = true) -> StringName:
	# Checked before the action/bonus-action flags so an exhausted pool reports
	# the reason the player can act on ("no uses left") rather than whichever
	# economy slot happened to be spent first this turn.
	if ability.max_uses >= 0 and remaining_uses(actor, ability) <= 0:
		return RejectionReasonRules.ABILITY_USES_EXHAUSTED
	if not in_combat:
		return _item_rejection(actor, ability, definitions)
	if ability.costs_action and not actor.action_available:
		return RejectionReasonRules.ACTION_UNAVAILABLE
	if ability.costs_bonus_action and not actor.bonus_action_available:
		return RejectionReasonRules.BONUS_ACTION_UNAVAILABLE
	if ability.costs_reaction and (not actor.reaction_available or not actor.can_take_reactions()):
		return RejectionReasonRules.REACTION_UNAVAILABLE
	if ability.movement_cost > 0.0 and actor.movement_remaining + MOVEMENT_EPSILON < ability.movement_cost:
		return RejectionReasonRules.INSUFFICIENT_MOVEMENT
	return _item_rejection(actor, ability, definitions)


## A consume effect is an ability cost too: validate it before any event is
## emitted, so Resolver and advisory availability agree and never partially
## spend an action for an absent item.
static func _item_rejection(actor: ActorState, ability: AbilityDefinition, definitions: DefinitionLibrary) -> StringName:
	for effect in ability.effects:
		if effect.type == &"consume_item" and effect.consumes_item_id != &"":
			var required_item := definitions.get_item(effect.consumes_item_id) if definitions != null else null
			if required_item == null or not actor.inventory.has(required_item.id):
				return RejectionReasonRules.ITEM_NOT_IN_INVENTORY
	return &""


## Activations left in this ability's pool. Unlimited abilities (max_uses < 0)
## report a large positive number so callers can treat every ability uniformly
## without re-checking the sentinel.
static func remaining_uses(actor: ActorState, ability: AbilityDefinition) -> int:
	if ability.max_uses < 0:
		return 0x7FFFFFFF
	return maxi(0, ability.max_uses - int(actor.ability_uses_spent.get(ability.id, 0)))
