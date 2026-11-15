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
var _prev_tex: TextureRect
var _prev_chart: Control
var _prev_info: Label
var _prev_caption: Label
var _chart_fn := Callable()
var _imgs: Dictionary = {}
var _preview_for := ""

const LAYER_OF := {"gibs_modis_truecolor": "modis_truecolor", "gibs_viirs_truecolor": "viirs_truecolor",
		"gibs_blackmarble": "blackmarble", "lro_wac_moontrek": "lro_wac"}
const KIND_OF := {"donki_flr": "FLR", "donki_cme": "CME", "donki_gst": "GST", "donki_sep": "SEP"}
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
	var first: String = DatasetManager.get_all()[0].id
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--select="):
			first = a.substr(9)
	_select(first)
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
	_imgs["modis_truecolor"] = await EarthImageryManager.get_earth("modis_truecolor")
	_show_preview(_selected)
	var progress := func(done: int, total: int) -> void:
		_status.text = "Cargando archivo DONKI 2025–2026: %d%%" % int(100.0 * done / total)
	ScientificDataManager.history_progress.connect(progress)
	await ScientificDataManager.ensure_history()
	ScientificDataManager.history_progress.disconnect(progress)
	_status.text = "Consultando fuentes..."
	_show_preview(_selected)
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
	for key in ["lro_wac", "blackmarble", "viirs_truecolor"]:
		_imgs[key] = await EarthImageryManager.get_earth(key)
	_status.text = "Actualizado %s" % Time.get_time_string_from_system(true) + " UTC"
	_busy = false
	_show_preview(_selected)


# ---------------------------------------------------- VISTA PREVIA POR DATO ----
## El recuadro de la izquierda cambia con el dato elegido: imagen real (GIBS, LRO), grafico
## hecho con los datos reales (DONKI, NOAA, CMR) o una tarjeta para documentacion y parametros.

func _prev_mode(mode: String) -> void:
	_prev_tex.visible = mode == "image"
	_prev_chart.visible = mode == "chart"
	_prev_info.visible = mode == "info"


func _caption(text: String, label: String = "") -> void:
	_prev_caption.text = text
	_prev_caption.add_theme_color_override("font_color", _label_color(label) if label != "" else C_MUTED)


func _show_preview(id: String) -> void:
	_preview_for = id
	var d := DatasetManager.get_dataset(id)
	var label := _label_of(d)
	if LAYER_OF.has(id):
		var key: String = LAYER_OF[id]
		if not _imgs.has(key):
			_prev_mode("info")
			_prev_info.text = "Cargando imagen…"
			_imgs[key] = await EarthImageryManager.get_earth(key)
			if _preview_for != id:
				return
		var r: Dictionary = _imgs[key]
		if r.get("ok", false):
			_prev_mode("image")
			_prev_tex.texture = r["texture"]
			var when: String = r["image_date"] if r["image_date"] != "" else "mosaico / capa por defecto"
			var how := "caché local" if r["from_cache"] else "descargada ahora"
			_caption("%s · %s · %s · %s" % [d["name"], when, how, r["classification"]], r["classification"])
		else:
			_prev_mode("info")
			_prev_info.text = "🖼 Imagen no disponible\n(%s)" % r.get("error", "sin conexión")
			_caption("Sin conexión y sin copia guardada. El juego sigue funcionando.", "")
	elif KIND_OF.has(id):
		_prev_mode("chart")
		if not ScientificDataManager.history_loaded:
			_chart_fn = Callable()
			_prev_chart.queue_redraw()
			_prev_mode("info")
			_prev_info.text = "⏳ Cargando el archivo 2025–2026…"
			_caption("Se descarga por tramos de 30 días y se guarda en caché.", "")
			return
		_chart_fn = _draw_monthly.bind(KIND_OF[id])
		_prev_chart.queue_redraw()
		_caption("%s por mes (2025 → hoy) · NASA DONKI · %s" % [d["name"], ScientificDataManager.LABEL_HISTORIC], ScientificDataManager.LABEL_HISTORIC)
	elif id == "noaa_swpc":
		var res: Dictionary = await NASADataManager.noaa("noaa-planetary-k-index")
		if _preview_for != id:
			return
		if res.get("ok", false) and res["data"] is Array and (res["data"] as Array).size() > 0:
			_prev_mode("chart")
			_chart_fn = _draw_kp.bind(res["data"])
			_prev_chart.queue_redraw()
			_caption("Índice Kp cada 3 h (últimos %d valores) · NOAA SWPC · %s" % [(res["data"] as Array).size(), label], label)
		else:
			_prev_mode("info")
			_prev_info.text = "📉 Sin datos de NOAA ahora"
			_caption("Sin conexión y sin copia guardada.", "")
	elif id == "cmr_isslis":
		var ctx: Dictionary = await ScientificDataManager.get_station_context()
		if _preview_for != id:
			return
		if ctx.get("ok", false):
			_prev_mode("chart")
			_chart_fn = _draw_coverage.bind(ctx["record"])
			_prev_chart.queue_redraw()
			_caption("Cobertura del sensor LIS (ISS) · NASA Earthdata · %s" % ScientificDataManager.LABEL_HISTORIC, ScientificDataManager.LABEL_HISTORIC)
		else:
			_prev_mode("info")
			_prev_info.text = "🛰 Sin datos de Earthdata ahora"
			_caption("Sin conexión y sin copia guardada.", "")
	elif id == "donki_notifications" or id == "donki_wsa":
		var kind := "notifications" if id == "donki_notifications" else "WSAEnlilSimulations"
		var res: Dictionary = await NASADataManager.donki(kind, 30)
		if _preview_for != id:
			return
		var recs: Array = ScientificDataManager.normalize_donki(kind, res)
		recs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["event_time"]) > float(b["event_time"]))
		_prev_mode("info")
		if recs.is_empty():
			_prev_info.text = "Sin %s en los últimos 30 días" % ("avisos" if kind == "notifications" else "simulaciones")
			_caption("Sin datos ahora (o sin conexión y sin copia guardada).", "")
		else:
			var lines: PackedStringArray = ["Lo más reciente:"]
			for r in recs.slice(0, 4):
				lines.append("• %s · %s" % [Time.get_date_string_from_unix_time(int(r["event_time"])), str(r["title"])])
			_prev_info.text = "\n".join(lines)
			_caption("%d en los últimos 30 días · NASA DONKI · %s" % [recs.size(), label], label)
	else:
		_prev_mode("info")
		var is_ref := str(d.get("kind", "")) == "reference"
		_prev_info.text = ("📚 Documentación oficial de NASA\n\nSe cita dentro del juego y se enlaza abajo." if is_ref
				else ("⚙ Parámetros del juego\n\nSon valores de simulación, no datos medidos." if str(d.get("kind", "")) == "parameter"
				else "Sin vista previa para este conjunto de datos.\n\nSolo informativo."))
		_caption(label, label)


func _txt(c: Control, text: String, pos: Vector2, size: int, col: Color) -> void:
	c.draw_string(ThemeDB.fallback_font, pos, Lang.t(text), HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _draw_monthly(c: Control, kind: String) -> void:
	var w := c.size.x
	var h := c.size.y
	var now_d := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system()))
	var months := (int(now_d["year"]) - 2025) * 12 + int(now_d["month"])
	var counts: Array = []
	var strong: Array = []
	for i in months:
		counts.append(0)
		strong.append(0)
	for r in ScientificDataManager.history:
		if r["kind"] != kind:
			continue
		var dt := Time.get_datetime_dict_from_unix_time(int(r["event_time"]))
		var idx := (int(dt["year"]) - 2025) * 12 + int(dt["month"]) - 1
		if idx >= 0 and idx < months:
			counts[idx] += 1
			if int(r["severity"]) >= 2:
				strong[idx] += 1
	var mx := 1
	for v in counts:
		mx = maxi(mx, int(v))
	c.draw_rect(Rect2(0, 0, w, h), Color("0a1330"))
	var base := h - 22.0
	var bw := (w - 16.0) / months
	for i in months:
		var bh := (base - 22.0) * float(counts[i]) / mx
		c.draw_rect(Rect2(8 + i * bw + 1, base - bh, bw - 2, bh), Color("3f6fd0"))
		var sh := (base - 22.0) * float(strong[i]) / mx
		c.draw_rect(Rect2(8 + i * bw + 1, base - sh, bw - 2, sh), Color("ffb13d"))
	c.draw_line(Vector2(8, base), Vector2(w - 8, base), C_MUTED, 1.0)
	_txt(c, "máx. %d por mes" % mx, Vector2(8, 14), 12, C_TEXT)
	_txt(c, "ene 2025", Vector2(8, h - 6), 11, C_MUTED)
	_txt(c, "hoy", Vector2(w - 28, h - 6), 11, C_MUTED)
	c.draw_rect(Rect2(w - 196, 5, 9, 9), Color("3f6fd0"))
	_txt(c, "eventos", Vector2(w - 184, 14), 11, C_TEXT)
	c.draw_rect(Rect2(w - 128, 5, 9, 9), Color("ffb13d"))
	_txt(c, "fuertes (nivel ≥2)", Vector2(w - 116, 14), 11, C_TEXT)


func _draw_kp(c: Control, data: Array) -> void:
	var w := c.size.x
	var h := c.size.y
	c.draw_rect(Rect2(0, 0, w, h), Color("0a1330"))
	var n := data.size()
	var base := h - 20.0
	var bw := (w - 16.0) / maxf(1.0, n)
	for i in n:
		var kp := float(data[i].get("Kp", 0.0))
		var bh := (base - 20.0) * kp / 9.0
		var col := C_REAL if kp < 4.0 else (C_HIST if kp < 5.0 else C_BAD)
		c.draw_rect(Rect2(8 + i * bw + 0.5, base - bh, maxf(1.0, bw - 1.0), bh), col)
	var y5 := base - (base - 20.0) * 5.0 / 9.0
	c.draw_line(Vector2(8, y5), Vector2(w - 8, y5), C_BAD, 1.0)
	_txt(c, "Kp 5 = tormenta geomagnética", Vector2(10, y5 - 4), 11, C_BAD)
	c.draw_line(Vector2(8, base), Vector2(w - 8, base), C_MUTED, 1.0)
	_txt(c, "hace ~%d días" % int(round(n * 3.0 / 24.0)), Vector2(8, h - 5), 11, C_MUTED)
	_txt(c, "ahora", Vector2(w - 38, h - 5), 11, C_MUTED)


func _draw_coverage(c: Control, rec: Dictionary) -> void:
	var w := c.size.x
	var h := c.size.y
	c.draw_rect(Rect2(0, 0, w, h), Color("0a1330"))
	var y0 := 2015.0
	var y1 := 2027.0
	var f := func(unix: float) -> float:
		var dt := Time.get_datetime_dict_from_unix_time(int(unix))
		var yr := float(dt["year"]) + (float(dt["month"]) - 1.0) / 12.0
		return 12.0 + (yr - y0) / (y1 - y0) * (w - 24.0)
	var xs: float = f.call(float(rec["coverage_start"]))
	var xe: float = f.call(float(rec["coverage_end"]))
	var xn: float = f.call(Time.get_unix_time_from_system())
	c.draw_line(Vector2(12, h * 0.55), Vector2(w - 12, h * 0.55), C_MUTED, 1.0)
	c.draw_rect(Rect2(xs, h * 0.55 - 14, maxf(2.0, xe - xs), 28), Color("3f6fd0"))
	c.draw_line(Vector2(xn, h * 0.3), Vector2(xn, h * 0.8), C_BAD, 2.0)
	_txt(c, "hoy", Vector2(xn - 10, h * 0.3 - 4), 12, C_BAD)
	_txt(c, "Sensor LIS en la ISS", Vector2(12, 20), 14, C_TEXT)
	_txt(c, "%s → %s" % [Time.get_date_string_from_unix_time(int(rec["coverage_start"])), Time.get_date_string_from_unix_time(int(rec["coverage_end"]))], Vector2(12, 38), 12, C_HIST)
	_txt(c, "2015", Vector2(12, h - 8), 11, C_MUTED)
	_txt(c, "2027", Vector2(w - 36, h - 8), 11, C_MUTED)
	_txt(c, "La misión de datos terminó: es histórico", Vector2(12, h - 26), 11, C_MUTED)


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
	_show_preview(id)


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
	_vals["Uso en la misión"].text = str(d.get("game_use", "—"))
	_vals["Uso en la misión"].add_theme_color_override("font_color", Color("ffe08a"))
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
		"cache": return ["● CACHÉ LOCAL (copia guardada en tu equipo)", C_HIST]
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
	var pv := Control.new()
	pv.custom_minimum_size = Vector2(0, 170)
	lv.add_child(pv)
	_prev_tex = TextureRect.new()
	_prev_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_prev_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_prev_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pv.add_child(_prev_tex)
	_prev_chart = Control.new()
	_prev_chart.set_anchors_preset(Control.PRESET_FULL_RECT)
	_prev_chart.visible = false
	_prev_chart.draw.connect(func() -> void:
		if _chart_fn.is_valid():
			_chart_fn.call(_prev_chart))
	pv.add_child(_prev_chart)
	_prev_info = Label.new()
	_prev_info.set_anchors_preset(Control.PRESET_FULL_RECT)
	_prev_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prev_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prev_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prev_info.add_theme_font_size_override("font_size", 15)
	_prev_info.add_theme_color_override("font_color", C_TEXT)
	_prev_info.visible = false
	pv.add_child(_prev_info)
	_prev_caption = Label.new()
	_prev_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prev_caption.custom_minimum_size = Vector2(0, 34)
	_prev_caption.text = "Cargando…"
	_prev_caption.add_theme_font_size_override("font_size", 12)
	_prev_caption.add_theme_color_override("font_color", C_MUTED)
	lv.add_child(_prev_caption)
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
	for k in ["Fuente", "Descripción", "Uso en la misión", "Fecha del dato", "Fecha de consulta", "Tipo de información",
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
