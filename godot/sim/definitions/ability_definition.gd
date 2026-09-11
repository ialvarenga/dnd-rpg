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

## actor target relationship: hostile | ally | self | any. "hostile" means
## the opposing combat side, not hostile disposition, so Talk still works on
## neutral enemy-side NPCs. Applies only when targeting == &"actor"; every
## actor target must still be alive. Downed-target abilities (stabilize,
## potion) are deferred to Marco F.
@export var target_filter: StringName = &"hostile"

## Maximum distance from the actor to an actor/ground target. A negative value
## preserves legacy definitions whose perform_attack effect owns the range.
## Keeping range at the ability boundary lets movement-assisted targeting work
## for future spells and other targeted actions without knowing their effects.
@export var target_range_meters: float = -1.0

## Optional radius around a ground point or interactable target. A positive
## value makes the ability an area action; Resolver enumerates affected actors
## in stable actor-id order.
@export var target_radius_meters: float = 0.0

## Command metadata "mode" must name one of these entries. This is used by
## actions such as Shove without teaching the resolver a Shove content id.
@export var modes: Array[StringName] = []

## True when this ability may also resolve outside combat. Every other ability
## stays behind the combat turn-ownership gate, so this defaults false and
## existing content keeps its exact rejection order.
@export var usable_in_exploration: bool = false

## True when this ability is only legal during exploration. This is separate
## from usable_in_exploration because most abilities are combat actions that
## may optionally be exposed outside combat; Talk is exploration-only.
@export var exploration_only: bool = false

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

## Pure tactical meaning consumed by AI and HUD. Content ids are deliberately
## not a decision surface.
@export var ai_tags: Array[StringName] = []

@export var effects: Array[AbilityEffect] = []
