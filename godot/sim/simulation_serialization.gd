class_name SimulationSerialization
extends RefCounted

## JSON-safe conversion for simulation values. This stays in sim because it is
## deliberately independent of Nodes, scenes, physics, and provider adapters.

static func value_to_data(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return {"$type": "int", "value": value}
	if typeof(value) == TYPE_FLOAT:
		return {"$type": "float", "value": String.num(value, 17)}
	if value is Vector3:
		return {
			"$type": "Vector3",
			"x": value_to_data(value.x),
			"y": value_to_data(value.y),
			"z": value_to_data(value.z),
		}
	if value is PackedVector3Array:
		var points: Array = []
		for point in value:
			points.append(value_to_data(point))
		return {"$type": "PackedVector3Array", "points": points}
	if value is StringName:
		return {"$type": "StringName", "value": String(value)}
	if value is Array:
		var converted: Array = []
		for item in value:
			converted.append(value_to_data(item))
		return converted
	if value is Dictionary:
		var converted := {}
		var keys: Array = value.keys()
		keys.sort()
		for key in keys:
			converted[str(key)] = value_to_data(value[key])
		return converted
	return value


static func data_to_value(data: Variant) -> Variant:
	if data is Array:
		var converted: Array = []
		for item in data:
			converted.append(data_to_value(item))
		return converted
	if data is Dictionary:
		var dictionary: Dictionary = data
		if dictionary.get("$type", "") == "Vector3":
			return Vector3(
				float(data_to_value(dictionary.get("x", 0.0))),
				float(data_to_value(dictionary.get("y", 0.0))),
				float(data_to_value(dictionary.get("z", 0.0))),
			)
		if dictionary.get("$type", "") == "PackedVector3Array":
			var points := PackedVector3Array()
			for point in dictionary.get("points", []):
				var value: Variant = data_to_value(point)
				if value is Vector3:
					points.append(value)
			return points
		if dictionary.get("$type", "") == "StringName":
			return StringName(str(dictionary.get("value", "")))
		if dictionary.get("$type", "") == "int":
			return int(dictionary.get("value", 0))
		if dictionary.get("$type", "") == "float":
			return float(str(dictionary.get("value", "0")))
		var converted := {}
		for key in dictionary:
			converted[key] = data_to_value(dictionary[key])
		return converted
	return data
