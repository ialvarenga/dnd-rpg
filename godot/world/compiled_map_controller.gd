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

const PLAYER_CHARACTER_SCENE = preload("res://scenes/actors/player_character.tscn")
const TACTICAL_CAMERA_SCENE = preload("res://scenes/camera/tactical_camera_rig.tscn")
const OBJECTIVE_MARKER_SCENE = preload("res://scenes/world/objective_marker.tscn")
const TACTICAL_SUN_SCENE = preload("res://scenes/world/tactical_sun.tscn")
const EncounterSessionScript = preload("res://world/encounter_session.gd")
const MapSpecSourceScript = preload("res://world/map_spec_source.gd")
const ScreenPickerScript = preload("res://world/screen_picker.gd")


func _ready() -> void:
	map_source = MapSpecSourceScript.new(map_spec_path)
	compilation = MapCompiler.new().compile(_load_spec())
	if not compilation.is_valid():
		push_error("Map compilation failed: %s" % compilation.error_dicts())
		_show_compile_errors()
		return
	add_child(compilation.root)
	_setup_player()
	_setup_camera()
	_setup_light()
	_setup_path_preview()
	nav_provider = GodotNavProvider.new(compilation.navigation.navigation_region)
	los_provider = GodotLosProvider.new(get_world_3d(), 8)
	session = EncounterSessionScript.new()
	session.configure(battle_state, nav_provider, los_provider)
	NavigationServer3D.map_force_update(compilation.navigation.navigation_region.get_navigation_map())


func _unhandled_input(event: InputEvent) -> void:
	if camera == null or nav_provider == null:
		return
	if event is InputEventMouseMotion:
		var preview_target: Variant = ScreenPickerScript.terrain_point(camera, get_world_3d().direct_space_state, event.position)
		if preview_target is Vector3:
			_show_path_preview(preview_target)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var target: Variant = ScreenPickerScript.terrain_point(camera, get_world_3d().direct_space_state, event.position)
		if target is Vector3:
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
	battle_state.phase = &"exploration"
	var actor := ActorState.new()
	actor.id = 1
	actor.side = &"heroes"
	actor.hp = 20
	actor.max_hp = 20
	actor.position = character.global_position
	battle_state.actors[1] = actor
	if not spec.get("objectives", []).is_empty():
		var raw: Array = spec.objectives[0].position
		objective = Vector3(float(raw[0]), compilation.terrain.height_at(float(raw[0]), float(raw[1])) + 0.2, float(raw[1]))
		var marker := OBJECTIVE_MARKER_SCENE.instantiate() as MeshInstance3D
		marker.position = objective
		add_child(marker)


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


func _show_compile_errors() -> void:
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.position = Vector2(24, 24)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size = Vector2(900, 600)
	label.text = "Map compilation failed:\n\n%s" % JSON.stringify(compilation.error_dicts(), "  ")
	layer.add_child(label)
	add_child(layer)


func _move(target: Vector3) -> void:
	var result: ResolutionResult = session.submit_move(1, target, character.global_position)
	event_player.play_events(result.events)


func _show_path_preview(target: Vector3) -> void:
	if character == null or _path_line == null:
		return
	var preview = session.preview_move(1, target)
	var path: PackedVector3Array = preview.path
	_line_mesh.clear_surfaces()
	if path.size() < 2:
		return
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in path:
		_line_mesh.surface_add_vertex(point + Vector3.UP * 0.12)
	_line_mesh.surface_end()
