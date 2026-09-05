class_name MapValidationError
extends RefCounted

var code: StringName
var entity_id: StringName
var context: Dictionary
var message: String


func _init(error_code: StringName, human_message: String, id: StringName = &"", error_context: Dictionary = {}) -> void:
	code = error_code
	message = human_message
	entity_id = id
	context = error_context.duplicate(true)


func as_dict() -> Dictionary:
	return {"code": code, "entity_id": entity_id, "context": context, "message": message}
