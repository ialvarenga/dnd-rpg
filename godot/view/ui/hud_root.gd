class_name HudRoot
extends CanvasLayer

## Presentation adapter. It listens to the shared session but never submits a
## command itself; the owning world controller decides targets and calls it.
signal ability_requested(ability_id: StringName)
signal end_turn_requested
signal cancel_requested

## DefinitionLibrary is a RefCounted catalog, not an inspector Resource.
## Controllers may inject it at runtime; otherwise _ready() uses the default.
var definitions: DefinitionLibrary
var session: EncounterSession
var actor_id := -1

@onready var portrait: ActorPortrait = $Margin/Layout/ActorPortrait
@onready var resources: ResourcePips = $Margin/Layout/ResourcePips
@onready var hotbar: AbilityHotbar = $Margin/Layout/HotbarPanel/PanelMargin/Rows/Groups/AbilityHotbar
@onready var turns: TurnOrderBar = $Margin/TopBar/TurnOrder
@onready var conditions: ConditionStrip = $Margin/TopBar/Conditions
@onready var combat_log: CombatLog = $CombatLog
@onready var tooltip_layer: TooltipLayer = $TooltipLayer

func _ready() -> void:
	definitions = definitions if definitions != null else DefinitionLibrary.get_default()
	hotbar.ability_requested.connect(func(id): ability_requested.emit(id))
	$Margin/Layout/EndTurn.icon = hotbar.icon_set.texture_for(&"end_turn") if hotbar.icon_set != null else null
	$Margin/Layout/EndTurn.pressed.connect(func(): end_turn_requested.emit())

func bind(next_session: EncounterSession, next_actor_id: int) -> void:
	if session != null:
		if session.state_changed.is_connected(sync): session.state_changed.disconnect(sync)
		if session.events_resolved.is_connected(_on_events_resolved): session.events_resolved.disconnect(_on_events_resolved)
	session = next_session
	actor_id = next_actor_id
	if session != null:
		session.state_changed.connect(sync)
		session.events_resolved.connect(_on_events_resolved)
	sync()

func sync() -> void:
	if session == null or session.battle_state == null: return
	var data := HudViewModel.for_actor(session.battle_state, actor_id, definitions, session.available_actions(actor_id))
	if data.is_empty(): return
	portrait.set_actor(data)
	resources.set_resources(data)
	hotbar.set_actions(data.action_availability)
	turns.set_turn_order(HudViewModel.turn_order(session.battle_state, definitions))
	conditions.set_conditions(data.conditions)


## Events are applied before EncounterSession emits this signal, so narration
## remains a projection of authoritative state rather than a second rule path.
func _on_events_resolved(events: Array[Event]) -> void:
	if session == null or session.battle_state == null:
		return
	for event in events:
		combat_log.append_line(HudViewModel.narrate(event, session.battle_state, definitions))


func set_selected_ability(ability_id: StringName) -> void:
	hotbar.set_selected_ability(ability_id)

func _unhandled_input(event: InputEvent) -> void:
	for slot in range(6):
		if event.is_action_pressed(StringName("hotbar_%d" % (slot + 1))):
			hotbar.request_slot(slot)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"tactical_end_turn"):
		end_turn_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"tactical_cancel"):
		cancel_requested.emit()
		get_viewport().set_input_as_handled()
