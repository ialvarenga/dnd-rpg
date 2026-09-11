class_name MasteryRules
extends RefCounted

const SAP := &"sap"
const VEX := &"vex"
const NICK := &"nick"
const GRAZE := &"graze"
const TOPPLE := &"topple"

const DEFINITIONS := {
	SAP: {"label": "Sap", "description": "On hit, the target has Disadvantage on its next attack."},
	VEX: {"label": "Vex", "description": "On hit, your next attack against the target has Advantage."},
	NICK: {"label": "Nick", "description": "A Light offhand attack is folded into the Attack action once per turn."},
	GRAZE: {"label": "Graze", "description": "On miss, deal damage equal to the attack ability modifier."},
	TOPPLE: {"label": "Topple", "description": "On hit, the target makes a Constitution save or falls Prone."},
}


static func is_supported(mastery: StringName) -> bool:
	return DEFINITIONS.has(mastery)


static func description(mastery: StringName) -> String:
	var definition: Dictionary = DEFINITIONS.get(mastery, {})
	return str(definition.get("description", ""))


static func label(mastery: StringName) -> String:
	var definition: Dictionary = DEFINITIONS.get(mastery, {})
	return str(definition.get("label", String(mastery).capitalize()))


static func can_nick_attack(actor: ActorState, defs: DefinitionLibrary) -> bool:
	var main := Equipment.weapon(actor, defs)
	var offhand := Equipment.offhand(actor, defs)
	return (
		main != null and offhand != null
		and main.weapon_properties.has(&"light")
		and offhand.weapon_properties.has(&"light")
		and offhand.mastery == NICK
		and not bool(actor.ability_uses_spent.get(&"nick_attack", 0))
	)
