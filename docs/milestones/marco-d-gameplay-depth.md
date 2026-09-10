# Marco D — Gameplay depth: feedback, consumables, and a live world

**Status: concluído**, exceto portas e alavancas no mapa de envio (D4.4), que
continuam explicitamente adiadas.

> Extraído de `implementation_plan.md` v3.0. Registro histórico detalhado. Para
> o estado atual do projeto veja
> [implementation_plan.md](../../implementation_plan.md).

The deterministic simulation, event-sourced state, ports, replay support, and
HUD read model are complete through Marco C. This milestone adds content and
consequence without compromising those boundaries. It is deliberately ordered
to land immediate feedback first, then close the loop:

```text
chest → loot → inventory → drink → heal
```

Out of scope: weight/encumbrance, currency, shops, equip/unequip, rarity,
crafting, and spell slots.

## Fase D1 — Wire existing feedback into the running game

1. [COMPLETE] Instantiate `CombatLog` and `TooltipLayer` in
   `scenes/ui/hud_root.tscn`. `HudRoot` subscribes to
   `EncounterSession.events_resolved` and appends `HudViewModel.narrate()`
   output after the events have been applied. It still emits only intent and
   never creates commands, per ADR-005.
2. [COMPLETE] Extend `view/event_player.gd` to create `FloatingCombatText` for
   `damage_taken` (and `healing_received` in D2) and present the currently
   silent `actor_downed`, condition, and command-rejection events. Playback
   remains strictly post-apply under ADR-003.
3. [COMPLETE] Attach `WorldHealthBar` to each `CharacterView` in
   `CompiledMapController`, updating from `session.state_changed`.
4. [COMPLETE] Add `MusicDirector` to the test arena too, or document the
   intended asymmetry with the compiled-map scene.

**Value:** readable combat log, damage numbers, and enemy health bars from
already-authored components.

## Fase D2 — Consumables and healing

Model a consumable as an ability, not a new command. `Resolver.resolve()`
already dispatches registered ability ids and the generic action hotbar
already renders available ability dictionaries.

1. [COMPLETE] Add `heal_die`, `heal_dice_count = 1`, `heal_modifier`, and
   `consumes_item_id` to `AbilityEffect`; add `use_ability_id` to
   `ItemDefinition` (empty means not consumable).
2. [COMPLETE] Add `Dice.roll_dice(rng_state, count, sides)`. Its RNG advance
   order must match repeated `roll_die` calls exactly.
3. [COMPLETE] Add resolver effects `heal` and `consume_item`. They emit
   `healing_received { actor_id, amount, hp_before, hp_after }` and
   `item_consumed { actor_id, item_id }`; `apply()` clamps healing to max HP
   and removes exactly one matching inventory item.
4. [COMPLETE] Extend shared `AbilityCostRules.rejection_for_cost()` to
   receive definitions and reject a required missing item with
   `ITEM_NOT_IN_INVENTORY` in `RejectionReason`. Both Resolver and
   `ActionAvailability` use this one rule path.
5. [COMPLETE] Add `ActionAvailability.effective_ability_ids(actor, defs)`:
   actor abilities plus each carried item's `use_ability_id`. Use it in the
   HUD view model and encounter session so an unavailable potion is shown
   consistently.
6. [COMPLETE] Treat inventory as mutable state: update its `ActorState`
   documentation and include it in `BattleState.stable_snapshot()` so replay
   hashes catch inventory divergence.
7. [COMPLETE] Add an AI consumable candidate and score healing more highly
   as HP falls. Candidates continue to be validated by the real Resolver
   before scoring.
8. [COMPLETE] Add `quaff_healing_potion` (action, no target, heal 2d4+2 then
   consume) and `healing_potion` resources; give knight and raider one,
   register an icon, add both resources to fixed manifests, update ordering
   tests, and bump the content version.
9. [COMPLETE] Narrate healing and consumption, add full event-coverage
   tests, and bump save schema version according to the existing
   incompatible-save policy.

## Fase D3 — Chests contain loot

1. [COMPLETE] Add `contents: Array[StringName]` to `InteractableState`,
   including clone, serialization, deserialization, and stable snapshots.
2. [COMPLETE] When an opened container has contents, `_resolve_interact()`
   emits `items_looted { actor_id, interactable_id, item_ids }`. Applying it
   appends items to actor inventory and clears the container. Keep
   transitions data-driven rather than branching on an instance id.
3. [COMPLETE] Give the hand-built test-arena chest a healing potion.

## Fase D4 — Shipping-scene interactables

1. [PARTIAL] `MapCompiler` compiles authored interactable visuals through
   `AssetCatalog`; `CompiledMapController` creates the authoritative
   `InteractableState`s because the compiler remains presentation-only.
2. [COMPLETE] Have `CompiledMapController` seed those states, set
   `interactable_id` metadata and ScreenPicker collision layer 3, and route
   interact input using the existing test-arena pattern.
3. [COMPLETE] Add the schema-supported `barrel` transition to resolver data.
4. [DEFERRED] Add shipping-scene doors and levers. Resolver transitions
   exist, but MapSpec authoring, collision/nav updates, and animated
   presentation are still explicit future work.

## Fase D5 — Open-SRD tactical rules bundle

Source policy: only SRD 5.2.1 material under CC BY 4.0 or original content.
Every ability, condition, item, and actor is traced in
`docs/rules/open-content-ledger.csv`; required attribution and adaptations
are recorded in `docs/third_party/NOTICE.md`. Product copy uses
"5E compatible."

1. [COMPLETE] Make defeat, encounter victory, and map victory authoritative
   simulation outcomes. Zero HP ends the single-hero run; death saves remain
   deferred. Add a blocking outcome overlay and deterministic in-memory
   Retry Encounter checkpoint that restores state and presentation.
2. [COMPLETE] Resolve authored encounter membership to runtime actor IDs,
   scope initiative and outcomes to its participants, persist cleared
   encounters, and require `emberwatch_ambush` before completing the
   `emberwatch_camp` radius objective.
3. [COMPLETE] Replace runtime condition ID arrays with serializable
   `ConditionState` instances carrying source, duration, and turn-boundary
   expiration metadata.
4. [COMPLETE] Add reusable deterministic D20 saving throws and Shove (better
   Strength/Dexterity save, Prone on failure), plus Dodge until the owner's
   next turn.
5. [COMPLETE] Add Shortbow, ranged attack, and Archer content with
   normal/long range, nearby-hostile disadvantage, damage type, and
   beyond-range rejection.
6. [COMPLETE] Add deterministic cover (`none`, `half`, `three_quarters`,
   `total`) to `LosProvider`; apply +2/+5 AC or reject total cover.
7. [COMPLETE] Generalize enemy ability enumeration and utility scoring so
   attacks, approach movement, healing, Dash, Dodge, and Disengage compete
   through the same Resolver legality path.
8. [COMPLETE] Bump resolver, content, and save-schema versions and cover the
   new outcomes, objectives, conditions, saving throws, ranged rules,
   replay, serialization, and retry regression in the headless suite.

## Marco D architectural constraints

- Authoritative state remains `BattleState`; only `Command → Resolver →
  Event → apply()` mutates it. `resolve()` never mutates its input (ADR-001).
- Definitions stay in fixed `.tres` manifests keyed by `StringName`; resolver
  logic does not branch on concrete content ids (ADR-004).
- Views only play accepted, already-applied events (ADR-003). The HUD
  remains a `HudViewModel` projection that emits intent through
  `EncounterSession` (ADR-005).
- Register new test suites in `godot/tests/test_runner.gd` and commit `.uid`
  files alongside any new scripts.

Deferred after this milestone: death saves and revival, Dexterity-save
advantage while Dodging, ammunition and weapon masteries, resistance and
vulnerability, and shipping-scene doors/levers.
