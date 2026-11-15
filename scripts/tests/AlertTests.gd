extends Node
## Pruebas del sistema de alertas espaciales: catalogo, consecuencias reales, limites, generacion sin saturar,
## dificultad/progresion y la pantalla de alerta (botones, cuenta regresiva, bloqueo del juego).
## Ejecutar: godot --headless --path <proyecto> res://scenes/AlertTests.tscn

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
	print("=== PRUEBAS DE ALERTAS ESPACIALES ===")
	_test_catalog()
	_test_consequences()
	_test_limits()
	_test_director()
	await _test_overlay()
	await _test_game_integration()
	print("\nRESULTADO: %d OK, %d FALLOS" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _state(mission_id: String = "lunar_awakening", easy: bool = false) -> BaseState:
	return BaseState.new(easy, MissionManager.get_mission(mission_id))


func _snapshot(s: BaseState) -> Dictionary:
	return {"energy": s.main + s.backup, "materials": s.materials, "exposure": s.exposure, "o2": s.o2, "health": s.health,
			"plant": s.plant_health, "shield": s.shield, "ls": s.ls_cond, "food": s.food, "hours": s.hours_penalty,
			"solar": s.solar_event_mult, "score": s.alert_score, "backup": s.backup}


# --------------------------------------------------------------- catalogo ----

func _test_catalog() -> void:
	print("\nCatálogo de eventos")
	var cat := SpaceEvents.catalog()
	var ids: Array = []
	for e in cat:
		ids.append(e["id"])
	for want in ["meteor", "flare", "dust", "leak", "power", "thermal"]:
		_check(want in ids, "existe el evento pedido «%s»" % want)
	var ok_all := true
	for e in cat:
		var opts: Array = e["options"]
		var good := opts.size() >= 3 and float(e["seconds"]) >= 14.0 and int(e["tier"]) >= 1 and int(e["tier"]) <= 3
		good = good and str(e["title"]) != "" and str(e["desc"]) != "" and str(e["fact"]) != "" and (e["timeout"] as Dictionary).has("fx")
		for o in opts:
			good = good and not (o["good"] as Array).is_empty() and not (o["bad"] as Array).is_empty() and (o["fx"] as Dictionary).size() >= 2 and str(o["result"]) != ""
		if not good:
			ok_all = false
			print("     evento mal formado: ", e["id"])
	_check(ok_all, "todos tienen 3 opciones con ventajas y desventajas, efectos, dato curioso y consecuencia por no responder")
	# Ninguna opcion es siempre la mejor: las puntuaciones difieren y no hay una opcion con todo positivo.
	var no_free_lunch := true
	for e in cat:
		var scores: Array = []
		for o in e["options"]:
			scores.append(int(o["fx"].get("score", 0)))
			var neg := false
			for k in o["fx"]:
				if k == "hours" or k == "solar":
					neg = true
				elif k != "score":
					var d := float(o["fx"][k])
					if (k != "exposure" and d < 0.0) or (k == "exposure" and d > 0.0):
						neg = true
			if not neg:
				no_free_lunch = false
		var distinct := scores.duplicate()
		distinct.sort()
		if distinct[0] == distinct[distinct.size() - 1]:
			no_free_lunch = false
	_check(no_free_lunch, "cada opción tiene un coste real y las opciones no valen lo mismo")
	var worse := true
	for e in cat:
		var tmin := 999
		for o in e["options"]:
			tmin = mini(tmin, int(o["fx"].get("score", 0)))
		worse = worse and int(e["timeout"]["fx"].get("score", 0)) < tmin
	_check(worse, "no responder siempre puntúa peor que cualquier respuesta")
	_check(not (SpaceEvents.by_id("dust")["only"] as Array).is_empty(), "la tormenta de polvo marciana solo aparece en misiones de Marte")


# ------------------------------------------------------------ consecuencias ----

func _test_consequences() -> void:
	print("\nLas decisiones cambian el estado de verdad")
	var s := _state()
	var a := _snapshot(s)
	var r := SpaceEvents.resolve(s, SpaceEvents.by_id("meteor"), 0, 0.2)   # escudos
	var b := _snapshot(s)
	_check(float(b["energy"]) < float(a["energy"]) - 80.0, "activar escudos gasta energía (%d → %d)" % [a["energy"], b["energy"]])
	_check(float(b["shield"]) < float(a["shield"]), "…y el blindaje sufre un poco")
	_check(int(r["score"]) == 10 and s.alert_score == 10, "…y suma 10 puntos (sin bonus de rapidez)")
	_check(s.alert_log.size() == 1 and s.alert_log[0]["id"] == "meteor", "queda registrada en el historial de alertas")
	# bonus de rapidez
	var s2 := _state()
	var r2 := SpaceEvents.resolve(s2, SpaceEvents.by_id("meteor"), 0, 0.9)
	_check(int(r2["bonus"]) == SpaceEvents.SPEED_BONUS and int(r2["score"]) == 10 + SpaceEvents.SPEED_BONUS, "decidir rápido da +%d puntos" % SpaceEvents.SPEED_BONUS)
	# distintas opciones, distintas consecuencias
	var s3 := _state()
	SpaceEvents.resolve(s3, SpaceEvents.by_id("flare"), 0, 0.0)
	var s4 := _state()
	SpaceEvents.resolve(s4, SpaceEvents.by_id("flare"), 2, 0.0)
	_check(s3.exposure < s4.exposure and s3.hours_penalty > s4.hours_penalty, "refugio: menos radiación pero pierdes horas; el otro: más radiación y salud −")
	_check(s4.health < s3.health, "dejar a la tripulación expuesta baja la salud")
	# fuga de oxigeno
	var s5 := _state()
	var o2_before := s5.o2
	SpaceEvents.resolve(s5, SpaceEvents.by_id("leak"), -1, 0.0)
	_check(s5.o2 < o2_before - 15.0 and s5.alert_score < 0, "no responder a la fuga hace perder oxígeno y puntos (%d → %d)" % [o2_before, s5.o2])
	var s6 := _state()
	SpaceEvents.resolve(s6, SpaceEvents.by_id("leak"), 2, 0.0)   # soporte vital al maximo: sube el aire
	_check(s6.o2 > s5.o2 and s6.ls_cond < 85.0, "subir el soporte vital repone aire pero lo desgasta")
	# paneles solares: el efecto se nota en la generacion y caduca
	var s7 := _state()
	var gen0 := s7.generation()
	SpaceEvents.resolve(s7, SpaceEvents.by_id("eclipse"), 1, 0.0)
	_check(s7.generation() < gen0 * 0.55 and s7.generation() > 0.0, "el eclipse reduce la generación de los paneles (%d → %d)" % [gen0, s7.generation()])
	s7.step({"led": 1, "tasks": []})
	_check(s7.solar_event_turns == 1 and s7.solar_event_mult < 1.0, "dura más de un turno")
	s7.step({"led": 1, "tasks": []})
	_check(s7.solar_event_turns == 0 and is_equal_approx(s7.solar_event_mult, 1.0), "…y después los paneles se recuperan")
	# energia: gasta primero la principal, la reserva despues; la opcion de reserva toca la reserva
	var s8 := _state()
	var bk := s8.backup
	SpaceEvents.resolve(s8, SpaceEvents.by_id("power"), 2, 0.0)
	_check(s8.backup < bk - 100.0, "pasar a la batería de respaldo gasta la reserva (%d → %d)" % [bk, s8.backup])
	# horas de trabajo
	var s9 := _state()
	var hb := s9.hours_budget()
	SpaceEvents.resolve(s9, SpaceEvents.by_id("flare"), 0, 0.0)
	_check(s9.hours_budget() == hb - 4, "perder horas reduce el presupuesto de horas del turno (%d → %d)" % [hb, s9.hours_budget()])
	# modo 7-9: perdidas mas suaves
	var se := _state("lunar_awakening", true)
	var sn := _state("lunar_awakening", false)
	SpaceEvents.resolve(se, SpaceEvents.by_id("meteor"), -1, 0.0)
	SpaceEvents.resolve(sn, SpaceEvents.by_id("meteor"), -1, 0.0)
	_check(se.shield > sn.shield and se.materials > sn.materials, "en el modo 7–9 años las pérdidas son un 25% menores")


func _test_limits() -> void:
	print("\nLímites: una alerta no puede terminar la misión por sí sola")
	var survived := true
	for e in SpaceEvents.catalog():
		for idx in [-1, 0, 1, 2]:
			var s := _state("thermal_anomaly")
			s.o2 = 20.0
			s.exposure = 80.0
			s.main = 40.0
			s.backup = 20.0
			s.health = 25.0
			for k in 5:   # la misma alerta cinco veces seguidas
				SpaceEvents.resolve(s, e, idx, 0.0)
			s.check_end_now()
			if s.finished or s.o2 <= 0.0 or s.exposure >= 100.0 or s.main < 0.0 or s.backup < 0.0 or s.materials < 0.0:
				survived = false
				print("     fin con ", e["id"], " opción ", idx)
	_check(survived, "ningún evento, ni repetido 5 veces desde un estado muy débil, provoca la derrota ni valores negativos")


# -------------------------------------------------------------- generacion ----

func _play_clock(s: BaseState, d: AlertDirector, seconds: float, turn_fn: Callable = Callable()) -> Array:
	var fired: Array = []
	var t := 0.0
	while t < seconds:
		t += 0.25
		if turn_fn.is_valid():
			turn_fn.call(s, t)
		var ev := d.tick(0.25, s)
		if not ev.is_empty():
			fired.append({"t": t, "ev": ev, "turn": s.turn})
	return fired


func _test_director() -> void:
	print("\nGeneración de eventos")
	for mid in ["lunar_awakening", "orbital_shadow", "thermal_anomaly"]:
		var s := _state(mid)
		s.turn = 3
		var d := AlertDirector.new(s, 123)
		var fired := _play_clock(s, d, 1200.0)
		var spaced := true
		for i in range(1, fired.size()):
			if float(fired[i]["t"]) - float(fired[i - 1]["t"]) < AlertDirector.COOLDOWN - 0.01:
				spaced = false
		_check(fired.size() <= d.max_count and fired.size() >= 1, "%s: %d alertas (máximo %d), no se satura" % [mid, fired.size(), d.max_count])
		_check(spaced and (fired.is_empty() or float(fired[0]["t"]) >= AlertDirector.FIRST_MIN), "%s: espera de %d s entre alertas y primera no antes de %d s" % [mid, AlertDirector.COOLDOWN, AlertDirector.FIRST_MIN])
	# intervalos variables
	var gaps: Array = []
	for sd in range(1, 40):
		var sx := _state("lunar_awakening")
		sx.turn = 2
		var dx := AlertDirector.new(sx, sd)
		var f := _play_clock(sx, dx, 600.0)
		if f.size() >= 2:
			gaps.append(float(f[1]["t"]) - float(f[0]["t"]))
	var mn := 999.0
	var mx := 0.0
	for g in gaps:
		mn = minf(mn, g)
		mx = maxf(mx, g)
	_check(gaps.size() > 10 and mx - mn > 8.0, "los intervalos entre alertas varían (%d–%d s)" % [mn, mx])
	# dificultad: mas alertas / menos tiempo en una mision dificil que en una facil
	var total_easy := 0
	var total_hard := 0
	for sd in range(1, 41):
		var a := _state("lunar_awakening")
		a.turn = 3
		total_easy += _play_clock(a, AlertDirector.new(a, sd), 600.0).size()
		var b := _state("thermal_anomaly")
		b.turn = 3
		total_hard += _play_clock(b, AlertDirector.new(b, sd), 600.0).size()
	_check(total_hard > total_easy, "la misión más difícil recibe más alertas (%d frente a %d en 40 partidas)" % [total_hard, total_easy])
	var se := _state("thermal_anomaly", true)
	var sh := _state("thermal_anomaly", false)
	_check(AlertDirector.new(se, 1).max_count < AlertDirector.new(sh, 1).max_count, "el modo 7–9 años tiene menos alertas")
	var ev_e := AlertDirector.instance(SpaceEvents.by_id("meteor"), 9, true)
	var ev_h := AlertDirector.instance(SpaceEvents.by_id("meteor"), 9, false)
	var ev_f := AlertDirector.instance(SpaceEvents.by_id("meteor"), 1, false)
	_check(float(ev_e["seconds"]) > float(ev_h["seconds"]) and float(ev_h["seconds"]) < float(ev_f["seconds"]), "más dificultad = menos tiempo para reaccionar; modo 7–9 = más tiempo (%d / %d / %d s)" % [ev_e["seconds"], ev_h["seconds"], ev_f["seconds"]])
	# progresion: eventos mas peligrosos al avanzar
	var early := 0.0
	var late := 0.0
	var n := 400
	for i in n:
		var s1 := _state("orbital_shadow")
		s1.turn = 1
		var d1 := AlertDirector.new(s1, i + 1)
		early += float(d1.pick(s1)["tier"])
		var s2 := _state("orbital_shadow")
		s2.turn = s2.turns - 1
		var d2 := AlertDirector.new(s2, i + 1)
		late += float(d2.pick(s2)["tier"])
	_check(late / n > early / n + 0.4, "los eventos son más peligrosos al avanzar la misión (peligro medio %.2f → %.2f)" % [early / n, late / n])
	# restricciones
	var sr := _state("orbital_shadow")
	var seen_dust := false
	var consecutive := false
	var dr := AlertDirector.new(sr, 5)
	var last := ""
	for i in 300:
		var e := dr.pick(sr)
		seen_dust = seen_dust or e["id"] == "dust"
		dr.last_id = str(e["id"])
		if str(e["id"]) == last:
			consecutive = true
		last = str(e["id"])
	_check(not seen_dust, "la tormenta de polvo marciana no sale fuera de Marte")
	_check(not consecutive, "nunca salen dos alertas iguales seguidas")
	var sq := _state("lunar_awakening")
	sq.turn = sq.alert_turn
	var dq := AlertDirector.new(sq, 9)
	_check(_play_clock(sq, dq, 600.0).is_empty(), "no hay alertas en el turno de la tormenta solar de la misión")
	sq.turn = sq.turns
	_check(_play_clock(sq, AlertDirector.new(sq, 9), 600.0).is_empty(), "no hay alertas en el último turno")
	sq.turn = 3
	sq.finished = true
	_check(_play_clock(sq, AlertDirector.new(sq, 9), 600.0).is_empty(), "las alertas se detienen al terminar la misión")


# ---------------------------------------------------------------- pantalla ----

func _buttons(n: Node, out: Array) -> Array:
	if n is Button:
		out.append(n)
	for c in n.get_children():
		_buttons(c, out)
	return out


func _test_overlay() -> void:
	print("\nPantalla de alerta")
	for idx in 3:
		var s := _state()
		var before := _snapshot(s)
		var ov := AlertOverlay.new()
		ov.setup(AlertDirector.instance(SpaceEvents.by_id("meteor"), 1, false), s)
		add_child(ov)
		await get_tree().process_frame
		await get_tree().process_frame
		var opts := _buttons(ov, []).filter(func(b: Button) -> bool: return not b.disabled)
		if idx == 0:
			_check(opts.size() == 3, "la alerta muestra 3 botones de respuesta")
			_check(ov.mouse_filter == Control.MOUSE_FILTER_STOP, "la alerta bloquea el juego de abajo")
			var big := ov.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.get_theme_font_size("font_size") >= 36)
			_check(big.size() >= 1 and ov._art != null, "tiene un título grande y una escena animada")
		var finished_res := {}
		ov.finished.connect(func(r: Dictionary) -> void: finished_res.merge(r))
		(opts[idx] as Button).pressed.emit()
		var after := _snapshot(s)
		_check(ov.resolved and s.alert_log.size() == 1, "botón %d: registra la decisión" % (idx + 1))
		_check(str(after) != str(before), "botón %d: cambia de verdad el estado de la misión" % (idx + 1))
		_check(_buttons(ov, []).filter(func(b: Button) -> bool: return not b.is_queued_for_deletion() and not b.disabled).size() <= 1, "tras elegir solo queda el botón «Continuar»")
		ov.close()
		await get_tree().create_timer(0.6).timeout
		_check(not finished_res.is_empty() and not is_instance_valid(ov), "botón %d: la alerta se cierra con animación y avisa al juego" % (idx + 1))
	# cuenta regresiva
	var st := _state()
	var ob := _snapshot(st)
	var ovt := AlertOverlay.new()
	ovt.setup(AlertDirector.instance(SpaceEvents.by_id("leak"), 9, false), st)
	add_child(ovt)
	await get_tree().process_frame
	_check(ovt._count.text.contains("AIRE ESCAPANDO") and ovt._count.text.contains(" s"), "se ve la cuenta regresiva: «%s»" % ovt._count.text)
	var left0 := ovt._left
	ovt._process(2.0)
	_check(is_equal_approx(ovt._left, left0 - 2.0), "la cuenta regresiva baja con el tiempo")
	ovt._process(left0 + 1.0)
	_check(ovt.resolved and bool(ovt.result["timed_out"]), "al llegar a cero se ejecuta la consecuencia por no responder")
	_check(st.o2 < float(ob["o2"]) - 15.0 and st.alert_score < 0, "…y esa consecuencia es real (oxígeno %d → %d)" % [ob["o2"], st.o2])
	ovt.queue_free()
	await get_tree().process_frame
	# teclado
	var sk := _state()
	var ovk := AlertOverlay.new()
	ovk.setup(AlertDirector.instance(SpaceEvents.by_id("thermal"), 1, false), sk)
	add_child(ovk)
	await get_tree().process_frame
	var key := InputEventKey.new()
	key.keycode = KEY_2
	key.pressed = true
	ovk._input(key)
	_check(ovk.resolved and str(ovk.result["choice"]) == "Girar la base para dar sombra", "la tecla 2 elige la segunda opción")
	ovk.queue_free()
	await get_tree().process_frame


# -------------------------------------------------------------- integracion ----

func _test_game_integration() -> void:
	print("\nIntegración en la partida")
	MissionManager.current = MissionManager.get_mission("lunar_awakening")
	var g: Control = load("res://scenes/LunarBase.tscn").instantiate()
	g._simulated = true
	add_child(g)
	await get_tree().process_frame
	_check(g._alerts == null, "en pruebas automáticas (simuladas) no salen alertas por sorpresa")
	var guard := 0
	while (g._intro_pending or g._modal_root == null) and guard < 600:   # espera la ventana de presentacion y la cierra
		guard += 1
		await get_tree().process_frame
	g._close_modal()
	var ev := AlertDirector.instance(SpaceEvents.by_id("flare"), 1, false)
	var turn0: int = g.s.turn
	g._show_space_alert(ev)
	await get_tree().process_frame
	_check(g._alert_open and g._alert_ui != null, "la alerta se abre dentro de la misión")
	g._end_turn()
	_check(g.s.turn == turn0 and g._modal_root == null, "mientras hay una alerta no se puede finalizar el turno")
	var exposure0: float = g.s.exposure
	var btns := _buttons(g._alert_ui, []).filter(func(b: Button) -> bool: return not b.disabled)
	(btns[2] as Button).pressed.emit()   # desconectar equipos con la tripulacion expuesta
	g._alert_ui.close()
	await get_tree().create_timer(0.7).timeout
	_check(not g._alert_open and g.s.exposure > exposure0, "al responder, la misión sigue y la radiación subió (%d → %d)" % [exposure0, g.s.exposure])
	g._alerts = AlertDirector.new(g.s, 4)
	_check(g.s.alert_log.size() == 1 and g._extra_text().contains("Alertas: 1"), "la cabecera muestra las alertas atendidas y los puntos")
	g._alerts.next_at = 0.0
	g._alerts.last_at = -999.0
	g.s.turn = 3
	var shown := false
	for i in 400:
		g._process(0.25)
		if g._alert_open:
			shown = true
			break
	_check(shown, "con el generador activo, la alerta aparece sola durante la misión")
	if g._alert_open:
		g._alert_ui.choose(0)
		g._alert_ui.close()
		await get_tree().create_timer(0.7).timeout
	g.s.finished = true
	var count_before: int = g._alerts.count
	for i in 400:
		g._process(0.25)
	_check(not g._alert_open and g._alerts.count == count_before, "al terminar la misión las alertas se detienen")
	g.queue_free()
	await get_tree().process_frame
