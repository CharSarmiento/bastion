# Proyecto: Bastión — RTS táctico de campaña (Godot 4, 2D top-down)

## Reglas
- Lee docs/diseno.md antes de proponer cambios grandes.
- Motor: Godot 4.7 estándar, lenguaje GDScript con tipado estático.
- Datos de contenido en Resources (.tres) dentro de data/, nunca hardcodeados.
- Assets en assets/; no renombrar ni mover archivos de assets sin preguntar.
- Comentarios y nombres de UI en español; nombres de código en inglés.
- Tras cada cambio, explica cómo probarlo en el editor.
- El usuario no es programador experto: explica en español y de forma sencilla.
- Git: el usuario hace los commits y los pushes. Claude nunca ejecuta `git commit` ni `git push`;
  cuando algo funcione, recomienda un mensaje de commit.
- Repositorio público en GitHub (https://github.com/CharSarmiento/bastion). assets/ y _fuentes/
  están excluidos en .gitignore por la licencia de CraftPix: nunca deben subirse.

## Fase actual: 2 · Combate táctico
Listo cuando: una batalla completa se puede jugar y ganar.

Fase 1 (prototipo de batalla) terminada: mapa de prueba con dos compañías propias
(PlayerCompany y PlayerCompany2) y dos enemigas quietas; selección, movimiento moderno por
escuadras, disparo automático, cobertura, saltos, órdenes Avanzar / Retirada / Mantener posición
con barra de órdenes y atajos, y rendimiento revisado (ver secciones de abajo).

Orden de trabajo acordado para la Fase 2 (decidir el comportamiento y los controles con el
usuario al empezar cada paso):
1. **Moral** (sobre la supresión que ya existe). ← siguiente
2. **Victoria y derrota.**
3. **IA enemiga básica** (el enemigo usa las mismas órdenes que el jugador).
4. **Línea de visión y niebla de guerra.**
5. **HUD y menús** (idea del usuario: un MVP de infantería completo y presentable antes de
   añadir más tipos de unidad).
6. **Tanques**, 7. **morteros**, 8. **reconocimiento**.
Cada orden nueva lleva botón en la barra de órdenes y un atajo de teclado (decisión del usuario).

## Rendimiento (objetivo 200-300 soldados)
- Medido con 288 soldados combatiendo (12 compañías por bando): lógica 3,0 ms por fotograma
  de media (pico 14 ms al dar órdenes a todas a la vez); con dibujo, 3,7 ms. Presupuesto a
  60 FPS: 16,7 ms. Con 576 soldados: 7,0 ms de media.
- Regla: en código que se ejecuta a menudo, nunca `get_nodes_in_group()` (crea una lista
  nueva cada vez). Usar `Soldier.alive_by_team` / `Soldier.alive_in_team(team)` (vivos por
  bando) y `CoverObject.all` / `CoverObject.near(point, distance)`. Comparar distancias al
  cuadrado (`distance_squared_to`) en bucles grandes. Los grupos "soldiers" y "cover" se
  mantienen (los usan las pruebas).
- Si hace falta más: rejilla espacial para buscar enemigos (sigue siendo N², ~1 ms con 576).

## Órdenes y barra de órdenes
- Varias compañías: recuadro o Mayús + clic izquierdo. Clic simple y "Avanzar" conservan su
  posición relativa; el frente arrastrado se reparte entre ellas. Al elegir puestos, cada
  compañía evita los de las demás del mismo bando (`Formation._friendly_spots()`,
  `Squad.planned_spots()`; `Squad._is_spot_free()` mira a todo el bando).
- `SelectionManager.Order` {MOVE, BOUND, ADVANCE, RETREAT}. Atajos: clic derecho = mover,
  Ctrl = saltos, Alt = avanzar, Mayús = retirada (Mayús solo selecciona con el botón izquierdo). La barra (`OrderBar`, CanvasLayer creado por código en
  `battle.gd`, abajo en el centro, solo con selección) prepara la orden del siguiente clic
  derecho (`armed_order`); tras usarse vuelve a Mover; Esc la cancela.
- "Avanzar" (Alt + clic derecho, sin arrastre; vista previa: un punto azul por soldado):
  `Formation.advance_by(offset)` → `Squad.order_shift()`. El centro de la selección va al clic y
  cada soldado conserva su colocación: camina directo (sin fila) a su sitio desplazado, a paso
  normal (`Soldier.speed_factor`), y ahí toma cobertura a ≤ 40 px si la hay (misma prudencia de
  no adelantarse a tiro). Si cae en agua u obstáculo, el sitio válido más cercano. Mientras
  avanzan no se adelantan solos para disparar. Mantienen hacia dónde miraban.
- Retirada (Mayús + clic derecho, o arrastrar para el frente de llegada; rojo):
  `Formation.retreat_to()` = `move_to` normal + `Squad.begin_retreat()`. Sin frente dibujado,
  al llegar miran hacia donde venían. Por escuadra: si alguien tiene objetivo, todos van de
  espaldas (`Soldier.backpedal`: miran al objetivo, piernas al revés) a
  `retreat_backpedal_factor` (0,5); si nadie, corren a `retreat_run_factor` (1,4). Al llegar,
  `_hold_position`: no se adelantan solos hacia el enemigo hasta la siguiente orden
  (mismo efecto que "Mantener posición", pero solo hasta la siguiente orden).
- "Mantener posición" (tecla H o botón de la barra): interruptor permanente por compañía
  (`Formation.hold_position`, decisión del usuario), no se apaga con otras órdenes. Con él,
  `_update_advance()` no adelanta a nadie; quien ya estuviera adelantado vuelve a su puesto al
  acabar el combate. Si hay varias seleccionadas: se activa en todas salvo que ya lo tuvieran.

## Avance por saltos (etapa D) y supresión
- Ctrl + clic derecho (o Ctrl + arrastrar el frente): `Formation.move_to(..., bound = true)`.
  `_update_bounding()`: salta una escuadra cada vez, la más retrasada, y termina
  `bound_length / 2` por delante de la más avanzada (se adelantan unas a otras); corre
  (`bound_speed_factor`). Las demás cubren quietas. Vista previa y marcador en naranja.
  El progreso se mide desde el punto ordenado en cada salto (`_bound_positions`), nunca desde el
  centro real de la escuadra: al buscar cobertura el centro se desvía y el avance no terminaba
  nunca (bug con muchos árboles: saltaban una y otra vez).
- Supresión (paso previo a la moral de la Fase 2): cada disparo recibido suma
  `suppression_per_shot` (la mitad a cubierto); baja `suppression_recovery`/s. Reduce puntería
  y cadencia. Es lo que hace útil cubrir: con ella, saltar salva ~2 soldados de 12 frente a
  avanzar todos a la vez, a cambio de tardar ~3 veces más.
- Alcance: `effective_range` 320 (puntería normal) y `weapon_range` 380 (máximo, puntería
  × hasta 0,35). Al adelantarse para disparar buscan el alcance eficaz.
- Contra la inquietud (el usuario notó que se movían "sin motivo"): solo se adelanta quien NO
  tiene a nadie a tiro (no para mejorar un tiro largo), cada soldado se recoloca como mucho cada
  8 s (`ADVANCE_MIN_INTERVAL`) y nunca a menos del 80% del alcance eficaz de un enemigo.

## Cobertura (etapa C)
- Decoración con cobertura = `CoverObject` (Sprite2D con `cover_type`, grupo "cover"). Tipos en
  `data/cover_types/`: roca 0,75, sacos terreros 0,8 (forma LINE, solo protegen por sus caras
  largas), árbol 0,5 (solo el tronco, radio 14), tocón 0,35, arbusto 0,2.
- Direccional: protege si el objeto está entre el soldado (pegado a él, ≤ 18 px) y el tirador.
  Reduce la probabilidad de impacto × (1 − protección); cuenta la mejor cobertura.
- `Squad._plan_deployment()`: primero puestos a cubierto en el tramo (+ `cover_search_distance`),
  luego dispersión. Al adelantarse, prefieren cobertura a tiro (`_advance_cover_point`).
  Nadie se coloca encima de un obstáculo.
- Prudencia (petición del usuario: nada de riesgos innecesarios por una cobertura):
  al desplegarse no se adelantan más de 20 px de la línea ordenada si ese punto queda a tiro de
  algún enemigo (sin enemigos cerca, sí pueden ocupar cobertura adelantada, p. ej. sacos
  terreros). Al adelantarse para disparar, prefieren la cobertura más alejada que siga a tiro y
  nunca quedan a menos del 80% del alcance eficaz de ningún enemigo.
- Indicador: círculo de selección azul claro = a cubierto. Las copas de los árboles se vuelven
  semitransparentes con soldados debajo.
- Aún no hay línea de visión: rocas y árboles no cortan disparos (llegará con la niebla de guerra).

## Combate (paso 3)
- Cada `Soldier` busca 2 veces/s al enemigo vivo más cercano dentro de `weapon_range`
  (aún sin línea de visión) y dispara solo. Piernas y torso giran por separado: el torso apunta
  y puede disparar en marcha (puntería × `moving_accuracy_factor`).
- Disparo instantáneo: probabilidad según `accuracy` y distancia; trazadora en `BattleEffects`
  (un solo nodo dibuja todas). Pose `shot_texture` con fogonazo.
- Al morir: animación `Death`, el cuerpo pasa al nodo `Corpses` (grupo "corpses") y la
  compañía lo quita de su escuadra; sin soldados, la compañía desaparece.
- Enemigos: `team = ENEMY`, teñidos con `scenes/battle/team_tint.gdshader` (verde → gris azulado).
- Los enemigos aún no reciben órdenes (hasta el paso 3 de la Fase 2), pero devuelven el fuego.
- Acercarse para disparar (idea del usuario): si alguien de la compañía combate
  (`Formation.engaged`), los soldados que no llegan se adelantan hasta ponerse a tiro, como mucho
  `advance_leash` px desde su puesto y respetando la separación mínima
  (`Squad._update_advance()`). Vuelven a su puesto tras 2 s sin combate o con una orden nueva.
  Afecta a los dos bandos (el usuario lo quiere así: da sensación de iniciativa).
  Se desactiva con "Mantener posición" (tecla H).
- Dificultad: ahora es exigente y al usuario le gusta. El balance fino (puntería, vida, cadencia,
  correa) se deja para el final; no ajustarlo sin que lo pida.

## Movimiento de infantería moderna (prioridad del usuario)
Nada de bloques rígidos del siglo XIX: las unidades se mueven sueltas y con independencia.
- Jerarquía: compañía (`Formation`, la que manda el jugador) → escuadras (`Squad`, automáticas,
  `squad_size` soldados) → soldados (`Soldier`). El jugador nunca manda escuadras sueltas.
- Cada escuadra calcula su propia ruta, aunque las escuadras acaben cruzando por sitios distintos
  (decisión del usuario: se queda así). Un punto guía ("ancla") la recorre y deja un rastro;
  los soldados marchan en fila suelta sobre ese rastro, así cruzan puentes en fila.
- Reacción escalonada (retraso por escuadra y por soldado) y velocidades con variación.
- Al llegar, `Squad._plan_deployment()` elige puntos dispersos e irregulares en el tramo del
  frente de la escuadra; los soldados vigilan en abanico y miran a los lados de vez en cuando.
  En la etapa C esa función se sustituirá por la búsqueda de cobertura.
- Clic derecho = mover; arrastrar con clic derecho = dibujar el frente (anchura y orientación).
- Todos los números se ajustan en `data/unit_types/rifle_company.tres`.

## Assets (pack CraftPix, pixel art)
- Casilla de terreno 64×64 (assets/terrain/tiles/tiles.png: agua, césped, arena, tierra, asfalto).
  Filtro de textura: Nearest (pixel art).
- PNG sueltos, un archivo por fotograma (`walk_01.png`, `walk_02.png`…); no hay sprite sheets.
- Todos los sprites miran hacia ABAJO (sur): cañones y fusiles apuntan a +Y. Al girar hacia una
  dirección `dir`: `rotation = dir.angle() - PI / 2`.
- Soldados por capas: piernas (walk, 7 fr, 96×96) + torso con fusil (body, 64×64); disparo 128×128.
  Todas las capas están dibujadas centradas en su lienzo: se apilan con el mismo centro.
  Figura real del soldado: unos 20×28 px.
- Vehículos: casco + torreta separados (128×128).
- Solo existe el bando verde; el enemigo se distingue tiñendo con shader.
- Fuentes de Photoshop, portadas y licencia en _fuentes/ (ignorada por Godot).
- Como assets/ no está en git, nunca guardes archivos propios (.tres, .tscn, shaders) dentro de
  assets/: van en scenes/, scripts/ o data/.
