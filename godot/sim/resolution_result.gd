class_name ResolutionResult
extends RefCounted

var events: Array[Event] = []
var next_rng_state: int = 0


func to_dict() -> Dictionary:
	var serialized_events: Array[Dictionary] = []
	for event in events:
		serialized_events.append(event.to_dict())
	return {"events": serialized_events, "next_rng_state": next_rng_state}


static func from_dict(data: Dictionary) -> ResolutionResult:
	var result := ResolutionResult.new()
	for serialized_event in data.get("events", []):
		if serialized_event is Dictionary:
			result.events.append(Event.from_dict(serialized_event))
	result.next_rng_state = int(data.get("next_rng_state", 0))
	return result
