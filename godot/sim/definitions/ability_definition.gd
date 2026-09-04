class_name AbilityDefinition
extends Resource

## Stable content definition for a command-triggered ability (Basic Attack,
## Dash, Disengage, ...). Resolver never branches on `id`; it validates the
## generic costs below and then executes `effects` through generic handlers.

@export var id: StringName = &""
@export var display_name: String = ""

@export var costs_action: bool = false
@export var costs_bonus_action: bool = false
@export var costs_reaction: bool = false
@export var movement_cost: float = 0.0

## none | actor | ground_point
@export var targeting: StringName = &"none"

@export var effects: Array[AbilityEffect] = []
