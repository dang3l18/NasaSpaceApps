class_name MissionDirector
extends RefCounted
## Guion de OPERACION: REFUGIO LUNAR. Los eventos dependen del estado de la base y de las
## decisiones del jugador; no hay sucesos aleatorios sin relacion con los sistemas.

## Noticias al empezar un turno (y cambios de estado que preparan el turno).
static func start_of_turn(s: BaseState) -> Array:
	var news: Array = []
	match s.turn:
		1:
			news.append("☀ Es de día en la Luna. Los paneles solares cargan las baterías.")
		2:
			news.append("🌙 Pronto llegará la noche lunar: 2 días sin luz solar.")
		3:
			news.append("⚡ Última carga solar. Después solo habrá baterías.")
		4:
			s.hours_penalty = 6 if s.health < 70.0 else 2
			news.append("🌙 Empezó la noche. Un astronauta está cansado: −%d horas de trabajo." % s.hours_penalty)
		5:
			s.alert_tier = NasaBridge.alert_tier()
			s.alert_turn = SimConfig.ALERT_TURN
			news.append("☀️ ¡Alerta de actividad solar! Llegará en el turno %d. Prepara el refugio." % s.alert_turn)
			if s.ls_cond < 55.0:
				s.ls_failure = true
				news.append("⚠ Fallo parcial del soporte vital: hoy funciona a media potencia.")
		6:
			news.append("🚨 ¡La tormenta solar está aquí! El refugio necesita energía.")
		7:
			if s.plant_health < 60.0:
				s.plant_health = maxf(0.0, s.plant_health - 15.0)
				news.append("🥀 Las plantas están enfermas por falta de cuidados.")
			else:
				news.append("🌿 Las plantas están sanas.")
		8:
			s.scarcity = true
			news.append("⛏ Escasez: el regolito cercano rinde menos hoy.")
		9:
			news.append("🏁 Último turno. ¡Revisa los cuatro sistemas!")
	return news


## Decisiones del turno (tarjetas con coste y beneficio). Vacio si no toca ninguna.
static func cards_for_turn(s: BaseState) -> Array:
	var cards: Array = []
	match s.turn:
		2:
			cards.append({
				"id": "night_power", "icon": "🔋", "title": "AHORRAR O CONSUMIR ENERGÍA",
				"question": "Se acerca la noche lunar. ¿Cómo usamos las baterías?",
				"options": [
					{"label": "Activar ahorro", "good": ["Conserva baterías", "Más reserva de emergencia"],
						"bad": ["Menos producción de materiales", "Investigación más lenta"], "saving": true},
					{"label": "Todo al máximo", "good": ["Procesamiento e investigación a tope"],
						"bad": ["Gasta las reservas", "Puede faltar energía después"], "saving": false},
				]})
		3:
			cards.append({
				"id": "maint_vs_lab", "icon": "🛠", "title": "MANTENIMIENTO O INVESTIGACIÓN",
				"question": "La tripulación tiene poco tiempo. ¿A qué dedicamos 4 horas?",
				"options": [
					{"label": "Mantener soporte vital", "good": ["Menos fallos", "Aire más estable"],
						"bad": ["Investigación retrasada", "−4 h, −5 materiales"], "tasks": ["maintain_ls"]},
					{"label": "Trabajar en el laboratorio", "good": ["Desbloquea una mejora"],
						"bad": ["El soporte vital se desgasta más", "−4 h, −50 energía"], "tasks": ["research"], "wear": 10.0},
				]})
		4:
			cards.append({
				"id": "led_vs_energy", "icon": "💡", "title": "CULTIVOS O ENERGÍA",
				"question": "Las plantas piden más luz LED. ¿Qué hacemos esta noche?",
				"options": [
					{"label": "Luz LED alta", "good": ["Más comida", "Más aire de las plantas"],
						"bad": ["−70 energía este turno", "Menos reserva para la tormenta"], "led": 2},
					{"label": "Luz LED baja", "good": ["Ahorra electricidad"],
						"bad": ["Casi no crece comida", "Las plantas ayudan menos con el aire"], "led": 0},
				]})
		5:
			cards.append({
				"id": "shield_vs_bed", "icon": "🛡", "title": "BLINDAJE O INVERNADERO",
				"question": "Llega una alerta solar. ¿En qué usamos los materiales?",
				"options": [
					{"label": "Reforzar blindaje", "good": ["Más protección", "Menos riesgo en la tormenta"],
						"bad": ["−30 materiales, −5 h", "Sin cama nueva de cultivo"], "tasks": ["build_shield"]},
					{"label": "Ampliar invernadero", "good": ["Más comida cada turno", "Más aire de las plantas"],
						"bad": ["−30 materiales, −6 h", "Más riesgo en la tormenta"], "tasks": ["expand_bed"]},
				]})
	# Marca cuales opciones se pueden pagar ahora mismo.
	for c in cards:
		var any := false
		for o in c["options"]:
			var t: Array = o.get("tasks", [])
			o["affordable"] = t.is_empty() or s.can_afford(t)
			any = any or o["affordable"]
		if not any:
			(c["options"] as Array).append({"label": "Seguir sin cambios", "good": ["No gastas nada"], "bad": ["No mejoras la base"],
					"affordable": true})
	return cards


## Aplica la opcion elegida. Devuelve un texto corto para el informe final.
static func choose(s: BaseState, card: Dictionary, idx: int) -> void:
	var o: Dictionary = card["options"][idx]
	if o.has("saving"):
		s.saving = o["saving"]
	if o.has("led"):
		s.forced_led = int(o["led"])
	for t in o.get("tasks", []):
		if not (t in s.forced_tasks):
			s.forced_tasks.append(t)
	if o.has("wear"):
		s.ls_cond = maxf(0.0, s.ls_cond - float(o["wear"]))
	if "research" in o.get("tasks", []) and s.research_project == "":
		for p in BaseState.PROJECTS:
			if not (p in s.research_done):
				s.research_project = p
				break
	s.decisions.append({"turn": s.turn, "title": card["title"], "choice": o["label"], "good": o.get("good", []), "bad": o.get("bad", [])})
