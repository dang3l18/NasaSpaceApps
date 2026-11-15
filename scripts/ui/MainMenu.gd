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

const LEARN := [
	["La Luna", "La nave LRO de NASA cartografió la superficie lunar y midió su temperatura, composición y entorno de radiación. La imagen de la Luna del juego viene de su cámara (NASA Moon Trek)."],
	["El Sol", "El Sol lanza llamaradas y nubes de plasma llamadas CME. NASA DONKI las registra. Una tormenta fuerte puede afectar satélites, comunicaciones y astronautas."],
	["Radiación", "En la Luna no hay atmósfera que nos proteja. NASA investiga materiales de protección, incluso con regolito lunar (el polvo y las piedras de la Luna). En el juego usas regolito para reforzar el blindaje."],
	["Soporte vital", "NASA divide el soporte vital en tres partes: recuperar agua, limpiar el aire y producir oxígeno. En el juego, ese sistema gasta energía y necesita mantenimiento."],
	["Plantas", "NASA cultiva lechugas en el espacio con luces LED como comida fresca extra para la tripulación. Las plantas ayudan, pero no reemplazan a los sistemas de la base."],
	["Datos de NASA", "En el Space Data Center ves de dónde viene cada dato, su fecha y si es REAL, HISTÓRICO, REFERENCIA o un PARÁMETRO DE SIMULACIÓN del juego."],
]

var _earth: ColorRect
var _astro: Control
var _screens: Dictionary = {}
var _t := 0.0
var _stars: Array = []
var _stars_node: Control
var _learn_text: Label
var _learn_buttons: Array = []
var _ach_list: VBoxContainer
var _cfg_list: VBoxContainer
var _credits_list: VBoxContainer


func _ready() -> void:
	randomize()
	for i in 150:
		_stars.append([Vector2(randf() * 1280.0, randf() * 720.0), randf_range(0.6, 1.8), randf_range(0.35, 1.0)])
	_build_background()
	_build_astronaut()
	_build_title()
	_build_modes()
	_build_learn()
	_build_achievements()
	_build_config()
	_build_credits()
	var first := "title"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screen="):
			first = a.substr(9)
	_show(first)
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
		"learn": _pick_topic(0)


# ---------------------------------------------------------------- PANTALLAS ----

func _build_title() -> void:
	var s := _screen("title")
	var v := _center_column(s, 420)
	var t1 := _lbl("JUNIOR", 54, Color("ffffff"), false)
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t1)
	var t2 := _lbl("ASTRONAUT", 54, Color("ffffff"), false)
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t2)
	var t3 := _lbl("MISSION TRAINER", 28, C_GOLD, false)
	t3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t3)
	var sub := _lbl("Operación: Refugio Lunar\nAprende · Decide · Sobrevive", 16, C_MUTED, false)
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
	var q := _lbl("Elige tu modo de misión", 16, C_MUTED, false)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(q)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	row.add_child(_mode_card("🚀  MODO PRINCIPIANTE", "7–9 años", "+4 horas de trabajo por turno\nAlertas solares más suaves", "principiante", Color("2f7de0")))
	row.add_child(_mode_card("⭐  MODO INTERMEDIO", "10–12 años", "Horas de trabajo normales\nAlertas solares completas", "intermedio", Color("e0a02f")))
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
		get_tree().change_scene_to_file("res://scenes/LunarBase.tscn"))
	return b


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
	_learn_text = _lbl("", 17, C_TEXT, true)
	_learn_text.custom_minimum_size = Vector2(500, 200)
	panel.add_child(_learn_text)
	var cap := _lbl("Texto educativo del juego. Los datos con fecha y fuente están en el Space Data Center.", 12, C_MUTED, true)
	v.add_child(cap)
	v.add_child(_btn("← Volver", Color("1f6fd0"), func() -> void: _show("title")))


func _pick_topic(i: int) -> void:
	_learn_text.text = "%s\n\n%s" % [LEARN[i][0], LEARN[i][1]]
	for j in _learn_buttons.size():
		var col := Color("1f9f55") if j == i else Color("245aa8")
		for st in ["normal", "hover", "pressed"]:
			(_learn_buttons[j] as Button).add_theme_stylebox_override(st, _box(col, col.lightened(0.4), 2, 8))


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
	var st := Progress.stats()
	_ach_list.add_child(_lbl("Misiones jugadas: %d · superadas: %d" % [st["played"], st["won"]], 15, C_MUTED, false))
	for a in Progress.ACHIEVEMENTS:
		var ok := Progress.is_unlocked(a["id"])
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", _box(Color("14301f") if ok else Color("0f1830"), Color("2ecc71") if ok else Color("34456b"), 2, 10))
		var r := VBoxContainer.new()
		p.add_child(r)
		r.add_child(_lbl(("★ " if ok else "☆ ") + a["name"], 18, C_GOLD if ok else C_MUTED, false))
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
	_cfg_list = VBoxContainer.new()
	_cfg_list.add_theme_constant_override("separation", 4)
	v.add_child(_cfg_list)
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
	v.add_child(_lbl("Juego educativo desarrollado para NASA Space Apps Challenge 2026.", 16, C_TEXT, true))
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


func _lbl(text: String, size: int, col: Color, wrap: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(300, 0)
	return l


func _btn(text: String, col: Color, cb: Callable, size := 18, height := 46) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_size_override("font_size", size)
	for st in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(st, _box(col if st == "normal" else col.lightened(0.15), col.lightened(0.4), 2, 10))
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
