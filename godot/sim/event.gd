class_name Event
extends RefCounted

var type: StringName
var data: Dictionary


static func create(event_type: StringName, event_data: Dictionary = {}) -> Event:
	var event := Event.new()
	event.type = event_type
	event.data = event_data
	return event


func to_dict() -> Dictionary:
	return {"type": String(type), "data": SimulationSerialization.value_to_data(data)}


static func from_dict(serialized: Dictionary) -> Event:
	var restored_data: Variant = SimulationSerialization.data_to_value(serialized.get("data", {}))
	if not (restored_data is Dictionary):
		restored_data = {}
	return Event.create(StringName(str(serialized.get("type", ""))), restored_data)
