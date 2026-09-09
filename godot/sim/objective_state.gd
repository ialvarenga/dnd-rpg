class_name ObjectiveState
extends RefCounted

var id: String = ""
var position: Vector3 = Vector3.ZERO
var radius_m: float = 2.0
var requires_encounter_ids: Array[String] = []
var completed: bool = false


func clone() -> ObjectiveState:
	var copy := ObjectiveState.new()
	copy.id = id
	copy.position = position
	copy.radius_m = radius_m
	copy.requires_encounter_ids = requires_encounter_ids.duplicate()
	copy.completed = completed
	return copy


func requirements_met(cleared_encounter_ids: Array[String]) -> bool:
	for encounter_id in requires_encounter_ids:
		if not cleared_encounter_ids.has(encounter_id):
			return false
	return true


func to_dict() -> Dictionary:
	return {
		"id": id,
		"position": SimulationSerialization.value_to_data(position),
		"radius_m": radius_m,
		"requires_encounter_ids": requires_encounter_ids.duplicate(),
		"completed": completed,
	}


static func from_dict(data: Dictionary) -> ObjectiveState:
	var objective := ObjectiveState.new()
	objective.id = str(data.get("id", ""))
	var restored_position: Variant = SimulationSerialization.data_to_value(data.get("position", {}))
	if restored_position is Vector3:
		objective.position = restored_position
	objective.radius_m = float(data.get("radius_m", 2.0))
	for encounter_id in data.get("requires_encounter_ids", []):
		objective.requires_encounter_ids.append(str(encounter_id))
	objective.completed = bool(data.get("completed", false))
	return objective
