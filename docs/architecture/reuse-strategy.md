# Estratégia de reutilização open source

> Extraído de `implementation_plan.md` v3.0. Política de quando e como reusar
> código/assets de terceiros, e o registro dos projetos de referência avaliados.

## Regra geral

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

## Projetos de referência e uso planejado

### Tactical Slash

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

#### Usar como donor/reference para

```text
CameraRig
UI patterns
projectile/view animation
turn UI
LoS concepts
test organization
enemy controller ideas
```

#### Não copiar

```text
grid-based movement model
```

porque nosso jogo usa NavigationMesh contínua.

---

### Terrain3D

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

## Critérios para reutilizar código

Código externo deve passar em quatro filtros.

### 1. License

Preferência:

```text
MIT
BSD
Apache-2.0
CC0 for assets
```

### 2. Coupling

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

### 3. Architectural fit

Não importar um módulo se ele exigir abandonar:

```text
Command / Event / State
```

sem benefício comprovado.

### 4. Maintenance cost

Pergunta obrigatória:

> É mais barato manter esta dependência pelos próximos dois anos do que manter
> 300 linhas nossas?

Se não:

```text
copy/adapt small MIT code
```

pode ser melhor que:

```text
plugin dependency
```

---

## Estratégia final de reutilização

A expectativa atual é:

```text
Tactical Slash
    ↓
camera + view/testing patterns

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

Veja [core-simulation.md](core-simulation.md) para por que o núcleo
permanece proprietário mesmo com esta estratégia de reuso agressivo.

---

## Referências técnicas verificadas

### Tactical Slash

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

### Terrain3D

```text
https://github.com/TokisanGames/Terrain3D
```

- GDExtension
- MIT
- runtime-accessible API
- terrain LOD
- foliage
- heightmaps

### Godot Navigation

Documentação relevante:

```text
NavigationServer3D
NavigationMesh
NavigationRegion3D
NavigationAgent3D
NavigationObstacle3D
Navigation Layers
```

Para portas dinâmicas, preferir região/layer de conexão em vez de presumir que
`NavigationObstacle3D` altera pathfinding automaticamente.

---

## Dependency policy

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

### Pin versions

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
