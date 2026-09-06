class_name AbilityTargeting
extends RefCounted

## Read-only targeting facts for UI previews. Resolver remains the authority
## for accepting a command, but both layers read the range from the same
## AbilityEffect data so each attack type can declare its own reach.

const RANGE_EPSILON := 0.001


static func attack_range(definitions: DefinitionLibrary, ability_id: StringName) -> float:
	if definitions == null:
		return -1.0
	var ability := definitions.get_ability(ability_id)
	if ability == null:
		return -1.0
	for effect in ability.effects:
		if effect.type == &"perform_attack":
			return effect.range_meters
	return -1.0


static func is_target_in_attack_range(source: ActorState, target: ActorState, definitions: DefinitionLibrary, ability_id: StringName) -> bool:
	var range := attack_range(definitions, ability_id)
	return source != null and target != null and range >= 0.0 and source.position.distance_to(target.position) <= range + RANGE_EPSILON
