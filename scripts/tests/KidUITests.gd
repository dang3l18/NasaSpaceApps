extends Node
## Pruebas del rediseno infantil: iconos en vez de texto, tarjetas ilustradas, medidores con 3 estados,
## textos legibles (nunca menos de 14 px), todos los edificios con frase y analogia.
## Ejecutar: godot --headless --path <proyecto> res://scenes/KidUITests.tscn

var _pass := 0
var _fail := 0


func _check(c: bool, msg: String) -> void:
	if c:
		_pass += 1
		print("  [OK]    " + msg)
	else:
		_fail += 1
		print("  [FALLO] " + msg)


func _ready() -> void:
	NASADataManager.simulate_offline = true
	print("=== PRUEBAS DE INTERFAZ INFANTIL ===")
	_test_text_to_icons()
	_test_cards()
	_test_modules_text()
	await _test_game_screen()
	await _test_menu()
	await _test_tutorial()
	await _test_mission_series()
	await _test_results()
	print("\nRESULTADO: %d OK, %d FALLOS" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _small_fonts(root: Node) -> int:
	var n := 0
	for l in root.find_children("*", "Label", true, false):
		var lab := l as Label
		if lab.has_theme_font_size_override("font_size") and lab.get_theme_font_size("font_size") < UI.MIN_FONT and lab.text.strip_edges() != "":
			n += 1
			print("     texto pequeño: «%s» (%d)" % [lab.text, lab.get_theme_font_size("font_size")])
	for b in root.find_children("*", "Button", true, false):
		var bt := b as Button
		if bt.has_theme_font_size_override("font_size") and bt.get_theme_font_size("font_size") < UI.MIN_FONT:
			n += 1
	return n


func _test_text_to_icons() -> void:
	print("\nDel texto a los iconos")
	var ch := KidText.chips(["Gasta 70 de energía", "Más comida", "−70 energía este turno", "Casi no crece comida"])
	_check(ch.size() == 2 and ch[0]["icon"] == "⚡" and ch[0]["num"] == "70" and ch[1]["icon"] == "🍎", "«Gasta 70 de energía / Más comida» → ⚡70 y 🍎 (sin repetir)")
	_check(KidText.icons_in("Soporte vital, protección, energía y alimentos").size() == 4, "una lista de sistemas se convierte en 4 iconos")
	_check(KidText.short("Se acerca la noche lunar. ¿Cómo usamos las baterías?", 90) == "Se acerca la noche lunar.", "las preguntas largas se reducen a una frase")
	_check(KidText.short("a".repeat(30) + " " + "b".repeat(100), 50).ends_with("…"), "los textos muy largos se recortan con «…»")
	_check(KidText.sentence("CULTIVOS O ENERGÍA") == "Cultivos o energía", "los títulos no gritan en mayúsculas")
	var states := [KidText.state(0), KidText.state(1), KidText.state(2)]
	_check(states[0]["icon"] != states[1]["icon"] and states[1]["icon"] != states[2]["icon"], "cada estado tiene su símbolo además del color (accesibilidad)")
	var m := KidKit.meter("⚡", "Energía", Color.YELLOW)
	KidKit.set_meter(m, 80.0)
	var c_ok: Color = (m["bar"] as ProgressBar).get_theme_stylebox("fill").bg_color
	KidKit.set_meter(m, 45.0)
	var c_mid: Color = (m["bar"] as ProgressBar).get_theme_stylebox("fill").bg_color
	KidKit.set_meter(m, 10.0)
	var c_bad: Color = (m["bar"] as ProgressBar).get_theme_stylebox("fill").bg_color
	_check(c_ok == UI.GREEN and c_mid == UI.YELLOW and c_bad == UI.RED, "el medidor es verde / amarillo / rojo según el valor")
	_check(str((m["val"] as Label).text).contains("✗"), "el medidor en rojo muestra el símbolo ✗ y un número sin decimales: «%s»" % (m["val"] as Label).text)


func _test_cards() -> void:
	print("\nTarjetas de decisión")
	var total := 0
	var with_both := 0
	var with_some := 0
	var max_opts := 0
	for mid in ["lunar_awakening", "storm_horizon", "lunar_blackout", "lava_harvest", "orbital_shadow", "thermal_anomaly"]:
		var s := BaseState.new(false, MissionManager.get_mission(mid))
		for t in range(1, s.turns + 1):
			s.turn = t
			for card in MissionDirector.cards_for_turn(s):
				for o in card["options"]:
					total += 1
					var g := KidText.chips(o.get("good", [])).size()
					var b := KidText.chips(o.get("bad", [])).size()
					if g > 0 and b > 0:
						with_both += 1
					if g > 0 or b > 0:
						with_some += 1
				max_opts = maxi(max_opts, (card["options"] as Array).size())
	_check(total >= 20, "se revisaron %d opciones de decisión de las 6 misiones" % total)
	_check(with_some == total, "todas las opciones muestran sus consecuencias con iconos (%d de %d)" % [with_some, total])
	_check(float(with_both) / float(total) >= 0.85, "casi todas muestran lo que ganas Y lo que gastas (%d de %d)" % [with_both, total])
	_check(max_opts <= 3, "ninguna decisión ofrece más de 3 alternativas")


func _test_modules_text() -> void:
	print("\nEdificios")
	var ok_phrase := true
	var ok_analogy := true
	for id in ModuleDefs.ORDER:
		for lvl in 3:
			if KidText.module_phrase(id, lvl) == "":
				ok_phrase = false
		if str(KidText.ANALOGY.get(id, "")) == "":
			ok_analogy = false
	_check(ok_phrase, "los 14 edificios tienen una frase para cada estado (peligro / cuidado / bien)")
	_check(ok_analogy, "los 14 edificios tienen una analogía sencilla del robot")
	_check(KidText.MODULE_PHRASE.size() == ModuleDefs.ORDER.size(), "no sobra ni falta ningún edificio")


func _test_game_screen() -> void:
	print("\nPantalla de juego")
	MissionManager.current = MissionManager.get_mission("lunar_awakening")
	var g: Control = load("res://scenes/LunarBase.tscn").instantiate()
	g._simulated = true
	add_child(g)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(g._ind_rows.size() == 6, "seis medidores grandes con icono: oxígeno, agua, energía, comida, protección y materiales")
	_check(_small_fonts(g) == 0, "ningún texto del juego es menor de %d px" % UI.MIN_FONT)
	var bad_modules := 0
	for id in ModuleDefs.ORDER:
		g._select(id)
		await get_tree().process_frame
		var texts := ""
		for l in g._module_box.find_children("*", "Label", true, false):
			texts += (l as Label).text + " "
		if not (texts.contains("✓") or texts.contains("⚠") or texts.contains("✗")) or KidText.module_phrase(id, g._status_level(id)) == "" or not texts.contains(KidText.module_phrase(id, g._status_level(id))):
			bad_modules += 1
			print("     ventana incompleta: ", id)
	_check(bad_modules == 0, "al tocar cada uno de los 14 edificios sale una ventana con estado (símbolo), nombre y frase")
	g._select("greenhouse")
	await get_tree().process_frame
	var long_texts := 0
	for l in g._module_box.find_children("*", "Label", true, false):
		if (l as Label).text.length() > 80:
			long_texts += 1
	_check(long_texts == 0, "la ventana del invernadero no tiene párrafos (ningún texto de más de 80 letras)")
	g.queue_free()
	await get_tree().process_frame


func _test_menu() -> void:
	print("\nMenú")
	var mm: Control = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(mm)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_small_fonts(mm) == 0, "ningún texto del menú es menor de %d px" % UI.MIN_FONT)
	var titles := ""
	for b in (mm._screens["title"] as Control).find_children("*", "Button", true, false):
		titles += (b as Button).text + "|"
	_check(titles.contains("JUGAR") and titles.contains("Continuar") and titles.contains("Ajustes"), "el título tiene JUGAR, Continuar y Ajustes")
	var words := 0
	for l in (mm._screens["title"] as Control).find_children("*", "Label", true, false):
		words += (l as Label).text.split(" ", false).size()
	_check(words <= 12, "la pantalla de título casi no tiene texto (%d palabras)" % words)
	mm.queue_free()
	await get_tree().process_frame


func _test_tutorial() -> void:
	print("
Robot guía y tutorial")
	var path := "user://tutorial_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var ctl := Control.new()
	ctl.size = Vector2(300, 100)
	ctl.position = Vector2(100, 100)
	add_child(ctl)
	var allow := {"v": true}
	var tg := TutorialGuide.new()
	tg.save_path = path
	add_child(tg)
	tg.can_show = func() -> bool: return bool(allow["v"])
	tg.targets = {"energy": func() -> Rect2: return ctl.get_global_rect(), "module": func() -> Rect2: return ctl.get_global_rect()}
	tg.notify("start")
	tg.notify("select")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(tg.active == "energy", "el primer paso señala el indicador de energía")
	tg._dismiss()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(tg.active == "module" and tg.seen.has("energy"), "al entender, pasa al siguiente paso y recuerda el anterior")
	allow["v"] = false
	await get_tree().process_frame
	_check(not tg.visible or tg._bubble == null or not tg._bubble.visible, "si se abre una ventana, el consejo se oculta (no estorba)")
	allow["v"] = true
	tg._dismiss()
	var tg2 := TutorialGuide.new()
	tg2.save_path = path
	add_child(tg2)
	tg2.can_show = func() -> bool: return true
	tg2.targets = tg.targets
	tg2.notify("start")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(tg2.active == "" and tg2.seen.has("energy"), "en la siguiente partida no se repite lo que ya se explicó")
	tg2.replay()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(tg2.active == "energy", "«Repetir ayuda» vuelve a explicar desde el principio")
	tg2.targets = {"energy": func() -> Rect2: return Rect2()}
	await get_tree().process_frame
	_check(tg2.active == "", "si el elemento está oculto, el robot no insiste")
	tg.queue_free()
	tg2.queue_free()
	ctl.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# En la partida: el robot reacciona
	MissionManager.current = MissionManager.get_mission("lunar_awakening")
	var g: Control = load("res://scenes/LunarBase.tscn").instantiate()
	g._simulated = true
	add_child(g)
	await get_tree().process_frame
	g._cheer()
	_check(g._robot_mood() == 2, "el robot se pone contento cuando va bien")
	g._happy_until = 0
	g.s.o2 = 5.0
	_check(g._robot_mood() == 0, "el robot se preocupa si el aire está en rojo")
	g.s.o2 = 85.0
	g.s.water = 10.0
	_check(g._robot_tip().contains("agua"), "avisa con frases cortas: «%s»" % g._robot_tip())
	g.s.water = 80.0
	g.s.main = 20.0
	g.s.backup = 20.0
	_check(g._robot_tip() == "¡Necesitamos más energía!", "«¡Necesitamos más energía!» cuando hace falta")
	g.queue_free()
	await get_tree().process_frame


func _test_results() -> void:
	print("
Alertas y resultados")
	for id in SpaceEvents.catalog().map(func(e: Dictionary) -> String: return str(e["id"])):
		if not (id in KidArt.KINDS):
			_check(false, "el evento %s no tiene ilustración animada" % id)
	var ok_art := true
	for k in KidArt.KINDS:
		var a := KidArt.make(k)
		add_child(a)
		await get_tree().process_frame
		await get_tree().process_frame
		ok_art = ok_art and is_instance_valid(a)
		a.queue_free()
	_check(ok_art, "las %d ilustraciones animadas se dibujan sin errores" % KidArt.KINDS.size())
	var every_chip := true
	for e in SpaceEvents.catalog():
		for o in e["options"]:
			if SpaceEvents.chips_for(o["fx"]).is_empty():
				every_chip = false
	_check(every_chip, "cada respuesta de una alerta se resume en iconos con número")
	var s := BaseState.new(false, MissionManager.get_mission("lunar_awakening"))
	s.won = true
	s.exposure = 20.0
	_check(s.stars() == 3, "ganar sin que ningún sistema baje de 30 da 3 estrellas")
	s.min_ind["alimentos"] = 20.0
	_check(s.stars() == 2, "si algún sistema bajó mucho, 2 estrellas")
	s.min_ind["alimentos"] = 5.0
	_check(s.stars() == 1, "si estuvo al límite, 1 estrella")
	s.won = false
	_check(s.stars() == 0, "sin superar la misión no hay estrellas (pero tampoco castigo)")
	MissionManager.current = MissionManager.get_mission("lunar_awakening")
	var g: Control = load("res://scenes/LunarBase.tscn").instantiate()
	g._simulated = true
	add_child(g)
	await get_tree().process_frame
	g._close_modal()
	g.s.finished = true
	g.s.won = false
	g.s.reason_id = "radiation"
	g._show_end()
	await get_tree().process_frame
	var txt := ""
	for l in g._modal_root.find_children("*", "Label", true, false):
		txt += (l as Label).text + " "
	_check(txt.contains("Buen intento") and txt.contains("escudo"), "si se pierde: mensaje positivo y qué mejorar («escudo»)")
	var bad := false
	for w in ["perdiste", "fracaso", "derrota", "fallaste"]:
		bad = bad or txt.to_lower().contains(w)
	_check(not bad, "el mensaje de pérdida no castiga ni humilla")
	_check(txt.contains("Hoy aprendimos"), "siempre muestra qué aprendimos")
	g._close_modal()
	g.s.won = true
	for ch in ["Activar ahorro", "Mantener soporte vital", "Luz LED alta", "Reforzar blindaje"]:
		g.s.decisions.append({"turn": 2, "title": "x", "choice": ch, "good": [], "bad": [], "sacrifice": ""})
	g._show_end()
	await get_tree().process_frame
	txt = ""
	for l in g._modal_root.find_children("*", "Label", true, false):
		txt += (l as Label).text + " "
	_check(txt.contains("⭐") and txt.contains("Misión cumplida"), "si se gana: celebración con estrellas")
	var vis_buttons := 0
	for b in g._modal_root.find_children("*", "Button", true, false):
		if (b as Button).get_global_rect().end.y <= 720.0:
			vis_buttons += 1
	_check(vis_buttons == 4, "la pantalla final cabe entera y muestra sus 4 botones")
	g._close_modal()
	g.s = BaseState.new(false, MissionManager.get_mission("storm_horizon"))
	g._show_alert_modal([])
	await get_tree().process_frame
	txt = ""
	for l in g._modal_root.find_children("*", "Label", true, false):
		txt += (l as Label).text + " "
	_check(txt.contains("Alerta solar") and txt.contains("SIMULACIÓN") or txt.contains("DATO"), "la alerta solar muestra el dato de NASA con su etiqueta honesta")
	_check(_small_fonts(g) == 0, "ni las alertas ni los resultados usan texto menor de %d px" % UI.MIN_FONT)
	g.queue_free()
	await get_tree().process_frame


func _test_mission_series() -> void:
	print("
Una serie de ayudas para cada misión")
	var own_sets: Array = []
	var first_steps: Array = []
	for mid in TutorialGuide.SERIES:
		var m := MissionManager.get_mission(mid)
		var series: Array = TutorialGuide.SERIES[mid]
		var own: Array = series.filter(func(id: String) -> bool: return not (id in TutorialGuide.BASICS))
		var valid := true
		for id in series:
			if not TutorialGuide.STEPS.has(id):
				valid = false
				continue
			var st: Dictionary = TutorialGuide.STEPS[id]
			if str(st["text"]).length() > 70:
				valid = false
				print("     texto largo: ", id)
			for tr in st["triggers"]:
				var trs := str(tr)
				if trs.begins_with("turn:") and (int(trs.substr(5)) < 2 or int(trs.substr(5)) > m.turns - 1):
					valid = false
				if trs == "alert" and m.alert_turn == 0:
					valid = false
		_check(valid, "%s: todos los pasos existen, son cortos y se disparan en turnos válidos" % m.title)
		if mid != "lunar_awakening":
			_check(own.size() >= 3, "%s tiene %d ayudas propias, no solo las básicas" % [m.title, own.size()])
		own_sets.append(own)
		first_steps.append(series[0])
	var overlap := false
	for i in own_sets.size():
		for j in range(i + 1, own_sets.size()):
			for id in own_sets[i]:
				if id in own_sets[j]:
					overlap = true
	_check(not overlap, "ninguna ayuda propia se repite entre misiones")
	var distinct := {}
	for f in first_steps:
		distinct[f] = true
	_check(distinct.size() == first_steps.size(), "cada misión empieza con una ayuda distinta")
	# En el juego: cada paso apunta a algo visible y la ayuda de inicio es la de la misión
	for mid in TutorialGuide.SERIES:
		MissionManager.current = MissionManager.get_mission(mid)
		var g: Control = load("res://scenes/LunarBase.tscn").instantiate()
		g._simulated = true
		add_child(g)
		await get_tree().process_frame
		g._build_tutorial()
		g._tutorial.save_path = "user://tutorial_test2.cfg"
		g._tutorial.can_show = func() -> bool: return true
		g._tutorial.notify("start")
		g._select("greenhouse")
		await get_tree().process_frame
		var all_visible := true
		for id in TutorialGuide.SERIES[mid]:
			if (g._tutorial_target(str(TutorialGuide.STEPS[id]["target"])) as Rect2).size == Vector2.ZERO:
				all_visible = false
				print("     no se ve el objetivo de ", id)
		_check(all_visible, "%s: todos los pasos apuntan a algo que se ve en pantalla" % MissionManager.current.title)
		await get_tree().process_frame
		await get_tree().process_frame
		var want: String = str(TutorialGuide.SERIES[mid][0])
		_check(g._tutorial.active == want, "%s: la primera ayuda es «%s»" % [MissionManager.current.title, want])
		g._tutorial.replay()
		_check(g._tutorial._queue.size() == (TutorialGuide.SERIES[mid] as Array).size(), "«Repetir ayuda» pone en cola la serie completa de la misión")
		g.queue_free()
		await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://tutorial_test2.cfg"))
