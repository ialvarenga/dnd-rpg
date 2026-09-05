class_name MapValidationWarning
extends RefCounted

var code: StringName
var message: String
var entity_id: StringName
var context: Dictionary


func _init(warning_code: StringName, warning_message: String, id: StringName = &"", warning_context: Dictionary = {}) -> void:
	code = warning_code
	message = warning_message
	entity_id = id
	context = warning_context


func as_dict() -> Dictionary:
	return {"code": code, "message": message, "entity_id": entity_id, "context": context}
