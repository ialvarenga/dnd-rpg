class_name ConditionState
extends RefCounted

## Authoritative runtime instance of a data-defined condition. A negative
## trigger count means the condition is permanent until explicitly removed.
var definition_id: StringName = &""
var source_actor_id: int = -1
## Optional actor relationship used by attack-triggered conditions. A negative
## value means the condition applies to any matching attack relationship.
var related_actor_id: int = -1
var remaining_triggers: int = -1
var expiration_timing: StringName = &"none"


static func create(
	condition_id: StringName,
	source_id: int = -1,
	trigger_count: int = -1,
	timing: StringName = &"none",
	related_id: int = -1
) -> ConditionState:
	var state := ConditionState.new()
	state.definition_id = condition_id
	state.source_actor_id = source_id
	state.related_actor_id = related_id
	state.remaining_triggers = trigger_count
	state.expiration_timing = timing
	return state


func clone() -> ConditionState:
	return create(definition_id, source_actor_id, remaining_triggers, expiration_timing, related_actor_id)


func to_dict() -> Dictionary:
	return {
		"definition_id": String(definition_id),
		"source_actor_id": source_actor_id,
		"related_actor_id": related_actor_id,
		"remaining_triggers": remaining_triggers,
		"expiration_timing": String(expiration_timing),
	}


static func from_dict(data: Dictionary) -> ConditionState:
	return create(
		StringName(str(data.get("definition_id", ""))),
		int(data.get("source_actor_id", -1)),
		int(data.get("remaining_triggers", -1)),
		StringName(str(data.get("expiration_timing", "none"))),
		int(data.get("related_actor_id", -1)),
	)
