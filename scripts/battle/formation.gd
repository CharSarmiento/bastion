class_name Formation
extends Node2D
## Unidad de mando (compañía): el jugador la selecciona y la ordena como un solo bloque.
## Por dentro se divide sola en escuadras (Squad) que marchan con cierta independencia
## y se despliegan dispersas a lo largo del frente ordenado.
## También puede avanzar por saltos: una escuadra corre mientras las demás la cubren.
## La posición de este nodo es la media de las posiciones de sus soldados.

## Un soldado de la compañía ha huido del mapa (no ha muerto, pero ya no combate).
signal soldier_fled(formation: Formation)
## La compañía se ha quedado sin soldados: fled es true si los últimos huyeron del mapa.
signal company_lost(formation: Formation, fled: bool)

enum Team { PLAYER, ENEMY }
## Estado de la moral de la compañía:
## FIRM: obedece todas las órdenes.
## PINNED (clavada): se pega a la cobertura, dispara menos y peor; solo acepta Retirada y
##   "Mantener posición".
## BROKEN (rota): retrocede hacia su retaguardia sin obedecer ni disparar; si la dejan en paz,
##   se rehace.
## FLEEING (huye): corre hasta salir por su borde del mapa y se pierde.
enum Morale { FIRM, PINNED, BROKEN, FLEEING }

## Distancia (px) a su tramo final a partir de la cual una escuadra ha terminado de saltar.
const BOUND_ARRIVED_DISTANCE := 24.0
## Si quedan menos de estos píxeles hasta su tramo final, el salto va directamente hasta él.
const BOUND_FINAL_SNAP := 40.0
## Si una escuadra tarda más que esto (segundos) en terminar un salto, salta la siguiente igualmente.
const BOUND_TIMEOUT := 20.0
## Un disparo llega por el flanco si viene con más de este ángulo (grados) respecto al frente.
const FLANK_ANGLE_DEGREES := 75.0
## Cada cuánto (segundos) se comprueba si hay compañías amigas cerca y cuántos están a cubierto.
const MORALE_CHECK_INTERVAL := 0.5
## Una compañía rota que lleva menos de esto (segundos) sin recibir fuego sigue bajo el fuego.
const UNDER_FIRE_TIME := 2.0
## Un soldado que huye sale del mapa al quedar a menos de esto (píxeles) del borde.
const EXIT_MARGIN := 40.0

## Todas las compañías en la batalla (más rápido que recorrer el grupo "formations").
static var all: Array[Formation] = []
## Límites del mapa (los pone la escena de batalla). Las compañías que huyen salen por ellos.
static var map_bounds: Rect2 = Rect2()

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
## Moral de la compañía (0-100) y su estado.
var morale: float = 100.0
var morale_state: Morale = Morale.FIRM
## Hacia dónde queda su retaguardia (su borde del mapa): lo contrario de hacia donde mira al empezar.
var home_direction: Vector2 = Vector2.DOWN
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
## Moral: segundos desde el último disparo recibido, si hay amigos cerca, fracción de soldados
## a cubierto y temporizador de esas comprobaciones.
var _time_since_fire: float = 1000.0
var _friend_near: bool = false
var _covered_fraction: float = 0.0
var _morale_check_timer: float = 0.0
## Bajas sufridas desde que la compañía se rompió.
var _broken_casualties: int = 0


func _enter_tree() -> void:
	all.append(self)


func _exit_tree() -> void:
	all.erase(self)


func _ready() -> void:
	add_to_group("formations")
	facing = facing.normalized()
	home_direction = -facing
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
	var occupied: Array[Vector2] = _friendly_spots()
	for squad in squads:
		squad.order_shift(offset, occupied)


## true mientras la compañía sigue en la batalla: tiene soldados y no está huyendo.
func is_in_battle() -> bool:
	return not soldiers.is_empty() and morale_state != Morale.FLEEING


## true si acepta órdenes de movimiento (mover, saltos, avanzar): solo con la moral firme.
func can_move() -> bool:
	return morale_state == Morale.FIRM


## true si acepta la retirada y "Mantener posición": también clavada, pero no rota ni huyendo.
func can_retreat() -> bool:
	return morale_state == Morale.FIRM or morale_state == Morale.PINNED


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
	_update_morale(delta)


# --- Moral ---

## Un soldado de la compañía ha recibido un disparo (acierte o no) desde shooter.
func on_fire_received(soldier_position: Vector2, shooter: Vector2, covered: bool) -> void:
	_time_since_fire = 0.0
	if morale_state == Morale.BROKEN or morale_state == Morale.FLEEING:
		return  # ya corren: lo que decide si se rehacen o huyen son las bajas
	var loss: float = unit_type.morale_per_shot
	if covered:
		loss *= 0.5
	var from_front: float = rad_to_deg(absf(facing.angle_to(shooter - soldier_position)))
	if from_front > FLANK_ANGLE_DEGREES:
		loss *= unit_type.morale_flank_factor
	if _friend_near:
		loss *= unit_type.morale_friend_loss_factor
	if morale_state == Morale.PINNED:
		loss *= unit_type.pinned_morale_loss_factor
	_change_morale(-loss)


## Un soldado de la compañía ha abatido a un enemigo.
func on_enemy_killed() -> void:
	_change_morale(unit_type.morale_per_kill)


func _change_morale(amount: float) -> void:
	morale = clampf(morale + amount, 0.0, 100.0)


func _update_morale(delta: float) -> void:
	_time_since_fire += delta
	_morale_check_timer -= delta
	if _morale_check_timer <= 0.0:
		_morale_check_timer = MORALE_CHECK_INTERVAL
		_update_morale_surroundings()
	if _time_since_fire >= unit_type.morale_recovery_delay:
		var recovery: float = unit_type.morale_recovery
		if _covered_fraction >= 0.5:
			recovery *= unit_type.morale_recovery_bonus
		if _friend_near:
			recovery *= unit_type.morale_recovery_bonus
		_change_morale(recovery * delta)
	match morale_state:
		Morale.FIRM:
			if morale < unit_type.broken_threshold:
				_set_morale_state(Morale.BROKEN)
			elif morale < unit_type.pinned_threshold:
				_set_morale_state(Morale.PINNED)
		Morale.PINNED:
			if morale < unit_type.broken_threshold:
				_set_morale_state(Morale.BROKEN)
			elif morale >= unit_type.pinned_recover_threshold:
				_set_morale_state(Morale.FIRM)
		Morale.BROKEN:
			# (Si sufren bajas mientras están rotos, _on_soldier_died los hace huir.)
			if _is_settled():
				if _time_since_fire >= unit_type.rally_time:
					# Se rehacen: vuelven a obedecer, con la moral justa.
					morale = maxf(morale, unit_type.rally_morale)
					_set_morale_state(Morale.FIRM)
				elif _time_since_fire < UNDER_FIRE_TIME:
					_rout()  # han llegado, pero siguen bajo el fuego: retroceden más
		Morale.FLEEING:
			_update_fleeing()


## Comprueba si hay compañías amigas cerca y qué parte de la compañía está a cubierto.
func _update_morale_surroundings() -> void:
	_friend_near = false
	var radius_squared: float = unit_type.morale_nearby_radius * unit_type.morale_nearby_radius
	for other in all:
		if other != self and other.team == team and other.can_retreat() \
				and other.global_position.distance_squared_to(global_position) <= radius_squared:
			_friend_near = true
			break
	var covered: int = 0
	for soldier in soldiers:
		if soldier.is_covered():
			covered += 1
	_covered_fraction = float(covered) / soldiers.size()


func _set_morale_state(state: Morale) -> void:
	if state == morale_state:
		return
	var previous: Morale = morale_state
	morale_state = state
	for soldier in soldiers:
		soldier.pinned = state == Morale.PINNED
		soldier.can_fire = state == Morale.FIRM or state == Morale.PINNED
	match state:
		Morale.PINNED:
			# Se tiran al suelo donde están, pegados a la cobertura más cercana (salvo que ya
			# se estuvieran retirando).
			if not _any_squad_retreating():
				advance_by(Vector2.ZERO)
		Morale.BROKEN:
			_broken_casualties = 0
			_rout()
			_notify_nearby_companies()
		Morale.FLEEING:
			_flee()
			if previous != Morale.BROKEN:
				_notify_nearby_companies()


## Avisa a las compañías cercanas de que esta se ha roto: a las amigas les baja la moral y a las
## enemigas les sube. (Se usa pocas veces, solo cuando una compañía se rompe.)
func _notify_nearby_companies() -> void:
	var radius_squared: float = unit_type.morale_nearby_radius * unit_type.morale_nearby_radius
	for other in all:
		if other == self or other.global_position.distance_squared_to(global_position) > radius_squared:
			continue
		if other.team == team:
			other._change_morale(-other.unit_type.morale_friend_broken)
		else:
			other._change_morale(other.unit_type.morale_enemy_broken)


## Rota: retrocede rout_distance hacia su retaguardia, corriendo y mirando hacia el enemigo.
func _rout() -> void:
	var target: Vector2 = global_position + home_direction * unit_type.rout_distance
	if map_bounds.has_area():
		var inner: Rect2 = map_bounds.grow(-EXIT_MARGIN * 2.0)
		target = target.clamp(inner.position, inner.end)
	_run_to(target, -home_direction)


## Huye: corre hasta su borde del mapa.
func _flee() -> void:
	var target: Vector2 = global_position + home_direction * 100000.0
	if map_bounds.has_area():
		target = target.clamp(map_bounds.position, map_bounds.end)
	_run_to(target, home_direction)


func _run_to(target: Vector2, new_facing: Vector2) -> void:
	bounding = false
	_bound_mover = null
	facing = new_facing.normalized()
	_deploy(target, facing, unit_type.default_front_width, false, unit_type.retreat_run_factor)


## Los que huyen desaparecen al llegar al borde del mapa (o a su punto de huida, si el borde
## no es transitable). Sin soldados, la compañía se pierde.
func _update_fleeing() -> void:
	var inner: Rect2 = map_bounds.grow(-EXIT_MARGIN)
	for squad in squads.duplicate():
		var arrived: bool = squad.is_settled()
		for soldier in squad.members.duplicate():
			if arrived or (map_bounds.has_area() and not inner.has_point(soldier.global_position)):
				soldier_fled.emit(self)
				_remove_soldier(soldier)
				soldier.queue_free()


func _any_squad_retreating() -> bool:
	for squad in squads:
		if squad.is_retreating():
			return true
	return false


func _is_settled() -> bool:
	for squad in squads:
		if not squad.is_settled():
			return false
	return true


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
	var occupied: Array[Vector2] = _friendly_spots()
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
		soldier.company = self
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


## Una baja: baja la moral (más cuantas más bajas lleve la compañía). Si ya estaba rota, huye.
## Los cuerpos se quedan en el mapa: ya no son hijos de la compañía.
func _on_soldier_died(soldier: Soldier) -> void:
	_remove_soldier(soldier)
	if soldiers.is_empty():
		return
	var lost_fraction: float = 1.0 - float(soldiers.size()) / unit_type.soldier_count
	_change_morale(-unit_type.morale_per_casualty * (1.0 + lost_fraction))
	if morale_state == Morale.BROKEN:
		_broken_casualties += 1
		if _broken_casualties >= unit_type.broken_flee_casualties:
			_set_morale_state(Morale.FLEEING)


## Quita al soldado de la compañía y de su escuadra. Si no queda nadie, la compañía desaparece.
func _remove_soldier(soldier: Soldier) -> void:
	soldiers.erase(soldier)
	for squad in squads:
		if soldier in squad.members:
			squad.remove_member(soldier)
			if squad.members.is_empty():
				squads.erase(squad)
				squad.queue_free()
			break
	if soldiers.is_empty():
		company_lost.emit(self, morale_state == Morale.FLEEING)
		queue_free.call_deferred()


func _deploy(center: Vector2, direction: Vector2, width: float, instant: bool,
		speed_factor: float = 1.0) -> void:
	var segment: float = width / squads.size()
	var occupied: Array[Vector2] = _friendly_spots()
	for assignment in _assign_segments(center, direction, width):
		var squad: Squad = assignment[0]
		squad.order_move(assignment[1], direction, segment, center, width / 2.0, occupied, instant,
			speed_factor)


## Puestos de las demás compañías del mismo bando (los que ocupan o a los que se dirigen),
## para que al desplegarse nadie escoja un sitio ya tomado por otra compañía.
func _friendly_spots() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for other in all:
		if other != self and other.team == team:
			for squad in other.squads:
				result.append_array(squad.planned_spots())
	return result


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
