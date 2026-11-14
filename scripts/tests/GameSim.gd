extends Node
## Simula partidas completas de 7 dias contra la escena real (OrbitalStation) con distintas
## estrategias y severidades del evento solar. Sirve para comprobar el balance del juego.
## Ejecutar: godot --headless --path <proyecto> res://scenes/GameSim.tscn


func _ready() -> void:
	NASADataManager.simulate_offline = true   # usa solo cache: la simulacion no depende de la red
	print("=== SIMULACION DE PARTIDAS (7 dias) ===")
	print("%-34s | sev | %-8s | día | O2 EN COM BL CM | motivo" % ["Estrategia", "Resultado"])
	for sev in [0, 1, 2, 3]:
		for s in [
			["Pasivo, refuerza blindaje", false, true],
			["Pasivo, ahorra energía", false, false],
			["Hábil, refuerza blindaje", true, true],
			["Hábil, ahorra energía", true, false],
		]:
			await _play(s[0], s[1], s[2], sev)
	get_tree().quit()


func _play(label: String, smart: bool, reinforce: bool, sev: int) -> void:
	var g: Control = load("res://scenes/OrbitalStation.tscn").instantiate()
	g._simulated = true
	add_child(g)
	await get_tree().process_frame
	if not g.event_loaded:
		await g._event_ready
	g.event["is_fallback"] = false
	if g.event.get("record", {}).is_empty():
		g.event["record"] = {"severity": sev, "title": "x", "event_time": 0.0}
	g.event["record"]["severity"] = sev
	var guard := 0
	while not g.game_over and guard < 40:
		guard += 1
		if g._modal_root != null:
			if g.day == g.EVENT_DAY and not g._event_resolved_for_test:
				g._event_resolved_for_test = true
				g._resolve_event(reinforce)
			g._close_modal()
		if smart:
			_smart_actions(g)
		g._end_turn()
		await get_tree().process_frame
	var r: Dictionary = g.res
	print("%-34s |  %d  | %-8s | %d/%d | %02d %02d %02d %02d %02d | %s" % [label, sev, "VICTORIA" if g.outcome == "EXITO" else "DERROTA",
			min(g.day, 7), 7, r["oxigeno"], r["energia"], r["comida"], r["blindaje"], r["comunicacion"],
			"" if g.outcome == "EXITO" else g.outcome.trim_prefix("FALLO: ")])
	g.queue_free()
	await get_tree().process_frame


## Jugador que lee el HUD: repone lo mas bajo y protege la energia.
func _smart_actions(g: Control) -> void:
	while g.ap > 0:
		var r: Dictionary = g.res
		if r["energia"] < 55.0:
			g._action("paneles")
		elif r["blindaje"] < 55.0:
			g._action("blindaje")
		elif r["oxigeno"] <= r["comida"]:
			g._action("aire")
		else:
			g._action("cultivo")
