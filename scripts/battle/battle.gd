extends Node2D
## Escena de batalla. En este paso solo ajusta la cámara a los límites del mapa.

@onready var _ground: TileMapLayer = $Ground
@onready var _camera: BattleCamera = $BattleCamera


func _ready() -> void:
	var used: Rect2i = _ground.get_used_rect()
	var tile_size := Vector2(_ground.tile_set.tile_size)
	var bounds := Rect2(Vector2(used.position) * tile_size, Vector2(used.size) * tile_size)
	_camera.set_bounds(bounds)
