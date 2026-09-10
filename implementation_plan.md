# Plano Técnico — RPG Tático 3D em Godot

**Versão:** 3.1
**Status:** Marcos A–D concluídos (D4.4 adiado); Marco E em andamento (E0 concluído).
**Princípio condutor:** ter algo **jogável** antes de ter algo **inteligente**
ou **bonito**.

> Este arquivo foi reorganizado para manter apenas o estado atual e o trabalho
> ativo/futuro. Decisões arquiteturais travadas, contratos de simulação e o
> histórico detalhado de cada marco concluído foram movidos para arquivos
> dedicados — veja [Documentação relacionada](#documentação-relacionada) no
> final.

---

## 0. Resumo executivo

Este projeto é construído em três produtos relativamente independentes:

1. **RPG Runtime** — movimento click-to-move, câmera tática, combate por
   turnos, economia de ações, ataques e condições, IA, interação, save/load.
2. **Map Compiler** — recebe um `MapSpec`, instancia terreno, vegetação,
   estruturas e spawns, gera navegação, valida se o mapa é jogável.
3. **AI World Authoring** — converte descrição em linguagem natural em
   `MapSpec`, repara erros estruturados, permite edição incremental via
   `MapPatch`.

A ordem é obrigatória:

```text
RPG Runtime
    ↓
vertical slice jogável
    ↓
Map Compiler manual
    ↓
MapSpec válido e determinístico
    ↓
AI World Authoring
```

Estratégia de reutilização de código:

> reutilizar código e padrões open source onde forem maduros, mas manter o
> estado e a resolução autoritativa do combate em um núcleo de simulação
> determinístico e testável.

Detalhes em [docs/architecture/reuse-strategy.md](docs/architecture/reuse-strategy.md).

---

## 1. Objetivo

Construir um RPG tático 3D em Godot com mecânicas inspiradas em Baldur's Gate
3 e D&D 5e, **sem tentar reproduzir fidelidade gráfica de BG3**.

---

## 2. Estado atual

| Marco | Escopo | Status | Detalhes |
|---|---|---|---|
| A | RPG jogável (simulação pura, câmera, movimento, turnos, combate, IA, dados, save/load, interactables, arte mínima) | ✅ Concluído | [marco-a-playable-rpg.md](docs/milestones/marco-a-playable-rpg.md) |
| B | Map Compiler (catálogo, schema, MapSpec, terreno, vegetação, estruturas, rios/estradas, navegação, validação, mapa jogável) | ✅ Concluído | [marco-b-map-compiler.md](docs/milestones/marco-b-map-compiler.md) |
| C | HUD, action bar e apresentação | ✅ Concluído | [marco-c-hud-presentation.md](docs/milestones/marco-c-hud-presentation.md) |
| D | Feedback, consumíveis e mundo vivo | ✅ Concluído (D4.4 portas/alavancas adiado) | [marco-d-gameplay-depth.md](docs/milestones/marco-d-gameplay-depth.md) |
| E | Profundidade de combate | 🔶 Em andamento (E0 concluído) | Seção 4 abaixo |
| F | Party e progressão | ⏳ Planejado | Seção 4 abaixo |
| G | Aventura e mundo | ⏳ Planejado | Seção 4 abaixo |
| LLM World Authoring | Autoria por IA generativa | ⏸️ Adiado até E–G estabilizarem | [docs/deferred_llm_world_authoring.md](docs/deferred_llm_world_authoring.md) |

Arquitetura, contratos (`Command`/`Event`/`BattleState`/etc.), invariantes e
estrutura de repositório: veja
[docs/architecture/core-simulation.md](docs/architecture/core-simulation.md).

---

## 3. Marcos E–G — combate profundo, party e aventura (trabalho ativo/futuro)

Estes marcos têm prioridade sobre autoria de mundo por LLM. O escopo de LLM
adiado está preservado em
[docs/deferred_llm_world_authoring.md](docs/deferred_llm_world_authoring.md).

### Marco E — Combat depth

**Status:** em andamento — E0 (quick wins, estatísticas derivadas e
`attack_math.gd`) está concluído; novas ações (E1), geometria, furtividade e a
próxima iteração de IA ainda não começaram.

#### E0 — Fairness and attack correctness

- [x] Score AI attacks, healing, and opportunity risk from expected outcomes,
  never speculative dice. Pin the invariant with snapshots that differ only
  in `rng_state`.
- [x] Add full d20/attack breakdowns to the combat log, including modifier,
  target AC/DC, advantage/disadvantage rolls, and cover.
- [x] Wire `SaveLoadService` to F5/F9 quicksave/quickload, a HUD pause menu,
  and a separate autosave captured after encounter start.
- [x] Rebalance the shipping map to two healing potions total (one chest,
  one barrel) and add the archer stat block. The archer deliberately remains
  at a reachable camp position until player ranged attacks or jump/forced
  movement exist; an inaccessible high-ground placement is deferred with E2.
- [x] Derive attack and damage from ability scores, proficiency, weapon
  category, finesse, and magic bonus. Derive armor class from armor category
  and Dexterity. Actors author `weapon_proficiencies` instead of attack/AC
  numbers; unarmed strikes deal 1 + Strength. The bandit chieftain now wears
  a scimitar and studded leather and the bandit raider leather armor, so
  every enemy keeps its old AC; the knight's SRD Chain Mail is AC 16 (was 15).
- [x] Extract one pure `sim/rules/attack_math.gd` consumed by Resolver, AI,
  and HUD; it owns modifier, AC, cover, advantage/disadvantage sources, hit
  probability, and expected damage. Attack events and the combat log name
  every roll-mode source; the AI scores cover and roll mode through it, with
  repeated line-of-sight queries answered once per decision.
- [x] Bump rule/content/save compatibility versions when the derived-stat
  contract lands (rules 10, content 14, save schema 5), with migration
  rejection rather than silent reinterpretation.

#### E1 — D&D action vocabulary

- Add `AbilityDefinition.target_filter` (`hostile`, `ally`, `self`, `any`) to
  Resolver, targeting rules, and planners.
- Add Help and reusable "next attack against" condition expiration. Use it
  for Help, Vex, and Sap.
- Add data-defined weapon mastery effects: longsword Sap, shortbow Vex,
  dagger Nick, plus Graze and Topple for enemy weapons. Record open content
  and adaptations in the rules ledger and third-party notice.
- Expand Shove to choose Push or Prone. Add forced movement, wall blocking,
  fall damage, a `NavProvider.project_push()` query, and fakes/tests.

#### E2 — Battlefield geometry

- Add original/deviation high-ground attack modifiers (+2 at least 2.5m
  above, -2 below) through shared attack math.
- Add terrain regions with weighted path cost and `NavProvider.path_cost()`
  for river, thicket, and rubble; mirror the field through every MapSpec
  schema and map-builder validation surface.
- Add point targeting, radius, DEX save for half, and explosive barrels as
  the first area-effect capability.

#### E3 — Stealth, perception, and surprise

- Move hostile detection into a simulation rule. Add passive Perception and
  a Sneak toggle resolved as Stealth versus nearby passive Perception.
- Permit exploration attacks to begin the relevant encounter and resolve as
  the opening action.
- Add surprise initiative disadvantage and hidden-attacker first-hit
  advantage; offer "skip round 1" only as an explicit map variant.

#### E4 — Tactical AI

- Replace content-id checks with `AbilityDefinition.ai_tags` such as
  `defensive`, `mobility`, `escape`, and `control`.
- Add focus-fire/kill-probability target selection, leader protection, and
  ranged cover seeking.
- Add morale-driven flee/surrender, reusing disposition and encounter
  clearing.

### Marco F — Party and progression

- Split `compiled_map_controller.gd` into input/targeting, dialogue, and
  interactable coordinators before adding party state. Remove actor-1
  assumptions; add MapSpec party data in every schema mirror; bind the HUD
  to the selected hero and use exploration follow-the-leader.
- Add death saves, stabilization by Help/potion, and correct 0-HP damage
  rules.
- Add SRD level 1–5 Fighter, Rogue, Cleric, and Wizard capabilities,
  including spell slots and concentration resources.
- Use milestone leveling per cleared encounter/objective, then add short
  rests with Hit Dice and long rests at camp. Remove the per-encounter pool
  refill.

### Marco G — Adventure and world

- Persist world flags in `BattleState`; add dialogue requirements/effects
  for flags, items, and coins plus an objective journal in the HUD.
- Add doors, levers, locks, and traps with thieves' tools, Athletics,
  passive Perception, and disarm rules.
- Put skill proficiencies on actors; dialogue names only the skill and the
  simulation derives proficiency.
- Add drops, merchant coins, and equip/unequip.
- Add a map quality encounter-budget/potion validator and author three to
  four varied road encounters.

### Verification for Marcos E–G

- Unit suites: AI RNG independence, equipment/derived math, Help/masteries/
  push/fall/high-ground rules, replay, and save compatibility.
- Gates: `godot --headless --path godot --script res://tests/test_runner.gd`
  and `python3 scripts/check_gdscript_style.py`.
- Manual map pass: fair enemy choices, matching tooltip/log math, cliff
  shove, and quicksave/quit/quickload mid-combat.

---

## 4. Testing strategy

### Pure unit tests

Target:

```text
sim/
```

Examples:

- attack math;
- advantage;
- initiative;
- movement budget;
- conditions;
- reactions.

### Property tests

Examples:

```text
HP never below expected bounds
movement_remaining never negative
dead actor cannot act
action cannot be spent twice
```

### Determinism tests

```text
same state + same command
→
same result hash
```

### Integration tests

Godot headless with:

- navigation;
- LoS physics;
- door nav region;
- serialization.

### Golden replay tests

Keep a few known command logs:

```text
replays/golden/
```

CI verifies generated event hashes.

---

## 5. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Pure sim accidentally coupled to Node | Critical | CI architecture test + code review |
| Terrain3D runtime path insufficient | High | Terrain Spike + TerrainProvider |
| Runtime bake slow | Medium | profile + source arrays + optional chunks |
| AI simulation too expensive | Medium | candidate limits + query budget |
| D&D scope explosion | High | fixed v1 subset |
| Save compatibility breaks | High | schema/content/rules versioning |
| Opportunity reaction sequencing bugs | High | segmented movement + golden tests |
| Door pathfinding incorrect | Medium | dedicated nav region/layers |
| Open-source license drift | Medium | commit pin + reuse audit |
| Art style inconsistency | Medium | one primary asset family |
| Map schema divergence | Medium | JSON Schema canonical source |

Política de dependências externas (licença, pinning, etc.):
[docs/architecture/reuse-strategy.md](docs/architecture/reuse-strategy.md#dependency-policy).

---

## 6. Roadmap resumido

```text
A0 Foundation ✅
      ↓
A1 Free Movement
      ↓
A2 Pure Simulation Integration
      ↓
A3 Movement Rules
      ↓
A4 Turns
      ↓
A5 Combat + Reactions
      ↓
A6 Enemy AI
      ↓
A7 Data Definitions
      ↓
A8 Save / Replay
      ↓
A9 Interactables
      ↓
A10 Minimal Art
      ↓
===================
    MARCO A
  PLAYABLE RPG ✅
===================
      ↓
B1 Asset Catalog
      ↓
B2 Schema
      ↓
B3 Handwritten MapSpec
      ↓
B4 Terrain Provider
      ↓
B5 Terrain
      ↓
B6 Vegetation
      ↓
B7 Structures
      ↓
B8 Rivers/Roads
      ↓
B9 Navigation
      ↓
B10 Validation
      ↓
B11 Playable Map Completion
      ↓
===================
    MARCO B
  MAP COMPILER ✅
===================
      ↓
Marco C: HUD + presentation ✅
      ↓
Marco D: live-world feedback ✅
      ↓
Marco E: combat depth 🔶 em andamento
      ↓
Marco F: party + progression
      ↓
Marco G: adventure + world
      ↓
===================
  DEFERRED AFTERWARD
  LLM WORLD AUTHORING
===================
```

---

## 7. O que explicitamente NÃO fazer agora

Não implementar:

- full D&D rules;
- spells (fora de Marco F);
- classes (fora de Marco F);
- character creator;
- multiplayer;
- dialogue cinematics;
- procedural buildings;
- huge maps;
- world streaming;
- AI-generated meshes;
- vertical combat;
- partial cover além de half/three_quarters/total já implementado;
- complex inventory;
- crafting;
- quest generator;
- LLM integration (deferred to
  [docs/deferred_llm_world_authoring.md](docs/deferred_llm_world_authoring.md)
  until combat, party, and world contracts are stable);
- realistic terrain erosion.

---

## Documentação relacionada

- **Arquitetura e contratos travados** — [docs/architecture/core-simulation.md](docs/architecture/core-simulation.md)
  (Command/Event/BattleState, invariantes, estrutura de repositório, ADR
  registry).
- **Correções de design iniciais** (rationale) — [docs/architecture/design-corrections.md](docs/architecture/design-corrections.md)
- **Estratégia de reutilização open source** — [docs/architecture/reuse-strategy.md](docs/architecture/reuse-strategy.md)
- **Marco A — RPG jogável** (histórico completo) — [docs/milestones/marco-a-playable-rpg.md](docs/milestones/marco-a-playable-rpg.md)
- **Marco B — Map Compiler** (histórico completo) — [docs/milestones/marco-b-map-compiler.md](docs/milestones/marco-b-map-compiler.md)
- **Marco C — HUD e apresentação** (histórico completo) — [docs/milestones/marco-c-hud-presentation.md](docs/milestones/marco-c-hud-presentation.md)
- **Marco D — Profundidade de gameplay** (histórico completo) — [docs/milestones/marco-d-gameplay-depth.md](docs/milestones/marco-d-gameplay-depth.md)
- **LLM World Authoring (adiado)** — [docs/deferred_llm_world_authoring.md](docs/deferred_llm_world_authoring.md)
- **ADRs** — [docs/ADR/](docs/ADR/)
