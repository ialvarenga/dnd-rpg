# ADR-009: Ledge jumps are Strength-gated navigation links

## Status

Accepted. Amends ADR-007 (jump links were out of scope; hills could not
overlap) and ADR-008 (a Shove fall now leaves its target Prone).

## Context

The only way between heights was the earthen ramp a `navigable` hill
generates (ADR-007), and the shipping map's single ramp led straight to the
archer's perch. Hills were otherwise cliffs: walls that steer routes. Nothing
in the simulation could jump, drop off a ledge on purpose, or climb.

SRD 5.2.1 (Rules Glossary; CC-BY-4.0, attribution in
`docs/third_party/NOTICE.md`) supplies the numbers, in the project's metric
scale of 1 ft = 0.3 m:

- **Long Jump**: horizontally up to the Strength score in feet after a 10 ft
  (3 m) run-up, half from a standstill. Each foot jumped costs a foot of
  movement.
- **High Jump**: up 3 + Strength modifier feet (minimum 0) after the same
  run-up, half from a standstill, at the same movement cost.
- **Falling**: 1d6 Bludgeoning per 10 ft (3 m) fallen, maximum 20d6. The
  creature lands Prone unless it took no damage.

The SRD has no rule for jumping *down* on purpose.

## Decision

### Rules (`sim/rules/jump_rules.gd`)

`JumpRules` is a pure module; resolver, routing, AI, preview, and the
character sheet all read it.

- A **deliberate drop** absorbs the jumper's running High Jump height. What
  remains is an SRD fall: `floor(effective / 3 m)` d6, and Prone whenever that
  is at least one die. The Knight (STR 14) drops under 4.5 m safely and the
  Archer (STR 10) under 3.9 m. This is a project rule.
- A **climb** onto a ledge is allowed if the rise is no more than the High Jump
  for that approach: running after a 3 m straight run-up, otherwise standing.
- **Cost** is movement only, as in SRD 2024. A drop pays its horizontal
  distance, since falling is free. A climb pays horizontal distance plus the
  rise.
- Ledges under 0.6 m are steps and are walked, not jumped.
- A **Shove fall** absorbs nothing. It keeps ADR-008's 2.5 m threshold and
  `max(1, floor(d / 3 m))` d6, and now also applies Prone per SRD Falling.

### Navigation

- Hills gain `jumpable` (the summit is walkable, no blocker) and `height_m` (a
  summit lower than the model; the model is sunk by the difference).
- Hills may overlap: stamps already combine with `max()`, so an overlap
  builds a terrace. Every base elevation is sampled before any stamp.
- `MapNavigationCompiler` drops navmesh triangles that straddle a jumpable
  ledge. Otherwise a short ledge across one 2 m sample would pass the 35°
  slope gate as a walkable slope.
- `JumpLinkCompiler` samples each jumpable edge every ~1.5 m and finds the
  walkable surface on each side. It emits one-way `NavigationLink3D`s:
  - **Safe drop**, on the layer of the lowest Strength that lands it safely.
  - **Hurtful drop**, on a shared top layer with a 25 m enter cost, so routing
    uses it only when nothing safer exists.
  - **Standing climb**.
  - **Running climb**, whose link starts one run-up back from the ledge.
- A link's layer bit N (1..30) means "needs Strength N"; layer 1 is walking.
  `NavProvider.for_jumper(strength)` returns a view that routes only across
  the ledges that Strength can take. The resolver, both approach planners, and
  the AI (through the resolver) use it. `jump_between(from, to)` tells the
  resolver which path segments are jumps.
- `GodotNavProvider.is_reachable` rejects a route that ends a storey away from
  its target, so a summit without links for this Strength is an island.
  Same-level partial routes keep ADR-008's "get as close as you can" behaviour.
- The compiled map disables async navigation iterations and syncs once at
  load, since the links take several extra frames to become queryable.

### The Jump action

- `data/abilities/jump.tres` is a `ground_point` hotbar ability with a `leap`
  effect. It is an explicit leap to a chosen spot: across a gap, off a ledge,
  or onto one.
- `Resolver._resolve_leap` checks the target against `JumpRules.leap_check`:
  - The horizontal distance must be within the Long Jump.
  - A rise must be within the High Jump.
  - Both are halved unless `ActorState.run_up_m` is at least 3 m.
  - It also needs walkable ground at the target (`NavProvider.surface_point`)
    and no wall in between.
- Costs, falls, Prone, and opportunity attacks reuse the ledge-jump path. A
  Prone jumper stands first.
- `run_up_m` counts metres walked immediately before. It is reset by acting, by
  a jump or push, and at turn start. It is serialized (save schema 8).
- While aiming, the preview shows a ring of current reach, the arc, and either
  the landing ("Jump ↑ 1.5 m", "Fall 4.2 m · 1d6 · Prone") or why the spot
  cannot be reached ("Too far… Run 3 m first to jump farther.").

### Actions outside combat

- Every shipped hotbar ability is `usable_in_exploration`.
- Outside combat there is no action economy. Turn flags and movement never gate
  or spend anything; only use pools and consumed items do.
- An ability aimed at the other side (an attack, Shove) opens combat first,
  as attacks already did (`CommandPhaseRules.opens_combat_from_exploration`).
- Hotbar buttons are never disabled. Clicking one that cannot be used right
  now, say mid-combat with the action spent, floats the reason over the
  character. The tooltip still carries it.
- The hotbar holds 10 slots on keys 1–9 and 0.
- `Resolver.RULES_VERSION` is 16 and `DefinitionLibrary.CONTENT_VERSION` is 19.

### Resolution, presentation, AI

- `_resolve_move` splits a path into walking legs and jump legs.
  - An opportunity attack provoked by a jump resolves at the takeoff point.
  - Clamping never ends a move in mid-air.
  - A hard landing emits `fall_started` (`deliberate`, `prone`), the fall
    damage, and Prone in combat only, then ends the move.
  - `jump_performed` carries kind, height, cost, and whether it was a running
    jump.
- `EventPlayer` holds the rest of a batch while a jumper (or a creature pushed
  off a ledge) is in the air, as it already does for arrows.
- `CharacterView` flies the shared `JumpArc` with collision bypassed, using
  KayKit's `Jump_Start` / looping `Jump_Idle` / `Jump_Land`. A hard landing
  plays the existing knockdown instead.
- `JumpArc` is a ballistic parabola sized by the leap rather than a fixed hop:
  its apex is 0.25 m per metre jumped (floor 0.6 m, ceiling 1.6 m), a climb
  passes 0.5 m over the lip it lands on, a drop pushes off 0.3 m above the
  ledge it leaves, and `duration` is the free-fall time for that apex under a
  stylised 17.6 m/s². The original fixed 0.4 m apex, flown in 0.44 s, left the
  KayKit rigs — two heads tall on 0.53 m legs — shuffling rather than leaping.
- Takeoff, landing, and hard-landing sounds play on a separate `MovementSfx`
  player, so the thud survives the hurt grunt.
- The path preview draws jumps as arcs and labels the first hurtful one, for
  example "Fall 4.2 m · 1d6 · Prone".
- The AI scores a hard landing like an opportunity attack: by expected fall
  damage plus a Prone penalty.
- `Resolver.RULES_VERSION` is 15.

## Consequences

- The Emberwatch rise lost its ramp. Its archer perch (4.2 m) steps down
  terraces of 3.0 m and 1.5 m:
  - The Archer descends every step but cannot climb back.
  - The Knight can climb each step with a run-up.
  - The 4.2 m south face is safe for the Knight and floors the Archer.
- Click-to-move routing only jumps at hill edges. Long jumps across gaps (a
  river, a chasm) are the Jump action's job, not a routed link. Climbing
  beyond the High Jump (ladders, a Climb action) remains out of scope.
- Hill rotations other than 0/90/180/270° appear to turn the stamp opposite to
  the model (`stamp_hill` versus the mesh's `rotation.y`). Right angles hide it
  because the footprints are symmetric; the terraces use only right angles.
