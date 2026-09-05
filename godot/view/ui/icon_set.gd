class_name IconSet
extends Resource

@export var textures: Dictionary[StringName, Texture2D] = {}

func texture_for(id: StringName) -> Texture2D:
	return textures.get(id)
