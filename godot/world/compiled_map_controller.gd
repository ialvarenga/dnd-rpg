class_name CompiledMapController
extends Node3D

## Small player-facing B11 harness. Generated maps use the same Command/Event
## movement pipeline as the arena and expose the objective as a visible marker.

@export var map_spec_path := "../world_authoring/maps/test_map.json"

var compilation: MapCompilationResult
var nav_provider: NavProvider
var battle_state := BattleState.new()
var session
var los_provider: LosProvider
var map_source
var character: CharacterView
var event_player: EventPlayer
var camera: Camera3D
var camera_rig: TacticalCameraRig
var objective: Vector3
var _path_line: MeshInstance3D
var _line_mesh := ImmediateMesh.new()
var _preview_path := PackedVector3Array()
var _destination_marker: DestinationClickMarker
var hud: HudRoot
var hostile_views: Dictionary[int, CharacterView] = {}
var encounter_definitions: Dictionary[String, Dictionary] = {}
var authored_actor_ids: Dictionary[String, int] = {}
var detection_range := 8.0
var _enemy_action_cooldown := 0.0
var _targeting_ability_id: StringName = &""
var _highlighted_target_id := -1
var _highlighted_interactable_id := ""
var _interactable_highlights: Dictionary[String, MeshInstance3D] = {}
var _pending_interactable_id := ""
var _pending_targeted_action: Dictionary = {}
var _dialog_catalog: DialogCatalogScript
var _dialog_session: DialogSessionScript
var _interactable_highlight_time := 0.0
var music
var _encounter_checkpoint: BattleState
var _encounter_start_command: Command
var _pending_victory_overlay := false

const QUICKSAVE_SLOT := "quicksave"
const AUTOSAVE_SLOT := "autosave"

const EnemyAIScript = preload("res://ai/enemy_ai.gd")
const AbilityTargetingRules = preload("res://sim/ability_targeting.gd")
const ObjectiveStateScript = preload("res://sim/objective_state.gd")

const PLAYER_CHARACTER_SCENE = preload("res://scenes/actors/player_character.tscn")
const TACTICAL_CAMERA_SCENE = preload("res://scenes/camera/tactical_camera_rig.tscn")
const OBJECTIVE_MARKER_SCENE = preload("res://scenes/world/objective_marker.tscn")
const TACTICAL_SUN_SCENE = preload("res://scenes/world/tactical_sun.tscn")
const EncounterSessionScript = preload("res://world/encounter_session.gd")
const MapSpecSourceScript = preload("res://world/map_spec_source.gd")
const ScreenPickerScript = preload("res://world/screen_picker.gd")
const DialogCatalogScript = preload("res://world/dialog_catalog.gd")
const DialogSessionScript = preload("res://world/dialog_session.gd")
const MusicDirectorScript = preload("res://view/music_director.gd")
const WORLD_HEALTH_BAR_SCENE = preload("res://view/ui/world_health_bar.tscn")
const PathPreviewRendererScript = preload("res://view/path_preview_renderer.gd")
const DestinationClickMarkerScript = preload("res://view/destination_click_marker.gd")

const INTERACTABLE_READY_COLOR := Color("76e887")
const INTERACTABLE_APPROACH_COLOR := Color("f5d742")
const INTERACTABLE_BLOCKED_COLOR := Color("ef625d")

## MapSpec interactable kinds this map runtime owns. Every other kind is
## authored as scenery: compiled and collision-checked, never registered.
const REGISTERED_INTERACTABLE_KINDS: Array[StringName] = [&"chest", &"barrel"]

## Stat block used for an authored enemy that names none. Keeps maps written
## before MapSpec actor.stat_block existed spawning exactly as they did.
const DEFAULT_ENEMY_STAT_BLOCK := &"raider"

## Ability that opens a conversation. Named here rather than inlined so the
## click handler and the approach planner agree. It is deliberately contextual
## and never appears in the player's persistent hotbar.
const TALK_ABILITY := &"talk"

## How long the rolled check stays on screen before the conversation moves on,
## so the player reads the number instead of only its consequence.
const CHECK_REVEAL_SECONDS := 1.4


func _ready() -> void:
	print("[CompiledMapController] loading MapSpec '%s'" % map_spec_path)
	map_source = MapSpecSourceScript.new(map_spec_path)
	var spec := _load_spec()
	if spec.is_empty():
		var load_message := "MapSpec load failed:\n\n%s" % map_source.last_error
		push_error(load_message)
		_show_error(load_message)
		return
	compilation = MapCompiler.new().compile(spec)
	if not compilation.is_valid():
		push_error("Map compilation failed: %s" % compilation.error_dicts())
		_show_compile_errors()
		return
	add_child(compilation.root)
	_setup_player()
	_setup_objectives(spec)
	_setup_pickups(spec)
	_setup_interactables(spec)
	_setup_hostiles(spec)
	_setup_encounters(spec)
	_setup_camera()
	_setup_light()
	_setup_path_preview()
	_setup_destination_marker()
	nav_provider = GodotNavProvider.new(compilation.navigation.navigation_region)
	los_provider = GodotLosProvider.new(get_world_3d(), 8)
	session = EncounterSessionScript.new()
	session.configure(battle_state, nav_provider, los_provider)
	session.state_changed.connect(_update_world_health_bars)
	session.events_resolved.connect(_on_outcome_events_resolved)
	_update_world_health_bars()
	_setup_music(compilation.music)
	_setup_hud()
	_setup_dialogs(spec)
	NavigationServer3D.map_force_update(compilation.navigation.navigation_region.get_navigation_map())


func _unhandled_input(event: InputEvent) -> void:
	if camera == null or nav_provider == null:
		return
	if hud != null and hud.is_world_paused():
		get_viewport().set_input_as_handled()
		return
	if battle_state.phase == &"game_over":
		get_viewport().set_input_as_handled()
		return
	if _dialog_session != null and _dialog_session.is_active():
		# The panel's own buttons still receive input; everything that would
		# move or attack from the world below it does not.
		get_viewport().set_input_as_handled()
		return
	if battle_state.phase == &"combat" and _presentation_busy(character):
		# The simulation commits movement immediately, while the CharacterView
		# catches up over several frames. Keep combat input behind that visual
		# barrier so an attack cannot appear to land from the old position.
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		if _targeting_ability_id != &"":
			_clear_interactable_highlight()
			_update_target_highlight(_hostile_at_screen_position(event.position, _targeting_ability_id))
			return
		var hovered := _hostile_at_screen_position(event.position, TALK_ABILITY)
		if hovered != null and _dialog_id_for_actor(hovered.actor_id) != &"":
			_clear_interactable_highlight()
			_clear_path_preview()
			_update_target_highlight(hovered, TALK_ABILITY)
			return
		_update_target_highlight(null, TALK_ABILITY)
		var hovered_interactable_id := ScreenPickerScript.interactable_id(camera, get_world_3d().direct_space_state, event.position)
		if not _pending_interactable_id.is_empty():
			return
		_update_interactable_highlight(hovered_interactable_id)
		if not hovered_interactable_id.is_empty():
			_clear_path_preview()
			return
		var preview_target: Variant = ScreenPickerScript.terrain_point(camera, get_world_3d().direct_space_state, event.position)
		if preview_target is Vector3:
			_show_path_preview(preview_target)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var interactable_id := ScreenPickerScript.interactable_id(camera, get_world_3d().direct_space_state, event.position)
		if interactable_id != "":
			_pending_targeted_action.clear()
			_clear_targeting()
			_approach_interactable(interactable_id)
			get_viewport().set_input_as_handled()
			return
		_cancel_pending_interaction()
		_pending_targeted_action.clear()
		_clear_interactable_highlight()
		var hovered_ability := _targeting_ability_id if _targeting_ability_id != &"" else TALK_ABILITY
		var hostile := _hostile_at_screen_position(event.position, hovered_ability)
		if _targeting_ability_id != &"":
			if hostile != null:
				_submit_targeted_ability(hostile.actor_id)
			get_viewport().set_input_as_handled()
			return
		if hostile != null and _dialog_id_for_actor(hostile.actor_id) != &"":
			# Talking reuses the ordinary approach-then-act path: `talk` is an
			# ability with a range like any other, so the walk-into-range
			# machinery needs no special case.
			_targeting_ability_id = TALK_ABILITY
			_submit_targeted_ability(hostile.actor_id)
			get_viewport().set_input_as_handled()
			return
		if hostile != null:
			# Clicking an NPC is movement, not an implicit attack. Attacks remain
			# explicit through the selected targeting ability.
			_move(hostile.global_position)
			get_viewport().set_input_as_handled()
			return
		var target: Variant = ScreenPickerScript.terrain_point(camera, get_world_3d().direct_space_state, event.position)
		if target is Vector3:
			_show_exploration_destination(target)
			_show_path_preview(target)
			_move(target)
		get_viewport().set_input_as_handled()


func _load_spec() -> Dictionary:
	return map_source.load_spec()


func _setup_player() -> void:
	var spec := _load_spec()
	var spawns: Array = spec.get("spawn_points", [])
	var point := Vector2(2, 2) if spawns.is_empty() else Vector2(float(spawns[0].position[0]), float(spawns[0].position[1]))
	character = PLAYER_CHARACTER_SCENE.instantiate() as CharacterView
	character.name = "Player"
	character.actor_id = 1
	character.position = Vector3(point.x, compilation.terrain.height_at(point.x, point.y) + 1.0, point.y)
	_dress_player(character, spec.get("player", {}))
	add_child(character)
	event_player = EventPlayer.new()
	add_child(event_player)
	event_player.register_character_view(character)
	event_player.movement_completed.connect(_synchronize_completed_movement)
	battle_state.phase = &"exploration"
	battle_state.rng_seed = 1
	battle_state.rng_state = 1
	var knight := DefinitionLibrary.get_default().get_actor(&"knight")
	var actor := ActorState.from_definition(knight, 1, &"heroes", character.global_position)
	battle_state.actors[1] = actor
	character.configure_weapon_presentation(Equipment.weapon(actor, DefinitionLibrary.get_default()))
	_attach_world_health_bar(character)


func _setup_objectives(spec: Dictionary) -> void:
	for raw_objective in spec.get("objectives", []):
		var position_data: Array = raw_objective.get("position", [])
		if position_data.size() != 2:
			continue
		var state: ObjectiveStateScript = ObjectiveStateScript.new()
		state.id = str(raw_objective.get("id", ""))
		state.position = Vector3(float(position_data[0]), compilation.terrain.height_at(float(position_data[0]), float(position_data[1])), float(position_data[1]))
		state.radius_m = float(raw_objective.get("radius_m", 2.0))
		for encounter_id in raw_objective.get("requires_encounter_ids", []):
			state.requires_encounter_ids.append(str(encounter_id))
		battle_state.objectives[state.id] = state
		if objective == Vector3.ZERO:
			objective = state.position
			var marker := OBJECTIVE_MARKER_SCENE.instantiate() as MeshInstance3D
			marker.position = objective + Vector3.UP * 0.2
			add_child(marker)


func _setup_pickups(spec: Dictionary) -> void:
	for raw_pickup in spec.get("pickups", []):
		var pickup_id := str(raw_pickup.get("id", ""))
		var position_data: Array = raw_pickup.get("position", [])
		if pickup_id.is_empty() or position_data.size() != 2:
			continue
		var pickup := InteractableState.new()
		pickup.id = pickup_id
		pickup.type = &"pickup"
		pickup.state = &"ready"
		pickup.position = Vector3(float(position_data[0]), compilation.terrain.height_at(float(position_data[0]), float(position_data[1])), float(position_data[1]))
		pickup.interact_range = 2.0
		pickup.contents = [StringName(str(raw_pickup.get("item_id", "healing_potion")))]
		battle_state.interactables[pickup.id] = pickup
		var pickup_view := compilation.root.get_node_or_null(NodePath(pickup_id))
		if pickup_view != null:
			pickup_view.set_meta("interactable_id", pickup.id)
			_remember_interaction_layers(pickup_view)
			var asset_id := StringName(str(raw_pickup.get("asset", "")))
			_register_interactable_highlight(pickup.id, pickup_view as Node3D, asset_id)


## Authored containers become runtime interactables here, mirroring
## _setup_pickups: MapCompiler stays presentation-only and BattleState owns
## every interactable's authoritative state.
func _setup_interactables(spec: Dictionary) -> void:
	for raw_interactable in spec.get("interactables", []):
		var interactable_id := str(raw_interactable.get("id", ""))
		var kind := StringName(str(raw_interactable.get("kind", "")))
		var position_data: Array = raw_interactable.get("position", [])
		if interactable_id.is_empty() or position_data.size() != 2 or not REGISTERED_INTERACTABLE_KINDS.has(kind):
			continue
		var interactable := InteractableState.new()
		interactable.id = interactable_id
		interactable.type = kind
		interactable.state = &"closed"
		interactable.position = Vector3(float(position_data[0]), compilation.terrain.height_at(float(position_data[0]), float(position_data[1])), float(position_data[1]))
		interactable.interact_range = 2.0
		for item_id in raw_interactable.get("contents", []):
			interactable.contents.append(StringName(str(item_id)))
		battle_state.interactables[interactable.id] = interactable
		var asset_id := StringName(str(raw_interactable.get("asset", "")))
		var interactable_view := compilation.root.get_node_or_null(NodePath(interactable_id)) as Node3D
		_attach_pick_collider(interactable_view, interactable_id, asset_id)
		_register_interactable_highlight(interactable.id, interactable_view, asset_id)


## Compiled props are bare catalog art -- AssetCatalog.instantiate() returns the
## glTF scene itself, with no collider -- so screen picking needs a body of its
## own. ScreenPicker reads the meta off whichever collider its ray hits, so the
## id lives on the body rather than on the art node above it.
func _attach_pick_collider(view: Node3D, interactable_id: String, asset_id: StringName) -> void:
	if view == null:
		return
	var definition := AssetCatalog.get_definition(asset_id)
	var body := StaticBody3D.new()
	body.name = "InteractPicker"
	body.collision_layer = 4
	body.collision_mask = 0
	body.set_meta("interactable_id", interactable_id)
	var cylinder := CylinderShape3D.new()
	cylinder.radius = maxf(0.5, definition.footprint_radius if definition != null else 0.5)
	cylinder.height = 2.0
	var collision := CollisionShape3D.new()
	collision.shape = cylinder
	collision.position = Vector3.UP * (cylinder.height * 0.5)
	body.add_child(collision)
	view.add_child(body)
	_remember_interaction_layers(view)


## Interactables use the same ground-marker language as actor targeting. The
## marker is presentation-only and stays attached to the item while it is
## hovered, approached, and acted upon.
func _register_interactable_highlight(interactable_id: String, view: Node3D, asset_id: StringName) -> void:
	if view == null:
		return
	var definition := AssetCatalog.get_definition(asset_id)
	var radius := maxf(0.55, definition.footprint_radius if definition != null else 0.55)
	var highlight := MeshInstance3D.new()
	highlight.name = "InteractableHighlight"
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius + 0.22
	mesh.bottom_radius = radius + 0.22
	mesh.height = 0.035
	mesh.radial_segments = 32
	highlight.mesh = mesh
	highlight.position = Vector3.UP * 0.08
	highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	highlight.material_override = material
	highlight.visible = false
	view.add_child(highlight)
	_interactable_highlights[interactable_id] = highlight


## Actors are visual map data until this composition root turns hostile ones
## into views plus authoritative ActorState entries. This keeps MapCompiler
## presentation-only and makes each encounter deterministic/replayable.
func _setup_hostiles(spec: Dictionary) -> void:
	var actor_id := 2
	for raw_actor in spec.get("actors", []):
		if String(raw_actor.get("side", "enemies")) != "enemies":
			continue
		var position_data: Array = raw_actor.get("position", [])
		if position_data.size() != 2:
			continue
		var asset_id := StringName(raw_actor.get("archetype", ""))
		var definition := AssetCatalog.get_definition(asset_id)
		if definition == null or definition.asset_type != &"character":
			continue
		var hostile := PLAYER_CHARACTER_SCENE.instantiate() as CharacterView
		hostile.name = "Hostile_%s" % raw_actor.get("id", actor_id)
		hostile.actor_id = actor_id
		hostile.position = Vector3(float(position_data[0]), compilation.terrain.height_at(float(position_data[0]), float(position_data[1])) + 1.0, float(position_data[1]))
		hostile.set_meta("hostile_actor_id", actor_id)
		var authored_id := str(raw_actor.get("id", actor_id))
		authored_actor_ids[authored_id] = actor_id
		add_child(hostile)
		AssetCatalog.dress(hostile, asset_id)
		var compiled_visual := compilation.root.get_node_or_null(String(raw_actor.get("id", ""))) as Node3D
		if compiled_visual != null:
			compiled_visual.visible = false
		event_player.register_character_view(hostile)
		hostile.movement_completed.connect(_synchronize_completed_movement)
		hostile_views[actor_id] = hostile
		# Stats are authored per actor instance. `archetype` still picks the art
		# only, so the same model can be a scout on one map and a chieftain on
		# another; an unknown or absent stat_block falls back to the default
		# block rather than silently spawning an actor with no stats.
		var definitions := DefinitionLibrary.get_default()
		var stat_block_id := StringName(str(raw_actor.get("stat_block", DEFAULT_ENEMY_STAT_BLOCK)))
		if not definitions.has_actor(stat_block_id):
			push_error("Actor '%s' names unknown stat_block '%s'; falling back to '%s'" % [authored_id, stat_block_id, DEFAULT_ENEMY_STAT_BLOCK])
			stat_block_id = DEFAULT_ENEMY_STAT_BLOCK
		var hostile_actor := ActorState.from_definition(definitions.get_actor(stat_block_id), actor_id, &"enemies", hostile.global_position)
		# Social stance and conversation are per-instance map data, never part of
		# the stat block -- see ActorState.disposition / dialog_id.
		hostile_actor.disposition = StringName(str(raw_actor.get("initial_disposition", "hostile")))
		hostile_actor.dialog_id = StringName(str(raw_actor.get("dialog", "")))
		battle_state.actors[actor_id] = hostile_actor
		hostile.configure_weapon_presentation(Equipment.weapon(hostile_actor, definitions))
		_attach_world_health_bar(hostile)
		actor_id += 1


func _setup_encounters(spec: Dictionary) -> void:
	for raw_encounter in spec.get("encounters", []):
		var encounter_id := str(raw_encounter.get("id", ""))
		if encounter_id.is_empty():
			continue
		var combatant_ids: Array[int] = [character.actor_id]
		for authored_id in raw_encounter.get("actor_ids", []):
			var actor_id := int(authored_actor_ids.get(str(authored_id), -1))
			if actor_id >= 0 and not combatant_ids.has(actor_id):
				combatant_ids.append(actor_id)
		combatant_ids.sort()
		encounter_definitions[encounter_id] = {
			"id": encounter_id,
			"combatant_ids": combatant_ids,
			"trigger_radius_m": float(raw_encounter.get("trigger_radius_m", detection_range)),
		}


## Health bars are a read-only projection of already-applied session state.
## They deliberately do not inspect events or participate in combat resolution.
func _attach_world_health_bar(view: CharacterView) -> void:
	if view == null or not is_instance_valid(view):
		return
	var bar := view.get_node_or_null("WorldHealthBar") as WorldHealthBar
	if bar == null:
		bar = WORLD_HEALTH_BAR_SCENE.instantiate() as WorldHealthBar
		if bar == null:
			return
		bar.name = "WorldHealthBar"
		bar.position = Vector3.UP * 2.0
		view.add_child(bar)
	_update_world_health_bar(view)


func _update_world_health_bars() -> void:
	_update_world_health_bar(character)
	for hostile in hostile_views.values():
		_update_world_health_bar(hostile as CharacterView)


func _update_world_health_bar(view: CharacterView) -> void:
	if view == null or not is_instance_valid(view) or not battle_state.actors.has(view.actor_id):
		return
	var bar := view.get_node_or_null("WorldHealthBar") as WorldHealthBar
	var actor := battle_state.actors.get(view.actor_id) as ActorState
	if bar == null or actor == null:
		return
	bar.fraction = clampf(float(actor.hp) / maxf(1.0, float(actor.max_hp)), 0.0, 1.0)


func _process(delta: float) -> void:
	if session == null or character == null:
		return
	if hud != null and hud.is_world_paused():
		return
	_animate_interactable_highlight(delta)
	if music != null:
		music.set_phase(battle_state.phase)
	if battle_state.phase == &"game_over":
		_clear_path_preview()
		return
	if battle_state.phase == &"exploration":
		_clear_path_preview()
		# Detection is _process-driven, so the panel's mouse_filter alone would
		# not stop a sentry noticing you mid-sentence.
		if _dialog_session == null or not _dialog_session.is_active():
			_check_hostile_detection()
		return
	if _destination_marker != null:
		_destination_marker.hide_marker()
	PathPreviewRendererScript.draw(_line_mesh, _preview_path, character.global_position)
	_enemy_action_cooldown = maxf(0.0, _enemy_action_cooldown - delta)
	if _enemy_action_cooldown <= 0.0:
		_take_enemy_turn()


func _check_hostile_detection() -> void:
	var player := battle_state.actors.get(character.actor_id) as ActorState
	if player == null or not player.is_conscious() or battle_state.game_outcome != &"ongoing":
		return
	var encounter_ids: Array = encounter_definitions.keys()
	encounter_ids.sort()
	for encounter_id in encounter_ids:
		if battle_state.cleared_encounter_ids.has(encounter_id):
			continue
		var encounter: Dictionary = encounter_definitions[encounter_id]
		for actor_id in encounter.combatant_ids:
			if actor_id == character.actor_id or not hostile_views.has(actor_id) or not battle_state.actors.has(actor_id):
				continue
			var hostile := hostile_views[actor_id] as CharacterView
			var hostile_state := battle_state.actors[actor_id] as ActorState
			if hostile == null or not hostile_state.is_conscious():
				continue
			# A pacified or peaceable actor stays in the encounter roster (so a
			# fight started another way still includes them) but does not start
			# one itself.
			if hostile_state.disposition != &"hostile":
				continue
			if character.global_position.distance_to(hostile.global_position) <= float(encounter.trigger_radius_m) and los_provider.has_line_of_sight(hostile.global_position, character.global_position):
				var start := Command.create(&"start_combat", actor_id)
				start.metadata = {"encounter_id": encounter_id, "participant_actor_ids": encounter.combatant_ids.duplicate()}
				_start_encounter(start, true)
				return


## A view still catching up to the simulation (walking, falling, drawing) or
## an arrow still in flight: the next command waits for either, so nothing is
## narrated out of order.
func _presentation_busy(view: CharacterView) -> bool:
	return (view != null and view.is_presentation_busy()) or (event_player != null and event_player.is_busy())


func _take_enemy_turn() -> void:
	var actor_id := battle_state.current_actor_id()
	var hostile_view := hostile_views.get(actor_id) as CharacterView
	if hostile_view == null or _presentation_busy(hostile_view):
		# Authoritative movement is applied before its presentation completes.
		# Do not resolve the enemy's next action against that still-distant view,
		# nor attack while its turn-start stand-up is still playing.
		return
	var command: Command = EnemyAIScript.new().choose_command(battle_state, actor_id, nav_provider, los_provider)
	if command == null:
		return
	var result: ResolutionResult = session.submit_command(command)
	event_player.play_events(result.events)
	_enemy_action_cooldown = 0.45


func _start_encounter(start: Command, capture_checkpoint: bool) -> void:
	if capture_checkpoint:
		_encounter_checkpoint = battle_state.clone()
		_encounter_start_command = Command.from_dict(start.to_dict())
	var result: ResolutionResult = session.submit_command(start)
	event_player.play_events(result.events)
	_enemy_action_cooldown = 0.4
	if capture_checkpoint:
		_save_game(AUTOSAVE_SLOT, "Autosaved at encounter start.")


func _hostile_at_screen_position(screen_position: Vector2, ability_id: StringName = &"") -> CharacterView:
	var query := PhysicsRayQueryParameters3D.create(camera.project_ray_origin(screen_position), camera.project_ray_origin(screen_position) + camera.project_ray_normal(screen_position) * 250.0, 2)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var collider := hit.get("collider") as Node
	if collider is CharacterView and (collider as CharacterView).actor_id != character.actor_id:
		var view := collider as CharacterView
		if ability_id == &"":
			return view
		var source: ActorState = battle_state.actors.get(character.actor_id)
		var target: ActorState = battle_state.actors.get(view.actor_id)
		var ability := DefinitionLibrary.get_default().get_ability(ability_id)
		if AbilityTargetingRules.is_valid_target(source, target, ability):
			return view
	return null


func _synchronize_completed_movement(actor_id: int) -> void:
	if not battle_state.actors.has(actor_id):
		return
	var view := event_player.get_character_view(actor_id)
	if view != null:
		view.synchronize_to_authoritative_position((battle_state.actors[actor_id] as ActorState).position)
	if actor_id == character.actor_id and not _pending_interactable_id.is_empty():
		_complete_pending_interaction()
	if actor_id == character.actor_id and not _pending_targeted_action.is_empty():
		_complete_pending_targeted_action()
	if actor_id == character.actor_id and _pending_victory_overlay:
		_pending_victory_overlay = false
		hud.present_outcome(&"victory")


func _approach_interactable(interactable_id: String) -> void:
	if not battle_state.interactables.has(interactable_id):
		return
	_cancel_pending_interaction()
	_pending_targeted_action.clear()
	var plan = session.plan_interaction(character.actor_id, interactable_id)
	if not plan.can_execute:
		_set_interactable_highlight(interactable_id, &"blocked")
		_resolve_interaction(interactable_id)
		return
	if not plan.requires_movement:
		_set_interactable_highlight(interactable_id, &"ready")
		_resolve_interaction(interactable_id)
		return
	_set_interactable_highlight(interactable_id, &"approaching")
	_pending_interactable_id = interactable_id
	_show_path_preview(plan.movement_target)
	var result := _move(plan.movement_target)
	if result.events.any(func(event: Event): return event.type == &"command_rejected"):
		_pending_interactable_id = ""
		_set_interactable_highlight(interactable_id, &"blocked")
	elif not character.is_moving() and not _pending_interactable_id.is_empty():
		# As with queued attacks, a presentation path can collapse even though
		# the authoritative move advanced. Do not leave the interaction waiting.
		_synchronize_completed_movement(character.actor_id)


func _complete_pending_interaction() -> void:
	var interactable_id := _pending_interactable_id
	_pending_interactable_id = ""
	_set_interactable_highlight(interactable_id, &"ready")
	_resolve_interaction(interactable_id)


func _complete_pending_targeted_action() -> void:
	var pending := _pending_targeted_action.duplicate()
	_pending_targeted_action.clear()
	var result: ResolutionResult = session.submit_ability(
		character.actor_id,
		pending.get("ability_id", &""),
		int(pending.get("target_id", -1)),
		pending.get("target_pos", Vector3.INF),
	)
	event_player.play_events(result.events)


func _resolve_interaction(interactable_id: String) -> void:
	var result: ResolutionResult = session.submit_interact(character.actor_id, interactable_id)
	event_player.play_events(result.events)
	if result.events.any(func(event: Event): return event.type == &"command_rejected"):
		_set_interactable_highlight(interactable_id, &"blocked")
	for resolved_event in result.events:
		if resolved_event.type != &"items_looted":
			continue
		# Only pickups are consumed by looting; an emptied chest or barrel stays
		# in the world with its state flipped to "open".
		var looted_id := str(resolved_event.data["interactable_id"])
		var looted := battle_state.interactables.get(looted_id) as InteractableState
		if looted == null:
			continue
		if looted.type == &"pickup":
			var pickup_view := compilation.root.get_node_or_null(NodePath(looted_id))
			if pickup_view != null:
				_set_interactable_view_active(pickup_view, false)
		var collected_highlight := _interactable_highlights.get(looted_id) as MeshInstance3D
		if collected_highlight != null and looted.contents.is_empty():
			collected_highlight.visible = false
		if _highlighted_interactable_id == looted_id:
			_highlighted_interactable_id = ""


func _sync_interactable_views() -> void:
	for interactable_id in battle_state.interactables:
		var interactable := battle_state.interactables[interactable_id] as InteractableState
		if interactable.type != &"pickup":
			continue
		var view := compilation.root.get_node_or_null(NodePath(interactable.id))
		if view != null:
			_set_interactable_view_active(view, interactable.state != &"collected")


func _remember_interaction_layers(root: Node) -> void:
	var collision_objects: Array[Node] = []
	if root is CollisionObject3D:
		collision_objects.append(root)
	for child in root.find_children("*", "CollisionObject3D", true, false):
		collision_objects.append(child)
	for collision_object_node in collision_objects:
		var collision_object := collision_object_node as CollisionObject3D
		if not collision_object.has_meta("active_collision_layer"):
			collision_object.set_meta("active_collision_layer", collision_object.collision_layer)


func _set_interactable_view_active(root: Node, active: bool) -> void:
	if root is Node3D:
		(root as Node3D).visible = active
	var collision_objects: Array[Node] = []
	if root is CollisionObject3D:
		collision_objects.append(root)
	for child in root.find_children("*", "CollisionObject3D", true, false):
		collision_objects.append(child)
	for collision_object_node in collision_objects:
		var collision_object := collision_object_node as CollisionObject3D
		var active_layer := int(collision_object.get_meta("active_collision_layer", collision_object.collision_layer))
		collision_object.collision_layer = active_layer if active else 0


func _dress_player(player: CharacterView, player_data: Dictionary) -> void:
	var asset_id := StringName(player_data.get("character_asset", ""))
	if asset_id == &"":
		return
	var definition := AssetCatalog.get_definition(asset_id)
	if definition == null or definition.asset_type != &"character":
		push_error("Player character_asset '%s' is not a usable character asset" % asset_id)
		return
	AssetCatalog.dress(player, asset_id)


func _setup_camera() -> void:
	# Generated maps compose the same tested isometric rig used by test_arena;
	# map compilation supplies only the focus bounds, never a second camera UI.
	var spec := _load_spec()
	var spawns: Array = spec.get("spawn_points", [])
	var focus := character.position
	if spawns.is_empty():
		var center := compilation.terrain.bounds * 0.5
		focus = Vector3(center.x, compilation.terrain.height_at(center.x, center.y), center.y)
	camera_rig = TACTICAL_CAMERA_SCENE.instantiate() as TacticalCameraRig
	camera_rig.position = focus
	camera_rig.target_focus = focus
	# Keep the generated-map view centered on the interpolated player view, so
	# camera motion stays in sync with the visible character rather than the
	# simulation's instantaneous position.
	camera_rig.follow_target = character
	camera_rig.follow_offset = Vector3.ZERO
	if spawns.is_empty():
		camera_rig.target_zoom = camera_rig.maximum_zoom
	camera_rig.pan_limit = maxf(compilation.terrain.bounds.x, compilation.terrain.bounds.y)
	camera = camera_rig.get_node("Pivot/Camera3D") as Camera3D
	add_child(camera_rig)


func _setup_light() -> void:
	add_child(TACTICAL_SUN_SCENE.instantiate())


func _setup_path_preview() -> void:
	_path_line = MeshInstance3D.new()
	_path_line.name = "PathPreview"
	_path_line.mesh = _line_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("f5d742")
	material.emission_enabled = true
	material.emission = Color("f5d742")
	_path_line.material_override = material
	add_child(_path_line)


func _setup_destination_marker() -> void:
	_destination_marker = DestinationClickMarkerScript.new() as DestinationClickMarker
	_destination_marker.name = "DestinationClickMarker"
	add_child(_destination_marker)


func _setup_hud() -> void:
	hud = preload("res://scenes/ui/hud_root.tscn").instantiate() as HudRoot
	add_child(hud)
	hud.bind(session, character.actor_id)
	hud.ability_requested.connect(_on_hud_ability_requested)
	hud.inventory_item_requested.connect(_on_inventory_item_requested)
	hud.end_turn_requested.connect(_on_hud_end_turn_requested)
	hud.cancel_requested.connect(_on_hud_cancel_requested)
	hud.retry_requested.connect(_on_retry_requested)
	hud.restart_requested.connect(_on_restart_requested)
	hud.quicksave_requested.connect(_on_hud_quicksave_requested)
	hud.quickload_requested.connect(_on_hud_quickload_requested)
	hud.world_pause_changed.connect(func(paused: bool):
		if camera_rig != null: camera_rig.input_enabled = not paused
	)


func _setup_music(settings: Dictionary) -> void:
	music = get_node_or_null("MusicDirector")
	if music == null:
		music = MusicDirectorScript.new()
		music.name = "MusicDirector"
		var player := AudioStreamPlayer.new()
		player.name = "AudioStreamPlayer"
		music.add_child(player)
		add_child(music)
	music.configure(settings)


func _on_hud_ability_requested(ability_id: StringName) -> void:
	if _presentation_busy(character):
		return
	_cancel_pending_interaction()
	_pending_targeted_action.clear()
	_clear_interactable_highlight()
	var definitions := DefinitionLibrary.get_default()
	var ability := definitions.get_ability(ability_id)
	if ability != null and ability.targeting == &"actor" and AbilityTargetingRules.target_range(definitions, ability_id) >= 0.0:
		_clear_targeting()
		_targeting_ability_id = ability_id
		hud.set_selected_ability(ability_id)
		_clear_path_preview()
		return
	_clear_targeting()
	var result: ResolutionResult = session.submit_ability(character.actor_id, ability_id, -1, Vector3.INF)
	event_player.play_events(result.events)


func _on_inventory_item_requested(item_id: StringName) -> void:
	if _presentation_busy(character):
		return
	_cancel_pending_interaction()
	_pending_targeted_action.clear()
	_clear_interactable_highlight()
	var item := DefinitionLibrary.get_default().get_item(item_id)
	if item == null or item.use_ability_id == &"":
		return
	var result: ResolutionResult = session.submit_ability(character.actor_id, item.use_ability_id, -1, Vector3.INF)
	event_player.play_events(result.events)


func _on_hud_end_turn_requested() -> void:
	if _presentation_busy(character):
		return
	_cancel_pending_interaction()
	_clear_interactable_highlight()
	_pending_targeted_action.clear()
	_clear_targeting()
	var result: ResolutionResult = session.end_turn(character.actor_id)
	event_player.play_events(result.events)


func _on_hud_cancel_requested() -> void:
	_cancel_pending_interaction()
	_clear_interactable_highlight()
	_pending_targeted_action.clear()
	_clear_targeting()
	_clear_path_preview()


func _on_retry_requested() -> void:
	if _encounter_checkpoint == null or _encounter_start_command == null:
		return
	battle_state = _encounter_checkpoint.clone()
	session.replace_state(battle_state)
	event_player.reset_views(battle_state)
	hud.reset_outcome()
	_pending_victory_overlay = false
	_cancel_pending_interaction()
	_pending_targeted_action.clear()
	_clear_targeting()
	_clear_interactable_highlight()
	_clear_path_preview()
	_sync_interactable_views()
	_update_world_health_bars()
	_start_encounter(Command.from_dict(_encounter_start_command.to_dict()), false)


func _on_outcome_events_resolved(events: Array[Event]) -> void:
	if not events.any(func(event: Event): return event.type in [&"game_over", &"game_completed"]):
		return
	_cancel_pending_interaction()
	_pending_targeted_action.clear()
	_clear_targeting()
	_clear_interactable_highlight()
	_clear_path_preview()
	if _destination_marker != null:
		_destination_marker.hide_marker()


func _on_restart_requested() -> void:
	get_tree().reload_current_scene()


func _on_hud_quicksave_requested() -> void:
	_save_game(QUICKSAVE_SLOT, "Quicksaved.")


func _on_hud_quickload_requested() -> void:
	_load_game(QUICKSAVE_SLOT)


func _save_game(slot: String, success_message: String) -> void:
	if battle_state == null:
		return
	var error := SaveLoadService.save(slot, SaveGame.create(battle_state.clone(), map_spec_path))
	if hud == null:
		return
	hud.combat_log.append_line(success_message if error == OK else "Save failed (error %d)." % error)


func _load_game(slot: String) -> void:
	var save := SaveLoadService.load_save(slot)
	if hud == null:
		return
	if save == null:
		hud.combat_log.append_line("No compatible %s save found." % slot)
		return
	if save.map_id != map_spec_path:
		hud.combat_log.append_line("That save belongs to another map.")
		return
	battle_state = save.battle_state
	session.replace_state(battle_state)
	event_player.reset_views(battle_state)
	hud.reset_outcome()
	_pending_victory_overlay = false
	_cancel_pending_interaction()
	_pending_targeted_action.clear()
	_clear_targeting()
	_clear_interactable_highlight()
	_clear_path_preview()
	_sync_interactable_views()
	_update_world_health_bars()
	hud.combat_log.append_line("Quickload complete.")


## `ability_id` defaults to whatever the hotbar has selected. Hovering a
## talkable NPC passes `talk` instead, so the ring reports talk range rather
## than the range of an attack the player has not chosen.
func _update_target_highlight(hostile: CharacterView, ability_id: StringName = &"") -> void:
	var range_ability := ability_id if ability_id != &"" else _targeting_ability_id
	var next_target_id := hostile.actor_id if hostile != null else -1
	if _highlighted_target_id == next_target_id:
		return
	if hostile_views.has(_highlighted_target_id):
		hostile_views[_highlighted_target_id].set_target_highlight(false)
	_highlighted_target_id = next_target_id
	if hostile != null:
		var source: ActorState = battle_state.actors.get(character.actor_id)
		var target: ActorState = battle_state.actors.get(hostile.actor_id)
		hostile.set_target_highlight(true, AbilityTargetingRules.is_target_in_range(source, target, DefinitionLibrary.get_default(), range_ability))


## Composition root for conversations. The catalog is map content, the session
## is a pure graph walker, and this controller is the only thing that turns a
## chosen option into an authoritative command.
func _setup_dialogs(spec: Dictionary) -> void:
	_dialog_catalog = DialogCatalogScript.new()
	_dialog_catalog.configure(spec)
	_dialog_session = DialogSessionScript.new()
	_dialog_session.configure(_dialog_catalog)
	_dialog_session.presented.connect(_on_dialog_presented)
	_dialog_session.check_requested.connect(_on_dialog_check_requested)
	_dialog_session.payment_requested.connect(_on_dialog_payment_requested)
	_dialog_session.finished.connect(_on_dialog_finished)
	hud.dialog_panel.option_chosen.connect(_on_dialog_option_chosen)
	hud.dialog_panel.dismissed.connect(_on_dialog_dismissed)
	session.events_resolved.connect(_on_dialog_events_resolved)


func _dialog_id_for_actor(actor_id: int) -> StringName:
	var actor := battle_state.actors.get(actor_id) as ActorState
	if actor == null or not actor.is_conscious():
		return &""
	return actor.dialog_id


## The Resolver decides whether the conversation may open at all (range, line
## of sight, whether the target has anything to say); this only reacts to the
## event it emits.
func _on_dialog_events_resolved(events: Array[Event]) -> void:
	for event in events:
		if event.type != &"dialog_started":
			continue
		var speaker_id := int(event.data["target_id"])
		var speaker_name := str(HudViewModel.for_actor(battle_state, speaker_id, DefinitionLibrary.get_default()).get("name", ""))
		_dialog_session.begin(StringName(str(event.data["dialog_id"])), speaker_id, speaker_name)
		return


func _on_dialog_presented(view: Dictionary) -> void:
	_clear_targeting()
	_clear_path_preview()
	var presented := view.duplicate(true)
	var payer := battle_state.actors.get(character.actor_id) as ActorState
	presented["coin_balance"] = payer.coins if payer != null else 0
	hud.dialog_panel.present(presented)


func _on_dialog_option_chosen(option_index: int) -> void:
	_dialog_session.choose(option_index)


func _on_dialog_payment_requested(option_index: int, coin_cost: int) -> void:
	var command := Command.create(&"transfer_coins", character.actor_id)
	command.target_id = _dialog_session.speaker_actor_id()
	command.metadata = {"amount": coin_cost}
	var result: ResolutionResult = session.submit_command(command)
	var succeeded := result.events.any(func(event: Event): return event.type == &"coins_transferred")
	_dialog_session.resolve_payment(option_index, succeeded)


func _on_dialog_dismissed() -> void:
	_dialog_session.cancel()
	hud.dialog_panel.close()


## The roll itself belongs to the simulation, so the option is not resolved
## until skill_check comes back. The result is held on screen briefly before
## the conversation moves on.
func _on_dialog_check_requested(option_index: int, ability: StringName, skill: StringName, difficulty_class: int, proficient: bool) -> void:
	var command := Command.create(&"skill_check", character.actor_id)
	command.target_id = _dialog_session.speaker_actor_id()
	command.metadata = {"ability": ability, "skill": skill, "dc": difficulty_class, "proficient": proficient}
	var result: ResolutionResult = session.submit_command(command)
	var success := false
	for event in result.events:
		if event.type != &"skill_check_rolled":
			continue
		success = bool(event.data["success"])
		hud.dialog_panel.present_check(skill, int(event.data["difficulty_class"]), int(event.data["total"]), success)
		await get_tree().create_timer(CHECK_REVEAL_SECONDS).timeout
		break
	if _dialog_session.is_active():
		_dialog_session.resolve_check(option_index, success)


func _on_dialog_finished(effect: StringName) -> void:
	var speaker_id := _dialog_session.speaker_actor_id()
	hud.dialog_panel.close()
	match effect:
		DialogSessionScript.EFFECT_PACIFY_ENCOUNTER:
			_set_encounter_disposition(speaker_id, &"neutral")
		DialogSessionScript.EFFECT_START_COMBAT:
			_set_encounter_disposition(speaker_id, &"hostile")
			var encounter_id := _encounter_id_for_actor(speaker_id)
			var start := Command.create(&"start_combat", speaker_id)
			if not encounter_id.is_empty():
				start.metadata = {"encounter_id": encounter_id, "participant_actor_ids": (encounter_definitions[encounter_id].combatant_ids as Array).duplicate()}
			_start_encounter(start, true)


## Talking is with the camp, not one bandit: a stance the conversation settles
## applies to everyone the encounter would have pulled into the fight.
func _set_encounter_disposition(speaker_id: int, disposition: StringName) -> void:
	var encounter_id := _encounter_id_for_actor(speaker_id)
	var actor_ids: Array = [speaker_id] if encounter_id.is_empty() else encounter_definitions[encounter_id].combatant_ids
	for actor_id in actor_ids:
		if actor_id == character.actor_id or not battle_state.actors.has(actor_id):
			continue
		var command := Command.create(&"set_disposition", int(actor_id))
		command.metadata = {"disposition": disposition}
		var result: ResolutionResult = session.submit_command(command)
		event_player.play_events(result.events)
	if disposition == &"neutral" and not encounter_id.is_empty():
		var clear := Command.create(&"clear_encounter", speaker_id)
		clear.metadata = {"encounter_id": encounter_id}
		var clear_result: ResolutionResult = session.submit_command(clear)
		event_player.play_events(clear_result.events)


func _encounter_id_for_actor(actor_id: int) -> String:
	var encounter_ids: Array = encounter_definitions.keys()
	encounter_ids.sort()
	for encounter_id in encounter_ids:
		if (encounter_definitions[encounter_id].combatant_ids as Array).has(actor_id):
			return str(encounter_id)
	return ""


func _submit_targeted_ability(target_id: int) -> void:
	if _presentation_busy(character) or not battle_state.actors.has(character.actor_id) or not battle_state.actors.has(target_id):
		return
	_cancel_pending_interaction()
	_clear_interactable_highlight()
	var ability_id := _targeting_ability_id
	var definitions := DefinitionLibrary.get_default()
	var ability := definitions.get_ability(ability_id)
	var source: ActorState = battle_state.actors.get(character.actor_id)
	var target: ActorState = battle_state.actors.get(target_id)
	if not AbilityTargetingRules.is_valid_target(source, target, ability):
		_clear_targeting()
		return
	var plan = session.plan_targeted_ability(character.actor_id, ability_id, target_id)
	if not plan.can_execute or not plan.requires_movement:
		var immediate: ResolutionResult = session.submit_ability(character.actor_id, ability_id, target_id, Vector3.INF)
		event_player.play_events(immediate.events)
		_clear_targeting()
		return
	_pending_targeted_action = {
		"ability_id": ability_id,
		"target_id": target_id,
		"target_pos": Vector3.INF,
	}
	var movement := _move(plan.movement_target)
	if movement.events.any(func(event: Event): return event.type == &"command_rejected"):
		_pending_targeted_action.clear()
	elif not character.is_moving() and not _pending_targeted_action.is_empty():
		# A presentation path can collapse to the current view position even
		# though the authoritative move advanced. Complete the queued action
		# instead of leaving it waiting for a movement signal that will not fire.
		_synchronize_completed_movement(character.actor_id)
	_clear_targeting()


func _clear_targeting() -> void:
	if hostile_views.has(_highlighted_target_id):
		hostile_views[_highlighted_target_id].set_target_highlight(false)
	_highlighted_target_id = -1
	_targeting_ability_id = &""
	if hud != null:
		hud.set_selected_ability(&"")


func _update_interactable_highlight(interactable_id: String) -> void:
	if interactable_id.is_empty() or not battle_state.interactables.has(interactable_id):
		_clear_interactable_highlight()
		return
	var actor := battle_state.actors.get(character.actor_id) as ActorState
	var interactable := battle_state.interactables.get(interactable_id) as InteractableState
	var status := &"ready" if actor != null and interactable != null and actor.position.distance_to(interactable.position) <= interactable.interact_range else &"approaching"
	_set_interactable_highlight(interactable_id, status)


func _set_interactable_highlight(interactable_id: String, status: StringName) -> void:
	if _highlighted_interactable_id != interactable_id and _interactable_highlights.has(_highlighted_interactable_id):
		_interactable_highlights[_highlighted_interactable_id].visible = false
	_highlighted_interactable_id = interactable_id
	var highlight := _interactable_highlights.get(interactable_id) as MeshInstance3D
	if highlight == null or not is_instance_valid(highlight):
		return
	var color := INTERACTABLE_READY_COLOR
	if status == &"approaching":
		color = INTERACTABLE_APPROACH_COLOR
	elif status == &"blocked":
		color = INTERACTABLE_BLOCKED_COLOR
	var material := highlight.material_override as StandardMaterial3D
	material.albedo_color = Color(color.r, color.g, color.b, 0.58)
	material.emission = color
	highlight.visible = true
	_interactable_highlight_time = 0.0


func _clear_interactable_highlight() -> void:
	var highlight := _interactable_highlights.get(_highlighted_interactable_id) as MeshInstance3D
	if highlight != null and is_instance_valid(highlight):
		highlight.visible = false
		highlight.scale = Vector3.ONE
	_highlighted_interactable_id = ""


func _cancel_pending_interaction() -> void:
	_pending_interactable_id = ""


func _animate_interactable_highlight(delta: float) -> void:
	var highlight := _interactable_highlights.get(_highlighted_interactable_id) as MeshInstance3D
	if highlight == null or not is_instance_valid(highlight) or not highlight.visible:
		return
	_interactable_highlight_time += delta
	var pulse := 1.0 + sin(_interactable_highlight_time * 5.0) * 0.055
	highlight.scale = Vector3(pulse, 1.0, pulse)


func _show_compile_errors() -> void:
	_show_error("Map compilation failed:\n\n%s" % JSON.stringify(compilation.error_dicts(), "  "))


func _show_error(message: String) -> void:
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.position = Vector2(24, 24)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size = Vector2(900, 600)
	label.text = message
	layer.add_child(label)
	add_child(layer)


func _move(target: Vector3) -> ResolutionResult:
	var result: ResolutionResult = session.submit_move(1, target, character.global_position)
	_pending_victory_overlay = result.events.any(func(event: Event): return event.type == &"game_completed")
	event_player.play_events(result.events)
	if _pending_victory_overlay and not character.is_moving():
		_pending_victory_overlay = false
		hud.present_outcome(&"victory")
	return result


func _show_path_preview(target: Vector3) -> void:
	if character == null or _path_line == null:
		return
	if battle_state.phase != &"combat":
		_clear_path_preview()
		return
	var preview = session.preview_move(1, target, character.global_position)
	_preview_path = preview.path
	PathPreviewRendererScript.draw(_line_mesh, _preview_path, character.global_position)


func _show_exploration_destination(target: Vector3) -> void:
	if battle_state.phase == &"exploration" and _destination_marker != null:
		_destination_marker.show_at(target)


func _clear_path_preview() -> void:
	_preview_path = PackedVector3Array()
	_line_mesh.clear_surfaces()
