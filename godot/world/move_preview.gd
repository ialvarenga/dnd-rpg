class_name MovePreview
extends RefCounted

## Non-mutating movement read-model used by world input and presentation.
var accepted := false
var path := PackedVector3Array()
var cost := 0.0
var remaining := 0.0
var ignores_budget := false
var destination := Vector3.ZERO
var rejection_reason: StringName = &""
## Ledge jumps along `path`, in order: {from, to, kind, height, dice, prone}.
## `dice`/`prone` are the deterministic JumpRules landing for this mover, so a
## hurtful drop can be flagged before it is committed.
var jumps: Array[Dictionary] = []


## The first jump that would hurt, or {} when every landing is safe.
func hard_landing() -> Dictionary:
	for jump in jumps:
		if int(jump.get("dice", 0)) > 0:
			return jump
	return {}

## Retained for the arena's compatibility wrapper while callers migrate from
## its historical ResolutionResult preview API.
var resolution: ResolutionResult
