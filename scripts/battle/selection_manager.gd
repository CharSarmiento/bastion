class_name SelectionManager
extends Node2D
## Selección de formaciones con clic o recuadro (botón izquierdo; Mayús para añadir)
## y orden de mover con el botón derecho.

## Píxeles de pantalla que hay que arrastrar para que un clic se convierta en recuadro.
const DRAG_THRESHOLD := 6.0
## Distancia (píxeles del mundo) a un soldado para seleccionar su formación con un clic.
const CLICK_RADIUS := 16.0
const MARKER_DURATION := 0.6
const BOX_FILL := Color(0.45, 1.0, 0.45, 0.12)
const BOX_BORDER := Color(0.45, 1.0, 0.45, 0.9)

var _selected: Array[Formation] = []
var _pressing: bool = false
var _dragging: bool = false
var _press_screen: Vector2
var _press_world: Vector2
## Marcadores de destino: cada uno es [posición, tiempo restante].
var _markers: Array[Array] = []


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_pressing = true
				_dragging = false
				_press_screen = button.position
				_press_world = get_global_mouse_position()
			elif _pressing:
				_pressing = false
				var additive: bool = button.shift_pressed
				if _dragging:
					_select_in_rect(_drag_rect(), additive)
				else:
					_select_at(get_global_mouse_position(), additive)
				_dragging = false
				queue_redraw()
		elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			_order_move(get_global_mouse_position())
	elif event is InputEventMouseMotion and _pressing:
		var motion: InputEventMouseMotion = event
		if not _dragging and motion.position.distance_to(_press_screen) > DRAG_THRESHOLD:
			_dragging = true
		queue_redraw()


func _process(delta: float) -> void:
	if _markers.is_empty():
		return
	for i in range(_markers.size() - 1, -1, -1):
		_markers[i][1] -= delta
		if _markers[i][1] <= 0.0:
			_markers.remove_at(i)
	queue_redraw()


func _draw() -> void:
	if _dragging:
		var rect: Rect2 = _drag_rect()
		draw_rect(rect, BOX_FILL, true)
		draw_rect(rect, BOX_BORDER, false, -1.0)
	for marker in _markers:
		var t: float = marker[1] / MARKER_DURATION
		draw_arc(marker[0], 6.0 + 14.0 * t, 0.0, TAU, 24, Color(BOX_BORDER, t), 1.5)


func _drag_rect() -> Rect2:
	return Rect2(_press_world, get_global_mouse_position() - _press_world).abs()


func _player_formations() -> Array[Formation]:
	var result: Array[Formation] = []
	for node in get_tree().get_nodes_in_group("formations"):
		var formation: Formation = node
		if formation.team == Formation.Team.PLAYER:
			result.append(formation)
	return result


func _select_at(point: Vector2, additive: bool) -> void:
	var hit: Array[Formation] = []
	for formation in _player_formations():
		if formation.has_soldier_near(point, CLICK_RADIUS):
			hit.append(formation)
			break
	_set_selection(hit, additive)


func _select_in_rect(rect: Rect2, additive: bool) -> void:
	var hit: Array[Formation] = []
	for formation in _player_formations():
		if formation.has_soldier_in_rect(rect):
			hit.append(formation)
	_set_selection(hit, additive)


func _set_selection(formations: Array[Formation], additive: bool) -> void:
	if not additive:
		for formation in _selected:
			formation.selected = false
		_selected.clear()
	for formation in formations:
		if formation not in _selected:
			_selected.append(formation)
			formation.selected = true


## Mueve las formaciones seleccionadas; si hay varias, conservan su posición relativa.
func _order_move(target: Vector2) -> void:
	for i in range(_selected.size() - 1, -1, -1):
		if not is_instance_valid(_selected[i]):
			_selected.remove_at(i)
	if _selected.is_empty():
		return
	var center := Vector2.ZERO
	for formation in _selected:
		center += formation.global_position
	center /= _selected.size()
	for formation in _selected:
		formation.move_to(target + formation.global_position - center)
	_markers.append([target, MARKER_DURATION])
	queue_redraw()
