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

## Fase actual: 1 · Prototipo de batalla
Mapa de prueba, una compañía propia y dos enemigas quietas. Selección (clic o recuadro),
movimiento con clic derecho, disparo automático al enemigo en rango.
Listo cuando: mover y disparar se siente bien.

Orden de trabajo acordado: pasos 1-2 hechos → A. movimiento moderno (hecho) →
paso 3: enemigos y disparos (hecho) → C. cobertura (hecha) → D. avance por saltos (hecho).

Pendiente (ideas del usuario, en este orden; decidir controles con él al llegar):
1. **"Avanzar"**: la compañía adelanta su posición conservando la colocación de cada soldado.
2. **Retirada combatiendo**: retroceden sin dejar de disparar hasta salir del alcance enemigo;
   después se dan la vuelta y corren.
3. **"Mantener posición"**: desactiva el adelantarse solos para disparar.
Quizá haga falta una pequeña barra de órdenes en pantalla. Después: cerrar la Fase 1,
revisar rendimiento (objetivo 200-300 soldados) y empezar la Fase 2.

## Avance por saltos (etapa D) y supresión
- Ctrl + clic derecho (o Ctrl + arrastrar el frente): `Formation.move_to(..., bound = true)`.
  `_update_bounding()`: salta una escuadra cada vez, la más retrasada, y termina
  `bound_length / 2` por delante de la más avanzada (se adelantan unas a otras); corre
  (`bound_speed_factor`). Las demás cubren quietas. Vista previa y marcador en naranja.
- Supresión (paso previo a la moral de la Fase 2): cada disparo recibido suma
  `suppression_per_shot` (la mitad a cubierto); baja `suppression_recovery`/s. Reduce puntería
  y cadencia. Es lo que hace útil cubrir: con ella, saltar salva ~2 soldados de 12 frente a
  avanzar todos a la vez, a cambio de tardar ~3 veces más.
- Alcance: `effective_range` 320 (puntería normal) y `weapon_range` 380 (máximo, puntería
  × hasta 0,35). Al adelantarse para disparar buscan el alcance eficaz.

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
  nunca quedan a menos del 60% del alcance de ningún enemigo.
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
- Los enemigos de la Fase 1 no reciben órdenes, pero devuelven el fuego.
- Acercarse para disparar (idea del usuario): si alguien de la compañía combate
  (`Formation.engaged`), los soldados que no llegan se adelantan hasta ponerse a tiro, como mucho
  `advance_leash` px desde su puesto y respetando la separación mínima
  (`Squad._update_advance()`). Vuelven a su puesto tras 2 s sin combate o con una orden nueva.
  Afecta a los dos bandos (el usuario lo quiere así: da sensación de iniciativa).
  Pendiente: orden "Mantener posición" que lo desactive.
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
