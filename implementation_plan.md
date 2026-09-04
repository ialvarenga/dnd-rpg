# Plano Técnico — RPG Tático 3D em Godot

**Versão:** 3.0  
**Status:** plano revisado após avaliação arquitetural + estratégia de reutilização de código open source  
**Princípio condutor:** ter algo **jogável** antes de ter algo **inteligente** ou **bonito**.

---

# 0. Resumo executivo

Este projeto será construído em três produtos relativamente independentes:

1. **RPG Runtime**
   - movimento click-to-move;
   - câmera tática;
   - combate por turnos;
   - economia de ações;
   - ataques e condições;
   - IA;
   - interação;
   - save/load.

2. **Map Compiler**
   - recebe um `MapSpec`;
   - instancia terreno, vegetação, estruturas e spawns;
   - gera navegação;
   - valida se o mapa é jogável.

3. **AI World Authoring**
   - converte descrição em linguagem natural em `MapSpec`;
   - repara erros estruturados;
   - permite edição incremental via `MapPatch`.

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

A principal mudança em relação aos planos anteriores é que **não implementaremos do zero tudo que já existe no ecossistema Godot**.

A estratégia agora é:

> reutilizar código e padrões open source onde forem maduros, mas manter o estado e a resolução autoritativa do combate em um núcleo de simulação determinístico e testável.

---

# 1. Avaliação das alterações propostas

As alterações propostas fazem sentido em sua maioria.

## 1.1 Alterações aceitas

| Proposta | Decisão | Motivo |
|---|---|---|
| Núcleo puro `Command / Event / State` | **ACEITA** | Resolve testes, replay, save, IA e reações |
| `NavProvider` injetado | **ACEITA** | Mantém simulação independente da engine |
| `LosProvider` injetado | **ACEITA** | Mesma justificativa da navegação |
| IA como fase própria | **ACEITA** | Um inimigo que apenas caminha e ataca é um stub, não uma IA |
| Verticalidade cortada da v1 | **ACEITA** | Reduz drasticamente escopo |
| LoS simples incluída desde v1 | **ACEITA** | Targeting dependerá dela |
| Coordenadas absolutas em metros | **ACEITA** | Assets físicos não escalam com mapas |
| Limite de mapas em 256×256m | **ACEITA** | Evita streaming/chunking cedo demais |
| Schema com fonte única | **ACEITA** | Duas implementações manuais inevitavelmente divergem |
| Spike de simulação | **ACEITA** | Valida a arquitetura mais importante |
| Spike de terreno/navmesh runtime | **ACEITA** | Resolve risco do Map Compiler antes de depender dele |
| IA generativa após vertical slice | **ACEITA** | Protege o objetivo principal |

---

## 1.2 Alterações aceitas com correções

### GodotGAS

A estratégia de reutilizar GodotGAS é mantida, mas com uma restrição importante:

```text
GodotGAS NÃO é o BattleState autoritativo.
```

O projeto fornece uma arquitetura robusta para:

- attributes;
- gameplay tags;
- gameplay effects;
- ability definitions;
- effect stacking;
- cues;
- calculations.

Entretanto, seu `AbilitySystemComponent` é um componente do ecossistema Godot com sinais e lifecycle próprio.

O nosso núcleo:

```text
sim/
```

precisa continuar:

```text
sem Node
sem await
sem signals como mecanismo de regra
sem estado escondido em SceneTree
```

Portanto:

```text
                     OUR SIMULATION
                           │
                    BattleState
                    Resolver
                    Rules
                           │
              ┌────────────┴─────────────┐
              │                          │
              ▼                          ▼
      data definitions             view adapters
              │                          │
       GAS-like concepts               Godot
              │                          │
              └────────────┬─────────────┘
                           ▼
                        presentation
```

GodotGAS será inicialmente usado de duas maneiras:

1. **referência e fonte de padrões reutilizáveis**;
2. opcionalmente como **componente de apresentação/runtime não autoritativo**, depois de um spike de integração.

Não acoplaremos a arquitetura central do jogo ao plugin antes desse spike.

---

### RNG dentro de `BattleState`

A ideia de RNG serializado é correta, mas a implementação proposta tinha uma contradição:

```gdscript
resolve(state, command)
```

foi definida como pura e sem modificar `state`, enquanto:

```gdscript
RandomNumberGenerator
```

é um objeto cujo estado interno muda quando se rola um número.

A versão correta é:

```text
BattleState
    rng_seed
    rng_state
```

ou outra representação serializável equivalente.

`resolve()` trabalha com uma cópia local do RNG.

O avanço do RNG precisa aparecer no resultado da resolução.

Exemplo:

```text
resolve()
  ↓
local_rng seeded from BattleState.rng_state
  ↓
roll
  ↓
events
  ↓
rng_state_advanced
```

Alternativamente:

```gdscript
ResolutionResult:
    events
    next_rng_state
```

Neste plano usaremos preferencialmente:

```gdscript
class_name ResolutionResult
extends RefCounted

var events: Array[Event]
var next_rng_state: int
```

Assim:

```text
same state
+
same command
=
same events
+
same next_rng_state
```

sem mutação escondida.

---

### Reações durante movimento

A ideia está correta, mas:

```text
actor_moved → reaction → actor_moved
```

precisa representar **segmentos** do caminho.

O resolver deve simular internamente sobre uma cópia temporária:

```text
original BattleState
       ↓
working copy
       ↓
move segment A
       ↓
cross threat boundary
       ↓
opportunity attack
       ↓
target survives?
   yes ↓       no ↓
segment B      movement stops
```

Os eventos finais podem ser:

```text
movement_segment
reaction_triggered
attack_rolled
damage_taken
movement_segment
movement_spent
```

O estado externo continua sendo alterado somente por `apply()`.

---

### Ataque de oportunidade

Correção importante:

```text
Dash NÃO evita Opportunity Attack.
```

A ação que evita isso é:

```text
Disengage
```

Portanto a v1 terá:

- Basic Attack
- Dash
- Disengage
- End Turn

Se quisermos ficar mais próximos de D&D 5e:

```text
Dash       → Action
Disengage  → Action
```

O sistema de custos permitirá mudar isso posteriormente.

---

### Porta e navegação

`NavigationObstacle3D` é útil para avoidance e pode participar do **bake**, mas não deve ser tratado como um bloqueador dinâmico universal de pathfinding.

Para portas, a solução planejada será:

```text
Room nav region
      │
Door nav connector
      │
Room nav region
```

com uma pequena `NavigationRegion3D` no portal da porta.

Porta aberta:

```text
door region enabled
```

Porta fechada:

```text
door region disabled
```

ou controle via navigation layers.

Isso afeta queries futuras sem rebake do mapa inteiro.

---

# 2. Estratégia de reutilização open source

## 2.1 Regra geral

Não iremos:

```text
forkar um RPG inteiro
↓
apagar metade
↓
lutar contra decisões arquiteturais herdadas
```

Faremos:

```text
nosso projeto
├── núcleo autoritativo próprio
├── plugins permissivos
├── código adaptado de projetos MIT
└── padrões estudados de projetos similares
```

---

# 3. Projetos de referência e uso planejado

## 3.1 GodotGAS

Repositório:

```text
https://github.com/yulrun/godot-gas
```

Licença:

```text
MIT
```

Alvo:

```text
Godot 4.6+
```

Usar como referência ou reutilizar componentes para:

- attribute definitions;
- gameplay tags;
- gameplay effects;
- effect contexts;
- stacking;
- ability metadata;
- cues;
- editor tooling.

### Não delegar inicialmente

- BattleState autoritativo;
- iniciativa;
- movimento tático;
- resolução determinística;
- reaction sequencing;
- save/replay;
- enemy simulation.

---

## 3.2 Tactical Slash

Repositório:

```text
https://github.com/sion-rgb/tactical-slash
```

Licença:

```text
MIT
```

Características úteis:

- Godot 4.7;
- typed GDScript;
- câmera 3D tática;
- turn flow;
- attack/heal/projectile patterns;
- LoS;
- enemy AI;
- testes;
- separação entre lógica e representação.

### Usar como donor/reference para

```text
CameraRig
UI patterns
projectile/view animation
turn UI
LoS concepts
test organization
enemy controller ideas
```

### Não copiar

```text
grid-based movement model
```

porque nosso jogo usa NavigationMesh contínua.

---

## 3.3 Six Worlds

Repositório:

```text
https://github.com/olstach/six_worlds
```

Código:

```text
MIT
```

Conteúdo/assets:

```text
CC BY-NC-SA 4.0
```

Usar como referência para:

- iniciativa;
- action economy;
- status effects;
- AI;
- data-driven abilities;
- save systems;
- combat organization.

Não copiar conteúdo temático ou assets para um produto comercial.

---

## 3.4 Terrain3D

Repositório:

```text
https://github.com/TokisanGames/Terrain3D
```

Licença:

```text
MIT
```

Usar somente se o Spike de runtime comprovar que atende ao pipeline.

Não tornar o `MapSpec` dependente de Terrain3D.

Contrato:

```text
TerrainProvider
```

deve permitir trocar:

```text
Terrain3D
```

por:

```text
custom ArrayMesh
```

sem mudar MapSpec.

---

# 4. Objetivo

Construir um RPG tático 3D em Godot com mecânicas inspiradas em Baldur's Gate 3 e D&D 5e, **sem tentar reproduzir fidelidade gráfica de BG3**.

---

# 5. Definição do Marco A — Jogável

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

Nenhuma IA generativa.

Nenhum MapSpec.

Nenhum mapa procedural.

---

# 6. Decisões arquiteturais travadas

## 6.1 Engine

```text
Godot 4.6+
```

Novos projetos em Godot 4.6 usam Jolt como engine de física 3D por padrão.

---

## 6.2 Linguagem

```text
GDScript
```

C# apenas se surgir um gargalo medido.

---

## 6.3 Unidade física

```text
1 Godot unit = 1 meter
```

Movimento D&D-like:

```text
30 ft ≈ 9 m
```

---

## 6.4 Movimento

```text
NavigationMesh
+
NavigationServer3D
+
movimento contínuo
```

Sem grid visível.

---

## 6.5 Verticalidade

### V1

Não teremos:

- múltiplos pavimentos conectados;
- jump traversal;
- ladders;
- cliffs;
- knockback para quedas;
- `NavigationLink3D` como mecânica;
- diferença de altura como regra de combate.

Permitido:

```text
colinas suaves
```

O terreno continua sendo uma superfície navegável contínua.

---

## 6.6 Linha de visão

V1:

```text
raycast
chest → chest
```

Layer:

```text
4: cover
```

Resultado:

```text
visible
not_visible
```

Sem meia cobertura.

Sem três quartos de cobertura.

Vegetação decorativa não entra na layer de cover.

---

## 6.7 Tamanhos

| Preset | Dimensões | Uso |
|---|---:|---|
| encounter | 64 × 64m | combate |
| small | 128 × 128m | ruína/acampamento |
| medium | 256 × 256m | vila/floresta |

Nenhum preset maior até existir necessidade real.

---

## 6.8 Coordenadas

MapSpec usa:

```text
metros absolutos
```

Origem:

```text
southwest corner
```

Exemplo:

```yaml
position: [84, 42]
```

significa:

```text
84m east
42m north
```

---

## 6.9 Âncoras semânticas

Para layouts relativos:

```yaml
position:
  anchor: north_edge
  offset: [-10, 25]
```

Outras:

```text
center
north_edge
south_edge
east_edge
west_edge
region:<id>
structure:<id>
```

O compilador resolve isso em metros.

---

# 7. Escopo D&D-like da V1

## Atributos

- STR / FOR
- DEX / DES
- CON
- INT
- WIS / SAB
- CHA / CAR

---

## Derivados

- Armor Class;
- HP;
- movement speed;
- proficiency bonus.

---

## Ataques

```text
d20
+
ability modifier
+
proficiency
vs
Armor Class
```

---

## Crítico

Natural:

```text
20
```

---

## Dano

```text
dice
+
modifier
```

Um damage type é suficiente inicialmente.

---

## Advantage / Disadvantage

```text
2d20 keep high
2d20 keep low
```

---

## Action economy

```text
Action
Bonus Action
Reaction
Movement
```

Reaction existe desde o modelo inicial.

V1 implementa:

```text
Opportunity Attack
```

---

## Condições

- prone;
- poisoned;
- unconscious;
- dead.

---

## Fora da V1

- spellcasting;
- spell slots;
- saving throws;
- classes;
- levels;
- equipment system;
- rests;
- concentration;
- multiclassing;
- full 5e compatibility.

---

# 8. Arquitetura central

```text
┌──────────────────────────────────────────────┐
│ PRESENTATION                                 │
│ Godot Nodes                                  │
│                                              │
│ Camera · UI · Animation · VFX · Input        │
│                                              │
│ Never decides combat rules.                  │
└────────────────┬─────────────────────────────┘
                 │ Command ↓       ↑ Events
┌────────────────┴─────────────────────────────┐
│ PURE SIMULATION                              │
│                                              │
│ BattleState                                  │
│ Resolver                                     │
│ Rules                                        │
│ Dice                                         │
│                                              │
│ No Node                                      │
│ No await                                     │
│ No global RNG                                │
└────────────────┬─────────────────────────────┘
                 │ ports
┌────────────────┴─────────────────────────────┐
│ WORLD SERVICES                               │
│                                              │
│ NavProvider                                  │
│ LosProvider                                  │
│ future TerrainQueryProvider                  │
│                                              │
│ Implemented through Godot engine APIs        │
└──────────────────────────────────────────────┘
```

---

# 9. Invariantes de arquitetura

Arquivos dentro de:

```text
sim/
```

não podem:

```text
extend Node
call await
emit engine signals as rule flow
query NavigationServer3D directly
query PhysicsServer3D directly
read Input
read SceneTree
use global random functions
```

Eles podem usar value types do Godot:

```text
Vector3
StringName
PackedVector3Array
Dictionary
Array
```

---

# 10. Command

```gdscript
class_name Command
extends RefCounted

var type: StringName

var actor_id: int
var target_id: int = -1
var target_pos: Vector3 = Vector3.ZERO

var metadata: Dictionary = {}
```

Tipos V1:

```text
move
attack
dash
disengage
end_turn
interact
```

---

# 11. Event

```gdscript
class_name Event
extends RefCounted

var type: StringName
var data: Dictionary
```

Vocabulário inicial:

```text
combat_started
combat_ended

turn_started
turn_ended

movement_segment
movement_spent

attack_rolled
damage_taken

reaction_triggered

condition_added
condition_removed

actor_downed
actor_died

interaction_completed

command_rejected
```

---

# 12. BattleState

```gdscript
class_name BattleState
extends RefCounted

var actors: Dictionary = {}

var initiative_order: Array[int] = []
var current_turn_index: int = 0
var round_number: int = 1

var phase: StringName = &"exploration"

var rng_seed: int
var rng_state: int

var world_flags: Dictionary = {}
```

---

# 13. ActorState

Exemplo:

```gdscript
class_name ActorState
extends RefCounted

var id: int
var side: StringName

var position: Vector3

var hp: int
var max_hp: int
var armor_class: int

var strength: int
var dexterity: int
var constitution: int
var intelligence: int
var wisdom: int
var charisma: int

var proficiency_bonus: int

var movement_speed: float
var movement_remaining: float

var action_available: bool
var bonus_action_available: bool
var reaction_available: bool

var conditions: Array[StringName]

var disengaged: bool
```

---

# 14. Resolução determinística

## 14.1 Resultado

```gdscript
class_name ResolutionResult
extends RefCounted

var events: Array[Event] = []
var next_rng_state: int
```

---

## 14.2 Resolver

```gdscript
class_name Resolver

static func resolve(
    state: BattleState,
    cmd: Command,
    nav: NavProvider,
    los: LosProvider
) -> ResolutionResult:
    ...
```

Garantia:

```text
same state
+
same command
+
same providers
=
same result
```

---

# 15. Apply

```gdscript
static func apply(
    state: BattleState,
    event: Event
) -> void:
    ...
```

Após os eventos:

```gdscript
state.rng_state = result.next_rng_state
```

Também é aceitável representar essa mudança como evento interno.

---

# 16. Resolução de reação no meio de movimento

Resolver trabalha com:

```text
temporary cloned BattleState
```

Fluxo:

```text
path
↓
split at reaction boundaries
↓
emit movement segment
↓
simulate segment
↓
check reactions
↓
resolve reaction
↓
apply internally to working state
↓
continue only if legal
```

Isso permite:

```text
enemy opportunity attack kills moving actor
```

e o segundo segmento simplesmente não existe.

---

# 17. NavProvider

```gdscript
class_name NavProvider
extends RefCounted

func find_path(
    from: Vector3,
    to: Vector3
) -> PackedVector3Array:
    push_error("abstract")
    return PackedVector3Array()


func path_cost(
    path: PackedVector3Array
) -> float:
    push_error("abstract")
    return INF


func is_reachable(
    from: Vector3,
    to: Vector3
) -> bool:
    return false


func snap_to_navmesh(
    pos: Vector3
) -> Vector3:
    return pos
```

Implementações:

```text
GodotNavProvider
FakeNavProvider
```

---

# 18. LosProvider

```gdscript
class_name LosProvider
extends RefCounted

func has_line_of_sight(
    from: Vector3,
    to: Vector3
) -> bool:
    push_error("abstract")
    return false
```

Implementações:

```text
GodotLosProvider
FakeLosProvider
```

---

# 19. EventPlayer

Toda animação assíncrona fica fora da simulação.

```gdscript
class_name EventPlayer
extends Node

var queue: Array[Event] = []
var playing := false


func enqueue(events: Array[Event]) -> void:
    queue.append_array(events)

    if not playing:
        _play()


func _play() -> void:
    playing = true

    while not queue.is_empty():

        var event := queue.pop_front()

        match event.type:

            &"movement_segment":
                await _animate_move(event)

            &"attack_rolled":
                await _animate_attack(event)

            &"damage_taken":
                await _animate_damage(event)

    playing = false
```

Regra:

```text
animation narrates state
```

não:

```text
animation controls state
```

---

# 20. Adaptação para GodotGAS

GodotGAS será avaliado no:

```text
Reuse Spike
```

antes de se tornar dependência estrutural.

Queremos descobrir:

1. quais partes funcionam como Resources/pure-ish definitions;
2. quais exigem `AbilitySystemComponent`;
3. se GameplayEffects podem ser usados apenas como definição;
4. se converter GAS effect → simulation event é simples;
5. se o plugin pode continuar atualizado sem quebrar save/replay.

Possível adapter:

```text
GameplayAbility Resource
       ↓
AbilityDefinitionAdapter
       ↓
SimAbilityDefinition
       ↓
Resolver
```

ou:

```text
our YAML/resource
       ↓
simulation
       ↓
GodotGAS only for view/effects
```

A decisão será orientada pelo código, não pelo desejo de usar um framework.

---

# 21. Estrutura de repositório

```text
project/
│
├── godot/
│   ├── project.godot
│   │
│   ├── addons/
│   │   └── GodotGAS/          # apenas se aprovado no Reuse Spike
│   │
│   ├── sim/
│   │   ├── command.gd
│   │   ├── event.gd
│   │   ├── resolution_result.gd
│   │   ├── battle_state.gd
│   │   ├── actor_state.gd
│   │   ├── resolver.gd
│   │   ├── dice.gd
│   │   │
│   │   ├── rules/
│   │   │   ├── movement.gd
│   │   │   ├── actions.gd
│   │   │   ├── attacks.gd
│   │   │   ├── reactions.gd
│   │   │   ├── conditions.gd
│   │   │   └── turn_order.gd
│   │   │
│   │   └── ports/
│   │       ├── nav_provider.gd
│   │       └── los_provider.gd
│   │
│   ├── ai/
│   │   ├── enemy_brain.gd
│   │   ├── command_enumerator.gd
│   │   └── scorers/
│   │
│   ├── view/
│   │   ├── event_player.gd
│   │   ├── camera/
│   │   ├── characters/
│   │   ├── targeting/
│   │   ├── ui/
│   │   └── debug/
│   │
│   ├── world/
│   │   ├── godot_nav_provider.gd
│   │   ├── godot_los_provider.gd
│   │   │
│   │   ├── interactables/
│   │   │
│   │   ├── navigation/
│   │   │
│   │   ├── terrain/
│   │   │
│   │   └── compiler/
│   │
│   ├── data/
│   │   ├── actors/
│   │   ├── abilities/
│   │   └── conditions/
│   │
│   ├── assets/
│   ├── scenes/
│   │
│   └── tests/
│       ├── unit/
│       ├── integration/
│       ├── deterministic/
│       └── fakes/
│
├── world_authoring/
│   ├── schema/
│   ├── validation/
│   ├── agents/
│   └── tests/
│
├── spikes/
│
└── docs/
    ├── architecture/
    ├── ADR/
    └── third_party/
```

---

# 22. Registro de decisões — ADR

Decisões importantes devem virar:

```text
docs/ADR/
```

Exemplos:

```text
ADR-001-pure-simulation.md
ADR-002-navigation-mesh.md
ADR-003-no-verticality-v1.md
ADR-004-map-coordinates-meters.md
ADR-005-godotgas-integration.md
ADR-006-terrain-provider.md
```

Isso evita revisitar decisões sem lembrar por que foram tomadas.

---

# MARCO A — RPG JOGÁVEL

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

---

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

---

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

---

## Testes adicionais

```text
state clone
does not mutate original

resolve
does not mutate original

apply
only changes fields represented by event
```

---

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
GodotGAS
Tactical Slash
Six Worlds
```

---

## GodotGAS

Responder:

- ASC é obrigatório para quais funcionalidades?
- Effects podem funcionar como definitions?
- Tags podem ser reutilizadas?
- ExecCalcs podem ser adaptadas para pure sim?
- plugin cria hidden state que atrapalha replay?
- data/resources são serializáveis de forma estável?

---

## Tactical Slash

Identificar módulos que podem ser transplantados com baixo acoplamento:

```text
camera
LoS
event visualization
turn UI
tests
```

---

## Six Worlds

Identificar padrões:

```text
data format
initiative
AI
conditions
save
```

---

## Saída

Criar:

```text
docs/ADR/ADR-005-godotgas-integration.md
docs/third_party/reuse-audit.md
```

---

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

Pode ser feito cedo porque elimina um risco técnico, embora o restante do Map Compiler só venha após Marco A.

---

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

---

## Terrain3D branch

Testar Terrain3D.

---

## Fallback

Se a integração runtime/navmesh for problemática:

```text
CustomHeightmapTerrainProvider
```

usando:

```text
ArrayMesh
```

---

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

---

## Physics

Godot 4.6:

```text
Jolt
```

como default para projetos novos.

Registrar explicitamente a escolha para evitar mudança silenciosa.

---

## Collision layers

```text
1 terrain
2 character
3 interactable
4 cover
5 trigger
6 projectile
```

---

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

---

## CI

Executar:

```text
unit
deterministic
integration-safe headless tests
```

a cada push.

---

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

---

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

**Status:** implementação concluída; smoke manual no editor pendente neste ambiente sem aplicação gráfica.

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

---

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

---

## Character

```text
CharacterBody3D
NavigationAgent3D
CapsuleMesh
```

---

## Input

```text
LMB
↓
terrain raycast
↓
navigation target
```

---

## Debug

- clicked marker;
- path;
- destination;
- velocity;
- navmesh overlay.

---

## Important

Nesta fase o personagem ainda pode ser movido diretamente pelo prototype controller.

Isso é proposital.

A Fase A2 substituirá isso por:

```text
Command → Event
```

Evitar tentar construir duas arquiteturas simultaneamente antes de validar movimento.

---

## DoD

Movimento robusto com:

- repeated clicks;
- unreachable target;
- obstacle path;
- near target;
- path replacement.

---

# Fase A2 — Integração simulação ↔ apresentação

**Status:** implementação concluída — integração de movimento por Command/Event, adapters Godot e testes headless implementados; a validação requer Godot 4.6.x.

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

---

## Implementar

- [x] production BattleState;
- [x] ActorState;
- [x] Resolver;
- [x] ResolutionResult;
- [x] GodotNavProvider;
- [x] GodotLosProvider;
- [x] EventPlayer.

---

## Testes

### Purity

```text
hash(state before)
==
hash(state after resolve)
```

- [x] snapshot/hash before and after resolve are identical.

---

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

- [x] BattleState, Command, ResolutionResult and Event JSON round-trips preserve semantic data.

---

### Navigation reject

Target completamente não navegável:

```text
command_rejected
```

- [x] non-navigable targets emit `command_rejected` without moving state or view.

---

## DoD

Visualmente A1 continua funcionando.

Arquiteturalmente nenhum clique move Node diretamente.

- [x] accepted movement reaches `CharacterView` through `EventPlayer`.
- [x] target replacement remains on the Command/Event path.

---

# Fase A3 — Regras de movimento

**Status:** implementação concluída — custo de movimento autoritativo por
polyline, clamp exato em combate e preview não mutável integrados ao fluxo
Command/Event; a validação requer Godot 4.6.x.

## Movement budget

```text
movement_speed = 9m
movement_remaining
```

---

## Exploration

Ignorar budget.

---

## Combat

Aplicar budget.

---

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

---

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
- [x] preview resolve path/custo/restante sem aplicar `BattleState` ou mover a view;
- [x] playback e debug usam paths entregues por eventos, com sincronização final
  da posição autoritativa.

---

# Fase A4 — Turnos

**Status:** implementação concluída — iniciativa determinística, ciclo de
encontro e propriedade autoritativa dos turnos estão em `sim/`; a validação
requer Godot 4.6.x.

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

---

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

---

## Initiative

```text
d20 + DEX modifier
```

Empate:

1. DEX;
2. stable actor ID.

---

## DoD

Jogador e inimigo passivo alternam turnos.

---

# Fase A5 — Actions + Combat

Esta é a maior fase do Marco A.

**Status:** implementação concluída — economia de ações, ataques básicos,
condições simplificadas e reações são resolvidos deterministicamente em
`sim/`; a validação requer Godot 4.6.x.

---

## Economy

```text
action
bonus_action
reaction
movement
```

---

## Habilidades

### Basic Attack

```text
Action
```

---

### Dash

```text
Action
movement_remaining += movement_speed
```

---

### Disengage

```text
Action
disengaged = true for turn
```

---

### End Turn

```text
no cost
```

---

## Targeting

V1:

```text
single actor
ground point
```

---

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

---

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

---

## Important

Opportunity Attack não depende da animação.

Ele ocorre durante:

```text
Resolver.resolve(move_command)
```

sobre uma working copy.

---

## Conditions

### Prone

V1 simplificada:

- standing costs half base movement;
- melee attackers within 1.5m gain advantage;
- ranged attacks beyond close range have disadvantage.

---

### Poisoned

```text
disadvantage on attack rolls
```

Não implementar ability checks até existirem.

---

### Unconscious

- cannot act;
- prone semantic state;
- attacks at close range receive simplified advantage if desired.

---

### Dead

- removed from initiative/action eligibility.

---

## Implementado

- [x] economia de `action`, `bonus_action`, `reaction` e movimento por turno;
- [x] Basic Attack, Dash, Disengage e End Turn no pipeline Command/Event;
- [x] targeting por ator para ataque e por ponto no solo para movimento;
- [x] LoS, alcance, d20 determinístico, dano, downed e dead;
- [x] ataques de oportunidade no polyline resolvido, com reação, visibilidade,
  vida e Disengage autoritativos;
- [x] prone, poisoned, unconscious e dead, com testes headless de pureza,
  replay, comandos rejeitados e regressões A3/A4.

---

## GodotGAS decision point

Ao final de A5, decidir se:

```text
ability/effect definitions
```

serão:

- nossas Resources/YAML;
- GodotGAS Resources via adapter;
- híbrido.

Não usar dois sistemas de definitions permanentemente.

---

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

## AI does not manipulate Nodes

Entrada:

```text
BattleState snapshot
```

Saída:

```text
Command
```

---

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

---

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

---

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

---

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

---

## DoD

Enemy:

- approaches intelligently;
- attacks when legal;
- doesn't walk randomly;
- avoids obvious lethal choices;
- ends turn.

"Recua quando quase morrendo" é comportamento desejável, não Definition of Done obrigatório.

---

# Fase A7 — Data-driven definitions

## Goal

Separar regra genérica de conteúdo.

---

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

---

## Avoid expression strings initially

Para v1, preferir tipos explícitos:

```yaml
effects:
  - type: add_base_movement
    multiplier: 1.0
```

em vez de construir uma linguagem de expressões prematuramente.

---

## ConditionDefinition

```yaml
id: poisoned

tags:
  - condition.poisoned

modifiers:
  attack_roll:
    disadvantage: true
```

---

# Fase A8 — Save / Load / Replay

## Snapshot save

Formato primário:

```text
schema_version
game_version
map_id
battle_state
world_state
```

---

## Replay/debug log

Separado:

```text
initial_snapshot
commands
optional event hashes
```

---

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

---

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

---

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

---

# Fase A9 — Interactables

## Contract

```text
InteractableState
```

precisa estar no world state serializável.

---

## V1

- door;
- chest;
- lever.

---

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

---

## Collision

Door also changes:

```text
physics collision
cover collision
```

---

## Combat

Interaction cost:

```text
exploration → free
combat → action
```

---

# Fase A10 — Arte mínima

Apenas agora.

---

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

---

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

---

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

# MARCO B — MAP COMPILER

---

# Fase B1 — Asset Catalog

Todo objeto reutilizável:

```yaml
id: oak_tree_01
scene: res://assets/vegetation/oak_tree_01.tscn

type: vegetation

tags:
  - tree
  - temperate

footprint:
  radius: 2.1

placement:
  max_slope_deg: 27
```

---

## Compiler never accepts

```text
raw res:// path
```

from a MapSpec.

Only:

```text
asset ID
```

---

# Fase B2 — Schema source of truth

Escolha definitiva:

```text
JSON Schema
```

como contrato canônico.

Motivo:

- language-neutral;
- Python can validate;
- docs can be generated;
- structured-output systems can consume it;
- Godot may receive already validated JSON.

Canonical files:

```text
world_authoring/schema/map_spec.schema.json
world_authoring/schema/map_patch.schema.json
```

---

## Python

Use:

```text
jsonschema
```

and optionally generated Pydantic models.

Pydantic:

```text
generated or aligned from the schema
```

Não manter manualmente duas definições.

---

## Godot

Map Compiler:

```text
expects validated MapSpec
```

mas ainda executa sanity checks críticos:

- unknown asset;
- impossible enum;
- missing required object.

Falhar alto em desenvolvimento.

---

# Fase B3 — MapSpec v1

Handwritten first.

Scope:

```text
map
terrain
regions
vegetation
structures
spawn_points
```

---

## Example

```yaml
version: 1

map:
  id: forest_test
  preset: encounter
  width_m: 64
  height_m: 64
  seed: 918273

terrain:
  profile: rolling_hills

regions:

  - id: north_forest

    polygon:
      - [0, 32]
      - [64, 32]
      - [64, 64]
      - [0, 64]

    vegetation:
      profile: temperate_dense

structures:

  - id: cabin
    asset: medieval_house_01
    position: [34, 24]

spawn_points:

  - id: player_start
    position: [12, 8]
```

---

# Fase B4 — TerrainProvider

Define interface conceptual:

```text
TerrainProvider
```

Operations:

```text
generate(profile, seed, bounds)
height_at(x,z)
normal_at(x,z)
slope_at(x,z)
export_navigation_geometry()
```

Implementations:

```text
Terrain3DProvider
CustomArrayMeshTerrainProvider
```

O spike decide qual será produção inicialmente.

---

# Fase B5 — Procedural terrain

Profiles:

- flat;
- rolling_hills;
- valley.

Input:

```text
profile
seed
parameters
```

Output:

```text
heightfield
```

LLM nunca gera heightmap individual.

---

# Fase B6 — VegetationGenerator

Flow:

```text
region polygon
↓
Poisson / blue-noise sampling
↓
candidate point
↓
slope
↓
clearances
↓
height query
↓
asset selection
↓
MultiMesh
```

---

## Determinism

Every generator receives derived seed:

```text
map_seed
+
region_id
+
generator_version
```

Use stable hash.

---

# Fase B7 — Structures

```text
asset catalog
↓
PackedScene
↓
instantiate
↓
position
rotation
```

Before placement:

- footprint test;
- terrain slope;
- bounds;
- collision with reserved areas.

---

# Fase B8 — Rivers + Roads

Only after basic compiler works.

---

## Rivers

```text
semantic control points
↓
spline
↓
terrain deformation
↓
water
↓
vegetation exclusion
```

No hydraulic simulation.

---

## Roads

```text
control points
or
semantic from/to anchors
↓
path planning
↓
spline
↓
terrain flattening
↓
material
```

---

# Fase B9 — Navigation compilation

Map complete:

```text
terrain
structures
bridges
walls
roads
```

then:

```text
navigation source geometry
↓
bake
↓
regions
```

---

## Chunk strategy

Only if necessary.

For medium:

```text
256 × 256m
```

candidate:

```text
64 × 64m navigation regions
```

But do not implement chunking blindly if one bake is fast enough.

Measure first.

---

# Fase B10 — Validation

Single validation pipeline.

---

## Schema

Examples:

- malformed IDs;
- invalid enum;
- missing field;
- unknown asset.

---

## Spatial

Examples:

- building outside map;
- overlap;
- invalid river crossing;
- spawn inside structure;
- impossible slope.

---

## Gameplay

Examples:

```text
spawn → objective reachable?
spawn → encounter reachable?
required door state solvable?
```

---

## Structured error

```json
{
  "code": "NAV_UNREACHABLE",
  "entity": "village",
  "context": {
    "from": "player_start"
  },
  "message": "Village is unreachable from player_start."
}
```

---

# MARCO B CONCLUÍDO

Manual:

```text
MapSpec
↓
validate
↓
compile
↓
play
```

must work reliably.

---

# MARCO C — AI WORLD AUTHORING

---

# Fase C1 — Natural language → MapSpec

Input:

```text
Quero uma floresta densa no norte...
```

Agent context:

- JSON Schema;
- Asset Catalog;
- terrain profiles;
- vegetation profiles;
- map bounds;
- generator capabilities.

Output:

```text
structured MapSpec
```

No prose parsing.

---

# Fase C2 — Validation repair

```text
MapSpec
↓
validator
↓
structured errors
↓
repair model
↓
MapPatch
↓
validation
```

Limit:

```text
3 iterations
```

Then return errors.

---

# Fase C3 — Conversational MapPatch

Operations:

```text
ADD
REMOVE
MOVE
ROTATE
RESIZE
CHANGE_DENSITY
CHANGE_PROFILE
```

MapPatch is preferred over full regeneration.

---

# Fase C4 — Versioning

Map identity:

```text
map_spec_version
asset_catalog_version
generator_version
seed
```

Generation must be reproducible within the same version set.

---

# 23. Testing strategy

## Pure unit tests

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

---

## Property tests

Examples:

```text
HP never below expected bounds
movement_remaining never negative
dead actor cannot act
action cannot be spent twice
```

---

## Determinism tests

```text
same state + same command
→
same result hash
```

---

## Integration tests

Godot headless with:

- navigation;
- LoS physics;
- door nav region;
- serialization.

---

## Golden replay tests

Keep a few known command logs:

```text
replays/golden/
```

CI verifies generated event hashes.

---

# 24. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Pure sim accidentally coupled to Node | Critical | CI architecture test + code review |
| GodotGAS conflicts with pure sim | High | Reuse Spike + adapter boundary |
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

---

# 25. Dependency policy

Every external dependency needs:

```text
name
repo
license
commit/tag
why used
update strategy
```

File:

```text
docs/third_party/DEPENDENCIES.md
```

---

## Pin versions

Do not track:

```text
main
```

in production.

Prefer:

```text
release tag
```

or:

```text
commit hash
```

---

# 26. Immediate backlog — First two weeks

# Week 1 — architecture + reuse validation

## Foundation

- [x] Create repository
- [x] Create Godot 4.6 project
- [x] Add project folders
- [x] Configure collision layers
- [x] Install test framework
- [x] CI headless
- [x] Create `test_arena.tscn`

---

## Spike A-0

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

---

## Spike A-1

Clone/read:

- [ ] GodotGAS
- [ ] Tactical Slash
- [ ] Six Worlds

Produce:

- [ ] reuse audit
- [ ] GodotGAS ADR
- [ ] exact modules to copy/adapt
- [ ] exact licenses
- [ ] commit hashes

---

## Terrain spike

- [ ] Generate 64×64 heightfield
- [ ] Terrain3D runtime test
- [ ] extract/provide nav geometry
- [ ] runtime bake
- [ ] path query
- [ ] benchmark
- [ ] document Terrain3D vs ArrayMesh decision

---

# Week 2 — tactical exploration

## Camera

- [x] Inspect Tactical Slash implementation
- [x] Adapt or implement CameraRig
- [x] WASD
- [x] middle-drag
- [x] zoom
- [x] rotation

---

## Navigation

- [x] NavigationRegion3D
- [x] NavigationMesh
- [x] obstacle geometry
- [x] NavigationAgent3D

---

## Character

- [x] capsule
- [x] click raycast
- [x] path follow
- [x] rotation
- [x] target replacement

---

## Debug

- [x] destination marker
- [x] path line
- [x] nav target
- [x] position/velocity overlay

---

## Tests

- [x] straight path
- [x] obstacle
- [x] unreachable point
- [x] repeated click
- [x] target replacement
- [x] click outside terrain

---

# 27. Roadmap resumido

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
  PLAYABLE RPG
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
===================
    MARCO B
  MAP COMPILER
===================
      ↓
C1 NL → MapSpec
      ↓
C2 Repair
      ↓
C3 MapPatch
      ↓
C4 Versioning
      ↓
===================
    MARCO C
 AI AUTHORING
===================
```

---

# 28. O que explicitamente NÃO fazer agora

Não implementar:

- full D&D rules;
- spells;
- classes;
- character creator;
- multiplayer;
- dialogue cinematics;
- procedural buildings;
- huge maps;
- world streaming;
- AI-generated meshes;
- vertical combat;
- partial cover;
- complex inventory;
- crafting;
- quest generator;
- LLM integration;
- realistic terrain erosion.

---

# 29. Critérios para reutilizar código

Código externo deve passar em quatro filtros.

## 29.1 License

Preferência:

```text
MIT
BSD
Apache-2.0
CC0 for assets
```

---

## 29.2 Coupling

Bom:

```text
isolated CameraRig
utility function
Resource definitions
pure algorithms
```

Ruim:

```text
autoload with entire game state
large inherited scene tree
global singleton dependency chain
```

---

## 29.3 Architectural fit

Não importar um módulo se ele exigir abandonar:

```text
Command / Event / State
```

sem benefício comprovado.

---

## 29.4 Maintenance cost

Pergunta obrigatória:

> É mais barato manter esta dependência pelos próximos dois anos do que manter 300 linhas nossas?

Se não:

```text
copy/adapt small MIT code
```

pode ser melhor que:

```text
plugin dependency
```

---

# 30. Estratégia final de reutilização

A expectativa atual é:

```text
Tactical Slash
    ↓
camera + view/testing patterns

Six Worlds
    ↓
combat/data/AI reference

GodotGAS
    ↓
ability/effect/tag concepts
    ↓
possible adapter after spike

Godot Native Navigation
    ↓
continuous movement/pathfinding

Terrain3D
    ↓
candidate terrain backend

OUR CODE
    ↓
authoritative BattleState
Resolver
D&D-like rules
continuous movement budget
reactions
AI command layer
MapSpec
Map Compiler
AI authoring
```

---

# 31. Por que manter o núcleo próprio mesmo reutilizando frameworks

O diferencial do projeto não é:

```text
como calcular 1d20
```

nem:

```text
como fazer uma câmera girar
```

Essas rodas já existem.

O diferencial é a composição:

```text
deterministic tactical RPG
+
continuous navigation
+
structured generated worlds
+
validated MapSpec
+
AI world authoring
```

Portanto devemos reaproveitar agressivamente:

```text
camera
ability patterns
effects
testing patterns
UI concepts
asset tooling
```

e ser deliberadamente proprietários apenas das peças que definem a arquitetura do produto:

```text
simulation contract
world contract
map generation contract
AI authoring contract
```

---

# 32. Primeiro objetivo real

Não é gerar uma floresta com IA.

Não é importar um personagem bonito.

Não é implementar cinquenta regras de D&D.

É conseguir executar:

```text
godot --headless
```

e provar:

```text
Command
↓
deterministic Resolution
↓
Events
↓
State
```

e depois abrir a arena e provar:

```text
click
↓
Command
↓
path
↓
movement events
↓
EventPlayer
↓
character moves
```

A partir daí o projeto possui uma fundação que pode crescer sem uma reescrita estrutural previsível.

---

# 33. Referências técnicas verificadas

## GodotGAS

```text
https://github.com/yulrun/godot-gas
```

- Godot 4.6+
- MIT
- Gameplay Ability System em GDScript
- abilities, attributes, tags, effects, calculations e cues

---

## Tactical Slash

```text
https://github.com/sion-rgb/tactical-slash
```

- Godot 4.7
- MIT
- RPG tático 3D
- LoS
- AI
- turn flow
- tactical camera
- typed GDScript

---

## Six Worlds

```text
https://github.com/olstach/six_worlds
```

- Godot 4.x
- código MIT
- conteúdo/assets com licença separada
- tactical combat
- initiative
- data-driven systems
- save/load

---

## Terrain3D

```text
https://github.com/TokisanGames/Terrain3D
```

- GDExtension
- MIT
- runtime-accessible API
- terrain LOD
- foliage
- heightmaps

---

## Godot Navigation

Documentação relevante:

```text
NavigationServer3D
NavigationMesh
NavigationRegion3D
NavigationAgent3D
NavigationObstacle3D
Navigation Layers
```

Para portas dinâmicas, preferir região/layer de conexão em vez de presumir que `NavigationObstacle3D` altera pathfinding automaticamente.
