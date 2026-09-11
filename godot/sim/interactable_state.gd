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
var tags: Array[StringName] = []
var destroyed: bool = false
var blast_radius_meters: float = 0.0
var blast_damage_die: int = 0
var blast_damage_dice_count: int = 0


func clone() -> InteractableState:
	var copy := InteractableState.new()
	copy.id = id
	copy.type = type
	copy.state = state
	copy.position = position
	copy.interact_range = interact_range
	copy.contents = contents.duplicate()
	copy.tags = tags.duplicate()
	copy.destroyed = destroyed
	copy.blast_radius_meters = blast_radius_meters
	copy.blast_damage_die = blast_damage_die
	copy.blast_damage_dice_count = blast_damage_dice_count
	return copy


func to_dict() -> Dictionary:
	return {
		"id": id,
		"type": String(type),
		"state": String(state),
		"position": SimulationSerialization.value_to_data(position),
		"interact_range": interact_range,
		"contents": SimulationSerialization.value_to_data(contents),
		"tags": SimulationSerialization.value_to_data(tags),
		"destroyed": destroyed,
		"blast_radius_meters": blast_radius_meters,
		"blast_damage_die": blast_damage_die,
		"blast_damage_dice_count": blast_damage_dice_count,
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
	var restored_tags: Variant = SimulationSerialization.data_to_value(data.get("tags", []))
	if restored_tags is Array:
		for tag in restored_tags:
			interactable.tags.append(StringName(str(tag)))
	interactable.destroyed = bool(data.get("destroyed", false))
	interactable.blast_radius_meters = float(data.get("blast_radius_meters", 0.0))
	interactable.blast_damage_die = int(data.get("blast_damage_die", 0))
	interactable.blast_damage_dice_count = int(data.get("blast_damage_dice_count", 0))
	return interactable
