class_name UnitType
extends Resource
## Ficha de un tipo de unidad: valores base que no cambian durante la partida.
## Cada tipo se guarda como un .tres en data/unit_types/.

## Nombre que ve el jugador.
@export var display_name: String = ""
## Escena de cada miembro de la unidad (por ejemplo, Soldier.tscn).
@export var soldier_scene: PackedScene
@export_range(1, 40) var soldier_count: int = 12

@export_group("Formación")
## Número de filas de la formación en línea.
@export_range(1, 6) var ranks: int = 2
## Separación entre soldados, en píxeles.
@export var soldier_spacing: float = 24.0
## Velocidad de marcha de la formación, en píxeles por segundo.
@export var move_speed: float = 70.0
## Velocidad de giro de la formación, en grados por segundo.
@export var turn_speed_degrees: float = 120.0
