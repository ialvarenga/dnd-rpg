class_name Encounter
extends RefCounted

const TurnOrderRules = preload("res://sim/rules/turn_order.gd")

const EXPLORATION: StringName = &"exploration"
const COMBAT_STARTING: StringName = &"combat_starting"
const COMBAT: StringName = &"combat"
const COMBAT_ENDING: StringName = &"combat_ending"
const GAME_OVER: StringName = &"game_over"

const OUTCOME_NONE: StringName = &"none"
const OUTCOME_VICTORY: StringName = &"victory"
const OUTCOME_DEFEAT: StringName = &"defeat"


static func can_start(state: BattleState) -> bool:
	return state.phase == EXPLORATION and not TurnOrderRules.eligible_actor_ids(state).is_empty()


static func can_end(state: BattleState) -> bool:
	return state.phase == COMBAT


## Returns an empty outcome while both sides can still act. Hero defeat takes
## precedence if a future simultaneous effect removes the last actor on both
## sides, matching the single-hero run rule.
static func resolved_outcome(state: BattleState) -> StringName:
	if state.phase != COMBAT:
		return OUTCOME_NONE
	var participants := state.active_combatant_ids
	if participants.is_empty():
		participants = TurnOrderRules.eligible_actor_ids(state)
	var hero_active := false
	var enemy_active := false
	var has_hero_participant := false
	var has_enemy_participant := false
	for actor_id in participants:
		if not state.actors.has(actor_id):
			continue
		var actor: ActorState = state.actors[actor_id]
		if actor.side == &"heroes":
			has_hero_participant = true
			hero_active = hero_active or actor.is_conscious()
		elif actor.side == &"enemies":
			has_enemy_participant = true
			enemy_active = enemy_active or actor.is_conscious()
	if not has_hero_participant or not has_enemy_participant:
		return OUTCOME_NONE
	if not hero_active:
		return OUTCOME_DEFEAT
	if not enemy_active:
		return OUTCOME_VICTORY
	return OUTCOME_NONE
