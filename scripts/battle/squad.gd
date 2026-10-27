class_name Squad
extends Node
## Escuadra: grupo pequeño de soldados dentro de una compañía (Formation).
## Marcha en fila suelta siguiendo el rastro de un punto guía (el "ancla") que recorre
## la ruta, y al llegar se despliega en puntos dispersos e irregulares.

enum State { HOLDING, MARCHING }

## Distancia entre los puntos del rastro que deja el ancla.
const TRAIL_STEP := 6.0
## Desplazamiento lateral alternado de los soldados respecto al rastro al marchar.
const MARCH_LATERAL_OFFSET := 9.0
## Retraso (px) del soldado más rezagado a partir del cual la escuadra frena para esperarle.
const LAG_TOLERANCE := 30.0
const LAG_MAX := 90.0
const MIN_SPEED_FACTOR := 0.3
## Los soldados pueden ir algo más rápido que la escuadra para recuperar su puesto.
const CATCH_UP_FACTOR := 1.6
## Intentos para encontrar cada punto de despliegue antes de relajar la distancia mínima.
const DEPLOY_ATTEMPTS := 40
## Cada cuánto (segundos) revisa si algún soldado debe adelantarse para poder disparar.
const ADVANCE_CHECK_INTERVAL := 0.5
## Al adelantarse, se queda a esta fracción del alcance del enemigo (algo dentro, no al límite).
const ADVANCE_RANGE_FACTOR := 0.85
## Ángulos (grados) alrededor del enemigo que prueba al adelantarse, del más directo al menos.
const ADVANCE_ANGLE_OFFSETS: Array[float] = [0.0, 12.0, -12.0, 24.0, -24.0, 36.0, -36.0]
## Segundos sin que nadie de la compañía combata antes de volver a los puestos.
const DISENGAGE_DELAY := 2.0

var members: Array[Soldier] = []

var _unit_type: UnitType
var _rng := RandomNumberGenerator.new()
var _state: State = State.HOLDING
var _time: float = 0.0
var _speed: float
## Punto guía que recorre la ruta; el primer soldado (jefe de escuadra) va sobre él.
var _anchor: Vector2
var _path: PackedVector2Array = PackedVector2Array()
var _destination: Vector2
var _path_pending: bool = false
## Rastro del ancla, del punto más antiguo al más reciente.
var _trail: PackedVector2Array = PackedVector2Array()
var _start_time: float = 0.0
var _release_times: PackedFloat64Array = PackedFloat64Array()
## Distancia de cada soldado tras el ancla al marchar (con un poco de azar).
var _trail_distances: PackedFloat64Array = PackedFloat64Array()
## Punto de despliegue y dirección de vigilancia de cada soldado.
var _spots: PackedVector2Array = PackedVector2Array()
var _spot_facings: PackedVector2Array = PackedVector2Array()
## Por soldado: punto al que se ha adelantado para poder disparar (Vector2), o null si está
## en su puesto.
var _advance_spots: Array = []
var _advance_timer: float = 0.0
var _disengaged_time: float = 0.0


func setup(unit_type: UnitType, squad_members: Array[Soldier]) -> void:
	_unit_type = unit_type
	members = squad_members
	_rng.randomize()
	_speed = _unit_type.move_speed
	_release_times.resize(members.size())
	_trail_distances.resize(members.size())
	_advance_spots.resize(members.size())
	for i in members.size():
		_trail_distances[i] = i * _unit_type.march_spacing + _rng.randf_range(-4.0, 4.0)
		members[i].max_speed = _unit_type.move_speed * CATCH_UP_FACTOR \
			* _rng.randf_range(1.0 - _unit_type.speed_variation, 1.0 + _unit_type.speed_variation)


## Quita a un soldado caído. El resto sigue con sus puestos y cierra la fila de marcha.
func remove_member(soldier: Soldier) -> void:
	var index: int = members.find(soldier)
	if index == -1:
		return
	members.remove_at(index)
	_release_times.remove_at(index)
	_trail_distances.remove_at(index)
	_advance_spots.remove_at(index)
	if index < _spots.size():
		_spots.remove_at(index)
		_spot_facings.remove_at(index)
	for i in _trail_distances.size():
		_trail_distances[i] = i * _unit_type.march_spacing + _rng.randf_range(-4.0, 4.0)


func center() -> Vector2:
	var sum := Vector2.ZERO
	for soldier in members:
		sum += soldier.global_position
	return sum / maxi(members.size(), 1)


## Orden de ir a un tramo del frente. occupied acumula los puntos ya repartidos entre todas las
## escuadras de la compañía, para que nadie se ponga encima de otro.
## Con instant = true los soldados aparecen directamente en su sitio (al empezar la batalla).
func order_move(destination: Vector2, facing: Vector2, frontage: float, front_center: Vector2,
		front_half_width: float, occupied: Array[Vector2], instant: bool) -> void:
	_destination = destination
	# Una orden nueva manda: nadie sigue adelantado por su cuenta.
	_advance_spots.fill(null)
	_disengaged_time = 0.0
	_plan_deployment(destination, facing, frontage, front_center, front_half_width, occupied)
	if instant:
		for i in members.size():
			members[i].snap_to_slot(_spots[i], _spot_facings[i])
		_state = State.HOLDING
		return

	var variation: float = _unit_type.speed_variation * 0.8
	_speed = _unit_type.move_speed * _rng.randf_range(1.0 - variation, 1.0 + variation)
	# Si ya marchaba, reacciona más rápido y sigue desde donde va.
	var delay_scale: float = 0.5 if _state == State.MARCHING else 1.0
	if _state == State.HOLDING:
		_anchor = members[0].global_position
		_trail = PackedVector2Array([_anchor])
	_start_time = _time + _rng.randf() * _unit_type.squad_delay_max * delay_scale
	for i in members.size():
		var reaction: float = 0.0 if i == 0 else _rng.randf_range(0.1, _unit_type.reaction_delay_max)
		_release_times[i] = _start_time + reaction * delay_scale
	_state = State.MARCHING
	_path_pending = true


func _physics_process(delta: float) -> void:
	if members.is_empty():
		return
	_time += delta
	if _state == State.MARCHING:
		if _path_pending:
			_request_path()
		if not _path_pending and _time >= _start_time:
			_advance_anchor(delta)
	else:
		_update_advance(delta)
	_assign_targets()


func _map() -> RID:
	return members[0].get_world_2d().navigation_map


func _map_ready() -> bool:
	return NavigationServer2D.map_get_iteration_id(_map()) > 0


func _request_path() -> void:
	if not _map_ready():
		return
	_path = NavigationServer2D.map_get_path(_map(), _anchor, _destination, true)
	_path_pending = false
	# Al ordenar a los soldados según su punto, el jefe va al más lejano de la llegada y el
	# último al más cercano, así nadie tiene que adelantar a otro al desplegarse.
	var approach: Vector2 = _path[_path.size() - 2] if _path.size() >= 2 else _anchor
	_sort_spots_by_distance_from(approach)


func _advance_anchor(delta: float) -> void:
	var step: float = _speed * _cohesion_factor() * delta
	while step > 0.0 and not _path.is_empty():
		var to_next: Vector2 = _path[0] - _anchor
		var distance: float = to_next.length()
		if distance <= step:
			_anchor = _path[0]
			_path.remove_at(0)
			step -= distance
		else:
			_anchor += to_next / distance * step
			step = 0.0
	if _anchor.distance_to(_trail[_trail.size() - 1]) >= TRAIL_STEP:
		_trail.append(_anchor)
		_trim_trail()
	if _path.is_empty():
		_state = State.HOLDING


## Frena la escuadra si alguno de los soldados que ya marchan se ha quedado atrás.
func _cohesion_factor() -> float:
	var max_lag: float = 0.0
	for i in members.size():
		if _time >= _release_times[i]:
			max_lag = maxf(max_lag, members[i].distance_to_slot())
	var t: float = clampf((max_lag - LAG_TOLERANCE) / (LAG_MAX - LAG_TOLERANCE), 0.0, 1.0)
	return lerpf(1.0, MIN_SPEED_FACTOR, t)


func _assign_targets() -> void:
	for i in members.size():
		if _time < _release_times[i]:
			continue  # todavía no ha reaccionado a la orden: sigue donde estaba
		var soldier: Soldier = members[i]
		if _state == State.HOLDING:
			var spot: Vector2 = _spots[i] if _advance_spots[i] == null else _advance_spots[i]
			soldier.set_slot(spot, _spot_facings[i])
		else:
			soldier.set_slot(_march_position(i), _march_facing())


## Si alguien de la compañía está combatiendo, los que no llegan a disparar se adelantan
## (como mucho advance_leash desde su puesto) hasta ponerse a tiro. Cuando la compañía deja de
## combatir durante un rato, todos vuelven a sus puestos.
func _update_advance(delta: float) -> void:
	var company: Formation = get_parent()
	if not company.engaged:
		_disengaged_time += delta
		if _disengaged_time >= DISENGAGE_DELAY:
			_advance_spots.fill(null)
		return
	_disengaged_time = 0.0
	_advance_timer -= delta
	if _advance_timer > 0.0:
		return
	_advance_timer = ADVANCE_CHECK_INTERVAL
	for i in members.size():
		# El que ya dispara se queda donde está (en su puesto o adelantado).
		if _time >= _release_times[i] and members[i].current_target() == null:
			_advance_spots[i] = _advance_position(i)


## Punto desde el que ya tendría a tiro al enemigo más cercano, o null si para eso tendría que
## adelantarse más de lo permitido. Prueba primero el camino recto hacia el enemigo y, si ese
## punto queda pegado a un compañero, otros ángulos alrededor del enemigo.
func _advance_position(index: int) -> Variant:
	var spot: Vector2 = _spots[index]
	var reach: float = _unit_type.weapon_range * ADVANCE_RANGE_FACTOR
	var enemy: Soldier = members[index].find_nearest_enemy(spot, reach + _unit_type.advance_leash)
	if enemy == null or spot.distance_to(enemy.global_position) <= reach:
		return null
	var from_enemy: Vector2 = (spot - enemy.global_position).normalized()
	for degrees in ADVANCE_ANGLE_OFFSETS:
		var point: Vector2 = enemy.global_position + from_enemy.rotated(deg_to_rad(degrees)) * reach
		if spot.distance_to(point) > _unit_type.advance_leash:
			continue
		if _map_ready():
			var walkable: Vector2 = NavigationServer2D.map_get_closest_point(_map(), point)
			# Si el punto cae en el agua, no sirve.
			if walkable.distance_to(point) > 8.0:
				continue
			point = walkable
		if _is_spot_free(point, members[index]):
			return point
	return null


## true si ningún otro soldado de la compañía va a quedar demasiado cerca de point.
func _is_spot_free(point: Vector2, who: Soldier) -> bool:
	var company: Formation = get_parent()
	for other in company.soldiers:
		if other != who and other.target_slot().distance_to(point) < _unit_type.deploy_spacing_min:
			return false
	return true


## Puesto en la fila: un punto del rastro a cierta distancia tras el ancla, un poco a un lado.
## Si el rastro todavía es corto, el soldado espera donde está hasta que le toque.
func _march_position(index: int) -> Vector2:
	var soldier: Soldier = members[index]
	var wanted: float = _trail_distances[index]
	var walked: float = 0.0
	var point: Vector2 = _anchor
	var direction: Vector2 = Vector2.ZERO
	var previous: Vector2 = _anchor
	var found: bool = wanted <= 0.0
	for k in range(_trail.size() - 1, -1, -1):
		var segment: float = previous.distance_to(_trail[k])
		if segment > 0.0:
			direction = (previous - _trail[k]) / segment
		if walked + segment >= wanted:
			point = previous.lerp(_trail[k], (wanted - walked) / segment) if segment > 0.0 else previous
			found = true
			break
		walked += segment
		previous = _trail[k]
	if not found:
		return soldier.global_position
	if index > 0 and direction != Vector2.ZERO:
		var side: float = 1.0 if index % 2 == 1 else -1.0
		point += Vector2(-direction.y, direction.x) * side * MARCH_LATERAL_OFFSET
	if _map_ready():
		point = NavigationServer2D.map_get_closest_point(_map(), point)
	return point


func _march_facing() -> Vector2:
	if _trail.size() >= 2:
		return (_trail[_trail.size() - 1] - _trail[_trail.size() - 2]).normalized()
	return (_destination - _anchor).normalized()


## Quita la parte del rastro que ya no necesita nadie.
func _trim_trail() -> void:
	var needed: float = _trail_distances[_trail_distances.size() - 1] + 40.0
	var length: float = 0.0
	for k in range(_trail.size() - 1, 0, -1):
		length += _trail[k].distance_to(_trail[k - 1])
		if length > needed:
			_trail = _trail.slice(k - 1)
			return


## Elige los puntos de despliegue de la escuadra dentro de su tramo del frente: dispersos,
## irregulares, en suelo transitable y a distancia mínima de los demás soldados.
## En la etapa de cobertura esta función se sustituirá por la búsqueda de cobertura.
func _plan_deployment(destination: Vector2, facing: Vector2, frontage: float, front_center: Vector2,
		front_half_width: float, occupied: Array[Vector2]) -> void:
	var right := Vector2(-facing.y, facing.x)
	var min_spacing: float = _unit_type.deploy_spacing_min
	var count: int = members.size()
	# Profundidad de la zona: la justa para que quepan los soldados con su separación.
	var area_per_soldier: float = pow(min_spacing * 1.4, 2.0)
	var half_depth: float = maxf(14.0, count * area_per_soldier / maxf(frontage, 1.0) / 2.0)
	var map_ready: bool = _map_ready()
	_spots = PackedVector2Array()
	_spot_facings = PackedVector2Array()
	for i in count:
		var spacing: float = min_spacing
		var chosen: Vector2 = destination
		var placed: bool = false
		while not placed:
			for attempt in DEPLOY_ATTEMPTS:
				# Cada soldado se reparte en su franja del tramo, con azar dentro de ella.
				var lateral: float = ((i + _rng.randf()) / count - 0.5) * frontage
				var depth: float = _rng.randf_range(-half_depth, half_depth)
				var candidate: Vector2 = destination + right * lateral - facing * depth
				if map_ready:
					var walkable: Vector2 = NavigationServer2D.map_get_closest_point(_map(), candidate)
					if walkable.distance_to(candidate) > 1.0:
						continue
				if _far_from_all(candidate, occupied, spacing):
					chosen = candidate
					placed = true
					break
			spacing *= 0.85
			if spacing < 4.0:
				placed = true
		occupied.append(chosen)
		_spots.append(chosen)
		# Abanico: cuanto más a un lado del frente, más mira hacia ese lado.
		var side_t: float = clampf((chosen - front_center).dot(right) / maxf(front_half_width, 1.0), -1.0, 1.0)
		var angle: float = deg_to_rad(side_t * _unit_type.sector_spread_degrees + _rng.randf_range(-6.0, 6.0))
		_spot_facings.append(facing.rotated(angle))


func _far_from_all(point: Vector2, others: Array[Vector2], spacing: float) -> bool:
	for other in others:
		if other.distance_to(point) < spacing:
			return false
	return true


func _sort_spots_by_distance_from(approach: Vector2) -> void:
	var order: Array[int] = []
	for i in _spots.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return _spots[a].distance_to(approach) > _spots[b].distance_to(approach))
	var spots := PackedVector2Array()
	var facings := PackedVector2Array()
	for i in order:
		spots.append(_spots[i])
		facings.append(_spot_facings[i])
	_spots = spots
	_spot_facings = facings
