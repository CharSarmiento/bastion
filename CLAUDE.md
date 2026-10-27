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
paso 3: enemigos y disparos (hecho) → **C. cobertura** → D. avance por saltos.

## Combate (paso 3)
- Cada `Soldier` busca 2 veces/s al enemigo vivo más cercano dentro de `weapon_range`
  (aún sin línea de visión) y dispara solo. Piernas y torso giran por separado: el torso apunta
  y puede disparar en marcha (puntería × `moving_accuracy_factor`).
- Disparo instantáneo: probabilidad según `accuracy` y distancia; trazadora en `BattleEffects`
  (un solo nodo dibuja todas). Pose `shot_texture` con fogonazo.
- Al morir: animación `Death`, el cuerpo pasa al nodo `Corpses` (grupo "corpses") y la
  compañía lo quita de su escuadra; sin soldados, la compañía desaparece.
- Enemigos: `team = ENEMY`, teñidos con `scenes/battle/team_tint.gdshader` (verde → gris azulado).
- Los enemigos de la Fase 1 no se mueven, pero devuelven el fuego.

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
