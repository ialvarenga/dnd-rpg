class_name SaveGame
extends RefCounted

## Authoritative save snapshot (Fase A8). This is deliberately NOT
## seed + initial_state + command_log: future rule/content/balance changes
## must not silently reinterpret an old run (see the "Important correction"
## in implementation_plan.md, Fase A8). ReplayLog is the separate,
## non-authoritative debug/regression artifact built on top of the same
## command pipeline.
##
## schema_version describes the shape of this dict; rules_version and
## content_version describe the meaning of the BattleState it carries. A
## loader must check all three before trusting a save (see is_compatible).

## Fase C2 bump: ActorState now serializes ability_ids/equipment_slots/
## inventory/definition_id. Bump 4 adds persistent actor coin wallets.
## Bump 5: ActorState drops armor_class/attack_bonus/damage_die/damage_modifier
## (now derived by AttackMath) and serializes weapon_proficiencies.
const SCHEMA_VERSION: int = 5
const GAME_VERSION: String = "0.1.0"

var schema_version: int = SCHEMA_VERSION
var game_version: String = GAME_VERSION
var rules_version: int = Resolver.RULES_VERSION
var content_version: int = DefinitionLibrary.CONTENT_VERSION
var map_id: String = ""
var battle_state: BattleState = BattleState.new()

## Door/chest/lever state (Fase A9) lives in battle_state.interactables --
## Resolver reads and mutates it deterministically like actors, so it has to
## be inside the state the resolver sees, not out here. This field stays
## reserved for future non-authoritative, non-resolver world bookkeeping
## (e.g. map/scene progress flags) that never needs to affect resolution.
var world_state: Dictionary = {}


static func create(state: BattleState, save_map_id: String = "", state_world: Dictionary = {}) -> SaveGame:
	var save := SaveGame.new()
	save.battle_state = state
	save.map_id = save_map_id
	save.world_state = state_world
	return save


## True when a loader running the current rules/content can trust this save's
## battle_state as-is. False means either the dict shape changed
## (schema_version) or the same shape now means something different
## (rules_version/content_version) -- either way, load() should refuse rather
## than guess.
func is_compatible(current_rules_version: int = Resolver.RULES_VERSION, current_content_version: int = DefinitionLibrary.CONTENT_VERSION) -> bool:
	return (
		schema_version == SCHEMA_VERSION
		and rules_version == current_rules_version
		and content_version == current_content_version
	)


func to_dict() -> Dictionary:
	return {
		"schema_version": schema_version,
		"game_version": game_version,
		"rules_version": rules_version,
		"content_version": content_version,
		"map_id": map_id,
		"battle_state": battle_state.to_dict(),
		"world_state": SimulationSerialization.value_to_data(world_state),
	}


static func from_dict(data: Dictionary) -> SaveGame:
	var save := SaveGame.new()
	save.schema_version = int(data.get("schema_version", SCHEMA_VERSION))
	save.game_version = str(data.get("game_version", GAME_VERSION))
	save.rules_version = int(data.get("rules_version", Resolver.RULES_VERSION))
	save.content_version = int(data.get("content_version", DefinitionLibrary.CONTENT_VERSION))
	save.map_id = str(data.get("map_id", ""))
	var battle_data: Variant = data.get("battle_state", {})
	save.battle_state = BattleState.from_dict(battle_data) if battle_data is Dictionary else BattleState.new()
	var restored_world: Variant = SimulationSerialization.data_to_value(data.get("world_state", {}))
	save.world_state = restored_world if restored_world is Dictionary else {}
	return save
