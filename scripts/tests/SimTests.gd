extends Node
## Pruebas del nucleo de simulacion (sin interfaz ni red): comprueba que no hay una
## estrategia siempre ganadora y que el equilibrio de los 4 sistemas es lo que gana.
## Ejecutar: godot --headless --path <proyecto> res://scenes/SimTests.tscn

var _fail := 0
var _pass := 0


func _ready() -> void:
	Lang.set_language("es", false)   # las pruebas comprueban los textos en espanol
	print("=== PRUEBAS DE SIMULACION: OPERACION REFUGIO LUNAR ===")
	print("%-34s | tier | %-8s | t | VIDA PROT ENER ALIM | exp | causa" % ["Estrategia", "Resultado"])
	var results := {}
	for tier in [1, 2, 3]:
		for s in ["pasivo", "solo_comida", "solo_blindaje", "equilibrado", "ahorro_extremo", "sin_proteger"]:
			var r := _play(s, tier)
			results["%s_%d" % [s, tier]] = r
			var ind: Dictionary = r["ind"]
			print("%-34s |  %d   | %-8s | %d | %4d %4d %4d %4d | %3d | %s" % [s, tier, "VICTORIA" if r["won"] else "DERROTA", r["turn"],
					ind["vida"], ind["proteccion"], ind["energia"], ind["alimentos"], r["exp"], r["reason_id"]])
	print("")
	for tier in [1, 2, 3]:
		_check(results["equilibrado_%d" % tier]["won"], "Equilibrado gana con alerta nivel %d" % tier)
		_check(not results["pasivo_%d" % tier]["won"], "Pasivo pierde con alerta nivel %d" % tier)
		_check(not results["solo_comida_%d" % tier]["won"], "Maximizar solo comida pierde (nivel %d)" % tier)
		_check(not results["solo_blindaje_%d" % tier]["won"], "Maximizar solo blindaje pierde (nivel %d)" % tier)
	_check(not results["sin_proteger_3"]["won"], "Sin proteger pierde ante alerta fuerte (nivel 3)")
	print("\nRESULTADO: %d OK, %d FALLOS" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _check(c: bool, msg: String) -> void:
	if c:
		_pass += 1
		print("  [OK]    " + msg)
	else:
		_fail += 1
		print("  [FALLO] " + msg)


func _play(strategy: String, tier: int) -> Dictionary:
	var s := BaseState.new(false)
	NasaBridge.event = {"is_fallback": false, "record": {"severity": tier, "title": "x", "event_time": 0.0, "class_type": "M"}}
	var guard := 0
	while not s.finished and guard < 12:
		guard += 1
		MissionDirector.start_of_turn(s)
		for card in MissionDirector.cards_for_turn(s):
			MissionDirector.choose(s, card, _pick_option(strategy, card))
		s.step(_plan(strategy, s))
	return {"won": s.won, "turn": mini(s.turn, 9), "ind": s.indicators(), "exp": int(s.exposure), "reason_id": s.reason_id}


func _pick_option(strategy: String, card: Dictionary) -> int:
	var n: int = (card["options"] as Array).size()
	var want := 0
	match strategy:
		"pasivo": want = 1
		"solo_comida": want = 0 if card["id"] in ["led_vs_energy"] else 1
		"solo_blindaje": want = 0 if card["id"] in ["shield_vs_bed"] else 1
		"ahorro_extremo": want = 0 if card["id"] in ["night_power", "maint_vs_lab"] else 1
		"sin_proteger": want = 1 if card["id"] in ["shield_vs_bed"] else 0
		"equilibrado":
			want = {"night_power": 0, "maint_vs_lab": 0, "led_vs_energy": 1, "shield_vs_bed": 0}.get(card["id"], 0)
	want = mini(want, n - 1)
	if not card["options"][want].get("affordable", true):
		for i in n:
			if card["options"][i].get("affordable", true):
				return i
	return want


func _plan(strategy: String, s: BaseState) -> Dictionary:
	var tasks: Array = []
	var led := 1
	match strategy:
		"pasivo":
			led = 1
		"solo_comida":
			led = 2
			tasks = ["tend", "fertilize", "expand_bed"]
		"solo_blindaje":
			led = 0
			tasks = ["build_shield", "build_shelter"]
		"ahorro_extremo":
			led = 0
			tasks = ["tend"]
		"sin_proteger":
			led = 1
			tasks = ["tend", "maintain_ls", "process"]
		"equilibrado":
			led = 2 if s.is_day() else 0
			if s.turn >= 7:
				led = 1
			tasks = ["tend"]
			if s.ls_cond < 70.0:
				tasks.append("maintain_ls")
			if s.is_day():
				tasks.append("process")
			if s.nutrients < 30.0:
				tasks.append("fertilize")
			if s.shield < 66.0 and s.materials >= 30.0 and s.turn <= 5:
				tasks.append("build_shield")
			elif s.shelter < 65.0 and s.materials >= 25.0 and s.turn <= 5:
				tasks.append("build_shelter")
			if s.exposure > 30.0:
				tasks.append("treat")
	# Recorta las tareas que no caben (el jugador no podria confirmarlas).
	var final: Array = []
	for t in tasks:
		var test := final.duplicate()
		test.append(t)
		if s.can_afford(test):
			final.append(t)
	return {"led": led, "tasks": final}
