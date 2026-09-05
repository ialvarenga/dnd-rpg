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

## Retained for the arena's compatibility wrapper while callers migrate from
## its historical ResolutionResult preview API.
var resolution: ResolutionResult
