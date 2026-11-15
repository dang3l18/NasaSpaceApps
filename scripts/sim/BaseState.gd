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


func _init(easy_mode: bool = false) -> void:
	easy = easy_mode


# ---------------------------------------------------------------- consultas ----

func day_number() -> int:
	return (turn - 1) / SimConfig.TURNS_PER_DAY + 1


func is_day() -> bool:
	return turn < SimConfig.NIGHT_FROM_TURN


func hours_budget() -> int:
	var h := int(round(SimConfig.CREW_HOURS * (0.7 + 0.3 * health / 100.0)))
	if easy:
		h += SimConfig.EASY_HOURS_BONUS
	return maxi(4, h - hours_penalty)


func energy_total() -> float:
	return main + backup


func generation() -> float:
	return panels * SimConfig.PANEL_OUTPUT if is_day() else 0.0


func protection_factor(ratio_shelter: float = 1.0) -> float:
	var shelter_eff := shelter * (0.4 + 0.6 * ratio_shelter)
	return 0.55 * shield / 100.0 + 0.45 * shelter_eff / 100.0


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
	return out


func led_level(plan: Dictionary) -> int:
	return forced_led if forced_led >= 0 else clampi(int(plan.get("led", led)), 0, 2)


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
	var f := 0.7 if saving else 1.0
	var l: Array = [["ls", SimConfig.LOAD_LS]]
	if turn == alert_turn and alert_tier > 0:
		l.append(["shelter", SimConfig.LOAD_SHELTER])
	l.append(["control", SimConfig.LOAD_CONTROL * f])
	l.append(["habitat", SimConfig.LOAD_HABITAT * f])
	if level > 0:
		l.append(["led", led_load(level)])
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
	var g := (beds / 3.0) * lightf * plant_health / 100.0
	o2 = clampf(o2 + SimConfig.O2_LS * eff + SimConfig.O2_PLANTS * g - SimConfig.O2_USE, 0.0, 100.0)
	co2 = clampf(co2 + SimConfig.CO2_GEN - SimConfig.CO2_LS * eff - SimConfig.CO2_PLANTS * g, 0.0, 100.0)
	water = clampf(water + SimConfig.WATER_LS * eff + SimConfig.WATER_PLANTS_RETURN * g - SimConfig.WATER_USE
			- SimConfig.WATER_PLANTS_USE * beds * lightf, 0.0, 100.0)

	# --- Alimentos
	var nutr_f := 1.0 if nutrients >= 20.0 else (0.5 if nutrients > 0.0 else 0.1)
	var prod := beds * SimConfig.FOOD_PER_BED * lightf * plant_health / 100.0 * nutr_f
	food = clampf(food + prod - SimConfig.FOOD_USE, 0.0, 100.0)
	starve_turns = starve_turns + 1 if food <= 0.0 else 0
	if food <= 0.0:
		msgs.append("¡Se acabó la comida!")

	# --- Plantas y nutrientes
	if "tend" in tasks:
		plant_health += 15.0
	else:
		plant_health -= 12.0
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

	# --- Radiacion: ambiente + alerta solar
	var pf := protection_factor(float(ratio.get("shelter", 1.0)))
	exposure += SimConfig.AMBIENT_EXPOSURE * (1.0 - 0.5 * pf)
	if turn == alert_turn and alert_tier > 0:
		var base: float = float(SimConfig.ALERT_EXPOSURE[alert_tier]) * (SimConfig.EASY_ALERT_FACTOR if easy else 1.0)
		var dose := base * (1.0 - pf)
		exposure += dose
		msgs.append("Alerta solar: el blindaje y el refugio frenaron %d%% de la exposición." % int(pf * 100.0))
	if "treat" in tasks:
		exposure = maxf(0.0, exposure - 8.0 * float(ratio.get("treat", 1.0)))
	exposure = clampf(exposure, 0.0, 150.0)

	# --- Salud de la tripulacion
	health += 6.0 if float(ratio.get("habitat", 1.0)) > 0.99 else 2.0
	if co2 > 60.0: health -= 10.0
	if o2 < 30.0: health -= 15.0
	if exposure > 50.0: health -= 8.0
	if food <= 0.0: health -= 10.0
	if "treat" in tasks: health += 20.0
	health = clampf(health, 0.0, 100.0)

	# --- Fin de turno
	for k in ["forced_tasks"]:
		forced_tasks = []
	forced_led = -1
	hours_penalty = 0
	ls_failure = false
	scarcity = false
	_check_end()
	if not finished:
		turn += 1
		if turn > SimConfig.TURNS:
			_check_victory()
	return {"before": before, "after": indicators(), "before_raw": before_raw, "msgs": msgs, "finished": finished, "won": won,
			"prod": prod, "gen": gen, "load": total_supplied}


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
	if ok:
		finished = true
		won = true
		reason_id = "win"
		reason = "¡La base lunar sobrevivió los 3 días!"
	else:
		var why: PackedStringArray = []
		if o2 < 30.0 or co2 > 70.0: why.append("el aire quedó en mal estado")
		if exposure >= SimConfig.EXPOSURE_WIN_MAX: why.append("la tripulación recibió mucha radiación")
		if energy_total() < 60.0: why.append("casi no quedó energía de reserva")
		if food < SimConfig.FOOD_WIN_MIN: why.append("la comida no alcanzó para seguir")
		_lose("final", "Llegaron al final, pero " + ", ".join(why) + ".")


func _lose(id: String, text: String) -> void:
	finished = true
	won = false
	reason_id = id
	reason = text
