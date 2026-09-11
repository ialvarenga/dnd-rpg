class_name TestArenaController
extends Node3D

## World-side composition root for A3. Hover resolves a non-mutating preview;
## confirmed input creates Commands, applies accepted events immediately, and
## EventPlayer alone narrates movement on the CharacterView.

@onready var camera_rig: TacticalCameraRig = $PlayerCharacter/CameraRig
@onready var camera: Camera3D = camera_rig.camera
@onready var character: CharacterView = $PlayerCharacter
@onready var navigation_region: NavigationRegion3D = $NavigationRegion3D
@onready var event_player: EventPlayer = $EventPlayer
@onready var destination_marker: DestinationClickMarker = $Debug/DestinationMarker
@onready var path_mesh: MeshInstance3D = $Debug/PathLine
@onready var debug_label: Label = $DebugOverlay/Panel/Label
@onready var hud: HudRoot = $HudRoot
@onready var music: MusicDirector = $MusicDirector

var battle_state := BattleState.new()
var nav_provider: NavProvider
var los_provider: LosProvider
var session
var last_command: Command
var last_resolution: ResolutionResult
var last_preview: ResolutionResult
var last_input_status: StringName = &"idle"

var _preview

var _line_mesh := ImmediateMesh.new()

const EncounterSessionScript = preload("res://world/encounter_session.gd")
const ScreenPickerScript = preload("res://world/screen_picker.gd")
const PathPreviewRendererScript = preload("res://view/path_preview_renderer.gd")


func _ready() -> void:
	# This view-only attachment deliberately follows the interpolated character
	# view, never the BattleState. The rig can therefore remain a child of the
	# character without affecting simulation or screen picking.
	camera_rig.follow_target = character
	camera_rig.follow_offset = camera_rig.global_position - character.global_position
	path_mesh.mesh = _line_mesh
	_dress_arena_props()
	nav_provider = GodotNavProvider.new(navigation_region)
	los_provider = GodotLosProvider.new(get_world_3d(), 8)
	_initialize_exploration_state()
	session = EncounterSessionScript.new()
	session.configure(battle_state, nav_provider, los_provider)
	event_player.register_character_view(character)
	event_player.movement_completed.connect(_synchronize_completed_movement)
	hud.bind(session, character.actor_id)
	hud.ability_requested.connect(_on_hud_ability_requested)
	hud.inventory_item_requested.connect(_on_inventory_item_requested)
	hud.end_turn_requested.connect(_on_hud_end_turn_requested)
	hud.cancel_requested.connect(_on_hud_cancel_requested)
	hud.world_pause_changed.connect(func(paused: bool): camera_rig.input_enabled = not paused)


## The hand-authored arena consumes the same ID-only catalog as the future map
## compiler. Collision stays on these anchors; AssetCatalog swaps visuals only.
func _dress_arena_props() -> void:
	AssetCatalog.dress($TreeA, &"tree_oak_01")
	AssetCatalog.dress($TreeB, &"tree_oak_02")
	AssetCatalog.dress($NorthWall, &"wall_run_dungeon_01")
	AssetCatalog.dress($CentralObstacle, &"rock_large_01")
	AssetCatalog.dress($Chest, &"chest_wood_01")
	AssetCatalog.dress(character, &"character_knight_01")


func _process(_delta: float) -> void:
	if music != null:
		music.set_phase(battle_state.phase)
	if battle_state.phase != &"exploration":
		destination_marker.hide_marker()
	_update_debug_view()


func _unhandled_input(event: InputEvent) -> void:
	if camera == null or not is_instance_valid(camera):
		return
	if hud != null and hud.is_world_paused():
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		var preview_target: Variant = ScreenPickerScript.terrain_point(camera, get_world_3d().direct_space_state, event.position)
		if preview_target is Vector3:
			preview_move_target(preview_target)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var interactable_id := ScreenPickerScript.interactable_id(camera, get_world_3d().direct_space_state, event.position)
		if interactable_id != "":
			submit_interact(interactable_id)
		else:
			handle_terrain_click(ScreenPickerScript.terrain_point(camera, get_world_3d().direct_space_state, event.position))
		get_viewport().set_input_as_handled()


## Kept public so headless scene tests can exercise the same input boundary as
## a terrain click without requiring a visible window.
func handle_terrain_click(destination: Variant) -> void:
	if destination == null:
		last_input_status = &"outside_terrain"
		return
	if not (destination is Vector3) or not _is_finite_vector(destination):
		last_input_status = &"invalid_target"
		return
	# The click confirms a fresh authoritative resolution; it never applies the
	# hover result, which remains presentation-only.
	if battle_state.phase == &"exploration":
		destination_marker.show_at(destination)
	preview_move_target(destination)
	submit_move_target(destination)


## Public for runtime tests and future UI. It intentionally calls only the pure
## resolver and updates local debug state; BattleState and CharacterView remain
## untouched until submit_move_target confirms a command.
func preview_move_target(target: Vector3) -> ResolutionResult:
	_preview = session.preview_move(character.actor_id, target, character.global_position)
	last_preview = _preview.resolution
	if _preview.accepted:
		last_input_status = &"preview"
	elif _preview.rejection_reason != &"":
		last_input_status = _preview.rejection_reason
	return last_preview


func submit_move_target(target: Vector3) -> ResolutionResult:
	last_command = Command.create(&"move", character.actor_id)
	last_command.target_pos = target
	last_resolution = session.submit_move(character.actor_id, target, character.global_position)
	var accepted_movement := false
	for event in last_resolution.events:
		if event.type == &"movement_segment":
			accepted_movement = true
		elif event.type == &"command_rejected":
			last_input_status = event.data["reason"]
	if accepted_movement:
		last_input_status = &"accepted"
		_clear_preview()
	event_player.play_events(last_resolution.events)
	return last_resolution


## Public for runtime tests and future UI, mirroring submit_move_target: it
## resolves through the same Command/Resolver/apply pipeline as movement, so
## the chest is never opened by mutating InteractableState directly.
func submit_interact(interactable_id: String) -> ResolutionResult:
	last_command = Command.create(&"interact", character.actor_id)
	last_command.target_interactable_id = interactable_id
	last_resolution = session.submit_interact(character.actor_id, interactable_id)
	for event in last_resolution.events:
		if event.type == &"command_rejected":
			last_input_status = event.data["reason"]
		elif event.type == &"interaction_completed":
			last_input_status = &"interacted"
	event_player.play_events(last_resolution.events)
	return last_resolution


func _on_hud_ability_requested(ability_id: StringName) -> void:
	# Target selection remains a controller concern; untargeted abilities work
	# immediately, while Resolver rejects an attack without a valid target.
	last_resolution = session.submit_ability(character.actor_id, ability_id, -1, Vector3.INF)
	event_player.play_events(last_resolution.events)


func _on_inventory_item_requested(item_id: StringName) -> void:
	var item := DefinitionLibrary.get_default().get_item(item_id)
	if item != null and item.use_ability_id != &"":
		last_resolution = session.submit_ability(character.actor_id, item.use_ability_id, -1, Vector3.INF)
		event_player.play_events(last_resolution.events)


func _on_hud_end_turn_requested() -> void:
	last_resolution = session.end_turn(character.actor_id)
	event_player.play_events(last_resolution.events)


func _on_hud_cancel_requested() -> void:
	# Cancel changes only a presentation overlay; it never creates a command or
	# changes BattleState outside EncounterSession.
	$DebugOverlay.visible = not $DebugOverlay.visible


func _initialize_exploration_state() -> void:
	battle_state.phase = &"exploration"
	battle_state.rng_seed = 1
	battle_state.rng_state = 1
	var knight := DefinitionLibrary.get_default().get_actor(&"knight")
	var player := ActorState.from_definition(knight, character.actor_id, &"heroes", character.global_position)
	battle_state.actors[player.id] = player
	character.configure_weapon_presentation(Equipment.weapon(player, DefinitionLibrary.get_default()))

	var chest := InteractableState.new()
	chest.id = "chest_a"
	chest.type = &"chest"
	chest.state = &"closed"
	# Ground/navmesh height, matching where a nav-driven ActorState.position
	# actually lands after movement (~0.1) rather than the Chest node's own
	# ground-pivoted transform.y (0.265) or the player's un-moved spawn height
	# (1.0) -- interact_range below absorbs the difference either way.
	chest.position = Vector3(10, 0.1, -10)
	chest.interact_range = 2.5
	chest.contents.append(&"healing_potion")
	battle_state.interactables[chest.id] = chest


func _synchronize_completed_movement(actor_id: int) -> void:
	if not battle_state.actors.has(actor_id):
		return
	var view := event_player.get_character_view(actor_id)
	if view == null:
		return
	# BattleState changes on acceptance for deterministic command handling while
	# the view interpolates the event path. Completion snaps only tiny collision
	# or tolerance drift back to that already-authoritative position.
	view.synchronize_to_authoritative_position((battle_state.actors[actor_id] as ActorState).position)


func _update_debug_view() -> void:
	var path: PackedVector3Array = _preview.path if _preview != null else PackedVector3Array()
	if path.is_empty():
		path = event_player.get_resolved_path(character.actor_id)
	if battle_state.phase == &"combat":
		PathPreviewRendererScript.draw(_line_mesh, path, character.global_position)
	else:
		_line_mesh.clear_surfaces()
	var preview_text := "Preview: --"
	if _preview != null and not _preview.path.is_empty():
		if _preview.ignores_budget:
			preview_text = "Preview: %.2fm (exploration: budget ignored)" % _preview.cost
		else:
			preview_text = "Preview: %.2fm consumed, %.2fm remaining" % [_preview.cost, _preview.remaining]
	debug_label.text = "Command: %s\nDestination: %s (%s)\nVelocity: %s\n%s" % [
		last_input_status,
		_format_vector(character.destination),
		character.destination_state,
		_format_vector(character.get_debug_velocity()),
		preview_text,
	]


func _clear_preview() -> void:
	_preview = null


func _format_vector(value: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [value.x, value.y, value.z]


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
