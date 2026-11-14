extends Control
## OPERACION: ULTIMA ORBITA - escena orbital del MVP.
## Estacion modular en orbita terrestre. Datos externos usados de verdad:
##   - NASA GIBS: la Tierra que se ve es una imagen satelital real (MODIS Terra) sobre una esfera.
##   - NASA DONKI: el evento solar del dia 3 sale de una llamarada/CME/tormenta real (o, sin datos,
##     de un escenario rotulado SIMULACION EDUCATIVA).
##   - Space Data Center: pantalla con fuentes, fechas, estados y etiquetas.
## La red nunca bloquea el juego: todo se carga en segundo plano.
##
## Pruebas:  godot --path <proyecto> -- --shot=C:/x.png [--day=3] [--offline]

signal data_loaded
signal _event_ready

const DAYS := 7
const EVENT_DAY := 3
const ACTIONS_PER_TURN := 2
const KEYS := ["oxigeno", "energia", "comida", "blindaje", "comunicacion"]
const NAMES := {"oxigeno": "Oxígeno", "energia": "Energía", "comida": "Comida", "blindaje": "Blindaje", "comunicacion": "Comunicación"}
const COLORS := {"oxigeno": Color("3fd0ff"), "energia": Color("ffc23d"), "comida": Color("5fd85f"), "blindaje": Color("4f8dff"), "comunicacion": Color("9fd8ff")}

const ICONS := {"oxigeno": "O₂", "energia": "⚡", "comida": "🍎", "blindaje": "🛡", "comunicacion": "📡"}
const C_BG := Color("02040c")
const C_PANEL := Color("0a1838")
const C_BORDER := Color("2f6fd6")
const C_TEXT := Color("e8f1ff")
const C_MUTED := Color("8fa8d0")

var res := {"oxigeno": 85.0, "energia": 70.0, "comida": 90.0, "blindaje": 80.0, "comunicacion": 100.0}
var day := 1
var ap := GameSettings.actions_per_turn()
var _reinforced := false
var _event_sev_used := 0
var event: Dictionary = {}
var event_loaded := false
var game_over := false
var outcome := ""   # "EXITO" o "FALLO: motivo" (lo usa la simulacion de pruebas)

var _t := 0.0
var _stars: Array = []
var _earth: ColorRect
var _station: Control
var _bars: Dictionary = {}
var _vals: Dictionary = {}
var _day_label: Label
var _ap_label: Label
var _weather: Label
var _weather_src: Label
var _earth_caption: Label
var _flash := 0.0
var _modal_root: Control
var _action_buttons: Array = []
var _end_button: Button
var _center_open := false
var _earth_loaded := false
var _event_shown := false
var _event_resolved_for_test := false
var _simulated := false   # true en GameSim: no guarda logros


func _ready() -> void:
	randomize()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--day="):
			day = clampi(int(a.substr(6)), 1, DAYS)
	for i in 160:
		_stars.append([Vector2(randf() * 1280.0, randf() * 720.0), randf_range(0.6, 1.8), randf_range(0.35, 1.0)])
	_build_ui()
	_refresh_hud()
	_fade_in()
	_load_data()
	_start_day(true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			if not (event_loaded and _earth_loaded):
				await data_loaded
			await get_tree().create_timer(1.2).timeout
			get_viewport().get_texture().get_image().save_png(a.substr(7))
			get_tree().quit()


func _process(delta: float) -> void:
	_t += delta
	_earth.material.set_shader_parameter("rot", _t * 0.04)
	_flash = maxf(0.0, _flash - delta * 0.8)
	_station.queue_redraw()


# ------------------------------------------------------------ DATOS REALES ----

func _load_data() -> void:
	_load_earth()
	_load_event()


func _load_earth() -> void:
	var r: Dictionary = await EarthImageryManager.get_earth("modis_truecolor")
	if r.get("ok", false):
		_earth.material.set_shader_parameter("earth", r["texture"])
		_earth.material.set_shader_parameter("has_tex", true)
		var how := "caché local" if r["from_cache"] else "NASA GIBS"
		_earth_caption.text = "Tierra real · MODIS Terra · %s · %s" % [r["image_date"], r["classification"]]
		_earth_caption.tooltip_text = how
	else:
		_earth_caption.text = "Tierra: imagen real no disponible (%s). Se muestra una esfera genérica." % r.get("error", "sin conexión")
	_earth_loaded = true
	_check_loaded()


func _load_event() -> void:
	event = await ScientificDataManager.build_solar_event()
	event_loaded = true
	_event_ready.emit()
	_update_weather()
	_check_loaded()
	# Archivo DONKI 2025-2026 en segundo plano (por tramos de 30 dias, con cache).
	ScientificDataManager.history_progress.connect(func(done: int, total: int) -> void:
		if not ScientificDataManager.history_loaded:
			_weather_src.text = "NASA DONKI · archivo 2025-2026: %d%%" % int(100.0 * done / total))
	await ScientificDataManager.ensure_history()
	if not _event_shown:
		event = await ScientificDataManager.build_solar_event()
	_update_weather()


func _update_weather() -> void:
	var rec: Dictionary = event.get("record", {})
	var sev := int(rec.get("severity", 0))
	if event["is_fallback"]:
		_weather.text = "Clima Espacial: sin datos"
		_weather.add_theme_color_override("font_color", Color("b07cff"))
		_weather_src.text = "SIMULACIÓN EDUCATIVA"
	else:
		var alert: bool = sev >= 2 and event["classification"] == ScientificDataManager.LABEL_REAL
		_weather.text = "Clima Espacial: " + ("Alerta" if alert else "Normal")
		_weather.add_theme_color_override("font_color", Color("ff6b5b") if alert else Color("5fe08a"))
		_weather_src.text = "NASA DONKI · %s" % event["classification"]
		if ScientificDataManager.history_loaded:
			_weather_src.text += " · archivo 2025-26"


func _check_loaded() -> void:
	if event_loaded and _earth_loaded:
		data_loaded.emit()


# --------------------------------------------------------------- JUEGO ----

func _start_day(first := false) -> void:
	ap = GameSettings.actions_per_turn()
	_refresh_hud()
	if day == EVENT_DAY and not game_over:
		_show_event_decision()


func _action(kind: String) -> void:
	if ap <= 0 or game_over or _modal_root != null:
		return
	match kind:
		"aire": _add("oxigeno", 14.0); _add("energia", -8.0); _toast("+14 Oxígeno   −8 Energía", COLORS["oxigeno"])
		"cultivo": _add("comida", 14.0); _add("energia", -6.0); _toast("+14 Comida   −6 Energía", COLORS["comida"])
		"blindaje": _add("blindaje", 12.0); _add("energia", -8.0); _toast("+12 Blindaje   −8 Energía", COLORS["blindaje"])
		"paneles": _add("energia", 12.0); _toast("+12 Energía", COLORS["energia"])
	ap -= 1
	_refresh_hud()


## Aviso flotante que sube y se desvanece (retroalimentacion de cada accion).
func _toast(text: String, col: Color) -> void:
	var l := _lbl(text, 18, col, false)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.position = Vector2(560, 600)
	l.z_index = 5
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", 540.0, 1.1)
	tw.tween_property(l, "modulate:a", 0.0, 1.1).set_delay(0.5)
	tw.chain().tween_callback(l.queue_free)


func _fade_in() -> void:
	var f := ColorRect.new()
	f.color = Color.BLACK
	f.set_anchors_preset(Control.PRESET_FULL_RECT)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.z_index = 100
	add_child(f)
	var tw := create_tween()
	tw.tween_property(f, "color:a", 0.0, 0.7)
	tw.tween_callback(f.queue_free)


func _end_turn() -> void:
	if game_over or _modal_root != null:
		return
	var f := GameSettings.consumption_factor()
	_add("oxigeno", -8.0 * f)
	_add("comida", -7.0 * f)
	_add("energia", -8.0 * f)
	_add("blindaje", -2.0 * f)
	var reason := _failure()
	if reason != "":
		_finish(false, reason)
		return
	day += 1
	if day > DAYS:
		_finish(true, "")
		return
	_start_day()


func _failure() -> String:
	if res["oxigeno"] <= 0.0: return "Se agotó el oxígeno de la estación."
	if res["energia"] <= 0.0: return "La estación se quedó sin energía: los sistemas vitales se apagaron."
	if res["comida"] <= 0.0: return "Se acabó la comida de la tripulación."
	if res["blindaje"] <= 0.0: return "El blindaje se agotó y la radiación alcanzó a la tripulación."
	if res["comunicacion"] <= 0.0: return "Se perdió el contacto con el control de misión."
	return ""


func _add(key: String, amount: float) -> void:
	res[key] = clampf(res[key] + amount, 0.0, 100.0)


# ---------------------------------------------------------- EVENTO SOLAR ----

func _event_severity() -> int:
	if event.get("is_fallback", true):
		return 2   # escenario de practica, rotulado como simulacion
	return int(event["record"].get("severity", 0))


func _show_event_decision() -> void:
	if not event_loaded:
		await _event_ready
	_event_shown = true
	var sev := _event_severity()
	var v := _modal("DECISIÓN IMPORTANTE", Color("ffd24d"), 700)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	head.add_child(_sun_icon())
	var title := "Tormenta solar en camino" if sev >= 2 else "Actividad solar detectada"
	head.add_child(_lbl(title, 22, Color("ffb15c"), true, true))
	head.add_child(_badge(event["classification"]))
	var src := "Escenario de práctica (sin datos de NASA disponibles)." if event["is_fallback"] else "Según NASA DONKI: " + str(event["record"]["title"]) + " (" + Time.get_date_string_from_unix_time(int(event["record"]["event_time"])) + ")."
	v.add_child(_lbl(src + " La radiación puede aumentar en las próximas horas. ¿Qué hacemos?", 15, C_TEXT, true))
	var choice := {"v": ""}
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var b1 := _choice("Reforzar el blindaje", "Cuesta 20% de energía.\nReduce mucho el daño por radiación.", Color("2f7de0"))
	var b2 := _choice("Ahorrar energía", "No gastas energía.\nAsumes mayor riesgo de daños.", Color("e0a02f"))
	row.add_child(b1)
	row.add_child(b2)
	var ok := _button("Confirmar", Color("1f9f55"), Callable())
	ok.disabled = true
	var pick := func(which: String) -> void:
		choice["v"] = which
		ok.disabled = false
		b1.button_pressed = which == "reforzar"
		b2.button_pressed = which == "ahorrar"
	b1.pressed.connect(pick.bind("reforzar"))
	b2.pressed.connect(pick.bind("ahorrar"))
	ok.pressed.connect(func() -> void: _resolve_event(choice["v"] == "reforzar"))
	v.add_child(ok)


func _resolve_event(reinforce: bool) -> void:
	var sev := _event_severity()
	_reinforced = reinforce
	_event_sev_used = sev
	var effects: PackedStringArray = []
	if reinforce:
		_add("energia", -20.0)
		_add("blindaje", -(2.0 + 3.0 * sev))
		_add("comunicacion", -(1.0 * sev))
		effects.append("Energía −20%%, blindaje −%d%%, comunicación −%d%%." % [int(2 + 3 * sev), sev])
	else:
		_add("blindaje", -(10.0 + 22.0 * sev))
		_add("comunicacion", -(5.0 + 15.0 * sev))
		_add("energia", -(3.0 * sev))
		effects.append("Blindaje −%d%%, comunicación −%d%%, energía −%d%%." % [int(10 + 22 * sev), int(5 + 15 * sev), int(3 * sev)])
	_flash = 1.0
	_refresh_hud()
	_show_real_data(reinforce, " ".join(effects))


func _show_real_data(reinforce: bool, effects: String) -> void:
	var v := _modal("EVENTO: DATO REAL DE LA NASA" if not event["is_fallback"] else "EVENTO: SIMULACIÓN EDUCATIVA", Color("ffd24d"), 760)
	v.add_child(_badge(event["classification"]))
	v.add_child(_lbl(event["explanation"], 15, C_TEXT, true))
	if not event["is_fallback"]:
		var rec: Dictionary = event["record"]
		if str(rec.get("link", "")) != "":
			var lk := LinkButton.new()
			lk.text = "Ver el registro original en NASA DONKI"
			lk.uri = rec["link"]
			lk.add_theme_color_override("font_color", Color("6fb4ff"))
			v.add_child(lk)
	var ctx := ScientificDataManager.history_summary()
	if ctx != "":
		v.add_child(_lbl("Contexto 2025–2026: " + ctx, 13, C_MUTED, true))
	v.add_child(_lbl("Resultado de tu decisión: " + effects, 15, Color("ffd9a0"), true))
	var tip := "Consejo: un blindaje adecuado reduce los riesgos para tu equipo." if reinforce \
			else "Consejo: ahorraste energía, pero sin blindaje la radiación daña más tus sistemas."
	var tipbox := PanelContainer.new()
	tipbox.add_theme_stylebox_override("panel", _box(Color("2a2410"), Color("e0b02f"), 2, 8))
	tipbox.add_child(_lbl("💡 " + tip, 15, Color("ffe08a"), true))
	v.add_child(tipbox)
	v.add_child(_button("Continuar", Color("1f6fd0"), _close_modal))


# --------------------------------------------------------------- FINAL ----

func _finish(success: bool, reason: String) -> void:
	game_over = true
	outcome = "EXITO" if success else "FALLO: " + reason
	if not _simulated:
		Progress.record_game(success, GameSettings.mode, _reinforced, _event_sev_used)
	if success:
		var v := _modal("¡MISIÓN EXITOSA!", Color("ffd24d"), 640)
		v.add_child(_lbl("Tu estación sobrevivió %d días y aprendiste sobre los desafíos reales del espacio." % DAYS, 16, C_TEXT, true))
		v.add_child(_lbl("Aprendizajes clave:", 18, Color("ffd24d"), false))
		for t in ["Balancea los recursos", "Protege a tu equipo", "Usa datos reales de la NASA"]:
			v.add_child(_lbl("✔  " + t, 16, Color("7be88a"), false))
		_end_buttons(v, Color("1f9f55"), "Jugar de nuevo")
	else:
		var v := _modal("MISIÓN FALLIDA", Color("ff6b5b"), 640)
		v.add_child(_lbl("La estación no pudo sobrevivir... " + reason, 16, C_TEXT, true))
		v.add_child(_lbl("Quizás el consumo de energía fue muy alto o la radiación fue demasiado fuerte. ¡Inténtalo otra vez!", 15, C_MUTED, true))
		_end_buttons(v, Color("c0392b"), "Intentar de nuevo")


func _end_buttons(v: VBoxContainer, col: Color, retry_text: String) -> void:
	v.add_child(_button(retry_text, col, func() -> void: get_tree().reload_current_scene()))
	v.add_child(_button("Space Data Center", Color("1f6fd0"), _open_data_center))
	v.add_child(_button("Menú principal", Color("245aa8"), _go_menu))


func _go_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


# ----------------------------------------------------------- DATA CENTER ----

func _open_data_center() -> void:
	if _center_open:
		return
	_center_open = true
	Progress.unlock("data_scientist")
	var dc: Control = load("res://scenes/SpaceDataCenter.tscn").instantiate()
	dc.back_requested.connect(func() -> void:
		dc.queue_free()
		_center_open = false)
	add_child(dc)


# ------------------------------------------------------------------ HUD ----

func _refresh_hud() -> void:
	for k in KEYS:
		var v: float = res[k]
		(_bars[k] as ProgressBar).value = v
		(_vals[k] as Label).text = "%d%%" % int(round(v))
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color("ff4d4d") if v < 25.0 else COLORS[k]
		fill.set_corner_radius_all(4)
		(_bars[k] as ProgressBar).add_theme_stylebox_override("fill", fill)
	_day_label.text = "Día %d de %d" % [day, DAYS]
	_ap_label.text = "Acciones: %d" % ap
	for b in _action_buttons:
		(b as Button).disabled = ap <= 0 or game_over


# ------------------------------------------------------------ DIBUJO ----

func _draw_stars() -> void:
	var s := _stars_node
	for st in _stars:
		var a: float = st[2] * (0.75 + 0.25 * sin(_t * 1.5 + st[0].x))
		s.draw_circle(st[0], st[1], Color(1, 1, 1, a))


var _stars_node: Control


func _draw_station() -> void:
	var c := Vector2(0, 0)
	var s := _station
	var bob := Vector2(0, sin(_t * 0.8) * 4.0)
	var hull := Color("cfd8e6")
	var dark := Color("6b7a93")
	var panel := Color("1b4fb0")
	var panel_l := Color("4f8dff")
	# Resplandor suave alrededor de la estacion
	s.draw_circle(c + bob, 125.0, Color(0.3, 0.55, 1.0, 0.04))
	s.draw_circle(c + bob, 75.0, Color(0.45, 0.7, 1.0, 0.06))
	# Armazon principal
	s.draw_rect(Rect2(c + bob + Vector2(-190, -5), Vector2(380, 10)), dark)
	s.draw_rect(Rect2(c + bob + Vector2(-9, -95), Vector2(18, 190)), dark)
	# Paneles solares
	for sx in [-1, 1]:
		for i in 2:
			var x: float = sx * (110.0 + i * 78.0) - 30.0
			var r := Rect2(c + bob + Vector2(x, -118), Vector2(60, 100))
			var r2 := Rect2(c + bob + Vector2(x, 18), Vector2(60, 100))
			for rr in [r, r2]:
				s.draw_rect(rr, panel)
				s.draw_rect(rr, panel_l, false, 2.0)
				for g in range(1, 4):
					s.draw_line(rr.position + Vector2(0, g * 25.0), rr.position + Vector2(60, g * 25.0), panel_l.darkened(0.3), 1.0)
				s.draw_line(rr.position + Vector2(30, 0), rr.position + Vector2(30, 100), panel_l.darkened(0.3), 1.0)
	# Modulos
	for off in [Vector2(-60, 0), Vector2(60, 0)]:
		s.draw_rect(Rect2(c + bob + off + Vector2(-26, -16), Vector2(52, 32)), hull)
		s.draw_rect(Rect2(c + bob + off + Vector2(-26, -16), Vector2(52, 32)), dark, false, 2.0)
	s.draw_rect(Rect2(c + bob + Vector2(-16, -58), Vector2(32, 36)), hull)
	s.draw_rect(Rect2(c + bob + Vector2(-16, 22), Vector2(32, 36)), hull)
	# Ventanas iluminadas en los modulos
	for off in [Vector2(-60, 0), Vector2(60, 0)]:
		for i in 3:
			s.draw_rect(Rect2(c + bob + off + Vector2(-17 + i * 12, -6), Vector2(8, 10)), Color("ffe9a8"))
	# Antena parabolica
	s.draw_line(c + bob + Vector2(0, -95), c + bob + Vector2(0, -112), dark, 3.0)
	s.draw_arc(c + bob + Vector2(0, -112), 15.0, PI * 1.05, PI * 1.95, 14, hull, 3.0)
	# Luces de navegacion intermitentes
	if sin(_t * 4.0) > 0.0:
		s.draw_circle(c + bob + Vector2(-190, 0), 5.0, Color("ff4d4d"))
		s.draw_circle(c + bob + Vector2(190, 0), 5.0, Color("4dff88"))
	# Cupula central (centro de comandos)
	s.draw_circle(c + bob, 30.0, Color("aab8cf"))
	s.draw_arc(c + bob, 30.0, 0, TAU, 40, dark, 3.0)
	s.draw_circle(c + bob + Vector2(-8, -8), 11.0, Color("7fd0ff", 0.8))
	# Escudo de radiacion
	var shield: float = res["blindaje"] / 100.0
	if shield > 0.02:
		var col := Color("55c8ff", 0.10 + 0.35 * shield)
		if _flash > 0.0:
			col = Color("ff6b5b", 0.25 + 0.5 * _flash)
		s.draw_arc(c + bob, 170.0, 0, TAU, 72, col, 3.0 + 3.0 * _flash)


# ------------------------------------------------------------------- UI ----

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_stars_node = Control.new()
	_stars_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stars_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stars_node.draw.connect(_draw_stars)
	add_child(_stars_node)
	var timer := Timer.new()
	timer.wait_time = 0.1
	timer.autostart = true
	timer.timeout.connect(_stars_node.queue_redraw)
	add_child(timer)

	_earth = ColorRect.new()
	_earth.position = Vector2(380, 330)
	_earth.size = Vector2(1000, 1000)
	_earth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/earth_sphere.gdshader")
	_earth.material = mat
	add_child(_earth)

	_station = Control.new()
	_station.position = Vector2(640, 250)
	_station.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_station.draw.connect(_draw_station)
	add_child(_station)

	# HUD izquierdo: recursos
	var hud := PanelContainer.new()
	hud.position = Vector2(14, 72)
	hud.custom_minimum_size = Vector2(230, 0)
	hud.add_theme_stylebox_override("panel", _box(Color(0.04, 0.09, 0.22, 0.88), C_BORDER, 2, 10))
	add_child(hud)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 8)
	hud.add_child(hv)
	for k in KEYS:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		hv.add_child(row)
		var top := HBoxContainer.new()
		row.add_child(top)
		var n := _lbl("%s  %s" % [ICONS[k], NAMES[k]], 15, COLORS[k], false)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(n)
		_vals[k] = _lbl("", 15, C_TEXT, false)
		top.add_child(_vals[k])
		var pb := ProgressBar.new()
		pb.custom_minimum_size = Vector2(0, 10)
		pb.show_percentage = false
		pb.max_value = 100.0
		var bgs := StyleBoxFlat.new()
		bgs.bg_color = Color("14213f")
		bgs.set_corner_radius_all(4)
		pb.add_theme_stylebox_override("background", bgs)
		row.add_child(pb)
		_bars[k] = pb

	# Cabecera: mision y dia
	var mission := PanelContainer.new()
	mission.position = Vector2(300, 12)
	mission.custom_minimum_size = Vector2(380, 0)
	mission.add_theme_stylebox_override("panel", _box(Color(0.04, 0.09, 0.22, 0.9), C_BORDER, 2, 12))
	add_child(mission)
	var mv := VBoxContainer.new()
	mv.alignment = BoxContainer.ALIGNMENT_CENTER
	mission.add_child(mv)
	var mt := _lbl("MISIÓN ACTUAL: OPERACIÓN ÚLTIMA ÓRBITA", 15, Color("ffd24d"), false)
	mt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(mt)
	_day_label = _lbl("", 17, C_TEXT, false)
	_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(_day_label)

	var title := _lbl("%s · ESTACIÓN ORBITAL" % GameSettings.mode_label().to_upper(), 13, C_MUTED, false)
	title.position = Vector2(16, 8)
	add_child(title)
	var menu_btn := _button("☰ Menú", Color("245aa8"), _go_menu)
	menu_btn.position = Vector2(16, 28)
	menu_btn.custom_minimum_size = Vector2(90, 32)
	add_child(menu_btn)

	# Derecha: clima espacial, objetivo, data center
	var right := VBoxContainer.new()
	right.position = Vector2(950, 12)
	right.custom_minimum_size = Vector2(316, 0)
	right.add_theme_constant_override("separation", 8)
	add_child(right)
	var wp := PanelContainer.new()
	wp.add_theme_stylebox_override("panel", _box(Color(0.04, 0.09, 0.22, 0.9), C_BORDER, 2, 10))
	right.add_child(wp)
	var wv := VBoxContainer.new()
	wp.add_child(wv)
	_weather = _lbl("Clima Espacial: consultando…", 15, C_MUTED, false)
	wv.add_child(_weather)
	_weather_src = _lbl("NASA DONKI", 12, C_MUTED, false)
	wv.add_child(_weather_src)
	right.add_child(_button("Space Data Center", Color("1f6fd0"), _open_data_center))
	var obj := PanelContainer.new()
	obj.add_theme_stylebox_override("panel", _box(Color(0.04, 0.09, 0.22, 0.9), Color("e0b02f"), 2, 10))
	right.add_child(obj)
	var ov := VBoxContainer.new()
	obj.add_child(ov)
	ov.add_child(_lbl("★ Objetivo:", 15, Color("ffd24d"), false))
	var ol := _lbl("Mantén la estación funcionando por %d días." % DAYS, 14, C_TEXT, true)
	ol.custom_minimum_size = Vector2(280, 0)
	ov.add_child(ol)

	_earth_caption = _lbl("Cargando imagen real de la Tierra…", 12, C_MUTED, true)
	_earth_caption.position = Vector2(14, 640)
	_earth_caption.custom_minimum_size = Vector2(380, 0)
	add_child(_earth_caption)

	# Acciones y fin de turno
	var bar := HBoxContainer.new()
	bar.position = Vector2(300, 656)
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)
	_ap_label = _lbl("", 15, Color("ffd24d"), false)
	_ap_label.custom_minimum_size = Vector2(110, 0)
	_ap_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(_ap_label)
	for a in [["Reciclar aire", "aire", "Oxígeno +14, energía −8"], ["Cultivar", "cultivo", "Comida +14, energía −6"],
			["Reparar blindaje", "blindaje", "Blindaje +12, energía −8"], ["Orientar paneles", "paneles", "Energía +12"]]:
		var b := _button(a[0], Color("245aa8"), _action.bind(a[1]))
		b.tooltip_text = a[2]
		b.custom_minimum_size = Vector2(120, 40)
		_action_buttons.append(b)
		bar.add_child(b)
	_end_button = _button("Finalizar Turno ▶▶", Color("1f9f55"), _end_turn)
	_end_button.custom_minimum_size = Vector2(170, 40)
	bar.add_child(_end_button)


## Icono del Sol dibujado en codigo (ilustracion, no es una imagen de datos).
func _sun_icon() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(72, 72)
	c.draw.connect(func() -> void:
		var ctr := Vector2(36, 36)
		for i in 6:
			c.draw_circle(ctr, 34.0 - i * 3.0, Color(1.0, 0.45 + i * 0.07, 0.1, 0.12 + i * 0.1))
		c.draw_circle(ctr, 17.0, Color("ffd24d"))
		for k in 12:
			var a := TAU * k / 12.0 + _t * 0.4
			c.draw_line(ctr + Vector2.from_angle(a) * 22.0, ctr + Vector2.from_angle(a) * 33.0, Color("ffb13d"), 2.0))
	var timer := Timer.new()
	timer.wait_time = 0.05
	timer.autostart = true
	timer.timeout.connect(c.queue_redraw)
	c.add_child(timer)
	return c


func _modal(title: String, title_col: Color, width: int) -> VBoxContainer:
	_close_modal()
	_modal_root = Control.new()
	_modal_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_modal_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	panel.add_theme_stylebox_override("panel", _box(Color("0a1838"), C_BORDER, 3, 14))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var t := _lbl(title, 26, title_col, false)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	return v


func _close_modal() -> void:
	if _modal_root != null:
		_modal_root.queue_free()
		_modal_root = null


func _lbl(text: String, size: int, col: Color, wrap: bool, expand := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if expand:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if wrap:
		l.custom_minimum_size = Vector2(300, 0)
	return l


func _badge(label: String) -> Label:
	var col := Color("7b8798")
	match label:
		ScientificDataManager.LABEL_REAL: col = Color("2ecc71")
		ScientificDataManager.LABEL_HISTORIC: col = Color("f1b434")
		ScientificDataManager.LABEL_SIM: col = Color("b07cff")
	var l := _lbl(" %s " % label, 13, col, false)
	l.add_theme_stylebox_override("normal", _box(col.darkened(0.55), col, 2, 12))
	return l


func _button(text: String, col: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 38)
	for st in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(st, _box(col if st == "normal" else col.lightened(0.15), col.lightened(0.4), 2, 8))
	b.add_theme_stylebox_override("disabled", _box(Color("1a2438"), Color("2a3550"), 2, 8))
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


func _choice(title: String, desc: String, col: Color) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.text = "%s\n\n%s" % [title, desc]
	b.custom_minimum_size = Vector2(0, 120)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_stylebox_override("normal", _box(Color("0f2150"), col.darkened(0.2), 2, 10))
	b.add_theme_stylebox_override("hover", _box(Color("17327a"), col, 2, 10))
	b.add_theme_stylebox_override("pressed", _box(col.darkened(0.55), col.lightened(0.3), 4, 10))
	return b


func _box(bg: Color, border: Color, w: int, r: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(w)
	s.set_corner_radius_all(r)
	s.set_content_margin_all(10)
	return s
