extends Node
## Juega la mision COMPLETA a traves de la interfaz real (LunarBase): pulsa los botones de los
## modulos, las tarjetas de decision, los informes y la pantalla final. Sin red (solo cache).
## Ejecutar: godot --headless --path <proyecto> res://scenes/UIPlaythrough.tscn

var _pass := 0
var _fail := 0


func _ready() -> void:
	NASADataManager.simulate_offline = true
	print("=== PARTIDA COMPLETA POR LA INTERFAZ ===")
	for case in [["equilibrado", "lunar_awakening"], ["pasivo", "lunar_awakening"], ["lava_alterna", "lava_harvest"],
			["pasivo", "lava_harvest"], ["pasivo", "orbital_shadow"], ["pasivo", "thermal_anomaly"]]:
		await _play(case[0], case[1])
	print("\nRESULTADO: %d OK, %d FALLOS" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _check(c: bool, msg: String) -> void:
	if c:
		_pass += 1
		print("  [OK]    " + msg)
	else:
		_fail += 1
		print("  [FALLO] " + msg)


func _buttons(n: Node, out: Array) -> Array:
	if n is Button:
		out.append(n)
	for c in n.get_children():
		_buttons(c, out)
	return out


func _play(strat: String, mission_id: String) -> void:
	print("\n-- %s · %s --" % [mission_id, strat])
	MissionManager.current = MissionManager.get_mission(mission_id)
	var g: Control = load("res://scenes/LunarBase.tscn").instantiate()
	g._simulated = true
	add_child(g)
	await get_tree().process_frame
	var modals_seen := 0
	var turns_ended := 0
	var guard := 0
	while guard < 200:
		guard += 1
		await get_tree().process_frame
		if g._modal_root != null:
			modals_seen += 1
			var bs := _buttons(g._modal_root, [])
			var toggles := bs.filter(func(b: Button) -> bool: return b.toggle_mode and not b.disabled)
			if toggles.size() > 0:
				var want: int = int({2: 0, 3: 0, 4: 1, 5: 0}.get(g.s.turn, 0)) if strat == "equilibrado" else (0 if strat == "lava_alterna" else 1)
				(toggles[mini(want, toggles.size() - 1)] as Button).pressed.emit()
			var last: Button = bs[bs.size() - 1]
			if g.s.finished and bs.size() >= 3:
				break   # pantalla final: sus botones son "Jugar de nuevo / Datos / Menu"
			last.pressed.emit()
			await get_tree().process_frame
			continue
		if g.s.finished:
			continue
		_plan_ui(g, strat)
		g._end_turn()
		turns_ended += 1
	var s: BaseState = g.s
	_check(s.finished, "la misión termina (%s)" % (s.reason if s.finished else "sin terminar"))
	_check(modals_seen >= 10, "se mostraron tarjetas, alertas e informes (%d ventanas)" % modals_seen)
	if strat == "equilibrado":
		_check(s.won, "la estrategia equilibrada gana jugando por la interfaz")
		_check(s.decisions.size() == 4, "se registraron las 4 decisiones (%d)" % s.decisions.size())
	elif strat == "lava_alterna":
		_check(s.won, "alternar luz y oscuridad gana «Tubos de Lava» por la interfaz")
		_check(s.decisions.size() == 3, "se registraron las 3 decisiones de la misión (%d)" % s.decisions.size())
	else:
		_check(not s.won, "la estrategia pasiva pierde por la interfaz")
	var end_texts := ""
	for l in g.find_children("*", "Label", true, false):
		end_texts += (l as Label).text + " "
	_check("Tus decisiones importantes" in end_texts, "la pantalla final explica las decisiones")
	g.queue_free()
	await get_tree().process_frame


func _plan_ui(g: Control, strat: String) -> void:
	var s: BaseState = g.s
	if strat == "pasivo":
		return
	if strat == "lava_alterna":
		g._set_led(2 if s.turn % 2 == 0 else 0)
		for tid in ["tend", "maintain_ls", "fertilize"]:
			var need: bool = tid == "tend" or (tid == "maintain_ls" and s.ls_cond < 65.0) or (tid == "fertilize" and s.nutrients < 30.0)
			var test: Array = (g.plan["tasks"] as Array).duplicate()
			test.append(tid)
			if need and not (tid in s.forced_tasks) and s.can_afford(test):
				g._toggle_task(tid)
		return
	var want: Array = ["tend"]
	if s.ls_cond < 70.0: want.append("maintain_ls")
	if s.is_day(): want.append("process")
	if s.nutrients < 30.0: want.append("fertilize")
	if s.shield < 66.0 and s.materials >= 30.0 and s.turn <= 5: want.append("build_shield")
	elif s.shelter < 65.0 and s.materials >= 25.0 and s.turn <= 5: want.append("build_shelter")
	if s.exposure > 30.0: want.append("treat")
	g._set_led(2 if (s.is_day() and s.turn <= 3) else (1 if s.turn >= 7 else 0))
	for t in want:
		var test: Array = (g.plan["tasks"] as Array).duplicate()
		test.append(t)
		if t in s.forced_tasks:
			continue
		if s.can_afford(test):
			g._toggle_task(t)
