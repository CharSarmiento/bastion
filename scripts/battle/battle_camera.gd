class_name BattleCamera
extends Camera2D
## Cámara de batalla: se mueve con WASD/flechas, acercando el ratón al borde
## o arrastrando con el botón central, y hace zoom con la rueda.

## Velocidad de desplazamiento, en píxeles de pantalla por segundo.
@export var pan_speed: float = 900.0
## Distancia al borde de la ventana (en píxeles) que activa el desplazamiento.
@export var edge_margin: int = 12
@export var edge_scroll_enabled: bool = true
@export var zoom_min: float = 0.5
@export var zoom_max: float = 2.5
## Factor de zoom por cada paso de la rueda.
@export var zoom_step: float = 1.1

var _bounds: Rect2 = Rect2()
var _dragging: bool = false


## Límites del mapa en coordenadas del mundo; la cámara no muestra nada fuera.
func set_bounds(bounds: Rect2) -> void:
	_bounds = bounds
	_clamp_to_bounds()


func _process(delta: float) -> void:
	var direction: Vector2 = Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if edge_scroll_enabled and direction == Vector2.ZERO and not _dragging:
		direction = _edge_direction()
	if direction != Vector2.ZERO:
		# Se divide por el zoom para que la velocidad en pantalla sea siempre la misma.
		position += direction * pan_speed * delta / zoom.x
		_clamp_to_bounds()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					_zoom_at(zoom.x * zoom_step, button.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					_zoom_at(zoom.x / zoom_step, button.position)
			MOUSE_BUTTON_MIDDLE:
				_dragging = button.pressed
	elif event is InputEventMouseMotion and _dragging:
		var motion: InputEventMouseMotion = event
		position -= motion.relative / zoom.x
		_clamp_to_bounds()


## Cambia el zoom manteniendo fijo el punto del mapa que está bajo el ratón.
func _zoom_at(new_zoom: float, screen_point: Vector2) -> void:
	new_zoom = clampf(new_zoom, zoom_min, zoom_max)
	var offset_from_center: Vector2 = screen_point - get_viewport_rect().size / 2.0
	var world_point: Vector2 = position + offset_from_center / zoom.x
	zoom = Vector2(new_zoom, new_zoom)
	position = world_point - offset_from_center / new_zoom
	_clamp_to_bounds()


func _edge_direction() -> Vector2:
	if not DisplayServer.window_is_focused():
		return Vector2.ZERO
	var viewport_rect: Rect2 = get_viewport_rect()
	var mouse: Vector2 = get_viewport().get_mouse_position()
	if not viewport_rect.has_point(mouse):
		return Vector2.ZERO
	var direction := Vector2.ZERO
	if mouse.x < edge_margin:
		direction.x = -1.0
	elif mouse.x > viewport_rect.size.x - edge_margin:
		direction.x = 1.0
	if mouse.y < edge_margin:
		direction.y = -1.0
	elif mouse.y > viewport_rect.size.y - edge_margin:
		direction.y = 1.0
	return direction.normalized()


func _clamp_to_bounds() -> void:
	if not _bounds.has_area():
		return
	var half_view: Vector2 = get_viewport_rect().size / zoom / 2.0
	# Si el mapa es más pequeño que la vista en un eje, se centra en ese eje.
	if _bounds.size.x <= half_view.x * 2.0:
		position.x = _bounds.get_center().x
	else:
		position.x = clampf(position.x, _bounds.position.x + half_view.x, _bounds.end.x - half_view.x)
	if _bounds.size.y <= half_view.y * 2.0:
		position.y = _bounds.get_center().y
	else:
		position.y = clampf(position.y, _bounds.position.y + half_view.y, _bounds.end.y - half_view.y)
