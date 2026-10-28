class_name UnitType
extends Resource
## Ficha de un tipo de unidad: valores base que no cambian durante la partida.
## Cada tipo se guarda como un .tres en data/unit_types/.

## Nombre que ve el jugador.
@export var display_name: String = ""
## Escena de cada miembro de la unidad (por ejemplo, Soldier.tscn).
@export var soldier_scene: PackedScene
@export_range(1, 40) var soldier_count: int = 12
## Soldados por escuadra; la compañía se divide sola en escuadras de este tamaño.
@export_range(1, 12) var squad_size: int = 4
## Velocidad de marcha, en píxeles por segundo.
@export var move_speed: float = 70.0

@export_group("Combate")
## Vida de cada soldado.
@export var soldier_health: float = 100.0
## Alcance máximo del arma, en píxeles (una casilla = 64).
@export var weapon_range: float = 380.0
## Alcance eficaz: hasta aquí la puntería baja poco a poco con la distancia; más allá, hasta el
## alcance máximo, cae mucho más (se multiplica hasta long_range_accuracy_factor).
@export var effective_range: float = 320.0
@export_range(0.0, 1.0) var long_range_accuracy_factor: float = 0.35
## Daño de cada impacto.
@export var damage: float = 35.0
## Probabilidad de acertar a quemarropa (0-1); baja con la distancia.
@export_range(0.0, 1.0) var accuracy: float = 0.35
## Tiempo entre disparos de un soldado, en segundos (se elige al azar entre mínimo y máximo).
@export var fire_interval_min: float = 1.4
@export var fire_interval_max: float = 2.6
## Al disparar caminando: la puntería se multiplica por este factor...
@export_range(0.0, 1.0) var moving_accuracy_factor: float = 0.4
## ...y el tiempo entre disparos por este otro.
@export var moving_fire_interval_factor: float = 1.5
## Si su escuadra está combatiendo y un soldado no llega a disparar, se adelanta desde su
## puesto como mucho esta distancia (píxeles) para ponerse a tiro. 0 = nunca se adelanta.
@export var advance_leash: float = 160.0

@export_group("Marcha")
## Distancia entre soldados de una escuadra cuando marchan en fila, en píxeles.
@export var march_spacing: float = 28.0
## Variación de velocidad entre escuadras y entre soldados (0,1 = ±10%).
@export_range(0.0, 0.5) var speed_variation: float = 0.1
## Retraso máximo (segundos) con el que arranca cada escuadra al recibir una orden.
@export var squad_delay_max: float = 0.5
## Retraso máximo (segundos) con el que reacciona cada soldado, sumado al de su escuadra.
@export var reaction_delay_max: float = 0.6

@export_group("Supresión")
## Presión (0-1) que suma cada disparo recibido, acierte o no. A cubierto, la mitad.
@export_range(0.0, 1.0) var suppression_per_shot: float = 0.12
## Presión que se recupera por segundo.
@export var suppression_recovery: float = 0.2
## Con presión máxima, la puntería se multiplica por (1 - este valor)...
@export_range(0.0, 1.0) var suppression_accuracy_penalty: float = 0.7
## ...y el tiempo entre disparos por (1 + este valor).
@export var suppression_fire_delay: float = 1.0

@export_group("Moral")
## La moral (0-100) es de toda la compañía. Moral que se pierde por cada disparo recibido por un
## soldado (acierte o no). A cubierto, la mitad.
@export var morale_per_shot: float = 0.5
## Los disparos que llegan por el flanco o la espalda quitan esta cantidad de veces más moral.
@export var morale_flank_factor: float = 2.0
## Moral que se pierde por cada baja propia; aumenta con las bajas que ya lleve la compañía
## (con la mitad de los soldados caídos, cada baja quita 1,5 veces esto).
@export var morale_per_casualty: float = 6.0
## Moral que se gana por cada enemigo abatido.
@export var morale_per_kill: float = 1.5
## Moral que se pierde cuando se rompe una compañía amiga cercana...
@export var morale_friend_broken: float = 15.0
## ...y la que se gana cuando se rompe una compañía enemiga cercana.
@export var morale_enemy_broken: float = 10.0
## Distancia (píxeles) a la que una compañía tiene en cuenta a las demás (amigos cerca,
## compañías que se rompen).
@export var morale_nearby_radius: float = 450.0
## Con una compañía amiga cerca se pierde esta fracción de la moral de cada disparo.
@export_range(0.0, 1.0) var morale_friend_loss_factor: float = 0.75
## Segundos sin recibir fuego hasta que la moral empieza a recuperarse.
@export var morale_recovery_delay: float = 4.0
## Moral que se recupera por segundo...
@export var morale_recovery: float = 3.0
## ...multiplicada por esto si la mayoría está a cubierto, y otra vez si hay amigos cerca.
@export var morale_recovery_bonus: float = 1.5
## Por debajo de esta moral la compañía queda clavada (se pega al suelo y a la cobertura)...
@export var pinned_threshold: float = 35.0
## ...y deja de estarlo al recuperar esta.
@export var pinned_recover_threshold: float = 50.0
## Por debajo de esta moral la compañía se rompe y retrocede sin obedecer.
@export var broken_threshold: float = 15.0
## Segundos que una compañía rota tiene que pasar sin recibir fuego para rehacerse...
@export var rally_time: float = 6.0
## ...y moral con la que vuelve a obedecer.
@export var rally_morale: float = 40.0
## Distancia (píxeles) que retrocede una compañía al romperse.
@export var rout_distance: float = 450.0
## Una compañía rota que sufre estas bajas mientras está rota huye y se pierde.
@export_range(1, 12) var broken_flee_casualties: int = 2
## Clavados (pegados al suelo) pierden por cada disparo esta fracción de la moral normal: así da
## tiempo a ordenar la retirada antes de que se rompan.
@export_range(0.0, 1.0) var pinned_morale_loss_factor: float = 0.5
## Clavados: la puntería se multiplica por esto...
@export_range(0.0, 1.0) var pinned_accuracy_factor: float = 0.5
## ...y el tiempo entre disparos por esto otro.
@export var pinned_fire_interval_factor: float = 2.0
## Pegados al suelo son más difíciles de alcanzar: la probabilidad de que les den se multiplica por esto.
@export_range(0.0, 1.0) var pinned_target_factor: float = 0.6

@export_group("Avance por saltos")
## Longitud de referencia de los saltos, en píxeles: la escuadra que salta termina la mitad de
## esta distancia por delante de la escuadra más avanzada.
@export var bound_length: float = 140.0
## Las escuadras corren al saltar: su velocidad se multiplica por este factor.
@export var bound_speed_factor: float = 1.3

@export_group("Retirada")
## Mientras alguien de la escuadra tiene un enemigo a tiro, retroceden de espaldas disparando:
## su velocidad se multiplica por este factor...
@export var retreat_backpedal_factor: float = 0.5
## ...y, fuera del alcance enemigo, se dan la vuelta y corren con este otro.
@export var retreat_run_factor: float = 1.4

@export_group("Despliegue")
## Distancia mínima entre soldados al desplegarse, en píxeles.
@export var deploy_spacing_min: float = 26.0
## Hasta qué distancia (píxeles) fuera de su tramo del frente busca cada escuadra cobertura.
@export var cover_search_distance: float = 100.0
## Anchura del frente cuando se da una orden con un clic simple, en píxeles.
@export var default_front_width: float = 260.0
@export var min_front_width: float = 80.0
@export var max_front_width: float = 480.0
## Apertura del abanico de vigilancia: los extremos del frente miran hasta estos grados hacia fuera.
@export var sector_spread_degrees: float = 25.0
