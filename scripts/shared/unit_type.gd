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

@export_group("Marcha")
## Distancia entre soldados de una escuadra cuando marchan en fila, en píxeles.
@export var march_spacing: float = 28.0
## Variación de velocidad entre escuadras y entre soldados (0,1 = ±10%).
@export_range(0.0, 0.5) var speed_variation: float = 0.1
## Retraso máximo (segundos) con el que arranca cada escuadra al recibir una orden.
@export var squad_delay_max: float = 0.5
## Retraso máximo (segundos) con el que reacciona cada soldado, sumado al de su escuadra.
@export var reaction_delay_max: float = 0.6

@export_group("Despliegue")
## Distancia mínima entre soldados al desplegarse, en píxeles.
@export var deploy_spacing_min: float = 26.0
## Anchura del frente cuando se da una orden con un clic simple, en píxeles.
@export var default_front_width: float = 260.0
@export var min_front_width: float = 80.0
@export var max_front_width: float = 480.0
## Apertura del abanico de vigilancia: los extremos del frente miran hasta estos grados hacia fuera.
@export var sector_spread_degrees: float = 25.0
