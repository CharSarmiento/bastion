class_name CoverType
extends Resource
## Ficha de un tipo de cobertura (roca, sacos terreros, árbol...).
## Cada tipo se guarda como un .tres en data/cover_types/.

enum Shape { CIRCLE, LINE }

## Nombre que ve el jugador.
@export var display_name: String = ""
## Fracción de impactos que detiene cuando está entre el soldado y el tirador (0-1).
@export_range(0.0, 1.0) var protection: float = 0.5
## CIRCLE: objeto redondo (roca, tronco). LINE: objeto alargado (sacos terreros), a lo largo
## del eje horizontal del sprite; solo protege por sus dos caras largas.
@export var shape: Shape = Shape.CIRCLE
## Tamaño del obstáculo respecto al sprite: el radio del círculo es esta fracción de la mitad
## del lado menor; la línea, esta fracción de la anchura.
@export var size_factor: float = 0.8
## Si es mayor que 0, radio fijo en píxeles en lugar de size_factor (el tronco de un árbol:
## la copa es grande pero lo que para balas es el tronco).
@export var fixed_radius: float = 0.0
## Si es true (árboles), el sprite se vuelve semitransparente cuando hay soldados debajo,
## para que no queden ocultos bajo la copa.
@export var fade_when_units_below: bool = false
