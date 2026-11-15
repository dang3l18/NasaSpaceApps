extends Control
## Pantalla SPACE DATA CENTER: muestra, para cada fuente, nombre, descripcion, fechas,
## enlace original, tipo, estado de conexion y la etiqueta DATO REAL / HISTORICO / SIMULACION.
## Todo viene de DatasetManager (estado real de las consultas). Nunca bloquea la mision.
##
## Captura para pruebas:  godot --path <proyecto> -- --shot=C:/ruta/captura.png

signal back_requested

const C_BG := Color("070d22")
const C_PANEL := Color("0c1a3d")
const C_BORDER := Color("2f6fd6")
const C_TEXT := Color("e8f1ff")
const C_MUTED := Color("8fa8d0")
const C_REAL := Color("2ecc71")
const C_HIST := Color("f1b434")
const C_SIM := Color("b07cff")
const C_NONE := Color("7b8798")
const C_BAD := Color("ff5d5d")

var _busy := false
var _selected := ""
var _buttons: Dictionary = {}
var _list: VBoxContainer
var _status: Label
var _earth_rect: TextureRect
var _earth_caption: Label
var _badge: Label
var _title: Label
var _vals: Dictionary = {}
var _link: LinkButton
var _event_title: Label
var _event_badge: Label
var _event_text: Label
var _event_cross: Label


func _ready() -> void:
	_build_ui()
	_populate_list()
	DatasetManager.dataset_updated.connect(_on_dataset_updated)
	_select(DatasetManager.get_all()[0].id)
	await refresh_all()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			await get_tree().create_timer(0.5).timeout
			get_viewport().get_texture().get_image().save_png(a.substr(7))
			get_tree().quit()


# ---------------------------------------------------------------- DATOS ----

func refresh_all() -> void:
	if _busy:
		return
	_busy = true
	_status.text = "Consultando fuentes..."
	var earth: Dictionary = await EarthImageryManager.get_earth("modis_truecolor")
	_show_earth(earth)
	var progress := func(done: int, total: int) -> void:
		_status.text = "Cargando archivo DONKI 2025–2026: %d%%" % int(100.0 * done / total)
	ScientificDataManager.history_progress.connect(progress)
	await ScientificDataManager.ensure_history()
	ScientificDataManager.history_progress.disconnect(progress)
	var ev: Dictionary = await ScientificDataManager.build_solar_event()
	_show_event(ev)
	var hs := ScientificDataManager.history_summary()
	if hs != "":
		_event_cross.text = hs
	await ScientificDataManager.refresh_donki_extras()
	await ScientificDataManager.get_station_context()
	var gst := ScientificDataManager.normalize_donki("GST", await NASADataManager.donki("GST", 30))
	var cross: Dictionary = await ScientificDataManager.get_geomagnetic_crosscheck(gst)
	_event_cross.text = cross["comparison"] + "  [NOAA SWPC · %s]" % cross["classification"] if cross.get("ok", false) else "NOAA SWPC: sin datos disponibles."
	await EarthImageryManager.get_earth("lro_wac")
	await EarthImageryManager.get_earth("blackmarble")
	await EarthImageryManager.get_earth("viirs_truecolor")
	_status.text = "Actualizado %s" % Time.get_time_string_from_system(true) + " UTC"
	_busy = false


func _show_earth(r: Dictionary) -> void:
	if r.get("ok", false):
		_earth_rect.texture = r["texture"]
		var how := "caché local" if r["from_cache"] else "descarga NASA GIBS"
		_earth_caption.text = "Tierra · MODIS Terra · imagen del %s · %s · %s" % [r["image_date"], how, r["classification"]]
		_earth_caption.add_theme_color_override("font_color", _label_color(r["classification"]))
	else:
		_earth_rect.texture = null
		_earth_caption.text = "Imagen de la Tierra no disponible (%s)" % r.get("error", "sin conexión")
		_earth_caption.add_theme_color_override("font_color", C_BAD)


func _show_event(ev: Dictionary) -> void:
	_event_badge.text = ev["classification"]
	_event_badge.add_theme_color_override("font_color", _label_color(ev["classification"]))
	_event_text.text = ev["explanation"]
	_event_title.text = "EVENTO DE LA MISIÓN · ACTIVIDAD SOLAR" + ("  (escenario de práctica)" if ev["is_fallback"] else "")


# ------------------------------------------------------------------ LISTA ----

func _populate_list() -> void:
	for d in DatasetManager.get_all():
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 54)
		b.clip_text = true
		b.pressed.connect(_select.bind(d["id"]))
		_list.add_child(b)
		_buttons[d["id"]] = b
		_style_button(d["id"])


func _style_button(id: String) -> void:
	var d := DatasetManager.get_dataset(id)
	var b: Button = _buttons[id]
	var label := _label_of(d)
	b.text = "● %s\n   %s · %s" % [d["name"], d["source"].split(" (")[0], label]
	var col := _label_color(label)
	b.add_theme_color_override("font_color", C_TEXT)
	b.add_theme_stylebox_override("normal", _box(Color("0f2150") if id != _selected else Color("1a3a80"), col if id == _selected else C_BORDER.darkened(0.3), 1, 6))
	b.add_theme_stylebox_override("hover", _box(Color("17327a"), col, 2, 6))
	b.add_theme_stylebox_override("pressed", _box(Color("1a3a80"), col, 2, 6))


func _on_dataset_updated(id: String) -> void:
	if _buttons.has(id):
		_style_button(id)
	if id == _selected:
		_fill_detail(id)


func _select(id: String) -> void:
	var prev := _selected
	_selected = id
	if prev != "" and _buttons.has(prev):
		_style_button(prev)
	_style_button(id)
	_fill_detail(id)


# ---------------------------------------------------------------- DETALLE ----

func _fill_detail(id: String) -> void:
	var d := DatasetManager.get_dataset(id)
	var label := _label_of(d)
	_title.text = d["name"]
	_badge.text = " %s " % label
	_badge.add_theme_stylebox_override("normal", _box(_label_color(label).darkened(0.55), _label_color(label), 2, 14))
	_badge.add_theme_color_override("font_color", _label_color(label))
	_vals["Fuente"].text = d["source"]
	_vals["Descripción"].text = d["description"]
	_vals["Fecha del dato"].text = str(d.get("data_date", "sin consulta"))
	_vals["Fecha de consulta"].text = "No aplica (documentación)" if str(d.get("connection", "")) == "ref" else DatasetManager.format_time(float(d.get("queried_at", 0.0)))
	_vals["Tipo de información"].text = d["info_type"]
	_vals["Formato"].text = d["format"]
	_vals["Licencia"].text = d["license"]
	_vals["Atribución"].text = d["attribution"]
	var conn := str(d.get("connection", "none"))
	var conn_info := _conn_text(conn)
	_vals["Estado de conexión"].text = conn_info[0] + ("  ·  " + str(d["note"]) if str(d.get("note", "")) != "" and conn != "online" else "")
	_vals["Estado de conexión"].add_theme_color_override("font_color", conn_info[1])
	_link.text = d["url_original"]
	_link.uri = d["url_original"]


func _label_of(d: Dictionary) -> String:
	if not d.has("classification"):
		return "SIN CONSULTA"
	return str(d["classification"])


func _label_color(label: String) -> Color:
	match label:
		ScientificDataManager.LABEL_REAL: return C_REAL
		ScientificDataManager.LABEL_HISTORIC: return C_HIST
		ScientificDataManager.LABEL_SIM: return C_SIM
		ScientificDataManager.LABEL_REF: return Color("4fc3f7")
		ScientificDataManager.LABEL_PARAM: return C_SIM
	return C_NONE


func _conn_text(conn: String) -> Array:
	match conn:
		"online": return ["● EN LÍNEA", C_REAL]
		"cache": return ["● CACHÉ LOCAL (sin conexión nueva)", C_HIST]
		"rate_limited": return ["● LÍMITE DE LA API", Color("ff9d4d")]
		"offline": return ["● SIN CONEXIÓN", C_BAD]
		"ref": return ["● DOCUMENTACIÓN (no es un dato en vivo)", Color("4fc3f7")]
	return ["● SIN CONSULTAR", C_NONE]


# ------------------------------------------------------------------- UI ----

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 16)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	# Cabecera
	var head := HBoxContainer.new()
	root.add_child(head)
	var t := Label.new()
	t.text = "SPACE DATA CENTER"
	t.add_theme_font_size_override("font_size", 26)
	t.add_theme_color_override("font_color", Color("ffd24d"))
	head.add_child(t)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_status = Label.new()
	_status.add_theme_color_override("font_color", C_MUTED)
	head.add_child(_status)
	head.add_child(_btn("Actualizar", Color("1f8f4e"), refresh_all))
	head.add_child(_btn("Volver", Color("1f6fd0"), func(): back_requested.emit()))

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)

	# Columna izquierda: Tierra + lista
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(380, 0)
	left.add_theme_stylebox_override("panel", _box(C_PANEL, C_BORDER, 2, 10))
	body.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	left.add_child(lv)
	_earth_rect = TextureRect.new()
	_earth_rect.custom_minimum_size = Vector2(0, 170)
	_earth_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_earth_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	lv.add_child(_earth_rect)
	_earth_caption = Label.new()
	_earth_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_earth_caption.text = "Cargando imagen de la Tierra..."
	_earth_caption.add_theme_font_size_override("font_size", 12)
	_earth_caption.add_theme_color_override("font_color", C_MUTED)
	lv.add_child(_earth_caption)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 5)
	scroll.add_child(_list)

	# Columna derecha: detalle + evento
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	body.add_child(right)

	var detail := PanelContainer.new()
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_theme_stylebox_override("panel", _box(C_PANEL, C_BORDER, 2, 10))
	right.add_child(detail)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 8)
	detail.add_child(dv)
	var top := HBoxContainer.new()
	dv.add_child(top)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", C_TEXT)
	top.add_child(_title)
	_badge = Label.new()
	_badge.add_theme_font_size_override("font_size", 14)
	top.add_child(_badge)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	dv.add_child(grid)
	for k in ["Fuente", "Descripción", "Fecha del dato", "Fecha de consulta", "Tipo de información",
			"Estado de conexión", "Formato", "Licencia", "Atribución"]:
		var kl := Label.new()
		kl.text = k
		kl.custom_minimum_size = Vector2(150, 0)
		kl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		kl.add_theme_color_override("font_color", C_MUTED)
		grid.add_child(kl)
		var vl := Label.new()
		vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vl.add_theme_color_override("font_color", C_TEXT)
		grid.add_child(vl)
		_vals[k] = vl
	var lk := Label.new()
	lk.text = "Enlace original"
	lk.add_theme_color_override("font_color", C_MUTED)
	grid.add_child(lk)
	_link = LinkButton.new()
	_link.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_link.add_theme_color_override("font_color", Color("6fb4ff"))
	grid.add_child(_link)

	var ev := PanelContainer.new()
	ev.add_theme_stylebox_override("panel", _box(Color("1a1330"), C_SIM, 2, 10))
	right.add_child(ev)
	var evv := VBoxContainer.new()
	evv.add_theme_constant_override("separation", 4)
	ev.add_child(evv)
	var evh := HBoxContainer.new()
	evv.add_child(evh)
	_event_title = Label.new()
	_event_title.text = "EVENTO DE LA MISIÓN · ACTIVIDAD SOLAR"
	_event_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_event_title.add_theme_color_override("font_color", Color("ffd24d"))
	evh.add_child(_event_title)
	_event_badge = Label.new()
	evh.add_child(_event_badge)
	_event_text = Label.new()
	_event_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_event_text.text = "Consultando NASA DONKI..."
	_event_text.add_theme_color_override("font_color", C_TEXT)
	evv.add_child(_event_text)
	_event_cross = Label.new()
	_event_cross.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_event_cross.add_theme_font_size_override("font_size", 13)
	_event_cross.add_theme_color_override("font_color", C_MUTED)
	evv.add_child(_event_cross)


func _btn(text: String, col: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(110, 36)
	for st in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(st, _box(col if st == "normal" else col.lightened(0.15), col.lightened(0.4), 2, 8))
	b.pressed.connect(cb)
	return b


func _box(bg: Color, border: Color, w: int, r: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(w)
	s.set_corner_radius_all(r)
	s.set_content_margin_all(10)
	return s
