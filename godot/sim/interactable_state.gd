class_name InteractableState
extends RefCounted

## Runtime state for a single world interactable (door/chest/lever -- Fase A9).
## Mirrors ActorState's role: authoritative per-instance data living inside
## BattleState, mutated only through Resolver events, never through Nodes.

var id: String = ""
var type: StringName = &""
var state: StringName = &""
var position: Vector3 = Vector3.ZERO
var interact_range: float = 2.0
var contents: Array[StringName] = []


func clone() -> InteractableState:
	var copy := InteractableState.new()
	copy.id = id
	copy.type = type
	copy.state = state
	copy.position = position
	copy.interact_range = interact_range
	copy.contents = contents.duplicate()
	return copy


func to_dict() -> Dictionary:
	return {
		"id": id,
		"type": String(type),
		"state": String(state),
		"position": SimulationSerialization.value_to_data(position),
		"interact_range": interact_range,
		"contents": SimulationSerialization.value_to_data(contents),
	}


static func from_dict(data: Dictionary) -> InteractableState:
	var interactable := InteractableState.new()
	interactable.id = str(data.get("id", ""))
	interactable.type = StringName(str(data.get("type", "")))
	interactable.state = StringName(str(data.get("state", "")))
	var restored_position: Variant = SimulationSerialization.data_to_value(data.get("position", {}))
	if restored_position is Vector3:
		interactable.position = restored_position
	interactable.interact_range = float(data.get("interact_range", 2.0))
	var restored_contents: Variant = SimulationSerialization.data_to_value(data.get("contents", []))
	if restored_contents is Array:
		for item_id in restored_contents:
			interactable.contents.append(StringName(str(item_id)))
	return interactable
