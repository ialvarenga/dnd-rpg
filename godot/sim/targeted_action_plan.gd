class_name TargetedActionPlan
extends RefCounted

## Read-only result of planning an actor-targeted action. Planning never mutates
## BattleState; the controller still submits movement and ability commands
## independently through EncounterSession.
var can_execute := false
var requires_movement := false
var movement_target := Vector3.INF
var destination := Vector3.INF
var movement_cost := 0.0
var rejection_reason: StringName = &""
