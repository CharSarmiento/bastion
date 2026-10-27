# Documento de diseño — Bastión (nombre código)

RTS táctico de campaña · Godot 4 · 2D top-down · Versión: 27 de octubre de 2026

## Visión general

Un juego de estrategia 2D top-down que combina una campaña por turnos con batallas tácticas en tiempo real, ambientado en un conflicto ficticio de mediados del siglo XX, con la tecnología y el estilo de esa época. El objetivo es conquistar territorio en un mapa estratégico grande; cada choque entre ejércitos se resuelve en una batalla donde el jugador dirige compañías, no soldados individuales.

**Inspiración:** la estructura de campaña de Total War, llevada a una guerra ficticia de los años 50 y 60, en campo abierto y ciudades, con vista cenital 2D.

**Pilares de diseño**

- **Mando, no microgestión.** El jugador da órdenes a compañías y pelotones; los soldados dentro de cada unidad se manejan solos.
- **El terreno decide.** Praderas, bosques, rocas, ríos, pueblos y ciudades cambian la cobertura, la visibilidad y la velocidad. Usar bien el terreno pesa más que tener más tropas.
- **El apoyo se pide, no se maneja.** Aviones, helicópteros y artillería son apoyos que se solicitan sobre un punto del mapa, con un costo y un tiempo de llegada.
- **Las pérdidas importan.** Las bajas de cada batalla se arrastran a la campaña; una victoria cara puede costar la guerra.
- **Alcance acotado.** Sin construcción en tiempo real, sin multijugador en la primera versión.

**Pendiente de definir:** el título comercial del juego, los bandos ficticios y su historia, y el país o región inventado donde ocurre.

## Estructura del juego

El juego alterna dos capas: un mapa de campaña por turnos y batallas en tiempo real que se abren cuando dos ejércitos chocan.

**Ciclo de un turno**

1. **Cobrar recursos** de las regiones controladas.
2. **Reclutar y reforzar** unidades.
3. **Mover ejércitos** en el mapa de campaña.
4. **¿Hay choque con un ejército enemigo?**
   - **No:** se pasa directamente al turno de la IA enemiga (paso 6).
   - **Sí:** el jugador elige entre:
     - **Batalla en tiempo real** (jugarla), o
     - **Resolución automática** (calcularla).
5. **Aplicar resultados:** bajas, experiencia y dueño de la región.
6. **Turno de la IA enemiga.**
7. Vuelta al paso 1 (siguiente turno).

```
Cobrar recursos → Reclutar y reforzar → Mover ejércitos → ¿Choque?
                                                              │
                         ┌──────────── sí ────────────────────┤
                         │                                    │ no
            ┌────────────┴────────────┐                       │
            ▼                         ▼                       │
   Resolución automática    Batalla en tiempo real            │
            │                         │                       │
            └──────────┬──────────────┘                       │
                       ▼                                      │
              Aplicar resultados                              │
       (bajas, experiencia, dueño de región)                  │
                       │                                      │
                       ▼                                      │
             Turno de la IA enemiga ◄─────────────────────────┘
                       │
                       └──► siguiente turno (vuelve a Cobrar recursos)
```

Cada choque puede jugarse en tiempo real o calcularse automáticamente; en ambos casos el resultado vuelve a la campaña antes del turno enemigo.

## Batallas en tiempo real

La batalla es el corazón del juego: si mover y combatir con compañías no es divertido en un mapa pequeño, nada de lo demás importa. Por eso se construye primero.

### Unidades

Cada unidad del jugador es una formación con soldados o vehículos dentro. Se selecciona y se ordena como un solo bloque.

| Unidad | Composición | Rol | Fortaleza | Debilidad |
| --- | --- | --- | --- | --- |
| Compañía de infantería | 10–20 soldados (sprites individuales) | Tomar y mantener terreno | Usa cobertura, fuerte en bosques y edificios | Lenta en campo abierto |
| Pelotón de tanques | 2–4 tanques | Ruptura, apoyo directo | Blindaje, potencia de fuego | Vulnerable en calles y bosques cerrados |
| Sección de morteros | 2–3 equipos | Fuego indirecto de corto alcance | Ataca sin línea de visión | Débil en combate cercano |
| Pelotón de reconocimiento | 6–8 soldados | Explorar y marcar objetivos | Rápido, visión amplia | Poco poder de fuego |

### Órdenes

1. **Mover** a un punto (clic derecho). Con modificador: movimiento rápido o sigiloso.
2. **Atacar** una unidad enemiga concreta.
3. **Mantener posición**: no persigue, dispara a lo que entre en rango.
4. **Retirarse** hacia el borde propio del mapa; preserva tropas a cambio de ceder terreno.
5. **Cambiar formación** (línea, columna, dispersa), que afecta frente de fuego, velocidad y vulnerabilidad a explosivos.

Los soldados dentro de la unidad mantienen su puesto en la formación, buscan la cobertura más cercana a ese puesto y disparan por su cuenta al enemigo visible.

### Terreno y cobertura

- El mapa de batalla es un tilemap 2D con un tipo de terreno por casilla.
- **Pradera y césped:** poca cobertura, visibilidad larga, buena velocidad para vehículos.
- **Bosques y arboledas:** buena cobertura, visibilidad corta; los vehículos avanzan lento.
- **Rocas y terreno quebrado:** cobertura alta para infantería; bloquean el paso de vehículos.
- **Ríos:** solo cruzables por vados o puentes.
- **Colinas:** ventaja de visión y de alcance.
- **Pueblos y ciudades:** ver combate urbano.

### Combate urbano

- La infantería puede ocupar edificios: cobertura muy alta y buena vista, pero el edificio puede caer bajo artillería o bombardeo.
- Las calles canalizan el movimiento: los tanques avanzan por ellas y quedan expuestos a infantería apostada en los edificios.
- Las esquinas cortan la línea de visión; el reconocimiento se vuelve clave.
- Artillería y apoyo aéreo son menos precisos en ciudad y el riesgo de fuego amigo es mayor.
- Los mapas urbanos son más pequeños y el combate más cercano que en campo abierto.

### Moral

Cada unidad tiene una barra de moral además de su número de efectivos. Baja con bajas recibidas, fuego intenso, flancos expuestos y oficiales caídos; sube cerca de unidades aliadas y en buena cobertura. Con moral baja la unidad dispara peor; al quebrarse, huye y deja de obedecer durante un tiempo.

### Visibilidad (niebla de guerra)

Solo se ve lo que tus unidades ven. Árboles, rocas y edificios cortan la línea de visión, lo que permite emboscadas en ambas direcciones. El reconocimiento y los helicópteros de observación sirven para revelar zonas.

### Apoyo aéreo y de artillería

Ninguno de estos se controla como unidad. Se piden desde un panel, se apunta a una zona del mapa y llegan tras una demora.

| Apoyo | Efecto | Demora | Usos por batalla |
| --- | --- | --- | --- |
| Barrera de artillería | Explosiones repetidas en un área circular | Media | Según recursos de campaña |
| Ataque aéreo | Bombardeo en línea a lo largo de una pasada | Larga | Pocos |
| Napalm | Área en llamas durante varios segundos; daño y gran golpe a la moral | Larga | Muy pocos |
| Helicóptero artillado | Sobrevuela un área y ataca lo que ve durante un tiempo limitado | Media | Pocos |
| Inserción en helicóptero | Despliega una compañía de reserva en un punto | Larga | Según tropas disponibles |
| Helicóptero de observación | Revela un área amplia temporalmente | Corta | Varios |

Los apoyos también pueden fallar o tocar a tropas propias si se piden demasiado cerca: obliga a pensar antes de usarlos.

### Condiciones de victoria

- Destruir o hacer huir a todas las unidades enemigas.
- O controlar los puntos clave del mapa al acabar el tiempo.
- El jugador siempre puede retirarse: pierde la batalla pero conserva lo que saque del mapa.

### IA enemiga en batalla

Empieza simple: avanzar hacia los puntos clave, atacar al enemigo visible más cercano, retirarse con moral baja. Más tarde se añade un comportamiento de guerrilla para el bando defensor: esperar ocultos en bosques o edificios, emboscar y replegarse.

## Campaña por turnos

La campaña es un tablero de regiones conectadas donde, turno a turno, se mueven ejércitos, se gestionan recursos y se decide dónde pelear. Empieza con 6–8 regiones y crece cuando la base funcione.

### El mapa

- Una imagen 2D del territorio dividida en **regiones** (provincias, valles, distritos).
- Cada región tiene: dueño, tipo de terreno dominante: campo abierto, bosque o ciudad (define el mapa de batalla que se genera), recursos que produce, y si contiene una base, una aldea o una ciudad.
- Las regiones se conectan en un grafo: solo se puede mover a regiones vecinas.

### Ejércitos

- Un ejército es una ficha en el mapa con un comandante y una lista de unidades (compañías, pelotones).
- Cada turno puede moverse un número de regiones según su tipo; los ejércitos con helicópteros asignados se mueven más lejos.
- Si entra en una región con un ejército enemigo, se dispara una batalla.
- Opción en cada batalla: **combatir en tiempo real** o **resolución automática** (cálculo rápido según fuerzas y terreno). La resolución automática ahorra tiempo en choques poco importantes.

### Recursos

| Recurso | Para qué sirve | De dónde sale |
| --- | --- | --- |
| Suministros | Reclutar y reforzar unidades | Regiones controladas cada turno |
| Combustible | Mantener tanques y helicópteros | Bases y rutas de suministro |
| Puntos de apoyo | Pedir artillería y apoyo aéreo en batalla | Bases aéreas y de artillería controladas |
| Apoyo civil | Determina rebeldía o colaboración de las regiones | Cómo se trata a cada región |

El apoyo civil es opcional para la primera versión, pero encaja con el tema: conquistar sin ganarse a la población genera insurgencia.

### Turno del jugador

1. Cobrar recursos de las regiones controladas.
2. Reclutar o reforzar unidades en regiones con base.
3. Mover ejércitos.
4. Resolver batallas (en tiempo real o automáticas).
5. Terminar turno: actúa la IA enemiga.

### Condiciones de victoria de la campaña

- Controlar un número de regiones clave, o la capital enemiga.
- Derrota si se pierde la base principal o si los suministros quedan en negativo varios turnos seguidos.

### IA de campaña

En su versión simple: reforzar regiones amenazadas, atacar la región vecina más débil, y retirarse si sus fuerzas son muy inferiores.

## Puente campaña–batalla

Campaña y batalla comparten un único estado del juego: cada unidad existe como un registro de datos, y la batalla solo lo lee al empezar y lo actualiza al terminar. Diseñarlo así desde el principio evita reescribir medio juego después.

**Lo que la campaña entrega a la batalla**

- Las unidades de cada bando, con efectivos actuales, experiencia y moral base.
- El tipo de terreno de la región, para elegir o generar el mapa de batalla.
- Los puntos de apoyo disponibles (artillería, aire).
- Quién ataca y quién defiende (define zonas de despliegue).

**Lo que la batalla devuelve a la campaña**

- Ganador, o retirada de uno de los bandos.
- Efectivos restantes de cada unidad; las unidades a cero se eliminan.
- Experiencia ganada por las unidades que participaron.
- Puntos de apoyo gastados.
- Cambio de dueño de la región si gana el atacante.

**Datos de cada unidad (registro persistente)**

| Campo | Ejemplo | Notas |
| --- | --- | --- |
| id | `cia_b_1` | Único en toda la partida |
| tipo | infantería | Referencia a la ficha del tipo (stats base, sprites) |
| nombre | Compañía B, 1.er Batallón | Mostrado al jugador |
| efectivos | 14 / 20 | Actual sobre máximo |
| experiencia | 2 | Niveles que mejoran puntería y moral |
| moral_base | 70 | Valor inicial de moral en batalla |
| ejército | `ejercito_norte_1` | A qué ejército de campaña pertenece |

La resolución automática usa exactamente estos mismos datos, así una batalla jugada y una calculada producen resultados del mismo tipo.

## Arquitectura técnica en Godot

Godot 4 con GDScript. Todo el contenido (tipos de unidad, regiones, apoyos) se define como datos en archivos `Resource` (`.tres`), no dentro del código: así se pueden añadir unidades o balancear números sin tocar la lógica.

### Estructura de carpetas

```
res://
├── assets/
│   ├── units/          # sprites de soldados, tanques
│   ├── vehicles/       # helicópteros, aviones (solo visuales de apoyo)
│   ├── terrain/        # tilesets de césped, árboles, rocas, edificios, calles
│   ├── effects/        # explosiones, humo, fuego, disparos
│   ├── ui/             # iconos, paneles, cursores
│   └── campaign/       # mapa estratégico, fichas de ejército
├── data/
│   ├── unit_types/     # .tres por tipo de unidad
│   ├── support_types/  # .tres por apoyo (artillería, napalm…)
│   └── regions/        # .tres por región del mapa de campaña
├── scenes/
│   ├── battle/         # Battle.tscn, Formation.tscn, Soldier.tscn…
│   ├── campaign/       # Campaign.tscn, RegionNode.tscn, ArmyToken.tscn
│   └── ui/             # menús, HUD de batalla, panel de apoyos
├── scripts/
│   ├── autoload/       # GameState.gd, SaveSystem.gd
│   ├── battle/
│   ├── campaign/
│   └── shared/         # cálculos de combate, resolución automática
└── docs/
    └── diseño.md       # este documento, para Claude Code
```

### Piezas principales

- **`GameState` (autoload):** guarda el estado completo de la partida (regiones, ejércitos, unidades, recursos, turno). Es lo único que sobrevive entre escenas.
- **`Campaign.tscn`:** muestra el mapa, gestiona turnos y movimientos, y lanza batallas.
- **`Battle.tscn`:** recibe la configuración de batalla desde `GameState`, la juega y devuelve el resultado.
- **`Formation` (unidad de mando):** el nodo que el jugador selecciona y ordena. Calcula la ruta con `NavigationAgent2D` y asigna un puesto a cada miembro.
- **`Soldier` / `Vehicle`:** miembros individuales; siguen su puesto, buscan cobertura y disparan.
- **`SupportManager`:** recibe peticiones de apoyo, aplica la demora y crea el efecto (explosiones, pasada de avión, helicóptero).
- **`SaveSystem` (autoload):** guarda y carga `GameState` a disco.

### Decisiones técnicas

- **Movimiento:** navegación 2D de Godot (`NavigationRegion2D` + `NavigationAgent2D`) para la formación; los soldados solo siguen su puesto, no calculan rutas propias. Esto mantiene el rendimiento con muchas unidades.
- **Terreno:** `TileMapLayer` con datos personalizados por tile (cobertura, visibilidad, coste de movimiento).
- **Visión:** comprobación por raycast o por cuadrícula entre unidades, recalculada unas pocas veces por segundo, no cada frame.
- **Escala objetivo:** 10–20 unidades de mando por bando, unos 200–300 soldados en pantalla.
- **Resolución de pantalla:** definir tamaño de sprite base (por ejemplo, 32×32 o 64×64) según tus assets antes de empezar.

## Fases de desarrollo

El desarrollo va de lo más arriesgado a lo más seguro: primero se comprueba que la batalla es divertida, luego se construye la campaña y al final se conectan. No se pasa a la siguiente fase hasta cumplir su condición de "listo".

### Fase 1 · Prototipo de batalla  ← fase actual

Mapa de prueba, una compañía propia y dos enemigas quietas. Selección, movimiento en formación, disparo automático.

**Listo cuando:** mover y disparar se siente bien.

### Fase 2 · Combate táctico

Infantería, tanques, morteros y reconocimiento; cobertura, moral, niebla de guerra e IA enemiga básica.

**Listo cuando:** una batalla completa se puede jugar y ganar.

### Fase 3 · Apoyos

Artillería, ataque aéreo, napalm y helicópteros, pedidos desde un panel con demora y riesgo de fuego amigo.

**Listo cuando:** los apoyos cambian batallas sin decidirlas solos.

### Fase 4 · Campaña mínima

6 a 8 regiones, ejércitos, recursos, turnos y resolución automática de batallas.

**Listo cuando:** se puede ganar la campaña solo con batallas automáticas.

### Fase 5 · Conexión campaña y batalla

Las batallas se lanzan desde la campaña y devuelven bajas y experiencia; guardar y cargar partida.

**Listo cuando:** una partida se juega de principio a fin.

### Fase 6 · Profundidad y pulido

IA de campaña, guerrilla, apoyo civil, más mapas, sonido, menús y balance.

**Listo cuando:** otras personas pueden probarlo sin ayuda.

Las fases 2 y 3 pueden alternarse si prefieres probar los apoyos antes.

## Cómo trabajar con Claude Code

Guarda este documento dentro del proyecto como `docs/diseño.md` y crea un archivo `CLAUDE.md` en la raíz: Claude Code lo lee al empezar cada sesión, así no tienes que repetir el contexto.

**Contenido sugerido para `CLAUDE.md`**

```markdown
# Proyecto: Bastión — RTS táctico de campaña (Godot 4, 2D top-down)

- Lee docs/diseño.md antes de proponer cambios grandes.
- Motor: Godot 4.x estándar, lenguaje GDScript con tipado estático.
- Datos de contenido en Resources (.tres) dentro de data/, nunca hardcodeados.
- Assets en assets/; no renombrar ni mover archivos de assets sin preguntar.
- Fase actual: 1 (prototipo de batalla).
- Comentarios y nombres de UI en español; nombres de código en inglés.
- Tras cada cambio, explica cómo probarlo en el editor.
```

**Primer pedido (Fase 1)**

> Lee docs/diseño.md y CLAUDE.md. Estamos en la Fase 1. Crea la escena Battle.tscn con un mapa de prueba usando los tiles de assets/terrain/, una compañía de infantería del jugador con los sprites de assets/units/ y dos compañías enemigas quietas. Quiero poder seleccionar la compañía con clic o recuadro, moverla con clic derecho manteniendo una formación en línea, y que los soldados disparen solos al enemigo en rango. Antes de escribir código, dime qué archivos vas a crear.

**Consejos**

- **Un objetivo por sesión.** "Agregar la moral" es un buen pedido; "terminar las batallas" no.
- **Pide el plan primero** en tareas grandes y corrígelo antes de que escriba código.
- **Prueba después de cada cambio** y describe lo que ves: "los soldados se amontonan al girar", "el tanque atraviesa los árboles".
- **Pega los errores** de la consola de Godot tal cual.
- **Usa git** y haz un commit cada vez que algo funcione; si un cambio rompe el juego, vuelves atrás en segundos.
- **Describe tus sprites** la primera vez: tamaño en píxeles, si son sprite sheets, cuántos frames por animación y en qué dirección miran.
- **Actualiza `CLAUDE.md`** al pasar de fase.
