class_name ActorDefinition
extends Resource

## Stable content definition for a playable/enemy actor template (Knight,
## ...). ActorState.from_definition() builds a fresh, independent ActorState
## from one of these; the resolver never reads ActorDefinition directly, the
## same way it never reads AbilityDefinition/ConditionDefinition content
## through anything but the ActorState it already produced (ADR-004).

@export var id: StringName = &""
@export var display_name: String = ""

@export var max_hp: int = 1
@export var armor_class: int = 10

@export var strength: int = 10
@export var dexterity: int = 10
@export var constitution: int = 10
@export var intelligence: int = 10
@export var wisdom: int = 10
@export var charisma: int = 10
@export var proficiency_bonus: int = 2
@export var saving_throw_proficiencies: Array[StringName] = []

@export var movement_speed: float = 9.0

@export var attack_bonus: int = 0
@export var damage_die: int = 6
@export var damage_modifier: int = 0

## Ordered so a HUD hotbar (Fase C3) and ActionAvailability enumerate an
## actor's abilities deterministically instead of depending on Dictionary or
## manifest iteration order.
@export var ability_ids: Array[StringName] = []

## Slot (Equipment.SLOT_WEAPON/SLOT_ARMOR) -> ItemDefinition id. There is no
## equip command in this milestone: this is the actor's fixed starting
## loadout, copied once into ActorState.equipment_slots.
@export var equipment_slots: Dictionary = {}

## Item ids carried but not equipped.
@export var starting_inventory: Array[StringName] = []

## Single-denomination currency copied into the actor's authoritative wallet.
## This is separate from inventory because coins are fungible and have no
## equipment or use behavior.
@export var starting_coins: int = 0
