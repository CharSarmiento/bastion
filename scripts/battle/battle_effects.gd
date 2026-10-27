class_name BattleEffects
extends Node2D
## Efectos ligeros de la batalla dibujados todos juntos en un solo nodo (más eficiente que
## crear un nodo por bala). De momento: trazadoras de los disparos.

## Duración de cada trazadora, en segundos.
const TRACER_DURATION := 0.07
const TRACER_COLOR := Color(1.0, 0.9, 0.55, 0.9)

## Cada trazadora es [inicio, fin, tiempo restante].
var _tracers: Array[Array] = []


func _ready() -> void:
	add_to_group("battle_effects")


func add_tracer(from: Vector2, to: Vector2) -> void:
	_tracers.append([from, to, TRACER_DURATION])
	queue_redraw()


func _process(delta: float) -> void:
	if _tracers.is_empty():
		return
	for i in range(_tracers.size() - 1, -1, -1):
		_tracers[i][2] -= delta
		if _tracers[i][2] <= 0.0:
			_tracers.remove_at(i)
	queue_redraw()


func _draw() -> void:
	for tracer in _tracers:
		var t: float = tracer[2] / TRACER_DURATION
		draw_line(tracer[0], tracer[1], Color(TRACER_COLOR, TRACER_COLOR.a * t), 1.0)
