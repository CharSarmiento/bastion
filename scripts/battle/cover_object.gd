class_name CoverObject
extends Sprite2D
## Objeto del mapa que da cobertura (roca, árbol, sacos terreros...).
## Protege a un soldado que está pegado a él cuando queda entre el soldado y quien le dispara.

## Distancia máxima (px) entre el borde del objeto y el soldado para que le cubra.
const COVER_REACH := 18.0
## Separación entre el borde del objeto y el punto donde se coloca un soldado.
const STAND_OFFSET := 10.0
## Giro (grados) de los puntos alternativos alrededor de un objeto redondo.
const ALTERNATIVE_ANGLE := 25.0
## Transparencia de la copa con soldados debajo, y cada cuánto se comprueba (segundos).
const FADED_ALPHA := 0.45
const FADE_CHECK_INTERVAL := 0.2
const FADE_SPEED := 4.0

@export var cover_type: CoverType

## CIRCLE: radio del obstáculo. LINE: medio grosor.
var radius: float = 16.0
## Solo LINE: media longitud.
var half_length: float = 0.0
## Radio de la copa (todo el sprite), para saber si hay soldados debajo.
var _canopy_radius: float = 0.0
var _fade_timer: float = 0.0
var _target_alpha: float = 1.0


func _enter_tree() -> void:
	# En _enter_tree y no en _ready: así las compañías ya lo encuentran al desplegarse
	# al empezar la batalla, aunque este nodo esté más abajo en la escena.
	add_to_group("cover")
	var size: Vector2 = texture.get_size() * scale.abs() if texture else Vector2(32.0, 32.0)
	if cover_type.shape == CoverType.Shape.CIRCLE:
		radius = cover_type.fixed_radius if cover_type.fixed_radius > 0.0 \
			else minf(size.x, size.y) / 2.0 * cover_type.size_factor
	else:
		half_length = size.x / 2.0 * cover_type.size_factor
		radius = size.y / 2.0
	_canopy_radius = minf(size.x, size.y) / 2.0 * 0.9
	set_process(cover_type.fade_when_units_below)


func _process(delta: float) -> void:
	_fade_timer -= delta
	if _fade_timer <= 0.0:
		_fade_timer = FADE_CHECK_INTERVAL
		_target_alpha = 1.0
		for node in get_tree().get_nodes_in_group("soldiers"):
			var soldier: Node2D = node
			if soldier.global_position.distance_to(global_position) < _canopy_radius:
				_target_alpha = FADED_ALPHA
				break
	modulate.a = move_toward(modulate.a, _target_alpha, FADE_SPEED * delta)


## Distancia desde point hasta el borde del obstáculo (negativa si está dentro).
func distance_to_point(point: Vector2) -> float:
	if cover_type.shape == CoverType.Shape.CIRCLE:
		return point.distance_to(global_position) - radius
	var ends: PackedVector2Array = _line_ends()
	return point.distance_to(Geometry2D.get_closest_point_to_segment(point, ends[0], ends[1])) - radius


## Protección (0-1) que da a un soldado en target frente a un disparo hecho desde shooter.
func protection_for(target: Vector2, shooter: Vector2) -> float:
	if distance_to_point(target) > COVER_REACH:
		return 0.0
	if shooter.distance_to(global_position) >= shooter.distance_to(target):
		return 0.0  # el objeto está detrás del soldado, no delante
	if cover_type.shape == CoverType.Shape.CIRCLE:
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(global_position, shooter, target)
		return cover_type.protection if closest.distance_to(global_position) <= radius else 0.0
	var ends: PackedVector2Array = _line_ends()
	var crossing: Variant = Geometry2D.segment_intersects_segment(shooter, target, ends[0], ends[1])
	return cover_type.protection if crossing != null else 0.0


## Puntos donde ponerse a cubierto de una amenaza que está en la dirección threat_dir
## (vector desde el soldado hacia el enemigo). Puede devolver una lista vacía.
func cover_points(threat_dir: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	var away: Vector2 = -threat_dir.normalized()
	if cover_type.shape == CoverType.Shape.CIRCLE:
		var distance: float = radius + STAND_OFFSET
		points.append(global_position + away * distance)
		points.append(global_position + away.rotated(deg_to_rad(ALTERNATIVE_ANGLE)) * distance)
		points.append(global_position + away.rotated(deg_to_rad(-ALTERNATIVE_ANGLE)) * distance)
		return points
	# Objeto alargado: solo sirve si la amenaza viene más o menos de frente a su cara larga.
	var axis: Vector2 = Vector2.RIGHT.rotated(global_rotation)
	var normal: Vector2 = axis.orthogonal()
	if absf(normal.dot(away)) < 0.4:
		return points
	if normal.dot(away) < 0.0:
		normal = -normal
	var base: Vector2 = global_position + normal * (radius + STAND_OFFSET)
	for k in [-0.6, 0.0, 0.6]:
		points.append(base + axis * half_length * k)
	return points


func _line_ends() -> PackedVector2Array:
	var axis: Vector2 = Vector2.RIGHT.rotated(global_rotation)
	return PackedVector2Array([global_position - axis * half_length, global_position + axis * half_length])
