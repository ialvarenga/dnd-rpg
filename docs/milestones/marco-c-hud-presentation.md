# Marco C — HUD, action bar, and presentation

**Status: CONCLUÍDO** (C1–C6).

> Extraído de `implementation_plan.md` v3.0. Registro histórico detalhado. Para
> o estado atual do projeto veja
> [implementation_plan.md](../../implementation_plan.md).

The deterministic simulation, event-sourced state, ports, replay support, and
HUD read model are complete through Marco C. This milestone adds content and
consequence without compromising those boundaries.

## Fase C1 — Shared world session and scene prefabs — concluída

Shared session/picker/preview/map-source extraction and reusable player,
tactical-camera, objective-marker, and directional-light scenes are now used
by the playable roots. Controller compatibility forwarders remain for the
arena runtime boundary. GDScript style and diff checks pass.

- Add `EncounterSession` as the world-side owner of `BattleState`, navigation,
  line-of-sight, resolve → apply → narrate sequencing, and presentation-path
  rebasing. It exposes state/event/rejection signals, non-mutating movement
  previews, movement/interact/ability/end-turn submission, and an action
  availability query.
- Add `MovePreview`, `ScreenPicker`, and cached `MapSpecSource`; both arena
  controllers delegate to these instead of maintaining duplicate raycasts,
  resolver pipelines, and JSON reads.
- Keep the arena controller's public input methods as compatibility
  forwarders for runtime tests.
- Author fixed player, tactical-camera, and objective-marker structure once
  as scenes under `scenes/`; instance them from both playable roots. Keep
  visual dressing data-driven through `AssetCatalog` rather than baking
  Knight art into the player prefab.

## Fase C2 — Definitions, equipment, and action availability — concluída

Rejection reasons and command→ability routing (with an explicit reverse map)
now live in `sim/rules/`; `Resolver` and the new pure `ActionAvailability`
share the same command-phase/ability-cost rejection rules, closing a prior gap
where a perform_attack-effect ability only ever checked/spent
`costs_action`, ignoring any `costs_bonus_action`/`costs_reaction`/
`movement_cost` the same definition declared. `ActorDefinition`/
`ItemDefinition` content (Knight/Longsword/Leather Armor) builds actors via
`ActorState.from_definition()`, replacing controller-local HP constants;
`Equipment` aggregates weapon/armor modifiers at resolver read time over a
fixed slot order, with `EnemyAI` scoring reading through the same
aggregation. Save/content/rules versions are bumped and
`SaveLoadService.load_save()` now refuses an incompatible save instead of
loading it.

- Add data-driven `ActorDefinition` and `ItemDefinition` resources plus fixed
  manifests, actor/item content, ordered ability accessors, and descriptions.
- Add actor ability, equipment, inventory, and definition-id serialization;
  build actors from definitions rather than controller-local HP constants.
- Add pure `Equipment` aggregation over a fixed slot order. Equipment
  modifies attack and armor calculations at resolver read time; no equip
  command or inventory panel lands in this milestone.
- Extract command phase and ability-cost rejections into shared pure rules
  and expose `ActionAvailability` as advisory HUD data. Resolver remains the
  sole authority for command acceptance.
- Move rejection literals and ability routing to dependency-free shared
  rules; preserve established rejection-order semantics and close the
  attack-effect cost-spending gap.
- Bump save, content, and resolver versions; reject incompatible stored
  saves. Keep new immutable content fields out of `stable_snapshot()`.

## Fase C3 — Reusable HUD components — concluída

- Add a pure `HudViewModel` which derives actor information, turn order,
  action availability, and readable narration for every event type.
- Add `HudRoot` with portrait/HP/AC, resource pips and movement meter,
  ability hotbar, turn order, condition strip, combat log, floating combat
  text, tooltip layer, and view-side icon lookup. Each reusable component has
  a script and scene.
- Bind the HUD explicitly to `EncounterSession`; do not introduce autoloads
  or a global signal bus. Preserve the arena debug overlay as a toggleable
  HUD panel. Decorative controls use pass-through mouse filtering.
- Add billboarded world health bars compatible with the Compatibility
  renderer.

## Fase C4 — Character animation state machine — concluída

- Replace bind-pose-at-rest behavior with `ActorAnimationSet` resources and a
  `CharacterAnimator` that merges animation libraries and drives an
  `AnimationTree` state machine.
- Map idle, locomotion, jump, crouch, dodge, interact, attack, block, hit,
  and death verbs to KayKit clips. Missing clips degrade gracefully.
- Add KayKit General, MovementAdvanced, and CombatMelee libraries alongside
  MovementBasic; retain data-driven view-side actor-art and animation
  mapping.

## Fase C5 — Inputs, assets, and documentation — concluída

- Configure six hotbar actions, end-turn, cancel, and canvas-item UI stretch.
- Add Kenney UI and per-icon game-icons.net attribution, update third-party
  dependency records, and add ADR-005 documenting the HUD read-model and
  Resolver authority.
- Update project readmes to describe the current milestone.

## Fase C6 — Verification — concluída

- Add unit coverage for action-availability/resolver agreement, equipment
  aggregation and serialization, and HUD view-model narration of all events.
- Add integration coverage for `EncounterSession`, HUD binding, and character
  animator fallback; generalize async suite registration.
- Keep replay and replay-log suites green. CI gates are GDScript style,
  headless editor import, and the complete test runner.

## Character sheet modal — concluída

- Add a paused, tabbed Character Sheet for Stats, Equipment, and Inventory.
- Keep the sheet as a pure `BattleState` projection; inventory use continues
  through the existing HUD intent and `EncounterSession` controller path.

### Exit criteria

```text
knight HUD renders health, AC, conditions, resources, and movement
↓
hotbar exposes basic attack, dash, and disengage through Resolver
↓
events narrate in the combat log and HUD clicks do not reach terrain
↓
both arena and compiled-map scenes use the same session and prefabs
↓
idle animation plays when movement stops
```
