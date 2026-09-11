# Marco E — Combat Depth

## Status

Complete in the deterministic simulation and automated headless suite. The
interactive visual checklist at the end remains a release/manual QA pass.

## E1 — actions and masteries

- `ItemDefinition.mastery` assigns Sap to Longsword, Vex to Shortbow, Nick to
  Dagger, Graze to the bandit raider's Scimitar, and Topple to the bandit
  chieftain's Toppling Club.
- `MasteryRules` is the shared vocabulary for Resolver, HUD, and AI. Sap and
  Vex use the reusable next-attack condition machinery. Nick performs one
  offhand Light attack per turn without adding the ability modifier to damage.
- Shove commands require a Push or Prone mode. Push uses
  `NavProvider.project_push()` and emits attempted, resisted, blocked,
  displaced, fall, damage, and incapacitation outcomes without spending the
  target's movement.

## E2 — battlefield geometry and area effects

- `AttackMath` owns the original +2 high-ground/-2 low-ground modifier at a
  2.5 m height difference. Events, logs, HUD probability, and AI all consume
  the same evaluation.
- Heightfield hills have a rotated <=30° generated ramp. Their decorative
  sides remain steep, their summit is reachable, and the same surface feeds
  mesh, collision, navigation, and push/drop queries.
- River paths and thicket/rubble polygons compile to weighted movement
  regions. `path_cost()` drives previews, movement clamping/spend, and AI
  scoring. Bridges avoid the river multiplier rather than being the only way
  across shallow water.
- Actor, interactable, and ground-point targeting are supported. Area damage
  rolls once, then resolves saves/damage in actor-ID order. Explosive
  interactables (a separately tinted barrel, radius preview, Dexterity save
  for half, destruction event, generated flash) are generic Resolver/AI
  content, but nothing can trigger one yet -- no ability targets them
  directly. That arrives with a thrown-bomb ability. Chain reactions are
  deliberately omitted.

## E3 — stealth and surprise

- Actor data carries skill proficiencies; passive Perception and observer
  detection live in pure `DetectionRules`.
- Sneak is an exploration toggle with a single Stealth roll and per-observer
  hidden state. Movement rechecks detection; attacking reveals the attacker
  after granting the first qualifying hidden-attacker Advantage.
- An exploration attack starts the target's authored encounter and resolves
  as its opening action. Surprised defenders roll initiative with
  Disadvantage. `skip_surprised_round_one` is an explicit per-encounter
  MapSpec variant and defaults off.

## E4 — tactical AI

- Ability behavior comes from `ai_tags`, not ability IDs. Candidate selection
  filters enemies hidden from that observer.
- Expected attack outcomes drive focus fire and kill probability. Protector
  actors prioritize threats near a leader; ranged actors evaluate two bounded
  lateral cover positions, high ground, weighted travel cost, and standoff.
- Area scoring rewards expected enemy damage and penalizes friendly fire and
  self-harm. Mastery/control utility contributes deterministic pre-roll score.
- Low morale produces flee movement above one-third HP and surrender at or
  below one-third HP. Surrender neutralizes the actor, removes it from turn
  eligibility, and reuses normal encounter resolution.
- Per-turn budgets default to six navigation and eight LOS queries; target,
  area, and cover candidates are capped. Tests prove choices do not change
  when only `rng_state` changes.

## Compatibility

- Resolver rules: 14
- Definition content: 18
- Save schema: 7

All three must match on load. The new actor/interactable/detection/surprise
state is serialized and cloned; incompatible saves are rejected.

## Shipping-map manual QA

Use `world_authoring/maps/test_map.json` and verify:

1. Sap/Vex/Graze/Topple/Nick feedback and combat-log text.
2. Shove mode selection, resistance, a wall-blocked Push, displacement, and a
   push from the Emberwatch rise that produces fall damage.
3. Reachable hilltop combat and both high/low-ground modifiers.
4. River, thicket, and rubble path-preview costs; the bridge should be cheaper.
5. (Deferred until a bomb/throw ability ships) Explosive radius preview,
   saves, damage, barrel destruction, and AI refusal when an ally or itself
   makes the blast unsafe.
6. Sneak crouch, hidden/detected feedback, an exploration opening attack, and
   initiative Disadvantage. Temporarily author the skip variant true to verify
   its first-round event.
7. Archer cover/high-ground movement and low-morale flee/surrender.
8. F5 quicksave, quit/reload, and F9 quickload during combat with stealth,
   conditions, and surprise state present.
