# Marco A — RPG jogável

**Status: CONCLUÍDO.**

> Extraído de `implementation_plan.md` v3.0. Registro histórico detalhado das
> spikes e fases que produziram o vertical slice jogável. Para o estado atual
> do projeto veja [implementation_plan.md](../../implementation_plan.md); para
> os contratos de arquitetura veja
> [docs/architecture/core-simulation.md](../architecture/core-simulation.md).

## Definição do Marco A — Jogável

Uma cena feita à mão contendo:

- terreno;
- obstáculos;
- uma porta;
- um baú;
- um jogador;
- dois inimigos.

Fluxo:

```text
exploração
   ↓
click-to-move
   ↓
aproximação de inimigo
   ↓
combate começa
   ↓
initiative
   ↓
turnos
   ↓
move
attack
dash
disengage
reaction
   ↓
morte
   ↓
combat end
```

Além disso:

```text
save mid-combat
↓
close game
↓
load
↓
continue exactly
```

Nenhuma IA generativa. Nenhum MapSpec. Nenhum mapa procedural.

---

# Spike A-0 — Simulação determinística

**Status:** concluído.

## Objetivo

Provar o modelo:

```text
Command
↓
Resolver
↓
Events
↓
Apply
```

sem nenhuma cena.

## Implementar

Dois atores.

Campos mínimos:

```text
HP
AC
movement
attack bonus
damage die
position
```

Comandos:

```text
move
attack
end_turn
```

Providers:

```text
FakeNavProvider
FakeLosProvider
```

## Teste determinístico

Executar:

```text
simulate(seed=42)
```

1000 vezes como execuções independentes.

Esperado:

```text
hash(event_log) identical
```

para todas.

Depois:

```text
seed=43
```

deve produzir resultado diferente quando houver aleatoriedade relevante.

## Testes adicionais

```text
state clone
does not mutate original

resolve
does not mutate original

apply
only changes fields represented by event
```

## Critério de sucesso

```text
godot --headless
```

executa milhares de turnos sem:

- SceneTree;
- animação;
- input;
- janela;
- dependência de Node.

---

# Spike A-1 — Reuse Spike

## Objetivo

Não decidir integração com frameworks apenas olhando README.

Clonar para estudo:

```text
Tactical Slash
```

## Tactical Slash

Identificar módulos que podem ser transplantados com baixo acoplamento:

```text
camera
LoS
event visualization
turn UI
tests
```

## Saída

Criar:

```text
docs/third_party/reuse-audit.md
```

## Critério

Cada trecho reutilizado precisa ter:

```text
source repository
commit hash
license
files copied/adapted
local modifications
```

---

# Spike B-0 — Terrain runtime + navmesh

Pode ser feito cedo porque elimina um risco técnico, embora o restante do Map
Compiler só venha após Marco A.

## Teste

Gerar:

```text
64×64m heightmap
```

por noise.

Depois:

```text
heightmap
↓
TerrainProvider implementation
↓
terrain mesh
↓
navigation source geometry
↓
runtime navmesh bake
↓
path query
```

## Terrain3D branch

Testar Terrain3D.

## Fallback

Se a integração runtime/navmesh for problemática:

```text
CustomHeightmapTerrainProvider
```

usando:

```text
ArrayMesh
```

## Métrica

Registrar:

```text
terrain build ms
navigation parse ms
navigation bake ms
memory
```

Não transformar:

```text
< 2 seconds
```

em requisito rígido antes de medir em máquinas diferentes.

Meta inicial:

```text
interactive enough for authoring
```

e geração poderá ser assíncrona.

---

# Fase A0 — Fundação

**Status:** concluída.

## Repositório

- Git;
- Godot project;
- README;
- ADR directory;
- third-party notice directory.

## Physics

Godot 4.6:

```text
Jolt
```

como default para projetos novos.

Registrar explicitamente a escolha para evitar mudança silenciosa.

## Collision layers

```text
1 terrain
2 character
3 interactable
4 cover
5 trigger
6 projectile
```

## Tests

Escolher:

```text
GUT
```

ou runner equivalente.

Critério:

```text
headless in CI
```

## CI

Executar:

```text
unit
deterministic
integration-safe headless tests
```

a cada push.

## Arena

```text
64×64m
```

com:

- floor;
- cubes;
- walls;
- door placeholder;
- directional light.

## DoD

```text
clone
↓
open
↓
run test arena
↓
run tests
↓
green
```

---

# Fase A1 — Câmera e locomoção

**Status:** implementação concluída; smoke manual no editor pendente naquele
ambiente sem aplicação gráfica.

## Reuso

Antes de implementar do zero:

```text
inspect Tactical Slash camera
```

Se suficientemente isolada e adequada:

```text
adapt under MIT
```

Caso contrário:

```text
implement same architecture locally
```

## Camera

```text
CameraRig
└── Pivot
    └── Camera3D
```

Features:

- WASD pan;
- middle mouse pan;
- zoom;
- Q/E rotation;
- smooth interpolation.

## Character

```text
CharacterBody3D
NavigationAgent3D
CapsuleMesh
```

## Input

```text
LMB
↓
terrain raycast
↓
navigation target
```

## Debug

- clicked marker;
- path;
- destination;
- velocity;
- navmesh overlay.

## Important

Nesta fase o personagem ainda pode ser movido diretamente pelo prototype
controller.

Isso é proposital.

A Fase A2 substituirá isso por:

```text
Command → Event
```

Evitar tentar construir duas arquiteturas simultaneamente antes de validar
movimento.

## DoD

Movimento robusto com:

- repeated clicks;
- unreachable target;
- obstacle path;
- near target;
- path replacement.

---

# Fase A2 — Integração simulação ↔ apresentação

**Status:** implementação concluída — integração de movimento por
Command/Event, adapters Godot e testes headless implementados.

## Refatoração

Antes:

```text
Input
↓
CharacterController
↓
move
```

Depois:

```text
Input
↓
Command
↓
Resolver
↓
Events
↓
apply
↓
EventPlayer
↓
CharacterView
```

## Implementar

- [x] production BattleState;
- [x] ActorState;
- [x] Resolver;
- [x] ResolutionResult;
- [x] GodotNavProvider;
- [x] GodotLosProvider;
- [x] EventPlayer.

## Testes

### Purity

```text
hash(state before)
==
hash(state after resolve)
```

- [x] snapshot/hash before and after resolve are identical.

### Serialization

```text
state
↓
to_dict
↓
JSON
↓
from_dict
↓
same semantic state
```

- [x] BattleState, Command, ResolutionResult and Event JSON round-trips
  preserve semantic data.

### Navigation reject

Target completamente não navegável:

```text
command_rejected
```

- [x] non-navigable targets emit `command_rejected` without moving state or
  view.

## DoD

Visualmente A1 continua funcionando.

Arquiteturalmente nenhum clique move Node diretamente.

- [x] accepted movement reaches `CharacterView` through `EventPlayer`.
- [x] target replacement remains on the Command/Event path.

---

# Fase A3 — Regras de movimento

**Status:** implementação concluída — custo de movimento autoritativo por
polyline, clamp exato em combate e preview não mutável integrados ao fluxo
Command/Event.

## Movement budget

```text
movement_speed = 9m
movement_remaining
```

## Exploration

Ignorar budget.

## Combat

Aplicar budget.

## Clamp

Se path custa:

```text
12m
```

e personagem tem:

```text
7m
```

achar ponto no polyline correspondente a:

```text
7m cumulative distance
```

e mover até lá.

## Preview

Calcular antes de confirmar.

UI:

```text
path preview
movement consumed
remaining movement
```

Círculo de alcance pode existir apenas como aproximação visual.

O path real é autoritativo.

## Implementado

- [x] exploração ignora `movement_remaining`;
- [x] combate aplica `movement_remaining` e clamp no ponto exato da polyline;
- [x] eventos registram path, custo gasto e destino clampados;
- [x] preview resolve path/custo/restante sem aplicar `BattleState` ou mover a
  view;
- [x] playback e debug usam paths entregues por eventos, com sincronização
  final da posição autoritativa.

---

# Fase A4 — Turnos

**Status:** implementação concluída — iniciativa determinística, ciclo de
encontro e propriedade autoritativa dos turnos estão em `sim/`.

## Sistemas

Dentro de `sim/rules`:

```text
turn_order
encounter
initiative
```

Não criar um `TurnManager Node` autoritativo.

Pode haver:

```text
TurnUIController
```

na presentation.

## Implementado

- [x] estados `exploration`, `combat_starting`, `combat` e `combat_ending`;
- [x] ordem de iniciativa autoritativa por `initiative_order` e
  `current_turn_index`;
- [x] iniciativa `d20 + modificador de DEX`, com desempate por DEX e ID
  estável;
- [x] eventos explícitos para início/fim de combate, iniciativa e início de
  turno;
- [x] avanço de um ator elegível por vez, incremento de rodada no wrap e reset
  dos recursos por turno;
- [x] testes headless para iniciativa, ciclo de combate, restrições de ator
  atual, replay/pureza e preservação do movimento A3.

## States

```text
exploration
combat_starting
combat
combat_ending
```

O ator ativo vem de:

```text
BattleState.initiative_order
```

## Initiative

```text
d20 + DEX modifier
```

Empate:

1. DEX;
2. stable actor ID.

## DoD

Jogador e inimigo passivo alternam turnos.

---

# Fase A5 — Actions + Combat

Esta foi a maior fase do Marco A.

**Status:** implementação concluída — economia de ações, ataques básicos,
condições simplificadas e reações são resolvidos deterministicamente em
`sim/`.

## Economy

```text
action
bonus_action
reaction
movement
```

## Habilidades

### Basic Attack

```text
Action
```

### Dash

```text
Action
movement_remaining += movement_speed
```

### Disengage

```text
Action
disengaged = true for turn
```

### End Turn

```text
no cost
```

## Targeting

V1:

```text
single actor
ground point
```

## Attack resolution

```text
LoS
↓
range
↓
attack roll
↓
hit
↓
damage
↓
condition/death check
```

## Opportunity Attack

Threat range:

```text
1.5m
```

Quando o caminho sai da threat radius:

```text
if enemy.reaction_available
and not mover.disengaged
and enemy can see mover
and enemy alive:
    trigger reaction
```

## Important

Opportunity Attack não depende da animação.

Ele ocorre durante:

```text
Resolver.resolve(move_command)
```

sobre uma working copy.

## Conditions

### Prone

V1 simplificada:

- standing costs half base movement;
- melee attackers within 1.5m gain advantage;
- ranged attacks beyond close range have disadvantage.

### Poisoned

```text
disadvantage on attack rolls
```

Não implementar ability checks até existirem.

### Unconscious

- cannot act;
- prone semantic state;
- attacks at close range receive simplified advantage if desired.

### Dead

- removed from initiative/action eligibility.

## Implementado

- [x] economia de `action`, `bonus_action`, `reaction` e movimento por turno;
- [x] Basic Attack, Dash, Disengage e End Turn no pipeline Command/Event;
- [x] targeting por ator para ataque e por ponto no solo para movimento;
- [x] LoS, alcance, d20 determinístico, dano, downed e dead;
- [x] ataques de oportunidade no polyline resolvido, com reação, visibilidade,
  vida e Disengage autoritativos;
- [x] prone, poisoned, unconscious e dead, com testes headless de pureza,
  replay, comandos rejeitados e regressões A3/A4.

## DoD

Combate manual completo:

```text
movement
attack
dash
disengage
opportunity attack
death
end combat
```

---

# Fase A6 — Enemy AI

**Status:** implementação e cobertura headless adicionadas — utility AI
determinística, decisões incrementais por Command, simulação de candidatos
pelo Resolver puro e orçamento explícito de consultas especulativas de
navegação/LoS.

## AI does not manipulate Nodes

Entrada:

```text
BattleState snapshot
```

Saída:

```text
Command
```

## Utility architecture

```text
enumerate legal commands
        ↓
simulate candidate
        ↓
score resulting state
        ↓
choose command
```

## Critical correction

A IA não pode usar:

```text
GodotNavProvider
```

para milhares de speculative queries sem controle.

Criar:

```text
AIQueryBudget
```

e medir.

Inicialmente:

- gerar poucos candidatos;
- usar heurísticas;
- chamar pathfinding somente para destinos úteis.

## Initial scoring

Positive:

- expected damage;
- finishing enemy;
- reducing distance;
- retaining HP;
- preserving action economy.

Negative:

- surrounded;
- provoking opportunity attack;
- unreachable target;
- wasting action.

## Recurring decision loop

AI may return:

```text
move
```

then after events applied:

```text
choose next command
```

until:

```text
end_turn
```

Não precisa planejar o turno inteiro de uma vez.

## DoD

Enemy:

- approaches intelligently;
- attacks when legal;
- doesn't walk randomly;
- avoids obvious lethal choices;
- ends turn.

"Recua quando quase morrendo" é comportamento desejável, não Definition of
Done obrigatório.

---

# Fase A7 — Data-driven definitions

**Status:** implementação concluída — `AbilityDefinition`/`ConditionDefinition`
como Godot Resources (`.tres`) sob `data/abilities` e `data/conditions`,
indexados por `DefinitionLibrary`; Resolver executa efeitos genéricos
(`add_base_movement`, `apply_disengage`, `apply_condition`, `remove_condition`,
`perform_attack`) em vez de ramificar por id de habilidade/condição. Decisão
de formato registrada em `docs/ADR/ADR-004-data-driven-definitions.md`.

## Goal

Separar regra genérica de conteúdo.

## AbilityDefinition

Exemplo:

```yaml
id: dash

name: Dash

cost:
  action: 1

effects:
  - type: add_movement
    amount:
      expression: actor.movement_speed
```

## Avoid expression strings initially

Para v1, preferir tipos explícitos:

```yaml
effects:
  - type: add_base_movement
    multiplier: 1.0
```

em vez de construir uma linguagem de expressões prematuramente.

## ConditionDefinition

```yaml
id: poisoned

tags:
  - condition.poisoned

modifiers:
  attack_roll:
    disadvantage: true
```

## Implementado

- [x] `AbilityDefinition`/`AbilityEffect`/`ConditionDefinition` como Godot
  Resources (`sim/definitions/`), com id estável, custos explícitos
  (action/bonus_action/reaction/movement) e modificadores tipados;
- [x] `DefinitionLibrary` como fonte única de verdade, indexada por id,
  carregada de um manifesto fixo de `.tres` sob `data/abilities` e
  `data/conditions` (sem scan de diretório, determinístico);
- [x] Basic Attack, Dash, Disengage, Poisoned, Prone, Unconscious e Dead
  migrados como conteúdo de dados;
- [x] Resolver executa `effects` por tipo genérico (`add_base_movement`,
  `apply_disengage`, `apply_condition`, `remove_condition`, `perform_attack`)
  em vez de ramificar por id de habilidade; modificadores de condição
  (disadvantage, advantage, prone, unconscious, dead) lidos via
  `DefinitionLibrary` em vez de `conditions.has(&"poisoned")` literais;
- [x] `Resolver.resolve()` aceita um `DefinitionLibrary` opcional
  (default = biblioteca padrão), preservando todos os call sites A2-A6 sem
  alteração e permitindo testes com bibliotecas alternativas;
- [x] ids de habilidade/condição desconhecidos rejeitados deterministicamente
  (`command_rejected` com motivo `unknown_ability_definition`; ids de
  condição desconhecidos são ignorados de forma segura nos modificadores);
- [x] `BattleState.content_version` (default =
  `DefinitionLibrary.CONTENT_VERSION`) serializado em `to_dict`/`from_dict`,
  pronto para validação em A8;
- [x] testes headless novos (`unit/test_definitions`) e replay determinístico
  estendido (`deterministic/test_replay`) cobrindo dash/poisoned via dados,
  ids desconhecidos e paridade de hash/RNG; suíte completa A3-A7 verde.

---

# Fase A8 — Save / Load / Replay

**Status:** implementação concluída — `SaveGame` (snapshot autoritativo,
`sim/save_game.gd`) e `ReplayLog` (artefato de replay/debug,
`sim/replay_log.gd`) como classes puras em `sim/`, com `to_dict`/`from_dict`
reaproveitando `BattleState`/`Command`/`Event` e `SimulationSerialization` já
existentes de A2; `world/save_load_service.gd` isola toda a I/O de arquivo
(`FileAccess`/`DirAccess` sob `user://saves` e `user://replays`), mantendo
`sim/` livre de I/O. Também corrigido nesta fase um bug pré-existente em A6
(`ai/enemy_ai.gd`) que quebrava silenciosamente `EnemyAI` — a suíte
`unit/test_enemy_ai` reportava PASS mesmo com todo `EnemyAI.new()` falhando em
runtime.

## Snapshot save

Formato primário:

```text
schema_version
game_version
map_id
battle_state
world_state
```

## Replay/debug log

Separado:

```text
initial_snapshot
commands
optional event hashes
```

## Important correction

Não usar somente:

```text
seed + initial_state + command_log
```

como save normal.

Motivo:

- alterações futuras na resolução podem produzir outcomes diferentes;
- mods/version changes quebram replay;
- updates de balance quebram determinismo histórico.

Portanto:

```text
snapshot = authoritative save
command log = replay/debug artifact
```

Salvar também:

```text
rules_version
content_version
```

## Deterministic replay

Em desenvolvimento:

```text
Replay
↓
resolve commands again
↓
compare event hashes
```

Excelente detector de regressão.

## DoD

Save mid-combat restaura:

- HP;
- positions;
- turn;
- movement;
- action resources;
- conditions;
- reactions;
- RNG state;
- interactable state.

## Implementado

- [x] `SaveGame` como snapshot autoritativo (`schema_version`, `game_version`,
  `rules_version`, `content_version`, `map_id`, `battle_state`,
  `world_state`), serializado via `to_dict`/`from_dict` sobre o
  `BattleState.to_dict`/`from_dict` já existente de A2;
- [x] `world_state` reservado como campo de topo vazio, pronto para os
  estados de interactable de A9 sem quebra de schema;
- [x] `SaveGame.is_compatible()` valida `schema_version`, `rules_version`
  (`Resolver.RULES_VERSION`, novo) e `content_version`
  (`DefinitionLibrary.CONTENT_VERSION`) antes de confiar num save carregado;
- [x] `ReplayLog` como artefato de replay/debug separado (`initial_snapshot`,
  `commands`, `event_hashes`), com `append_command()` gravado a cada comando
  realmente resolvido durante o jogo e `find_divergences()` re-resolvendo a
  partir de um clone do snapshot inicial para comparar hashes — detector de
  regressão de resolver/conteúdo;
- [x] `world/save_load_service.gd` isola toda I/O (`FileAccess`/`DirAccess`
  sob `user://saves` e `user://replays`) fora de `sim/`, seguindo a mesma
  separação de `GodotNavProvider`/`GodotLosProvider`;
- [x] round-trip de save mid-combate cobre HP, posições, turno/rodada,
  movimento restante, recursos de ação/bônus/reação, condições, `disengaged`
  e `rng_state`, incluindo o caso de round-trip pelo disco via
  `SaveLoadService`;
- [x] testes headless novos (`unit/test_save_game`,
  `deterministic/test_replay_log`, `integration/test_save_load_service`).

---

# Fase A9 — Interactables

**Status:** parcialmente concluída — estado serializável, interação por
`Command → Event`, custo em combate, pickups, baús e barris estão em produção.
Portas/alavancas no mapa de envio, incluindo colisão/navegação dinâmica e
apresentação animada, permanecem adiadas (ver Fase D4.4 em
[marco-d-gameplay-depth.md](marco-d-gameplay-depth.md)).

## Contract

```text
InteractableState
```

precisa estar no world state serializável.

## V1

- door;
- chest;
- lever.

## Door navigation

Estrutura:

```text
Room NavigationRegion
     ↓
Door NavigationRegion
     ↓
Room NavigationRegion
```

Abrir:

```text
enable connector region
```

Fechar:

```text
disable connector region
```

ou:

```text
toggle navigation layer
```

## Collision

Door also changes:

```text
physics collision
cover collision
```

## Combat

Interaction cost:

```text
exploration → free
combat → action
```

---

# Fase A10 — Arte mínima

**Status:** concluída para o vertical slice — família visual KayKit, UI
Kenney, catálogo de assets e auditoria em `docs/third_party/assets.csv` estão
no repositório.

Apenas agora.

## Choose one visual family

Prefer:

```text
KayKit
```

or another cohesive source.

Supplement carefully with:

- Kenney;
- Quaternius;
- Poly Haven;
- ambientCG.

## Asset audit

Create:

```text
docs/third_party/assets.csv
```

Fields:

```text
asset
source
author
license
download_date
local_path
modified
```

## DoD — Marco A

Arena final:

- player;
- 2 enemies;
- obstacles;
- cover;
- chest;
- door;
- basic art.

Playable from:

```text
exploration
```

to:

```text
combat victory/defeat
```

with save/load.

---

# MARCO A CONCLUÍDO

Antes do Map Compiler:

```text
STOP
PLAY
PROFILE
WRITE ISSUES
REASSESS
```

Não carregar automaticamente as estimativas antigas para o próximo marco.

---

# Backlog detalhado — Semanas 1–2 (histórico)

## Semana 1 — arquitetura + validação de reuso

### Foundation

- [x] Create repository
- [x] Create Godot 4.6 project
- [x] Add project folders
- [x] Configure collision layers
- [x] Install test framework
- [x] CI headless
- [x] Create `test_arena.tscn`

### Spike A-0

- [x] `ActorState`
- [x] `BattleState`
- [x] `Command`
- [x] `Event`
- [x] `ResolutionResult`
- [x] `FakeNavProvider`
- [x] `FakeLosProvider`
- [x] `move`
- [x] `attack`
- [x] `end_turn`
- [x] deterministic RNG state
- [x] 1000 identical-seed replay checks

### Spike A-1

Clone/read:

- [x] Tactical Slash

Produce:

- [x] reuse audit (Tactical Slash; no source copied)
- [x] exact modules to copy/adapt (none qualified; local CameraRig retained)
- [x] exact licenses (Tactical Slash MIT)
- [x] commit hashes (Tactical Slash audit record)

### Terrain spike

- [x] Generate 64×64 heightfield
- [ ] Terrain3D runtime test
- [x] extract/provide nav geometry
- [x] runtime bake
- [x] path query
- [ ] benchmark
- [ ] document Terrain3D vs ArrayMesh decision

## Semana 2 — exploração tática

### Camera

- [x] Inspect Tactical Slash implementation
- [x] Adapt or implement CameraRig
- [x] WASD
- [x] middle-drag
- [x] zoom
- [x] rotation

### Navigation

- [x] NavigationRegion3D
- [x] NavigationMesh
- [x] obstacle geometry
- [x] NavigationAgent3D

### Character

- [x] capsule
- [x] click raycast
- [x] path follow
- [x] rotation
- [x] target replacement

### Debug

- [x] destination marker
- [x] path line
- [x] nav target
- [x] position/velocity overlay

### Tests

- [x] straight path
- [x] obstacle
- [x] unreachable point
- [x] repeated click
- [x] target replacement
- [x] click outside terrain
