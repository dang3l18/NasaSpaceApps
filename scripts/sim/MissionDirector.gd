class_name MissionDirector
extends RefCounted
## Guiones de las misiones. Cada MissionDef elige un `script_id`:
##   awakening -> Refugio Lunar: El Despertar (tutorial)
##   storm     -> Tormenta en el Horizonte (radiacion y clima espacial)
##   blackout  -> Apagon en el Casquete (escasez de energia)
## Los eventos dependen del estado de la base y de las decisiones; no hay azar sin relacion.


static func _script_of(s: BaseState) -> String:
	return s.mission.script_id if s.mission != null else "awakening"


## Noticias al empezar un turno (y cambios de estado que preparan el turno).
static func start_of_turn(s: BaseState) -> Array:
	var news: Array = []
	match _script_of(s):
		"storm": news = _storm_news(s)
		"blackout": news = _blackout_news(s)
		"lava": news = _lava_news(s)
		"shadow": news = _shadow_news(s)
		"breach": news = _breach_news(s)
		_: news = _awakening_news(s)
	if s.mission != null and s.mission.event_aggression > 0.0:
		news.append_array(_risk_events(s))
	return news


## Sucesos de riesgo (modificador de dificultad `event_aggression`). No son azar puro: solo
## pueden ocurrir si descuidaste ese sistema, y son mas probables cuanto mas agresiva es la mision.
static func _risk_events(s: BaseState) -> Array:
	var out: Array = []
	var a := s.mission.event_aggression
	if s.turn < 2 or s.turn >= s.turns:
		return out
	if s.ls_cond < 65.0 and s.rng.randf() < 0.6 * a:
		s.ls_failure = true
		out.append("⚠ El soporte vital se atasca por el desgaste: hoy rinde a media potencia.")
	elif s.energy_total() < 350.0 and s.rng.randf() < 0.5 * a:
		var leak := minf(40.0 * (1.0 + a), s.main)
		s.main -= leak
		out.append("🔋 Una batería baja de tensión por la poca reserva: −%d energía." % int(leak))
	elif s.plant_health < 55.0 and s.rng.randf() < 0.6 * a:
		s.plant_health = maxf(0.0, s.plant_health - 10.0)
		out.append("🥀 Una plaga ataca a las plantas descuidadas: −10 de salud vegetal.")
	elif s.health < 65.0 and s.rng.randf() < 0.5 * a:
		s.hours_penalty += 2
		out.append("😴 La tripulación está agotada: −2 horas de trabajo.")
	return out


## Decisiones del turno (tarjetas con coste y beneficio). Vacio si no toca ninguna.
static func cards_for_turn(s: BaseState) -> Array:
	var cards: Array = []
	match _script_of(s):
		"storm": cards = _storm_cards(s)
		"blackout": cards = _blackout_cards(s)
		"lava": cards = _lava_cards(s)
		"shadow": cards = _shadow_cards(s)
		"breach": cards = _breach_cards(s)
		_: cards = _awakening_cards(s)
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


## Aplica la opcion elegida y la registra (con el recurso sacrificado, si lo hay).
static func choose(s: BaseState, card: Dictionary, idx: int) -> void:
	var o: Dictionary = card["options"][idx]
	if o.has("saving"):
		s.saving = o["saving"]
	if o.has("led"):
		s.forced_led = int(o["led"])
	if o.has("led_cap"):
		s.led_cap = int(o["led_cap"])
	if o.has("control_on"):
		s.control_on = bool(o["control_on"])
	if o.has("habitat_on"):
		s.habitat_on = bool(o["habitat_on"])
	if o.has("heat_on"):
		s.heat_on = bool(o["heat_on"])
	if o.has("comms_on"):
		s.comms_on = bool(o["comms_on"])
	if o.has("energy_now"):
		var amt := minf(float(o["energy_now"]), s.backup)
		s.backup -= amt
		s.main = minf(SimConfig.MAIN_CAP, s.main + amt)
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
	var sac := str(o.get("sacrifice", ""))
	if sac != "":
		s.sacrifices.append(sac)
	s.decisions.append({"turn": s.turn, "title": card["title"], "choice": o["label"], "good": o.get("good", []), "bad": o.get("bad", []), "sacrifice": sac})


# =============================================================== AWAKENING ====

static func _awakening_news(s: BaseState) -> Array:
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
			news.append("☀️ ¡Alerta de actividad solar! Llegará en el turno %d. Prepara el refugio." % s.alert_turn)
			if s.ls_cond < 55.0:
				s.ls_failure = true
				news.append("⚠ Fallo parcial del soporte vital: hoy funciona a media potencia.")
		6:
			news.append("🚨 ¡La tormenta solar está aquí! El refugio necesita energía.")
		7:
			news.append_array(_plants_check(s))
		8:
			s.scarcity = true
			news.append("⛏ Escasez: el regolito cercano rinde menos hoy.")
		9:
			news.append("🏁 Último turno. ¡Revisa los cuatro sistemas!")
	return news


static func _plants_check(s: BaseState) -> Array:
	if s.plant_health < 60.0:
		s.plant_health = maxf(0.0, s.plant_health - 15.0)
		return ["🥀 Las plantas están enfermas por falta de cuidados."]
	return ["🌿 Las plantas están sanas."]


static func _awakening_cards(s: BaseState) -> Array:
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
						"bad": ["Casi no crece comida", "Las plantas ayudan menos con el aire"], "led": 0, "sacrifice": "alimentos"},
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
	return cards


# ================================================================== STORM ====
## Tormenta en el Horizonte: alerta de nivel maximo en el turno 5 (escenario educativo).

static func _storm_news(s: BaseState) -> Array:
	var news: Array = []
	match s.turn:
		1:
			s.alert_tier = NasaBridge.alert_tier()
			news.append("☀️ DONKI avisa de actividad solar fuerte: la tormenta llegará en el turno %d." % s.alert_turn)
		2:
			news.append("📡 Los paneles rinden poco por el polvo. Cada unidad de energía cuenta.")
		3:
			news.append("🛡 Faltan 2 turnos para la tormenta. Revisa blindaje y refugio.")
		4:
			s.hours_penalty = 4
			news.append("⚠ Mañana llega la tormenta. El refugio gastará ⚡ 40. Un astronauta está cansado: −4 horas.")
		5:
			news.append("🚨 ¡LA TORMENTA SOLAR ESTÁ AQUÍ! Toda la tripulación al refugio.")
		6:
			s.led_cap = 2
			news.append("🌙 Pasó lo peor. Empieza la noche. Las plantas pueden recuperar su luz si hay energía.")
		7:
			news.append_array(_plants_check(s))
		8:
			s.scarcity = true
			news.append("⛏ Escasez: el regolito cercano rinde menos hoy.")
		9:
			news.append("🏁 Último turno. ¿Cuidaste a la tripulación y a los cultivos?")
	return news


static func _storm_cards(s: BaseState) -> Array:
	var cards: Array = []
	match s.turn:
		2:
			cards.append({
				"id": "storm_crops", "icon": "🌱", "title": "SACRIFICAR LA ENERGÍA DE LOS CULTIVOS",
				"question": "El refugio necesitará energía en la tormenta. ¿Apagamos las luces del invernadero hasta que pase?",
				"options": [
					{"label": "Apagar luces LED hasta la tormenta", "good": ["Ahorras energía para el refugio", "Más reserva el día de la tormenta"],
						"bad": ["Casi no crece comida", "Las plantas ayudan menos con el aire"], "led_cap": 0, "sacrifice": "alimentos"},
					{"label": "Mantener los cultivos", "good": ["La comida sigue creciendo"],
						"bad": ["Gastas la energía que luego querrás para el refugio"]},
				]})
		3:
			cards.append({
				"id": "storm_materials", "icon": "🧱", "title": "BLINDAJE O PANELES",
				"question": "Solo alcanza para una obra grande antes de la tormenta. ¿Cuál?",
				"options": [
					{"label": "Reforzar blindaje", "good": ["Más protección contra la radiación"],
						"bad": ["−30 materiales, −5 h", "No habrá más energía solar"], "tasks": ["build_shield"]},
					{"label": "Añadir un panel solar", "good": ["+75 energía cada turno de día"],
						"bad": ["−40 materiales, −6 h", "Menos protección en la tormenta"], "tasks": ["expand_panel"]},
				]})
		4:
			cards.append({
				"id": "storm_shelter", "icon": "🏠", "title": "REFUGIO O DESCANSO",
				"question": "Última preparación antes de que llegue la tormenta.",
				"options": [
					{"label": "Mejorar el refugio", "good": ["El refugio frena más radiación"],
						"bad": ["−25 materiales, −5 h", "La tripulación descansa menos"], "tasks": ["build_shelter"]},
					{"label": "Atender a la tripulación", "good": ["Más salud y menos radiación acumulada"],
						"bad": ["−10 energía, −2 h", "El refugio queda como está"], "tasks": ["treat"]},
				]})
	return cards


# =============================================================== BLACKOUT ====
## Apagon en el Casquete: casi sin luz solar, sin alerta. Se decide que apagar.

static func _blackout_news(s: BaseState) -> Array:
	var news: Array = []
	match s.turn:
		1:
			news.append("🔦 Casi no llega luz solar: los paneles generan menos de la mitad.")
		2:
			news.append("🌑 En 1 turno empieza la noche larga. Usa el Centro de comandos para apagar subsistemas.")
		3:
			news.append("⚡ Última carga solar. Después solo baterías.")
		4:
			s.hours_penalty = 4
			news.append("🌑 Noche larga. Un astronauta está cansado: −4 horas de trabajo.")
		5:
			news.append("📉 Cada turno gastas energía sin recibir nada. Revisa qué sigue encendido.")
		6:
			var leak := minf(60.0, s.main)
			s.main -= leak
			news.append("💧 Una batería pierde carga por el frío: −%d energía." % int(leak))
		7:
			news.append_array(_plants_check(s))
		8:
			s.scarcity = true
			news.append("⛏ Escasez: el regolito cercano rinde menos hoy.")
		9:
			news.append("🏁 Último turno. ¿Te queda energía de reserva?")
	return news


static func _blackout_cards(s: BaseState) -> Array:
	var cards: Array = []
	match s.turn:
		2:
			cards.append({
				"id": "blackout_what", "icon": "🔌", "title": "¿QUÉ SUBSISTEMA APAGAMOS?",
				"question": "No alcanza la energía para todo. Cada apagado ahorra batería, pero tiene un coste. Puedes cambiarlo después en el Centro de comandos.",
				"options": [
					{"label": "Apagar el Hogar", "good": ["Ahorra ⚡ 30 por turno"],
						"bad": ["La tripulación pierde salud cada turno", "Dormitorios y área común sin calor"], "habitat_on": false, "sacrifice": "descanso"},
					{"label": "Apagar el Control", "good": ["Ahorra ⚡ 30 por turno"],
						"bad": ["No hay obras ni investigación", "No se puede construir ni procesar regolito"], "control_on": false, "sacrifice": "obras"},
					{"label": "Apagar luces del invernadero", "good": ["Ahorra ⚡ 35 a 70 por turno"],
						"bad": ["Casi no crece comida", "Las plantas ayudan menos con el aire"], "led_cap": 0, "sacrifice": "alimentos"},
				]})
		4:
			cards.append({
				"id": "blackout_reserve", "icon": "🔋", "title": "RESERVA DE RESPALDO",
				"question": "La batería principal baja. ¿Usamos la reserva de emergencia?",
				"options": [
					{"label": "Gastar 150 de reserva ahora", "good": ["Más energía en la batería principal"],
						"bad": ["Menos reserva para el final", "Sin colchón ante una fuga"], "energy_now": 150.0, "sacrifice": "reserva de emergencia"},
					{"label": "Guardar la reserva", "good": ["Reserva intacta para emergencias"],
						"bad": ["La batería principal baja más rápido"]},
				]})
	return cards


# ============================================================ INTERMEDIO ====
# Nivel Intermedio: modificadores de consumo y de sucesos de riesgo (ver MissionDef).

# ---- La Cosecha de los Tubos de Lava: ciclos de luz del invernadero ----

static func _lava_news(s: BaseState) -> Array:
	var news: Array = []
	match s.turn:
		1:
			news.append("🌋 Estás en un tubo de lava. Las plantas dan casi todo el oxígeno: el soporte vital rinde poco.")
		2:
			news.append("💡 Alterna luz alta y oscuridad: tras un turno a oscuras, la luz alta da un impulso de crecimiento.")
		3:
			news.append("⚡ Ojo: dos turnos seguidos de luz alta estresan a las plantas.")
		4:
			s.hours_penalty += 2
			news.append("😴 Un astronauta está cansado: −2 horas de trabajo.")
		5:
			news.append("🌙 Cae la noche fuera del tubo. Solo baterías.")
		6:
			news.append_array(_plants_check(s))
		7:
			if s.ls_cond < 60.0:
				s.ls_failure = true
				news.append("⚠ La bomba de aire falla: hoy funciona a media potencia.")
		8:
			s.scarcity = true
			news.append("⛏ Escasez: el regolito cercano rinde menos hoy.")
		9:
			news.append("🏁 Último turno. ¿Cuidaste el aire, la comida y la energía?")
	return news


static func _lava_cards(s: BaseState) -> Array:
	var cards: Array = []
	match s.turn:
		2:
			cards.append({
				"id": "lava_light", "icon": "💡", "title": "LUZ ALTA O DESCANSO DE LA PLANTA",
				"question": "Empieza el ciclo de luz del invernadero. ¿Cómo arrancamos este turno?",
				"options": [
					{"label": "Luz alta ahora", "good": ["Más oxígeno y comida ahora"],
						"bad": ["−70 energía", "Si repites, las plantas se estresan"], "risk": "Dos turnos seguidos de luz alta dañan a las plantas", "led": 2},
					{"label": "Oscuridad ahora", "good": ["Ahorras energía", "El siguiente turno de luz alta crece más"],
						"bad": ["Casi sin oxígeno de las plantas este turno"], "risk": "El aire depende de las plantas: vigila el oxígeno", "led": 0, "sacrifice": "oxígeno de las plantas"},
				]})
		4:
			cards.append({
				"id": "lava_o2_food", "icon": "🪴", "title": "MÁS PLANTAS O MÁS SOPORTE VITAL",
				"question": "El oxígeno depende de las plantas. ¿En qué usamos las horas de la tripulación?",
				"options": [
					{"label": "Ampliar el invernadero", "good": ["Más oxígeno y comida de las plantas"],
						"bad": ["−30 materiales, −6 h", "Más luz que pagar"], "tasks": ["expand_bed"]},
					{"label": "Mantener el soporte vital", "good": ["Aire más estable", "Menos riesgo de fallo"],
						"bad": ["−4 h, −5 materiales", "Las plantas siguen siendo la base del oxígeno"], "tasks": ["maintain_ls"]},
				]})
		6:
			cards.append({
				"id": "lava_night", "icon": "🔋", "title": "AHORRAR O CONSUMIR ENERGÍA",
				"question": "La noche será larga. ¿Cómo usamos las baterías?",
				"options": [
					{"label": "Activar ahorro", "good": ["Conserva baterías"],
						"bad": ["Menos materiales", "Investigación más lenta"], "saving": true},
					{"label": "Todo al máximo", "good": ["Producción sin recortes"],
						"bad": ["Gasta la reserva"], "saving": false},
				]})
	return cards


# ---- Efecto de Sombra Orbital: calefaccion o transmision de datos ----

static func _shadow_news(s: BaseState) -> Array:
	var news: Array = []
	match s.turn:
		1:
			news.append("🌑 Noche prolongada: casi no habrá luz solar. Calefacción y transmisión compiten por la batería.")
		2:
			news.append("📡 Hay que enviar datos a la Tierra en al menos 4 turnos. La calefacción evita el frío.")
		3:
			news.append("❄ El frío aprieta. Sin calefacción la salud baja 16 por turno.")
		4:
			s.hours_penalty += 2
			news.append("😴 Un astronauta está cansado: −2 horas de trabajo.")
		5:
			news.append("📊 Revisa cuántos paquetes de datos llevas enviados (Centro de comandos).")
		6:
			news.append_array(_plants_check(s))
		7:
			news.append("🌑 Siguen sin llegar rayos de sol. ¿Calor o contacto?")
		8:
			s.scarcity = true
			news.append("⛏ Escasez: el regolito cercano rinde menos hoy.")
		9:
			news.append("🏁 Último turno. ¿Enviaste suficientes datos y mantuviste a todos sanos?")
	return news


static func _shadow_cards(s: BaseState) -> Array:
	var cards: Array = []
	match s.turn:
		2:
			cards.append({
				"id": "shadow_heat_comms", "icon": "🌡", "title": "CALEFACCIÓN O TRANSMISIÓN",
				"question": "La energía no alcanza para las dos cosas. ¿Qué mantenemos encendido? (Puedes cambiarlo en el Centro de comandos.)",
				"options": [
					{"label": "Mantener la calefacción", "good": ["La tripulación no sufre frío"],
						"bad": ["No se envían datos a la Tierra"], "risk": "Necesitas datos en 4 turnos para ganar", "comms_on": false, "sacrifice": "datos"},
					{"label": "Transmitir datos", "good": ["Datos científicos a la Tierra"],
						"bad": ["Frío: −16 de salud por turno"], "risk": "La salud puede caer por debajo de 40%", "heat_on": false, "sacrifice": "calefacción"},
				]})
		4:
			cards.append({
				"id": "shadow_reserve", "icon": "🔋", "title": "RESERVA DE RESPALDO",
				"question": "La batería principal baja. ¿Usamos la reserva de emergencia?",
				"options": [
					{"label": "Gastar 150 de reserva ahora", "good": ["Más energía en la batería principal"],
						"bad": ["Menos reserva para el final"], "risk": "Una fuga o un fallo después te dejaría sin colchón", "energy_now": 150.0, "sacrifice": "reserva de emergencia"},
					{"label": "Guardar la reserva", "good": ["Reserva intacta para emergencias"],
						"bad": ["La batería principal baja más rápido"]},
				]})
		6:
			cards.append({
				"id": "shadow_control", "icon": "🔌", "title": "¿APAGAMOS EL CONTROL?",
				"question": "Faltan 4 turnos de noche. Apagar el Control ahorra ⚡ 30 por turno, pero no habrá obras ni investigación.",
				"options": [
					{"label": "Apagar el Control", "good": ["Ahorra ⚡ 30 por turno"],
						"bad": ["No hay obras ni investigación"], "control_on": false, "sacrifice": "obras"},
					{"label": "Dejarlo encendido", "good": ["Puedes seguir trabajando"],
						"bad": ["Gastas ⚡ 30 por turno"]},
				]})
	return cards


# ---- Anomalia en el Escudo Termico: sellar la fisura con EVA ----

static func _breach_news(s: BaseState) -> Array:
	var news: Array = []
	match s.turn:
		1:
			s.alert_tier = NasaBridge.alert_tier()
			news.append("☀️ DONKI avisa de una tormenta solar fuerte: llegará en el turno %d." % s.alert_turn)
		2:
			news.append("🛰 Revisión del escudo térmico: aguanta, pero está muy cargado.")
		3:
			news.append("🧑‍🚀 Prepara los trajes de EVA: quizá hagan falta antes de la tormenta.")
		4:
			s.breach_open = true
			s.breach_progress = 0.0
			s.hours_penalty += 2
			news.append("🚨 ¡ANOMALÍA! Se abrió una fisura en el escudo térmico: la protección baja al 40%. Hay que sellarla en 2 salidas EVA.")
		5:
			if s.breach_open:
				news.append("⚠ La fisura sigue abierta y mañana llega la tormenta. ¡Última oportunidad de sellarla!")
			else:
				news.append("✅ La fisura está sellada. Mañana llega la tormenta.")
		6:
			news.append("🚨 ¡LA TORMENTA SOLAR ESTÁ AQUÍ! Toda la tripulación al refugio.")
		7:
			news.append_array(_plants_check(s))
		8:
			s.scarcity = true
			news.append("⛏ Escasez: el regolito cercano rinde menos hoy.")
		9:
			news.append("🏁 Último turno. Revisa el aire, la energía y la salud.")
	return news


static func _breach_cards(s: BaseState) -> Array:
	var cards: Array = []
	match s.turn:
		3:
			cards.append({
				"id": "breach_prep", "icon": "🧑‍🚀", "title": "TRAJES O REFUGIO",
				"question": "Antes de que pase algo, ¿en qué usamos las horas?",
				"options": [
					{"label": "Recargar los trajes", "good": ["Oxígeno de EVA al máximo"],
						"bad": ["−8 de aire de la base", "−2 h, −15 energía"], "tasks": ["recharge_suits"]},
					{"label": "Mejorar el refugio", "good": ["El refugio frena más radiación"],
						"bad": ["−25 materiales, −5 h", "Los trajes quedan como están"], "tasks": ["build_shelter"]},
				]})
		4:
			cards.append({
				"id": "breach_seal_1", "icon": "🔧", "title": "SELLAR LA FISURA (1.ª EVA)",
				"question": "Soldar el escudo exige desviar energía del soporte vital y gastar oxígeno de los trajes.",
				"options": [
					{"label": "Salir a sellar ahora", "good": ["El sellado avanza al 50%", "Al terminar, el blindaje vuelve a protegerte"],
						"bad": ["El aire funciona a media potencia", "−30 oxígeno de los trajes, −20 materiales, −6 h"],
						"risk": "Con poca energía, el soporte vital puede quedarse corto este turno", "tasks": ["seal_breach"], "sacrifice": "soporte vital"},
					{"label": "Esperar y reforzar el refugio", "good": ["El aire sigue a plena potencia"],
						"bad": ["La fisura sigue abierta (+4 radiación por turno)"], "risk": "Si no la sellas antes de la tormenta, pasará por la fisura", "tasks": ["build_shelter"]},
				]})
		5:
			if s.breach_open:
				cards.append({
					"id": "breach_seal_2", "icon": "🔧", "title": "SELLAR LA FISURA (2.ª EVA)",
					"question": "Mañana llega la tormenta. ¿Cerramos la fisura o recargamos los trajes?",
					"options": [
						{"label": "Terminar el sellado", "good": ["La fisura queda cerrada"],
							"bad": ["El aire funciona a media potencia", "−30 oxígeno de los trajes, −20 materiales, −6 h"],
							"risk": "Si los trajes no tienen 30 de oxígeno, no podrás salir", "tasks": ["seal_breach"], "sacrifice": "soporte vital"},
						{"label": "Recargar trajes primero", "good": ["+30 oxígeno de EVA"],
							"bad": ["−8 de aire de la base", "La fisura sigue abierta hoy"], "risk": "Mañana ya será la tormenta: no habrá otra oportunidad", "tasks": ["recharge_suits"]},
					]})
	return cards
