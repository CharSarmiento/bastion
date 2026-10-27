class_name OrderBar
extends CanvasLayer
## Barra de órdenes abajo en el centro de la pantalla. Solo se ve con alguna compañía
## seleccionada. Cada botón prepara una orden para el siguiente clic derecho; el botón
## iluminado es la orden que se dará. Cada orden tiene también su atajo de teclado.

## [orden, texto del botón]. Las órdenes nuevas (retirada, mantener posición) irán aquí.
const BUTTONS: Array[Array] = [
	[SelectionManager.Order.MOVE, "Mover  ·  clic dcho"],
	[SelectionManager.Order.BOUND, "Saltos  ·  Ctrl"],
	[SelectionManager.Order.ADVANCE, "Avanzar  ·  Alt"],
	[SelectionManager.Order.RETREAT, "Retirada  ·  Mayús"],
]
const BOTTOM_MARGIN := 12

var selection_manager: SelectionManager

var _panel: PanelContainer
## Orden -> botón.
var _buttons: Dictionary = {}
## Interruptor "Mantener posición": encendido si toda la selección lo tiene activado.
var _hold_button: Button


func _ready() -> void:
	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_top = -BOTTOM_MARGIN
	_panel.offset_bottom = -BOTTOM_MARGIN
	anchor.add_child(_panel)
	var row := HBoxContainer.new()
	_panel.add_child(row)
	for entry in BUTTONS:
		var order: SelectionManager.Order = entry[0]
		var button := Button.new()
		button.text = entry[1]
		button.toggle_mode = true
		# Sin foco: así las teclas (Ctrl, Alt, espacio...) no activan los botones.
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_button_pressed.bind(order))
		row.add_child(button)
		_buttons[order] = button
	row.add_child(VSeparator.new())
	_hold_button = Button.new()
	_hold_button.text = "Mantener posición  ·  H"
	_hold_button.toggle_mode = true
	_hold_button.focus_mode = Control.FOCUS_NONE
	_hold_button.pressed.connect(func() -> void: selection_manager.toggle_hold())
	row.add_child(_hold_button)


func _process(_delta: float) -> void:
	_panel.visible = selection_manager != null and selection_manager.has_selection()
	if not _panel.visible:
		return
	for order: SelectionManager.Order in _buttons:
		var button: Button = _buttons[order]
		button.set_pressed_no_signal(order == selection_manager.armed_order)
	_hold_button.set_pressed_no_signal(selection_manager.selection_holds())


func _on_button_pressed(order: SelectionManager.Order) -> void:
	selection_manager.arm(order)
