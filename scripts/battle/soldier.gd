class_name Soldier
extends Node2D
## Un soldado: camina hacia el puesto que le asigna su escuadra y mira hacia donde va.
## No calcula rutas propias salvo pequeños rodeos; la ruta la calcula su escuadra.
## Parado, vigila su sector y de vez en cuando mira un poco a un lado.
## Combate por su cuenta: busca al enemigo más cercano a tiro, gira el torso y dispara.
## Las piernas miran hacia donde camina y el torso (con el fusil) hacia donde apunta,
## así puede disparar en marcha (con peor puntería).

## Avisa a su compañía cuando muere.
signal died(soldier: Soldier)

## Velocidad de giro, en radianes por segundo.
const TURN_SPEED := 8.0
## Velocidad de giro al mirar alrededor estando parado (más tranquila).
const LOOK_TURN_SPEED := 3.0
## A menos de esta distancia (píxeles) del puesto se considera que ha llegado.
const ARRIVE_DISTANCE := 2.0
## A partir de esta distancia mira hacia donde camina; más cerca, hacia donde mira la formación.
const FACE_MOVEMENT_DISTANCE := 8.0
## Velocidad (px/s) a la que la animación de andar se reproduce a su ritmo normal.
const WALK_ANIM_REFERENCE_SPEED := 70.0
const SELECTION_COLOR := Color(0.45, 1.0, 0.45, 0.9)
## Color del círculo de selección cuando está a cubierto frente al enemigo.
const SELECTION_COVERED_COLOR := Color(0.45, 0.85, 1.0, 0.95)
## Distancia del punto imaginario desde el que se comprueba la cobertura cuando no hay enemigo
## a tiro (se usa la dirección hacia la que vigila).
const COVER_CHECK_DISTANCE := 200.0
## Cada cuánto (segundos) comprueba si el camino recto a su puesto está libre.
const PATH_CHECK_INTERVAL := 0.2
## Distancia entre los puntos que se comprueban a lo largo del camino recto.
const PATH_CHECK_STEP := 12.0
## Cada cuánto (segundos) busca un nuevo objetivo.
const TARGET_CHECK_INTERVAL := 0.5
## Solo dispara si está girado hacia el objetivo con menos de este error (grados).
const AIM_TOLERANCE_DEGREES := 10.0
## Lo máximo que puede girar el torso respecto a las piernas (grados).
const MAX_TORSO_TWIST_DEGREES := 110.0
## Posición de la boca del fusil respecto al centro, con el sprite mirando hacia abajo.
const MUZZLE_OFFSET := Vector2(-3.0, 15.0)
## Tiempo que se muestra la pose de disparo (con fogonazo).
const SHOT_POSE_DURATION := 0.08
const HIT_FLASH_COLOR := Color(1.0, 0.45, 0.45)
const HIT_FLASH_DURATION := 0.12
## Material que tiñe el uniforme de los enemigos (compartido por todos).
const ENEMY_TINT_SHADER := preload("res://scenes/battle/team_tint.gdshader")

static var _enemy_material: ShaderMaterial

## Textura del cuerpo en el momento de disparar (incluye el fogonazo).
@export var shot_texture: Texture2D

## Ficha de su unidad (vida, alcance, puntería...). La asigna su compañía.
var unit_type: UnitType
## Bando (Formation.Team). Lo asigna su compañía antes de añadirlo a la escena.
var team: int = Formation.Team.PLAYER
var health: float = 100.0
## Velocidad máxima; la escuadra la ajusta para que pueda alcanzar su puesto.
var max_speed: float = 100.0
var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()

var _dead: bool = false
## true si está a cubierto frente a su objetivo (o frente a donde vigila). Para el indicador.
var _covered: bool = false
var _slot: Vector2
var _slot_facing: Vector2 = Vector2.DOWN
var _facing: Vector2 = Vector2.DOWN
## Dirección del torso y el fusil (puede diferir de las piernas al disparar en marcha).
var _aim: Vector2 = Vector2.DOWN
## Rodeo hasta el puesto cuando el camino recto pasa por agua u otra zona no transitable.
var _detour: PackedVector2Array = PackedVector2Array()
var _path_check_timer: float
## Giro (radianes) de la mirada ocasional hacia un lado, y tiempo hasta el siguiente cambio.
var _glance_angle: float = 0.0
var _glance_timer: float
var _target: Soldier = null
var _target_timer: float
var _fire_cooldown: float
var _shot_pose_timer: float = 0.0
var _hit_flash_timer: float = 0.0
var _body_texture: Texture2D
var _effects: BattleEffects = null

@onready var _visual: Node2D = $Visual
@onready var _legs: AnimatedSprite2D = $Visual/Legs
@onready var _body: Sprite2D = $Visual/Body
@onready var _death: AnimatedSprite2D = $Visual/Death


func _ready() -> void:
	add_to_group("soldiers")
	_slot = global_position
	_body_texture = _body.texture
	if unit_type:
		health = unit_type.soldier_health
		_fire_cooldown = randf_range(0.0, unit_type.fire_interval_max)
	# Momentos iniciales aleatorios para que no todos hagan lo mismo en el mismo frame.
	_path_check_timer = randf() * PATH_CHECK_INTERVAL
	_target_timer = randf() * TARGET_CHECK_INTERVAL
	_glance_timer = randf_range(3.0, 7.0)
	if team == Formation.Team.ENEMY:
		if _enemy_material == null:
			_enemy_material = ShaderMaterial.new()
			_enemy_material.shader = ENEMY_TINT_SHADER
		_visual.material = _enemy_material
		for sprite: CanvasItem in [_legs, _body, _death]:
			sprite.use_parent_material = true
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
	_aim = facing
	_apply_facing()


## Puesto hacia el que camina (o en el que está).
func target_slot() -> Vector2:
	return _slot


func distance_to_slot() -> float:
	return global_position.distance_to(_slot)


func is_alive() -> bool:
	return not _dead


## Protección (0-1) que le da la cobertura que tenga pegada frente a un disparo desde shooter.
## Si varias cubren a la vez, cuenta la mejor.
func cover_protection_from(shooter: Vector2) -> float:
	var best: float = 0.0
	for node in get_tree().get_nodes_in_group("cover"):
		var cover: CoverObject = node
		best = maxf(best, cover.protection_for(global_position, shooter))
	return best


## El enemigo al que está disparando ahora mismo, o null si no tiene ninguno a tiro.
func current_target() -> Soldier:
	return _target if unit_type and _has_target() else null


## El enemigo vivo más cercano a point dentro de max_distance, o null si no hay ninguno.
func find_nearest_enemy(point: Vector2, max_distance: float) -> Soldier:
	var best: Soldier = null
	var best_distance: float = max_distance
	for node in get_tree().get_nodes_in_group("soldiers"):
		var other: Soldier = node
		if other.team == team or not other.is_alive():
			continue
		var distance: float = point.distance_to(other.global_position)
		if distance <= best_distance:
			best = other
			best_distance = distance
	return best


func take_damage(amount: float) -> void:
	if _dead:
		return
	health -= amount
	_hit_flash_timer = HIT_FLASH_DURATION
	_visual.modulate = HIT_FLASH_COLOR
	if health <= 0.0:
		_die()


func _physics_process(delta: float) -> void:
	_update_effect_timers(delta)
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
	var walking: bool = distance > ARRIVE_DISTANCE
	if walking:
		# Frena al acercarse al puesto para no pasarse ni temblar.
		var speed: float = minf(max_speed, slot_distance * 6.0)
		global_position += to_goal / distance * minf(speed * delta, distance)
		_turn_toward(to_goal if slot_distance > FACE_MOVEMENT_DISTANCE else _slot_facing, TURN_SPEED, delta)
		_legs.play("walk")
		_legs.speed_scale = speed / WALK_ANIM_REFERENCE_SPEED
	else:
		if _has_target():
			_turn_toward(_target.global_position - global_position, TURN_SPEED, delta)
		else:
			_update_glance(delta)
			_turn_toward(_slot_facing.rotated(_glance_angle), LOOK_TURN_SPEED, delta)
		if _legs.is_playing():
			_legs.stop()
			_legs.frame = 0
	_update_aim(delta)
	_apply_facing()
	_update_combat(delta, walking)


# --- Combate ---

func _update_combat(delta: float, walking: bool) -> void:
	if unit_type == null:
		return
	_target_timer -= delta
	if _target_timer <= 0.0:
		_target_timer = TARGET_CHECK_INTERVAL
		_target = find_nearest_enemy(global_position, unit_type.weapon_range)
		_update_covered()
	if not _has_target():
		_target = null
	_fire_cooldown -= delta
	if _target == null or _fire_cooldown > 0.0:
		return
	# Solo dispara con el fusil apuntando al objetivo.
	var to_target: Vector2 = _target.global_position - global_position
	if absf(angle_difference(_aim.angle(), to_target.angle())) > deg_to_rad(AIM_TOLERANCE_DEGREES):
		return
	_fire_at(_target, walking)
	_fire_cooldown = randf_range(unit_type.fire_interval_min, unit_type.fire_interval_max)
	if walking:
		_fire_cooldown *= unit_type.moving_fire_interval_factor


## Para el indicador: ¿está a cubierto frente a su objetivo o, si no tiene, frente a donde vigila?
func _update_covered() -> void:
	var threat: Vector2 = global_position + _slot_facing * COVER_CHECK_DISTANCE
	if _has_target():
		threat = _target.global_position
	var covered: bool = cover_protection_from(threat) > 0.0
	if covered != _covered:
		_covered = covered
		queue_redraw()


## El torso gira hacia el objetivo (sin pasar del giro máximo respecto a las piernas);
## sin objetivo, vuelve a mirar al frente.
func _update_aim(delta: float) -> void:
	var aim_goal: float = _facing.angle()
	if _has_target():
		var to_target: Vector2 = _target.global_position - global_position
		var max_twist: float = deg_to_rad(MAX_TORSO_TWIST_DEGREES)
		aim_goal += clampf(angle_difference(_facing.angle(), to_target.angle()), -max_twist, max_twist)
	_aim = Vector2.from_angle(rotate_toward(_aim.angle(), aim_goal, TURN_SPEED * delta))


func _has_target() -> bool:
	return is_instance_valid(_target) and _target.is_alive() \
		and global_position.distance_to(_target.global_position) <= unit_type.weapon_range * 1.1


func _fire_at(target: Soldier, walking: bool) -> void:
	var distance: float = global_position.distance_to(target.global_position)
	var hit_chance: float = unit_type.accuracy * clampf(1.0 - 0.6 * distance / unit_type.weapon_range, 0.2, 1.0)
	if walking:
		hit_chance *= unit_type.moving_accuracy_factor
	hit_chance *= 1.0 - target.cover_protection_from(global_position)
	var hit: bool = randf() < hit_chance
	var impact: Vector2 = target.global_position
	if not hit:
		impact += Vector2.from_angle(randf() * TAU) * randf_range(10.0, 28.0)
	if _effects == null:
		_effects = get_tree().get_first_node_in_group("battle_effects")
	if _effects:
		_effects.add_tracer(_body.to_global(MUZZLE_OFFSET), impact)
	if shot_texture:
		_body.texture = shot_texture
		_shot_pose_timer = SHOT_POSE_DURATION
	if hit:
		target.take_damage(unit_type.damage)


func _update_effect_timers(delta: float) -> void:
	if _shot_pose_timer > 0.0:
		_shot_pose_timer -= delta
		if _shot_pose_timer <= 0.0:
			_body.texture = _body_texture
	if _hit_flash_timer > 0.0:
		_hit_flash_timer -= delta
		if _hit_flash_timer <= 0.0:
			_visual.modulate = Color.WHITE


func _die() -> void:
	_dead = true
	selected = false
	remove_from_group("soldiers")
	set_physics_process(false)
	_visual.modulate = Color.WHITE
	_legs.hide()
	_body.hide()
	_death.show()
	_death.play("die")
	# El cuerpo pasa a la capa de caídos (debajo de los vivos). Se hace al final del frame
	# porque ahora mismo se está procesando el disparo que lo ha matado. Se programa antes de
	# avisar a la compañía para que, si era el último, el cuerpo se salve antes de que ella desaparezca.
	_become_corpse.call_deferred()
	died.emit(self)


func _become_corpse() -> void:
	var corpses: Node = get_tree().get_first_node_in_group("corpses")
	if corpses:
		reparent(corpses)


# --- Movimiento ---

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
		var color: Color = SELECTION_COVERED_COLOR if _covered else SELECTION_COLOR
		draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 24, color, 1.5)


## Cada 3-7 s mira un poco a un lado durante 1-2 s y luego vuelve a su sector.
func _update_glance(delta: float) -> void:
	_glance_timer -= delta
	if _glance_timer > 0.0:
		return
	if _glance_angle == 0.0:
		_glance_angle = deg_to_rad(randf_range(10.0, 25.0)) * (1.0 if randf() < 0.5 else -1.0)
		_glance_timer = randf_range(1.0, 2.0)
	else:
		_glance_angle = 0.0
		_glance_timer = randf_range(3.0, 7.0)


func _turn_toward(direction: Vector2, turn_speed: float, delta: float) -> void:
	if direction.length_squared() < 0.0001:
		return
	var angle: float = rotate_toward(_facing.angle(), direction.angle(), turn_speed * delta)
	_facing = Vector2.from_angle(angle)


func _apply_facing() -> void:
	# Los sprites del pack miran hacia abajo (+Y); por eso se resta PI / 2.
	_visual.rotation = _facing.angle() - PI / 2.0
	# El torso gira aparte, respecto a las piernas.
	_body.rotation = angle_difference(_facing.angle(), _aim.angle())
