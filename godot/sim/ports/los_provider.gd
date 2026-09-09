class_name LosProvider
extends RefCounted

const COVER_NONE: StringName = &"none"
const COVER_HALF: StringName = &"half"
const COVER_THREE_QUARTERS: StringName = &"three_quarters"
const COVER_TOTAL: StringName = &"total"

func has_line_of_sight(_from: Vector3, _to: Vector3) -> bool:
	push_error("LosProvider.has_line_of_sight must be implemented by an adapter")
	return false


## Existing adapters remain valid: a binary LoS provider maps clear/blocked to
## no/total cover. Rich 3D adapters override this with deterministic samples.
func cover_between(from: Vector3, to: Vector3) -> StringName:
	return COVER_NONE if has_line_of_sight(from, to) else COVER_TOTAL
