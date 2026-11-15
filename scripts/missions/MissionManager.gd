extends Node
## MissionManager (autoload): catalogo de misiones, dificultad, desbloqueo en cadena y progreso.
## Una mision se desbloquea cuando la anterior (`requires`) se ha superado. El progreso se guarda
## en JSON (SaveStore). Para añadir una mision: crear otra MissionDef en _build() y, si hace
## falta un guion nuevo de eventos, un script_id en MissionDirector.

signal mission_started(id: String)
signal decision_made(card_id: String, option_index: int, sacrifice: String)
signal mission_finished(id: String, won: bool, stats: Dictionary)

var data: Dictionary = {}
var current: MissionDef
var _missions: Array[MissionDef] = []


func _ready() -> void:
	_build()
	for a in OS.get_cmdline_user_args():   # solo para pruebas: usar otro archivo de guardado
		if a.begins_with("--save="):
			SaveStore.path = "user://" + a.substr(7)
	reload()
	current = _missions[0]


func reload() -> void:
	data = SaveStore.load_data()


func save() -> bool:
	return SaveStore.save_data(data)


# --------------------------------------------------------------- catalogo ----

func all() -> Array[MissionDef]:
	return _missions


func of_tier(tier: int) -> Array[MissionDef]:
	var out: Array[MissionDef] = []
	for m in _missions:
		if m.tier == tier:
			out.append(m)
	return out


func get_mission(id: String) -> MissionDef:
	for m in _missions:
		if m.id == id:
			return m
	return null


func is_completed(id: String) -> bool:
	var rec: Variant = (data["missions"] as Dictionary).get(id, {})
	return rec is Dictionary and bool((rec as Dictionary).get("completed", false))


func is_unlocked(id: String) -> bool:
	var m := get_mission(id)
	if m == null or not m.ready:
		return false
	return m.requires == "" or is_completed(m.requires)


## Texto corto de por que una mision esta bloqueada ("" si esta disponible).
func lock_reason(id: String) -> String:
	var m := get_mission(id)
	if m == null:
		return "Misión desconocida"
	if not m.ready:
		return "Próximamente"
	if is_unlocked(id):
		return ""
	var prev := get_mission(m.requires)
	return "Supera «%s» para desbloquearla" % (prev.title if prev != null else m.requires)


func attempts(id: String) -> int:
	var rec: Variant = (data["missions"] as Dictionary).get(id, {})
	return int((rec as Dictionary).get("attempts", 0)) if rec is Dictionary else 0


func select(id: String) -> bool:
	if not is_unlocked(id):
		return false
	current = get_mission(id)
	return true


# ------------------------------------------------------------------ partida ----

func begin_run() -> void:
	mission_started.emit(current.id)


## Registra el resultado de una partida. `persist=false` (pruebas/simulaciones) no guarda nada.
## Devuelve {won, stats, new_achievements: Array[String], unlocked_missions: Array[String]}.
func finish_run(state: BaseState, persist: bool = true) -> Dictionary:
	var stats := state.run_stats()
	var won := state.won
	var result := {"won": won, "stats": stats, "new_achievements": [] as Array[String], "unlocked_missions": [] as Array[String]}
	if not persist:
		result["new_achievements"] = AchievementManager.evaluate(current.id, won, stats)
		return result
	var before: Array[String] = []
	for m in _missions:
		if is_unlocked(m.id):
			before.append(m.id)
	var missions: Dictionary = data["missions"]
	var rec: Dictionary = missions.get(current.id, {"completed": false, "attempts": 0, "wins": 0})
	rec["attempts"] = int(rec.get("attempts", 0)) + 1
	if won:
		rec["wins"] = int(rec.get("wins", 0)) + 1
		rec["completed"] = true
	missions[current.id] = rec
	var st: Dictionary = data["stats"]
	st["played"] = int(st.get("played", 0)) + 1
	if won:
		st["won"] = int(st.get("won", 0)) + 1
	AchievementManager.last_new.clear()
	mission_finished.emit(current.id, won, stats)   # AchievementManager escucha esta señal y desbloquea
	save()
	result["new_achievements"] = AchievementManager.last_new.duplicate()
	for m in _missions:
		if is_unlocked(m.id) and not (m.id in before):
			(result["unlocked_missions"] as Array[String]).append(m.id)
	return result


# ----------------------------------------------------------- definiciones ----

func _build() -> void:
	var m1 := MissionDef.new()
	m1.id = "lunar_awakening"
	m1.title = "Refugio Lunar: El Despertar"
	m1.place = "Base lunar"
	m1.icon = "🌙"
	m1.difficulty = 1
	m1.summary = "Tutorial: aprende los 4 sistemas de la base y cómo compiten por energía, materiales y horas."
	m1.dilemma_title = "Cuatro sistemas, un solo presupuesto"
	m1.dilemma_text = "Mejorar una parte de la base siempre quita energía, materiales o tiempo a otra. Aprende a repartir."
	m1.protect = "Soporte vital, protección, energía y alimentos"
	m1.sacrifice = "Tiempo, materiales y energía que no podrás usar en otra cosa"
	m1.objectives = PackedStringArray(["Completa los 9 turnos", "Mantén el aire seguro y la tripulación sana", "Supera la alerta solar del turno 6", "Termina con comida y energía de reserva"])
	m1.victory_text = "Los cuatro sistemas quedan en un estado seguro al terminar el turno 9."
	m1.script_id = "awakening"
	_missions.append(m1)

	var m2 := MissionDef.new()
	m2.id = "storm_horizon"
	m2.title = "Tormenta en el Horizonte"
	m2.place = "Base lunar · clima espacial"
	m2.icon = "☀️"
	m2.difficulty = 2
	m2.requires = "lunar_awakening"
	m2.summary = "Una tormenta solar de nivel máximo se acerca. ¿Cuánta energía de los cultivos sacrificas para proteger a la tripulación?"
	m2.dilemma_title = "Cultivos o escudo"
	m2.dilemma_text = "El refugio y el blindaje necesitan energía y materiales justo cuando las plantas piden más luz."
	m2.protect = "La tripulación frente a la radiación"
	m2.sacrifice = "La energía de los cultivos (y parte de la comida)"
	m2.objectives = PackedStringArray(["Prepara blindaje y refugio antes del turno 5", "Supera la tormenta sin pasar de 75 de exposición", "Mantén la salud de la tripulación por encima de 35%", "Llega al turno 9 con aire, energía y comida"])
	m2.victory_text = "Sobrevives a la tormenta y los cuatro sistemas siguen seguros, aunque hayas sacrificado parte de los cultivos."
	m2.script_id = "storm"
	m2.night_from_turn = 6
	m2.alert_turn = 5
	m2.alert_tier_min = 3
	m2.solar_factor = 0.65
	m2.start = {"main": 360.0, "materials": 70.0, "shield": 30.0, "shelter": 20.0, "health": 85.0, "food": 80.0}
	m2.win_extra = {"max_exposure": 75.0, "min_health": 35.0}
	_missions.append(m2)

	var m3 := MissionDef.new()
	m3.id = "lunar_blackout"
	m3.title = "Apagón en el Casquete"
	m3.place = "Casquete polar · poca luz solar"
	m3.icon = "🔦"
	m3.difficulty = 3
	m3.requires = "storm_horizon"
	m3.summary = "Casi no llega luz solar. Decide qué subsistemas apagar y cuáles mantener para llegar al final."
	m3.dilemma_title = "¿Qué apagamos?"
	m3.dilemma_text = "La energía no alcanza para todo: cada subsistema que apagas ahorra batería pero tiene un coste."
	m3.protect = "El soporte vital y la salud de la tripulación"
	m3.sacrifice = "Subsistemas: hogar, control de obras o luces de cultivo"
	m3.objectives = PackedStringArray(["Sobrevive con muy poca generación solar", "Apaga y enciende subsistemas por turnos (Centro de comandos)", "Mantén la salud de la tripulación por encima de 40%", "Llega al turno 9 con energía de reserva"])
	m3.victory_text = "Llegas al turno 9 con el aire seguro, la tripulación sana y energía de reserva."
	m3.script_id = "blackout"
	m3.night_from_turn = 3
	m3.alert_turn = 0
	m3.solar_factor = 0.5
	m3.start = {"main": 520.0, "backup": 400.0, "materials": 80.0, "shield": 45.0, "health": 90.0}
	m3.win_extra = {"min_health": 40.0}
	_missions.append(m3)

	# ----- Nivel INTERMEDIO (independiente del nivel Fácil; en cadena dentro del nivel) -----
	var i1 := MissionDef.new()
	i1.id = "lava_harvest"
	i1.title = "La Cosecha de los Tubos de Lava"
	i1.place = "Tubo de lava · invernadero subterráneo"
	i1.icon = "🌋"
	i1.tier = 2
	i1.difficulty = 1
	i1.summary = "El soporte vital rinde poco: las plantas deben dar el oxígeno y la comida. Alterna luz y oscuridad para ganar energía."
	i1.dilemma_title = "Luz o energía"
	i1.dilemma_text = "Las luces alimentan a las plantas pero gastan baterías. Dos turnos seguidos de luz alta las estresan; tras un turno a oscuras, la luz alta da un impulso de crecimiento."
	i1.protect = "El oxígeno y la comida que dan las plantas"
	i1.sacrifice = "Energía de las baterías y, a ratos, la luz de las plantas"
	i1.objectives = PackedStringArray(["Alterna turnos de luz alta y de oscuridad", "No dejes caer el aire por debajo de 30", "Mantén la salud de la tripulación por encima de 40%", "Llega al turno 9 con comida y energía de reserva"])
	i1.victory_text = "Llegas al turno 9 con el aire seguro, la tripulación sana, comida y energía de reserva."
	i1.script_id = "lava"
	i1.night_from_turn = 5
	i1.alert_turn = 0
	i1.solar_factor = 0.8
	i1.consumption_factor = 1.05
	i1.event_aggression = 0.25
	i1.rules = {"light_cycle": true, "plant_o2": 3.0, "ls_output": 0.55}
	i1.start = {"beds": 4, "main": 450.0}
	i1.win_extra = {"min_health": 40.0}
	_missions.append(i1)

	var i2 := MissionDef.new()
	i2.id = "orbital_shadow"
	i2.title = "Efecto de Sombra Orbital"
	i2.place = "Casquete polar · noche prolongada"
	i2.icon = "🌑"
	i2.tier = 2
	i2.difficulty = 2
	i2.requires = "lava_harvest"
	i2.summary = "Una noche larguísima agota las baterías. No alcanza para calentar la base y transmitir datos a la Tierra a la vez."
	i2.dilemma_title = "Calor o contacto con la Tierra"
	i2.dilemma_text = "La calefacción protege a la tripulación del frío; la transmisión envía los datos científicos. Cada turno con uno encendido gasta energía que no tendrás para el otro."
	i2.protect = "La tripulación (calefacción) y los datos científicos"
	i2.sacrifice = "Calor de la base o turnos de transmisión"
	i2.objectives = PackedStringArray(["Envía datos a la Tierra en al menos 4 turnos", "Mantén la salud de la tripulación por encima de 40%", "Sobrevive a la noche prolongada", "Llega al turno 9 con aire, comida y energía de reserva"])
	i2.victory_text = "Sobrevives a la noche, la tripulación sigue sana y enviaste al menos 4 paquetes de datos a la Tierra."
	i2.script_id = "shadow"
	i2.night_from_turn = 4
	i2.alert_turn = 0
	i2.solar_factor = 1.0
	i2.consumption_factor = 1.05
	i2.event_aggression = 0.35
	i2.rules = {"heat_comms": true}
	i2.start = {"main": 450.0, "backup": 250.0, "health": 90.0, "food": 100.0}
	i2.win_extra = {"min_health": 40.0, "min_data": 4}
	_missions.append(i2)

	var i3 := MissionDef.new()
	i3.id = "thermal_anomaly"
	i3.title = "Anomalía en el Escudo Térmico"
	i3.place = "Base lunar · tormenta solar"
	i3.icon = "🛡"
	i3.tier = 2
	i3.difficulty = 3
	i3.requires = "orbital_shadow"
	i3.summary = "Una fisura se abre en el blindaje justo antes de una tormenta solar. Sellarla cuesta energía del soporte vital y oxígeno de los trajes."
	i3.dilemma_title = "Sellar la fisura o cuidar el aire"
	i3.dilemma_text = "Soldar el blindaje desvía energía del soporte vital y gasta oxígeno de los trajes de EVA. Si no lo sellas, la tormenta pasa por la fisura."
	i3.protect = "La tripulación frente a la radiación (blindaje)"
	i3.sacrifice = "Energía del soporte vital y oxígeno de los trajes"
	i3.objectives = PackedStringArray(["Sella la fisura antes de la tormenta (2 salidas EVA)", "No pases de 75 de exposición a la radiación", "Mantén la salud por encima de 35%", "Llega al turno 9 con aire, comida y energía"])
	i3.victory_text = "Sellas la fisura, resistes la tormenta y el aire de la base sigue siendo seguro."
	i3.script_id = "breach"
	i3.night_from_turn = 5
	i3.alert_turn = 6
	i3.alert_tier_min = 3
	i3.solar_factor = 1.0
	i3.consumption_factor = 1.1
	i3.event_aggression = 0.45
	i3.rules = {"breach": true}
	i3.start = {"main": 600.0, "materials": 90.0, "shield": 60.0, "shelter": 35.0, "health": 90.0, "food": 100.0}
	i3.win_extra = {"max_exposure": 75.0, "min_health": 35.0}
	_missions.append(i3)

	# ----- Nivel AVANZADO (en preparacion) -----
	var m4 := MissionDef.new()
	m4.id = "mars_outpost"
	m4.title = "Base en Marte"
	m4.place = "Marte"
	m4.icon = "🔴"
	m4.tier = 3
	m4.difficulty = 3
	m4.ready = false
	m4.summary = "En preparación. Reutilizará los cuatro sistemas con desafíos nuevos."
	_missions.append(m4)
