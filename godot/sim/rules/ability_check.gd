class_name AbilityCheck
extends RefCounted

## Content-agnostic d20 ability check. This is a thin façade: the roll itself
## belongs to D20Test (sim/d20_test.gd) and the score-to-modifier arithmetic
## belongs to ActorState.ability_modifier, so there is exactly one
## implementation of each. What lives here is the vocabulary -- which
## StringNames are ability scores, and which narration skill maps to which
## score -- plus the proficiency rule shared by every check.
##
## Resolver never reads SKILL_ABILITIES: a skill_check command carries its own
## `ability`, and `skill` is a narration label only. The table exists so
## authoring tools and the dialog layer can default one from the other without
## the resolver ever branching on content (ADR-004).

const D20TestScript = preload("res://sim/d20_test.gd")

const ABILITY_SCORES: Array[StringName] = [
	&"strength", &"dexterity", &"constitution",
	&"intelligence", &"wisdom", &"charisma",
]

const SKILL_ABILITIES := {
	&"athletics": &"strength",
	&"acrobatics": &"dexterity",
	&"stealth": &"dexterity",
	&"insight": &"wisdom",
	&"perception": &"wisdom",
	&"persuasion": &"charisma",
	&"deception": &"charisma",
	&"intimidation": &"charisma",
}


static func is_ability_score(ability: StringName) -> bool:
	return ABILITY_SCORES.has(ability)


## Governing ability score for a narration skill, or &"" when unknown.
static func ability_for_skill(skill: StringName) -> StringName:
	return SKILL_ABILITIES.get(skill, &"")


static func modifier(actor: ActorState, ability: StringName, proficient: bool) -> int:
	return actor.ability_modifier(ability) + (actor.proficiency_bonus if proficient else 0)


## D20Test.roll's dictionary, plus the check's own vocabulary so a caller can
## narrate the result without re-deriving it. Threads rng_state like every
## other roll in the simulation.
static func resolve(
	rng_state: int,
	actor: ActorState,
	ability: StringName,
	difficulty_class: int,
	proficient: bool,
	advantage: bool = false,
	disadvantage: bool = false
) -> Dictionary:
	var result := D20TestScript.roll(rng_state, modifier(actor, ability, proficient), difficulty_class, advantage, disadvantage)
	result["ability"] = ability
	result["proficient"] = proficient
	return result
