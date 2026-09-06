class_name DefinitionLibrary
extends RefCounted

## Runtime lookup for AbilityDefinition/ConditionDefinition/ItemDefinition/
## ActorDefinition content, indexed by stable id. This is the single source
## of truth for all four catalogs: Resolver, ActorState, and Equipment
## consult it instead of branching on concrete content ids.
##
## The default library loads a fixed, explicit manifest of resource paths --
## no directory scanning -- so content stays deterministic across runs. Tests
## may build an alternate DefinitionLibrary (via `add_ability`/`add_condition`/
## `add_item`/`add_actor`) to prove behavior is actually read from data and to
## exercise unknown-id rejection paths.

## Bumped whenever the shape or meaning of shipped content changes, so saves
## (A8) can carry/validate a content_version alongside rules/schema versioning.
## Fase C3 bump: adds the raider actor definition used by map encounters.
const CONTENT_VERSION: int = 3

const ABILITY_MANIFEST: Array[String] = [
	"res://data/abilities/basic_attack.tres",
	"res://data/abilities/dash.tres",
	"res://data/abilities/disengage.tres",
]

const CONDITION_MANIFEST: Array[String] = [
	"res://data/conditions/poisoned.tres",
	"res://data/conditions/prone.tres",
	"res://data/conditions/unconscious.tres",
	"res://data/conditions/dead.tres",
]

const ITEM_MANIFEST: Array[String] = [
	"res://data/items/longsword.tres",
	"res://data/items/leather_armor.tres",
]

const ACTOR_MANIFEST: Array[String] = [
	"res://data/actors/knight.tres",
	"res://data/actors/raider.tres",
]

var content_version: int = CONTENT_VERSION
var abilities: Dictionary = {}
var conditions: Dictionary = {}
var items: Dictionary = {}
var actors: Dictionary = {}

static var _default: DefinitionLibrary = null


static func get_default() -> DefinitionLibrary:
	if _default == null:
		_default = load_from_manifests(ABILITY_MANIFEST, CONDITION_MANIFEST, ITEM_MANIFEST, ACTOR_MANIFEST)
	return _default


## Test-only escape hatch: forces the next get_default() call to reload from
## disk. Production code never needs this; content is immutable for the life
## of a process.
static func reset_default() -> void:
	_default = null


static func load_from_manifests(ability_paths: Array[String], condition_paths: Array[String], item_paths: Array[String] = [], actor_paths: Array[String] = []) -> DefinitionLibrary:
	var library := DefinitionLibrary.new()
	for path in ability_paths:
		var resource: Resource = load(path)
		if resource is AbilityDefinition:
			library.add_ability(resource)
		else:
			push_error("Invalid AbilityDefinition resource at %s" % path)
	for path in condition_paths:
		var condition_resource: Resource = load(path)
		if condition_resource is ConditionDefinition:
			library.add_condition(condition_resource)
		else:
			push_error("Invalid ConditionDefinition resource at %s" % path)
	for path in item_paths:
		var item_resource: Resource = load(path)
		if item_resource is ItemDefinition:
			library.add_item(item_resource)
		else:
			push_error("Invalid ItemDefinition resource at %s" % path)
	for path in actor_paths:
		var actor_resource: Resource = load(path)
		if actor_resource is ActorDefinition:
			library.add_actor(actor_resource)
		else:
			push_error("Invalid ActorDefinition resource at %s" % path)
	return library


func add_ability(definition: AbilityDefinition) -> void:
	if String(definition.id) == "":
		push_error("AbilityDefinition missing stable id")
		return
	if abilities.has(definition.id):
		push_error("Duplicate AbilityDefinition id: %s" % definition.id)
	abilities[definition.id] = definition


func add_condition(definition: ConditionDefinition) -> void:
	if String(definition.id) == "":
		push_error("ConditionDefinition missing stable id")
		return
	if conditions.has(definition.id):
		push_error("Duplicate ConditionDefinition id: %s" % definition.id)
	conditions[definition.id] = definition


func add_item(definition: ItemDefinition) -> void:
	if String(definition.id) == "":
		push_error("ItemDefinition missing stable id")
		return
	if items.has(definition.id):
		push_error("Duplicate ItemDefinition id: %s" % definition.id)
	items[definition.id] = definition


func add_actor(definition: ActorDefinition) -> void:
	if String(definition.id) == "":
		push_error("ActorDefinition missing stable id")
		return
	if actors.has(definition.id):
		push_error("Duplicate ActorDefinition id: %s" % definition.id)
	actors[definition.id] = definition


func get_ability(id: StringName) -> AbilityDefinition:
	return abilities.get(id)


func get_condition(id: StringName) -> ConditionDefinition:
	return conditions.get(id)


func get_item(id: StringName) -> ItemDefinition:
	return items.get(id)


func get_actor(id: StringName) -> ActorDefinition:
	return actors.get(id)


func has_ability(id: StringName) -> bool:
	return abilities.has(id)


func has_condition(id: StringName) -> bool:
	return conditions.has(id)


func has_item(id: StringName) -> bool:
	return items.has(id)


func has_actor(id: StringName) -> bool:
	return actors.has(id)


## Insertion order for each catalog matches its manifest, since GDScript
## Dictionary preserves insertion order -- these accessors just make that
## intent explicit for ordered iteration (ADR-001/ADR-004) instead of callers
## reaching for `.keys()` on the raw dictionaries.
func ordered_ability_ids() -> Array[StringName]:
	return _ordered_keys(abilities)


func ordered_condition_ids() -> Array[StringName]:
	return _ordered_keys(conditions)


func ordered_item_ids() -> Array[StringName]:
	return _ordered_keys(items)


func ordered_actor_ids() -> Array[StringName]:
	return _ordered_keys(actors)


func is_compatible_content_version(saved_version: int) -> bool:
	return saved_version == content_version


func _ordered_keys(catalog: Dictionary) -> Array[StringName]:
	var ids: Array[StringName] = []
	for id in catalog.keys():
		ids.append(id)
	return ids
