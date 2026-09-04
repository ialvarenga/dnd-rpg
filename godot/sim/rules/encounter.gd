class_name Encounter
extends RefCounted

const TurnOrderRules = preload("res://sim/rules/turn_order.gd")

const EXPLORATION: StringName = &"exploration"
const COMBAT_STARTING: StringName = &"combat_starting"
const COMBAT: StringName = &"combat"
const COMBAT_ENDING: StringName = &"combat_ending"


static func can_start(state: BattleState) -> bool:
	return state.phase == EXPLORATION and not TurnOrderRules.eligible_actor_ids(state).is_empty()


static func can_end(state: BattleState) -> bool:
	return state.phase == COMBAT
