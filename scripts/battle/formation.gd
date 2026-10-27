class_name Formation
extends Node2D
## Unidad de mando (compañía): el jugador la selecciona y la ordena como un solo bloque.
## Por dentro se divide sola en escuadras (Squad) que marchan con cierta independencia
## y se despliegan dispersas a lo largo del frente ordenado.
## La posición de este nodo es la media de las posiciones de sus soldados.

enum Team { PLAYER, ENEMY }

@export var unit_type: UnitType
@export var team: Team = Team.PLAYER
## Dirección hacia la que mira la formación al empezar.
@export var facing: Vector2 = Vector2.UP

var soldiers: Array[Soldier] = []
var squads: Array[Squad] = []
var selected: bool = false:
	set(value):
		selected = value
		for soldier in soldiers:
			soldier.selected = value


func _ready() -> void:
	add_to_group("formations")
	facing = facing.normalized()
	_spawn()


## Orden de mover. facing es hacia dónde mirará al llegar (si es cero, hacia donde avanza)
## y width la anchura del frente (si es cero, la anchura por defecto de su ficha).
func move_to(target: Vector2, new_facing: Vector2 = Vector2.ZERO, width: float = 0.0) -> void:
	if new_facing == Vector2.ZERO:
		var direction: Vector2 = target - global_position
		new_facing = direction.normalized() if direction.length() > 1.0 else facing
	facing = new_facing.normalized()
	if width <= 0.0:
		width = unit_type.default_front_width
	width = clampf(width, unit_type.min_front_width, unit_type.max_front_width)
	_deploy(target, facing, width, false)


## Número de escuadras (para dibujar la vista previa del frente).
func squad_count() -> int:
	return squads.size()


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


func _physics_process(_delta: float) -> void:
	if soldiers.is_empty():
		return
	var sum := Vector2.ZERO
	for soldier in soldiers:
		sum += soldier.global_position
	global_position = sum / soldiers.size()


func _spawn() -> void:
	var start: Vector2 = global_position
	for i in unit_type.soldier_count:
		var soldier: Soldier = unit_type.soldier_scene.instantiate()
		# top_level: el soldado no se mueve automáticamente con el nodo de la formación;
		# camina él solo hacia su puesto.
		soldier.top_level = true
		soldier.unit_type = unit_type
		soldier.team = team
		soldier.died.connect(_on_soldier_died)
		add_child(soldier)
		soldier.global_position = start
		soldiers.append(soldier)
	for first in range(0, soldiers.size(), unit_type.squad_size):
		var squad := Squad.new()
		squad.name = "Squad%d" % (squads.size() + 1)
		add_child(squad)
		squad.setup(unit_type, soldiers.slice(first, first + unit_type.squad_size))
		squads.append(squad)
	_deploy(start, facing, unit_type.default_front_width, true)


## Quita al caído de la compañía y de su escuadra. Si no queda nadie, la compañía desaparece
## (los cuerpos se quedan en el mapa: ya no son hijos de la compañía).
func _on_soldier_died(soldier: Soldier) -> void:
	soldiers.erase(soldier)
	for squad in squads:
		if soldier in squad.members:
			squad.remove_member(soldier)
			if squad.members.is_empty():
				squads.erase(squad)
				squad.queue_free()
			break
	if soldiers.is_empty():
		queue_free.call_deferred()


## Divide el frente en un tramo por escuadra y se los reparte sin que se crucen:
## la escuadra que está más a la izquierda (mirando al frente) va al tramo de la izquierda.
func _deploy(center: Vector2, direction: Vector2, width: float, instant: bool) -> void:
	var right := Vector2(-direction.y, direction.x)
	var ordered: Array[Squad] = squads.duplicate()
	ordered.sort_custom(func(a: Squad, b: Squad) -> bool:
		return a.center().dot(right) < b.center().dot(right))
	var segment: float = width / ordered.size()
	var occupied: Array[Vector2] = []
	for k in ordered.size():
		var segment_center: Vector2 = center + right * ((k - (ordered.size() - 1) / 2.0) * segment)
		ordered[k].order_move(segment_center, direction, segment, center, width / 2.0, occupied, instant)
