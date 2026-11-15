class_name BaseState
extends RefCounted
## Modelo de la base lunar: 4 sistemas interdependientes que compiten por
## ENERGIA, MATERIALES y HORAS DE TRABAJO. Logica pura (sin interfaz) para poder probarla.
## Todos los numeros salen de SimConfig (parametros de simulacion, no datos de NASA).

const TASKS := {
	"maintain_ls": {"name": "Mantener soporte vital", "icon": "🛠", "hours": 4, "mat": 5, "energy": 0},
	"tend": {"name": "Cuidar las plantas", "icon": "🌱", "hours": 3, "mat": 0, "energy": 0},
	"research": {"name": "Investigar", "icon": "🔬", "hours": 4, "mat": 0, "energy": 50},
	"build_shield": {"name": "Reforzar blindaje (regolito)", "icon": "🛡", "hours": 5, "mat": 30, "energy": 0},
	"build_shelter": {"name": "Mejorar refugio", "icon": "🏠", "hours": 5, "mat": 25, "energy": 0},
	"expand_bed": {"name": "Ampliar invernadero", "icon": "🪴", "hours": 6, "mat": 30, "energy": 0},
	"expand_panel": {"name": "Añadir panel solar", "icon": "☀", "hours": 6, "mat": 40, "energy": 0},
	"process": {"name": "Procesar regolito", "icon": "⛏", "hours": 4, "mat": 0, "energy": 40},
	"fertilize": {"name": "Fertilizar", "icon": "🧪", "hours": 2, "mat": 4, "energy": 10},
	"treat": {"name": "Atender a la tripulación", "icon": "🩺", "hours": 2, "mat": 0, "energy": 10},
	# Tareas de misiones concretas (solo aparecen si la mision las usa)
	"seal_breach": {"name": "Sellar la fisura (EVA)", "icon": "🔧", "hours": 6, "mat": 20, "energy": 0},
	"recharge_suits": {"name": "Recargar trajes de EVA", "icon": "🧑‍🚀", "hours": 2, "mat": 0, "energy": 15},
}
const ROBOT_TASKS := ["build_shield", "build_shelter", "expand_bed", "expand_panel", "process"]
const PROJECTS := {
	"led_eff": {"name": "LED eficientes", "desc": "Las luces del invernadero gastan 30% menos energía."},
	"co2_filter": {"name": "Filtro de CO₂ mejorado", "desc": "El soporte vital se desgasta más despacio."},
	"regolith_mix": {"name": "Mezcla regolito-polímero", "desc": "El blindaje cuesta 20 materiales en vez de 30."},
}

# ---- estado ----
var turn := 1
var easy := false
var panels: int = SimConfig.PANELS_START
var beds := 3
var main: float = SimConfig.MAIN_START
var backup: float = SimConfig.BACKUP_CAP
var materials: float = SimConfig.START_MATERIALS
var o2 := 85.0
var co2 := 15.0
var water := 80.0
var ls_cond := 85.0
var shield: float = SimConfig.SHIELD_START
var shelter: float = SimConfig.SHELTER_START
var exposure := 0.0
var food: float = SimConfig.START_FOOD
var nutrients := 60.0
var plant_health := 100.0
var health := 90.0
var saving := false
var led := 1
var research_project := ""
var research_progress := 0.0
var research_done: Array = []
var starve_turns := 0
var hours_penalty := 0
var ls_failure := false
var scarcity := false
var alert_tier := 0
var alert_turn: int = SimConfig.ALERT_TURN
var forced_tasks: Array = []
var forced_led := -1
var decisions: Array = []
var finished := false
var won := false
var reason_id := ""
var reason := ""
var last_ratio: Dictionary = {}

# ---- configuracion por mision (MissionDef) ----
var mission: MissionDef
var turns: int = SimConfig.TURNS
var night_from: int = SimConfig.NIGHT_FROM_TURN
var solar_factor := 1.0
var control_on := true      # control apagado: no se pueden hacer obras ni investigar (ahorra energia)
var habitat_on := true      # hogar apagado: la tripulacion pierde salud (ahorra energia)
var led_cap := 2            # nivel maximo de luz permitido (una decision puede bajarlo)
var rules: Dictionary = {}  # reglas propias de la mision (MissionDef.rules)
var cons := 1.0             # modificador de consumo por turno (MissionDef.consumption_factor)
var rng := RandomNumberGenerator.new()   # solo para los sucesos de riesgo; las pruebas fijan la semilla

# ---- mecanicas de misiones del nivel Intermedio ----
var led_prev := 1           # nivel de luz del turno anterior (ciclos de luz)
var heat_on := true         # calefaccion (regla heat_comms)
var comms_on := true        # transmision de datos a la Tierra (regla heat_comms)
var data_sent := 0          # paquetes de datos enviados
var breach_open := false    # fisura abierta en el blindaje (regla breach)
var breach_progress := 0.0  # 0-100 sellado de la fisura
var suit_o2 := 80.0         # oxigeno de los trajes de EVA

# ---- alertas espaciales en tiempo real (SpaceEvents / AlertDirector) ----
var alert_score := 0          # puntos por responder bien a las alertas (puede ser negativo)
var alert_log: Array = []     # [{turn, id, title, choice, timed_out, score}]
var solar_event_mult := 1.0   # reduccion temporal de los paneles por un evento (eclipse, polvo...)
var solar_event_turns := 0    # turnos que dura

# ---- seguimiento para los logros ----
var min_ind := {"vida": 100.0, "proteccion": 100.0, "energia": 100.0, "alimentos": 100.0}
var shield_at_alert := -1.0
var expanded_before_alert := false
var sacrifices: Array = []

const HEAT_LOAD := 35.0          # energia de la calefaccion por turno (mision Sombra Orbital)
const COMMS_LOAD := 30.0         # energia de la transmision de datos por turno
const HEAT_OFF_PENALTY := 16.0   # salud que pierde la tripulacion cada turno sin calefaccion (mision Sombra Orbital)
const CONTROL_TASKS :=["build_shield", "build_shelter", "expand_bed", "expand_panel", "process", "research", "seal_breach"]


func _init(easy_mode: bool = false, m: MissionDef = null) -> void:
	easy = easy_mode
	rng.randomize()
	if m != null:
		mission = m
		rules = m.rules
		cons = m.consumption_factor
		turns = m.turns
		night_from = m.night_from_turn
		alert_turn = m.alert_turn
		solar_factor = m.solar_factor
		for k in m.start:
			match k:
				"main": main = float(m.start[k])
				"backup": backup = float(m.start[k])
				"materials": materials = float(m.start[k])
				"shield": shield = float(m.start[k])
				"shelter": shelter = float(m.start[k])
				"food": food = float(m.start[k])
				"health": health = float(m.start[k])
				"panels": panels = int(m.start[k])
				"beds": beds = int(m.start[k])
				"ls_cond": ls_cond = float(m.start[k])


# ---------------------------------------------------------------- consultas ----

func day_number() -> int:
	return (turn - 1) / SimConfig.TURNS_PER_DAY + 1


func is_day() -> bool:
	return turn < night_from


func hours_budget() -> int:
	var h := int(round(SimConfig.CREW_HOURS * (0.7 + 0.3 * health / 100.0)))
	if easy:
		h += SimConfig.EASY_HOURS_BONUS
	return maxi(4, h - hours_penalty)


func energy_total() -> float:
	return main + backup


func generation() -> float:
	return panels * SimConfig.PANEL_OUTPUT * solar_factor * solar_event_mult if is_day() else 0.0


func protection_factor(ratio_shelter: float = 1.0) -> float:
	var shelter_eff := shelter * (0.4 + 0.6 * ratio_shelter)
	var shield_eff := shield * (0.4 if breach_open else 1.0)   # una fisura abierta deja pasar la radiacion
	return 0.55 * shield_eff / 100.0 + 0.45 * shelter_eff / 100.0


func rule(key: String, default: Variant) -> Variant:
	return rules.get(key, default)


## Algunas tareas solo existen en misiones concretas.
func task_visible(id: String) -> bool:
	match id:
		"seal_breach": return bool(rule("breach", false)) and breach_open
		"recharge_suits": return bool(rule("breach", false))
	return true


func task_cost(id: String) -> Dictionary:
	var t: Dictionary = (TASKS[id] as Dictionary).duplicate()
	if id in ROBOT_TASKS:
		t["hours"] = int(ceil(float(t["hours"]) * 0.75))   # el robot constructor ayuda
	if id == "build_shield" and "regolith_mix" in research_done:
		t["mat"] = 20
	if saving and id in ["research", "process"]:
		t["energy"] = int(float(t["energy"]) * 0.5)
	return t


func all_tasks(plan: Dictionary) -> Array:
	var out: Array = []
	for t in forced_tasks:
		if not (t in out):
			out.append(t)
	for t in plan.get("tasks", []):
		if not (t in out) and TASKS.has(t):
			out.append(t)
	if not control_on:   # sin control no hay obras ni investigacion
		out = out.filter(func(t: String) -> bool: return not (t in CONTROL_TASKS))
	out = out.filter(func(t: String) -> bool: return task_visible(t))
	if "seal_breach" in out and suit_o2 < 30.0:   # sin oxigeno en los trajes no hay EVA
		out.erase("seal_breach")
	return out


func led_level(plan: Dictionary) -> int:
	var lv := forced_led if forced_led >= 0 else clampi(int(plan.get("led", led)), 0, 2)
	return mini(lv, led_cap)


func led_load(level: int) -> float:
	return float(SimConfig.LOAD_LED[level]) * (0.7 if "led_eff" in research_done else 1.0)


## Vista previa para la interfaz: {hours, mat, energy_load, energy_have, ok, why}
func preview(plan: Dictionary) -> Dictionary:
	var tasks := all_tasks(plan)
	var hours := 0
	var mat := 0.0
	var e := 0.0
	for l in _loads_list(tasks, led_level(plan)):
		e += float(l[1])
	for t in tasks:
		var c := task_cost(t)
		hours += int(c["hours"])
		mat += float(c["mat"])
	var why := ""
	if hours > hours_budget():
		why = "Faltan horas de trabajo"
	elif mat > materials + 0.001:
		why = "Faltan materiales"
	return {"hours": hours, "mat": mat, "energy_load": e, "energy_have": generation() + energy_total(),
			"hours_budget": hours_budget(), "ok": why == "", "why": why}


func can_afford(tasks: Array) -> bool:
	var plan := {"tasks": tasks}
	var saved_forced := forced_tasks
	forced_tasks = []
	var p := preview(plan)
	forced_tasks = saved_forced
	var hours_used := 0
	for t in forced_tasks:
		hours_used += int(task_cost(t)["hours"])
	return int(p["hours"]) + hours_used <= hours_budget() and float(p["mat"]) <= materials


func indicators() -> Dictionary:
	var life := minf(o2, minf(100.0 - co2, water))
	var prot := 100.0 * protection_factor()
	return {
		"vida": clampf(life, 0.0, 100.0),
		"proteccion": clampf(prot, 0.0, 100.0),
		"energia": clampf(energy_total() / (SimConfig.MAIN_CAP + SimConfig.BACKUP_CAP) * 100.0, 0.0, 100.0),
		"alimentos": clampf(food / (SimConfig.FOOD_USE * 5.0) * 100.0, 0.0, 100.0),
	}


# ------------------------------------------------------------------ turno ----

func _loads_list(tasks: Array, level: int) -> Array:
	var f := (0.7 if saving else 1.0) * cons
	var l: Array = []
	if "seal_breach" in tasks:
		# La soldadura desvia energia del soporte vital: tiene prioridad y el aire funciona a media potencia.
		l.append(["seal", 60.0])
		l.append(["ls", SimConfig.LOAD_LS * 0.5])
	else:
		l.append(["ls", SimConfig.LOAD_LS])
	if turn == alert_turn and alert_tier > 0:
		l.append(["shelter", SimConfig.LOAD_SHELTER])
	if bool(rule("heat_comms", false)) and heat_on:
		l.append(["heat", HEAT_LOAD])
	if control_on:
		l.append(["control", SimConfig.LOAD_CONTROL * f])
	if habitat_on:
		l.append(["habitat", SimConfig.LOAD_HABITAT * f])
	if bool(rule("heat_comms", false)) and comms_on:
		l.append(["comms", COMMS_LOAD])
	if level > 0:
		l.append(["led", led_load(level)])
	if "recharge_suits" in tasks:
		l.append(["recharge_suits", float(task_cost("recharge_suits")["energy"])])
	for tid in ["fertilize", "treat", "process", "research"]:
		if tid in tasks:
			l.append([tid, float(task_cost(tid)["energy"])])
	return l


## Resuelve un turno. Devuelve {before, after, msgs, finished, won}.
func step(plan: Dictionary) -> Dictionary:
	var tasks := all_tasks(plan)
	var level := led_level(plan)
	led = level
	var before := indicators()
	var before_raw := {"food": food, "materials": materials, "exposure": exposure, "energy": energy_total(), "o2": o2, "co2": co2}
	var msgs: Array = []

	# --- Materiales (se gastan al empezar)
	for t in tasks:
		materials -= float(task_cost(t)["mat"])
	materials = maxf(0.0, materials)

	# --- Energia con prioridades: soporte vital > refugio > control > hogar > luces > resto
	var gen := generation()
	var loads := _loads_list(tasks, level)
	var avail := gen + main + backup
	var supplied := {}
	var total_supplied := 0.0
	var ratio := {}
	for l in loads:
		var s := minf(float(l[1]), avail)
		supplied[l[0]] = s
		avail -= s
		total_supplied += s
		ratio[l[0]] = (s / float(l[1])) if float(l[1]) > 0.0 else 1.0
	last_ratio = ratio
	var net := gen - total_supplied
	if net >= 0.0:
		main += net
		if main > SimConfig.MAIN_CAP:
			backup = minf(SimConfig.BACKUP_CAP, backup + (main - SimConfig.MAIN_CAP))
			main = SimConfig.MAIN_CAP
	else:
		var need := -net
		var take := minf(main, need)
		main -= take
		need -= take
		backup = maxf(0.0, backup - minf(backup, need))
	if ratio.get("led", 1.0) < 0.99 and level > 0:
		msgs.append("Faltó energía: las luces del invernadero se apagaron un poco.")

	# --- Soporte vital + contribucion parcial de las plantas
	var eff := (ls_cond / 100.0) * float(ratio.get("ls", 1.0)) * (0.5 if ls_failure else 1.0)
	var lightf := float(SimConfig.LIGHT[level]) * float(ratio.get("led", 1.0))
	var light_stress := false
	if bool(rule("light_cycle", false)) and level == 2:
		if led_prev == 0:   # tras un turno a oscuras, la luz alta da un impulso de crecimiento
			lightf *= 1.35
			msgs.append("☀ Ciclo de luz: tras la oscuridad, las plantas crecen más.")
		elif led_prev == 2:   # dos turnos seguidos de luz alta estresan a las plantas
			light_stress = true
			msgs.append("🥀 Dos turnos seguidos de luz alta estresan a las plantas. Alterna con oscuridad.")
	var g := (beds / 3.0) * lightf * plant_health / 100.0
	var lso := float(rule("ls_output", 1.0))     # el soporte vital de la mision puede rendir menos oxigeno
	var po2 := float(rule("plant_o2", 1.0))      # y las plantas pueden aportar mas
	o2 = clampf(o2 + SimConfig.O2_LS * eff * lso + SimConfig.O2_PLANTS * po2 * g - SimConfig.O2_USE * cons, 0.0, 100.0)
	co2 = clampf(co2 + SimConfig.CO2_GEN - SimConfig.CO2_LS * eff - SimConfig.CO2_PLANTS * g, 0.0, 100.0)
	water = clampf(water + SimConfig.WATER_LS * eff + SimConfig.WATER_PLANTS_RETURN * g - SimConfig.WATER_USE * cons
			- SimConfig.WATER_PLANTS_USE * beds * lightf, 0.0, 100.0)
	led_prev = level

	# --- Alimentos
	var nutr_f := 1.0 if nutrients >= 20.0 else (0.5 if nutrients > 0.0 else 0.1)
	var prod := beds * SimConfig.FOOD_PER_BED * lightf * plant_health / 100.0 * nutr_f
	food = clampf(food + prod - SimConfig.FOOD_USE * cons, 0.0, 100.0)
	starve_turns = starve_turns + 1 if food <= 0.0 else 0
	if food <= 0.0:
		msgs.append("¡Se acabó la comida!")

	# --- Plantas y nutrientes
	if "tend" in tasks:
		plant_health += 15.0
	else:
		plant_health -= 12.0
	if light_stress:
		plant_health -= 10.0
	if water < 20.0:
		plant_health -= 8.0
	nutrients -= 3.0 * beds / 3.0
	if "fertilize" in tasks:
		nutrients += 20.0 * float(ratio.get("fertilize", 1.0))
	if nutrients < 15.0:
		plant_health -= 5.0
	plant_health = clampf(plant_health, 0.0, 100.0)
	nutrients = clampf(nutrients, 0.0, 100.0)

	# --- Desgaste y obras
	ls_cond -= SimConfig.LS_DECAY - (3.0 if "co2_filter" in research_done else 0.0)
	if "maintain_ls" in tasks:
		ls_cond += SimConfig.LS_MAINTAIN
	ls_cond = clampf(ls_cond, 0.0, 100.0)
	shield = maxf(0.0, shield - SimConfig.SHIELD_DECAY)
	if "build_shield" in tasks:
		shield = minf(100.0, shield + SimConfig.SHIELD_BUILD)
	if "build_shelter" in tasks:
		shelter = minf(100.0, shelter + SimConfig.SHELTER_BUILD)
	if "expand_bed" in tasks:
		beds = mini(5, beds + 1)
		if alert_turn <= 0 or turn < alert_turn:
			expanded_before_alert = true   # priorizo produccion antes de la alerta (lo mira el logro Escudo Humano)
	if "expand_panel" in tasks:
		panels = mini(SimConfig.PANELS_MAX, panels + 1)

	# --- Procesamiento y laboratorio
	if "process" in tasks:
		var y := 30.0 * float(ratio.get("process", 1.0)) * (0.5 if scarcity else 1.0) * (0.5 if saving else 1.0)
		materials += y
		msgs.append("Procesaste regolito: +%d materiales." % int(y))
	if "research" in tasks and research_project != "":
		research_progress += 50.0 * float(ratio.get("research", 1.0)) * (0.5 if saving else 1.0)
		if research_progress >= 100.0:
			research_done.append(research_project)
			msgs.append("¡Investigación lista: %s!" % PROJECTS[research_project]["name"])
			research_project = ""
			research_progress = 0.0

	# --- Fisura del blindaje (EVA): sellar gasta oxigeno de los trajes; recargarlos gasta aire de la base
	if "seal_breach" in tasks:
		breach_progress += 50.0 * float(ratio.get("seal", 1.0))
		suit_o2 = maxf(0.0, suit_o2 - 30.0)
		if breach_progress >= 100.0:
			breach_open = false
			msgs.append("🔧 ¡Fisura sellada! El blindaje vuelve a proteger.")
		else:
			msgs.append("🔧 Sellado de la fisura al %d%%. Falta otra salida EVA." % int(breach_progress))
	if "recharge_suits" in tasks:
		suit_o2 = minf(100.0, suit_o2 + 30.0 * float(ratio.get("recharge_suits", 1.0)))
		o2 = maxf(0.0, o2 - 8.0)
		msgs.append("🧑‍🚀 Trajes recargados: +30 de oxígeno (−8 de aire de la base).")

	# --- Calefaccion y transmision de datos (regla heat_comms)
	if bool(rule("heat_comms", false)):
		if not heat_on or float(ratio.get("heat", 1.0)) < 0.99:
			health -= HEAT_OFF_PENALTY
			ls_cond = maxf(0.0, ls_cond - 3.0)
			msgs.append("❄ Sin calefacción: la tripulación pierde %d de salud." % int(HEAT_OFF_PENALTY))
		else:
			health += 2.0
		if comms_on and float(ratio.get("comms", 1.0)) >= 0.99:
			data_sent += 1
			msgs.append("📡 Datos enviados a la Tierra (%d)." % data_sent)

	# --- Radiacion: ambiente + alerta solar
	var pf := protection_factor(float(ratio.get("shelter", 1.0)))
	exposure += SimConfig.AMBIENT_EXPOSURE * (1.0 - 0.5 * pf)
	if breach_open:
		exposure += 4.0   # por la fisura entra radiacion todos los turnos
	if turn == alert_turn and alert_tier > 0:
		var base: float = float(SimConfig.ALERT_EXPOSURE[alert_tier]) * (SimConfig.EASY_ALERT_FACTOR if easy else 1.0)
		var dose := base * (1.0 - pf)
		shield_at_alert = shield
		exposure += dose
		msgs.append("Alerta solar: el blindaje y el refugio frenaron %d%% de la exposición." % int(pf * 100.0))
	if "treat" in tasks:
		exposure = maxf(0.0, exposure - 8.0 * float(ratio.get("treat", 1.0)))
	exposure = clampf(exposure, 0.0, 150.0)

	# --- Salud de la tripulacion
	if not habitat_on:
		health -= 4.0   # sin calefaccion ni luz del hogar la tripulacion se resiente
	else:
		health += 6.0 if float(ratio.get("habitat", 1.0)) > 0.99 else 2.0
	if co2 > 60.0: health -= 10.0
	if o2 < 30.0: health -= 15.0
	if exposure > 50.0: health -= 8.0
	if food <= 0.0: health -= 10.0
	if "treat" in tasks: health += 20.0
	health = clampf(health, 0.0, 100.0)

	# --- Seguimiento de minimos (logros): estado de los 4 sistemas al terminar el turno
	var ind_now := indicators()
	for k in min_ind:
		min_ind[k] = minf(float(min_ind[k]), float(ind_now[k]))

	# --- Fin de turno
	for k in ["forced_tasks"]:
		forced_tasks = []
	forced_led = -1
	hours_penalty = 0
	if solar_event_turns > 0:
		solar_event_turns -= 1
		if solar_event_turns == 0:
			solar_event_mult = 1.0
	ls_failure = false
	scarcity = false
	_check_end()
	if not finished:
		turn += 1
		if turn > turns:
			_check_victory()
	return {"before": before, "after": indicators(), "before_raw": before_raw, "msgs": msgs, "finished": finished, "won": won,
			"prod": prod, "gen": gen, "load": total_supplied}


## Comprueba derrota inmediata (las alertas usan limites que evitan llegar aqui; es una red de seguridad).
func check_end_now() -> void:
	if not finished:
		_check_end()


func _check_end() -> void:
	if o2 <= 0.0 or co2 >= 100.0:
		_lose("ls", "Falló el soporte vital: el aire de la base dejó de ser seguro.")
	elif exposure >= SimConfig.EXPOSURE_FAIL:
		_lose("radiation", "La protección no alcanzó: la tripulación recibió demasiada radiación.")
	elif energy_total() <= 0.0 and float(last_ratio.get("ls", 1.0)) < 0.5:
		_lose("energy", "Se acabó la energía y los sistemas esenciales se apagaron.")
	elif starve_turns >= 2:
		_lose("food", "No hubo comida suficiente para la tripulación.")


func _check_victory() -> void:
	var ok := o2 >= 30.0 and co2 <= 70.0 and exposure < SimConfig.EXPOSURE_WIN_MAX \
			and energy_total() >= 60.0 and food >= SimConfig.FOOD_WIN_MIN
	var extra_why: PackedStringArray = []
	if mission != null:
		var ex := mission.win_extra
		if ex.has("max_exposure") and exposure > float(ex["max_exposure"]):
			ok = false
			extra_why.append("la radiación recibida superó el límite de la misión")
		if ex.has("min_health") and health < float(ex["min_health"]):
			ok = false
			extra_why.append("la tripulación quedó demasiado cansada o enferma")
		if ex.has("min_energy") and energy_total() < float(ex["min_energy"]):
			ok = false
			extra_why.append("faltó energía de reserva")
		if ex.has("min_data") and data_sent < int(ex["min_data"]):
			ok = false
			extra_why.append("solo enviaste %d de %d paquetes de datos a la Tierra" % [data_sent, int(ex["min_data"])])
		if bool(rule("breach", false)) and breach_open:
			ok = false
			extra_why.append("la fisura del blindaje quedó sin sellar")
	if ok:
		finished = true
		won = true
		reason_id = "win"
		reason = "¡La base lunar sobrevivió los 3 días!"
	else:
		var why: PackedStringArray = extra_why.duplicate()
		if o2 < 30.0 or co2 > 70.0: why.append("el aire quedó en mal estado")
		if exposure >= SimConfig.EXPOSURE_WIN_MAX: why.append("la tripulación recibió mucha radiación")
		if energy_total() < 60.0: why.append("casi no quedó energía de reserva")
		if food < SimConfig.FOOD_WIN_MIN: why.append("la comida no alcanzó para seguir")
		_lose("final", "Llegaron al final, pero " + ", ".join(why) + ".")


## Estrellas de la mision (0-3): 0 si no se supera; 1 por superarla; 2 si ningun sistema bajo de 12;
## 3 si ninguno bajo de 30 y la radiacion final es baja. Es solo para celebrar, no cambia el progreso.
func stars() -> int:
	if not won:
		return 0
	var lowest := 100.0
	for k in min_ind:
		lowest = minf(lowest, float(min_ind[k]))
	if lowest >= 30.0 and exposure < 50.0:
		return 3
	return 2 if lowest >= 12.0 else 1


## Resumen de la partida para logros y progreso (lo consume MissionManager).
func run_stats() -> Dictionary:
	return {
		"mission": mission.id if mission != null else "",
		"won": won, "turns": turns,
		"min_ind": min_ind.duplicate(), "min_food": float(min_ind["alimentos"]),
		"alert_tier": alert_tier, "shield_at_alert": shield_at_alert,
		"expanded_before_alert": expanded_before_alert,
		"sacrifices": sacrifices.duplicate(), "decisions": decisions.size(),
		"exposure": exposure, "health": health, "energy": energy_total(), "food": food,
		"data_sent": data_sent, "breach_open": breach_open,
		"alerts": alert_log.size(), "alert_score": alert_score,
	}


## Riesgos que el jugador debe ver ANTES de confirmar el turno. Cada uno: {lvl, text}
## lvl: 0 = peligro, 1 = ojo, 2 = bonus.
func risks(plan: Dictionary) -> Array:
	var out: Array = []
	var tasks := all_tasks(plan)
	var level := led_level(plan)
	var pv := preview(plan)
	var need: float = pv["energy_load"]
	var have: float = pv["energy_have"]
	if need > have:
		out.append({"lvl": 0, "text": "Falta energía: se apagará lo menos importante"})
	elif not is_day() and have - need < 120.0:
		out.append({"lvl": 1, "text": "Quedará poca energía para el próximo turno"})
	if ls_cond < 55.0:
		out.append({"lvl": 1, "text": "Soporte vital muy desgastado: riesgo de fallo"})
	if bool(rule("heat_comms", false)):
		if not heat_on:
			out.append({"lvl": 0, "text": "Sin calefacción: la salud baja %d este turno" % int(HEAT_OFF_PENALTY)})
		if not comms_on:
			out.append({"lvl": 1, "text": "Sin transmisión: no se enviarán datos (%d de %d)" % [data_sent, int(mission.win_extra.get("min_data", 0))]})
	if breach_open:
		out.append({"lvl": 0, "text": "Fisura abierta: el blindaje protege solo el 40%"})
	if "seal_breach" in tasks:
		out.append({"lvl": 1, "text": "Sellar desvía energía del soporte vital (aire a media potencia) y gasta 30 de oxígeno de los trajes"})
	if bool(rule("breach", false)) and breach_open and suit_o2 < 30.0:
		out.append({"lvl": 0, "text": "Los trajes no tienen oxígeno para una EVA: recárgalos"})
	if bool(rule("light_cycle", false)):
		if level == 2 and led_prev == 2:
			out.append({"lvl": 1, "text": "Dos turnos seguidos de luz alta estresan a las plantas"})
		elif level == 2 and led_prev == 0:
			out.append({"lvl": 2, "text": "Impulso de crecimiento: luz alta tras oscuridad"})
	if alert_turn > 0 and turn < alert_turn and alert_tier > 0 and protection_factor() < 0.5:
		out.append({"lvl": 1, "text": "La protección aún es baja para la tormenta del turno %d" % alert_turn})
	return out


func _lose(id: String, text: String) -> void:
	finished = true
	won = false
	reason_id = id
	reason = text
