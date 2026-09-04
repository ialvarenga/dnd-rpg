class_name Command
extends RefCounted

var type: StringName
var actor_id: int
var target_id: int = -1
var target_pos: Vector3 = Vector3.ZERO
var metadata: Dictionary = {}


static func create(command_type: StringName, source_actor_id: int) -> Command:
	var command := Command.new()
	command.type = command_type
	command.actor_id = source_actor_id
	return command

