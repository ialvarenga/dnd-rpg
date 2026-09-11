class_name CharacterSheetViewModel
extends RefCounted

## A deliberately node-free projection for the character-sheet modal.  The
## dictionaries returned here are presentation facts only; they never retain
## or mutate BattleState.
const AbilityCheckRules = preload("res://sim/rules/ability_check.gd")
const AbilityCostRules = preload("res://sim/rules/ability_cost_rules.gd")
const AttackMathRules = preload("res://sim/rules/attack_math.gd")
const EquipmentRules = preload("res://sim/equipment.gd")


static func for_actor(state: BattleState, actor_id: int, defs: DefinitionLibrary) -> Dictionary:
	if state == null or not state.actors.has(actor_id):
		return {}
	var actor := state.actors[actor_id] as ActorState
	var hud_header := HudViewModel.for_actor(state, actor_id, defs)
	var conditions: Array[Dictionary] = []
	for condition_id in actor.condition_ids():
		var condition := defs.get_condition(condition_id) if defs != null else null
		conditions.append({"id": condition_id, "name": condition.display_name if condition != null and not condition.display_name.is_empty() else _title(condition_id)})
	hud_header["conditions"] = conditions
	var armor := AttackMathRules.armor_class(actor, defs) if defs != null else {"base": 10, "dexterity_bonus": actor.ability_modifier(&"dexterity"), "magic_bonus": 0, "total": 10 + actor.ability_modifier(&"dexterity"), "armor_id": &""}
	return {
		"header": hud_header,
		"stats": _stats(state, actor, defs, armor, conditions),
		"equipment": _equipment(actor, defs, armor),
		"inventory": {
			"stacks": inventory_stacks(state, actor_id, defs),
			"coins": actor.coins,
			"display_slots": maxi(20, ceili(float(inventory_stacks(state, actor_id, defs).size()) / 5.0) * 5),
		},
	}


static func inventory_stacks(state: BattleState, actor_id: int, defs: DefinitionLibrary) -> Array[Dictionary]:
	var stacks: Array[Dictionary] = []
	if state == null or not state.actors.has(actor_id):
		return stacks
	var actor := state.actors[actor_id] as ActorState
	var index_by_id: Dictionary = {}
	for item_id in actor.inventory:
		if index_by_id.has(item_id):
			stacks[int(index_by_id[item_id])]["count"] = int(stacks[int(index_by_id[item_id])]["count"]) + 1
			continue
		var item := defs.get_item(item_id) if defs != null else null
		var availability := {"available": false, "reason": &""}
		var usable := item != null and item.use_ability_id != &""
		if usable:
			availability = ActionAvailability.evaluate(state, actor_id, item.use_ability_id, defs)
		var lines: Array[String] = []
		if item != null and usable:
			var ability := defs.get_ability(item.use_ability_id)
			lines = HudViewModel.action_mechanics(actor, ability, defs)
		var stack := {
			"item_id": item_id,
			"name": item.display_name if item != null and not item.display_name.is_empty() else _title(item_id),
			"count": 1,
			"kind": _item_kind(item),
			"lines": lines,
			"description": item.description if item != null else "",
			"usable": usable,
			"available": bool(availability.get("available", false)),
			"unavailable_reason": HudViewModel.availability_reason(StringName(str(availability.get("reason", "")))) if usable and not bool(availability.get("available", false)) else "",
		}
		index_by_id[item_id] = stacks.size()
		stacks.append(stack)
	return stacks


static func _stats(state: BattleState, actor: ActorState, defs: DefinitionLibrary, armor: Dictionary, conditions: Array[Dictionary]) -> Dictionary:
	var abilities: Array[Dictionary] = []
	for ability_id in AbilityCheckRules.ABILITY_SCORES:
		var skills: Array[String] = []
		for skill_id in AbilityCheckRules.SKILL_ABILITIES:
			if AbilityCheckRules.SKILL_ABILITIES[skill_id] == ability_id:
				skills.append(_title(skill_id))
		var modifier := actor.ability_modifier(ability_id)
		var save_proficient := actor.saving_throw_proficiencies.has(ability_id)
		abilities.append({
			"id": ability_id, "abbr": String(ability_id).substr(0, 3).to_upper(), "name": _title(ability_id),
			"score": _score(actor, ability_id), "modifier": modifier,
			"modifier_text": HudViewModel.format_modifier(modifier),
			"save_text": HudViewModel.format_modifier(actor.saving_throw_modifier(ability_id)),
			"save_proficient": save_proficient, "skills": skills,
		})
	var armor_name := ""
	if defs != null and StringName(armor.get("armor_id", &"")) != &"":
		var item := defs.get_item(StringName(armor["armor_id"]))
		armor_name = item.display_name if item != null else _title(StringName(armor["armor_id"]))
	var ac_detail := "%d base" % int(armor["base"])
	if int(armor["dexterity_bonus"]) != 0:
		ac_detail += " %s Dex" % HudViewModel.format_modifier(int(armor["dexterity_bonus"]))
	if int(armor["magic_bonus"]) != 0:
		ac_detail += " %s magic" % HudViewModel.format_modifier(int(armor["magic_bonus"]))
	if not armor_name.is_empty():
		ac_detail += " (%s)" % armor_name
	var speed := actor.movement_remaining if state.phase == &"combat" else actor.movement_speed
	var derived: Array[Dictionary] = [
		{"label": "Armor Class", "value": str(armor["total"]), "detail": ac_detail},
		{"label": "Initiative", "value": HudViewModel.format_modifier(actor.ability_modifier(&"dexterity")), "detail": "Dexterity modifier"},
		{"label": "Proficiency", "value": HudViewModel.format_modifier(actor.proficiency_bonus), "detail": "Proficiency bonus"},
		{"label": "Speed", "value": "%s m%s" % [HudViewModel.format_number(speed), " left" if state.phase == &"combat" else ""], "detail": "Movement"},
		{"label": "Hit Points", "value": "%d / %d" % [actor.hp, actor.max_hp], "detail": "Current / maximum"},
	]
	var limited: Array[Dictionary] = []
	for ability_id in actor.ability_ids:
		var ability := defs.get_ability(ability_id) if defs != null else null
		if ability != null and ability.max_uses >= 0:
			limited.append({"name": ability.display_name if not ability.display_name.is_empty() else _title(ability_id), "remaining": AbilityCostRules.remaining_uses(actor, ability), "maximum": ability.max_uses, "text": "%d/%d" % [AbilityCostRules.remaining_uses(actor, ability), ability.max_uses]})
	return {"abilities": abilities, "derived": derived, "limited_uses": limited, "conditions": conditions}


static func _equipment(actor: ActorState, defs: DefinitionLibrary, armor: Dictionary) -> Dictionary:
	var slots: Array[Dictionary] = []
	for slot in EquipmentRules.SLOT_ORDER:
		var item_id := StringName(actor.equipment_slots.get(slot, &""))
		var item := defs.get_item(item_id) if defs != null and item_id != &"" else null
		var lines: Array[String] = []
		if item != null:
			if slot == EquipmentRules.SLOT_WEAPON:
				var profile := AttackMathRules.weapon_profile(actor, defs)
				lines.append("%s attack" % HudViewModel.format_modifier(int(profile["attack_bonus"])))
				lines.append("%s %s" % [HudViewModel.format_roll(int(profile["damage_dice_count"]), int(profile["damage_die"]), int(profile["damage_modifier"])), String(profile["damage_type"])])
			elif slot == EquipmentRules.SLOT_ARMOR:
				lines.append("%s AC" % HudViewModel.format_modifier(int(armor["total"]) - 10))
		slots.append({"slot": slot, "item_id": item_id, "name": item.display_name if item != null and not item.display_name.is_empty() else "Empty slot", "icon_id": item_id, "lines": lines})
	var profile := AttackMathRules.weapon_profile(actor, defs) if defs != null else {}
	var range := "Melee"
	if defs != null and EquipmentRules.is_ranged_weapon(actor, defs):
		range = "%s m / %s m long" % [HudViewModel.format_number(EquipmentRules.normal_range(actor, defs, 0.0)), HudViewModel.format_number(EquipmentRules.long_range(actor, defs, 0.0))]
	return {"slots": slots, "combat": {"attack": HudViewModel.format_modifier(int(profile.get("attack_bonus", 0))), "damage": "%s %s" % [HudViewModel.format_roll(int(profile.get("damage_dice_count", 0)), int(profile.get("damage_die", 0)), int(profile.get("damage_modifier", 1))), String(profile.get("damage_type", "bludgeoning"))], "range": range, "armor_class": int(armor["total"])}}


static func _score(actor: ActorState, ability_id: StringName) -> int:
	return int(actor.get(String(ability_id)))


static func _item_kind(item: ItemDefinition) -> String:
	if item == null:
		return "Item"
	if item.slot == EquipmentRules.SLOT_WEAPON:
		return "Weapon"
	if item.slot == EquipmentRules.SLOT_ARMOR:
		return "Armor"
	return "Consumable" if item.use_ability_id != &"" else "Item"


static func _title(id: StringName) -> String:
	return String(id).replace("_", " ").capitalize()
