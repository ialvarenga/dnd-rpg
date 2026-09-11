class_name CommandPhaseRules
extends RefCounted

## Shared phase/turn-ownership and consciousness gates. Resolver.resolve()'s
## top-level dispatch and its per-command handlers call these so the pure
## ActionAvailability reader (sim/action_availability.gd) can reproduce the
## exact same command-phase rejection Resolver would give for a combat
## command, without owning a second copy of the logic or depending on
## NavProvider/LosProvider.

const EncounterRules = preload("res://sim/rules/encounter.gd")
const RejectionReasonRules = preload("res://sim/rules/rejection_reason.gd")


## Empty StringName means the command may proceed as far as phase/turn
## ownership is concerned; Resolver still runs command-specific checks after.
static func rejection_for_combat_turn(state: BattleState, actor_id: int) -> StringName:
	if state.phase == EncounterRules.GAME_OVER:
		return RejectionReasonRules.GAME_OVER
	if state.phase != EncounterRules.COMBAT:
		return RejectionReasonRules.NOT_IN_COMBAT
	if state.current_actor_id() != actor_id:
		return RejectionReasonRules.NOT_CURRENT_ACTOR
	return &""


## Phase gate for an ability command. An ability that declares
## usable_in_exploration resolves outside combat without owning a turn;
## exploration_only abilities are rejected once combat starts; everything else
## falls through to the shared combat turn gate unchanged.
static func rejection_for_ability(state: BattleState, actor_id: int, ability: AbilityDefinition) -> StringName:
	if state.phase == EncounterRules.EXPLORATION and ability != null and ability.usable_in_exploration:
		return &""
	if state.phase == EncounterRules.COMBAT and ability != null and ability.exploration_only:
		return RejectionReasonRules.COMBAT_ALREADY_ACTIVE
	return rejection_for_combat_turn(state, actor_id)


## True when using this ability outside combat starts the fight: an attack, or
## anything else aimed at a creature on the other side (Shove). Talk is aimed
## at the other side too, but it is exploration-only, so it never opens combat.
static func opens_combat_from_exploration(ability: AbilityDefinition) -> bool:
	if ability == null or ability.exploration_only:
		return false
	if ability.effects.any(func(effect: AbilityEffect): return effect.type == &"perform_attack"):
		return true
	return ability.targeting == &"actor" and ability.target_filter == &"hostile"


static func rejection_for_conscious(actor: ActorState) -> StringName:
	return &"" if actor.is_conscious() else RejectionReasonRules.ACTOR_CANNOT_ACT
