class_name Soldier
extends Node2D
## Un soldado: camina hacia el puesto que le asigna su formación y mira hacia donde va.
## No calcula rutas propias; eso lo hace la formación.

## Velocidad de giro, en radianes por segundo.
const TURN_SPEED := 8.0
## A menos de esta distancia (píxeles) del puesto se considera que ha llegado.
const ARRIVE_DISTANCE := 2.0
## A partir de esta distancia mira hacia donde camina; más cerca, hacia donde mira la formación.
const FACE_MOVEMENT_DISTANCE := 8.0
## Velocidad (px/s) a la que la animación de andar se reproduce a su ritmo normal.
const WALK_ANIM_REFERENCE_SPEED := 70.0
const SELECTION_COLOR := Color(0.45, 1.0, 0.45, 0.9)
## Cada cuánto (segundos) comprueba si el camino recto a su puesto está libre.
const PATH_CHECK_INTERVAL := 0.2
## Distancia entre los puntos que se comprueban a lo largo del camino recto.
const PATH_CHECK_STEP := 12.0

## Velocidad máxima; la formación la ajusta para que pueda alcanzar su puesto.
var max_speed: float = 100.0
var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()

var _slot: Vector2
var _slot_facing: Vector2 = Vector2.DOWN
var _facing: Vector2 = Vector2.DOWN
## Rodeo hasta el puesto cuando el camino recto pasa por agua u otra zona no transitable.
var _detour: PackedVector2Array = PackedVector2Array()
var _path_check_timer: float

@onready var _visual: Node2D = $Visual
@onready var _legs: AnimatedSprite2D = $Visual/Legs


func _ready() -> void:
	_slot = global_position
	# Momento inicial aleatorio para que no todos los soldados comprueben en el mismo frame.
	_path_check_timer = randf() * PATH_CHECK_INTERVAL
	_apply_facing()


## Puesto en el mundo hacia el que debe ir y dirección a la que mirar al llegar.
func set_slot(slot: Vector2, facing: Vector2) -> void:
	_slot = slot
	_slot_facing = facing


## Coloca al soldado directamente en su puesto, sin caminar (al aparecer).
func snap_to_slot(slot: Vector2, facing: Vector2) -> void:
	global_position = slot
	set_slot(slot, facing)
	_facing = facing
	_apply_facing()


func distance_to_slot() -> float:
	return global_position.distance_to(_slot)


func _physics_process(delta: float) -> void:
	_path_check_timer -= delta
	if _path_check_timer <= 0.0:
		_path_check_timer = PATH_CHECK_INTERVAL
		_update_detour()
	var goal: Vector2 = _slot
	while not _detour.is_empty() and global_position.distance_to(_detour[0]) < 4.0:
		_detour.remove_at(0)
	if not _detour.is_empty():
		goal = _detour[0]

	var to_goal: Vector2 = goal - global_position
	var distance: float = to_goal.length()
	var slot_distance: float = distance_to_slot()
	if distance > ARRIVE_DISTANCE:
		# Frena al acercarse al puesto para no pasarse ni temblar.
		var speed: float = minf(max_speed, slot_distance * 6.0)
		global_position += to_goal / distance * minf(speed * delta, distance)
		_turn_toward(to_goal if slot_distance > FACE_MOVEMENT_DISTANCE else _slot_facing, delta)
		_legs.play("walk")
		_legs.speed_scale = speed / WALK_ANIM_REFERENCE_SPEED
	else:
		_turn_toward(_slot_facing, delta)
		if _legs.is_playing():
			_legs.stop()
			_legs.frame = 0


## Si el camino recto hasta el puesto está libre, no hace falta rodeo; si no, pide una ruta.
func _update_detour() -> void:
	var map: RID = get_world_2d().navigation_map
	if NavigationServer2D.map_get_iteration_id(map) == 0:
		return
	if _is_straight_line_walkable(map, global_position, _slot):
		_detour.clear()
	else:
		_detour = NavigationServer2D.map_get_path(map, global_position, _slot, true)


func _is_straight_line_walkable(map: RID, from: Vector2, to: Vector2) -> bool:
	var length: float = from.distance_to(to)
	var steps: int = ceili(length / PATH_CHECK_STEP)
	for i in range(1, steps + 1):
		var point: Vector2 = from.lerp(to, float(i) / steps)
		if NavigationServer2D.map_get_closest_point(map, point).distance_to(point) > 1.0:
			return false
	return true


func _draw() -> void:
	# Se dibuja debajo de los sprites del soldado.
	if selected:
		draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 24, SELECTION_COLOR, 1.5)


func _turn_toward(direction: Vector2, delta: float) -> void:
	if direction.length_squared() < 0.0001:
		return
	var angle: float = rotate_toward(_facing.angle(), direction.angle(), TURN_SPEED * delta)
	_facing = Vector2.from_angle(angle)
	_apply_facing()


func _apply_facing() -> void:
	# Los sprites del pack miran hacia abajo (+Y); por eso se resta PI / 2.
	_visual.rotation = _facing.angle() - PI / 2.0
