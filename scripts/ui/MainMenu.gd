extends Control
## Menu del juego: titulo, seleccion de modo, aprender sobre la NASA, logros,
## configuracion (estado real de las fuentes de datos) y creditos (atribuciones reales).
## Pruebas:  godot --path <proyecto> -- --screen=title|modes|learn|achievements|config|credits --shot=x.png

const C_BG := Color("070b2a")
const C_PANEL := Color("1b2a72")
const C_BORDER := Color("6db6ff")
const C_TEXT := Color("f6f9ff")
const C_MUTED := Color("c0d0f2")
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
var _cfg_status: Label
var _cfg_busy: bool = false
var _cfg_last_check: int = -100000
var _ui_checks := {}
var _mission_q: Label
var _mission_row: HBoxContainer
var _tier_row: HBoxContainer
var _mission_tier := 1
var _br_box: VBoxContainer
var _deco: Control
var _continue_btn: Button
var _credits_list: VBoxContainer


func _ready() -> void:
	randomize()
	for i in 150:
		_stars.append([Vector2(randf() * 1280.0, randf() * 720.0), randf_range(0.6, 1.8), randf_range(0.35, 1.0)])
	_build_background()
	_build_astronaut()
	_build_deco()
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
		_deco.queue_redraw()


func _load_earth() -> void:
	var r: Dictionary = await EarthImageryManager.get_earth("modis_truecolor")
	if r.get("ok", false):
		_earth.material.set_shader_parameter("earth", r["texture"])
		_earth.material.set_shader_parameter("has_tex", true)


func _show(name: String) -> void:
	for k in _screens:
		(_screens[k] as Control).visible = k == name
	_astro.visible = name == "title" or name == "modes"
	_deco.visible = _astro.visible
	_continue_btn.visible = name != "title" or _has_progress()
	match name:
		"achievements": _fill_achievements()
		"config": _fill_config()
		"credits": _fill_credits()
		"missions":
			_mission_q.text = GameSettings.mode_label()
			_fill_missions()
		"learn": _pick_topic(0)


# ---------------------------------------------------------------- PANTALLAS ----

func _build_title() -> void:
	var s := _screen("title")
	var v := _center_column(s, 460)
	v.add_theme_constant_override("separation", 12)
	# Logo ilustrado: letras doradas gruesas con borde azul y una estrella que brilla
	var logo := Control.new()
	logo.custom_minimum_size = Vector2(0, 118)
	v.add_child(logo)
	var t1 := _lbl("ZYRANTH", 98, Color("ffd24d"), false)
	var bold := FontVariation.new()
	bold.base_font = ThemeDB.fallback_font
	bold.variation_embolden = 0.6
	t1.add_theme_font_override("font", bold)
	t1.add_theme_color_override("font_outline_color", Color("1b3fa8"))
	t1.add_theme_constant_override("outline_size", 14)
	t1.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.4))
	t1.add_theme_constant_override("shadow_offset_y", 6)
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t1.set_anchors_preset(Control.PRESET_FULL_RECT)
	logo.add_child(t1)
	var sub := PanelContainer.new()
	sub.add_theme_stylebox_override("panel", _box(Color("2a45c0"), Color("8ec5ff"), 3, 12))
	sub.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sub.add_child(_lbl("🚀  Junior Astronaut", 22, Color.WHITE, false))
	v.add_child(sub)
	v.add_child(_spacer(10))
	v.add_child(_btn("▶   ¡JUGAR!", Color("ff9f1c"), func() -> void: _show("modes"), 36, 82))
	_continue_btn = _btn("⏩   Continuar", Color("28b36a"), _continue_game, 26, 62)
	v.add_child(_continue_btn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	for it in [["⚙  Ajustes", "config", Color("5a4fd0")], ["🏆  Logros", "achievements", Color("3b6fe0")], ["📖  Aprender", "learn", Color("3b6fe0")]]:
		var b := _btn(str(it[0]), it[2], func() -> void: _show(str(it[1])), 18, 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	var cr := _btn("ℹ", Color("34456b"), func() -> void: _show("credits"), 18, 52)
	cr.tooltip_text = "Créditos"
	cr.custom_minimum_size = Vector2(60, 52)
	row.add_child(cr)


func _build_modes() -> void:
	var s := _screen("modes")
	var v := _center_column(s, 650)
	var h := _lbl("¿Quién va a jugar?", 40, C_GOLD, false)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	v.add_child(row)
	row.add_child(_mode_card("🚀", "Explorador", "7 a 9 años", [["⏱", "+4 h", true], ["🌤️", "Más suave", true]], "principiante", Color("3b8cff")))
	row.add_child(_mode_card("⭐", "Comandante", "10 a 12 años", [["⏱", "Normal", true], ["☀️", "Completo", true]], "intermedio", Color("ffa51f")))
	v.add_child(_btn("← Volver", Color("3b6fe0"), func() -> void: _show("title"), 20, 54))


func _mode_card(icon: String, title: String, age: String, chips: Array, mode: String, col: Color) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 330)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _box(Color("22348a"), col, 5, 16))
	b.add_theme_stylebox_override("hover", _box(Color("2d44a8"), col.lightened(0.25), 5, 16))
	b.add_theme_stylebox_override("pressed", _box(col.darkened(0.5), Color.WHITE, 6, 16))
	UI.bounce(b)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 14)
	b.add_child(m)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 8)
	m.add_child(v)
	var pic := KidKit.disc(icon, col, 120)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pic)
	var t := _lbl(title, 32, Color.WHITE, false)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var a := _lbl(age, 22, col.lightened(0.3), false)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(a)
	var fl := HBoxContainer.new()
	fl.alignment = BoxContainer.ALIGNMENT_CENTER
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fl.add_theme_constant_override("separation", 8)
	v.add_child(fl)
	for c in chips:
		var ch := KidKit.chip(str(c[0]), str(c[1]), bool(c[2]), 17)
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fl.add_child(ch)
	b.pressed.connect(func() -> void:
		GameSettings.mode = mode
		_show("missions"))
	return b


func _build_missions() -> void:
	var s := _screen("missions")
	var v := _center_column(s, 1080)
	var h := _lbl("🚀 Elige tu misión", 40, C_GOLD, false)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	var q := _lbl("", 18, C_MUTED, false)
	_mission_q = q
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(q)
	_tier_row = HBoxContainer.new()
	_tier_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_tier_row.add_theme_constant_override("separation", 10)
	v.add_child(_tier_row)
	_mission_row = HBoxContainer.new()
	_mission_row.add_theme_constant_override("separation", 14)
	v.add_child(_mission_row)
	var hint := _lbl("🔓 Supera una misión para abrir la siguiente", 16, C_MUTED, false)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	v.add_child(_btn("← Volver", Color("3b6fe0"), func() -> void: _show("modes"), 20, 54))


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
		var col: Color = MissionDef.TIER_COLORS[t]
		var label := "%s%s" % [MissionDef.TIER_NAMES[t], ("  %d/%d ⭐" % [done, playable]) if playable > 0 else "  🔒"]
		var b := _btn(label, col.darkened(0.15) if t == _mission_tier else Color("34456b"), func() -> void:
			_mission_tier = t
			_fill_missions(), 19, 52)
		b.custom_minimum_size = Vector2(210, 52)
		if t == _mission_tier:
			for st in ["normal", "hover", "pressed"]:
				b.add_theme_stylebox_override(st, UI.press_box(col.darkened(0.1), st == "pressed"))
			b.add_theme_color_override("font_outline_color", col.darkened(0.6))
		_tier_row.add_child(b)


func _fill_missions() -> void:
	_fill_tabs()
	for c in _mission_row.get_children():
		c.queue_free()
	for m in MissionManager.of_tier(_mission_tier):
		var unlocked := MissionManager.is_unlocked(m.id)
		var done := MissionManager.is_completed(m.id)
		var col := (Color("3ddc84") if done else Color("4f8dff")) if unlocked else Color("6b7596")
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.tooltip_text = m.summary if unlocked else MissionManager.lock_reason(m.id)
		card.add_theme_stylebox_override("panel", _box(Color("22348a") if unlocked else Color("232a4a"), col, 5, 16))
		_mission_row.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 6)
		card.add_child(cv)
		var pic := KidKit.disc(m.icon if unlocked else "🔒", col, 96)
		pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cv.add_child(pic)
		var title := _lbl(m.title, 21, C_GOLD if unlocked else C_MUTED, true, 230)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(title)
		var stars := _lbl("%s  %s" % [m.stars(), m.difficulty_label()], 18, m.difficulty_color() if unlocked else C_MUTED, false)
		stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(stars)
		var tag := _lbl(str(KidText.MISSION_TAG.get(m.id, "")), 17, C_TEXT if unlocked else C_MUTED, true, 230)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(tag)
		var status := "⭐ ¡Superada!" if done else ("" if unlocked else ("🔒 Supera la anterior" if m.ready else "🚧 Muy pronto"))
		var st := _lbl(status if status != "" else " ", 17, Color("7be88a") if done else Color("ffb07a"), false)
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(st)
		var btn := _btn("¡Jugar! ▶" if unlocked else "Bloqueada", Color("28b36a") if unlocked else Color("3a4468"), Callable(), 22, 56)
		btn.disabled = not unlocked
		if unlocked:
			btn.pressed.connect(_open_briefing.bind(m.id))
		cv.add_child(btn)


func _build_briefing() -> void:
	var s := _screen("briefing")
	var v := _center_column(s, 880)
	_br_box = VBoxContainer.new()
	_br_box.add_theme_constant_override("separation", 12)
	v.add_child(_br_box)
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", 12)
	v.add_child(b)
	var start := _btn("🚀 ¡Empezar misión!", Color("28b36a"), func() -> void:
		get_tree().change_scene_to_file(MissionManager.current.scene), 26, 64)
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_child(start)
	var back := _btn("← Volver", Color("3b6fe0"), func() -> void: _show("missions"), 20, 64)
	back.custom_minimum_size = Vector2(170, 64)
	b.add_child(back)


func _open_briefing(id: String) -> void:
	if not MissionManager.select(id):
		return
	var m := MissionManager.current
	for c in _br_box.get_children():
		c.queue_free()
	# Titulo con ilustracion y dificultad
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 14)
	_br_box.add_child(head)
	head.add_child(KidKit.disc(m.icon, m.tier_color(), 84))
	var hv := VBoxContainer.new()
	hv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hv)
	hv.add_child(_lbl(m.title, 34, C_GOLD, false))
	hv.add_child(_lbl("%s  %s" % [m.stars(), m.difficulty_label()], 20, m.difficulty_color(), false))
	# Escena: la Luna, la base y los astronautas
	var scene_row := HBoxContainer.new()
	scene_row.alignment = BoxContainer.ALIGNMENT_CENTER
	scene_row.add_theme_constant_override("separation", 14)
	_br_box.add_child(scene_row)
	for pair in [["🌙", Color("8d93ad")], ["🛰️", Color("4f8dff")], ["🧑‍🚀", Color("f1b434")], ["🤖", Color("5a7bd0")]]:
		scene_row.add_child(KidKit.disc(str(pair[0]), pair[1], 72))
	var goal := _lbl("¡Mantén a tu equipo seguro durante 3 días junto a la Luna!", 26, C_TEXT, true, 820)
	goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_br_box.add_child(goal)
	# El dilema en una linea + que proteges y que sacrificas en iconos
	var dil := PanelContainer.new()
	dil.add_theme_stylebox_override("panel", _box(Color("3a2a7a"), Color("c39bff"), 3, 12))
	dil.tooltip_text = m.dilemma_text
	dil.add_child(_lbl("⚖️ El dilema: " + m.dilemma_title, 21, C_GOLD, true, 800))
	_br_box.add_child(dil)
	_br_box.add_child(KidKit.protect_sacrifice(m.protect, m.sacrifice))
	_br_box.add_child(KidKit.how_to_play())
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


func _alive(token: int, live: Variant) -> bool:
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
	v.add_child(_lbl("Fuentes de datos. «Copia vigente» = descargada hace poco, no hace falta pedirla otra vez. Pulsa el botón para consultar la red ahora:", 15, C_MUTED, true))
	_cfg_status = _lbl("", 13, C_MUTED, true)
	v.add_child(_btn("↻ Consultar la red ahora", Color("1f6fd0"), _check_connections, 14, 34))
	v.add_child(_cfg_status)
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
	var tut := _btn("🔁 Repetir el tutorial", Color("6a4fd0"), func() -> void:
		TutorialGuide.reset_saved()
		_cfg_status.text = "¡Listo! El robot volverá a explicarte todo en la próxima misión.", 14, 38)
	tut.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rowb.add_child(tut)
	v.add_child(_lbl("Para MOVER los paneles, abre ⚙ Interfaz dentro del juego y activa «Mover paneles».", 12, C_MUTED, true, 600))
	v.add_child(_btn("← Volver", Color("1f6fd0"), func() -> void: _show("title")))


## Ignora las copias vigentes y consulta la red de cada fuente (una vez cada 30 s como maximo).
func _check_connections() -> void:
	var now := Time.get_ticks_msec()
	if _cfg_busy or now - _cfg_last_check < 30000:
		return
	_cfg_busy = true
	_cfg_last_check = now
	_cfg_status.text = "Consultando NASA y NOAA..."
	NASADataManager.force_stale = true
	var ev: Dictionary = await ScientificDataManager.build_solar_event()
	await ScientificDataManager.refresh_donki_extras()
	await ScientificDataManager.get_station_context()
	var gst := ScientificDataManager.normalize_donki("GST", await NASADataManager.donki("GST", 30))
	await ScientificDataManager.get_geomagnetic_crosscheck(gst)
	for key in ["modis_truecolor", "viirs_truecolor", "blackmarble", "lro_wac"]:
		await EarthImageryManager.get_earth(key)
	NASADataManager.force_stale = false
	_cfg_busy = false
	if not is_instance_valid(_cfg_list):
		return
	_cfg_status.text = "Revisado %s UTC (DONKI: %s)" % [Time.get_time_string_from_system(true), str(ev.get("connection", "?"))]
	_fill_config()


func _fill_config() -> void:
	for c in _cfg_list.get_children():
		c.queue_free()
	var conn_txt := {"online": ["● En línea", Color("2ecc71")], "cache": ["● Caché local", Color("f1b434")], "ref": ["● Documentación", Color("4fc3f7")],
			"rate_limited": ["● Límite de la API", Color("ff9d4d")], "offline": ["● Sin conexión", Color("ff5d5d")]}
	for d in DatasetManager.get_all():
		var c: String = str(d.get("connection", "none"))
		var info: Array = conn_txt.get(c, ["● Sin consultar", Color("7b8798")])
		if c == "cache":
			# «Cache vigente» = la copia es reciente y no hacia falta pedirla de nuevo;
			# cualquier otra nota = la red fallo y se uso la copia guardada.
			if str(d.get("note", "")).begins_with("Cache vigente"):
				info = ["● Copia vigente", Color("7fd1a8")]
			else:
				info = ["● Copia guardada (la red falló)", Color("f1b434")]
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
	v.add_child(_lbl("Letra: Fredoka (SIL OFL 1.1) · Iconos: Twemoji (Twitter/Mozilla COLR, CC-BY 4.0) · Símbolos: DejaVu Sans (licencia libre Bitstream Vera).", 13, C_MUTED, true))
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
	return UI.lbl(text, size, col, wrap, min_w)


func _btn(text: String, col: Color, cb: Callable, size := 18, height := 46) -> Button:
	return UI.btn(text, col, cb, size, height)


func _box(bg: Color, border: Color, w: int, r: int) -> StyleBoxFlat:
	return UI.box(bg, border, w, r, 12)



## Escena ilustrada del titulo: suelo lunar, base con domos y paneles, rover y el robot compañero.
func _build_deco() -> void:
	_deco = Control.new()
	_deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	_deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deco.draw.connect(_draw_deco)
	add_child(_deco)


func _draw_deco() -> void:
	var d := _deco
	# Suelo lunar con borde iluminado y crateres
	var ground := PackedVector2Array([Vector2(0, 720)])
	var rim := PackedVector2Array()
	for i in 33:
		var p := Vector2(i * 40.0, 636.0 + 12.0 * sin(i * 0.5 + 0.8))
		ground.append(p)
		rim.append(p)
	ground.append(Vector2(1280, 720))
	d.draw_colored_polygon(ground, Color("a3a9c2"))
	d.draw_polyline(rim, Color("e3e8f8"), 5.0)
	for c in [[150, 690, 70], [540, 682, 44], [1000, 700, 80], [1210, 670, 34]]:
		var pts := PackedVector2Array()
		for k in 24:
			var a := TAU * k / 24.0
			pts.append(Vector2(float(c[0]) + cos(a) * float(c[2]), float(c[1]) + sin(a) * float(c[2]) * 0.26))
		d.draw_colored_polygon(pts, Color("8a90ab"))
	# Base: paneles solares, dos domos, tubo y torre con antena
	var bx := 930.0
	var by := 640.0
	for px in [-210.0, -135.0]:
		d.draw_line(Vector2(bx + px + 32, by), Vector2(bx + px + 32, by - 26), Color("5d6578"), 5.0)
		var pr := Rect2(bx + px, by - 74, 64, 44)
		d.draw_rect(pr, Color("2f6bff"))
		d.draw_rect(pr, Color("9ec4ff"), false, 3.0)
		d.draw_line(Vector2(pr.position.x + 32, pr.position.y), Vector2(pr.position.x + 32, pr.end.y), Color("9ec4ff", 0.7), 2.0)
		d.draw_line(Vector2(pr.position.x, pr.position.y + 22), Vector2(pr.end.x, pr.position.y + 22), Color("9ec4ff", 0.7), 2.0)
	d.draw_rect(Rect2(bx + 40, by - 24, 70, 16), Color("c7cfe3"))
	_dome(d, Vector2(bx, by), 76.0, Color("f1f5ff"))
	_dome(d, Vector2(bx + 140, by), 46.0, Color("dfe9ff"))
	d.draw_rect(Rect2(bx + 214, by - 120, 12, 120), Color("c7cfe3"))
	d.draw_circle(Vector2(bx + 220, by - 124), 8.0, Color("ff5d5d") if fmod(_t, 1.2) < 0.6 else Color("ff9d9d"))
	d.draw_arc(Vector2(bx + 220, by - 124), 18.0, -PI * 0.9, -PI * 0.1, 10, Color("aab2c4"), 3.0)
	# Rover que va y viene por el suelo
	var f := fmod(_t * 0.07, 1.0)
	var rx := 330.0 + (1.0 - absf(f * 2.0 - 1.0)) * 360.0
	var ry := 668.0
	d.draw_style_box(_sb(Color("ffc83d"), 8), Rect2(rx - 24, ry - 20, 48, 20))
	d.draw_style_box(_sb(Color("c7cfe3"), 6), Rect2(rx - 8, ry - 34, 24, 15))
	d.draw_circle(Vector2(rx - 15, ry + 1), 8.0, Color("2a2f45"))
	d.draw_circle(Vector2(rx + 15, ry + 1), 8.0, Color("2a2f45"))
	# Robot companero con globo de dialogo
	var rp := Vector2(1110, 250 + sin(_t * 1.6) * 8.0)
	KidKit.draw_robot(d, rp, _t, 0.0, 1, 1.9)
	var bub := Rect2(rp.x - 140, rp.y - 78, 200, 52)
	d.draw_style_box(UI.box(Color("eaf3ff"), Color("8ec5ff"), 3, 12, 0), bub)
	d.draw_colored_polygon(PackedVector2Array([Vector2(bub.end.x - 36, bub.end.y - 2), Vector2(bub.end.x - 8, bub.end.y - 2), Vector2(bub.end.x - 20, bub.end.y + 18)]), Color("eaf3ff"))
	d.draw_string(ThemeDB.fallback_font, Vector2(bub.position.x + 14, bub.position.y + 34), "¡Hola, comandante!", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("15306b"))


func _dome(d: Control, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 25:
		var a := PI * k / 24.0
		pts.append(Vector2(c.x - cos(a) * r, c.y - sin(a) * r))
	d.draw_colored_polygon(pts, col)
	d.draw_polyline(pts, Color("9db4d8"), 4.0)
	d.draw_rect(Rect2(c.x - r, c.y - 10, r * 2.0, 10), Color("b7c3dd"))
	for k in 3:   # ventanas con luz
		d.draw_circle(Vector2(c.x - r * 0.45 + k * r * 0.45, c.y - r * 0.38), r * 0.1, Color("ffe08a"))


## ¿Hay progreso guardado? (alguna mision superada o jugada)
func _has_progress() -> bool:
	for m in MissionManager.all():
		if MissionManager.is_completed(m.id) or MissionManager.attempts(m.id) > 0:
			return true
	return false


## «Continuar»: va a la seleccion de misiones, en el nivel de la primera mision desbloqueada sin superar.
func _continue_game() -> void:
	if GameSettings.mode == "":
		GameSettings.mode = "intermedio"
	for t in [1, 2, 3]:
		for m in MissionManager.of_tier(t):
			if m.ready and MissionManager.is_unlocked(m.id) and not MissionManager.is_completed(m.id):
				_mission_tier = t
				_show("missions")
				return
	_show("missions")
