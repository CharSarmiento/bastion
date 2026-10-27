extends Node2D
## Escena de batalla: ajusta la cámara a los límites del mapa y crea la barra de órdenes.

@onready var _ground: TileMapLayer = $Ground
@onready var _camera: BattleCamera = $BattleCamera
@onready var _selection_manager: SelectionManager = $SelectionManager


func _ready() -> void:
	var used: Rect2i = _ground.get_used_rect()
	var tile_size := Vector2(_ground.tile_set.tile_size)
	var bounds := Rect2(Vector2(used.position) * tile_size, Vector2(used.size) * tile_size)
	_camera.set_bounds(bounds)
	var order_bar := OrderBar.new()
	order_bar.name = "OrderBar"
	order_bar.selection_manager = _selection_manager
	add_child(order_bar)
