class_name Formation
extends Node2D
## Unidad de mando (compañía): el jugador la selecciona y la ordena como un solo bloque.
## La posición de este nodo es el centro de la formación; calcula la ruta con
## NavigationAgent2D y asigna a cada soldado un puesto en una formación en línea.

enum Team { PLAYER, ENEMY }

@export var unit_type: UnitType
@export var team: Team = Team.PLAYER
## Dirección hacia la que mira la formación al empezar.
@export var facing: Vector2 = Vector2.UP

## Retraso (en píxeles) del soldado más rezagado a partir del cual la formación frena.
const LAG_TOLERANCE := 20.0
## Retraso con el que la formación avanza al ritmo mínimo.
const LAG_MAX := 80.0
const MIN_SPEED_FACTOR := 0.25
## Los soldados pueden ir algo más rápido que la formación para recuperar su puesto.
const SOLDIER_SPEED_FACTOR := 1.6

var soldiers: Array[Soldier] = []
var selected: bool = false:
	set(value):
		selected = value
		for soldier in soldiers:
			soldier.selected = value

var _moving: bool = false
## Dirección actual de la línea (hacia dónde está su frente).
var _heading: Vector2
## Dirección hacia la que mirará al terminar el movimiento.
var _final_facing: Vector2

@onready var _agent: NavigationAgent2D = $NavigationAgent2D


func _ready() -> void:
	add_to_group("formations")
	_heading = facing.normalized()
	_final_facing = _heading
	_spawn_soldiers()


## Orden de mover: la formación va hasta target y al llegar mira en la dirección de la marcha.
func move_to(target: Vector2) -> void:
	var direction: Vector2 = target - global_position
	if direction.length() > 1.0:
		_final_facing = direction.normalized()
	_agent.target_position = target
	_moving = true


func has_soldier_near(point: Vector2, radius: float) -> bool:
	for soldier in soldiers:
		if soldier.global_position.distance_to(point) <= radius:
			return true
	return false


func has_soldier_in_rect(rect: Rect2) -> bool:
	for soldier in soldiers:
		if rect.has_point(soldier.global_position):
			return true
	return false


func _spawn_soldiers() -> void:
	for i in unit_type.soldier_count:
		var soldier: Soldier = unit_type.soldier_scene.instantiate()
		# top_level: el soldado no se mueve automáticamente con el nodo de la formación;
		# camina él solo hacia su puesto.
		soldier.top_level = true
		soldier.max_speed = unit_type.move_speed * SOLDIER_SPEED_FACTOR
		add_child(soldier)
		soldiers.append(soldier)
	for i in soldiers.size():
		soldiers[i].snap_to_slot(_slot_position(i), _heading)


func _physics_process(delta: float) -> void:
	if _moving:
		if _agent.is_navigation_finished():
			_moving = false
		else:
			var next_point: Vector2 = _agent.get_next_path_position()
			var to_next: Vector2 = next_point - global_position
			if to_next.length() > 0.5:
				var step: float = unit_type.move_speed * _cohesion_factor() * delta
				global_position += to_next.normalized() * minf(step, to_next.length())
				_turn_heading(to_next, delta)
	else:
		_turn_heading(_final_facing, delta)
	_assign_slots()


## Gira la línea poco a poco. Si hay que dar media vuelta, la formación se "invierte"
## al instante (cada soldado toma el puesto opuesto) en vez de rotar 180 grados entera.
func _turn_heading(direction: Vector2, delta: float) -> void:
	var target: Vector2 = direction.normalized()
	if _heading.dot(target) < -0.2:
		_heading = -_heading
		soldiers.reverse()
	var turn_speed: float = deg_to_rad(unit_type.turn_speed_degrees)
	_heading = Vector2.from_angle(rotate_toward(_heading.angle(), target.angle(), turn_speed * delta))


## Frena la formación si algún soldado se ha quedado atrás.
func _cohesion_factor() -> float:
	var max_lag: float = 0.0
	for soldier in soldiers:
		max_lag = maxf(max_lag, soldier.distance_to_slot())
	var t: float = clampf((max_lag - LAG_TOLERANCE) / (LAG_MAX - LAG_TOLERANCE), 0.0, 1.0)
	return lerpf(1.0, MIN_SPEED_FACTOR, t)


func _assign_slots() -> void:
	var map: RID = get_world_2d().navigation_map
	var map_ready: bool = NavigationServer2D.map_get_iteration_id(map) > 0
	for i in soldiers.size():
		var slot: Vector2 = _slot_position(i)
		if map_ready:
			# Si el puesto cae en el agua u otra zona no transitable, se usa el punto
			# transitable más cercano (por ejemplo, al cruzar el puente).
			slot = NavigationServer2D.map_get_closest_point(map, slot)
		soldiers[i].set_slot(slot, _heading)


## Posición en el mundo del puesto número index en una formación en línea:
## varias filas, centradas en la posición de la formación.
func _slot_position(index: int) -> Vector2:
	var count: int = soldiers.size()
	var ranks: int = mini(unit_type.ranks, count)
	var per_rank: int = ceili(float(count) / ranks)
	var rank: int = floori(float(index) / per_rank)
	var file: int = index % per_rank
	var in_this_rank: int = mini(per_rank, count - rank * per_rank)
	var spacing: float = unit_type.soldier_spacing
	var side: float = (file - (in_this_rank - 1) / 2.0) * spacing
	var back: float = (rank - (ranks - 1) / 2.0) * spacing
	var right := Vector2(-_heading.y, _heading.x)
	return global_position + right * side - _heading * back
