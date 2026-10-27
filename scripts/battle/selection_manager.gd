class_name SelectionManager
extends Node2D
## Selección de formaciones con clic o recuadro (botón izquierdo; Mayús para añadir).
## Botón derecho: un clic mueve; arrastrar dibuja el frente (anchura y hacia dónde miran).
## Con Ctrl + botón derecho, la orden es de avance por saltos; con Alt, "Avanzar" (se desplazan
## conservando su colocación); con Mayús, retirada combatiendo. Las mismas órdenes se pueden
## preparar con la barra de órdenes: el siguiente clic derecho usa la orden preparada (Esc la cancela).
## La tecla H activa o desactiva "Mantener posición" en la selección.

enum Order { MOVE, BOUND, ADVANCE, RETREAT }

## Píxeles de pantalla que hay que arrastrar para que un clic se convierta en arrastre.
const DRAG_THRESHOLD := 6.0
## Distancia (píxeles del mundo) a un soldado para seleccionar su formación con un clic.
const CLICK_RADIUS := 16.0
const MARKER_DURATION := 0.6
const BOX_FILL := Color(0.45, 1.0, 0.45, 0.12)
const BOX_BORDER := Color(0.45, 1.0, 0.45, 0.9)
## Color de las órdenes de avance por saltos (Ctrl + clic derecho).
const BOUND_COLOR := Color(1.0, 0.7, 0.3, 0.95)
## Color de la orden "Avanzar" (Alt + clic derecho).
const ADVANCE_COLOR := Color(0.45, 0.8, 1.0, 0.95)
## Color de la retirada combatiendo (Mayús + clic derecho).
const RETREAT_COLOR := Color(1.0, 0.45, 0.45, 0.95)
## Longitud de la flecha que indica hacia dónde mirará el frente.
const FACING_ARROW_LENGTH := 36.0

## Orden preparada con la barra de órdenes para el siguiente clic derecho.
var armed_order: Order = Order.MOVE

var _selected: Array[Formation] = []
# Botón izquierdo: selección.
var _left_pressing: bool = false
var _left_dragging: bool = false
var _left_press_screen: Vector2
var _left_press_world: Vector2
# Botón derecho: órdenes.
var _right_pressing: bool = false
var _right_dragging: bool = false
var _right_press_screen: Vector2
var _right_press_world: Vector2
## Marcadores de destino: cada uno es [posición, tiempo restante, color].
var _markers: Array[Array] = []


func has_selection() -> bool:
	_prune_selection()
	return not _selected.is_empty()


## Prepara una orden para el siguiente clic derecho (lo usa la barra de órdenes).
func arm(order: Order) -> void:
	armed_order = order
	queue_redraw()


## true si todas las formaciones seleccionadas tienen activado "Mantener posición".
func selection_holds() -> bool:
	_prune_selection()
	if _selected.is_empty():
		return false
	for formation in _selected:
		if not formation.hold_position:
			return false
	return true


## Activa "Mantener posición" en la selección o, si ya lo tenían todas, lo desactiva.
func toggle_hold() -> void:
	var value: bool = not selection_holds()
	for formation in _selected:
		formation.hold_position = value


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_button(button)
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_button(button)
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		if _left_pressing and motion.position.distance_to(_left_press_screen) > DRAG_THRESHOLD:
			_left_dragging = true
		if _right_pressing and motion.position.distance_to(_right_press_screen) > DRAG_THRESHOLD:
			_right_dragging = true
		if _left_pressing or _right_pressing or _current_order() == Order.ADVANCE:
			queue_redraw()
	elif event is InputEventKey:
		var key: InputEventKey = event
		if key.pressed and key.keycode == KEY_ESCAPE:
			arm(Order.MOVE)
		elif key.pressed and not key.echo and key.keycode == KEY_H:
			toggle_hold()
		# Pulsar o soltar Ctrl o Alt cambia la vista previa.
		queue_redraw()


func _handle_left_button(button: InputEventMouseButton) -> void:
	if button.pressed:
		_left_pressing = true
		_left_dragging = false
		_left_press_screen = button.position
		_left_press_world = get_global_mouse_position()
	elif _left_pressing:
		_left_pressing = false
		if _left_dragging:
			_select_in_rect(_drag_rect(), button.shift_pressed)
		else:
			_select_at(get_global_mouse_position(), button.shift_pressed)
		_left_dragging = false
		queue_redraw()


func _handle_right_button(button: InputEventMouseButton) -> void:
	if button.pressed:
		_right_pressing = true
		_right_dragging = false
		_right_press_screen = button.position
		_right_press_world = get_global_mouse_position()
	elif _right_pressing:
		_right_pressing = false
		var order: Order = _current_order()
		if order == Order.ADVANCE:
			# "Avanzar" no dibuja frente: va hasta donde se suelta el botón.
			_order_advance(get_global_mouse_position())
		elif _right_dragging:
			_order_front(_right_press_world, get_global_mouse_position(), order)
		else:
			_order_move(get_global_mouse_position(), order)
		_right_dragging = false
		armed_order = Order.MOVE
		queue_redraw()


## Orden que daría ahora un clic derecho: Ctrl = saltos, Alt = avanzar, Mayús = retirada;
## sin teclas, la preparada.
func _current_order() -> Order:
	if Input.is_key_pressed(KEY_CTRL):
		return Order.BOUND
	if Input.is_key_pressed(KEY_ALT):
		return Order.ADVANCE
	if Input.is_key_pressed(KEY_SHIFT):
		return Order.RETREAT
	return armed_order


func _process(delta: float) -> void:
	if _markers.is_empty():
		return
	for i in range(_markers.size() - 1, -1, -1):
		_markers[i][1] -= delta
		if _markers[i][1] <= 0.0:
			_markers.remove_at(i)
	queue_redraw()


func _draw() -> void:
	if _left_dragging:
		var rect: Rect2 = _drag_rect()
		draw_rect(rect, BOX_FILL, true)
		draw_rect(rect, BOX_BORDER, false, -1.0)
	if _current_order() == Order.ADVANCE:
		_draw_advance_preview(get_global_mouse_position())
	elif _right_dragging:
		_draw_front_preview(_right_press_world, get_global_mouse_position())
	for marker in _markers:
		var t: float = marker[1] / MARKER_DURATION
		draw_arc(marker[0], 6.0 + 14.0 * t, 0.0, TAU, 24, Color(marker[2], t), 1.5)


func _order_color(order: Order) -> Color:
	match order:
		Order.BOUND:
			return BOUND_COLOR
		Order.ADVANCE:
			return ADVANCE_COLOR
		Order.RETREAT:
			return RETREAT_COLOR
	return BOX_BORDER


## Línea del frente, flecha hacia donde mirará y un punto por escuadra.
func _draw_front_preview(from: Vector2, to: Vector2) -> void:
	_prune_selection()
	if _selected.is_empty():
		return
	var color: Color = _order_color(_current_order())
	var facing: Vector2 = _front_facing(from, to)
	var center: Vector2 = (from + to) / 2.0
	draw_line(from, to, color, -1.0)
	var tip: Vector2 = center + facing * FACING_ARROW_LENGTH
	draw_line(center, tip, color, -1.0)
	draw_line(tip, tip - facing.rotated(0.5) * 8.0, color, -1.0)
	draw_line(tip, tip - facing.rotated(-0.5) * 8.0, color, -1.0)
	for part in _split_front(from, to):
		var formation: Formation = part[0]
		var part_from: Vector2 = part[1]
		var part_to: Vector2 = part[2]
		var count: int = formation.squad_count()
		for k in count:
			draw_circle(part_from.lerp(part_to, (k + 0.5) / count), 3.0, color)


## "Avanzar": un punto por soldado donde quedaría (antes de buscar cobertura cercana).
func _draw_advance_preview(target: Vector2) -> void:
	_prune_selection()
	if _selected.is_empty():
		return
	var offset: Vector2 = target - _selection_center()
	for formation in _selected:
		for soldier in formation.soldiers:
			draw_circle(soldier.global_position + offset, 2.5, ADVANCE_COLOR)
	draw_line(_selection_center(), target, Color(ADVANCE_COLOR, 0.4), -1.0)


func _drag_rect() -> Rect2:
	return Rect2(_left_press_world, get_global_mouse_position() - _left_press_world).abs()


func _player_formations() -> Array[Formation]:
	var result: Array[Formation] = []
	for node in get_tree().get_nodes_in_group("formations"):
		var formation: Formation = node
		if formation.team == Formation.Team.PLAYER:
			result.append(formation)
	return result


func _prune_selection() -> void:
	for i in range(_selected.size() - 1, -1, -1):
		if not is_instance_valid(_selected[i]):
			_selected.remove_at(i)


func _selection_center() -> Vector2:
	var center := Vector2.ZERO
	for formation in _selected:
		center += formation.global_position
	return center / maxi(_selected.size(), 1)


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


## Orden simple: mueve las formaciones seleccionadas; si hay varias, conservan su posición relativa.
## order puede ser mover, avance por saltos o retirada.
func _order_move(target: Vector2, order: Order) -> void:
	_prune_selection()
	if _selected.is_empty():
		return
	var center: Vector2 = _selection_center()
	for formation in _selected:
		_give_move_order(formation, target + formation.global_position - center, Vector2.ZERO, 0.0, order)
	_markers.append([target, MARKER_DURATION, _order_color(order)])


func _give_move_order(formation: Formation, target: Vector2, facing: Vector2, width: float,
		order: Order) -> void:
	if order == Order.RETREAT:
		formation.retreat_to(target, facing, width)
	else:
		formation.move_to(target, facing, width, order == Order.BOUND)


## Orden "Avanzar": todas las formaciones seleccionadas se desplazan lo mismo, de modo que el
## centro de la selección acaba en target, y cada soldado conserva su colocación.
func _order_advance(target: Vector2) -> void:
	_prune_selection()
	if _selected.is_empty():
		return
	var offset: Vector2 = target - _selection_center()
	for formation in _selected:
		formation.advance_by(offset)
	_markers.append([target, MARKER_DURATION, ADVANCE_COLOR])


## Orden de frente: cada formación seleccionada recibe su parte de la línea dibujada.
## order puede ser mover, avance por saltos o retirada.
func _order_front(from: Vector2, to: Vector2, order: Order) -> void:
	_prune_selection()
	if _selected.is_empty():
		return
	var facing: Vector2 = _front_facing(from, to)
	for part in _split_front(from, to):
		var formation: Formation = part[0]
		var part_from: Vector2 = part[1]
		var part_to: Vector2 = part[2]
		_give_move_order(formation, (part_from + part_to) / 2.0, facing, part_from.distance_to(part_to), order)
	_markers.append([(from + to) / 2.0, MARKER_DURATION, _order_color(order)])


## Arrastrar de izquierda a derecha hace mirar "hacia arriba" respecto a la línea.
func _front_facing(from: Vector2, to: Vector2) -> Vector2:
	var line: Vector2 = (to - from).normalized()
	return Vector2(line.y, -line.x)


## Reparte la línea entre las formaciones seleccionadas, ordenadas a lo largo de ella para que
## no se crucen. Devuelve una lista de [formación, inicio de su tramo, fin de su tramo].
func _split_front(from: Vector2, to: Vector2) -> Array[Array]:
	var line: Vector2 = to - from
	var ordered: Array[Formation] = _selected.duplicate()
	ordered.sort_custom(func(a: Formation, b: Formation) -> bool:
		return a.global_position.dot(line) < b.global_position.dot(line))
	var parts: Array[Array] = []
	for i in ordered.size():
		var part_from: Vector2 = from + line * (float(i) / ordered.size())
		var part_to: Vector2 = from + line * (float(i + 1) / ordered.size())
		parts.append([ordered[i], part_from, part_to])
	return parts
