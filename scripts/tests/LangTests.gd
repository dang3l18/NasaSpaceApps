extends Node
## Comprueba que el juego en INGLES no deja texto en espanol: recorre menu, misiones, edificios, tarjetas de decision,
## alertas, resumenes, pantallas finales y tutorial, y busca palabras espanolas en lo que se muestra.
## Ejecutar: godot --headless --path <proyecto> res://scenes/LangTests.tscn   (sin red)

const SPANISH_WORDS := ["el", "la", "los", "las", "del", "con", "para", "por", "una", "tu", "tus", "más", "menos", "sin", "hay", "muy",
		"ahora", "turno", "turnos", "energía", "misión", "luz", "aire", "agua", "comida", "plantas", "tripulación", "escudo", "refugio",
		"soporte", "vital", "invernadero", "datos", "dato", "cuando", "pero", "aunque", "mientras", "desde", "sobre", "entre", "puede",
		"hace", "tiene", "necesita", "mejora", "apagar", "encender", "enviar", "sellar", "reparar", "proteger", "nivel", "fecha", "noche",
		"hoy", "ayuda", "fuente", "eventos", "riesgo", "peligro", "cuidado", "bueno", "buena", "nuevo", "nueva", "hogar", "gasta",
		"cada", "todo", "todos", "esta", "este", "como", "donde", "porque", "también", "solo", "hasta", "tras", "dos", "tres", "cuatro",
		"explorador", "comandante", "completo", "intermedia", "avanzada", "marte", "investigar", "fertilizar", "dormitorios", "formato",
		"licencia", "actualizar", "cerrar", "ojo", "fácil", "difícil", "bloqueada", "superada", "jugar", "volver", "ajustes", "logros"]
const ALLOWED := ["Español"]

var _pass := 0
var _fail := 0
var _seen: Dictionary = {}       # texto fuente ya revisado
var _leftover: Dictionary = {}   # texto fuente -> traduccion (con espanol)
var _checked := 0
var online := false


func _ready() -> void:
	online = "--online" in OS.get_cmdline_user_args()   # con datos reales de NASA (necesita red)
	NASADataManager.simulate_offline = not online
	Lang.set_language("en", false)
	print("=== PRUEBA DE IDIOMA (inglés) ===")
	await _scan_menu()
	await _scan_game()
	await _scan_events()
	await _scan_data_center()
	_scan_static()
	_scan_source_literals()
	print("\nTextos revisados: %d" % _checked)
	if _leftover.is_empty():
		_pass += 1
		print("  [OK]    no queda texto en español en la versión inglesa")
	else:
		for k in _leftover:
			_fail += 1
			print("  [ESPAÑOL] «%s»  →  «%s»" % [str(k).replace("\n", "\\n"), str(_leftover[k]).replace("\n", "\\n")])
	var dict_ok := _dictionary_ok()
	print("\nRESULTADO: %d OK, %d FALLOS" % [_pass + (1 if dict_ok else 0), _fail + (0 if dict_ok else 1)])
	get_tree().quit(1 if (_fail > 0 or not dict_ok) else 0)


func _has_spanish(s: String) -> bool:
	for a in ALLOWED:
		if a in s:
			s = s.replace(a, "")
	for ch in "áéíóúñ¿¡Ñ":
		if ch in s:
			return true
	var re := RegEx.new()
	re.compile("[A-Za-zÁÉÍÓÚáéíóúñ]+")
	for m in re.search_all(s):
		if m.get_string().to_lower() in SPANISH_WORDS:
			return true
	return false


func _check_text(src: String) -> void:
	if src.strip_edges() == "" or _seen.has(src):
		return
	_seen[src] = true
	_checked += 1
	var out := Lang.t(src)
	if _has_spanish(out):
		_leftover[src] = out


func _collect(root: Node) -> void:
	for n in root.find_children("*", "Control", true, false):
		if n is Label:
			_check_text((n as Label).text)
		elif n is Button:
			_check_text((n as Button).text)
		elif n is LinkButton:
			_check_text((n as LinkButton).text)
		var tt: String = (n as Control).tooltip_text
		if tt != "":
			_check_text(tt)


func _dictionary_ok() -> bool:
	var d: Dictionary = Lang._read_json(Lang.DICT_PATH)
	var ok := true
	for k in d:
		if str(d[k]).strip_edges() == "":
			print("  [FALLO] traducción vacía: ", k)
			ok = false
	print("  [OK]    el diccionario tiene %d traducciones" % d.size() if ok else "  [FALLO] el diccionario tiene traducciones vacías")
	return ok


# -------------------------------------------------------------------- menu ----

func _scan_menu() -> void:
	MissionManager.reload()
	var mm: Control = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(mm)
	await get_tree().process_frame
	await get_tree().process_frame
	for name in mm._screens:
		mm._show(name)
		await get_tree().process_frame
		_collect(mm)
	for tier in [1, 2, 3]:
		mm._mission_tier = tier
		mm._show("missions")
		await get_tree().process_frame
		_collect(mm)
	for m in MissionManager.all():
		if m.ready:
			mm._open_briefing(m.id)
			await get_tree().process_frame
			_collect(mm)
	for i in mm.LEARN.size():
		mm._pick_topic(i)
		if online:
			await get_tree().create_timer(9.0).timeout
		else:
			for k in 6:
				await get_tree().process_frame
		_collect(mm)
	mm._fill_config()
	_collect(mm)
	mm.queue_free()
	await get_tree().process_frame


# -------------------------------------------------------------------- juego ----

func _scan_game() -> void:
	for mid in ["lunar_awakening", "storm_horizon", "lunar_blackout", "lava_harvest", "orbital_shadow", "thermal_anomaly"]:
		MissionManager.current = MissionManager.get_mission(mid)
		var g: Control = load("res://scenes/LunarBase.tscn").instantiate()
		g._simulated = true
		add_child(g)
		await get_tree().process_frame
		await get_tree().create_timer(0.3).timeout
		_collect(g)   # incluye la ventana de presentacion
		g._close_modal()
		g._info_open = true
		for id in ModuleDefs.ORDER:
			g._select(id)
			await get_tree().process_frame
			_collect(g)
		# tareas, riesgos y mensajes de cada turno
		var s: BaseState = g.s
		for tid in BaseState.TASKS:
			for r in s.risks({"led": 2, "tasks": [tid]}):
				_check_text(str(r["text"]))
			_check_text(str(BaseState.TASKS[tid]["name"]))
		for t in range(1, s.turns + 1):
			s.turn = t
			var news: Array = MissionDirector.start_of_turn(s)
			for n in news:
				_check_text(str(n))
			for card in MissionDirector.cards_for_turn(s):
				g._show_card(card, news)
				await get_tree().process_frame
				_collect(g)
				g._close_modal()
		# resumen de turno y pantallas finales
		var s2 := BaseState.new(false, MissionManager.current)
		g.s = s2
		s2.turn = 3
		var r2: Dictionary = s2.step({"led": 0, "tasks": []})
		for m in r2["msgs"]:
			_check_text(str(m))
		g._show_report(3, r2)
		await get_tree().process_frame
		_collect(g)
		g._close_modal()
		for reason in ["ls", "radiation", "energy", "food", "final", "win"]:
			var s3 := BaseState.new(false, MissionManager.current)
			g.s = s3
			s3.finished = true
			s3.won = reason == "win"
			s3.reason_id = reason
			s3.reason = "¡La base lunar sobrevivió los 3 días!" if s3.won else "No hubo comida suficiente para la tripulación."
			s3.decisions.append({"turn": 2, "title": "x", "choice": "Activar ahorro", "good": [], "bad": [], "sacrifice": ""})
			g._show_end()
			await get_tree().process_frame
			_collect(g)
			g._close_modal()
		if s2.alert_turn > 0 or mid == "storm_horizon":
			g.s = BaseState.new(false, MissionManager.current)
			g._show_alert_modal([])
			await get_tree().process_frame
			_collect(g)
			g._close_modal()
		# consejos del robot en distintos estados
		var s4 := BaseState.new(false, MissionManager.current)
		g.s = s4
		for setup in [{"main": 10.0, "backup": 10.0}, {"water": 10.0}, {"exposure": 60.0}, {"food": 5.0}, {"plant_health": 20.0}, {"ls_cond": 20.0}, {}]:
			var s5 := BaseState.new(false, MissionManager.current)
			for k in setup:
				s5.set(k, setup[k])
			g.s = s5
			_check_text(g._robot_tip())
		g.s = s4
		for sac in ["alimentos", "descanso", "obras", "reserva de emergencia", "datos", "calefacción", "oxígeno de las plantas", "soporte vital", ""]:
			var s6 := BaseState.new(false, MissionManager.current)
			s6.turn = 3
			s6.decisions.append({"turn": 3, "title": "t", "choice": "Activar ahorro", "good": [], "bad": [], "sacrifice": sac})
			_check_text(GuideCoach.advice(s6))
		g.queue_free()
		await get_tree().process_frame


# ------------------------------------------------------------------ alertas ----

func _scan_events() -> void:
	for e in SpaceEvents.catalog():
		var ev := AlertDirector.instance(e, 3, false)
		for idx in [-2, -1, 0, 1, 2]:
			var s := BaseState.new(false, MissionManager.get_mission("lunar_awakening"))
			var ov := AlertOverlay.new()
			ov.setup(ev, s)
			add_child(ov)
			await get_tree().process_frame
			_collect(ov)
			if idx > -2:
				ov.choose(idx)
				await get_tree().process_frame
				_collect(ov)
			ov.queue_free()
			await get_tree().process_frame


func _scan_data_center() -> void:
	var dc: Control = load("res://scenes/SpaceDataCenter.tscn").instantiate()
	add_child(dc)
	await get_tree().process_frame
	await get_tree().process_frame
	_collect(dc)
	for ds in DatasetManager.get_all():
		dc._select(str(ds["id"]))
		await get_tree().process_frame
		_collect(dc)
	for s in ["máx. 12 por mes", "ene 2025", "hoy", "eventos", "fuertes (nivel ≥2)", "Kp 5 = tormenta geomagnética", "hace ~3 días", "ahora",
			"Sensor LIS en la ISS", "La misión de datos terminó: es histórico"]:
		_check_text(s)
	dc.queue_free()
	await get_tree().process_frame


## Red de seguridad permanente: busca en TODO el codigo y los datos cualquier texto que parezca para el jugador y no
## este en el diccionario (asi una palabra suelta nueva como «Explorador» no se escapa aunque no la muestre ninguna pantalla probada).
func _scan_source_literals() -> void:
	var dict: Dictionary = Lang._read_json(Lang.DICT_PATH)
	var tech := ["Label", "Button", "Control", "Panel", "PanelContainer", "Node", "Timer", "Tween", "ColorRect", "ShaderMaterial", "Dictionary",
			"Array", "String", "Color", "HBoxContainer", "VBoxContainer", "CenterContainer", "MarginContainer", "ScrollContainer", "HFlowContainer",
			"FlowContainer", "TextureRect", "LinkButton", "RegEx", "FontVariation", "ProgressBar", "CheckButton", "JSON", "Scale", "OK", "GET", "POST",
			"NASA DONKI", "NASA Earthdata CMR", "NOAA SWPC", "NASA GIBS", "NASA LRO · Moon Trek", "NOAA SWPC + NASA DONKI", "SPACE DATA CENTER",
			"🚀  Junior Astronaut", "Accept: */*", "User-Agent: ", "User-Agent:", "Zyranth/0.1 (educational game)",
			# nombres propios, identificadores de las APIs y palabras iguales en espanol e ingles: NO se traducen
			"&TIME=", "[NOAA SWPC · %s]", "HTTP %d", "MODIS_Terra_CorrectedReflectance_TrueColor", "VIIRS_SNPP_CorrectedReflectance_TrueColor",
			"VIIRS_Black_Marble", "WSAEnlilSimulations", "NOAA_noaa-planetary-k-index", "NASA / GSFC / CCMC - DONKI", "NASA · ECLSS",
			"NASA · Radiation Protection", "NASA DONKI (CCMC)", "NASA ECLSS", "NASA EOSDIS / GHRC DAAC", "NASA EOSDIS Global Imagery Browse Services (GIBS)",
			"NASA GIBS / Worldview", "NASA LRO", "NASA Lunar Reconnaissance Orbiter · NASA Moon Trek", "NASA Planetary Data System · Geosciences Node",
			"NASA Planetary Data System", "NASA Radiation Protection", "NASA Science · LRO", "NASA Science · Veggie", "NASA Veggie",
			"NOAA Space Weather Prediction Center", "Normal\n⚡%d", "WMS (JPEG)", "WMS (PNG)", "WMTS (JPEG)", "🖥 Control: %s (⚡%d)",
			"Zyranth · Junior Astronaut: Mission Trainer"]
	var letters := RegEx.new()
	letters.compile("[A-Za-zÁÉÍÓÚáéíóúñ]{3}")
	var ident := RegEx.new()
	ident.compile("^[a-z_0-9:\\-./%#@$&=?,;()\\[\\]*+]+$")
	var camel := RegEx.new()
	camel.compile("^([a-z]+[A-Z]\\w*|[A-Z_0-9]+)$")
	var missing: Array = []
	for path in _list_files("res://scripts", ".gd"):
		if "/tests/" in path or path.ends_with("DataTest.gd") or path.ends_with("FontSetup.gd") or path.ends_with("Lang.gd"):
			continue
		var n := 0
		for line in FileAccess.get_file_as_string(path).split("\n"):
			n += 1
			var st := line.strip_edges()
			if st.begins_with("#") or st.begins_with("print(") or st.contains("push_warning(") or st.begins_with("assert("):
				continue
			for lit in _literals(line):
				var s: String = lit
				var c := s.strip_edges()
				if c == "" or dict.has(s) or dict.has(c) or c in tech or letters.search(c) == null:
					continue
				if ident.search(c) != null or camel.search(c) != null or c.begins_with("res://") or c.begins_with("user://") or c.begins_with("http") \
						or c.begins_with("--") or c.contains("{") or c.contains("SERVICE=") or c.ends_with("_"):
					continue
				missing.append("%s:%d  «%s»" % [path.get_file(), n, c])
	var d: Dictionary = Lang._read_json("res://data/datasets.json")
	for ds in d.get("datasets", []):
		for k in ["name", "info_type", "source", "attribution", "license", "format", "description", "game_use", "type"]:
			var v := str(ds.get(k, "")).strip_edges()
			if v != "" and not dict.has(v) and letters.search(v) != null and ident.search(v) == null and not (v in tech) and not v.begins_with("http"):
				missing.append("datasets.json:%s  «%s»" % [k, v])
	_checked += missing.size()
	if missing.is_empty():
		_pass += 1
		print("  [OK]    todo texto del código y de los datos tiene traducción")
	else:
		for mm in missing:
			_fail += 1
			print("  [SIN TRADUCIR] ", mm)


## Cadenas entre comillas de una linea de GDScript (con sus escapes \n y \").
func _literals(line: String) -> Array:
	var out: Array = []
	var i := 0
	while i < line.length():
		if line[i] == "\"":
			var j := i + 1
			var cur := ""
			while j < line.length() and line[j] != "\"":
				if line[j] == "\\" and j + 1 < line.length():
					var e := line[j + 1]
					cur += "\n" if e == "n" else ("\t" if e == "t" else e)
					j += 2
				else:
					cur += line[j]
					j += 1
			out.append(cur)
			i = j + 1
		else:
			i += 1
	return out


func _list_files(dir_path: String, ext: String) -> Array:
	var out: Array = []
	var da := DirAccess.open(dir_path)
	if da == null:
		return out
	for f in da.get_files():
		if f.ends_with(ext):
			out.append(dir_path + "/" + f)
	for sub in da.get_directories():
		out.append_array(_list_files(dir_path + "/" + sub, ext))
	return out


func _scan_static() -> void:
	for id in TutorialGuide.STEPS:
		_check_text(str(TutorialGuide.STEPS[id]["text"]))
	for id in ModuleDefs.ORDER:
		var d: Dictionary = ModuleDefs.DEFS[id]
		for k in ["name", "func", "needs", "conseq"]:
			_check_text(str(d.get(k, "")))
		if d.has("ref"):
			_check_text(str(d["ref"]["text"]))
			_check_text(str(d["ref"]["label"]))
	for k in KidText.ANALOGY:
		_check_text(str(KidText.ANALOGY[k]))
	for k in KidText.MODULE_PHRASE:
		for p in KidText.MODULE_PHRASE[k]:
			_check_text(str(p))
	for k in KidText.LEARN:
		for p in KidText.LEARN[k]:
			_check_text(str(p))
	for m in MissionManager.all():
		for t in [m.title, m.place, m.summary, m.dilemma_title, m.dilemma_text, m.protect, m.sacrifice, m.victory_text, m.modifiers_text()]:
			_check_text(str(t))
		for o in m.objectives:
			_check_text(o)
	for id in AchievementManager.DEFS if "DEFS" in AchievementManager else []:
		pass
	for ds in DatasetManager.get_all():
		for k in ["name", "description", "game_use", "type", "attribution"]:
			_check_text(str(ds.get(k, "")))
