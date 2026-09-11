# ADR-008: Combat depth remains event-driven across pure ports

## Status

Accepted.

## Context

Marco E adds weapon masteries, forced movement and falls, high ground,
weighted terrain, area damage, stealth/surprise, and richer AI. These features
all cross simulation, navigation, HUD, persistence, and replay boundaries. If
each consumer reimplemented the rule, previews and AI would drift from the
resolver; if the resolver queried Nodes or physics directly, replay would stop
being deterministic.

## Decision

- `AttackMath`, `MasteryRules`, and `DetectionRules` are pure shared rule
  modules. Ability and actor resources carry modes, mastery names, skills,
  morale, and `ai_tags`; neither Resolver nor AI branches on a content ID.
- `NavProvider.path_cost()` and `project_push()` are the only simulation-facing
  queries for weighted travel and stable forced-movement projection. Godot's
  adapter samples authored regions and the navmesh; tests provide fakes.
- Commands carry targeting intent (`mode`, actor/interactable/point). Events
  carry resolved rolls, elevation, displacement, falls, saves, explosions,
  detection, mastery, and surrender. Views animate and narrate those events.
- Hidden relationships are authoritative per observer (`hidden_from`), not a
  presentation visibility guess. AI filters unknown targets before candidate
  generation and scores only expected outcomes fixed before a roll.
- Candidate counts and navigation/LOS queries remain explicitly bounded.
  Area scoring prices enemy damage positively and friendly/self harm
  negatively; movement scoring includes weighted cost, cover, and elevation.
- A surrender changes disposition to neutral and removes turn eligibility, so
  the existing encounter-outcome path clears a fight when no hostile actor can
  continue. Low morale above the surrender threshold instead produces a
  deterministic flee movement.

## Deliberate adaptations

- High/low ground is an original symmetric ±2 modifier at a 2.5 m threshold;
  SRD 5.2.1 does not define this modifier.
- Nick folds one offhand Light-weapon attack into the Attack action once per
  turn and omits the ability modifier from its damage. This is the smallest
  deterministic two-weapon foundation needed by the current one-attack action
  model; bonus-action two-weapon fighting and weapon swapping remain out of
  scope.
- Shove uses the defender's better Strength/Dexterity save against the
  attacker's Strength-based DC. Push distance is 3 m (the metric project
  adaptation of 10 ft); size limits remain deferred.
- Explosive barrels roll damage once, then resolve Dexterity saves and damage
  in actor-ID order. Chain reactions are intentionally omitted.
- Surprise normally means initiative Disadvantage. Skipping surprised actors'
  first round exists only when an encounter explicitly authors
  `skip_surprised_round_one`.

## Compatibility

These semantics require Resolver rules version 14, content version 18, and
save schema 7. Saves must match all three versions; no migration silently
reinterprets older combat state.
