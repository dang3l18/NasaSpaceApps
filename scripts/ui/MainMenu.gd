extends Control
## Menu del juego: titulo, seleccion de modo, aprender sobre la NASA, logros,
## configuracion (estado real de las fuentes de datos) y creditos (atribuciones reales).
## Pruebas:  godot --path <proyecto> -- --screen=title|modes|learn|achievements|config|credits --shot=x.png

const C_BG := Color("02040c")
const C_PANEL := Color("0a1838")
const C_BORDER := Color("2f6fd6")
const C_TEXT := Color("e8f1ff")
const C_MUTED := Color("8fa8d0")
const C_GOLD := Color("ffd24d")
const C_GREEN := Color("2ecc71")

## [titulo, tipo, texto corto]. Los tipos moon/earth/sun/radiation/data consultan datos reales de
## NASA/NOAA al abrirse; ref_* son documentacion (no hay una medicion en vivo de ese tema).
const LEARN := [
	["🌙 La Luna", "moon", "La nave LRO de NASA cartografió la superficie lunar y midió su temperatura, composición y entorno de radiación."],
	["🌍 La Tierra hoy", "earth", "Así se ve la Tierra desde el espacio. NASA GIBS publica imágenes de satélite casi todos los días."],
	["☀ El Sol hoy", "sun", "El Sol lanza llamaradas y nubes de plasma llamadas CME. NASA DONKI las registra todos los días."],
	["☢ Radiación hoy", "radiation", "En la Luna no hay atmósfera que nos proteja. NOAA mide las tormentas de radiación solar con la escala S."],
	["💨 Soporte vital", "ref_eclss", "NASA divide el soporte vital en tres partes: recuperar agua, limpiar el aire y producir oxígeno. En el juego ese sistema gasta energía y necesita mantenimiento."],
	["🌱 Plantas", "ref_veggie", "NASA cultiva lechugas en el espacio con luces LED como comida fresca extra. Las plantas ayudan, pero no reemplazan a los sistemas de la base."],
	["📊 Datos de NASA", "data", "Estas son las fuentes que usa el juego y cuándo se consultaron por última vez."],
]
const ORIGIN_TEXT := {"network": "descargado ahora", "cache_fresh": "copia guardada vigente", "cache_stale": "copia guardada (sin conexión)", "none": "sin datos"}

var _earth: ColorRect
var _astro: Control
var _screens: Dictionary = {}
var _t := 0.0
var _stars: Array = []
var _stars_node: Control
var _learn_box: VBoxContainer
var _learn_buttons: Array = []
var _learn_token := 0
var _learn_cur := 0
var _learn_last_refresh := 0
var _ach_list: VBoxContainer
var _cfg_list: VBoxContainer
var _ui_checks := {}
var _mission_q: Label
var _mission_row: HBoxContainer
var _tier_row: HBoxContainer
var _mission_tier := 1
var _br_mods: Label
var _br_title: Label
var _br_diff: Label
var _br_dilemma: Label
var _br_text: Label
var _br_protect: Label
var _br_sacrifice: Label
var _br_obj: Label
var _br_victory: Label
var _credits_list: VBoxContainer


func _ready() -> void:
	randomize()
	for i in 150:
		_stars.append([Vector2(randf() * 1280.0, randf() * 720.0), randf_range(0.6, 1.8), randf_range(0.35, 1.0)])
	_build_background()
	_build_astronaut()
	_build_title()
	_build_modes()
	_build_missions()
	_build_briefing()
	_build_learn()
	_build_achievements()
	_build_config()
	_build_credits()
	var first := GameSettings.start_screen
	GameSettings.start_screen = "title"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screen="):
			first = a.substr(9)
		if a.begins_with("--tier="):
			_mission_tier = clampi(int(a.substr(7)), 1, 3)
		if a.begins_with("--briefing="):   # solo pruebas: abrir el dilema de una mision
			MissionManager.reload()
			_open_briefing(a.substr(11))
			first = "briefing"
	_show(first)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--topic="):
			_pick_topic(clampi(int(a.substr(8)), 0, LEARN.size() - 1))
	_fade_in()
	_load_earth()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			await get_tree().create_timer(1.5).timeout
			get_viewport().get_texture().get_image().save_png(a.substr(7))
			get_tree().quit()


func _process(delta: float) -> void:
	_t += delta
	_earth.material.set_shader_parameter("rot", _t * 0.04)
	if _astro.visible:
		_astro.queue_redraw()


func _load_earth() -> void:
	var r: Dictionary = await EarthImageryManager.get_earth("modis_truecolor")
	if r.get("ok", false):
		_earth.material.set_shader_parameter("earth", r["texture"])
		_earth.material.set_shader_parameter("has_tex", true)


func _show(name: String) -> void:
	for k in _screens:
		(_screens[k] as Control).visible = k == name
	_astro.visible = name == "title" or name == "modes"
	match name:
		"achievements": _fill_achievements()
		"config": _fill_config()
		"credits": _fill_credits()
		"missions":
			_mission_q.text = "Elige tu destino · %s" % GameSettings.mode_label()
			_fill_missions()
		"learn": _pick_topic(0)


# ---------------------------------------------------------------- PANTALLAS ----

func _build_title() -> void:
	var s := _screen("title")
	var v := _center_column(s, 420)
	var t1 := _lbl("ZYRANTH", 76, Color("3d8bff"), false)
	var bold := FontVariation.new()
	bold.base_font = ThemeDB.fallback_font
	bold.variation_embolden = 0.7
	t1.add_theme_font_override("font", bold)
	t1.add_theme_color_override("font_outline_color", Color("0a1d4a"))
	t1.add_theme_constant_override("outline_size", 8)
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t1)
	var t3 := _lbl("JUNIOR ASTRONAUT · MISSION TRAINER", 15, C_GOLD, false)
	t3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t3)
	var sub := _lbl("Aprende · Decide · Sobrevive", 16, C_MUTED, false)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(_spacer(16))
	v.add_child(_btn("JUGAR  ▶", Color("e0a02f"), func() -> void: _show("modes"), 26, 64))
	v.add_child(_btn("Aprender sobre la NASA", Color("245aa8"), func() -> void: _show("learn")))
	v.add_child(_btn("Logros", Color("245aa8"), func() -> void: _show("achievements")))
	v.add_child(_btn("Configuración", Color("245aa8"), func() -> void: _show("config")))
	v.add_child(_btn("Créditos", Color("245aa8"), func() -> void: _show("credits")))
	var note := _lbl("Datos de NASA: DONKI · GIBS · LRO · Earthdata", 12, C_MUTED, false)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(note)


func _build_modes() -> void:
	var s := _screen("modes")
	var v := _center_column(s, 640)
	var h := _lbl("MENÚ PRINCIPAL", 30, C_TEXT, false)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	var q := _lbl("Elige tu edad: el juego se adapta", 16, C_MUTED, false)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(q)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	row.add_child(_mode_card("🚀  MODO 7–9 AÑOS", "con más ayuda", "+4 horas de trabajo por turno\nAlertas solares más suaves", "principiante", Color("2f7de0")))
	row.add_child(_mode_card("⭐  MODO 10–12 AÑOS", "reglas completas", "Horas de trabajo normales\nAlertas solares completas", "intermedio", Color("e0a02f")))
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 14)
	v.add_child(row2)
	var b1 := _btn("📖  Aprender sobre la NASA", Color("245aa8"), func() -> void: _show("learn"))
	b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(b1)
	var b2 := _btn("🏆  Logros", Color("245aa8"), func() -> void: _show("achievements"))
	b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(b2)
	v.add_child(_btn("← Volver", Color("1f6fd0"), func() -> void: _show("title")))


func _mode_card(title: String, age: String, desc: String, mode: String, col: Color) -> Button:
	var b := Button.new()
	b.text = "%s\n(%s)\n\n%s" % [title, age, desc]
	b.custom_minimum_size = Vector2(0, 150)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_stylebox_override("normal", _box(Color("0f2150"), col, 3, 12))
	b.add_theme_stylebox_override("hover", _box(Color("17327a"), col.lightened(0.3), 3, 12))
	b.add_theme_stylebox_override("pressed", _box(col.darkened(0.5), col.lightened(0.3), 3, 12))
	b.pressed.connect(func() -> void:
		GameSettings.mode = mode
		_show("missions"))
	return b


## Seleccion de mision: se reconstruye cada vez que se abre, con dificultad, candados y progreso
## (todo viene de MissionManager). Una mision se desbloquea al superar la anterior.
func _build_missions() -> void:
	var s := _screen("missions")
	var v := _center_column(s, 1040)
	var h := _lbl("SELECCIÓN DE MISIÓN", 30, C_TEXT, false)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	var q := _lbl("Elige tu destino", 16, C_MUTED, false)
	_mission_q = q
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(q)
	_tier_row = HBoxContainer.new()
	_tier_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_tier_row.add_theme_constant_override("separation", 10)
	v.add_child(_tier_row)
	_mission_row = HBoxContainer.new()
	_mission_row.add_theme_constant_override("separation", 12)
	v.add_child(_mission_row)
	var hint := _lbl("Supera cada misión para desbloquear la siguiente.", 13, C_MUTED, false)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	v.add_child(_btn("← Volver", Color("1f6fd0"), func() -> void: _show("modes")))


## Pestañas de nivel (Fácil / Intermedia / Avanzada) con el progreso de cada una.
func _fill_tabs() -> void:
	for c in _tier_row.get_children():
		c.queue_free()
	for t in [1, 2, 3]:
		var list := MissionManager.of_tier(t)
		var done := 0
		var playable := 0
		for m in list:
			if m.ready:
				playable += 1
			if MissionManager.is_completed(m.id):
				done += 1
		var col: Color = MissionDef.TIER_COLORS[t] if t == _mission_tier else Color("34456b")
		var label := "%s%s" % [MissionDef.TIER_NAMES[t].to_upper(), ("  %d/%d" % [done, playable]) if playable > 0 else "  🔒"]
		var b := _btn(label, col.darkened(0.35) if t == _mission_tier else Color("1a2440"), func() -> void:
			_mission_tier = t
			_fill_missions(), 15, 38)
		b.custom_minimum_size = Vector2(190, 38)
		if t == _mission_tier:
			for st in ["normal", "hover", "pressed"]:
				b.add_theme_stylebox_override(st, _box(col.darkened(0.45), col, 3, 10))
		_tier_row.add_child(b)


func _fill_missions() -> void:
	_fill_tabs()
	for c in _mission_row.get_children():
		c.queue_free()
	for m in MissionManager.of_tier(_mission_tier):
		var unlocked := MissionManager.is_unlocked(m.id)
		var done := MissionManager.is_completed(m.id)
		var col := (Color("2ecc71") if done else Color("2f7de0")) if unlocked else Color("5b6478")
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", _box(Color("0f2150") if unlocked else Color("141a2c"), col, 3, 14))
		_mission_row.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 6)
		card.add_child(cv)
		var ic := _lbl(m.icon if unlocked or not m.ready else "🔒", 46, C_TEXT, false)
		ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(ic)
		cv.add_child(_lbl(m.title, 16, C_GOLD if unlocked else C_MUTED, true, 210))
		cv.add_child(_lbl(m.place, 12, C_MUTED, true, 210))
		cv.add_child(_lbl("%s  %s" % [m.stars(), m.difficulty_label()], 14, m.difficulty_color() if unlocked else C_MUTED, false))
		if m.ready and (m.consumption_factor > 1.001 or m.event_aggression > 0.0):
			cv.add_child(_lbl("⚙ " + m.modifiers_text(), 11, C_MUTED, true, 210))
		cv.add_child(_lbl(m.summary, 12, C_MUTED, true, 210))
		var status := "✔ Superada" if done else ("" if unlocked else "🔒 " + MissionManager.lock_reason(m.id))
		if status != "":
			cv.add_child(_lbl(status, 12, C_GREEN if done else Color("ffb07a"), true, 210))
		var btn := _btn("Ver dilema ▶" if unlocked else "Bloqueada", Color("1f9f55") if unlocked else Color("3a4258"), Callable(), 15, 40)
		btn.disabled = not unlocked
		if unlocked:
			btn.pressed.connect(_open_briefing.bind(m.id))
		cv.add_child(btn)


## Pantalla de dilema: antes de empezar, la mision explica que se protege y que se sacrifica.
func _build_briefing() -> void:
	var s := _screen("briefing")
	var v := _center_column(s, 800)
	_br_title = _lbl("", 28, C_GOLD, false)
	_br_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_br_title)
	_br_diff = _lbl("", 16, C_TEXT, false)
	_br_diff.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_br_diff)
	_br_mods = _lbl("", 13, C_MUTED, false)
	_br_mods.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_br_mods)
	var dil := PanelContainer.new()
	dil.add_theme_stylebox_override("panel", _box(Color("1a1330"), Color("b07cff"), 3, 14))
	v.add_child(dil)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 8)
	dil.add_child(dv)
	_br_dilemma = _lbl("", 20, C_GOLD, true, 700)
	dv.add_child(_br_dilemma)
	_br_text = _lbl("", 14, C_TEXT, true, 700)
	dv.add_child(_br_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	dv.add_child(row)
	var pp := PanelContainer.new()
	pp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pp.add_theme_stylebox_override("panel", _box(Color("10301f"), C_GREEN, 2, 10))
	row.add_child(pp)
	var pv := VBoxContainer.new()
	pp.add_child(pv)
	pv.add_child(_lbl("🛡 PROTEGES", 14, C_GREEN, false))
	_br_protect = _lbl("", 14, C_TEXT, true, 300)
	pv.add_child(_br_protect)
	var sp := PanelContainer.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.add_theme_stylebox_override("panel", _box(Color("33170f"), Color("ff8a3d"), 2, 10))
	row.add_child(sp)
	var sv := VBoxContainer.new()
	sp.add_child(sv)
	sv.add_child(_lbl("✂ SACRIFICAS", 14, Color("ff8a3d"), false))
	_br_sacrifice = _lbl("", 14, C_TEXT, true, 300)
	sv.add_child(_br_sacrifice)
	_br_obj = _lbl("", 13, C_TEXT, true, 760)
	v.add_child(_br_obj)
	_br_victory = _lbl("", 13, C_MUTED, true, 760)
	v.add_child(_br_victory)
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", 10)
	v.add_child(b)
	var start := _btn("▶ Empezar misión", Color("1f9f55"), func() -> void:
		get_tree().change_scene_to_file(MissionManager.current.scene), 20, 50)
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_child(start)
	var back := _btn("← Volver", Color("1f6fd0"), func() -> void: _show("missions"), 16, 50)
	back.custom_minimum_size = Vector2(160, 50)
	b.add_child(back)


func _open_briefing(id: String) -> void:
	if not MissionManager.select(id):
		return
	var m := MissionManager.current
	_br_title.text = "%s %s" % [m.icon, m.title.to_upper()]
	_br_diff.text = "Nivel %s · %s  Dificultad: %s" % [m.tier_label(), m.stars(), m.difficulty_label()]
	_br_diff.add_theme_color_override("font_color", m.difficulty_color())
	_br_mods.text = "Modificadores de esta misión: " + m.modifiers_text()
	_br_dilemma.text = "⚖ DILEMA: " + m.dilemma_title
	_br_text.text = m.dilemma_text
	_br_protect.text = m.protect
	_br_sacrifice.text = m.sacrifice
	_br_obj.text = "Objetivos:\n" + "\n".join(PackedStringArray(Array(m.objectives).map(func(o: String) -> String: return "• " + o)))
	_br_victory.text = "Victoria: " + m.victory_text
	_show("briefing")


func _build_learn() -> void:
	var s := _screen("learn")
	var v := _center_column(s, 820)
	var h := _lbl("APRENDE MÁS", 30, C_TEXT, false)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	v.add_child(body)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(230, 0)
	side.add_theme_constant_override("separation", 6)
	body.add_child(side)
	for i in LEARN.size():
		var b := _btn(LEARN[i][0], Color("245aa8"), _pick_topic.bind(i))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		side.add_child(b)
		_learn_buttons.append(b)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _box(Color("0f2150"), C_BORDER, 2, 12))
	body.add_child(panel)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(520, 330)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(sc)
	_learn_box = VBoxContainer.new()
	_learn_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_learn_box.add_theme_constant_override("separation", 8)
	sc.add_child(_learn_box)
	var cap := _lbl("Los temas con ☀ 🌍 🌙 ☢ 📊 consultan datos reales de NASA/NOAA al abrirse (con copia guardada si no hay internet).", 12, C_MUTED, true)
	v.add_child(cap)
	v.add_child(_btn("← Volver", Color("1f6fd0"), func() -> void: _show("title")))


func _pick_topic(i: int) -> void:
	_learn_token += 1
	_learn_cur = i
	var token := _learn_token
	for j in _learn_buttons.size():
		var col := Color("1f9f55") if j == i else Color("245aa8")
		for st in ["normal", "hover", "pressed"]:
			(_learn_buttons[j] as Button).add_theme_stylebox_override(st, _box(col, col.lightened(0.4), 2, 8))
	for c in _learn_box.get_children():
		c.queue_free()
	var kind: String = LEARN[i][1]
	_learn_box.add_child(_lbl(LEARN[i][0], 22, C_GOLD, false))
	_learn_box.add_child(_lbl(LEARN[i][2], 15, C_TEXT, true, 470))
	var live := VBoxContainer.new()
	live.add_theme_constant_override("separation", 6)
	_learn_box.add_child(live)
	match kind:
		"moon", "earth": await _topic_image(live, kind, token)
		"sun": await _topic_sun(live, token)
		"radiation": await _topic_radiation(live, token)
		"data": _topic_data(live)
		_: _topic_ref(live, kind.trim_prefix("ref_"))
	if token == _learn_token and kind in ["moon", "earth", "sun", "radiation"]:
		_learn_box.add_child(_btn("↻ Actualizar ahora", Color("1f6fd0"), _refresh_topic, 14, 34))


## Vuelve a consultar el tema abierto (como maximo una vez por minuto, para no repetir peticiones).
func _refresh_topic() -> void:
	var now := Time.get_ticks_msec()
	if now - _learn_last_refresh < 60000:
		return
	_learn_last_refresh = now
	NASADataManager.force_stale = true
	await _pick_topic(_learn_cur)
	NASADataManager.force_stale = false


func _alive(token: int, live: Control) -> bool:
	return token == _learn_token and is_instance_valid(live)


func _source_line(live: Control, source: String, label: String, retrieved: float, origin: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	live.add_child(row)
	row.add_child(UI.badge(label, 12))
	var when := ("consultado %s" % DatasetManager.format_time(retrieved)) if retrieved > 0 else "sin consulta"
	row.add_child(_lbl("%s · %s · %s" % [source, when, ORIGIN_TEXT.get(origin, origin)], 12, C_MUTED, true, 330))


func _wait_label(live: Control) -> Label:
	var l := _lbl("⏳ Consultando NASA…", 14, C_MUTED, false)
	live.add_child(l)
	return l


func _topic_image(live: Control, kind: String, token: int) -> void:
	var wait := _wait_label(live)
	var key := "lro_wac" if kind == "moon" else "modis_truecolor"
	var r: Dictionary = await EarthImageryManager.get_earth(key)
	if not _alive(token, live):
		return
	wait.queue_free()
	if not r.get("ok", false):
		live.add_child(_lbl("🖼 No hay imagen ahora (%s). El juego sigue funcionando." % r.get("error", "sin conexión"), 14, Color("ff9d9d"), true, 470))
		return
	var tr := TextureRect.new()
	tr.texture = r["texture"]
	tr.custom_minimum_size = Vector2(0, 170)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	live.add_child(tr)
	var what := "Imagen de la Tierra de hoy (MODIS Terra) del %s" % r["image_date"] if kind == "earth" else "Mosaico real de la Luna (LRO WAC), sin una fecha de captura única"
	live.add_child(_lbl(what, 14, C_TEXT, true, 470))
	_source_line(live, "NASA GIBS" if kind == "earth" else "NASA LRO · Moon Trek", r["classification"], r["retrieved_at"], "cache_fresh" if r["from_cache"] else "network")


func _topic_sun(live: Control, token: int) -> void:
	var wait := _wait_label(live)
	var ev: Dictionary = await ScientificDataManager.build_solar_event()
	var fl_res: Dictionary = await NASADataManager.donki("FLR", 30)
	var cme_res: Dictionary = await NASADataManager.donki("CME", 30)
	var cross: Dictionary = await ScientificDataManager.get_geomagnetic_crosscheck([])
	if not _alive(token, live):
		return
	wait.queue_free()
	var flares := ScientificDataManager.normalize_donki("FLR", fl_res)
	var cmes := ScientificDataManager.normalize_donki("CME", cme_res)
	if ev.get("is_fallback", true):
		live.add_child(_lbl("Sin datos de DONKI ahora ni copia guardada. El juego usa una alerta de práctica.", 14, Color("ffd9a0"), true, 470))
		_source_line(live, "NASA DONKI", ScientificDataManager.LABEL_SIM, 0.0, "none")
	else:
		var rec: Dictionary = ev["record"]
		live.add_child(_lbl("Lo más fuerte reciente: %s" % NasaBridge_headline(rec), 15, UI.GREEN if ev["classification"] == ScientificDataManager.LABEL_REAL else UI.YELLOW, true, 470))
		var strong := 0
		for f in flares:
			if str(f.get("class_type", "")).begins_with("M") or str(f.get("class_type", "")).begins_with("X"):
				strong += 1
		var fastest := 0.0
		for c in cmes:
			fastest = maxf(fastest, float(c.get("speed", 0.0)))
		live.add_child(_lbl("• Llamaradas en 30 días: %d (clase M o X: %d)" % [flares.size(), strong], 15, C_TEXT, true, 470))
		live.add_child(_lbl("• Nubes de plasma (CME) en 30 días: %d%s" % [cmes.size(), (" · la más rápida ≈ %d km/s" % int(fastest)) if fastest > 0 else ""], 15, C_TEXT, true, 470))
		_source_line(live, "NASA DONKI", ev["classification"], fl_res.get("retrieved_at", 0.0), fl_res.get("origin", "none"))
	if cross.get("ok", false):
		live.add_child(_lbl("• Índice Kp ahora: %.1f (tormenta geomagnética G%s)" % [cross["kp_now"], cross["g_scale"]], 15, C_TEXT, true, 470))
		_source_line(live, "NOAA SWPC", cross["classification"], cross["retrieved_at"], cross["origin"])


## Titulo corto de un registro DONKI normalizado.
func NasaBridge_headline(rec: Dictionary) -> String:
	return "%s (%s)" % [rec.get("title", "evento"), Time.get_date_string_from_unix_time(int(rec.get("event_time", 0)))]


func _topic_radiation(live: Control, token: int) -> void:
	var wait := _wait_label(live)
	var cross: Dictionary = await ScientificDataManager.get_geomagnetic_crosscheck([])
	var sep_res: Dictionary = await NASADataManager.donki("SEP", 30)
	if not _alive(token, live):
		return
	wait.queue_free()
	if not cross.get("ok", false):
		live.add_child(_lbl("Sin datos de NOAA ahora ni copia guardada.", 14, Color("ffd9a0"), true, 470))
		return
	var s_scale := str(cross["s_scale"])
	live.add_child(_lbl("• Tormenta de radiación solar hoy (escala S): S%s" % s_scale, 16, UI.GREEN if s_scale == "0" else UI.RED, true, 470))
	live.add_child(_lbl("   S0 significa «ninguna». S1 (leve) a S5 (extrema).", 12, C_MUTED, true, 470))
	live.add_child(_lbl("• Apagones de radio (R): R%s · Tormentas geomagnéticas (G): G%s" % [cross["r_scale"], cross["g_scale"]], 14, C_TEXT, true, 470))
	var seps := ScientificDataManager.normalize_donki("SEP", sep_res)
	live.add_child(_lbl("• Eventos de partículas solares (SEP) en 30 días: %d" % seps.size(), 14, C_TEXT, true, 470))
	_source_line(live, "NOAA SWPC + NASA DONKI", cross["classification"], cross["retrieved_at"], cross["origin"])
	live.add_child(_lbl("En el juego, la alerta solar del turno 6 sale de DONKI y es un parámetro de simulación, no una dosis real.", 12, C_MUTED, true, 470))


func _topic_data(live: Control) -> void:
	var shown := 0
	for d in DatasetManager.get_all():
		if str(d.get("connection", "none")) in ["none", "ref"]:
			continue
		shown += 1
		var ok := str(d["connection"]) == "online"
		var row := HBoxContainer.new()
		live.add_child(row)
		var n := _lbl("%s %s" % ["●", d["name"]], 13, C_TEXT)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
		row.add_child(_lbl("%s · %s" % [("en línea" if ok else "caché"), DatasetManager.format_time(float(d.get("queried_at", 0.0)))], 12, UI.GREEN if ok else UI.YELLOW))
	if shown == 0:
		live.add_child(_lbl("Aún no se consultó ninguna fuente en esta sesión. Abre el Space Data Center desde el juego o los temas ☀ 🌍 🌙 ☢.", 14, Color("ffd9a0"), true, 470))
	live.add_child(_lbl("Etiquetas: DATO REAL · DATO HISTÓRICO · REFERENCIA NASA · PARÁMETRO DE SIMULACIÓN. El detalle está en el Space Data Center.", 12, C_MUTED, true, 470))


func _topic_ref(live: Control, key: String) -> void:
	var d := DatasetManager.get_dataset("ref_" + key)
	var brow := HBoxContainer.new()
	brow.add_child(UI.badge(ScientificDataManager.LABEL_REF, 12))
	live.add_child(brow)
	live.add_child(_lbl("Es documentación de NASA: no hay una medición en vivo de este tema. " + str(d.get("description", "")), 13, C_MUTED, true, 470))
	var lk := LinkButton.new()
	lk.text = "Leer la fuente original de NASA"
	lk.uri = str(d.get("url_original", ""))
	lk.add_theme_color_override("font_color", Color("6fb4ff"))
	live.add_child(lk)


func _build_achievements() -> void:
	var s := _screen("achievements")
	var v := _center_column(s, 640)
	var h := _lbl("🏆  LOGROS", 30, C_GOLD, false)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	_ach_list = VBoxContainer.new()
	_ach_list.add_theme_constant_override("separation", 8)
	v.add_child(_ach_list)
	v.add_child(_btn("← Volver", Color("1f6fd0"), func() -> void: _show("title")))


func _fill_achievements() -> void:
	for c in _ach_list.get_children():
		c.queue_free()
	MissionManager.reload()
	var st: Dictionary = MissionManager.data["stats"]
	var n_ach := 0
	for a in AchievementManager.DEFS:
		if AchievementManager.is_unlocked(a["id"]):
			n_ach += 1
	_ach_list.add_child(_lbl("Partidas: %d · superadas: %d · logros: %d de %d" % [st["played"], st["won"], n_ach, AchievementManager.DEFS.size()], 15, C_MUTED, false))
	for a in AchievementManager.DEFS:
		var ok := AchievementManager.is_unlocked(a["id"])
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", _box(Color("14301f") if ok else Color("0f1830"), Color("2ecc71") if ok else Color("34456b"), 2, 10))
		var r := VBoxContainer.new()
		p.add_child(r)
		r.add_child(_lbl("%s %s %s" % ["★" if ok else "☆", a["icon"], a["name"]], 18, C_GOLD if ok else C_MUTED, false))
		r.add_child(_lbl(a["desc"], 14, C_TEXT if ok else C_MUTED, true))
		_ach_list.add_child(p)


func _build_config() -> void:
	var s := _screen("config")
	var v := _center_column(s, 720)
	var h := _lbl("CONFIGURACIÓN", 30, C_GOLD, false)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	v.add_child(_lbl("Idioma: Español", 17, C_TEXT, false))
	v.add_child(_lbl("Fuentes de datos (estado de la última consulta; las no consultadas se cargan al abrir el Space Data Center):", 15, C_MUTED, true))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 150)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_cfg_list = VBoxContainer.new()
	_cfg_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cfg_list.add_theme_constant_override("separation", 4)
	sc.add_child(_cfg_list)
	# Interfaz del juego: mostrar u ocultar paneles (mover se hace dentro del juego, con ⚙ Interfaz).
	UILayout.load_layout()
	v.add_child(_lbl("Interfaz del juego: elige qué paneles ver.", 15, C_GOLD, true, 600))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	v.add_child(grid)
	for e in UILayout.ELEMENTS:
		if not e["can_hide"]:
			continue
		var cb := CheckButton.new()
		cb.text = e["name"]
		cb.button_pressed = UILayout.is_shown(e["id"])
		cb.add_theme_font_size_override("font_size", 14)
		cb.toggled.connect(func(on: bool) -> void:
			UILayout.set_shown(e["id"], on)
			UILayout.save())
		_ui_checks[e["id"]] = cb
		grid.add_child(cb)
	var rowb := HBoxContainer.new()
	rowb.add_theme_constant_override("separation", 10)
	v.add_child(rowb)
	var rs := _btn("↺ Restablecer interfaz", Color("a85a24"), func() -> void:
		UILayout.reset()
		for k in _ui_checks:
			(_ui_checks[k] as CheckButton).button_pressed = true, 14, 38)
	rs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rowb.add_child(rs)
	v.add_child(_lbl("Para MOVER los paneles, abre ⚙ Interfaz dentro del juego y activa «Mover paneles».", 12, C_MUTED, true, 600))
	v.add_child(_btn("← Volver", Color("1f6fd0"), func() -> void: _show("title")))


func _fill_config() -> void:
	for c in _cfg_list.get_children():
		c.queue_free()
	var conn_txt := {"online": ["● En línea", Color("2ecc71")], "cache": ["● Caché local", Color("f1b434")], "ref": ["● Documentación", Color("4fc3f7")],
			"rate_limited": ["● Límite de la API", Color("ff9d4d")], "offline": ["● Sin conexión", Color("ff5d5d")]}
	for d in DatasetManager.get_all():
		var c: String = str(d.get("connection", "none"))
		var info: Array = conn_txt.get(c, ["● Sin consultar", Color("7b8798")])
		var row := HBoxContainer.new()
		var n := _lbl(("✔ " if conn_txt.has(c) else "○ ") + d["name"], 14, C_TEXT if conn_txt.has(c) else C_MUTED, false)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
		row.add_child(_lbl(info[0], 13, info[1], false))
		_cfg_list.add_child(row)
	if NASADataManager.using_demo_key:
		_cfg_list.add_child(_lbl("Aviso: usando la clave de demostración de NASA (límite muy bajo). Define NASA_API_KEY.", 13, Color("ff9d4d"), true))


func _build_credits() -> void:
	var s := _screen("credits")
	var v := _center_column(s, 720)
	var h := _lbl("CRÉDITOS", 30, C_GOLD, false)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	v.add_child(_lbl("ZYRANTH · Junior Astronaut: Mission Trainer. Juego educativo desarrollado para NASA Space Apps Challenge 2026.", 16, C_TEXT, true))
	v.add_child(_lbl("Datos y atribuciones:", 16, C_MUTED, false))
	_credits_list = VBoxContainer.new()
	_credits_list.add_theme_constant_override("separation", 3)
	v.add_child(_credits_list)
	var lk := LinkButton.new()
	lk.text = "Aprende más en nasa.gov"
	lk.uri = "https://www.nasa.gov"
	lk.add_theme_color_override("font_color", Color("6fb4ff"))
	v.add_child(lk)
	v.add_child(_lbl("Este proyecto no es un producto oficial de NASA ni está respaldado por NASA.", 12, C_MUTED, true))
	v.add_child(_btn("← Volver", Color("1f6fd0"), func() -> void: _show("title")))


func _fill_credits() -> void:
	for c in _credits_list.get_children():
		c.queue_free()
	var seen := {}
	for d in DatasetManager.get_all():
		var k: String = "%s — %s" % [d["attribution"], d["license"]]
		if not seen.has(k):
			seen[k] = true
			_credits_list.add_child(_lbl("• " + k, 13, C_TEXT, true))


# ------------------------------------------------------------------- UI ----

func _build_background() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_stars_node = Control.new()
	_stars_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stars_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stars_node.draw.connect(func() -> void:
		for st in _stars:
			_stars_node.draw_circle(st[0], st[1], Color(1, 1, 1, st[2])))
	add_child(_stars_node)
	_earth = ColorRect.new()
	_earth.position = Vector2(540, 380)
	_earth.size = Vector2(1100, 1100)
	_earth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/earth_sphere.gdshader")
	_earth.material = mat
	add_child(_earth)


## Astronauta ilustrado (dibujado en codigo, sin logos ni marcas) que flota en el titulo.
func _build_astronaut() -> void:
	_astro = Control.new()
	_astro.position = Vector2(190, 330)
	_astro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_astro.draw.connect(_draw_astronaut)
	add_child(_astro)


func _sb(col: Color, r: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(r)
	return s


func _draw_astronaut() -> void:
	var a := _astro
	var o := Vector2(0, sin(_t * 0.9) * 9.0)
	var rot := sin(_t * 0.6) * 0.06
	a.draw_set_transform(o, rot, Vector2(1.15, 1.15))
	var white := Color("eef2f8")
	var shade := Color("b9c4d8")
	# Brillo de fondo
	for i in 8:
		a.draw_circle(Vector2(0, 30), 190.0 - i * 18.0, Color(0.3, 0.55, 1.0, 0.012))
	# Mochila
	a.draw_style_box(_sb(shade, 18), Rect2(Vector2(-84, -30), Vector2(168, 150)))
	# Piernas
	a.draw_style_box(_sb(white, 20), Rect2(Vector2(-56, 120), Vector2(46, 120)))
	a.draw_style_box(_sb(white, 20), Rect2(Vector2(10, 120), Vector2(46, 120)))
	a.draw_style_box(_sb(Color("2f6fd6"), 12), Rect2(Vector2(-60, 215), Vector2(54, 36)))
	a.draw_style_box(_sb(Color("2f6fd6"), 12), Rect2(Vector2(6, 215), Vector2(54, 36)))
	# Torso
	a.draw_style_box(_sb(white, 30), Rect2(Vector2(-66, 30), Vector2(132, 130)))
	# Panel de control del pecho
	a.draw_style_box(_sb(Color("2a3a5e"), 8), Rect2(Vector2(-34, 62), Vector2(68, 38)))
	a.draw_circle(Vector2(-20, 81), 6.0, Color("ff5d5d"))
	a.draw_circle(Vector2(0, 81), 6.0, Color("ffd24d"))
	a.draw_circle(Vector2(20, 81), 6.0, Color("4dff88"))
	# Brazo izquierdo y derecho (pulgar arriba)
	a.draw_style_box(_sb(white, 22), Rect2(Vector2(-112, 44), Vector2(46, 100)))
	a.draw_style_box(_sb(white, 22), Rect2(Vector2(66, 28), Vector2(46, 92)))
	a.draw_circle(Vector2(-90, 150), 24.0, Color("2f6fd6"))
	a.draw_circle(Vector2(90, 122), 24.0, Color("2f6fd6"))
	a.draw_style_box(_sb(Color("2f6fd6"), 6), Rect2(Vector2(84, 76), Vector2(14, 34)))
	# Casco
	a.draw_circle(Vector2(0, -22), 70.0, white)
	a.draw_arc(Vector2(0, -22), 70.0, 0, TAU, 48, shade, 4.0)
	a.draw_circle(Vector2(0, -20), 50.0, Color("0c1730"))
	a.draw_circle(Vector2(-16, -36), 12.0, Color(0.6, 0.85, 1.0, 0.55))
	a.draw_arc(Vector2(0, -20), 50.0, PI * 1.1, PI * 1.6, 16, Color(0.5, 0.8, 1.0, 0.5), 4.0)
	a.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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


func _screen(name: String) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	_screens[name] = c
	return c


func _center_column(parent: Control, width: int) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(width, 0)
	v.add_theme_constant_override("separation", 10)
	center.add_child(v)
	return v


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _lbl(text: String, size: int, col: Color, wrap: bool = false, min_w: int = 300) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(min_w, 0)
	return l


func _btn(text: String, col: Color, cb: Callable, size := 18, height := 46) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_size_override("font_size", size)
	for st in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(st, _box(col if st == "normal" else col.lightened(0.15), col.lightened(0.4), 2, 10))
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


func _box(bg: Color, border: Color, w: int, r: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(w)
	s.set_corner_radius_all(r)
	s.set_content_margin_all(12)
	return s
