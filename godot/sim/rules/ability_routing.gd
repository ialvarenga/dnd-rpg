class_name AbilityRouting
extends RefCounted

## Command type -> AbilityDefinition id, and the explicit reverse of that
## mapping. Command types stay a small, fixed routing vocabulary; the actual
## ability content (costs/effects) always comes from the looked-up
## AbilityDefinition, never from branching on either id here (ADR-004).

const COMMAND_TO_ABILITY_ID := {
	&"attack": &"basic_attack",
	&"basic_attack": &"basic_attack",
	&"dash": &"dash",
	&"disengage": &"disengage",
}

## One canonical command type per routed ability id, for callers that start
## from an ability id (ActionAvailability, a future HUD hotbar) and need the
## command type Resolver.resolve() actually dispatches on. "attack" is an
## alias for "basic_attack" in the forward map above; the reverse resolves to
## "basic_attack" itself, which is equally accepted by Resolver.
const ABILITY_ID_TO_COMMAND_TYPE := {
	&"basic_attack": &"basic_attack",
	&"dash": &"dash",
	&"disengage": &"disengage",
}


static func is_ability_command(command_type: StringName) -> bool:
	return COMMAND_TO_ABILITY_ID.has(command_type)


static func ability_id_for_command(command_type: StringName) -> StringName:
	return COMMAND_TO_ABILITY_ID.get(command_type, &"")


## Falls back to the ability id itself when it is not a routed alias, since
## for every currently routed ability the id already doubles as a valid
## command type.
static func command_type_for_ability(ability_id: StringName) -> StringName:
	return ABILITY_ID_TO_COMMAND_TYPE.get(ability_id, ability_id)
