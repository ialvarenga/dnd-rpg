class_name AbilityDefinition
extends Resource

## Stable content definition for a command-triggered ability (Basic Attack,
## Dash, Disengage, ...). Resolver never branches on `id`; it validates the
## generic costs below and then executes `effects` through generic handlers.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""

@export var costs_action: bool = false
@export var costs_bonus_action: bool = false
@export var costs_reaction: bool = false
@export var movement_cost: float = 0.0

## none | actor | ground_point
@export var targeting: StringName = &"none"

## Maximum distance from the actor to an actor/ground target. A negative value
## preserves legacy definitions whose perform_attack effect owns the range.
## Keeping range at the ability boundary lets movement-assisted targeting work
## for future spells and other targeted actions without knowing their effects.
@export var target_range_meters: float = -1.0

## True when this ability may also resolve outside combat. Every other ability
## stays behind the combat turn-ownership gate, so this defaults false and
## existing content keeps its exact rejection order.
@export var usable_in_exploration: bool = false

## Activations available before a recharge. -1 means unlimited, which is what
## every ability without a per-rest budget wants, so existing content keeps its
## exact behavior. Resolver never branches on `id` to decide this.
@export var max_uses: int = -1

## When a spent pool refills: encounter | turn. There is no rest system, so an
## encounter boundary stands in for the SRD short rest (see NOTICE.md).
## Ignored while max_uses is negative.
@export var uses_recharge: StringName = &"encounter"

## Presentation-only: the ActorAnimationSet verb the user plays when this
## ability's action is spent. Empty means no dedicated animation (attacks are
## narrated by attack_rolled instead). The Resolver never reads it.
@export var animation_verb: StringName = &""

@export var effects: Array[AbilityEffect] = []
