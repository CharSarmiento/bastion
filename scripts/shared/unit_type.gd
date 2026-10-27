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
