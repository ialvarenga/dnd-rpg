class_name ReplayLog
extends RefCounted

## Debug/regression artifact (Fase A8) -- NOT the authoritative save; see
## SaveGame for that. Captures the state a command sequence started from,
## the exact commands resolved against it, and the event-log hash produced
## after each one. A development build can later replay the same commands
## from initial_snapshot and diff the resulting hashes to catch resolver or
## content regressions ("same state + same command -> same result").

var initial_snapshot: BattleState = BattleState.new()
var rules_version: int = Resolver.RULES_VERSION
var content_version: int = DefinitionLibrary.CONTENT_VERSION
var commands: Array[Command] = []
var event_hashes: Array[String] = []


static func start(state: BattleState) -> ReplayLog:
	var log := ReplayLog.new()
	log.initial_snapshot = state.clone()
	return log


## Call once per command as it is actually resolved during play, so the log
## reflects what really happened rather than a re-derivation after the fact.
func append_command(command: Command, result: ResolutionResult) -> void:
	commands.append(command)
	event_hashes.append(hash_events(result.events, result.next_rng_state))


## Re-resolves every recorded command from a fresh clone of initial_snapshot
## and returns the indices whose hash no longer matches what was recorded.
## An empty result means the replay reproduced the log exactly.
func find_divergences(nav: NavProvider, los: LosProvider, defs: DefinitionLibrary = null) -> Array[int]:
	var divergent_indices: Array[int] = []
	var state := initial_snapshot.clone()
	for index in range(commands.size()):
		var command: Command = commands[index]
		var result := Resolver.resolve(state, command, nav, los, defs)
		var actual_hash := hash_events(result.events, result.next_rng_state)
		var expected_hash := event_hashes[index] if index < event_hashes.size() else ""
		if actual_hash != expected_hash:
			divergent_indices.append(index)
		for event in result.events:
			Resolver.apply(state, event)
		state.rng_state = result.next_rng_state
	return divergent_indices


static func hash_events(events: Array[Event], next_rng_state: int) -> String:
	var entries: Array[String] = []
	for event in events:
		entries.append(JSON.stringify(event.to_dict()))
	entries.append("rng:%d" % next_rng_state)
	return "|".join(entries).md5_text()


func to_dict() -> Dictionary:
	var command_data: Array[Dictionary] = []
	for command in commands:
		command_data.append(command.to_dict())
	return {
		"initial_snapshot": initial_snapshot.to_dict(),
		"rules_version": rules_version,
		"content_version": content_version,
		"commands": command_data,
		"event_hashes": event_hashes.duplicate(),
	}


static func from_dict(data: Dictionary) -> ReplayLog:
	var log := ReplayLog.new()
	var snapshot_data: Variant = data.get("initial_snapshot", {})
	log.initial_snapshot = BattleState.from_dict(snapshot_data) if snapshot_data is Dictionary else BattleState.new()
	log.rules_version = int(data.get("rules_version", Resolver.RULES_VERSION))
	log.content_version = int(data.get("content_version", DefinitionLibrary.CONTENT_VERSION))
	for command_data in data.get("commands", []):
		if command_data is Dictionary:
			log.commands.append(Command.from_dict(command_data))
	for hash_value in data.get("event_hashes", []):
		log.event_hashes.append(str(hash_value))
	return log
