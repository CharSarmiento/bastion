class_name MoraleDisplay
extends Node2D
## Dibuja la moral de todas las compañías: una barrita encima de cada una (verde, amarilla o
## roja) y, si está clavada, rota o huyendo, una etiqueta con su estado.
## Un solo nodo dibuja todas las barras, por encima de los soldados.

const BAR_SIZE := Vector2(36.0, 4.0)
## Distancia (píxeles) entre el soldado más adelantado hacia arriba y la barra.
const BAR_GAP := 20.0
const BACKGROUND := Color(0.0, 0.0, 0.0, 0.6)
const HIGH_COLOR := Color(0.35, 0.85, 0.35)
const MID_COLOR := Color(0.95, 0.8, 0.25)
const LOW_COLOR := Color(0.9, 0.25, 0.2)
const FONT_SIZE := 10
const STATE_LABELS := {
	Formation.Morale.PINNED: ["CLAVADA", Color(0.95, 0.8, 0.25)],
	Formation.Morale.BROKEN: ["ROTA", Color(1.0, 0.5, 0.2)],
	Formation.Morale.FLEEING: ["HUYE", Color(1.0, 0.3, 0.25)],
}


func _ready() -> void:
	z_index = 50


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	for formation in Formation.all:
		if formation.soldiers.is_empty():
			continue
		var top: float = INF
		for soldier in formation.soldiers:
			top = minf(top, soldier.global_position.y)
		var center := Vector2(formation.global_position.x, top - BAR_GAP)
		var rect := Rect2(center - BAR_SIZE / 2.0, BAR_SIZE)
		draw_rect(rect.grow(1.0), BACKGROUND)
		var value: float = formation.morale / 100.0
		var color: Color = MID_COLOR.lerp(HIGH_COLOR, (value - 0.5) * 2.0) if value >= 0.5 \
			else LOW_COLOR.lerp(MID_COLOR, value * 2.0)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * value, rect.size.y)), color)
		if STATE_LABELS.has(formation.morale_state):
			var label: Array = STATE_LABELS[formation.morale_state]
			var text: String = label[0]
			var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
			var position_text := Vector2(center.x - width / 2.0, rect.position.y - 3.0)
			draw_string_outline(font, position_text, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 3,
				Color(0.0, 0.0, 0.0, 0.8))
			draw_string(font, position_text, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, label[1])
