extends Control
## OPERACION: REFUGIO LUNAR - base lunar jugable (3 dias, 9 turnos).
## Los 14 modulos son interactivos: al elegir uno ves su funcion, estado, consumo, produccion y
## las tareas que puedes asignar. Todas las tareas gastan los 3 presupuestos compartidos
## (energia, materiales, horas) definidos en BaseState.
##
## Pruebas: godot --path <proyecto> res://scenes/LunarBase.tscn -- --shot=x.png [--turn=5] [--module=greenhouse] [--skip-intro]

signal data_loaded

const MAP_POS := Vector2(250, 110)
const MOON_CENTER := Vector2(110, 500)   # la Luna al fondo, a la izquierda; la base orbita a su derecha
const MOON_RADIUS := 215.0
const ORBIT_R := 600.0
## Medidores de la izquierda: [id, icono, nombre, color del disco]. Solo 6, grandes y claros.
const METERS := [
	["vida", "💨", "Oxígeno", Color("4fc3f7")], ["agua", "💧", "Agua", Color("4f8dff")], ["energia", "⚡", "Energía", Color("ffc83d")],
	["alimentos", "🍎", "Comida", Color("ff7a6b")], ["proteccion", "🛡️", "Protección", Color("3ddc84")], ["materiales", "🧱", "Materiales", Color("c9a46a")],
]
const SHORT := {"habitat": "Hábitat", "dorms": "Dormir", "common": "Común", "lab": "Laboratorio", "life_support": "Soporte vital",
		"greenhouse": "Invernadero", "fertilization": "Abono", "infirmary": "Salud", "command": "Mando", "main_energy": "Energía",
		"backup_energy": "Respaldo", "shelter": "Refugio", "panels": "Paneles", "processing": "Materiales"}
const INDICATORS := [
	["vida", "💨", "Aire"], ["proteccion", "🛡️", "Escudo"], ["energia", "⚡", "Energía"], ["alimentos", "🍎", "Comida"]]
const PHASE_NAMES := ["inicio del día", "mitad del día", "final del día"]

var s: BaseState
var plan := {"led": 1, "tasks": []}
var selected := ""
var hover := ""
var _t := 0.0
var _world: Control
var _map: Control
var _earth: ColorRect
var _night: ColorRect
var _sbcache := {}
var _stars: Array = []
var _moon: ColorRect
var _turn_dots: Control
var _tutorial: TutorialGuide
var _module_panel: Control
var _mission_panel: Control
var _happy_until := 0   # ms: el robot esta contento hasta este momento
var _alerts: AlertDirector      # genera las alertas espaciales (null en las pruebas automaticas)
var _alert_ui: AlertOverlay
var _alert_open := false
var _modal_root: Control
var _ind_rows := {}
var _budget := {}
var _title_label: Label
var _phase_label: Label
var _banner: Label
var _tip: Label
var _module_box: VBoxContainer
var _end_btn: Button
var _warn: Label
var _earth_loaded := false
var _event_loaded := false
var _moon_tex: Texture2D
var _moon_note := ""
var _tip_idx := 0
var _event_locked := false
var _simulated := false   # true en las pruebas automaticas: no guarda logros
var _extra_label: Label
var _risk_panel: PanelContainer
var _risk_box: VBoxContainer
var _ui := {}             # id -> {node, def}: paneles y botones movibles/ocultables
var _move_mode := false
var _overlays := {}
var _settings_root: Control
var _robot_hop := 0.0
var _last_tip := ""
var _info_open := false
var _moon_done := false
var _intro_pending := false


func _ready() -> void:
	randomize()
	var mdef: MissionDef = MissionManager.current
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mission="):   # solo para pruebas: elegir mision sin pasar por el menu
			var forced := MissionManager.get_mission(a.substr(10))
			if forced != null:
				mdef = forced
				MissionManager.current = forced
	NasaBridge.forced_min = mdef.alert_tier_min
	s = BaseState.new(GameSettings.mode == "principiante", mdef)
	if not _simulated:
		MissionManager.begin_run()
	plan["led"] = s.led
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--turn="):
			s.turn = clampi(int(a.substr(7)), 1, s.turns)
	_gen_terrain()
	_build_ui()
	_load_data()
	_refresh_all()
	var skip := "--skip-intro" in OS.get_cmdline_user_args()
	# Alertas espaciales en tiempo real: solo en partida real (no en pruebas automaticas ni con --noalerts).
	if not _simulated and not ("--noalerts" in OS.get_cmdline_user_args()):
		_alerts = AlertDirector.new(s)
	if not _simulated and not ("--notutorial" in OS.get_cmdline_user_args()):
		_build_tutorial()
	_begin_turn(skip)
	if _tutorial != null:
		_tutorial.notify("start")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--alert="):   # solo para pruebas: forzar una alerta concreta
			var forced_ev := SpaceEvents.by_id(a.substr(8))
			if not forced_ev.is_empty():
				_show_space_alert(AlertDirector.instance(forced_ev, AlertDirector.difficulty_level(s), s.easy))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--module="):
			_select(a.substr(9))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			if not (_earth_loaded and _event_loaded):
				await data_loaded
			await get_tree().create_timer(1.3).timeout
			get_viewport().get_texture().get_image().save_png(a.substr(7))
			get_tree().quit()


func _process(delta: float) -> void:
	_t += delta
	if _earth:
		_earth.material.set_shader_parameter("rot", _t * 0.01)
	if _moon:
		_moon.material.set_shader_parameter("rot", _t * 0.004)
	_map.queue_redraw()
	# Alertas: el reloj solo corre cuando el jugador esta planificando (sin ventanas abiertas).
	if _alerts != null and not _alert_open and _modal_root == null and not _intro_pending and not s.finished \
			and (_settings_root == null or not is_instance_valid(_settings_root)):
		var ev: Dictionary = _alerts.tick(delta, s)
		if not ev.is_empty():
			_show_space_alert(ev)
	# El robot salta cuando cambia su mensaje; el boton de turno late cuando se puede pulsar.
	if _tip.text != _last_tip:
		_last_tip = _tip.text
		_robot_hop = 1.0
	_robot_hop = maxf(0.0, _robot_hop - delta * 3.0)
	if not _end_btn.disabled and _modal_root == null:
		var k := 0.93 + 0.07 * sin(_t * 3.2)
		_end_btn.modulate = Color(k, k, k)
	else:
		_end_btn.modulate = Color.WHITE


# ------------------------------------------------------------ DATOS NASA ----

func _load_data() -> void:
	_load_earth()
	_load_moon()
	_load_event()


func _load_earth() -> void:
	var r: Dictionary = await EarthImageryManager.get_earth("modis_truecolor")
	if r.get("ok", false):
		_earth.material.set_shader_parameter("earth", r["texture"])
		_earth.material.set_shader_parameter("has_tex", true)
		(_earth.get_meta("cap") as Label).text = "Tierra real · NASA GIBS · %s" % r["image_date"]
	_earth_loaded = true
	_check_loaded()


func _load_moon() -> void:
	var r: Dictionary = await EarthImageryManager.get_earth("lro_wac")
	if r.get("ok", false):
		_moon_tex = r["texture"]
		if _moon != null:
			_moon.material.set_shader_parameter("earth", _moon_tex)
			_moon.material.set_shader_parameter("has_tex", true)
		_moon_note = "Imagen real de la Luna · mosaico LRO WAC · NASA Moon Trek"
	_moon_done = true


## Espera (maximo 5 s) a la imagen de la Luna para mostrarla en la presentacion.
func _wait_moon() -> void:
	var t0 := Time.get_ticks_msec()
	while not _moon_done and Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame


func _load_event() -> void:
	NasaBridge.event = await ScientificDataManager.build_solar_event()
	_event_loaded = true
	_check_loaded()
	_refresh_module_panel()


func _check_loaded() -> void:
	if _earth_loaded and _event_loaded:
		data_loaded.emit()


# ---------------------------------------------------------------- TERRENO ----

## La base esta en orbita alrededor de la Luna: fondo de espacio con estrellas por toda la pantalla.
func _gen_terrain() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20262026
	for i in 260:
		_stars.append([Vector2(rng.randf() * 1280.0, rng.randf() * 720.0), rng.randf_range(0.6, 1.9), rng.randf_range(0.3, 1.0)])


func _draw_world() -> void:
	var w := _world
	# Espacio profundo: degradado azul marino (mas claro hacia abajo, hacia la Luna).
	for i in 18:
		w.draw_rect(Rect2(0, i * 40.0, 1280, 41), Color("050816").lerp(Color("0d1238"), float(i) / 17.0))
	for st in _stars:
		w.draw_circle(st[0], st[1], Color(1, 1, 1, st[2]))
	# Orbita de la base alrededor de la Luna (linea punteada).
	var moon_c := MOON_CENTER
	var k := -52.0
	while k < 52.0:
		var a0 := deg_to_rad(k)
		var a1 := deg_to_rad(k + 2.2)
		w.draw_line(moon_c + Vector2.from_angle(a0) * ORBIT_R, moon_c + Vector2.from_angle(a1) * ORBIT_R, Color("e8b730", 0.65), 2.5)
		k += 4.4


# --------------------------------------------------------------- MAPA ----

func _sb(col: Color, r: int = 12, border: Color = Color(0.2, 0.25, 0.35)) -> StyleBoxFlat:
	var key := "%s%s%s" % [col.to_html(), r, border.to_html()]
	if not _sbcache.has(key):
		var b := StyleBoxFlat.new()
		b.bg_color = col
		b.border_color = border
		b.set_border_width_all(2)
		b.set_corner_radius_all(r)
		b.shadow_color = Color(0, 0, 0, 0.38)
		b.shadow_size = 7
		b.shadow_offset = Vector2(3, 6)
		_sbcache[key] = b
	return _sbcache[key]


func _status_level(id: String) -> int:
	var v := 100.0
	match id:
		"life_support": v = minf(s.ls_cond, s.indicators()["vida"])
		"greenhouse": v = s.plant_health
		"fertilization": v = s.nutrients
		"shelter": v = 0.5 * s.shield + 0.5 * s.shelter
		"main_energy": v = s.main / SimConfig.MAIN_CAP * 100.0
		"backup_energy": v = s.backup / SimConfig.BACKUP_CAP * 100.0
		"panels": v = 100.0 if s.is_day() else 45.0
		"processing": v = 100.0 if s.materials >= 30.0 else 45.0
		"infirmary", "dorms", "common", "habitat": v = s.health
	return UI.light_of(v)


func _draw_map() -> void:
	var m := _map
	var night := not s.is_day()
	# Corredores
	for c in ModuleDefs.CORRIDORS:
		m.draw_line(c[0], c[1], Color("5d6578"), 14.0)
		m.draw_line(c[0], c[1], Color("aab2c4"), 9.0)
	# Paneles solares (izquierda y derecha)
	var pcol := Color("1b4fb0") if not night else Color("12306b")
	for i in 4:
		var r := Rect2(10 + (i % 2) * 36, 255 + (i / 2) * 62, 30, 54)
		_panel_rect(m, r, pcol)
	m.draw_line(Vector2(80, 315), Vector2(90, 315), Color("5d6578"), 8.0)
	var pr: Rect2 = ModuleDefs.DEFS["panels"]["rect"]
	for i in s.panels:
		var rr := Rect2(pr.position.x + (i % 2) * 44, pr.position.y + (i / 2) * 38, 40, 34)
		_panel_rect(m, rr, pcol)
	# Modulos
	m.draw_style_box(_sb(Color("c9d1e0")), Rect2(160, 298, 70, 34))
	for i in 4:
		m.draw_rect(Rect2(170 + i * 14, 310, 8, 8), Color("ffe9a8"))
	_pod(m, "dorms", Color("d5dbe8"), 4, true)
	_pod(m, "common", Color("d5dbe8"), 5, false)
	_pod(m, "infirmary", Color("eef2f8"), 0, true)
	var ir: Rect2 = ModuleDefs.DEFS["infirmary"]["rect"]
	var ic := ir.get_center()
	m.draw_rect(Rect2(ic.x - 4, ic.y - 14, 8, 28), Color("e84a4a"))
	m.draw_rect(Rect2(ic.x - 14, ic.y - 4, 28, 8), Color("e84a4a"))
	_pod(m, "lab", Color("b9e3ea"), 4, false)
	_life_support(m)
	_greenhouse(m)
	_pod(m, "fertilization", Color("c9d8b4"), 0, false)
	_battery(m, "main_energy", s.main / SimConfig.MAIN_CAP, Color("ffc23d"))
	_battery(m, "backup_energy", s.backup / SimConfig.BACKUP_CAP, Color("4dd6c8"))
	_pod(m, "command", Color("c3c9d8"), 3, false)
	var cr: Rect2 = ModuleDefs.DEFS["command"]["rect"]
	m.draw_arc(cr.position + Vector2(cr.size.x - 18, -2), 14.0, PI * 1.05, PI * 1.95, 14, Color("e8edf7"), 3.0)
	_shelter(m)
	_pod(m, "processing", Color("c9c2b0"), 0, false)
	var pcr: Rect2 = ModuleDefs.DEFS["processing"]["rect"]
	for i in 5:
		m.draw_circle(pcr.position + Vector2(14 + i * 20, 46), 4.0, Color("8a7f68"))
	# Ventilacion (decorativa, pertenece al soporte vital)
	m.draw_style_box(_sb(Color("c9d1e0")), Rect2(190, 350, 70, 70))
	for k in 2:
		var fc := Vector2(212 + k * 28, 385)
		m.draw_circle(fc, 12.0, Color("39425a"))
		var spin := _t * (7.0 if s.ls_cond > 40.0 else 1.5)
		for b in 3:
			var a := spin + TAU * b / 3.0
			m.draw_line(fc, fc + Vector2.from_angle(a) * 11.0, Color("dfe6f5"), 3.0)
	# Seleccion y estado
	for id in ModuleDefs.ORDER:
		var r: Rect2 = ModuleDefs.DEFS[id]["rect"]
		var dot := r.position + Vector2(r.size.x - 6, 6)
		var lv := _status_level(id)
		var pulse_r := 6.0 + (2.5 * (0.5 + 0.5 * sin(_t * 6.0)) if lv == 0 else 0.0)
		m.draw_circle(dot, pulse_r + 2.0, Color(0, 0, 0, 0.55))
		m.draw_circle(dot, pulse_r, UI.light_color(lv))
		if lv == 0:
			m.draw_circle(dot, pulse_r + 6.0, Color(1.0, 0.3, 0.3, 0.18))
		if id == hover and id != selected:
			m.draw_rect(r.grow(5), Color(1, 1, 1, 0.8), false, 2.0)
	if selected != "":
		var sr: Rect2 = ModuleDefs.DEFS[selected]["rect"]
		var pulse := 0.6 + 0.4 * sin(_t * 5.0)
		m.draw_rect(sr.grow(6), Color(1.0, 0.85, 0.3, pulse), false, 4.0)
	# Robot constructor y astronautas
	_rover(m)
	_astronauts(m)


func _panel_rect(m: Control, r: Rect2, col: Color) -> void:
	m.draw_rect(r, col)
	m.draw_rect(r, Color("4f8dff"), false, 2.0)
	m.draw_line(r.position + Vector2(r.size.x * 0.5, 0), r.position + Vector2(r.size.x * 0.5, r.size.y), Color("4f8dff", 0.6), 1.0)
	m.draw_line(r.position + Vector2(0, r.size.y * 0.5), r.position + Vector2(r.size.x, r.size.y * 0.5), Color("4f8dff", 0.6), 1.0)


func _pod(m: Control, id: String, col: Color, windows: int, vertical: bool) -> void:
	var r: Rect2 = ModuleDefs.DEFS[id]["rect"]
	m.draw_style_box(_sb(col), r)
	m.draw_rect(Rect2(r.position + Vector2(8, 4), Vector2(r.size.x - 16, 3)), Color(1, 1, 1, 0.5))   # brillo superior
	for i in windows:
		var wp: Vector2
		if vertical:
			wp = Vector2(r.position.x + r.size.x * 0.5 - 4, r.position.y + 12 + i * (r.size.y - 24) / maxf(1.0, windows))
		else:
			wp = Vector2(r.position.x + 12 + i * (r.size.x - 24) / maxf(1.0, windows), r.position.y + 10)
		if not s.is_day():
			m.draw_circle(wp + Vector2(4, 4), 9.0, Color(1.0, 0.85, 0.4, 0.22))
		m.draw_rect(Rect2(wp, Vector2(8, 8)), Color("ffe9a8"))


func _life_support(m: Control) -> void:
	var r: Rect2 = ModuleDefs.DEFS["life_support"]["rect"]
	m.draw_style_box(_sb(Color("cfd8e6"), 16), r)
	var fill := s.o2 / 100.0
	var inner := Rect2(r.position + Vector2(12, 16), r.size - Vector2(24, 32))
	m.draw_rect(inner, Color("1a2338"))
	m.draw_rect(Rect2(inner.position.x, inner.end.y - inner.size.y * fill, inner.size.x, inner.size.y * fill), Color("3fd0ff"))


func _greenhouse(m: Control) -> void:
	var r: Rect2 = ModuleDefs.DEFS["greenhouse"]["rect"]
	var base_y := r.end.y
	var pts := PackedVector2Array()
	for k in 21:
		var a := PI * k / 20.0
		pts.append(Vector2(r.position.x + r.size.x * 0.5 - cos(a) * r.size.x * 0.5, base_y - sin(a) * r.size.y))
	m.draw_colored_polygon(pts, Color(0.45, 0.8, 0.5, 0.45))
	var glow: float = [0.0, 0.15, 0.3][s.led]
	if glow > 0.0:
		m.draw_colored_polygon(pts, Color(1.0, 0.9, 0.5, glow))
	m.draw_polyline(pts, Color("d3f0d5"), 3.0)
	m.draw_rect(Rect2(r.position.x, base_y - 4, r.size.x, 8), Color("aab2c4"))
	var col := Color(0.3, 0.8, 0.3).lerp(Color(0.6, 0.55, 0.2), 1.0 - s.plant_health / 100.0)
	for i in s.beds:
		var px := r.position.x + 12 + i * (r.size.x - 24) / maxf(1.0, s.beds - 1.0 + 0.001) if s.beds > 1 else r.get_center().x
		m.draw_circle(Vector2(px, base_y - 14), 8.0 + s.plant_health * 0.04, col)
		m.draw_line(Vector2(px, base_y - 4), Vector2(px, base_y - 14), Color("3d7a3d"), 2.0)


func _battery(m: Control, id: String, level: float, col: Color) -> void:
	var r: Rect2 = ModuleDefs.DEFS[id]["rect"]
	m.draw_style_box(_sb(Color("b7bfcf"), 8), r)
	var inner := Rect2(r.position + Vector2(8, 8), r.size - Vector2(16, 16))
	m.draw_rect(inner, Color("1a2338"))
	m.draw_rect(Rect2(inner.position, Vector2(inner.size.x * clampf(level, 0.0, 1.0), inner.size.y)), col)


func _shelter(m: Control) -> void:
	var r: Rect2 = ModuleDefs.DEFS["shelter"]["rect"]
	m.draw_style_box(_sb(Color("9a9aa3"), 10), r)
	var mound_h := 10.0 + s.shield * 0.55
	var pts := PackedVector2Array()
	for k in 25:
		var a := PI * k / 24.0
		pts.append(Vector2(r.get_center().x - cos(a) * (r.size.x * 0.55), r.end.y - sin(a) * mound_h))
	m.draw_colored_polygon(pts, Color("7d8497"))   # blindaje: crece con el nivel de proteccion
	m.draw_polyline(pts, Color("b4bccf"), 2.0)
	var door := Color("4dd6c8") if s.shelter > 50.0 else Color("f1b434")
	m.draw_rect(Rect2(r.get_center().x - 9, r.end.y - 22, 18, 22), door.darkened(0.2))


func _rover(m: Control) -> void:
	var busy: bool = ("process" in plan["tasks"]) or ("build_shield" in plan["tasks"]) or ("expand_bed" in plan["tasks"]) \
			or ("build_shelter" in plan["tasks"]) or ("expand_panel" in plan["tasks"])
	var speed := 1.0 if busy else 0.25
	var f := fmod(_t * 0.18 * speed + 0.0, 1.0)
	var tri := 1.0 - absf(f * 2.0 - 1.0)
	# Dron de construccion que flota entre modulos (en orbita no hay suelo por donde rodar).
	var a := Vector2(420, 520)
	var b := Vector2(560, 520)
	var p := a.lerp(b, tri) + Vector2(0, sin(_t * 2.0) * 3.0)
	m.draw_style_box(_sb(Color("e0b94a"), 6), Rect2(p.x - 14, p.y - 12, 28, 14))
	m.draw_rect(Rect2(p.x - 6, p.y - 20, 14, 9), Color("aab2c4"))
	m.draw_circle(p + Vector2(0, -15), 2.5, Color("4dd6c8"))
	for sx in [-1.0, 1.0]:
		m.draw_rect(Rect2(p.x + sx * 12 - 3, p.y + 2, 6, 4), Color("39425a"))
		m.draw_colored_polygon(PackedVector2Array([p + Vector2(sx * 12 - 2, 6), p + Vector2(sx * 12 + 2, 6), p + Vector2(sx * 12, 12 + (4.0 if busy else 1.0))]), Color("ffb347", 0.85))
	if busy:
		m.draw_line(p + Vector2(14, -8), p + Vector2(24, -16 + sin(_t * 8.0) * 3.0), Color("e0b94a"), 3.0)


func _astronauts(m: Control) -> void:
	var alert := s.turn == s.alert_turn and s.alert_tier > 0
	for i in 3:
		var p: Vector2
		if alert:
			p = Vector2(250 + i * 22, 520) + Vector2(0, sin(_t * 3.0 + i) * 1.5)   # en el refugio
		else:
			var f := fmod(_t * 0.07 + i * 0.33, 1.0)
			var tri := 1.0 - absf(f * 2.0 - 1.0)
			p = Vector2(250, 385).lerp(Vector2(330, 385), tri) if i == 0 else (Vector2(240, 305).lerp(Vector2(330, 305), tri) if i == 1 else Vector2(520, 392).lerp(Vector2(430, 392), tri))
			p.y += sin(_t * 6.0 + i) * 1.5
		m.draw_style_box(_sb(Color("f2f5fa"), 6, Color("9aa5bd")), Rect2(p.x - 7, p.y - 10, 14, 19))
		m.draw_rect(Rect2(p.x - 3, p.y - 3, 6, 4), Color("2f6fd6"))
		m.draw_circle(p + Vector2(0, -15), 8.0, Color("f2f5fa"))
		m.draw_circle(p + Vector2(0, -15), 5.5, Color("1a2338"))
		m.draw_circle(p + Vector2(-2, -17), 1.8, Color(0.6, 0.85, 1.0, 0.8))


func _map_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var id := ModuleDefs.module_at((ev as InputEventMouseMotion).position)
		if id != hover:
			hover = id
			_map.tooltip_text = ModuleDefs.DEFS[id]["name"] if id != "" else ""
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var id := ModuleDefs.module_at((ev as InputEventMouseButton).position)
		if id != "":
			_select(id)


# ------------------------------------------------------------- PANEL DE MODULO ----

func _select(id: String) -> void:
	selected = id
	_refresh_module_panel()
	if _tutorial != null:
		_tutorial.notify("select")
		_tutorial.notify("select:" + id)


func _toggle_task(tid: String) -> void:
	if tid in s.forced_tasks:
		return
	var tasks: Array = plan["tasks"]
	if tid in tasks:
		tasks.erase(tid)
	else:
		tasks.append(tid)
	_say_task(tid)
	_refresh_all()
	if _tutorial != null and tid in plan["tasks"]:
		_tutorial.notify("task")


func _say_task(tid: String) -> void:
	var tips := {
		"build_shield": "Más blindaje protege a tu equipo, pero utiliza materiales.",
		"expand_bed": "Más camas dan más comida, pero piden luz, agua y cuidados.",
		"research": "Investigar sirve, pero quita tiempo al mantenimiento.",
		"process": "El robot saca materiales del regolito, pero gasta energía.",
		"maintain_ls": "Cuidar el soporte vital evita fallos del aire.",
		"tend": "Plantas cuidadas dan más comida.",
	}
	if tips.has(tid):
		_tip.text = tips[tid]


func _set_led(level: int) -> void:
	if s.forced_led >= 0:
		return
	plan["led"] = level
	_tip.text = ["Sin luz, las plantas casi no crecen.", "Luz normal: equilibrio entre comida y energía.",
			"Más luz ayuda a tus plantas, pero consume energía."][level]
	_refresh_all()


func _refresh_module_panel() -> void:
	for c in _module_box.get_children():
		c.queue_free()
	if selected == "":
		var hint := UI.lbl("👆", 54)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_module_box.add_child(hint)
		var ht := UI.lbl("¡Toca un edificio de la base!", 20, UI.TEXT, true, 250)
		ht.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_module_box.add_child(ht)
		return
	var d: Dictionary = ModuleDefs.DEFS[selected]
	var lvl := _status_level(selected)
	var st := KidText.state(lvl)
	# 1-4) Ilustracion grande, nombre, funcion y estado (color + simbolo + palabra)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_module_box.add_child(head)
	head.add_child(KidKit.disc(str(d["icon"]), st["col"], 72))
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hv)
	hv.add_child(UI.lbl(str(d["name"]), 20, UI.GOLD, true, 170))
	var badge := UI.lbl(" %s %s " % [st["icon"], st["word"]], 15, Color.WHITE)
	badge.add_theme_stylebox_override("normal", UI.box(Color(st["col"]).darkened(0.45), st["col"], 2, 10, 2))
	hv.add_child(badge)
	# 5) Una frase explicativa en un globo
	var phrase := KidText.module_phrase(selected, lvl)
	if phrase != "":
		var bub := PanelContainer.new()
		bub.add_theme_stylebox_override("panel", UI.box(Color("eaf3ff"), Color("8ec5ff"), 3, 10, 8))
		var bl := UI.lbl(phrase, 18, Color("15306b"), true, 240)
		bl.add_theme_constant_override("outline_size", 0)
		bub.add_child(bl)
		_module_box.add_child(bub)
	# Lo que produce y lo que gasta, en iconos
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 4)
	_module_box.add_child(chips)
	for c in _module_chips(selected):
		chips.add_child(KidKit.chip(str(c[0]), str(c[1]), bool(c[2]), 17))
	# Controles propios de cada modulo
	if selected == "greenhouse":
		_led_selector()
	if selected == "command":
		_command_controls()
	if selected == "lab":
		_lab_controls()
	# 6) Botones de accion
	for tid in d["tasks"]:
		if not s.task_visible(tid):
			continue
		_module_box.add_child(_task_button(tid))
	_info_section(d)


## Lo que el edificio da (verde) y lo que gasta (rojo) este turno, como [icono, texto, bueno].
func _module_chips(id: String) -> Array:
	match id:
		"life_support": return [["💨", "+%d" % int(11.0 * s.ls_cond / 100.0), true], ["⚡", "−70", false]]
		"greenhouse":
			var lf: float = SimConfig.LIGHT[s.led]
			return [["🍎", "+%d" % int(s.beds * SimConfig.FOOD_PER_BED * lf * s.plant_health / 100.0), true], ["💨", "", true], ["⚡", "−%d" % int(s.led_load(s.led)), false]]
		"fertilization": return [["🌱", "+20", true], ["⚡", "−10", false], ["🧱", "−4", false]]
		"shelter": return [["🛡️", "%d" % int(s.shield), true], ["🏠", "%d" % int(s.shelter), true], ["⚡", "−40", false]]
		"main_energy": return [["☀️", "+%d" % int(s.generation()), true], ["🔋", "%d" % int(s.main), true]]
		"backup_energy": return [["🔋", "%d" % int(s.backup), true]]
		"panels": return [["⚡", "+%d" % int(s.panels * SimConfig.PANEL_OUTPUT * s.solar_factor * s.solar_event_mult), s.is_day()]]
		"processing": return [["🧱", "+30", true], ["⚡", "−40", false]]
		"lab": return [["🔬", "+50", true], ["⚡", "−50", false]]
		"infirmary": return [["❤️", "+20", true], ["⚡", "−10", false]]
		"dorms", "common", "habitat": return [["❤️", "+6", true], ["⚡", "−%d" % int(SimConfig.LOAD_HABITAT * (0.7 if s.saving else 1.0)), false]]
		"command": return [["🔌", "−%d" % int(SimConfig.LOAD_CONTROL * (0.7 if s.saving else 1.0)), false]]
	return []


func _info_section(d: Dictionary) -> void:
	var tg := UI.btn("💡 Ocultar" if _info_open else "💡 ¿Sabías qué?", Color("6a4fd0"), func() -> void:
		_info_open = not _info_open
		_refresh_module_panel(), 14, 40)
	_module_box.add_child(tg)
	if not _info_open:
		return
	# El robot explica con una analogia sencilla; el detalle tecnico y la fuente de NASA quedan aqui.
	var an: String = str(KidText.ANALOGY.get(selected, ""))
	if an != "":
		_module_box.add_child(UI.lbl("🤖 " + an, 16, UI.GOLD, true, 250))
	_module_box.add_child(UI.lbl(_state_text(selected), 14, UI.TEXT, true, 250))
	_module_box.add_child(UI.lbl(_flow_text(selected), 14, Color("ffe08a"), true, 250))
	_module_box.add_child(UI.lbl("Necesita: " + d["needs"], 14, UI.MUTED, true, 250))
	_module_box.add_child(UI.lbl("Ojo: " + d["conseq"], 14, Color("ffd9a0"), true, 250))
	if d.has("ref"):
		var rb := PanelContainer.new()
		rb.add_theme_stylebox_override("panel", UI.box(Color("0c3040"), UI.REF, 2, 8, 6))
		var rv := VBoxContainer.new()
		rb.add_child(rv)
		rv.add_child(UI.badge(ScientificDataManager.LABEL_REF, 12))
		rv.add_child(UI.lbl(d["ref"]["text"], 14, UI.TEXT, true, 240))
		var lk := LinkButton.new()
		lk.text = d["ref"]["label"]
		lk.uri = d["ref"]["url"]
		lk.add_theme_font_size_override("font_size", 14)
		lk.add_theme_color_override("font_color", Color("8cc8ff"))
		rv.add_child(lk)
		_module_box.add_child(rb)


func _state_text(id: String) -> String:
	match id:
		"life_support": return "condición %d%% · O₂ %d · CO₂ %d · agua %d" % [s.ls_cond, s.o2, s.co2, s.water]
		"greenhouse": return "plantas %d%% sanas · %d camas · nutrientes %d%%" % [s.plant_health, s.beds, s.nutrients]
		"fertilization": return "nutrientes %d%%" % s.nutrients
		"shelter": return "blindaje %d%% · refugio %d%% · exposición %d/100" % [s.shield, s.shelter, s.exposure]
		"main_energy": return "%d / %d unidades" % [s.main, SimConfig.MAIN_CAP]
		"backup_energy": return "%d / %d unidades" % [s.backup, SimConfig.BACKUP_CAP]
		"panels": return "%d paneles · %s" % [s.panels, "al sol" if s.is_day() else "en la sombra (noche)"]
		"processing": return "materiales disponibles: %d" % s.materials
		"lab": return "mejoras listas: %d de 3" % s.research_done.size()
		"infirmary", "dorms", "common", "habitat": return "salud de la tripulación %d%%" % s.health
		"command": return "ahorro %s" % ("ACTIVO" if s.saving else "apagado")
	return "funcionando"


func _flow_text(id: String) -> String:
	match id:
		"life_support": return "⚡ Gasta 70/turno · Produce aire (O₂ +%d, CO₂ −%d)" % [11.0 * s.ls_cond / 100.0, 9.0 * s.ls_cond / 100.0]
		"greenhouse":
			var lf: float = SimConfig.LIGHT[s.led]
			return "⚡ Gasta %d/turno · Produce comida +%.1f y algo de aire" % [s.led_load(s.led), s.beds * SimConfig.FOOD_PER_BED * lf * s.plant_health / 100.0]
		"fertilization": return "⚡ 10 · 🧱 4 · ⏱ 2h → nutrientes +20"
		"shelter": return "⚡ 40 solo en alertas · 🧱 materiales para ampliar"
		"main_energy": return "☀ Genera %d este turno · Todo lo demás gasta de aquí" % s.generation()
		"backup_energy": return "Reserva de emergencia: úsala con cuidado"
		"panels": return "☀ +%d por turno de día · 0 de noche" % (s.panels * SimConfig.PANEL_OUTPUT * s.solar_factor)
		"processing": return "⚡ 40 · ⏱ 3h (con robot) → materiales +30"
		"lab": return "⚡ 50 · ⏱ 4h → investigación +50%"
		"infirmary": return "⚡ 10 · ⏱ 2h → salud +20 y menos radiación"
		"dorms", "common", "habitat": return "⚡ Hogar %d/turno · Descanso: salud +6" % (SimConfig.LOAD_HABITAT * (0.7 if s.saving else 1.0))
		"command": return "⚡ Control %d/turno" % (SimConfig.LOAD_CONTROL * (0.7 if s.saving else 1.0))
	return ""


func _task_button(tid: String) -> Button:
	var c := s.task_cost(tid)
	var forced := tid in s.forced_tasks
	var on: bool = forced or (tid in plan["tasks"])
	var costs: PackedStringArray = []
	if int(c["hours"]) > 0:
		costs.append("⏱ %dh" % int(c["hours"]))
	if int(c["mat"]) > 0:
		costs.append("🧱 %d" % int(c["mat"]))
	if int(c["energy"]) > 0:
		costs.append("⚡ %d" % int(c["energy"]))
	var b := UI.btn("%s%s  %s\n%s" % ["🔒 " if forced else ("✔ " if on else ""), c.get("icon", TASKS_ICON(tid)), BaseState.TASKS[tid]["name"],
			"  ".join(costs) if not costs.is_empty() else "¡Gratis!"], Color("28b36a") if on else Color("3b6fe0"), Callable(), 15, 56)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if not on:
		var test: Array = (plan["tasks"] as Array).duplicate()
		test.append(tid)
		b.disabled = not s.can_afford(test)
	if forced:
		b.disabled = true
	if tid in BaseState.CONTROL_TASKS and not s.control_on:
		b.disabled = true
		b.text += "\n(el Control está apagado)"
	b.pressed.connect(_toggle_task.bind(tid))
	return b


func TASKS_ICON(tid: String) -> String:
	return BaseState.TASKS[tid]["icon"]


func _led_selector() -> void:
	_module_box.add_child(UI.lbl("💡 Luz LED del invernadero:", 13, UI.GOLD))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_module_box.add_child(row)
	var names := ["Apagada\n⚡0", "Normal\n⚡%d" % s.led_load(1), "Alta\n⚡%d" % s.led_load(2)]
	var cur: int = s.forced_led if s.forced_led >= 0 else int(plan["led"])
	for i in 3:
		var b := UI.btn(names[i], Color("1f9f55") if cur == i else Color("245aa8"), _set_led.bind(i), 12, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = (s.forced_led >= 0 and cur != i) or i > s.led_cap
		row.add_child(b)
	if s.led_cap < 2:
		_module_box.add_child(UI.lbl("Por una decisión, las luces no pueden pasar del nivel %d." % s.led_cap, 12, Color("ffd9a0"), true, 250))


func _command_controls() -> void:
	var b := UI.btn(("🔋 Ahorro de energía: ACTIVO" if s.saving else "🔋 Ahorro de energía: apagado"), Color("1f9f55") if s.saving else Color("245aa8"), _toggle_saving, 13, 40)
	_module_box.add_child(b)
	_module_box.add_child(UI.lbl("Ahorro: −30% en control y hogar, pero el laboratorio y los materiales rinden la mitad.", 12, UI.MUTED, true, 250))
	_module_box.add_child(UI.lbl("🔌 Subsistemas (apagar ahorra energía, pero tiene un coste):", 13, UI.GOLD, true, 250))
	_module_box.add_child(UI.btn("🖥 Control: %s (⚡%d)" % ["ENCENDIDO" if s.control_on else "APAGADO", SimConfig.LOAD_CONTROL * (0.7 if s.saving else 1.0)],
			Color("1f9f55") if s.control_on else Color("a83a3a"), _toggle_control, 13, 36))
	_module_box.add_child(UI.btn("🏠 Hogar: %s (⚡%d)" % ["ENCENDIDO" if s.habitat_on else "APAGADO", SimConfig.LOAD_HABITAT * (0.7 if s.saving else 1.0)],
			Color("1f9f55") if s.habitat_on else Color("a83a3a"), _toggle_habitat, 13, 36))
	_module_box.add_child(UI.lbl("Sin Control no hay obras ni investigación. Sin Hogar la tripulación pierde salud cada turno.", 11, UI.MUTED, true, 250))
	if bool(s.rule("heat_comms", false)):
		_module_box.add_child(UI.btn("❄ Calefacción: %s (⚡35)" % ("ENCENDIDA" if s.heat_on else "APAGADA"),
				Color("1f9f55") if s.heat_on else Color("a83a3a"), _toggle_heat, 13, 36))
		_module_box.add_child(UI.btn("📡 Transmisión a la Tierra: %s (⚡30)" % ("ENCENDIDA" if s.comms_on else "APAGADA"),
				Color("1f9f55") if s.comms_on else Color("a83a3a"), _toggle_comms, 13, 36))
		_module_box.add_child(UI.lbl("Datos enviados: %d de %d. Sin calefacción la salud baja 16 por turno; sin transmisión no se envían datos." % [s.data_sent, int(s.mission.win_extra.get("min_data", 0))], 11, UI.MUTED, true, 250))
	var nb := PanelContainer.new()
	nb.add_theme_stylebox_override("panel", UI.box(Color("1a1330"), UI.SIM, 2, 8, 6))
	var nv := VBoxContainer.new()
	nb.add_child(nv)
	nv.add_child(UI.lbl("📡 Alerta solar (NASA DONKI)", 13, UI.GOLD))
	nv.add_child(UI.badge(NasaBridge.label(), 11))
	nv.add_child(UI.lbl(NasaBridge.headline() if _event_loaded else "Consultando DONKI…", 12, UI.TEXT, true, 240))
	nv.add_child(UI.lbl(NasaBridge.mapping_text() if _event_loaded else "", 11, UI.MUTED, true, 240))
	_module_box.add_child(nb)


func _toggle_control() -> void:
	s.control_on = not s.control_on
	if not s.control_on:
		plan["tasks"] = (plan["tasks"] as Array).filter(func(t: String) -> bool: return not (t in BaseState.CONTROL_TASKS))
		_tip.text = "Control apagado: ahorras energía, pero no puedes hacer obras ni investigar."
	else:
		_tip.text = "Control encendido otra vez: gasta energía, pero puedes construir."
	_refresh_all()


func _toggle_heat() -> void:
	s.heat_on = not s.heat_on
	_tip.text = "Sin calefacción la tripulación pasa frío: la salud baja." if not s.heat_on else "Calefacción encendida: gasta ⚡ 35 por turno."
	_refresh_all()


func _toggle_comms() -> void:
	s.comms_on = not s.comms_on
	_tip.text = "Transmisión apagada: no se envían datos a la Tierra." if not s.comms_on else "Transmisión encendida: gasta ⚡ 30 y envía datos."
	_refresh_all()


func _toggle_habitat() -> void:
	s.habitat_on = not s.habitat_on
	_tip.text = "Hogar apagado: la tripulación pierde salud cada turno." if not s.habitat_on else "Hogar encendido: la tripulación descansa mejor."
	_refresh_all()


func _toggle_saving() -> void:
	s.saving = not s.saving
	_tip.text = "Ahorro activado: conservas baterías, pero se produce menos." if s.saving else "¡Recuerda reservar energía para el oxígeno!"
	_refresh_all()


func _lab_controls() -> void:
	if s.research_project == "":
		_module_box.add_child(UI.lbl("Elige qué investigar:", 13, UI.GOLD))
		for p in BaseState.PROJECTS:
			if p in s.research_done:
				_module_box.add_child(UI.lbl("✔ %s (lista)" % BaseState.PROJECTS[p]["name"], 12, UI.GREEN, true, 250))
				continue
			var b := UI.btn("%s\n%s" % [BaseState.PROJECTS[p]["name"], BaseState.PROJECTS[p]["desc"]], Color("245aa8"), _pick_project.bind(p), 12, 50)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			_module_box.add_child(b)
	else:
		_module_box.add_child(UI.lbl("Investigando: %s (%d%%)" % [BaseState.PROJECTS[s.research_project]["name"], s.research_progress], 13, UI.GREEN, true, 250))


func _pick_project(p: String) -> void:
	s.research_project = p
	_refresh_module_panel()


# -------------------------------------------------------------- REFRESCOS ----

func _refresh_all() -> void:
	_refresh_indicators()
	_refresh_budget()
	_refresh_module_panel()
	_world.queue_redraw()
	_night.color.a = 0.0 if s.is_day() else 0.5
	_map.modulate = Color.WHITE if s.is_day() else Color(0.86, 0.9, 1.0)
	_extra_label.text = _extra_text()
	_extra_label.visible = _extra_label.text != ""
	_title_label.text = "Día %d · Turno %d de %d" % [s.day_number(), mini(s.turn, s.turns), s.turns]
	_phase_label.text = "☀ Hay luz del Sol" if s.is_day() else "🌙 Es de noche: no hay Sol"
	_turn_dots.queue_redraw()


func _refresh_indicators() -> void:
	var ind := s.indicators()
	var air := minf(s.o2, 100.0 - s.co2)   # aire sano: oxigeno y CO2 juntos
	KidKit.set_meter(_ind_rows["vida"], air)
	KidKit.set_meter(_ind_rows["agua"], s.water)
	KidKit.set_meter(_ind_rows["energia"], ind["energia"])
	KidKit.set_meter(_ind_rows["alimentos"], ind["alimentos"])
	KidKit.set_meter(_ind_rows["proteccion"], ind["proteccion"])
	KidKit.set_meter(_ind_rows["materiales"], minf(100.0, s.materials), s.materials)
	# El detalle tecnico queda a un paso (cursor encima), no ocupa la pantalla.
	(_ind_rows["vida"]["root"] as Control).tooltip_text = "Oxígeno %d · CO₂ %d" % [s.o2, s.co2]
	(_ind_rows["energia"]["root"] as Control).tooltip_text = "Principal %d · Respaldo %d" % [s.main, s.backup]
	(_ind_rows["alimentos"]["root"] as Control).tooltip_text = "Comida %d · plantas sanas %d%%" % [s.food, s.plant_health]
	(_ind_rows["proteccion"]["root"] as Control).tooltip_text = "Radiación recibida %d de 100" % s.exposure


func _refresh_budget() -> void:
	var pv := s.preview(plan)
	var e_use: float = pv["energy_load"]
	var e_have: float = pv["energy_have"]
	_set_budget("energy", e_use, e_have, "⚡ Energía  %d / %d" % [e_use, e_have])
	_set_budget("mat", pv["mat"], maxf(1.0, s.materials), "🧱 Materiales  %d / %d" % [pv["mat"], s.materials])
	_set_budget("hours", pv["hours"], pv["hours_budget"], "⏱ Horas  %d / %d" % [pv["hours"], pv["hours_budget"]])
	_end_btn.disabled = not bool(pv["ok"]) or s.finished
	_warn.text = str(pv["why"])
	if e_use > e_have:
		_warn.text = "Falta energía: se apagará lo menos importante"
	_refresh_risks()


## Panel de riesgos: muestra el peligro de las decisiones del turno ANTES de confirmarlas.
func _refresh_risks() -> void:
	for c in _risk_box.get_children():
		c.queue_free()
	var rs := s.risks(plan)
	_risk_panel.modulate.a = 1.0 if rs.size() > 0 else 0.0
	_risk_panel.mouse_filter = Control.MOUSE_FILTER_STOP if rs.size() > 0 else Control.MOUSE_FILTER_IGNORE
	var shown := 0
	for r in rs:
		if shown >= 3:
			break
		var col: Color = [UI.RED, UI.YELLOW, UI.GREEN][int(r["lvl"])]
		var icon: String = ["⛔", "⚠", "✨"][int(r["lvl"])]
		_risk_box.add_child(UI.lbl("%s %s" % [icon, r["text"]], 13, col, true, 640))
		shown += 1


## Linea de estado propia de cada mision (datos enviados, trajes, fisura, ciclo de luz...).
func _extra_text() -> String:
	var base := _mission_extra_text()
	if _alerts != null and not s.alert_log.is_empty():
		var al := "🚨 Alertas: %d · Puntos: %d" % [s.alert_log.size(), s.alert_score]
		return al if base == "" else base + "  ·  " + al
	return base


func _mission_extra_text() -> String:
	if bool(s.rule("heat_comms", false)):
		return "📡 Datos enviados: %d de %d  ·  ❄ Calefacción %s" % [s.data_sent, int(s.mission.win_extra.get("min_data", 0)), "ON" if s.heat_on else "apagada"]
	if bool(s.rule("breach", false)):
		var f := "ABIERTA (%d%% sellada)" % int(s.breach_progress) if s.breach_open else ("cerrada" if s.turn > 4 else "sin daños")
		return "🧑‍🚀 Trajes O₂: %d  ·  🔧 Fisura: %s" % [s.suit_o2, f]
	if bool(s.rule("light_cycle", false)):
		var tip := "alta" if s.led_prev == 2 else ("apagada" if s.led_prev == 0 else "normal")
		return "💡 Última luz: %s  ·  Alterna alta/oscuridad" % tip
	return ""


func _set_budget(key: String, used: float, avail: float, text: String) -> void:
	var row: Dictionary = _budget[key]
	(row["label"] as Label).text = text
	var pb: ProgressBar = row["bar"]
	pb.max_value = maxf(1.0, avail)
	pb.value = minf(used, avail)
	UI.set_bar_color(pb, UI.RED if used > avail + 0.001 else (UI.YELLOW if used > avail * 0.85 else UI.GREEN))


func _show_banner(text: String) -> void:
	_banner.text = text
	_banner.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(_banner, "modulate:a", 0.0, 1.0)


func _robot_tip() -> String:
	var ind := s.indicators()
	if s.turn >= s.alert_turn - 1 and s.turn <= s.alert_turn and s.alert_tier > 0:
		return "¡Tormenta solar! ¡Revisa el escudo y el refugio!"
	if s.energy_total() < 250.0:
		return "¡Necesitamos más energía!"
	if s.water < 30.0:
		return "¡Cuidado! Queda poca agua."
	if s.exposure > 40.0:
		return "¡Sube la radiación! ¡El escudo necesita mejoras!"
	var coach := GuideCoach.advice(s)   # guia segun lo que el jugador fue decidiendo
	if coach != "":
		return KidText.short(coach, 100)
	if s.food < 25.0:
		return "¡Poca comida! Cuida las plantas."
	if s.plant_health < 50.0:
		return "¡Las plantas necesitan cuidados!"
	if s.ls_cond < 50.0:
		return "¡El soporte vital está cansado!"
	if ind["proteccion"] < 40.0 and s.turn < s.alert_turn:
		return "¡El escudo necesita mejoras!"
	var generic := ["¡Buen trabajo, comandante!", "Más luz ayuda a las plantas, pero gasta energía.", "El escudo protege al equipo, pero usa materiales.",
			"¡Guarda energía para el aire!"]
	_tip_idx += 1
	return generic[_tip_idx % generic.size()]


# ----------------------------------------------------------------- TURNOS ----

func _begin_turn(skip_intro: bool = false) -> void:
	var news := MissionDirector.start_of_turn(s)
	plan["tasks"] = []
	plan["led"] = s.led
	var cards := MissionDirector.cards_for_turn(s)
	_refresh_all()
	_tip.text = _robot_tip()
	if _tutorial != null:
		_tutorial.notify("turn:%d" % s.turn)
	if s.turn == 1 and not skip_intro:
		_show_intro()
		return
	if cards.size() > 0:
		_show_card(cards[0], news)
	else:
		if news.size() > 0:
			_show_banner(str(news[0]))
		if s.alert_turn > 0 and s.turn == s.alert_turn:
			_show_alert_modal(news)


func _show_intro() -> void:
	_intro_pending = true
	await _wait_moon()
	_intro_pending = false
	var v := _modal("%s %s" % [s.mission.icon, s.mission.title], UI.GOLD, 860)
	var diff := UI.lbl("%s  %s" % [s.mission.stars(), s.mission.difficulty_label()], 17, s.mission.difficulty_color())
	diff.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(diff)
	# La mision en una imagen y una frase: la Luna, la base y los astronautas.
	var scene_row := HBoxContainer.new()
	scene_row.alignment = BoxContainer.ALIGNMENT_CENTER
	scene_row.add_theme_constant_override("separation", 14)
	v.add_child(scene_row)
	if _moon_tex != null:
		var tr := TextureRect.new()
		tr.texture = _moon_tex
		tr.custom_minimum_size = Vector2(190, 95)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.tooltip_text = _moon_note
		scene_row.add_child(tr)
	for pair in [["🌙", Color("8d93ad")], ["🛰️", Color("4f8dff")], ["🧑‍🚀", Color("f1b434")]]:
		scene_row.add_child(KidKit.disc(str(pair[0]), pair[1], 78))
	var goal := UI.lbl("¡Mantén a tu equipo seguro durante 3 días junto a la Luna!", 24, UI.TEXT, true, 760)
	goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(goal)
	v.add_child(KidKit.protect_sacrifice(s.mission.protect, s.mission.sacrifice))
	v.add_child(KidKit.how_to_play())
	if _alerts != null:
		var al := UI.lbl("🚨 ¡Pueden sonar alertas! Decide rápido.", 17, Color("ffb07a"))
		al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(al)
	v.add_child(UI.btn("🚀 ¡Empezar misión!", Color("28b36a"), func() -> void:
		_close_modal()
		_show_banner("☀ ¡Hay luz del Sol! Los paneles cargan las baterías."), 24, 60))


func _show_card(card: Dictionary, news: Array) -> void:
	var v := _modal("%s  %s" % [card["icon"], KidText.sentence(str(card["title"]))], UI.GOLD, 940)
	if news.size() > 0:
		var nl := UI.lbl(KidText.short(str(news[0]), 80), 15, UI.MUTED, true, 800)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(nl)
	# El robot plantea la situacion en una frase corta
	var ask := HBoxContainer.new()
	ask.alignment = BoxContainer.ALIGNMENT_CENTER
	ask.add_theme_constant_override("separation", 10)
	v.add_child(ask)
	ask.add_child(KidKit.disc("🤖", Color("5a7bd0"), 56))
	var bub := PanelContainer.new()
	bub.add_theme_stylebox_override("panel", UI.box(Color("eaf3ff"), Color("8ec5ff"), 3, 12, 10))
	var q := UI.lbl(KidText.short(str(card["question"]), 95), 20, Color("15306b"), true, 640)
	q.add_theme_constant_override("outline_size", 0)
	bub.add_child(q)
	ask.add_child(bub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	var choice := {"i": -1}
	var buttons: Array = []
	var ok := UI.btn("¡Confirmar! ✔", Color("28b36a"), Callable(), 22, 56)
	ok.disabled = true
	var cols := [Color("4f8dff"), Color("ffb02f"), Color("b07cff")]
	var opts: Array = card["options"]
	for i in opts.size():
		var o: Dictionary = opts[i]
		var col: Color = cols[i % 3]
		var cb := Button.new()
		cb.toggle_mode = true
		cb.custom_minimum_size = Vector2(0, 330)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cb.focus_mode = Control.FOCUS_NONE
		cb.add_theme_stylebox_override("normal", UI.box(Color("22348a"), col.darkened(0.1), 4, 14, 10))
		cb.add_theme_stylebox_override("hover", UI.box(Color("2d44a8"), col.lightened(0.2), 4, 14, 10))
		cb.add_theme_stylebox_override("pressed", UI.box(col.darkened(0.55), Color.WHITE, 6, 14, 10))
		cb.add_theme_stylebox_override("disabled", UI.box(Color("232a45"), Color("3a4468"), 3, 14, 10))
		cb.disabled = not bool(o.get("affordable", true))
		UI.bounce(cb)
		row.add_child(cb)
		_fill_option_card(cb, o, str(card["icon"]), col)
		buttons.append(cb)
		cb.pressed.connect(func() -> void:
			choice["i"] = i
			ok.disabled = false
			for j in buttons.size():
				(buttons[j] as Button).button_pressed = j == i)
	ok.pressed.connect(func() -> void:
		var idx := int(choice["i"])
		MissionDirector.choose(s, card, idx)
		MissionManager.decision_made.emit(str(card["id"]), idx, str((card["options"][idx] as Dictionary).get("sacrifice", "")))
		_close_modal()
		plan["led"] = s.forced_led if s.forced_led >= 0 else s.led
		_refresh_all()
		_tip.text = _robot_tip())
	v.add_child(ok)


## Tarjeta ilustrada de una opcion: dibujo grande, titulo corto, lo que ganas (verde) y lo que pierdes (rojo) en iconos.
func _fill_option_card(cb: Button, o: Dictionary, card_icon: String, col: Color) -> void:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	cb.add_child(m)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 6)
	m.add_child(v)
	var pic := KidKit.disc(KidText.illustration(str(o["label"]), card_icon), col, 92)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pic)
	var title := UI.lbl(str(o["label"]), 20, Color.WHITE, true, 250)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(title)
	_chip_row(v, "▲ Ganas", KidText.chips(o.get("good", [])), true)
	_chip_row(v, "▼ Gastas", KidText.chips(o.get("bad", [])), false)
	if o.has("risk"):
		var rk := UI.lbl("⚠ " + KidText.short(str(o["risk"]), 60), 14, Color("ffb07a"), true, 250)
		rk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(rk)
	if cb.disabled:
		var lk := UI.lbl("🔒 Faltan materiales u horas", 15, Color("ffb07a"), true, 250)
		lk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(lk)


func _chip_row(parent: VBoxContainer, title: String, chips: Array, good: bool) -> void:
	if chips.is_empty():
		return
	var lab := UI.lbl(title, 14, UI.GREEN if good else Color("ff9d9d"))
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lab)
	var fl := HFlowContainer.new()
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fl.add_theme_constant_override("h_separation", 5)
	fl.add_theme_constant_override("v_separation", 4)
	parent.add_child(fl)
	for c in chips.slice(0, 4):
		var num := str(c["num"])
		if num != "" and not (num.begins_with("+") or num.begins_with("−") or num.begins_with("-")):
			num = ("+" if good else "−") + num
		var ch := KidKit.chip(str(c["icon"]), num, good, 16)
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fl.add_child(ch)


func _show_alert_modal(news: Array) -> void:
	if _tutorial != null:
		_tutorial.notify("alert")
	var v := _modal("☀️ ¡Alerta solar!", UI.RED, 880)
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.add_theme_stylebox_override("panel", UI.box(Color("0b1240"), UI.RED, 4, 14, 0))
	frame.clip_contents = true
	frame.add_child(KidArt.make("solar_alert", Vector2(560, 200)))
	v.add_child(frame)
	var say := HBoxContainer.new()
	say.alignment = BoxContainer.ALIGNMENT_CENTER
	say.add_theme_constant_override("separation", 10)
	v.add_child(say)
	say.add_child(KidKit.disc("🤖", Color("5a7bd0"), 56))
	var bub := PanelContainer.new()
	bub.add_theme_stylebox_override("panel", UI.box(Color("eaf3ff"), Color("8ec5ff"), 3, 12, 10))
	var q := UI.lbl("¡Una tormenta solar se acerca! ¡Protejamos al equipo!", 22, Color("15306b"), true, 560)
	q.add_theme_constant_override("outline_size", 0)
	bub.add_child(q)
	say.add_child(bub)
	var ind := s.indicators()
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	var mt := KidKit.meter("🛡️", "Tu escudo", Color("3ddc84"))
	(mt["root"] as Control).custom_minimum_size = Vector2(300, 0)
	KidKit.set_meter(mt, float(ind["proteccion"]))
	row.add_child(mt["root"])
	row.add_child(KidKit.chip("⚡", "−40 hoy", false, 22))
	# El dato de NASA, en pequeno y con su etiqueta honesta (SIMULACION / DATO HISTORICO...)
	var src := HBoxContainer.new()
	src.alignment = BoxContainer.ALIGNMENT_CENTER
	src.add_theme_constant_override("separation", 8)
	src.tooltip_text = NasaBridge.mapping_text()
	v.add_child(src)
	src.add_child(UI.lbl(KidText.short(NasaBridge.headline(), 70), 15, UI.MUTED))
	src.add_child(UI.badge(NasaBridge.label(), 13))
	v.add_child(UI.btn("🛡️ ¡Entendido!", Color("28b36a"), _close_modal, 24, 58))


## Muestra una alerta espacial a pantalla grande. El juego queda en pausa hasta que el jugador responde (o se acaba el tiempo).
## Tutorial progresivo: el robot ensena cada cosa la primera vez que hace falta.
func _build_tutorial() -> void:
	_tutorial = TutorialGuide.new()
	_tutorial.mission_id = s.mission.id
	add_child(_tutorial)
	_tutorial.can_show = func() -> bool: return _modal_root == null and not _alert_open and not _intro_pending and not s.finished
	_tutorial.resolver = _tutorial_target


## Donde esta cada elemento al que apunta el robot (vacio = no se ve ahora).
func _tutorial_target(key: String) -> Rect2:
	if key.begins_with("meter:"):
		return _vis_rect(_ind_rows[key.substr(6)]["root"])
	if key.begins_with("module:"):
		return _module_rect(key.substr(7))
	match key:
		"header": return _vis_rect(_mission_panel)
		"panel:module": return _vis_rect(_module_panel)
		"end": return _vis_rect(_end_btn)
	return Rect2()


func _vis_rect(c: Control) -> Rect2:
	return c.get_global_rect() if (c != null and c.is_visible_in_tree() and c.modulate.a > 0.1) else Rect2()


func _module_rect(id: String) -> Rect2:
	var r: Rect2 = ModuleDefs.DEFS[id]["rect"]
	return Rect2(_map.global_position + r.position, r.size)


## Boton «Repetir ayuda» del robot.
func _replay_help() -> void:
	if _tutorial != null:
		_tutorial.replay()
	else:
		_tip.text = "¡Toca un edificio para ver qué hace!"
		_robot_hop = 1.0


func _show_space_alert(ev: Dictionary) -> void:
	if _alert_open or s.finished:
		return
	_alert_open = true
	_alert_ui = AlertOverlay.new()
	_alert_ui.setup(ev, s)
	_alert_ui.finished.connect(_on_alert_finished)
	add_child(_alert_ui)


func _on_alert_finished(res: Dictionary) -> void:
	_alert_open = false
	_alert_ui = null
	s.check_end_now()   # red de seguridad: las alertas tienen limites y no deberian terminar la mision
	_refresh_all()
	_refresh_module_panel()
	_tip.text = _robot_tip()
	_show_banner("🚨 %s  ·  %s%d puntos" % ["Sin respuesta" if bool(res["timed_out"]) else str(res["choice"]), "+" if int(res["score"]) >= 0 else "−", absi(int(res["score"]))])
	if s.finished:
		_show_end()


func _end_turn() -> void:
	if s.finished or _modal_root != null or _intro_pending or _alert_open:
		return
	var pv := s.preview(plan)
	if not bool(pv["ok"]):
		_tip.text = "Ajusta tus tareas: " + str(pv["why"]).to_lower() + "."
		return
	var turn_done := s.turn
	var r := s.step(plan)
	_refresh_all()
	_show_report(turn_done, r)


func _show_report(turn_done: int, r: Dictionary) -> void:
	var v := _modal("✅ ¡Turno %d terminado!" % turn_done, UI.GOLD, 820)
	var before: Dictionary = r["before"]
	var after: Dictionary = r["after"]
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var net := 0.0
	var worst := 100.0
	for k in INDICATORS:
		var a: float = after[k[0]]
		var d: float = a - float(before[k[0]])
		net += d
		worst = minf(worst, a)
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lvl := UI.light_of(a)
		card.add_theme_stylebox_override("panel", UI.box(Color("22348a"), UI.light_color(lvl), 4, 14, 8))
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 3)
		card.add_child(cv)
		var disc := KidKit.disc(str(k[1]), UI.light_color(lvl), 62)
		disc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cv.add_child(disc)
		var nm := UI.lbl(str(k[2]), 16, UI.TEXT)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(nm)
		var st := KidText.state(lvl)
		var val := UI.lbl("%s %d" % [st["icon"], int(a)], 24, st["col"] if lvl < 2 else Color.WHITE)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(val)
		var arrow := "▲ +%d" % int(round(d)) if d > 1.0 else ("▼ −%d" % int(round(absf(d))) if d < -1.0 else "■ igual")
		var dl := UI.lbl(arrow, 17, UI.GREEN if d > 1.0 else (UI.RED if d < -1.0 else UI.MUTED))
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(dl)
		row.add_child(card)
	var shown := 0
	for m in r["msgs"]:
		if shown >= 2:
			break
		v.add_child(UI.lbl("• " + KidText.short(str(m), 90), 17, Color("ffd9a0"), true, 740))
		shown += 1
	if not s.finished:
		if worst >= 40.0 and net >= 0.0:
			_cheer()
		var say := HBoxContainer.new()
		say.alignment = BoxContainer.ALIGNMENT_CENTER
		say.add_theme_constant_override("separation", 10)
		v.add_child(say)
		say.add_child(KidKit.disc("🤖", Color("5a7bd0"), 52))
		var bub := PanelContainer.new()
		bub.add_theme_stylebox_override("panel", UI.box(Color("eaf3ff"), Color("8ec5ff"), 3, 12, 8))
		var tl := UI.lbl(KidText.short(_robot_tip(), 100), 19, Color("15306b"), true, 620)
		tl.add_theme_constant_override("outline_size", 0)
		bub.add_child(tl)
		say.add_child(bub)
	v.add_child(UI.btn("¡Siguiente! ▶", Color("28b36a"), func() -> void:
		_close_modal()
		if s.finished:
			_show_end()
		else:
			_begin_turn(), 24, 58))


func _show_end() -> void:
	var persist := not _simulated and not ("--shot=" in "".join(OS.get_cmdline_user_args()))
	var res: Dictionary = MissionManager.finish_run(s, persist)
	var stars := s.stars()
	var v := _modal("🎉 ¡Misión cumplida!" if s.won else "💪 ¡Buen intento, comandante!", UI.GOLD if s.won else Color("ffb07a"), 900)
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.add_theme_stylebox_override("panel", UI.box(Color("0b1240"), UI.GOLD if s.won else Color("8ec5ff"), 4, 14, 0))
	frame.clip_contents = true
	frame.add_child(KidArt.make("win" if s.won else "lose", Vector2(560, 120)))
	v.add_child(frame)
	# Estrellas: aparecen una a una con un rebote
	var srow := HBoxContainer.new()
	srow.alignment = BoxContainer.ALIGNMENT_CENTER
	srow.add_theme_constant_override("separation", 10)
	v.add_child(srow)
	for i in 3:
		var st := UI.lbl("⭐" if i < stars else "☆", 44, Color.WHITE if i < stars else Color("6b7596"))
		st.pivot_offset = Vector2(28, 28)
		st.scale = Vector2.ZERO
		srow.add_child(st)
		var tw := create_tween()
		tw.tween_interval(0.5 + i * 0.4)
		tw.tween_property(st, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var msg := UI.lbl(KidText.short(s.reason, 90) if s.won else "Ahora sabemos qué debemos mejorar.", 22, UI.TEXT, true, 820)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(msg)
	if not s.won:
		var tip: Array = KidText.IMPROVE.get(s.reason_id, KidText.IMPROVE["final"])
		var fix := HBoxContainer.new()
		fix.alignment = BoxContainer.ALIGNMENT_CENTER
		fix.add_theme_constant_override("separation", 10)
		v.add_child(fix)
		fix.add_child(KidKit.disc(str(tip[0]), Color("ffb02f"), 52))
		fix.add_child(UI.lbl("Para la próxima: " + str(tip[1]), 21, Color("ffd9a0")))
	# Sistemas que aguantaron
	var ind := s.indicators()
	var held := HBoxContainer.new()
	held.alignment = BoxContainer.ALIGNMENT_CENTER
	held.add_theme_constant_override("separation", 10)
	v.add_child(held)
	for k in INDICATORS:
		var lvl := UI.light_of(float(ind[k[0]]))
		var stt := KidText.state(lvl)
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		box.add_child(KidKit.disc(str(k[1]), stt["col"], 44))
		box.add_child(UI.lbl(str(stt["icon"]), 24, stt["col"] if lvl < 2 else Color.WHITE))
		held.add_child(box)
	# Logros y misiones nuevas, en una linea cada uno
	for id in res["new_achievements"]:
		var d := AchievementManager.def_of(id)
		var al := UI.lbl("🏆 ¡Logro! %s %s" % [d.get("icon", ""), d.get("name", id)], 18, UI.GOLD)
		al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(al)
	for id in res["unlocked_missions"]:
		var ml := UI.lbl("🔓 ¡Misión nueva! %s" % MissionManager.get_mission(id).title, 18, UI.GREEN)
		ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(ml)
	# Tus decisiones importantes, como pastillas con su dibujo
	if not s.decisions.is_empty():
		v.add_child(UI.lbl("Tus decisiones importantes:", 16, UI.GOLD))
		var dfl := HFlowContainer.new()
		dfl.alignment = FlowContainer.ALIGNMENT_CENTER
		dfl.add_theme_constant_override("h_separation", 8)
		dfl.add_theme_constant_override("v_separation", 4)
		v.add_child(dfl)
		for dc in s.decisions:
			var pill := PanelContainer.new()
			pill.tooltip_text = "%s → %s" % [dc["title"], dc["choice"]]
			pill.add_theme_stylebox_override("panel", UI.box(Color("22348a"), Color("6db6ff"), 2, 8, 4))
			pill.add_child(UI.lbl("%s %s" % [KidText.illustration(str(dc["choice"]), "•"), KidText.short(str(dc["choice"]), 26)], 15, UI.TEXT))
			dfl.add_child(pill)
	if not s.alert_log.is_empty():
		var alr := UI.lbl("🚨 Alertas atendidas: %d · ⭐ %d puntos" % [s.alert_log.size(), s.alert_score], 18, UI.MUTED)
		alr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(alr)
	# Lo que aprendimos
	var learn := VBoxContainer.new()
	learn.add_theme_constant_override("separation", 2)
	v.add_child(learn)
	learn.add_child(UI.lbl("💡 Hoy aprendimos:", 19, UI.GOLD))
	var extras: int = (res["new_achievements"] as Array).size() + (res["unlocked_missions"] as Array).size()
	for line in (KidText.LEARN.get(s.mission.id, KidText.LEARN["default"]) as Array).slice(0, 2):
		learn.add_child(UI.lbl("• " + str(line), 17, UI.TEXT, true, 820))
	var b1 := HBoxContainer.new()
	b1.add_theme_constant_override("separation", 8)
	v.add_child(b1)
	for bb in [["🔄 Jugar otra vez", Color("28b36a"), func() -> void: get_tree().reload_current_scene()],
			["🚀 Otra misión", Color("ffa51f"), func() -> void:
				GameSettings.start_screen = "missions"
				_go_menu()],
			["📊 Datos", Color("3b6fe0"), _open_data_center], ["🏠 Menú", Color("5a4fd0"), _go_menu]]:
		var btn := UI.btn(bb[0], bb[1], bb[2], 18, 52)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b1.add_child(btn)


func _go_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _open_data_center() -> void:
	if not _simulated:
		AchievementManager.unlock("data_scientist")
	var dc: Control = load("res://scenes/SpaceDataCenter.tscn").instantiate()
	dc.back_requested.connect(func() -> void: dc.queue_free())
	add_child(dc)


# --------------------------------------------------------------------- UI ----

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
	panel.add_theme_stylebox_override("panel", UI.box(UI.PANEL, UI.BORDER, 3, 14, 14))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	_pop_in(panel)
	var t := UI.lbl(title, 28, title_col)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	return v


## Entrada suave de las ventanas: crecen con un pequeno rebote.
func _pop_in(panel: Control) -> void:
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.9, 0.9)
	await get_tree().process_frame
	if not is_instance_valid(panel):
		return
	panel.pivot_offset = panel.size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.18)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _close_modal() -> void:
	if _modal_root != null:
		_modal_root.queue_free()
		_modal_root = null


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_world = Control.new()
	_world.set_anchors_preset(Control.PRESET_FULL_RECT)
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.draw.connect(_draw_world)
	add_child(_world)
	# La Luna, grande y al fondo (imagen real LRO cuando carga). Misma esfera que la Tierra, sin atmosfera.
	_moon = ColorRect.new()
	_moon.position = MOON_CENTER - Vector2(MOON_RADIUS, MOON_RADIUS)
	_moon.size = Vector2(MOON_RADIUS, MOON_RADIUS) * 2.0
	_moon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mmat := ShaderMaterial.new()
	mmat.shader = load("res://shaders/earth_sphere.gdshader")
	mmat.set_shader_parameter("atmo", 0.0)
	mmat.set_shader_parameter("gain", 1.7)
	mmat.set_shader_parameter("fallback", Color("a9abb5"))
	_moon.material = mmat
	add_child(_moon)
	# De noche solo se oscurece el fondo: la Tierra y la base (con luces propias) siguen brillando.
	_night = ColorRect.new()
	_night.color = Color(0.02, 0.03, 0.12, 0.0)
	_night.set_anchors_preset(Control.PRESET_FULL_RECT)
	_night.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_night)
	# Tierra real en el cielo lunar
	_earth = ColorRect.new()
	_earth.position = Vector2(820, 62)
	_earth.size = Vector2(110, 110)
	_earth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/earth_sphere.gdshader")
	_earth.material = mat
	add_child(_earth)
	var cap := UI.lbl("", 11, UI.MUTED)
	cap.position = Vector2(690, 200)
	add_child(cap)
	_earth.set_meta("cap", cap)
	# Mapa de la base
	_map = Control.new()
	_map.position = MAP_POS
	_map.size = Vector2(700, 540)
	_map.draw.connect(_draw_map)
	_map.gui_input.connect(_map_input)
	add_child(_map)
	for id in ModuleDefs.ORDER:
		var r: Rect2 = ModuleDefs.DEFS[id]["rect"]
		var l := UI.lbl("%s %s" % [ModuleDefs.DEFS[id]["icon"], SHORT[id]], 11, Color("f2f6ff"))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_stylebox_override("normal", UI.box(Color(0.04, 0.08, 0.2, 0.85), Color(0.35, 0.5, 0.85), 1, 8, 2))
		if r.size.y >= 50:
			l.position = Vector2(r.position.x + 2, r.end.y - 21)
		else:
			l.position = Vector2(r.position.x - 4, r.end.y + 4)
		_map.add_child(l)
	_build_top()
	_build_indicators()
	_build_robot()
	_build_right()


func _build_top() -> void:
	var p := PanelContainer.new()
	p.position = Vector2(290, 8)
	p.custom_minimum_size = Vector2(500, 0)
	p.add_theme_stylebox_override("panel", UI.panel_box(0.94, UI.BORDER, 6))
	add_child(p)
	_mission_panel = p
	_register("mission", p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	var t := UI.lbl("%s %s" % [s.mission.icon, s.mission.title], 16, UI.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	_title_label = UI.lbl("", 21)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title_label)
	_turn_dots = KidKit.turn_dots(s.turns, func() -> int: return mini(s.turn, s.turns), s.night_from)
	var dots_row := CenterContainer.new()
	dots_row.add_child(_turn_dots)
	v.add_child(dots_row)
	_phase_label = UI.lbl("", 14, UI.MUTED)
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_phase_label)
	_extra_label = UI.lbl("", 13, UI.GOLD)
	_extra_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_extra_label)
	_banner = UI.lbl("", 17, UI.GOLD, true, 600)
	_banner.position = Vector2(250, 158)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner.add_theme_constant_override("outline_size", 6)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.custom_minimum_size = Vector2(700, 0)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.modulate.a = 0.0
	add_child(_banner)
	var mb := UI.btn("🏠 Menú", Color("3b6fe0"), _go_menu, 15, 40)
	mb.position = Vector2(14, 8)
	mb.custom_minimum_size = Vector2(120, 44)
	add_child(mb)
	_register("menu_btn", mb)


func _build_indicators() -> void:
	var p := PanelContainer.new()
	p.position = Vector2(12, 62)
	p.custom_minimum_size = Vector2(240, 0)
	p.add_theme_stylebox_override("panel", UI.panel_box(0.94, UI.BORDER, 8))
	add_child(p)
	_register("indicators", p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	p.add_child(v)
	for m in METERS:
		var mt := KidKit.meter(str(m[1]), str(m[2]), m[3])
		v.add_child(mt["root"])
		_ind_rows[str(m[0])] = mt


func _build_robot() -> void:
	var p := PanelContainer.new()
	p.position = Vector2(12, 466)
	p.custom_minimum_size = Vector2(240, 0)
	p.add_theme_stylebox_override("panel", UI.box(Color("eaf3ff"), Color("8ec5ff"), 4, 14, 8))   # globo de dialogo claro
	add_child(p)
	_register("robot", p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	var rb := Control.new()
	rb.custom_minimum_size = Vector2(66, 88)
	rb.draw.connect(func() -> void: KidKit.draw_robot(rb, Vector2(2, 2), _t, _robot_hop, _robot_mood()))
	var tmr := Timer.new()
	tmr.wait_time = 0.05
	tmr.autostart = true
	tmr.timeout.connect(rb.queue_redraw)
	rb.add_child(tmr)
	h.add_child(rb)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 4)
	h.add_child(tv)
	_tip = UI.lbl("", 16, Color("15306b"), true, 140)
	_tip.add_theme_constant_override("outline_size", 0)
	_tip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tv.add_child(_tip)
	var help := UI.btn("❓ Repetir ayuda", Color("6a4fd0"), _replay_help, 13, 36)
	help.custom_minimum_size = Vector2(0, 36)
	tv.add_child(help)


## El robot se preocupa (boca plana) cuando el aire o la energia estan en rojo.
func _robot_mood() -> int:
	if Time.get_ticks_msec() < _happy_until:
		return 2
	var ind := s.indicators()
	return 0 if UI.light_of(minf(float(ind["vida"]), float(ind["energia"]))) == 0 else 1


## El robot celebra un momento (salta y pone cara contenta).
func _cheer() -> void:
	_happy_until = Time.get_ticks_msec() + 4500
	_robot_hop = 1.0


func _build_right() -> void:
	var bp := PanelContainer.new()
	bp.position = Vector2(962, 8)
	bp.custom_minimum_size = Vector2(306, 0)
	bp.add_theme_stylebox_override("panel", UI.panel_box(0.94, UI.BORDER, 8))
	add_child(bp)
	_register("resources", bp)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 3)
	bp.add_child(bv)
	bv.add_child(UI.lbl("📝 Tu plan de hoy", 17, UI.GOLD))
	for k in [["energy", UI.YELLOW], ["mat", Color("c9b27a")], ["hours", Color("7fb3ff")]]:
		var lab := UI.lbl("", 15, UI.TEXT)
		bv.add_child(lab)
		var pb := UI.bar(0, 100, k[1], 14)
		bv.add_child(pb)
		_budget[k[0]] = {"label": lab, "bar": pb}
	_warn = UI.lbl("", 12, UI.RED, true, 280)
	bv.add_child(_warn)
	# Panel de riesgos del turno (abajo, bajo el mapa)
	_risk_panel = PanelContainer.new()
	_risk_panel.position = Vector2(262, 654)
	_risk_panel.custom_minimum_size = Vector2(676, 0)
	_risk_panel.add_theme_stylebox_override("panel", UI.box(Color(0.12, 0.05, 0.05, 0.92), Color("ff7a4d"), 2, 10, 5))
	add_child(_risk_panel)
	_register("risks", _risk_panel)
	_risk_box = VBoxContainer.new()
	_risk_box.add_theme_constant_override("separation", 1)
	_risk_panel.add_child(_risk_box)
	_end_btn = UI.btn("¡Terminar turno! ▶", Color("28b36a"), _end_turn, 20, 50)
	_end_btn.position = Vector2(962, 184)
	_end_btn.custom_minimum_size = Vector2(306, 50)
	add_child(_end_btn)
	_register("end_btn", _end_btn)
	var mp := PanelContainer.new()
	mp.position = Vector2(962, 244)
	mp.custom_minimum_size = Vector2(306, 410)
	mp.add_theme_stylebox_override("panel", UI.panel_box(0.96, UI.BORDER, 8))
	add_child(mp)
	_module_panel = mp
	_register("module", mp)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mp.add_child(sc)
	_module_box = VBoxContainer.new()
	_module_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_module_box.add_theme_constant_override("separation", 6)
	sc.add_child(_module_box)
	# Botones sueltos: Datos (movible/ocultable) e Interfaz (siempre visible).
	var dcb := UI.btn("📊 Datos", Color("1f6fd0"), _open_data_center, 14, 36)
	dcb.position = Vector2(12, 666)
	dcb.custom_minimum_size = Vector2(110, 36)
	add_child(dcb)
	_register("data_btn", dcb)
	var gear := UI.btn("⚙ Interfaz", Color("5a4aa8"), _open_interface_settings, 14, 36)
	gear.position = Vector2(132, 666)
	gear.custom_minimum_size = Vector2(120, 36)
	add_child(gear)
	_register("gear", gear)
	_apply_layout()


# ------------------------------------------------- INTERFAZ MOVIBLE / OCULTABLE ----

func _register(id: String, node: Control) -> void:
	_ui[id] = {"node": node, "def": node.position}


## Aplica la disposicion guardada (posiciones y paneles ocultos) y los ajustes de prueba por consola.
func _apply_layout() -> void:
	UILayout.load_layout()
	for id in _ui:
		var n: Control = _ui[id]["node"]
		var saved: Variant = UILayout.get_pos(id)
		n.position = saved if saved is Vector2 else _ui[id]["def"]
		n.visible = UILayout.is_shown(id) or not UILayout.can_hide(id)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hide="):
			for id in a.substr(7).split(","):
				if _ui.has(id) and UILayout.can_hide(id):
					(_ui[id]["node"] as Control).visible = false
		if a.begins_with("--move="):   # --move=robot:400:300
			var p := a.substr(7).split(":")
			if p.size() == 3 and _ui.has(p[0]):
				(_ui[p[0]]["node"] as Control).position = Vector2(float(p[1]), float(p[2]))
		if a == "--interface":
			_open_interface_settings()
		if a == "--movemode":
			_set_move_mode(true)


func _open_interface_settings() -> void:
	if _settings_root != null:
		_settings_root.queue_free()
		_settings_root = null
		return
	var p := PanelContainer.new()
	p.position = Vector2(400, 90)
	p.z_index = 60
	p.add_theme_stylebox_override("panel", UI.box(UI.PANEL, UI.GOLD, 3, 14, 12))
	add_child(p)
	_settings_root = p
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(460, 0)
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	v.add_child(UI.lbl("⚙ INTERFAZ DEL JUEGO", 20, UI.GOLD))
	v.add_child(UI.lbl("Elige qué paneles ver. Con «Mover» arrastras los paneles con el ratón. Se guarda para la próxima partida.", 13, UI.MUTED, true, 430))
	for e in UILayout.ELEMENTS:
		var id: String = e["id"]
		var cb := CheckButton.new()
		cb.text = e["name"] + ("" if e["can_hide"] else "  (siempre visible)")
		cb.button_pressed = (_ui[id]["node"] as Control).visible
		cb.disabled = not e["can_hide"]
		cb.add_theme_font_size_override("font_size", 14)
		cb.toggled.connect(_set_element_shown.bind(id))
		v.add_child(cb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var mv := UI.btn("✋ Mover paneles: " + ("SÍ" if _move_mode else "no"), Color("1f9f55") if _move_mode else Color("245aa8"), func() -> void:
		_set_move_mode(not _move_mode)
		_settings_root.queue_free()
		_settings_root = null
		_open_interface_settings(), 14, 38)
	mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mv)
	var rs := UI.btn("↺ Restablecer", Color("a85a24"), _reset_layout, 14, 38)
	rs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(rs)
	v.add_child(UI.btn("Cerrar", Color("1f6fd0"), _open_interface_settings, 15, 38))


func _set_element_shown(on: bool, id: String) -> void:
	(_ui[id]["node"] as Control).visible = on or not UILayout.can_hide(id)
	UILayout.set_shown(id, on)
	UILayout.save()
	if _move_mode:
		_refresh_overlays()


func _reset_layout() -> void:
	UILayout.reset()
	for id in _ui:
		(_ui[id]["node"] as Control).position = _ui[id]["def"]
		(_ui[id]["node"] as Control).visible = true
	if _move_mode:
		_refresh_overlays()
	if _settings_root != null:
		_settings_root.queue_free()
		_settings_root = null
		_open_interface_settings()


func _set_move_mode(on: bool) -> void:
	_move_mode = on
	_refresh_overlays()
	if on:
		_show_banner("✋ Modo mover: arrastra los paneles. Abre ⚙ Interfaz para terminar.")


## Mientras se mueve, cada panel lleva encima una capa dorada que recibe el arrastre
## (asi no se pulsan sus botones por accidente).
func _refresh_overlays() -> void:
	for id in _overlays:
		if is_instance_valid(_overlays[id]):
			(_overlays[id] as Control).queue_free()
	_overlays.clear()
	if not _move_mode:
		return
	for id in _ui:
		var n: Control = _ui[id]["node"]
		if not n.visible or id == "gear":
			continue
		var ov := Panel.new()
		ov.set_anchors_preset(Control.PRESET_FULL_RECT)
		ov.mouse_filter = Control.MOUSE_FILTER_STOP
		ov.mouse_default_cursor_shape = Control.CURSOR_MOVE
		ov.tooltip_text = "Arrastra para mover"
		ov.add_theme_stylebox_override("panel", UI.box(Color(1.0, 0.85, 0.3, 0.12), UI.GOLD, 2, 8, 0))
		ov.gui_input.connect(_drag_panel.bind(id))
		n.add_child(ov)
		_overlays[id] = ov


func _drag_panel(ev: InputEvent, id: String) -> void:
	var n: Control = _ui[id]["node"]
	if ev is InputEventMouseMotion and ((ev as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		n.position += (ev as InputEventMouseMotion).relative
		n.position = n.position.clamp(Vector2(-n.size.x + 50.0, 0.0), Vector2(1280.0 - 50.0, 720.0 - 30.0))
	elif ev is InputEventMouseButton and not (ev as InputEventMouseButton).pressed:
		UILayout.set_pos(id, n.position)
		UILayout.save()
