# Arquitetura central — simulação, contratos e estrutura

> Extraído de `implementation_plan.md` v3.0 durante reorganização. Este documento
> descreve decisões **travadas** (não histórico de marcos). Para o roadmap ativo,
> veja [implementation_plan.md](../../implementation_plan.md). Para decisões
> pontuais registradas formalmente, veja [docs/ADR/](../ADR/).

---

## 1. Decisões arquiteturais travadas

### 1.1 Engine

```text
Godot 4.6+
```

Novos projetos em Godot 4.6 usam Jolt como engine de física 3D por padrão.

### 1.2 Linguagem

```text
GDScript
```

C# apenas se surgir um gargalo medido.

### 1.3 Unidade física

```text
1 Godot unit = 1 meter
```

Movimento D&D-like:

```text
30 ft ≈ 9 m
```

### 1.4 Movimento

```text
NavigationMesh
+
NavigationServer3D
+
movimento contínuo
```

Sem grid visível.

### 1.5 Verticalidade

#### V1 / Marco E

“Sem combate vertical” significa que não há pavimentos empilhados, escadas
nem ladder/climbing. O campo continua sendo um único heightfield. Essa
superfície pode ter colinas com rampas, bordas e quedas: Marco E aplica ±2 a
ataques com pelo menos 2,5 m de diferença de altura e permite Shove Push com
projeção e dano de queda (e Prone).

Desde a ADR-009, colinas `jumpable` ligam seus patamares com
`NavigationLink3D` de mão única (descer e subir bordas). Cada link fica numa
camada que codifica a Força mínima para usá-lo (`JumpRules`, SRD 5.2.1 Long/
High Jump e Falling), e `NavProvider.for_jumper()` roteia cada criatura apenas
pelas bordas que ela consegue. Isso continua não sendo um sistema geral de
navegação multinível.

### 1.6 Linha de visão

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

Sem meia cobertura. Sem três quartos de cobertura.

Vegetação decorativa não entra na layer de cover.

> Nota: cobertura parcial (half/three_quarters/total) foi adicionada depois, em
> Marco D5 — ver [marco-d-gameplay-depth.md](../milestones/marco-d-gameplay-depth.md).

### 1.7 Tamanhos

| Preset | Dimensões | Uso |
|---|---:|---|
| encounter | 64 × 64m | combate |
| small | 128 × 128m | ruína/acampamento |
| medium | 256 × 256m | vila/floresta |

Nenhum preset maior até existir necessidade real.

### 1.8 Coordenadas

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

### 1.9 Âncoras semânticas

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

## 2. Escopo D&D-like da V1

### Atributos

- STR / FOR
- DEX / DES
- CON
- INT
- WIS / SAB
- CHA / CAR

### Derivados

- Armor Class;
- HP;
- movement speed;
- proficiency bonus.

### Ataques

```text
d20
+
ability modifier
+
proficiency
vs
Armor Class
```

### Crítico

Natural:

```text
20
```

### Dano

```text
dice
+
modifier
```

Um damage type é suficiente inicialmente.

### Advantage / Disadvantage

```text
2d20 keep high
2d20 keep low
```

### Action economy

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

### Condições

- prone;
- poisoned;
- unconscious;
- dead.

### Fora da V1

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

> Nota: várias destas foram destravadas em marcos posteriores (saving throws e
> equipment em Marco D/E; classes/spell slots/rests permanecem planejados para
> Marco F). Veja [implementation_plan.md](../../implementation_plan.md).

---

## 3. Arquitetura central

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

## 4. Invariantes de arquitetura

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

## 5. Command

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

## 6. Event

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
condition_consumed

actor_downed
actor_died

interaction_completed

command_rejected
```

---

## 7. BattleState

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

## 8. ActorState

Exemplo:

```gdscript
class_name ActorState
extends RefCounted

var id: int
var side: StringName

var position: Vector3

var hp: int
var max_hp: int

var strength: int
var dexterity: int
var constitution: int
var intelligence: int
var wisdom: int
var charisma: int

var proficiency_bonus: int
var weapon_proficiencies: Array[StringName]

# Attack bonus, damage and armor class are never stored: AttackMath
# (sim/rules/attack_math.gd) derives them from the ability scores, the
# proficiencies and equipment_slots.
var equipment_slots: Dictionary

var movement_speed: float
var movement_remaining: float

var action_available: bool
var bonus_action_available: bool
var reaction_available: bool

var conditions: Array[StringName]

var disengaged: bool
```

---

## 9. Resolução determinística

### 9.1 Resultado

```gdscript
class_name ResolutionResult
extends RefCounted

var events: Array[Event] = []
var next_rng_state: int
```

Garantia:

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

### 9.2 Resolver

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

## 10. Apply

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

## 11. Resolução de reação no meio de movimento

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

## 12. NavProvider

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

## 13. LosProvider

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

## 14. EventPlayer

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

## 15. Estrutura de repositório

```text
project/
│
├── godot/
│   ├── project.godot
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

## 16. Registro de decisões — ADR

Decisões importantes devem virar:

```text
docs/ADR/
```

Isso evita revisitar decisões sem lembrar por que foram tomadas. Veja o
diretório [docs/ADR/](../ADR/) para a lista atual.

---

## 17. Por que manter o núcleo próprio mesmo reutilizando frameworks

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

e ser deliberadamente proprietários apenas das peças que definem a arquitetura
do produto:

```text
simulation contract
world contract
map generation contract
AI authoring contract
```

Veja também [reuse-strategy.md](reuse-strategy.md) para a política de reuso de
código open source.

---

## 18. Primeiro objetivo real

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

A partir daí o projeto possui uma fundação que pode crescer sem uma reescrita
estrutural previsível.
