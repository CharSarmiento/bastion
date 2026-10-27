class_name Formation
extends Node2D
## Unidad de mando (compañía): el jugador la selecciona y la ordena como un solo bloque.
## Por dentro se divide sola en escuadras (Squad) que marchan con cierta independencia
## y se despliegan dispersas a lo largo del frente ordenado.
## También puede avanzar por saltos: una escuadra corre mientras las demás la cubren.
## La posición de este nodo es la media de las posiciones de sus soldados.

enum Team { PLAYER, ENEMY }

## Distancia (px) a su tramo final a partir de la cual una escuadra ha terminado de saltar.
const BOUND_ARRIVED_DISTANCE := 24.0
## Si quedan menos de estos píxeles hasta su tramo final, el salto va directamente hasta él.
const BOUND_FINAL_SNAP := 40.0
## Si una escuadra tarda más que esto (segundos) en terminar un salto, salta la siguiente igualmente.
const BOUND_TIMEOUT := 20.0

@export var unit_type: UnitType
@export var team: Team = Team.PLAYER
## Dirección hacia la que mira la formación al empezar.
@export var facing: Vector2 = Vector2.UP

var soldiers: Array[Soldier] = []
var squads: Array[Squad] = []
## true si algún soldado de la compañía está disparando a un enemigo (se actualiza cada frame).
var engaged: bool = false
## true mientras dura un avance por saltos.
var bounding: bool = false
## "Mantener posición" (interruptor del jugador, tecla H): nadie se adelanta por su cuenta para
## disparar. Dura hasta que se desactive, aunque la compañía reciba otras órdenes.
var hold_position: bool = false
var selected: bool = false:
	set(value):
		selected = value
		for soldier in soldiers:
			soldier.selected = value

## Avance por saltos: tramo final de cada escuadra (Squad -> Vector2), punto al que se le mandó
## en su último salto (Squad -> Vector2), anchura de cada tramo, escuadra que está saltando ahora
## y tiempo que lleva saltando.
## El progreso se mide desde el punto ordenado y no desde el centro real de la escuadra: al
## desplegarse buscan cobertura y su centro puede quedar lejos del punto, y entonces parecería
## que no han llegado nunca (saltaban una y otra vez sin terminar).
var _bound_targets: Dictionary = {}
var _bound_positions: Dictionary = {}
var _bound_frontage: float = 0.0
var _bound_mover: Squad = null
var _bound_time: float = 0.0


func _ready() -> void:
	add_to_group("formations")
	facing = facing.normalized()
	_spawn()


## Orden de mover. facing es hacia dónde mirará al llegar (si es cero, hacia donde avanza)
## y width la anchura del frente (si es cero, la anchura por defecto de su ficha).
## Con bound = true avanza por saltos: una escuadra corre mientras las demás la cubren.
func move_to(target: Vector2, new_facing: Vector2 = Vector2.ZERO, width: float = 0.0,
		bound: bool = false) -> void:
	if new_facing == Vector2.ZERO:
		var direction: Vector2 = target - global_position
		new_facing = direction.normalized() if direction.length() > 1.0 else facing
	facing = new_facing.normalized()
	if width <= 0.0:
		width = unit_type.default_front_width
	width = clampf(width, unit_type.min_front_width, unit_type.max_front_width)
	bounding = false
	_bound_mover = null
	if bound and squads.size() > 1:
		_bound_targets.clear()
		_bound_positions.clear()
		for assignment in _assign_segments(target, facing, width):
			_bound_targets[assignment[0]] = assignment[1]
			_bound_positions[assignment[0]] = assignment[0].center()
		_bound_frontage = width / squads.size()
		bounding = true
	else:
		_deploy(target, facing, width, false)


## Retirada combatiendo hasta target. Si new_facing es cero, al llegar miran hacia donde venían
## (hacia el enemigo). Mientras lo tengan a tiro retroceden de espaldas disparando; fuera de su
## alcance corren. Al llegar no se adelantan solos hacia el enemigo hasta la siguiente orden.
func retreat_to(target: Vector2, new_facing: Vector2 = Vector2.ZERO, width: float = 0.0) -> void:
	if new_facing == Vector2.ZERO:
		var back: Vector2 = global_position - target
		new_facing = back.normalized() if back.length() > 1.0 else facing
	move_to(target, new_facing, width)
	for squad in squads:
		squad.begin_retreat()


## Orden "Avanzar": toda la compañía se desplaza offset píxeles conservando la colocación de cada
## soldado (no se reparte un frente nuevo). Sigue mirando hacia donde miraba.
func advance_by(offset: Vector2) -> void:
	bounding = false
	_bound_mover = null
	var occupied: Array[Vector2] = []
	for squad in squads:
		squad.order_shift(offset, occupied)


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


func _physics_process(delta: float) -> void:
	if soldiers.is_empty():
		return
	var sum := Vector2.ZERO
	engaged = false
	for soldier in soldiers:
		sum += soldier.global_position
		if not engaged and soldier.current_target() != null:
			engaged = true
	global_position = sum / soldiers.size()
	if bounding:
		_update_bounding(delta)


## Avance por saltos: cuando la escuadra que salta ha terminado de colocarse, salta la que va
## más retrasada y termina un poco por delante de la más avanzada (se adelantan unas a otras).
## Las que no saltan se quedan quietas cubriendo, y al estar paradas apuntan mejor.
func _update_bounding(delta: float) -> void:
	_bound_time += delta
	if is_instance_valid(_bound_mover) and _bound_mover in squads \
			and not _bound_mover.is_settled() and _bound_time < BOUND_TIMEOUT:
		return
	var remaining: Dictionary = {}
	for squad in squads:
		if squad in _bound_targets:
			remaining[squad] = _path_length(_bound_positions[squad], _bound_targets[squad])
	var mover: Squad = null
	for squad: Squad in remaining:
		if remaining[squad] > BOUND_ARRIVED_DISTANCE and (mover == null or remaining[squad] > remaining[mover]):
			mover = squad
	if mover == null:
		bounding = false  # todas han llegado
		_bound_mover = null
		return
	var others_min: float = INF
	for squad: Squad in remaining:
		if squad != mover:
			others_min = minf(others_min, remaining[squad])
	var own: float = remaining[mover]
	var wanted: float = 0.0 if others_min == INF else maxf(0.0, others_min - unit_type.bound_length * 0.5)
	var step: float = clampf(own - wanted, minf(unit_type.bound_length * 0.5, own), unit_type.bound_length * 2.0)
	var final_target: Vector2 = _bound_targets[mover]
	var point: Vector2 = final_target
	if step < own - BOUND_FINAL_SNAP:
		point = _point_along_path(_bound_positions[mover], final_target, step)
	_bound_positions[mover] = point
	var occupied: Array[Vector2] = []
	for soldier in soldiers:
		if not soldier in mover.members:
			occupied.append(soldier.target_slot())
	mover.order_move(point, facing, _bound_frontage, point, _bound_frontage / 2.0, occupied, false,
		unit_type.bound_speed_factor)
	_bound_mover = mover
	_bound_time = 0.0


func _path_length(from: Vector2, to: Vector2) -> float:
	var path: PackedVector2Array = _nav_path(from, to)
	var length: float = 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	return length


## Punto que está a distance píxeles de from siguiendo la ruta hacia to.
func _point_along_path(from: Vector2, to: Vector2, distance: float) -> Vector2:
	var path: PackedVector2Array = _nav_path(from, to)
	var walked: float = 0.0
	for i in range(1, path.size()):
		var segment: float = path[i - 1].distance_to(path[i])
		if segment > 0.0 and walked + segment >= distance:
			return path[i - 1].lerp(path[i], (distance - walked) / segment)
		walked += segment
	return to


func _nav_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var map: RID = get_world_2d().navigation_map
	if NavigationServer2D.map_get_iteration_id(map) == 0:
		return PackedVector2Array([from, to])
	return NavigationServer2D.map_get_path(map, from, to, true)


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


func _deploy(center: Vector2, direction: Vector2, width: float, instant: bool) -> void:
	var segment: float = width / squads.size()
	var occupied: Array[Vector2] = []
	for assignment in _assign_segments(center, direction, width):
		var squad: Squad = assignment[0]
		squad.order_move(assignment[1], direction, segment, center, width / 2.0, occupied, instant)


## Divide el frente en un tramo por escuadra y se los reparte sin que se crucen:
## la escuadra que está más a la izquierda (mirando al frente) va al tramo de la izquierda.
## Devuelve una lista de [escuadra, centro de su tramo].
func _assign_segments(center: Vector2, direction: Vector2, width: float) -> Array[Array]:
	var right := Vector2(-direction.y, direction.x)
	var ordered: Array[Squad] = squads.duplicate()
	ordered.sort_custom(func(a: Squad, b: Squad) -> bool:
		return a.center().dot(right) < b.center().dot(right))
	var segment: float = width / ordered.size()
	var result: Array[Array] = []
	for k in ordered.size():
		result.append([ordered[k], center + right * ((k - (ordered.size() - 1) / 2.0) * segment)])
	return result
