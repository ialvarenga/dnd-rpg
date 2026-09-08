class_name AbilityTargeting
extends RefCounted

## Read-only targeting facts for UI previews and approach planning. Resolver
## remains the authority for accepting a command. New targeted abilities own
## their range directly; perform_attack effect range remains a compatibility
## fallback for existing/custom definitions.

const RANGE_EPSILON := 0.001


static func target_range(definitions: DefinitionLibrary, ability_id: StringName) -> float:
	if definitions == null:
		return -1.0
	var ability := definitions.get_ability(ability_id)
	if ability == null:
		return -1.0
	if ability.target_range_meters >= 0.0:
		return ability.target_range_meters
	for effect in ability.effects:
		if effect.type == &"perform_attack":
			return effect.range_meters
	return -1.0


static func attack_range(definitions: DefinitionLibrary, ability_id: StringName) -> float:
	return target_range(definitions, ability_id)


static func is_target_in_range(source: ActorState, target: ActorState, definitions: DefinitionLibrary, ability_id: StringName) -> bool:
	var range := target_range(definitions, ability_id)
	return source != null and target != null and range >= 0.0 and source.position.distance_to(target.position) <= range + RANGE_EPSILON


static func is_target_in_attack_range(source: ActorState, target: ActorState, definitions: DefinitionLibrary, ability_id: StringName) -> bool:
	return is_target_in_range(source, target, definitions, ability_id)
