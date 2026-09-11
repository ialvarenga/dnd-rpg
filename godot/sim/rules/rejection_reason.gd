class_name RejectionReason
extends RefCounted

## Every `command_rejected` reason value Resolver can emit, gathered in one
## place so Resolver, the pure ActionAvailability reader, and tests reference
## the same StringName instead of retyping literals that could silently
## drift apart. This is a pure extraction: no reason value changed and no
## rejection check was reordered (see resolver.gd, command_phase_rules.gd,
## ability_cost_rules.gd).

const UNKNOWN_ACTOR := &"unknown_actor"
const COMBAT_ALREADY_ACTIVE := &"combat_already_active"
const ACTOR_NOT_ELIGIBLE := &"actor_not_eligible"
const NO_ELIGIBLE_ACTORS := &"no_eligible_actors"
const NOT_IN_COMBAT := &"not_in_combat"
const NOT_CURRENT_ACTOR := &"not_current_actor"
const UNSUPPORTED_COMMAND := &"unsupported_command"
const ACTOR_CANNOT_ACT := &"actor_cannot_act"
const UNREACHABLE := &"unreachable"
const NO_MOVEMENT := &"no_movement"
const INSUFFICIENT_MOVEMENT_TO_STAND := &"insufficient_movement_to_stand"
const NO_MOVEMENT_REMAINING := &"no_movement_remaining"
const UNKNOWN_INTERACTABLE := &"unknown_interactable"
const OUT_OF_RANGE := &"out_of_range"
const ACTION_UNAVAILABLE := &"action_unavailable"
const INVALID_INTERACTABLE_STATE := &"invalid_interactable_state"
const UNKNOWN_ABILITY_DEFINITION := &"unknown_ability_definition"
const BONUS_ACTION_UNAVAILABLE := &"bonus_action_unavailable"
const REACTION_UNAVAILABLE := &"reaction_unavailable"
const INSUFFICIENT_MOVEMENT := &"insufficient_movement"
const ITEM_NOT_IN_INVENTORY := &"item_not_in_inventory"
const ABILITY_USES_EXHAUSTED := &"ability_uses_exhausted"
const UNKNOWN_TARGET := &"unknown_target"
const INVALID_TARGET := &"invalid_target"
const NO_LINE_OF_SIGHT := &"no_line_of_sight"
const TARGET_OUT_OF_RANGE := &"target_out_of_range"
const NO_INITIATIVE_ORDER := &"no_initiative_order"
const GAME_OVER := &"game_over"
const COMBAT_UNRESOLVED := &"combat_unresolved"
const INVALID_ENCOUNTER := &"invalid_encounter"
const INVALID_ABILITY_SCORE := &"invalid_ability_score"
const INVALID_DIFFICULTY_CLASS := &"invalid_difficulty_class"
const INVALID_DISPOSITION := &"invalid_disposition"
const TARGET_HAS_NO_DIALOG := &"target_has_no_dialog"
const INVALID_COIN_AMOUNT := &"invalid_coin_amount"
const INSUFFICIENT_COINS := &"insufficient_coins"
const INVALID_ABILITY_MODE := &"invalid_ability_mode"
const INVALID_TARGET_POINT := &"invalid_target_point"
