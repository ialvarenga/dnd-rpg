class_name Event
extends RefCounted

var type: StringName
var data: Dictionary


static func create(event_type: StringName, event_data: Dictionary = {}) -> Event:
	var event := Event.new()
	event.type = event_type
	event.data = event_data
	return event

