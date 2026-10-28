class_name BattleOutcome
extends CanvasLayer
## Decide quién gana: un bando pierde cuando todas sus compañías han muerto o están huyendo.
## Al terminar, tras unos segundos para ver el final, pausa el juego y muestra el resultado:
## bajas de cada bando, huidos, compañías perdidas y tiempo, con botones Reintentar y Salir.
## Lleva la cuenta desde el principio de la batalla (las compañías tienen que existir ya).

## Cada cuánto (segundos) se comprueba si la batalla ha terminado.
const CHECK_INTERVAL := 0.5
## Segundos entre el final de la batalla y la pantalla de resultado.
const RESULT_DELAY := 2.0
const VICTORY_COLOR := Color(0.45, 1.0, 0.45)
const DEFEAT_COLOR := Color(1.0, 0.4, 0.35)
const TEAMS: Array[int] = [Formation.Team.PLAYER, Formation.Team.ENEMY]

## true cuando la batalla ha terminado; victory dice si ha ganado el jugador.
var finished: bool = false
var victory: bool = false

## Por bando: soldados y compañías al empezar, soldados huidos y compañías perdidas.
var _start_soldiers: Dictionary = {}
var _start_companies: Dictionary = {}
var _fled_soldiers: Dictionary = {}
var _lost_companies: Dictionary = {}
var _elapsed: float = 0.0
var _check_timer: float = 0.0
var _result_timer: float = 0.0
var _panel: PanelContainer


func _ready() -> void:
	layer = 10
	# Sigue funcionando (sus botones) con el juego en pausa.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for team in TEAMS:
		_start_soldiers[team] = 0
		_start_companies[team] = 0
		_fled_soldiers[team] = 0
		_lost_companies[team] = 0
	for formation in Formation.all:
		_start_soldiers[formation.team] += formation.soldiers.size()
		_start_companies[formation.team] += 1
		formation.soldier_fled.connect(_on_soldier_fled)
		formation.company_lost.connect(_on_company_lost)


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	if finished:
		_result_timer -= delta
		if _result_timer <= 0.0:
			_show_result()
		return
	_elapsed += delta
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = CHECK_INTERVAL
	var player_defeated: bool = _is_defeated(Formation.Team.PLAYER)
	var enemy_defeated: bool = _is_defeated(Formation.Team.ENEMY)
	if player_defeated or enemy_defeated:
		finished = true
		# Si caen los dos bandos a la vez, cuenta como derrota.
		victory = enemy_defeated and not player_defeated
		_result_timer = RESULT_DELAY


## Un bando está derrotado si no le queda ninguna compañía en la batalla (las que huyen no cuentan).
func _is_defeated(team: int) -> bool:
	if _start_companies[team] == 0:
		return false  # en esta batalla no hay compañías de ese bando
	for formation in Formation.all:
		if formation.team == team and formation.is_in_battle():
			return false
	return true


func _on_soldier_fled(formation: Formation) -> void:
	_fled_soldiers[formation.team] += 1


func _on_company_lost(formation: Formation, _fled: bool) -> void:
	_lost_companies[formation.team] += 1


## Soldados del bando que han muerto: los del principio menos los vivos y los huidos.
func _casualties(team: int) -> int:
	return _start_soldiers[team] - Soldier.alive_in_team(team).size() - _fled_soldiers[team]


## Compañías perdidas: sin soldados o huyendo (aunque aún no hayan salido del mapa).
func _companies_lost(team: int) -> int:
	var lost: int = _lost_companies[team]
	for formation in Formation.all:
		if formation.team == team and not formation.soldiers.is_empty() \
				and formation.morale_state == Formation.Morale.FLEEING:
			lost += 1
	return lost


func _show_result() -> void:
	if _panel != null:
		return
	get_tree().paused = true
	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(anchor)
	# Oscurece el campo de batalla y bloquea los clics.
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anchor.add_child(shade)
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	anchor.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	var title := Label.new()
	title.text = "VICTORIA" if victory else "DERROTA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", VICTORY_COLOR if victory else DEFEAT_COLOR)
	column.add_child(title)

	var time := Label.new()
	time.text = "Duración: %d:%02d" % [floori(_elapsed / 60.0), int(_elapsed) % 60]
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(time)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 28)
	column.add_child(grid)
	var rows: Array[Array] = [
		["", "Tus tropas", "Enemigo"],
		["Soldados caídos", str(_casualties(Formation.Team.PLAYER)), str(_casualties(Formation.Team.ENEMY))],
		["Soldados huidos", str(_fled_soldiers[Formation.Team.PLAYER]), str(_fled_soldiers[Formation.Team.ENEMY])],
		["Compañías perdidas",
			"%d de %d" % [_companies_lost(Formation.Team.PLAYER), _start_companies[Formation.Team.PLAYER]],
			"%d de %d" % [_companies_lost(Formation.Team.ENEMY), _start_companies[Formation.Team.ENEMY]]],
	]
	for row in rows:
		for k in row.size():
			var cell := Label.new()
			cell.text = row[k]
			if k > 0:
				cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			grid.add_child(cell)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	column.add_child(buttons)
	var retry := Button.new()
	retry.text = "Reintentar"
	retry.pressed.connect(_on_retry_pressed)
	buttons.add_child(retry)
	var quit := Button.new()
	quit.text = "Salir"
	quit.pressed.connect(func() -> void: get_tree().quit())
	buttons.add_child(quit)


func _on_retry_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
