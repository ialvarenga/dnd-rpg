class_name DefinitionLibrary
extends RefCounted

## Runtime lookup for AbilityDefinition/ConditionDefinition content, indexed by
## stable id. This is the single source of truth for both catalogs: Resolver
## and ActorState consult it instead of branching on concrete content ids.
##
## The default library loads a fixed, explicit manifest of resource paths --
## no directory scanning -- so content stays deterministic across runs. Tests
## may build an alternate DefinitionLibrary (via `add_ability`/`add_condition`)
## to prove behavior is actually read from data and to exercise unknown-id
## rejection paths.

## Bumped whenever the shape or meaning of shipped content changes, so saves
## (A8) can carry/validate a content_version alongside rules/schema versioning.
const CONTENT_VERSION: int = 1

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

var content_version: int = CONTENT_VERSION
var abilities: Dictionary = {}
var conditions: Dictionary = {}

static var _default: DefinitionLibrary = null


static func get_default() -> DefinitionLibrary:
	if _default == null:
		_default = load_from_manifests(ABILITY_MANIFEST, CONDITION_MANIFEST)
	return _default


## Test-only escape hatch: forces the next get_default() call to reload from
## disk. Production code never needs this; content is immutable for the life
## of a process.
static func reset_default() -> void:
	_default = null


static func load_from_manifests(ability_paths: Array[String], condition_paths: Array[String]) -> DefinitionLibrary:
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


func get_ability(id: StringName) -> AbilityDefinition:
	return abilities.get(id)


func get_condition(id: StringName) -> ConditionDefinition:
	return conditions.get(id)


func has_ability(id: StringName) -> bool:
	return abilities.has(id)


func has_condition(id: StringName) -> bool:
	return conditions.has(id)


func is_compatible_content_version(saved_version: int) -> bool:
	return saved_version == content_version
