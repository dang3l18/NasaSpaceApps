extends Control
## OPERACION: REFUGIO LUNAR - base lunar jugable (3 dias, 9 turnos).
## Los 14 modulos son interactivos: al elegir uno ves su funcion, estado, consumo, produccion y
## las tareas que puedes asignar. Todas las tareas gastan los 3 presupuestos compartidos
## (energia, materiales, horas) definidos en BaseState.
##
## Pruebas: godot --path <proyecto> res://scenes/LunarBase.tscn -- --shot=x.png [--turn=5] [--module=greenhouse] [--skip-intro]

signal data_loaded

const MAP_POS := Vector2(250, 110)
const HORIZON_Y := 235.0
const SHORT := {"habitat": "Hábitat", "dorms": "Dormir", "common": "Común", "lab": "Laboratorio", "life_support": "Soporte vital",
		"greenhouse": "Invernadero", "fertilization": "Abono", "infirmary": "Salud", "command": "Mando", "main_energy": "Energía",
		"backup_energy": "Respaldo", "shelter": "Refugio", "panels": "Paneles", "processing": "Materiales"}
const INDICATORS := [
	["vida", "💨", "SOPORTE VITAL"], ["proteccion", "🛡", "PROTECCIÓN"], ["energia", "⚡", "ENERGÍA"], ["alimentos", "🌱", "ALIMENTOS"]]
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
var _mount: PackedVector2Array = PackedVector2Array()
var _craters: Array = []
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
var _robot_hop := 0.0
var _last_tip := ""
var _info_open := false
var _moon_done := false
var _intro_pending := false


func _ready() -> void:
	randomize()
	s = BaseState.new(GameSettings.mode == "principiante")
	plan["led"] = s.led
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--turn="):
			s.turn = clampi(int(a.substr(7)), 1, SimConfig.TURNS)
	_gen_terrain()
	_build_ui()
	_load_data()
	_refresh_all()
	var skip := "--skip-intro" in OS.get_cmdline_user_args()
	_begin_turn(skip)
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
	_map.queue_redraw()
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

func _gen_terrain() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20262026
	for i in 170:
		_stars.append([Vector2(rng.randf() * 1280.0, rng.randf() * HORIZON_Y), rng.randf_range(0.6, 1.7), rng.randf_range(0.35, 1.0)])
	_mount.append(Vector2(0, HORIZON_Y))
	var x := 0.0
	while x <= 1300.0:
		var h := 18.0 + 22.0 * absf(sin(x * 0.011)) + 14.0 * absf(sin(x * 0.037 + 1.3)) + rng.randf_range(0.0, 7.0)
		_mount.append(Vector2(x, HORIZON_Y - h))
		x += 24.0
	_mount.append(Vector2(1300, HORIZON_Y))
	for i in 16:
		_craters.append([Vector2(rng.randf_range(20, 1260), rng.randf_range(HORIZON_Y + 30, 700)), rng.randf_range(24, 70)])


func _draw_world() -> void:
	var w := _world
	w.draw_rect(Rect2(0, 0, 1280, HORIZON_Y), Color("03050d"))
	for st in _stars:
		w.draw_circle(st[0], st[1], Color(1, 1, 1, st[2]))
	w.draw_colored_polygon(_mount, Color("55565e"))
	for i in 24:
		var y := HORIZON_Y + i * 21.0
		var c := Color("8d8d92").darkened(i * 0.022)
		w.draw_rect(Rect2(0, y, 1280, 22), c)
	for c in _craters:
		var p: Vector2 = c[0]
		var r: float = c[1]
		var pts := PackedVector2Array()
		for k in 28:
			var a := TAU * k / 28.0
			pts.append(p + Vector2(cos(a) * r, sin(a) * r * 0.32))
		w.draw_colored_polygon(pts, Color("6f6f75"))
		w.draw_polyline(pts + PackedVector2Array([pts[0]]), Color("b6b6bb"), 2.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 260:
		w.draw_circle(Vector2(rng.randf() * 1280.0, rng.randf_range(HORIZON_Y + 5, 720.0)), rng.randf_range(0.8, 2.2), Color(0.35, 0.35, 0.38, 0.6))


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
	m.draw_colored_polygon(pts, Color("77777f"))
	m.draw_polyline(pts, Color("a8a8b0"), 2.0)
	var door := Color("4dd6c8") if s.shelter > 50.0 else Color("f1b434")
	m.draw_rect(Rect2(r.get_center().x - 9, r.end.y - 22, 18, 22), door.darkened(0.2))


func _rover(m: Control) -> void:
	var busy: bool = ("process" in plan["tasks"]) or ("build_shield" in plan["tasks"]) or ("expand_bed" in plan["tasks"]) \
			or ("build_shelter" in plan["tasks"]) or ("expand_panel" in plan["tasks"])
	var speed := 1.0 if busy else 0.25
	var f := fmod(_t * 0.18 * speed + 0.0, 1.0)
	var tri := 1.0 - absf(f * 2.0 - 1.0)
	var a := Vector2(420, 520)
	var b := Vector2(560, 520)
	var p := a.lerp(b, tri)
	m.draw_rect(Rect2(p.x - 14, p.y - 12, 28, 12), Color("e0b94a"))
	m.draw_rect(Rect2(p.x - 6, p.y - 20, 14, 9), Color("aab2c4"))
	m.draw_circle(p + Vector2(-9, 2), 5.0, Color("2a2f3c"))
	m.draw_circle(p + Vector2(9, 2), 5.0, Color("2a2f3c"))
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
		_module_box.add_child(UI.lbl("👆 Toca un módulo de la base para ver qué hace y qué puedes hacer con él.", 15, UI.MUTED, true, 250))
		return
	var d: Dictionary = ModuleDefs.DEFS[selected]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_module_box.add_child(head)
	head.add_child(UI.lbl(d["icon"], 26))
	var nm := UI.lbl(d["name"], 18, UI.GOLD, true, 190)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nm)
	var lvl := _status_level(selected)
	head.add_child(UI.lbl("●", 26, UI.light_color(lvl)))
	_module_box.add_child(UI.lbl(d["func"], 14, UI.TEXT, true, 250))
	var st := PanelContainer.new()
	st.add_theme_stylebox_override("panel", UI.box(UI.light_color(lvl).darkened(0.7), UI.light_color(lvl), 2, 8, 5))
	st.add_child(UI.lbl(_state_text(selected), 13, UI.TEXT, true, 240))
	_module_box.add_child(st)
	_module_box.add_child(UI.lbl(_flow_text(selected), 13, Color("ffe08a"), true, 250))
	# Controles propios de cada modulo
	if selected == "greenhouse":
		_led_selector()
	if selected == "command":
		_command_controls()
	if selected == "lab":
		_lab_controls()
	for tid in d["tasks"]:
		_module_box.add_child(_task_button(tid))
	_info_section(d)


## Datos extra plegables: mantiene el panel corto para ninos y deja la ciencia a un toque.
func _info_section(d: Dictionary) -> void:
	var tg := UI.btn("ℹ Menos información" if _info_open else "ℹ Más información y ciencia NASA", Color("2a3b66"), func() -> void:
		_info_open = not _info_open
		_refresh_module_panel(), 12, 32)
	_module_box.add_child(tg)
	if not _info_open:
		return
	_module_box.add_child(UI.lbl("Necesita: " + d["needs"], 12, UI.MUTED, true, 250))
	_module_box.add_child(UI.lbl("Ojo: " + d["conseq"], 12, Color("ffd9a0"), true, 250))
	if d.has("ref"):
		var rb := PanelContainer.new()
		rb.add_theme_stylebox_override("panel", UI.box(Color("0c2230"), UI.REF, 2, 8, 6))
		var rv := VBoxContainer.new()
		rb.add_child(rv)
		rv.add_child(UI.badge(ScientificDataManager.LABEL_REF, 11))
		rv.add_child(UI.lbl(d["ref"]["text"], 12, UI.TEXT, true, 240))
		var lk := LinkButton.new()
		lk.text = d["ref"]["label"]
		lk.uri = d["ref"]["url"]
		lk.add_theme_font_size_override("font_size", 12)
		lk.add_theme_color_override("font_color", Color("6fb4ff"))
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
		"panels": return "☀ +%d por turno de día · 0 de noche" % (s.panels * SimConfig.PANEL_OUTPUT)
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
	var b := UI.btn("%s%s  %s\n⏱%dh  🧱%d  ⚡%d" % ["🔒 " if forced else ("✔ " if on else ""), c.get("icon", TASKS_ICON(tid)), BaseState.TASKS[tid]["name"],
			c["hours"], c["mat"], c["energy"]], Color("1f9f55") if on else Color("245aa8"), Callable(), 13, 46)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if not on:
		var test: Array = (plan["tasks"] as Array).duplicate()
		test.append(tid)
		b.disabled = not s.can_afford(test)
	if forced:
		b.disabled = true
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
		b.disabled = s.forced_led >= 0 and cur != i
		row.add_child(b)


func _command_controls() -> void:
	var b := UI.btn(("🔋 Ahorro de energía: ACTIVO" if s.saving else "🔋 Ahorro de energía: apagado"), Color("1f9f55") if s.saving else Color("245aa8"), _toggle_saving, 13, 40)
	_module_box.add_child(b)
	_module_box.add_child(UI.lbl("Ahorro: −30% en control y hogar, pero el laboratorio y los materiales rinden la mitad.", 12, UI.MUTED, true, 250))
	var nb := PanelContainer.new()
	nb.add_theme_stylebox_override("panel", UI.box(Color("1a1330"), UI.SIM, 2, 8, 6))
	var nv := VBoxContainer.new()
	nb.add_child(nv)
	nv.add_child(UI.lbl("📡 Alerta solar (NASA DONKI)", 13, UI.GOLD))
	nv.add_child(UI.badge(NasaBridge.label(), 11))
	nv.add_child(UI.lbl(NasaBridge.headline() if _event_loaded else "Consultando DONKI…", 12, UI.TEXT, true, 240))
	nv.add_child(UI.lbl(NasaBridge.mapping_text() if _event_loaded else "", 11, UI.MUTED, true, 240))
	_module_box.add_child(nb)


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
	_title_label.text = "DÍA %d · TURNO %d/%d" % [s.day_number(), mini(s.turn, SimConfig.TURNS), SimConfig.TURNS]
	_phase_label.text = ("☀ " if s.is_day() else "🌙 ") + PHASE_NAMES[(mini(s.turn, SimConfig.TURNS) - 1) % 3] + (" · luz solar" if s.is_day() else " · sin luz solar")


func _refresh_indicators() -> void:
	var ind := s.indicators()
	for k in INDICATORS:
		var row: Dictionary = _ind_rows[k[0]]
		var v: float = ind[k[0]]
		var lvl := UI.light_of(v)
		(row["dot"] as Label).add_theme_color_override("font_color", UI.light_color(lvl))
		var pb: ProgressBar = row["bar"]
		pb.value = v
		UI.set_bar_color(pb, UI.light_color(lvl))
		(row["val"] as Label).text = "%d%%" % int(v)
	(_ind_rows["vida"]["sub"] as Label).text = "O₂ %d · CO₂ %d · 💧 %d" % [s.o2, s.co2, s.water]
	(_ind_rows["proteccion"]["sub"] as Label).text = "Radiación recibida %d/100" % s.exposure
	(_ind_rows["energia"]["sub"] as Label).text = "Principal %d · Respaldo %d" % [s.main, s.backup]
	(_ind_rows["alimentos"]["sub"] as Label).text = "Comida %d · plantas %d%%" % [s.food, s.plant_health]


func _refresh_budget() -> void:
	var pv := s.preview(plan)
	var e_use: float = pv["energy_load"]
	var e_have: float = pv["energy_have"]
	_set_budget("energy", e_use, e_have, "⚡ Energía: usa %d de %d" % [e_use, e_have])
	_set_budget("mat", pv["mat"], maxf(1.0, s.materials), "🧱 Materiales: usa %d de %d" % [pv["mat"], s.materials])
	_set_budget("hours", pv["hours"], pv["hours_budget"], "⏱ Horas: usa %d de %d" % [pv["hours"], pv["hours_budget"]])
	_end_btn.disabled = not bool(pv["ok"]) or s.finished
	_warn.text = str(pv["why"])
	if e_use > e_have:
		_warn.text = "Falta energía: se apagará lo menos importante"


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
		return "¡Tormenta solar! Revisa el refugio y su energía."
	if s.energy_total() < 250.0:
		return "¡Recuerda reservar energía para el oxígeno!"
	if s.exposure > 40.0:
		return "La radiación sube. Más blindaje protege a tu equipo, pero utiliza materiales."
	if s.food < 25.0:
		return "Poca comida. Cuida las plantas y dales luz."
	if s.plant_health < 50.0:
		return "Tus plantas necesitan cuidados."
	if s.ls_cond < 50.0:
		return "El soporte vital está cansado. ¡Necesita mantenimiento!"
	if ind["proteccion"] < 40.0 and s.turn < s.alert_turn:
		return "Aún falta protección. Una tormenta solar se acerca."
	var generic := ["Más luz ayuda a tus plantas, pero consume energía.", "Más blindaje protege a tu equipo, pero utiliza materiales.",
			"¡Recuerda reservar energía para el oxígeno!", "Las plantas ayudan con el aire, pero no lo hacen todo."]
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
	if s.turn == 1 and not skip_intro:
		_show_intro()
		return
	if cards.size() > 0:
		_show_card(cards[0], news)
	else:
		if news.size() > 0:
			_show_banner(str(news[0]))
		if s.turn == SimConfig.ALERT_TURN:
			_show_alert_modal(news)


func _show_intro() -> void:
	_intro_pending = true
	await _wait_moon()
	_intro_pending = false
	var v := _modal("OPERACIÓN: REFUGIO LUNAR", UI.GOLD, 720)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	if _moon_tex != null:
		var col := VBoxContainer.new()
		row.add_child(col)
		var tr := TextureRect.new()
		tr.texture = _moon_tex
		tr.custom_minimum_size = Vector2(250, 125)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		col.add_child(tr)
		col.add_child(UI.lbl(_moon_note, 11, UI.MUTED, true, 250))
		col.add_child(UI.badge(ScientificDataManager.LABEL_HISTORIC, 11))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	info.add_child(UI.lbl("Tu base está en la Luna. Sobrevive 3 días (9 turnos).", 17, UI.TEXT, true, 380))
	for r in [["💨", "Soporte vital: aire y agua"], ["🛡", "Protección contra la radiación"], ["⚡", "Energía para todo"], ["🌱", "Alimentos de tus plantas"]]:
		info.add_child(UI.lbl("%s  %s" % [r[0], r[1]], 16, UI.TEXT))
	info.add_child(UI.lbl("Todo compite por ⚡ energía, 🧱 materiales y ⏱ horas. Mejorar una parte puede dañar otra.", 14, Color("ffd9a0"), true, 380))
	v.add_child(UI.lbl("🤖 «¡Hola, Comandante! Toca los módulos de la base y elige qué hacer cada turno.»", 14, UI.MUTED, true, 600))
	v.add_child(UI.btn("¡Empezar misión!", Color("1f9f55"), func() -> void:
		_close_modal()
		_show_banner("☀ Es de día en la Luna. Los paneles solares cargan las baterías."), 20, 50))


func _show_card(card: Dictionary, news: Array) -> void:
	var v := _modal("%s  %s" % [card["icon"], card["title"]], UI.GOLD, 760)
	if news.size() > 0:
		v.add_child(UI.lbl(str(news[0]), 14, UI.MUTED, true, 640))
	v.add_child(UI.lbl(card["question"], 17, UI.TEXT, true, 640))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var choice := {"i": -1}
	var buttons: Array = []
	var ok := UI.btn("Confirmar", Color("1f9f55"), Callable(), 18, 46)
	ok.disabled = true
	var cols := [Color("2f7de0"), Color("e0a02f"), Color("8e5be0")]
	var opts: Array = card["options"]
	for i in opts.size():
		var o: Dictionary = opts[i]
		var txt := "%s\n" % o["label"]
		for g in o.get("good", []):
			txt += "\n✔ %s" % g
		for b in o.get("bad", []):
			txt += "\n✘ %s" % b
		var cb := Button.new()
		cb.toggle_mode = true
		cb.text = txt
		cb.custom_minimum_size = Vector2(0, 170)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cb.add_theme_font_size_override("font_size", 14)
		cb.add_theme_stylebox_override("normal", UI.box(Color("0f2150"), cols[i % 3].darkened(0.2), 2, 12, 10))
		cb.add_theme_stylebox_override("hover", UI.box(Color("17327a"), cols[i % 3], 2, 12, 10))
		cb.add_theme_stylebox_override("pressed", UI.box(cols[i % 3].darkened(0.55), cols[i % 3].lightened(0.3), 4, 12, 10))
		cb.add_theme_stylebox_override("disabled", UI.box(Color("11151f"), Color("2a3550"), 2, 12, 10))
		cb.disabled = not bool(o.get("affordable", true))
		if cb.disabled:
			cb.text += "\n\n(no alcanzan materiales u horas)"
		row.add_child(cb)
		buttons.append(cb)
		cb.pressed.connect(func() -> void:
			choice["i"] = i
			ok.disabled = false
			for j in buttons.size():
				(buttons[j] as Button).button_pressed = j == i)
	ok.pressed.connect(func() -> void:
		MissionDirector.choose(s, card, int(choice["i"]))
		_close_modal()
		plan["led"] = s.forced_led if s.forced_led >= 0 else s.led
		_refresh_all()
		_tip.text = _robot_tip())
	v.add_child(UI.lbl("💡 Compara costes y beneficios antes de confirmar. No hay una opción siempre mejor.", 13, UI.MUTED, true, 640))
	v.add_child(ok)


func _show_alert_modal(news: Array) -> void:
	var v := _modal("🚨 ¡ALERTA SOLAR!", UI.RED, 700)
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(UI.lbl(NasaBridge.headline(), 17, UI.GOLD, true, 420))
	head.add_child(UI.badge(NasaBridge.label()))
	v.add_child(UI.lbl("Hoy el refugio necesita ⚡ 40 de energía. Tu blindaje y tu refugio frenarán la radiación.", 15, UI.TEXT, true, 600))
	v.add_child(UI.lbl(NasaBridge.mapping_text(), 12, UI.MUTED, true, 600))
	var ind := s.indicators()
	v.add_child(UI.lbl("Tu protección ahora: %d%%" % int(ind["proteccion"]), 16, UI.light_color(UI.light_of(ind["proteccion"]))))
	v.add_child(UI.btn("Entendido", Color("1f6fd0"), _close_modal, 18, 46))


func _end_turn() -> void:
	if s.finished or _modal_root != null or _intro_pending:
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
	var v := _modal("RESUMEN DEL TURNO %d" % turn_done, UI.GOLD, 640)
	var before: Dictionary = r["before"]
	var after: Dictionary = r["after"]
	for k in INDICATORS:
		var b: float = before[k[0]]
		var a: float = after[k[0]]
		var d := a - b
		var arrow := "▲" if d > 1.0 else ("▼" if d < -1.0 else "■")
		var col := UI.GREEN if d > 1.0 else (UI.RED if d < -1.0 else UI.MUTED)
		var row := HBoxContainer.new()
		v.add_child(row)
		var n := UI.lbl("%s %s" % [k[1], k[2]], 16, UI.TEXT)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
		row.add_child(UI.lbl("%d%%  %s %d" % [int(a), arrow, int(absf(d))], 16, col))
	for m in r["msgs"]:
		v.add_child(UI.lbl("• " + str(m), 14, Color("ffd9a0"), true, 560))
	if not s.finished:
		v.add_child(UI.lbl("🤖 " + _robot_tip(), 14, UI.MUTED, true, 560))
	v.add_child(UI.btn("Continuar", Color("1f6fd0"), func() -> void:
		_close_modal()
		if s.finished:
			_show_end()
		else:
			_begin_turn(), 18, 46))


func _show_end() -> void:
	if not _simulated and not ("--shot=" in "".join(OS.get_cmdline_user_args())):
		Progress.record_game(s.won, GameSettings.mode, s.shield >= 65.0, NasaBridge.alert_tier())
	var v := _modal("¡MISIÓN COMPLETADA!" if s.won else "MISIÓN NO COMPLETADA", UI.GOLD if s.won else UI.RED, 760)
	v.add_child(UI.lbl(s.reason, 17, UI.TEXT, true, 680))
	var ind := s.indicators()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	for k in INDICATORS:
		row.add_child(UI.lbl("%s %d%%" % [k[1], int(ind[k[0]])], 16, UI.light_color(UI.light_of(ind[k[0]]))))
	v.add_child(UI.lbl("Tus decisiones importantes:", 15, UI.GOLD))
	for d in s.decisions:
		var good := ", ".join(PackedStringArray(d["good"]))
		var bad := ", ".join(PackedStringArray(d["bad"]))
		v.add_child(UI.lbl("T%d · %s → %s\n   ✔ %s · ✘ %s" % [d["turn"], d["title"], d["choice"], good, bad], 12, UI.MUTED, true, 680))
	if s.won:
		v.add_child(UI.lbl("Aprendiste que mejorar una parte de la base puede perjudicar otra. ¡Equilibrar los 4 sistemas fue la clave!", 14, Color("7be88a"), true, 680))
	else:
		v.add_child(UI.lbl("No pasa nada: así se aprende. Prueba repartir mejor energía, materiales y horas.", 14, Color("ffd9a0"), true, 680))
	var b1 := HBoxContainer.new()
	b1.add_theme_constant_override("separation", 8)
	v.add_child(b1)
	for bb in [["Jugar de nuevo", Color("1f9f55"), func() -> void: get_tree().reload_current_scene()],
			["Space Data Center", Color("1f6fd0"), _open_data_center], ["Menú principal", Color("245aa8"), _go_menu]]:
		var btn := UI.btn(bb[0], bb[1], bb[2], 15, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b1.add_child(btn)


func _go_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _open_data_center() -> void:
	Progress.unlock("data_scientist")
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
	var t := UI.lbl(title, 24, title_col)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	return v


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
	# De noche solo se oscurece el terreno: la Tierra y la base (con luces propias) siguen brillando.
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
	cap.position = Vector2(790, 176)
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
	p.position = Vector2(300, 8)
	p.custom_minimum_size = Vector2(480, 0)
	p.add_theme_stylebox_override("panel", UI.box(Color(0.04, 0.09, 0.22, 0.92), UI.BORDER, 2, 12, 6))
	add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	var t := UI.lbl("MISIÓN: OPERACIÓN REFUGIO LUNAR", 15, UI.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	_title_label = UI.lbl("", 18)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title_label)
	_phase_label = UI.lbl("", 13, UI.MUTED)
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_phase_label)
	_banner = UI.lbl("", 15, UI.GOLD, true, 600)
	_banner.position = Vector2(250, 98)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner.add_theme_constant_override("outline_size", 6)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.custom_minimum_size = Vector2(700, 0)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.modulate.a = 0.0
	add_child(_banner)
	var mb := UI.btn("☰ Menú", Color("245aa8"), _go_menu, 14, 34)
	mb.position = Vector2(14, 8)
	mb.custom_minimum_size = Vector2(100, 34)
	add_child(mb)
	var sub := UI.lbl(GameSettings.mode_label().to_upper(), 11, UI.MUTED)
	sub.position = Vector2(14, 46)
	add_child(sub)


func _build_indicators() -> void:
	var p := PanelContainer.new()
	p.position = Vector2(12, 66)
	p.custom_minimum_size = Vector2(228, 0)
	p.add_theme_stylebox_override("panel", UI.box(Color(0.04, 0.09, 0.22, 0.92), UI.BORDER, 2, 10, 8))
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 9)
	p.add_child(v)
	for k in INDICATORS:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 1)
		v.add_child(col)
		var top := HBoxContainer.new()
		col.add_child(top)
		var n := UI.lbl("%s %s" % [k[1], k[2]], 14, UI.TEXT)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(n)
		var dot := UI.lbl("●", 18, UI.GREEN)
		top.add_child(dot)
		var val := UI.lbl("", 14, UI.TEXT)
		top.add_child(val)
		var pb := UI.bar(100, 100, UI.GREEN, 14)
		col.add_child(pb)
		var sub := UI.lbl("", 11, UI.MUTED)
		col.add_child(sub)
		_ind_rows[k[0]] = {"dot": dot, "bar": pb, "val": val, "sub": sub}


func _build_robot() -> void:
	var p := PanelContainer.new()
	p.position = Vector2(12, 478)
	p.custom_minimum_size = Vector2(228, 0)
	p.add_theme_stylebox_override("panel", UI.box(Color(0.04, 0.09, 0.22, 0.92), UI.BORDER, 2, 10, 8))
	add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	var rb := Control.new()
	rb.custom_minimum_size = Vector2(62, 84)
	rb.draw.connect(func() -> void:
		var bob := sin(_t * 2.0) * 2.0 - _robot_hop * 10.0
		rb.draw_circle(Vector2(31, 82), 20.0, Color(0, 0, 0, 0.0))
		# cuerpo, brazos y cabeza
		rb.draw_style_box(_sb(Color("5a7bd0"), 8, Color("3a56a8")), Rect2(17, 58 + bob, 28, 20))
		rb.draw_circle(Vector2(31, 62 + bob), 5.0, Color("ffd24d"))
		rb.draw_circle(Vector2(31, 36 + bob), 27.0, Color("eef2f8"))
		rb.draw_arc(Vector2(31, 36 + bob), 27.0, 0, TAU, 40, Color("aab6cf"), 3.0)
		rb.draw_circle(Vector2(31, 37 + bob), 20.0, Color("0c1730"))
		var blink: bool = fmod(_t, 3.4) > 3.25
		var ey := 4.0 if not blink else 1.0
		rb.draw_rect(Rect2(21, 34 + bob - ey * 0.5, 7, ey * 2.0), Color("5fe0ff"))
		rb.draw_rect(Rect2(35, 34 + bob - ey * 0.5, 7, ey * 2.0), Color("5fe0ff"))
		rb.draw_arc(Vector2(31, 41 + bob), 6.0, 0.15 * PI, 0.85 * PI, 10, Color("5fe0ff"), 2.0)
		rb.draw_line(Vector2(31, 9 + bob), Vector2(31, 1 + bob), Color("aab2c4"), 3.0)
		rb.draw_circle(Vector2(31, 1 + bob), 3.5, Color("ff5d5d") if fmod(_t, 1.0) < 0.5 else Color("ff9d9d")))
	var tmr := Timer.new()
	tmr.wait_time = 0.05
	tmr.autostart = true
	tmr.timeout.connect(rb.queue_redraw)
	rb.add_child(tmr)
	h.add_child(rb)
	_tip = UI.lbl("", 13, UI.TEXT, true, 150)
	_tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_tip)


func _build_right() -> void:
	var col := VBoxContainer.new()
	col.position = Vector2(962, 8)
	col.custom_minimum_size = Vector2(306, 0)
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var bp := PanelContainer.new()
	bp.add_theme_stylebox_override("panel", UI.box(Color(0.04, 0.09, 0.22, 0.94), UI.BORDER, 2, 10, 8))
	col.add_child(bp)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 3)
	bp.add_child(bv)
	var top := HBoxContainer.new()
	bv.add_child(top)
	var bt := UI.lbl("RECURSOS DE ESTE TURNO", 13, UI.GOLD)
	bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(bt)
	var dcb := UI.btn("📊 Datos", Color("1f6fd0"), _open_data_center, 12, 26)
	top.add_child(dcb)
	for k in [["energy", UI.YELLOW], ["mat", Color("c9b27a")], ["hours", Color("7fb3ff")]]:
		var lab := UI.lbl("", 13, UI.TEXT)
		bv.add_child(lab)
		var pb := UI.bar(0, 100, k[1], 12)
		bv.add_child(pb)
		_budget[k[0]] = {"label": lab, "bar": pb}
	_warn = UI.lbl("", 12, UI.RED, true, 280)
	bv.add_child(_warn)
	_end_btn = UI.btn("Finalizar turno ▶▶", Color("1f9f55"), _end_turn, 17, 42)
	bv.add_child(_end_btn)
	var mp := PanelContainer.new()
	mp.custom_minimum_size = Vector2(0, 420)
	mp.add_theme_stylebox_override("panel", UI.box(Color(0.04, 0.09, 0.22, 0.94), UI.BORDER, 2, 10, 8))
	col.add_child(mp)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mp.add_child(sc)
	_module_box = VBoxContainer.new()
	_module_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_module_box.add_theme_constant_override("separation", 6)
	sc.add_child(_module_box)
