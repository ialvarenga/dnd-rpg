# Correções de design — avaliação inicial das propostas arquiteturais

> Extraído de `implementation_plan.md` v3.0. Registra o raciocínio por trás de
> correções feitas ainda na fase de design, antes da implementação de Marco A.
> As decisões finais já estão incorporadas em
> [core-simulation.md](core-simulation.md); este documento preserva o *porquê*.

As alterações propostas ao plano original fizeram sentido em sua maioria.

## Alterações aceitas sem correção

| Proposta | Decisão | Motivo |
|---|---|---|
| Núcleo puro `Command / Event / State` | **ACEITA** | Resolve testes, replay, save, IA e reações |
| `NavProvider` injetado | **ACEITA** | Mantém simulação independente da engine |
| `LosProvider` injetado | **ACEITA** | Mesma justificativa da navegação |
| IA como fase própria | **ACEITA** | Um inimigo que apenas caminha e ataca é um stub, não uma IA |
| Verticalidade complexa cortada da v1 | **ACEITA** | Mantém uma superfície contínua; Marco E ainda permite colinas navegáveis, vantagem de altura, empurrões e quedas |
| LoS simples incluída desde v1 | **ACEITA** | Targeting dependerá dela |
| Coordenadas absolutas em metros | **ACEITA** | Assets físicos não escalam com mapas |
| Limite de mapas em 256×256m | **ACEITA** | Evita streaming/chunking cedo demais |
| Schema com fonte única | **ACEITA** | Duas implementações manuais inevitavelmente divergem |
| Spike de simulação | **ACEITA** | Valida a arquitetura mais importante |
| Spike de terreno/navmesh runtime | **ACEITA** | Resolve risco do Map Compiler antes de depender dele |
| IA generativa após vertical slice | **ACEITA** | Protege o objetivo principal |

---

## Alterações aceitas com correções

### RNG dentro de `BattleState`

A ideia de RNG serializado é correta, mas a implementação proposta tinha uma
contradição:

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

`NavigationObstacle3D` é útil para avoidance e pode participar do **bake**, mas
não deve ser tratado como um bloqueador dinâmico universal de pathfinding.

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
