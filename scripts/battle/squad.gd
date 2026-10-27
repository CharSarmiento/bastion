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
## Al adelantarse, se queda a esta fracción del alcance eficaz (algo dentro, no al límite).
const ADVANCE_RANGE_FACTOR := 0.95
## Ángulos (grados) alrededor del enemigo que prueba al adelantarse, del más directo al menos.
const ADVANCE_ANGLE_OFFSETS: Array[float] = [0.0, 12.0, -12.0, 24.0, -24.0, 36.0, -36.0]
## Segundos sin que nadie de la compañía combata antes de volver a los puestos.
const DISENGAGE_DELAY := 2.0
## Un soldado que se ha recolocado por su cuenta no vuelve a hacerlo hasta pasados estos segundos
## (así no se pasan el combate yendo y viniendo).
const ADVANCE_MIN_INTERVAL := 8.0
## Al desplegarse, lo máximo (px) que se adelantan de la línea ordenada para buscar una
## cobertura que quede al alcance de algún enemigo: no se meten por delante de la línea del
## jugador si eso les pone a tiro. Sin enemigos cerca, sí pueden ocupar una cobertura adelantada.
const COVER_MAX_FORWARD := 20.0
## Al adelantarse para disparar, nunca se acercan a ningún enemigo a menos de esta fracción
## del alcance eficaz: no se arriesgan más de lo necesario por una cobertura.
const ADVANCE_MIN_RANGE_FACTOR := 0.8
## Orden "Avanzar": cada soldado busca cobertura como mucho a esta distancia (px) de su nuevo
## sitio; si no hay, se queda en él (o lo más cerca posible, si cae en el agua o en un obstáculo).
const SHIFT_COVER_RADIUS := 40.0
const SHIFT_SEARCH_RADIUS := 60.0
## Si alguien no llega en este tiempo (segundos), la orden "Avanzar" se da por terminada.
const SHIFT_TIMEOUT := 60.0

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
## Por soldado: momento (en _time) de su última recolocación por su cuenta.
var _last_relocation: PackedFloat64Array = PackedFloat64Array()
## true mientras cumple una orden "Avanzar" (cada soldado camina directo a su nuevo sitio).
var _shifting: bool = false
## true mientras marcha en retirada combatiendo.
var _retreating: bool = false
## true si no debe adelantarse por su cuenta para disparar (tras una retirada, hasta la
## siguiente orden).
var _hold_position: bool = false


func setup(unit_type: UnitType, squad_members: Array[Soldier]) -> void:
	_unit_type = unit_type
	members = squad_members
	_rng.randomize()
	_speed = _unit_type.move_speed
	_release_times.resize(members.size())
	_trail_distances.resize(members.size())
	_advance_spots.resize(members.size())
	_last_relocation.resize(members.size())
	_last_relocation.fill(-ADVANCE_MIN_INTERVAL)
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
	_last_relocation.remove_at(index)
	if index < _spots.size():
		_spots.remove_at(index)
		_spot_facings.remove_at(index)
	for i in _trail_distances.size():
		_trail_distances[i] = i * _unit_type.march_spacing + _rng.randf_range(-4.0, 4.0)


## true cuando la escuadra ha llegado y todos sus soldados están ya en su puesto.
func is_settled() -> bool:
	if _state != State.HOLDING:
		return false
	for i in members.size():
		if _time < _release_times[i] or members[i].distance_to_slot() > 8.0:
			return false
	return true


func center() -> Vector2:
	var sum := Vector2.ZERO
	for soldier in members:
		sum += soldier.global_position
	return sum / maxi(members.size(), 1)


## Orden de ir a un tramo del frente. occupied acumula los puntos ya repartidos entre todas las
## escuadras de la compañía, para que nadie se ponga encima de otro.
## Con instant = true los soldados aparecen directamente en su sitio (al empezar la batalla).
## speed_factor > 1 hace que la escuadra corra (en los saltos del avance por saltos).
func order_move(destination: Vector2, facing: Vector2, frontage: float, front_center: Vector2,
		front_half_width: float, occupied: Array[Vector2], instant: bool, speed_factor: float = 1.0) -> void:
	_destination = destination
	# Una orden nueva manda: nadie sigue adelantado por su cuenta.
	_advance_spots.fill(null)
	_disengaged_time = 0.0
	_end_shift()
	_end_retreat()
	_hold_position = false
	_plan_deployment(destination, facing, frontage, front_center, front_half_width, occupied)
	if instant:
		for i in members.size():
			members[i].snap_to_slot(_spots[i], _spot_facings[i])
		_state = State.HOLDING
		return

	var variation: float = _unit_type.speed_variation * 0.8
	_speed = _unit_type.move_speed * _rng.randf_range(1.0 - variation, 1.0 + variation) * speed_factor
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


## Orden "Avanzar": la escuadra se desplaza offset píxeles conservando la colocación de cada
## soldado. No marchan en fila: cada uno camina directo a su nuevo sitio (rodeando el agua) a
## paso normal, y al llegar busca una cobertura pegada a él.
func order_shift(offset: Vector2, occupied: Array[Vector2]) -> void:
	_advance_spots.fill(null)
	_disengaged_time = 0.0
	_end_retreat()
	_hold_position = false
	_state = State.HOLDING
	_path_pending = false
	_path.clear()
	_spots = PackedVector2Array()
	for i in members.size():
		var spot: Vector2 = _shift_spot(members[i].global_position + offset, _spot_facings[i], occupied)
		occupied.append(spot)
		_spots.append(spot)
	_start_time = _time + _rng.randf() * _unit_type.squad_delay_max
	for i in members.size():
		var reaction: float = 0.0 if i == 0 else _rng.randf_range(0.1, _unit_type.reaction_delay_max)
		_release_times[i] = _start_time + reaction
		members[i].speed_factor = 1.0 / CATCH_UP_FACTOR
	_shifting = true


func _physics_process(delta: float) -> void:
	if members.is_empty():
		return
	_time += delta
	if _state == State.MARCHING:
		if _path_pending:
			_request_path()
		if not _path_pending and _time >= _start_time:
			_advance_anchor(delta)
	elif _retreating:
		# Los últimos pasos hasta su puesto también los dan de espaldas si hay enemigos a tiro.
		_retreat_speed_factor()
		if is_settled():
			_end_retreat()
	elif _shifting:
		# Mientras avanzan, nadie se adelanta por su cuenta: manda la orden.
		if is_settled() or _time > _start_time + SHIFT_TIMEOUT:
			_end_shift()
	else:
		_update_advance(delta)
	_assign_targets()


## Convierte la marcha recién ordenada (order_move) en una retirada combatiendo: mientras alguien
## de la escuadra tenga un enemigo a tiro, retroceden de espaldas disparando; fuera del alcance,
## corren. Al llegar no se adelantan solos hacia el enemigo.
func begin_retreat() -> void:
	_retreating = true
	_hold_position = true


func _end_retreat() -> void:
	_retreating = false
	for soldier in members:
		soldier.backpedal = false


## Factor de velocidad de la marcha en retirada según haya o no enemigos a tiro.
func _retreat_speed_factor() -> float:
	var in_contact: bool = false
	for soldier in members:
		if soldier.current_target() != null:
			in_contact = true
			break
	for soldier in members:
		soldier.backpedal = in_contact
	return _unit_type.retreat_backpedal_factor if in_contact else _unit_type.retreat_run_factor


func _end_shift() -> void:
	_shifting = false
	for soldier in members:
		soldier.speed_factor = 1.0


## Sitio final de un soldado al avanzar: la mejor cobertura cercana a point (sin meterse por
## delante a tiro del enemigo); si no hay, point o el punto válido más cercano.
func _shift_spot(point: Vector2, facing: Vector2, occupied: Array[Vector2]) -> Vector2:
	var spacing: float = _unit_type.deploy_spacing_min
	var best: Variant = null
	var best_score: float = -INF
	for node in get_tree().get_nodes_in_group("cover"):
		var cover: CoverObject = node
		if cover.global_position.distance_to(point) > SHIFT_COVER_RADIUS + 40.0:
			continue
		for candidate in cover.cover_points(facing):
			var distance: float = candidate.distance_to(point)
			if distance > SHIFT_COVER_RADIUS:
				continue
			if (candidate - point).dot(facing) > COVER_MAX_FORWARD and _in_enemy_range(candidate):
				continue
			var score: float = cover.cover_type.protection - distance / 100.0
			if score > best_score and _is_valid_stand_point(candidate) \
					and _far_from_all(candidate, occupied, spacing):
				best = candidate
				best_score = score
	if best != null:
		return best
	if _is_valid_stand_point(point) and _far_from_all(point, occupied, spacing):
		return point
	# El sitio cae en el agua, en un obstáculo o encima de un compañero: busca el más cercano.
	for attempt in DEPLOY_ATTEMPTS:
		var radius: float = SHIFT_SEARCH_RADIUS * (attempt + 1) / DEPLOY_ATTEMPTS
		var candidate: Vector2 = point + Vector2.from_angle(_rng.randf() * TAU) * radius
		if _map_ready():
			candidate = NavigationServer2D.map_get_closest_point(_map(), candidate)
		if _is_valid_stand_point(candidate) and _far_from_all(candidate, occupied, spacing * 0.8):
			return candidate
	return NavigationServer2D.map_get_closest_point(_map(), point) if _map_ready() else point


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
	if _retreating:
		step *= _retreat_speed_factor()
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
	# Durante el avance por saltos nadie se adelanta por su cuenta: manda el salto.
	# Tras una retirada, tampoco: no van a volver solos hacia el enemigo.
	if company.bounding or _hold_position:
		return
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
		# Solo intenta acercarse quien no tiene a nadie a tiro; el que ya dispara (aunque sea de
		# lejos) se queda donde está. Y nadie se recoloca más de una vez cada ADVANCE_MIN_INTERVAL.
		if _time < _release_times[i] or members[i].current_target() != null \
				or _time < _last_relocation[i] + ADVANCE_MIN_INTERVAL:
			continue
		var previous: Variant = _advance_spots[i]
		_advance_spots[i] = _advance_position(i)
		if _advance_spots[i] != previous:
			_last_relocation[i] = _time
		# Se reserva el puesto ya, para que el siguiente compañero lo tenga en cuenta.
		var spot: Vector2 = _spots[i] if _advance_spots[i] == null else _advance_spots[i]
		members[i].set_slot(spot, _spot_facings[i])


## Punto desde el que ya tendría a tiro al enemigo más cercano, o null si para eso tendría que
## adelantarse más de lo permitido. Prefiere una cobertura a tiro; si no hay, prueba el camino
## recto hacia el enemigo y, si ese punto queda pegado a un compañero, otros ángulos.
func _advance_position(index: int) -> Variant:
	var spot: Vector2 = _spots[index]
	var reach: float = _unit_type.effective_range * ADVANCE_RANGE_FACTOR
	var enemy: Soldier = members[index].find_nearest_enemy(spot, reach + _unit_type.advance_leash)
	if enemy == null or spot.distance_to(enemy.global_position) <= reach:
		return null
	var cover_point: Variant = _advance_cover_point(index, spot, enemy.global_position, reach)
	if cover_point != null:
		return cover_point
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
		var too_close: Soldier = members[index].find_nearest_enemy(
			point, _unit_type.effective_range * ADVANCE_MIN_RANGE_FACTOR)
		if too_close == null and _is_spot_free(point, members[index]):
			return point
	return null


## La mejor cobertura frente al enemigo que esté a tiro de él y a no más de advance_leash del
## puesto del soldado, o null si no hay ninguna libre. Prefiere las que quedan más lejos del
## enemigo (al límite del alcance) y descarta las que le acercarían demasiado a cualquier enemigo.
func _advance_cover_point(index: int, spot: Vector2, enemy_position: Vector2, reach: float) -> Variant:
	var best: Variant = null
	var best_score: float = -INF
	var min_enemy_distance: float = _unit_type.effective_range * ADVANCE_MIN_RANGE_FACTOR
	for node in get_tree().get_nodes_in_group("cover"):
		var cover: CoverObject = node
		if cover.global_position.distance_to(spot) > _unit_type.advance_leash + 40.0:
			continue
		var threat_dir: Vector2 = (enemy_position - cover.global_position).normalized()
		for point in cover.cover_points(threat_dir):
			var travel: float = spot.distance_to(point)
			var to_target: float = point.distance_to(enemy_position)
			if travel > _unit_type.advance_leash or to_target > reach:
				continue
			var closest_enemy: Soldier = members[index].find_nearest_enemy(point, min_enemy_distance)
			if closest_enemy != null:
				continue  # demasiado cerca de algún enemigo
			# Cuanto más se acerca al enemigo de lo necesario, peor.
			var score: float = cover.cover_type.protection - travel / 400.0 - (reach - to_target) / 150.0
			if score > best_score and _is_valid_stand_point(point) and _is_spot_free(point, members[index]):
				best = point
				best_score = score
	return best


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


## Elige los puntos de despliegue de la escuadra en su tramo del frente:
## 1) primero, puestos a cubierto (detrás de rocas, árboles, sacos...) frente a la dirección facing;
## 2) los que no encuentren cobertura se dispersan de forma irregular por el tramo.
## Siempre en suelo transitable, fuera de los obstáculos y a distancia mínima de los demás.
func _plan_deployment(destination: Vector2, facing: Vector2, frontage: float, front_center: Vector2,
		front_half_width: float, occupied: Array[Vector2]) -> void:
	var right := Vector2(-facing.y, facing.x)
	var min_spacing: float = _unit_type.deploy_spacing_min
	var count: int = members.size()
	# Profundidad de la zona: la justa para que quepan los soldados con su separación.
	var area_per_soldier: float = pow(min_spacing * 1.4, 2.0)
	var half_depth: float = maxf(14.0, count * area_per_soldier / maxf(frontage, 1.0) / 2.0)
	var chosen_spots: Array[Vector2] = _pick_cover_spots(destination, facing, frontage / 2.0,
		half_depth, count, occupied)
	var open_count: int = count - chosen_spots.size()
	for i in open_count:
		var spacing: float = min_spacing
		var chosen: Vector2 = destination
		var placed: bool = false
		while not placed:
			for attempt in DEPLOY_ATTEMPTS:
				# Cada soldado se reparte en su franja del tramo, con azar dentro de ella.
				var lateral: float = ((i + _rng.randf()) / open_count - 0.5) * frontage
				var depth: float = _rng.randf_range(-half_depth, half_depth)
				var candidate: Vector2 = destination + right * lateral - facing * depth
				if _is_valid_stand_point(candidate) and _far_from_all(candidate, occupied, spacing):
					chosen = candidate
					placed = true
					break
			spacing *= 0.85
			if spacing < 4.0:
				placed = true
		occupied.append(chosen)
		chosen_spots.append(chosen)
	_spots = PackedVector2Array()
	_spot_facings = PackedVector2Array()
	for spot in chosen_spots:
		_spots.append(spot)
		# Abanico: cuanto más a un lado del frente, más mira hacia ese lado.
		var side_t: float = clampf((spot - front_center).dot(right) / maxf(front_half_width, 1.0), -1.0, 1.0)
		var angle: float = deg_to_rad(side_t * _unit_type.sector_spread_degrees + _rng.randf_range(-6.0, 6.0))
		_spot_facings.append(facing.rotated(angle))


## Puestos a cubierto frente a facing dentro del tramo (ampliado con cover_search_distance),
## de mejor a peor: más protección y más cerca de la línea del frente. Como mucho max_count.
func _pick_cover_spots(destination: Vector2, facing: Vector2, half_width: float, half_depth: float,
		max_count: int, occupied: Array[Vector2]) -> Array[Vector2]:
	var right := Vector2(-facing.y, facing.x)
	var margin: float = _unit_type.cover_search_distance
	var candidates: Array[Array] = []
	for node in get_tree().get_nodes_in_group("cover"):
		var cover: CoverObject = node
		var offset: Vector2 = cover.global_position - destination
		if absf(offset.dot(right)) > half_width + margin or absf(offset.dot(facing)) > half_depth + margin:
			continue
		for point in cover.cover_points(facing):
			var forward: float = (point - destination).dot(facing)
			if forward > COVER_MAX_FORWARD and _in_enemy_range(point):
				continue  # obligaría a meterse por delante de la línea, a tiro del enemigo
			var score: float = cover.cover_type.protection - absf(forward) / 400.0
			candidates.append([point, score])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	var result: Array[Vector2] = []
	for candidate in candidates:
		if result.size() >= max_count:
			break
		var point: Vector2 = candidate[0]
		if _is_valid_stand_point(point) and _far_from_all(point, occupied, _unit_type.deploy_spacing_min):
			occupied.append(point)
			result.append(point)
	return result


## true si algún enemigo vivo tiene point dentro de su alcance.
func _in_enemy_range(point: Vector2) -> bool:
	return members[0].find_nearest_enemy(point, _unit_type.weapon_range) != null


## Un soldado puede ponerse en point si es suelo transitable y no está dentro de un obstáculo.
func _is_valid_stand_point(point: Vector2) -> bool:
	if _map_ready():
		if NavigationServer2D.map_get_closest_point(_map(), point).distance_to(point) > 1.0:
			return false
	for node in get_tree().get_nodes_in_group("cover"):
		var cover: CoverObject = node
		if cover.distance_to_point(point) < 4.0:
			return false
	return true


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
