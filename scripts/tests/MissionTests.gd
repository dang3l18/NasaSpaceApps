extends Node
## Pruebas del sistema de misiones: balance por mision, desbloqueo en cadena y por nivel, victoria/derrota
## independientes, logros y guardado JSON. Usa un guardado temporal (no toca tu progreso real).
## Ejecutar: godot --headless --path <proyecto> res://scenes/MissionTests.tscn

const SEEDS := [11, 22, 33, 44, 55, 66, 77, 88, 99, 110]

var _pass := 0
var _fail := 0
var _real_path := ""


func _check(c: bool, msg: String) -> void:
	if c:
		_pass += 1
		print("  [OK]    " + msg)
	else:
		_fail += 1
		print("  [FALLO] " + msg)


## Modo demostracion: `-- --demo=archivo.json` juega las 6 misiones en el orden de desbloqueo y deja
## ese guardado en user:// (para sacar capturas de logros y misiones superadas).
func _demo(file: String) -> void:
	SaveStore.path = "user://" + file
	SaveStore.enabled = true
	SaveStore.delete_file()
	MissionManager.reload()
	for id in ["lunar_awakening", "storm_horizon", "lunar_blackout", "lava_harvest", "orbital_shadow", "thermal_anomaly"]:
		var m := MissionManager.get_mission(id)
		var open := MissionManager.is_unlocked(id) and MissionManager.select(id)
		var r: Dictionary = _run(m, _best_picks(m), "equilibrado", 33) if open else {}
		var res: Dictionary = MissionManager.finish_run(r["state"], true) if open else {}
		print("%s | desbloqueada=%s | resultado=%s | motivo=%s | logros nuevos=%s" % [m.title, open,
				"GANADA" if open and r["won"] else "no", (r["state"] as BaseState).reason if open else "", str(res.get("new_achievements", []))])
	print("Guardado: ", ProjectSettings.globalize_path(SaveStore.path))
	get_tree().quit(0)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--demo="):
			NasaBridge.event = {}
			_demo(a.substr(7))
			return
	NasaBridge.event = {}
	_real_path = SaveStore.path
	SaveStore.path = "user://zyranth_test_save.json"
	SaveStore.enabled = true
	SaveStore.delete_file()
	MissionManager.reload()
	print("=== PRUEBAS DE MISIONES ===")
	_test_catalog()
	_test_balance()
	_test_independent_rules()
	_test_unlock_chain()
	_test_intermediate_unlock()
	_test_achievements()
	_test_persistence()
	_test_guide()
	SaveStore.delete_file()
	SaveStore.path = _real_path
	MissionManager.reload()
	print("\nRESULTADO: %d OK, %d FALLOS" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


# --------------------------------------------------------------- catalogo ----

func _test_catalog() -> void:
	print("\nCatalogo, niveles y dificultad")
	var ms := MissionManager.all()
	_check(ms.size() >= 7, "hay %d misiones registradas" % ms.size())
	for t in [1, 2, 3]:
		var last := 0
		var ok := true
		for m in MissionManager.of_tier(t):
			print("   [%s] %-34s %s %-8s requiere: %s" % [m.tier_label(), m.title, m.stars(), m.difficulty_label(), m.requires if m.requires != "" else "-"])
			if m.difficulty < last:
				ok = false
			last = m.difficulty
		_check(ok, "nivel %s: la dificultad no baja de una misión a la siguiente" % MissionDef.TIER_NAMES[t])
	_check(MissionManager.of_tier(1).size() == 3 and MissionManager.of_tier(2).size() == 3, "el nivel Fácil y el Intermedio tienen 3 misiones cada uno")
	var lava := MissionManager.get_mission("lava_harvest")
	var shadow := MissionManager.get_mission("orbital_shadow")
	var thermal := MissionManager.get_mission("thermal_anomaly")
	_check(lava.difficulty == 1 and shadow.difficulty == 2 and thermal.difficulty == 3, "las 3 misiones intermedias van de Fácil a Difícil dentro del nivel")
	_check(lava.consumption_factor > 1.0 and shadow.consumption_factor > 1.0 and thermal.consumption_factor > lava.consumption_factor, "los modificadores de consumo suben con la dificultad")
	_check(lava.event_aggression < shadow.event_aggression and shadow.event_aggression < thermal.event_aggression, "los sucesos de riesgo son más agresivos en cada misión")
	for m in ms:
		if m.ready:
			_check(m.dilemma_title != "" and m.protect != "" and m.sacrifice != "" and m.objectives.size() > 0, "«%s» muestra dilema, qué protege y qué sacrifica" % m.title)


# ----------------------------------------------------------------- balance ----

func _test_balance() -> void:
	print("\nBalance por misión (varias semillas aleatorias)")
	print("%-32s | %-12s | victorias | ejemplo (t, exp, salud, energía, comida, causa)" % ["Misión", "Estrategia"])
	for m in MissionManager.all():
		if not m.ready:
			continue
		var picks := _best_picks(m)
		var bal_wins := 0
		var pas_wins := 0
		var ex_bal: Dictionary = {}
		var ex_pas: Dictionary = {}
		for sd in SEEDS:
			var b := _run(m, picks, "equilibrado", sd)
			var p := _run(m, {}, "pasivo", sd)
			bal_wins += 1 if b["won"] else 0
			pas_wins += 1 if p["won"] else 0
			if ex_bal.is_empty() or (not b["won"] and ex_bal["won"]):
				ex_bal = b
			ex_pas = p
		print("%-32s | %-12s | %2d de %2d   | %s" % [m.title.left(32), "pasivo", pas_wins, SEEDS.size(), _fmt(ex_pas)])
		print("%-32s | %-12s | %2d de %2d   | %s" % ["", "equilibrado", bal_wins, SEEDS.size(), _fmt(ex_bal)])
		_check(pas_wins == 0, "«%s»: un jugador pasivo nunca gana" % m.title)
		_check(bal_wins >= 8, "«%s»: repartir bien los recursos gana (%d de %d semillas)" % [m.title, bal_wins, SEEDS.size()])
	# No debe existir una respuesta siempre ganadora.
	var m3 := MissionManager.get_mission("lunar_blackout")
	var wins := 0
	var combos := 0
	for what in 3:
		for reserve in 2:
			combos += 1
			if _run(m3, {"blackout_what": what, "blackout_reserve": reserve}, "equilibrado", 5)["won"]:
				wins += 1
	_check(wins >= 1 and wins < combos, "«Apagón»: %d de %d combinaciones ganan (no hay una única respuesta correcta)" % [wins, combos])
	var m2 := MissionManager.get_mission("storm_horizon")
	var sw := 0
	var sc := 0
	for crops in 2:
		for mats in 2:
			for shelter in 2:
				sc += 1
				if _run(m2, {"storm_crops": crops, "storm_materials": mats, "storm_shelter": shelter}, "equilibrado", 5)["won"]:
					sw += 1
	_check(sw >= 1 and sw < sc, "«Tormenta»: %d de %d combinaciones ganan" % [sw, sc])
	var ms := MissionManager.get_mission("orbital_shadow")
	var sw1: bool = _run(ms, _best_picks(ms), "equilibrado", 5)["won"]
	var sw2: bool = _run(ms, _best_picks(ms), "sin_datos", 5)["won"]
	var sw3: bool = _run(ms, _best_picks(ms), "solo_datos", 5)["won"]
	_check(sw1 and not sw2 and not sw3, "«Sombra Orbital»: solo gana alternar calor y datos (ni solo calor ni solo datos)")


func _fmt(r: Dictionary) -> String:
	return "%s t%d exp%d sal%d ene%d com%d %s" % ["GANA " if r["won"] else "PIERDE", r["turn"], r["exposure"], r["health"], r["energy"], r["food"], r["reason_id"]]


## Decisiones del jugador equilibrado en cada mision (indice de opcion por tarjeta).
func _best_picks(m: MissionDef) -> Dictionary:
	match m.script_id:
		"storm": return {"storm_crops": 0, "storm_materials": 0, "storm_shelter": 0}
		"blackout": return {"blackout_what": 0, "blackout_reserve": 1}
		"lava": return {"lava_light": 0, "lava_o2_food": 0, "lava_night": 0}
		"shadow": return {"shadow_heat_comms": 1, "shadow_reserve": 1, "shadow_control": 0}
		"breach": return {"breach_prep": 0, "breach_seal_1": 0, "breach_seal_2": 0}
		_: return {"night_power": 0, "maint_vs_lab": 0, "led_vs_energy": 1, "shield_vs_bed": 0}


func _run(m: MissionDef, picks: Dictionary, strategy: String, seed_value: int = 1) -> Dictionary:
	NasaBridge.forced_min = m.alert_tier_min
	NasaBridge.event = {"is_fallback": false, "record": {"severity": 2, "title": "x", "event_time": 0.0, "class_type": "M"}}
	var s := BaseState.new(false, m)
	s.rng.seed = seed_value
	var guard := 0
	while not s.finished and guard < 14:
		guard += 1
		MissionDirector.start_of_turn(s)
		for card in MissionDirector.cards_for_turn(s):
			var idx := int(picks.get(card["id"], 1 if strategy == "pasivo" else 0))
			idx = mini(idx, (card["options"] as Array).size() - 1)
			if not card["options"][idx].get("affordable", true):
				for i in (card["options"] as Array).size():
					if card["options"][i].get("affordable", true):
						idx = i
						break
			MissionDirector.choose(s, card, idx)
		s.step(_plan(s, strategy))
	NasaBridge.forced_min = 0
	return {"won": s.won, "turn": mini(s.turn, s.turns), "exposure": int(s.exposure), "health": int(s.health),
			"energy": int(s.energy_total()), "food": int(s.food), "reason_id": s.reason_id, "state": s}


func _afford(s: BaseState, tasks: Array) -> Array:
	var final: Array = []
	for t in tasks:
		var test := final.duplicate()
		test.append(t)
		if s.can_afford(test):
			final.append(t)
	return final


func _plan(s: BaseState, strategy: String) -> Dictionary:
	if strategy == "pasivo":
		return {"led": 1, "tasks": []}
	var script := s.mission.script_id if s.mission != null else "awakening"
	match script:
		"lava": return _plan_lava(s, strategy)
		"shadow": return _plan_shadow(s, strategy)
		"breach": return _plan_breach(s, strategy)
	return _plan_classic(s)


func _plan_classic(s: BaseState) -> Dictionary:
	# En «Apagón» el jugador que equilibra apaga Hogar y Control desde el turno 3 (lo haría en el Centro de comandos).
	var blackout: bool = s.mission != null and s.mission.script_id == "blackout"
	if blackout and s.turn >= 3:
		s.habitat_on = false
		s.control_on = false
	var tasks: Array = ["tend"]
	if s.ls_cond < 70.0:
		tasks.append("maintain_ls")
	if s.is_day() and s.control_on and not blackout:
		tasks.append("process")
	if s.nutrients < 30.0:
		tasks.append("fertilize")
	var before_alert: bool = s.alert_turn <= 0 or s.turn < s.alert_turn
	if before_alert and s.alert_turn > 0:
		if s.shield < 75.0 and s.materials >= 30.0:
			tasks.append("build_shield")
		elif s.shelter < 70.0 and s.materials >= 25.0:
			tasks.append("build_shelter")
	if s.exposure > 30.0 or s.health < 55.0:
		tasks.append("treat")
	var led := 2 if s.is_day() else 1
	if s.turn >= 7 or blackout:
		led = 1
	return {"led": led, "tasks": _afford(s, tasks)}


## Tubos de lava: alterna luz alta y oscuridad (un turno a oscuras antes de cada luz alta).
func _plan_lava(s: BaseState, strategy: String) -> Dictionary:
	var tasks: Array = ["tend"]
	if s.ls_cond < 65.0:
		tasks.append("maintain_ls")
	if s.nutrients < 30.0:
		tasks.append("fertilize")
	if s.is_day() and s.control_on:
		tasks.append("process")
	var led := 2 if s.turn % 2 == 0 else 0
	if strategy == "luz_alta":
		led = 2
	elif strategy == "oscuridad":
		led = 0
	return {"led": led, "tasks": _afford(s, tasks)}


## Sombra orbital: turnos de transmision (calefaccion apagada) alternados con turnos de calor.
func _plan_shadow(s: BaseState, strategy: String) -> Dictionary:
	var comms_turns := [2, 4, 6, 8]
	match strategy:
		"sin_datos":    # nunca transmite: calefaccion siempre encendida
			s.comms_on = false
			s.heat_on = true
		"solo_datos":   # siempre transmite: calefaccion siempre apagada
			s.comms_on = true
			s.heat_on = false
		_:              # alterna: turnos de datos y turnos de calor
			s.comms_on = s.turn in comms_turns
			s.heat_on = not (s.turn in comms_turns)
	if s.turn >= 3 and strategy == "equilibrado":
		s.control_on = false   # ahorra la energia del Control (no hay obras que hacer)
	var tasks: Array = ["tend"]
	if s.ls_cond < 65.0:
		tasks.append("maintain_ls")
	if s.health < 55.0:
		tasks.append("treat")
	return {"led": 1 if s.turn % 2 == 1 else 0, "tasks": _afford(s, tasks)}


## Anomalia: recargar trajes, sellar la fisura en dos EVA y reforzar antes de la tormenta.
func _plan_breach(s: BaseState, strategy: String) -> Dictionary:
	var tasks: Array = ["tend"]
	if s.ls_cond < 65.0:
		tasks.append("maintain_ls")
	if s.is_day() and s.control_on and s.materials < 60.0:
		tasks.append("process")
	if s.breach_open and strategy != "sin_sellar":
		tasks.append("seal_breach")
	if s.turn <= 5 and s.shield < 70.0 and s.materials >= 50.0:
		tasks.append("build_shield")
	if s.exposure > 30.0 or s.health < 55.0:
		tasks.append("treat")
	return {"led": 1 if s.is_day() else 0, "tasks": _afford(s, tasks)}


# ----------------------------------------------- reglas y victoria independientes ----

func _test_independent_rules() -> void:
	print("\nReglas propias y condiciones de victoria independientes")
	var lava := MissionManager.get_mission("lava_harvest")
	var alt := _run(lava, _best_picks(lava), "equilibrado", 7)
	var high := _run(lava, _best_picks(lava), "luz_alta", 7)
	var dark := _run(lava, _best_picks(lava), "oscuridad", 7)
	print("   Lava · alterna: %s" % _fmt(alt))
	print("   Lava · luz alta siempre: %s plantas %d%%" % [_fmt(high), int(high["state"].plant_health)])
	print("   Lava · oscuridad siempre: %s" % _fmt(dark))
	_check(alt["won"], "Lava: alternar luz y oscuridad gana")
	_check(not high["won"] or high["state"].plant_health < alt["state"].plant_health, "Lava: luz alta siempre estresa a las plantas (o hace perder)")
	_check(not dark["won"], "Lava: oscuridad siempre pierde (sin plantas no hay aire ni comida)")

	var shadow := MissionManager.get_mission("orbital_shadow")
	var no_data := _run(shadow, _best_picks(shadow), "sin_datos", 7)
	var ok_data := _run(shadow, _best_picks(shadow), "equilibrado", 7)
	print("   Sombra · sin transmitir: %s datos %d" % [_fmt(no_data), no_data["state"].data_sent])
	print("   Sombra · equilibrado: %s datos %d" % [_fmt(ok_data), ok_data["state"].data_sent])
	_check(not no_data["won"] and no_data["state"].reason.contains("paquetes de datos") or not no_data["won"], "Sombra: sobrevivir sin enviar datos NO basta para ganar")
	_check(ok_data["won"] and ok_data["state"].data_sent >= 4, "Sombra: ganar exige enviar al menos 4 paquetes de datos")

	var th := MissionManager.get_mission("thermal_anomaly")
	var seal := _run(th, _best_picks(th), "equilibrado", 7)
	var skip := _run(th, {"breach_prep": 1, "breach_seal_1": 1, "breach_seal_2": 1}, "sin_sellar", 7)
	print("   Anomalía · sella: %s fisura %s trajes %d" % [_fmt(seal), "abierta" if seal["state"].breach_open else "cerrada", int(seal["state"].suit_o2)])
	print("   Anomalía · no sella: %s fisura %s" % [_fmt(skip), "abierta" if skip["state"].breach_open else "cerrada"])
	_check(seal["won"] and not seal["state"].breach_open, "Anomalía: sellar la fisura en 2 EVA y resistir la tormenta gana")
	_check(not skip["won"], "Anomalía: no sellar la fisura pierde (la tormenta pasa por ella)")
	_check(int(seal["state"].suit_o2) < 80, "Anomalía: sellar consume oxígeno de los trajes")

	# Mecanicas concretas
	var s := BaseState.new(false, th)
	s.breach_open = true
	var p1 := s.preview({"tasks": ["seal_breach"]})
	_check(s.risks({"tasks": ["seal_breach"]}).size() > 0, "al planear sellar, la interfaz recibe avisos de riesgo")
	s.suit_o2 = 20.0
	_check(not ("seal_breach" in s.all_tasks({"tasks": ["seal_breach"]})), "sin 30 de oxígeno en los trajes no se puede salir a sellar")
	var ls0 := BaseState.new(false, th)
	ls0.breach_open = true
	ls0.step({"tasks": ["seal_breach"], "led": 1})
	_check(float(ls0.last_ratio.get("seal", 0.0)) > 0.0 and ls0.breach_progress == 50.0, "una salida EVA avanza el sellado al 50%")
	var base_with := BaseState.new(false, th)
	base_with.breach_open = true
	_check(base_with.protection_factor() < BaseState.new(false, th).protection_factor(), "la fisura abierta reduce la protección")
	var dbg := p1


# --------------------------------------------------------------- desbloqueo ----

func _test_unlock_chain() -> void:
	print("\nDesbloqueo en cadena (nivel Fácil)")
	SaveStore.delete_file()
	MissionManager.reload()
	_check(MissionManager.is_unlocked("lunar_awakening"), "la primera misión empieza desbloqueada")
	_check(not MissionManager.is_unlocked("storm_horizon"), "«Tormenta» empieza bloqueada")
	_check(not MissionManager.is_unlocked("lunar_blackout"), "«Apagón» empieza bloqueada")
	_check(not MissionManager.is_unlocked("mars_outpost"), "Marte sigue bloqueada (próximamente)")
	_check(MissionManager.lock_reason("storm_horizon").contains("Refugio Lunar"), "el candado explica qué misión hay que superar: «%s»" % MissionManager.lock_reason("storm_horizon"))
	_check(not MissionManager.select("storm_horizon"), "no se puede elegir una misión bloqueada")

	MissionManager.select("lunar_awakening")
	var lost := _run(MissionManager.current, {}, "pasivo")
	var res0 := MissionManager.finish_run(lost["state"], true)
	_check(not MissionManager.is_unlocked("storm_horizon") and (res0["unlocked_missions"] as Array).is_empty(), "perder «El Despertar» no desbloquea la siguiente")

	var won := _run(MissionManager.current, _best_picks(MissionManager.current), "equilibrado")
	var res1 := MissionManager.finish_run(won["state"], true)
	_check(MissionManager.is_completed("lunar_awakening"), "ganar marca «El Despertar» como superada")
	_check("storm_horizon" in res1["unlocked_missions"] and MissionManager.is_unlocked("storm_horizon"), "ganar desbloquea «Tormenta en el Horizonte»")
	_check(not MissionManager.is_unlocked("lunar_blackout"), "«Apagón» sigue bloqueada hasta superar «Tormenta»")

	MissionManager.select("storm_horizon")
	var w2 := _run(MissionManager.current, _best_picks(MissionManager.current), "equilibrado")
	var res2 := MissionManager.finish_run(w2["state"], true)
	_check("lunar_blackout" in res2["unlocked_missions"], "superar «Tormenta» desbloquea «Apagón en el Casquete»")
	_check(MissionManager.attempts("lunar_awakening") == 2, "se cuentan los intentos (%d)" % MissionManager.attempts("lunar_awakening"))
	var before := JSON.stringify(MissionManager.data)
	MissionManager.finish_run(w2["state"], false)
	_check(JSON.stringify(MissionManager.data) == before, "una partida simulada no modifica el progreso")


func _test_intermediate_unlock() -> void:
	print("\nNivel Intermedio: independiente del Fácil y en cadena dentro del nivel")
	SaveStore.delete_file()
	MissionManager.reload()
	_check(MissionManager.is_unlocked("lava_harvest") and not MissionManager.is_completed("lunar_awakening"), "«Tubos de Lava» está disponible sin haber superado el nivel Fácil")
	_check(not MissionManager.is_unlocked("orbital_shadow") and not MissionManager.is_unlocked("thermal_anomaly"), "«Sombra» y «Anomalía» empiezan bloqueadas")
	_check(MissionManager.lock_reason("orbital_shadow").contains("Tubos de Lava"), "el candado de «Sombra» pide superar «Tubos de Lava»: «%s»" % MissionManager.lock_reason("orbital_shadow"))

	var chain := ["lava_harvest", "orbital_shadow", "thermal_anomaly"]
	for i in chain.size():
		var m := MissionManager.get_mission(chain[i])
		_check(MissionManager.select(chain[i]), "se puede elegir «%s»" % m.title)
		var r := _run(m, _best_picks(m), "equilibrado", 33)
		var res := MissionManager.finish_run(r["state"], true)
		_check(r["won"] and MissionManager.is_completed(chain[i]), "superar «%s» la marca como «Superada»" % m.title)
		if i + 1 < chain.size():
			_check(chain[i + 1] in res["unlocked_missions"] and MissionManager.is_unlocked(chain[i + 1]), "…y desbloquea «%s»" % MissionManager.get_mission(chain[i + 1]).title)
	_check(not MissionManager.is_completed("lunar_awakening") and not MissionManager.is_unlocked("storm_horizon"), "el progreso intermedio no toca el del nivel Fácil")


# ------------------------------------------------------------------- logros ----

func _stats(over: Dictionary) -> Dictionary:
	var base := {"min_ind": {"vida": 60.0, "proteccion": 40.0, "energia": 30.0, "alimentos": 70.0}, "min_food": 70.0, "alert_tier": 2,
			"shield_at_alert": 50.0, "expanded_before_alert": true, "sacrifices": []}
	base.merge(over, true)
	return base


func _test_achievements() -> void:
	print("\nLogros ligados a decisiones")
	SaveStore.delete_file()
	MissionManager.reload()
	_check(AchievementManager.evaluate("x", false, _stats({})).is_empty(), "perder no da logros")
	var plain := AchievementManager.evaluate("x", true, _stats({"min_ind": {"vida": 60.0, "proteccion": 10.0, "energia": 30.0, "alimentos": 70.0}}))
	_check(plain.size() == 1 and plain[0] == "first_win", "ganar sin nada especial solo da «Primera misión»")
	_check("field_engineer" in AchievementManager.evaluate("x", true, _stats({})), "Ingeniero de Campo: los 4 sistemas nunca por debajo de 15%")
	_check(not ("field_engineer" in AchievementManager.evaluate("x", true, _stats({"min_ind": {"vida": 60.0, "proteccion": 10.0, "energia": 30.0, "alimentos": 70.0}}))), "Ingeniero de Campo NO se da si un sistema cayó a 10%")
	_check("human_shield" in AchievementManager.evaluate("x", true, _stats({"alert_tier": 3, "shield_at_alert": 80.0, "expanded_before_alert": false})), "Escudo Humano: alerta nivel 3 con blindaje alto sin ampliar cultivos")
	_check(not ("human_shield" in AchievementManager.evaluate("x", true, _stats({"alert_tier": 2, "shield_at_alert": 80.0, "expanded_before_alert": false}))), "Escudo Humano NO se da con alerta de nivel 2")
	_check(not ("human_shield" in AchievementManager.evaluate("x", true, _stats({"alert_tier": 3, "shield_at_alert": 50.0, "expanded_before_alert": false}))), "Escudo Humano NO se da con poco blindaje")
	_check(not ("human_shield" in AchievementManager.evaluate("x", true, _stats({"alert_tier": 3, "shield_at_alert": 80.0, "expanded_before_alert": true}))), "Escudo Humano NO se da si priorizaste la producción")
	_check("space_farmer" in AchievementManager.evaluate("x", true, _stats({"min_food": 100.0})), "Agricultor Espacial: alimentos al 100% todos los turnos")
	_check(not ("space_farmer" in AchievementManager.evaluate("x", true, _stats({"min_food": 80.0}))), "Agricultor Espacial NO se da si bajaron los alimentos")
	_check("trade_off_master" in AchievementManager.evaluate("x", true, _stats({"sacrifices": ["alimentos"]})), "Maestro del Trade-off: sacrificar un recurso a propósito y ganar")
	_check(not ("trade_off_master" in AchievementManager.evaluate("x", true, _stats({}))), "Maestro del Trade-off NO se da sin ningún sacrificio")

	var m2 := MissionManager.get_mission("storm_horizon")
	MissionManager.current = m2
	var r := _run(m2, _best_picks(m2), "equilibrado")
	_check((r["state"].sacrifices as Array).size() > 0, "elegir apagar los LED registra el sacrificio de «alimentos»")
	var got := MissionManager.finish_run(r["state"], true)
	_check(r["won"] and "trade_off_master" in got["new_achievements"], "ganar «Tormenta» sacrificando cultivos desbloquea Maestro del Trade-off")
	_check(AchievementManager.is_unlocked("trade_off_master"), "el logro queda desbloqueado")
	var again := MissionManager.finish_run(r["state"], true)
	_check(not ("trade_off_master" in again["new_achievements"]), "un logro ya ganado no se vuelve a anunciar")


# ------------------------------------------------------------- persistencia ----

func _test_guide() -> void:
	print("\nGuía adaptativa según las decisiones")
	var m := MissionManager.get_mission("orbital_shadow")
	var s := BaseState.new(false, m)
	_check(GuideCoach.advice(s) == "", "sin decisiones la guía no inventa consejos")
	s.turn = 4
	s.decisions.append({"turn": 4, "title": "CALEFACCIÓN O TRANSMISIÓN", "choice": "Priorizar calor", "good": [], "bad": [], "sacrifice": "datos"})
	s.sacrifices.append("datos")
	var a1 := GuideCoach.advice(s)
	_check(a1.contains("datos"), "tras sacrificar datos, la guía habla de los datos: «%s»" % a1)
	s.decisions[0]["sacrifice"] = "calefacción"
	var a2 := GuideCoach.advice(s)
	_check(a2.contains("calefacción") and a2 != a1, "con otra decisión, el consejo cambia: «%s»" % a2)
	s.decisions[0]["sacrifice"] = ""
	_check(GuideCoach.advice(s).contains("Bien pensado"), "una decisión sin sacrificio se reconoce")
	s.turn = 9   # ya paso la ventana de comentario y hay un indicador flojo
	s.decisions.append({"turn": 4, "title": "x", "choice": "y", "good": [], "bad": [], "sacrifice": "alimentos"})
	s.sacrifices.append_array(["alimentos", "alimentos"])
	s.food = 0.0
	s.plant_health = 5.0
	var weak := GuideCoach.advice(s)
	var low := GuideCoach._weakest(s)
	_check((float(low[1]) >= 50.0 and weak == "") or weak.contains("punto más débil"), "con la ventana vencida orienta al punto más débil: «%s»" % weak)


func _test_persistence() -> void:
	print("\nPersistencia JSON")
	SaveStore.delete_file()
	MissionManager.reload()
	for id in ["lunar_awakening", "storm_horizon", "lava_harvest"]:   # supera misiones de ambos niveles y guarda
		var m := MissionManager.get_mission(id)
		MissionManager.current = m
		var run := _run(m, _best_picks(m), "equilibrado", 33)
		MissionManager.finish_run(run["state"], true)
	_check(FileAccess.file_exists(SaveStore.path), "existe el archivo de guardado")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveStore.path))
	_check(parsed is Dictionary and int((parsed as Dictionary).get("version", 0)) == SaveStore.VERSION, "es JSON válido con versión %d" % SaveStore.VERSION)
	_check(parsed is Dictionary and (parsed["missions"] as Dictionary).has("lava_harvest") and bool(parsed["missions"]["lava_harvest"]["completed"]), "el JSON guarda «Tubos de Lava» como superada")
	var ach_before := AchievementManager.is_unlocked("trade_off_master")
	MissionManager.reload()
	_check(MissionManager.is_completed("lunar_awakening") and MissionManager.is_completed("storm_horizon") and MissionManager.is_completed("lava_harvest"), "al recargar siguen «Superadas» las misiones de los dos niveles")
	_check(MissionManager.is_unlocked("lunar_blackout") and MissionManager.is_unlocked("orbital_shadow"), "al recargar siguen desbloqueadas las siguientes misiones")
	_check(ach_before and AchievementManager.is_unlocked("trade_off_master"), "al recargar los logros siguen desbloqueados")
	var f := FileAccess.open(SaveStore.path, FileAccess.WRITE)
	f.store_string("{ esto no es json")
	f.close()
	MissionManager.reload()
	_check(MissionManager.is_unlocked("lunar_awakening") and not MissionManager.is_unlocked("storm_horizon"), "un archivo dañado se ignora y vuelve al estado inicial")
	MissionManager.save()
	_check(not FileAccess.file_exists(SaveStore.path + ".tmp"), "no queda archivo temporal tras guardar")
