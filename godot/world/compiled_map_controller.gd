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
var hud: HudRoot
var hostile_views: Dictionary[int, CharacterView] = {}
var detection_range := 8.0
var _enemy_action_cooldown := 0.0
var _targeting_ability_id: StringName = &""
var _highlighted_target_id := -1
var _pending_interactable_id := ""
var music

const EnemyAIScript = preload("res://ai/enemy_ai.gd")
const AbilityTargetingRules = preload("res://sim/ability_targeting.gd")

const PLAYER_CHARACTER_SCENE = preload("res://scenes/actors/player_character.tscn")
const TACTICAL_CAMERA_SCENE = preload("res://scenes/camera/tactical_camera_rig.tscn")
const OBJECTIVE_MARKER_SCENE = preload("res://scenes/world/objective_marker.tscn")
const TACTICAL_SUN_SCENE = preload("res://scenes/world/tactical_sun.tscn")
const EncounterSessionScript = preload("res://world/encounter_session.gd")
const MapSpecSourceScript = preload("res://world/map_spec_source.gd")
const ScreenPickerScript = preload("res://world/screen_picker.gd")
const MusicDirectorScript = preload("res://view/music_director.gd")
const WORLD_HEALTH_BAR_SCENE = preload("res://view/ui/world_health_bar.tscn")


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
	_setup_pickups(spec)
	_setup_hostiles(spec)
	_setup_camera()
	_setup_light()
	_setup_path_preview()
	nav_provider = GodotNavProvider.new(compilation.navigation.navigation_region)
	los_provider = GodotLosProvider.new(get_world_3d(), 8)
	session = EncounterSessionScript.new()
	session.configure(battle_state, nav_provider, los_provider)
	session.state_changed.connect(_update_world_health_bars)
	_update_world_health_bars()
	_setup_music(compilation.music)
	_setup_hud()
	NavigationServer3D.map_force_update(compilation.navigation.navigation_region.get_navigation_map())


func _unhandled_input(event: InputEvent) -> void:
	if camera == null or nav_provider == null:
		return
	if event is InputEventMouseMotion:
		if _targeting_ability_id != &"":
			_update_target_highlight(_hostile_at_screen_position(event.position))
			return
		var preview_target: Variant = ScreenPickerScript.terrain_point(camera, get_world_3d().direct_space_state, event.position)
		if preview_target is Vector3:
			_show_path_preview(preview_target)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var interactable_id := ScreenPickerScript.interactable_id(camera, get_world_3d().direct_space_state, event.position)
		if interactable_id != "":
			_approach_interactable(interactable_id)
			get_viewport().set_input_as_handled()
			return
		var hostile := _hostile_at_screen_position(event.position)
		if _targeting_ability_id != &"":
			if hostile != null:
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
	character.held_weapon_model_path = Equipment.held_weapon_model_path(actor, DefinitionLibrary.get_default())
	_attach_world_health_bar(character)
	if not spec.get("objectives", []).is_empty():
		var raw: Array = spec.objectives[0].position
		objective = Vector3(float(raw[0]), compilation.terrain.height_at(float(raw[0]), float(raw[1])) + 0.2, float(raw[1]))
		var marker := OBJECTIVE_MARKER_SCENE.instantiate() as MeshInstance3D
		marker.position = objective
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
		add_child(hostile)
		AssetCatalog.dress(hostile, asset_id)
		var compiled_visual := compilation.root.get_node_or_null(String(raw_actor.get("id", ""))) as Node3D
		if compiled_visual != null:
			compiled_visual.visible = false
		event_player.register_character_view(hostile)
		hostile.movement_completed.connect(_synchronize_completed_movement)
		hostile_views[actor_id] = hostile
		var raider := DefinitionLibrary.get_default().get_actor(&"raider")
		var raider_actor := ActorState.from_definition(raider, actor_id, &"enemies", hostile.global_position)
		battle_state.actors[actor_id] = raider_actor
		hostile.held_weapon_model_path = Equipment.held_weapon_model_path(raider_actor, DefinitionLibrary.get_default())
		_attach_world_health_bar(hostile)
		actor_id += 1


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
	if music != null:
		music.set_phase(battle_state.phase)
	if battle_state.phase == &"exploration":
		_check_hostile_detection()
		return
	if _end_combat_if_resolved():
		return
	_enemy_action_cooldown = maxf(0.0, _enemy_action_cooldown - delta)
	if _enemy_action_cooldown <= 0.0:
		_take_enemy_turn()


func _check_hostile_detection() -> void:
	for actor_id in hostile_views:
		var hostile := hostile_views[actor_id]
		if not is_instance_valid(hostile) or not battle_state.actors.has(actor_id):
			continue
		var hostile_state: ActorState = battle_state.actors[actor_id]
		if not hostile_state.is_alive():
			continue
		if character.global_position.distance_to(hostile.global_position) <= detection_range and los_provider.has_line_of_sight(hostile.global_position, character.global_position):
			var start := Command.create(&"start_combat", actor_id)
			var result: ResolutionResult = session.submit_command(start)
			event_player.play_events(result.events)
			_enemy_action_cooldown = 0.4
			return


func _take_enemy_turn() -> void:
	var actor_id := battle_state.current_actor_id()
	if not hostile_views.has(actor_id):
		return
	var command: Command = EnemyAIScript.new().choose_command(battle_state, actor_id, nav_provider, los_provider)
	if command == null:
		return
	var result: ResolutionResult = session.submit_command(command)
	event_player.play_events(result.events)
	_enemy_action_cooldown = 0.45


func _end_combat_if_resolved() -> bool:
	var heroes_alive := false
	var enemies_alive := false
	for actor_id in battle_state.actors:
		var actor: ActorState = battle_state.actors[actor_id]
		if actor.side == &"heroes":
			heroes_alive = heroes_alive or actor.is_alive()
		elif actor.side == &"enemies":
			enemies_alive = enemies_alive or actor.is_alive()
	if heroes_alive and enemies_alive:
		return false
	var current_actor_id := battle_state.current_actor_id()
	if current_actor_id == -1:
		return false
	var result: ResolutionResult = session.submit_command(Command.create(&"end_combat", current_actor_id))
	event_player.play_events(result.events)
	return true


func _hostile_at_screen_position(screen_position: Vector2) -> CharacterView:
	var query := PhysicsRayQueryParameters3D.create(camera.project_ray_origin(screen_position), camera.project_ray_origin(screen_position) + camera.project_ray_normal(screen_position) * 250.0, 2)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var collider := hit.get("collider") as Node
	if collider is CharacterView and (collider as CharacterView).actor_id != 1:
		return collider as CharacterView
	return null


func _synchronize_completed_movement(actor_id: int) -> void:
	if not battle_state.actors.has(actor_id):
		return
	var view := event_player.get_character_view(actor_id)
	if view != null:
		view.synchronize_to_authoritative_position((battle_state.actors[actor_id] as ActorState).position)
	if actor_id == character.actor_id and not _pending_interactable_id.is_empty():
		_complete_pending_interaction()


func _approach_interactable(interactable_id: String) -> void:
	if not battle_state.interactables.has(interactable_id):
		return
	var interactable: InteractableState = battle_state.interactables[interactable_id]
	var actor: ActorState = battle_state.actors[character.actor_id]
	if actor.position.distance_to(interactable.position) <= interactable.interact_range:
		_resolve_interaction(interactable_id)
		return
	_pending_interactable_id = interactable_id
	var result := _move(interactable.position)
	if not result.events.is_empty() and result.events[0].type == &"command_rejected":
		_pending_interactable_id = ""


func _complete_pending_interaction() -> void:
	var interactable_id := _pending_interactable_id
	_pending_interactable_id = ""
	_resolve_interaction(interactable_id)


func _resolve_interaction(interactable_id: String) -> void:
	var result: ResolutionResult = session.submit_interact(character.actor_id, interactable_id)
	event_player.play_events(result.events)
	for resolved_event in result.events:
		if resolved_event.type == &"items_looted":
			var pickup_view := compilation.root.get_node_or_null(NodePath(str(resolved_event.data["interactable_id"])))
			if pickup_view != null:
				pickup_view.queue_free()


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


func _setup_hud() -> void:
	hud = preload("res://scenes/ui/hud_root.tscn").instantiate() as HudRoot
	add_child(hud)
	hud.bind(session, character.actor_id)
	hud.ability_requested.connect(_on_hud_ability_requested)
	hud.inventory_item_requested.connect(_on_inventory_item_requested)
	hud.end_turn_requested.connect(_on_hud_end_turn_requested)
	hud.cancel_requested.connect(_on_hud_cancel_requested)


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
	var definitions := DefinitionLibrary.get_default()
	var ability := definitions.get_ability(ability_id)
	if ability != null and ability.targeting == &"actor" and AbilityTargetingRules.attack_range(definitions, ability_id) >= 0.0:
		_clear_targeting()
		_targeting_ability_id = ability_id
		hud.set_selected_ability(ability_id)
		_line_mesh.clear_surfaces()
		return
	_clear_targeting()
	var result: ResolutionResult = session.submit_ability(character.actor_id, ability_id, -1, Vector3.INF)
	event_player.play_events(result.events)


func _on_inventory_item_requested(item_id: StringName) -> void:
	var item := DefinitionLibrary.get_default().get_item(item_id)
	if item == null or item.use_ability_id == &"":
		return
	var result: ResolutionResult = session.submit_ability(character.actor_id, item.use_ability_id, -1, Vector3.INF)
	event_player.play_events(result.events)


func _on_hud_end_turn_requested() -> void:
	_clear_targeting()
	var result: ResolutionResult = session.end_turn(character.actor_id)
	event_player.play_events(result.events)


func _on_hud_cancel_requested() -> void:
	_clear_targeting()
	_line_mesh.clear_surfaces()


func _update_target_highlight(hostile: CharacterView) -> void:
	var next_target_id := hostile.actor_id if hostile != null else -1
	if _highlighted_target_id == next_target_id:
		return
	if hostile_views.has(_highlighted_target_id):
		hostile_views[_highlighted_target_id].set_target_highlight(false)
	_highlighted_target_id = next_target_id
	if hostile != null:
		var source: ActorState = battle_state.actors.get(character.actor_id)
		var target: ActorState = battle_state.actors.get(hostile.actor_id)
		hostile.set_target_highlight(true, AbilityTargetingRules.is_target_in_attack_range(source, target, DefinitionLibrary.get_default(), _targeting_ability_id))


func _submit_targeted_ability(target_id: int) -> void:
	if not battle_state.actors.has(character.actor_id) or not battle_state.actors.has(target_id):
		return
	var source: ActorState = battle_state.actors[character.actor_id]
	var target: ActorState = battle_state.actors[target_id]
	if not AbilityTargetingRules.is_target_in_attack_range(source, target, DefinitionLibrary.get_default(), _targeting_ability_id):
		return
	var result: ResolutionResult = session.submit_ability(character.actor_id, _targeting_ability_id, target_id, Vector3.INF)
	event_player.play_events(result.events)
	_clear_targeting()


func _clear_targeting() -> void:
	if hostile_views.has(_highlighted_target_id):
		hostile_views[_highlighted_target_id].set_target_highlight(false)
	_highlighted_target_id = -1
	_targeting_ability_id = &""
	if hud != null:
		hud.set_selected_ability(&"")


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
	event_player.play_events(result.events)
	return result


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
