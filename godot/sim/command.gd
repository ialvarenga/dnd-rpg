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


func to_dict() -> Dictionary:
	return {
		"type": String(type),
		"actor_id": actor_id,
		"target_id": target_id,
		"target_pos": SimulationSerialization.value_to_data(target_pos),
		"metadata": SimulationSerialization.value_to_data(metadata),
	}


static func from_dict(data: Dictionary) -> Command:
	var command := Command.create(StringName(str(data.get("type", ""))), int(data.get("actor_id", -1)))
	command.target_id = int(data.get("target_id", -1))
	var restored_target: Variant = SimulationSerialization.data_to_value(data.get("target_pos", {}))
	if restored_target is Vector3:
		command.target_pos = restored_target
	var restored_metadata: Variant = SimulationSerialization.data_to_value(data.get("metadata", {}))
	if restored_metadata is Dictionary:
		command.metadata = restored_metadata
	return command
