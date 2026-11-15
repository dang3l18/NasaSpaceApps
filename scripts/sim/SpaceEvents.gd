class_name SpaceEvents
extends RefCounted
## Catalogo de ALERTAS ESPACIALES en tiempo real y aplicacion de sus consecuencias sobre BaseState.
## Todo es SIMULACION EDUCATIVA: las cifras son parametros de juego, no mediciones de NASA.
## Cada evento: icono, titulo, descripcion, peligro (tier 1-3), segundos para reaccionar y 3 opciones.
## Ninguna opcion es "la correcta": todas tienen ventajas (good) y desventajas (bad) con efectos reales (fx).
## Si el jugador no responde a tiempo se aplica `timeout` (la peor consecuencia del evento).
##
## Claves de `fx`: energy, backup, materials, exposure, o2, water, ls_cond, shield, shelter, food,
## plant_health, health (cambios), hours (horas de trabajo perdidas este turno), solar [multiplicador, turnos], score.

const SPEED_BONUS := 5          # puntos extra por decidir con mas de la mitad del tiempo
const EASY_RELIEF := 0.75       # en el modo 7-9 anos las perdidas se reducen un 25%
const FLOORS := {"o2": 12.0, "water": 15.0, "ls_cond": 5.0, "shield": 5.0, "shelter": 5.0, "plant_health": 5.0, "health": 20.0}
const EXPOSURE_CEIL := 92.0     # una alerta nunca provoca la derrota por si sola

const LABELS := {
	"energy": "⚡ Energía", "backup": "🔋 Reserva", "materials": "🧱 Materiales", "exposure": "☢ Radiación recibida",
	"o2": "💨 Oxígeno", "water": "💧 Agua", "ls_cond": "🛠 Soporte vital", "shield": "🛡 Blindaje", "shelter": "🏠 Refugio",
	"food": "🍎 Comida", "plant_health": "🌱 Salud de las plantas", "health": "🧑‍🚀 Salud de la tripulación",
}


## Definicion de todos los eventos. `only`: ids de mision donde puede aparecer (vacio = todas).
static func catalog() -> Array:
	return [
		{
			"id": "thermal", "icon": "🌡️", "title": "TEMPERATURA EXTREMA", "tier": 1, "seconds": 35.0, "verb": "RIESGO TÉRMICO EN", "robot": "¡Uy, hace mucho calor! ¡Enfriemos la base!",
			"desc": "La temperatura de la base sale del rango seguro. Si no actúas, los equipos y las plantas sufrirán.",
			"fact": "En el espacio, el lado que mira al Sol puede estar a cientos de grados más caliente que el lado en sombra.",
			"options": [
				{"label": "Activar la regulación térmica", "good": ["Temperatura estable"], "bad": ["Gasta 50 de energía"],
					"fx": {"energy": -50.0, "score": 10}, "result": "Los radiadores enfrían la base. Todo vuelve a la normalidad."},
				{"label": "Girar la base para dar sombra", "good": ["No gasta energía"], "bad": ["Los paneles rinden 40% menos este turno"],
					"fx": {"solar": [0.6, 1], "score": 5}, "result": "La base gira y se enfría, pero los paneles reciben menos luz."},
				{"label": "Apagar equipos y esperar", "good": ["Ahorras 20 de energía"], "bad": ["Plantas −10", "Salud −5"],
					"fx": {"energy": 20.0, "plant_health": -10.0, "health": -5.0, "score": 0}, "result": "Ahorras energía, pero el calor cansa a las plantas y a la tripulación."},
			],
			"timeout": {"text": "Nadie reaccionó: el sobrecalentamiento dañó equipos y plantas.",
				"fx": {"health": -10.0, "plant_health": -15.0, "ls_cond": -10.0, "score": -15}},
		},
		{
			"id": "eclipse", "icon": "🌑", "title": "ECLIPSE: PANELES SIN LUZ", "tier": 1, "seconds": 35.0, "verb": "SOMBRA TOTAL EN", "robot": "¡La Luna tapa el Sol! ¡Cuidemos la energía!",
			"desc": "La Luna tapa el Sol. Los paneles solares rinden mucho menos durante los próximos turnos.",
			"fact": "En órbita, la base pasa por la sombra de planetas y lunas: sin Sol, solo trabajan las baterías.",
			"options": [
				{"label": "Activar el modo ahorro", "good": ["Ahorras 40 de energía"], "bad": ["Plantas −8 por menos luz", "Paneles al 50% por 2 turnos"],
					"fx": {"energy": 40.0, "plant_health": -8.0, "solar": [0.5, 2], "score": 10}, "result": "El modo ahorro estira las baterías, pero las plantas reciben menos luz."},
				{"label": "Usar la reserva de emergencia", "good": ["Todo sigue a pleno rendimiento"], "bad": ["Gastas 100 de reserva", "Paneles al 50% por 2 turnos"],
					"fx": {"backup": -100.0, "solar": [0.5, 2], "score": 5}, "result": "No notas el eclipse… pero la reserva queda más baja."},
				{"label": "Orientar los paneles al máximo", "good": ["Recuperas parte de la luz (75%)"], "bad": ["−40 de energía", "−10 materiales"],
					"fx": {"energy": -40.0, "materials": -10.0, "solar": [0.75, 2], "score": 10}, "result": "La maniobra captura algo de luz, a cambio de energía y repuestos."},
			],
			"timeout": {"text": "Sin reacción: los paneles quedaron casi a oscuras y las baterías se vaciaron.",
				"fx": {"energy": -40.0, "solar": [0.4, 2], "score": -10}},
		},
		{
			"id": "power", "icon": "🔋", "title": "FALLO ENERGÉTICO", "tier": 2, "seconds": 30.0, "verb": "APAGÓN EN", "robot": "¡Falla la energía! ¿Qué es lo más importante?",
			"desc": "El sistema de energía tiene una falla. Hay que decidir qué sistemas esenciales se mantienen encendidos.",
			"fact": "Las baterías guardan la energía de los paneles para la parte de la órbita en que el Sol queda tapado.",
			"options": [
				{"label": "Priorizar el soporte vital", "good": ["El aire y el agua siguen seguros"], "bad": ["Cultivos sin luz: plantas −15", "−30 de energía"],
					"fx": {"energy": -30.0, "plant_health": -15.0, "score": 15}, "result": "El aire está a salvo; el invernadero se queda a oscuras un rato."},
				{"label": "Priorizar el invernadero", "good": ["Plantas y comida a salvo (+6 comida)"], "bad": ["El soporte vital trabaja a medias: aire −12"],
					"fx": {"food": 6.0, "o2": -12.0, "score": 5}, "result": "Las plantas siguen, pero el aire de la base empeora."},
				{"label": "Pasar a la batería de respaldo", "good": ["Todo sigue funcionando"], "bad": ["Gastas 120 de la reserva"],
					"fx": {"backup": -120.0, "score": 10}, "result": "Nada se apaga, pero la reserva de emergencia queda muy baja."},
			],
			"timeout": {"text": "Sin decisión: los sistemas se apagaron al azar.",
				"fx": {"energy": -80.0, "o2": -10.0, "plant_health": -10.0, "score": -20}},
		},
		{
			"id": "meteor", "icon": "☄️", "title": "METEORITO CERCA", "tier": 2, "seconds": 25.0, "verb": "IMPACTO EN", "robot": "¡Un meteorito se acerca! ¡Protejamos la base!",
			"desc": "Un meteoroide se acerca a la base. Debes decidir cómo protegerla.",
			"fact": "La ISS tiene escudos especiales contra micrometeoroides y desechos, y a veces maniobra para esquivarlos.",
			"options": [
				{"label": "Activar los escudos", "good": ["El blindaje absorbe el impacto"], "bad": ["Gasta 90 de energía", "Blindaje −4"],
					"fx": {"energy": -90.0, "shield": -4.0, "score": 10}, "result": "Los escudos aguantan el golpe sin daños graves."},
				{"label": "Desviarlo con los propulsores", "good": ["Esquivas el impacto"], "bad": ["−60 de energía", "Soporte vital −8 por la vibración"],
					"fx": {"energy": -60.0, "ls_cond": -8.0, "score": 15}, "result": "La maniobra funciona, aunque sacude el soporte vital."},
				{"label": "Proteger los módulos habitables", "good": ["La tripulación queda a salvo"], "bad": ["Los módulos de carga se dañan: −30 materiales", "Blindaje −10"],
					"fx": {"materials": -30.0, "shield": -10.0, "score": 5}, "result": "La tripulación está segura, pero se pierde parte de la carga."},
			],
			"timeout": {"text": "El meteoroide impactó sin protección.",
				"fx": {"shield": -18.0, "materials": -30.0, "ls_cond": -15.0, "health": -10.0, "score": -20}},
		},
		{
			"id": "flare", "icon": "☀️", "title": "LLAMARADA SOLAR DETECTADA", "tier": 2, "seconds": 30.0, "verb": "LLEGADA EN", "robot": "¡Una tormenta solar se acerca! ¡Protejamos al equipo!",
			"desc": "Una llamarada solar amenaza los sistemas electrónicos y a la tripulación. Activa la protección.",
			"fact": "Los satélites vigilan el Sol para avisar a los astronautas antes de que lleguen las partículas.",
			"options": [
				{"label": "Refugio de radiación y equipos desconectados", "good": ["Radiación casi nula", "Equipos a salvo"], "bad": ["−4 horas de trabajo este turno", "−40 de energía"],
					"fx": {"hours": 4, "energy": -40.0, "exposure": 2.0, "score": 15}, "result": "Todos al refugio: la tripulación y los equipos pasan la llamarada a salvo."},
				{"label": "Activar la protección y seguir trabajando", "good": ["No pierdes horas de trabajo"], "bad": ["Radiación +12", "−25 de energía por equipos calientes"],
					"fx": {"exposure": 12.0, "energy": -25.0, "score": 5}, "result": "Sigues trabajando, pero la tripulación recibe algo de radiación."},
				{"label": "Desconectar equipos con la tripulación en sus puestos", "good": ["Ahorras 30 de energía", "Equipos a salvo"], "bad": ["Radiación +22", "Salud −8"],
					"fx": {"energy": 30.0, "exposure": 22.0, "health": -8.0, "score": 0}, "result": "Los equipos están a salvo, pero la tripulación quedó expuesta."},
			],
			"timeout": {"text": "La llamarada llegó sin protección: sobrecarga y radiación.",
				"fx": {"exposure": 30.0, "energy": -60.0, "ls_cond": -10.0, "score": -20}},
		},
		{
			"id": "leak", "icon": "⚠️", "title": "FUGA DE OXÍGENO", "tier": 3, "seconds": 25.0, "verb": "AIRE ESCAPANDO · QUEDAN", "robot": "¡Se escapa el aire! ¡Rápido, comandante!",
			"desc": "Se detecta una fuga en un módulo habitable. El aire se escapa: hay que actuar rápido.",
			"fact": "En 2018 se detectó una pequeña fuga de aire en la ISS; la tripulación la localizó y la selló.",
			"options": [
				{"label": "Sellar el módulo y repararlo", "good": ["Detienes la fuga"], "bad": ["−20 materiales", "−3 horas de trabajo este turno", "Oxígeno −4"],
					"fx": {"materials": -20.0, "hours": 3, "o2": -4.0, "score": 20}, "result": "La fuga queda sellada. Cuesta repuestos y tiempo."},
				{"label": "Aislar el módulo (cerrar la compuerta)", "good": ["Rápido: casi no se pierde aire"], "bad": ["Hacinados: salud −6", "Oxígeno −6"],
					"fx": {"o2": -6.0, "health": -6.0, "score": 10}, "result": "Cierras la compuerta a tiempo, pero queda menos espacio para vivir."},
				{"label": "Subir el soporte vital al máximo", "good": ["Compensas el aire (+6)"], "bad": ["−80 de energía", "Soporte vital −12"],
					"fx": {"o2": 6.0, "energy": -80.0, "ls_cond": -12.0, "score": 5}, "result": "El soporte vital repone el aire, pero se desgasta y gasta mucha energía."},
			],
			"timeout": {"text": "La fuga siguió abierta: el aire de la base bajó mucho.",
				"fx": {"o2": -22.0, "ls_cond": -10.0, "health": -6.0, "score": -25}},
		},
		{
			"id": "shower", "icon": "🌠", "title": "LLUVIA DE METEOROS", "tier": 3, "seconds": 22.0, "verb": "OLEADA EN", "robot": "¡Muchas rocas espaciales! ¡Agárrense fuerte!",
			"desc": "Una lluvia de meteoroides cruza la órbita de la base. Habrá varios impactos seguidos.",
			"fact": "Los meteoroides suelen ser del tamaño de un grano de arena, pero viajan tan rápido que pueden dañar una nave.",
			"options": [
				{"label": "Escudos al máximo", "good": ["Los impactos rebotan"], "bad": ["−140 de energía", "Blindaje −6"],
					"fx": {"energy": -140.0, "shield": -6.0, "score": 20}, "result": "Los escudos resisten toda la lluvia, pero la batería se vacía."},
				{"label": "Toda la tripulación al refugio", "good": ["Nadie sufre daños"], "bad": ["Blindaje −20", "−40 materiales", "Salud −4"],
					"fx": {"shield": -20.0, "materials": -40.0, "health": -4.0, "score": 10}, "result": "La tripulación está a salvo; la base recibe golpes y pierde material."},
				{"label": "Seguir trabajando", "good": ["No pierdes horas de trabajo"], "bad": ["Blindaje −30", "Soporte vital −20", "−50 materiales"],
					"fx": {"shield": -30.0, "ls_cond": -20.0, "materials": -50.0, "score": -5}, "result": "Sigues con tus tareas, pero la base sufre mucho."},
			],
			"timeout": {"text": "La lluvia golpeó la base sin ninguna protección.",
				"fx": {"shield": -30.0, "ls_cond": -20.0, "health": -12.0, "materials": -50.0, "score": -30}},
		},
		{
			"id": "dust", "icon": "🌪️", "title": "TORMENTA DE POLVO MARCIANA", "tier": 2, "seconds": 30.0, "verb": "POLVO SOBRE LA BASE EN", "robot": "¡Una tormenta de polvo tapa los paneles!",
			"only": ["mars_outpost"],
			"desc": "Una tormenta de polvo reduce la eficiencia de los paneles solares. Administra la energía y protege los sistemas.",
			"fact": "En Marte las tormentas de polvo pueden durar semanas y obligaron a rovers solares a dormir para ahorrar energía.",
			"options": [
				{"label": "Modo ahorro y proteger sistemas", "good": ["Ahorras 30 de energía"], "bad": ["Plantas −8", "Paneles al 50% por 2 turnos"],
					"fx": {"energy": 30.0, "plant_health": -8.0, "solar": [0.5, 2], "score": 10}, "result": "Con el modo ahorro, la base aguanta mientras pasa el polvo."},
				{"label": "Limpiar los paneles (salida EVA)", "good": ["Los paneles recuperan 80%"], "bad": ["−4 horas de trabajo este turno", "−20 de energía"],
					"fx": {"hours": 4, "energy": -20.0, "solar": [0.8, 2], "score": 15}, "result": "La limpieza devuelve casi toda la luz, a cambio de tiempo."},
				{"label": "Usar la reserva de emergencia", "good": ["Todo sigue a pleno rendimiento"], "bad": ["Gastas 110 de reserva", "Paneles al 50% por 2 turnos"],
					"fx": {"backup": -110.0, "solar": [0.5, 2], "score": 5}, "result": "Pasas la tormenta sin apagar nada, con menos reserva."},
			],
			"timeout": {"text": "El polvo cubrió los paneles sin que nadie reaccionara.",
				"fx": {"energy": -60.0, "ls_cond": -8.0, "solar": [0.4, 3], "score": -20}},
		},
	]


static func by_id(id: String) -> Dictionary:
	for e in catalog():
		if str(e["id"]) == id:
			return e
	return {}


const ICONS := {
	"energy": "⚡", "backup": "🔋", "materials": "🧱", "exposure": "☢️", "o2": "💨", "water": "💧", "ls_cond": "🛠️",
	"shield": "🛡️", "shelter": "🏠", "food": "🍎", "plant_health": "🌱", "health": "❤️", "hours": "⏱️", "solar": "☀️",
}


## Efectos de una opcion como iconos con numero, para comparar de un vistazo: [{icon, num, good}].
static func chips_for(fx: Dictionary) -> Array:
	var out: Array = []
	for key in fx:
		var k := str(key)
		if k == "score":
			continue
		if k == "hours":
			out.append({"icon": ICONS[k], "num": "−%dh" % int(fx[k]), "good": false})
		elif k == "solar":
			out.append({"icon": ICONS[k], "num": "%d%%" % int(round(float((fx[k] as Array)[0]) * 100.0)), "good": false})
		else:
			var d := float(fx[k])
			var bad := d > 0.0 if k == "exposure" else d < 0.0
			out.append({"icon": ICONS.get(k, "•"), "num": ("+" if d > 0.0 else "−") + str(int(round(absf(d)))), "good": not bad})
	return out


## Aplica un diccionario de efectos al estado. Devuelve las lineas de resultado: [{text, good, icon, num}].
## Respeta limites (nunca provoca la derrota por si sola) y, en el modo 7-9 anos, suaviza las perdidas.
static func apply(s: BaseState, fx: Dictionary) -> Array:
	var lines: Array = []
	for key in fx:
		var k := str(key)
		if k == "score":
			continue
		if k == "hours":
			var h := int(fx[k])
			if h > 0:
				s.hours_penalty += h
				lines.append({"text": "−%d h de trabajo este turno" % h, "good": false, "icon": ICONS["hours"], "num": "−%dh" % h})
			continue
		if k == "solar":
			var arr: Array = fx[k]
			var mult := float(arr[0])
			var turns := int(arr[1])
			s.solar_event_mult = minf(s.solar_event_mult, mult)
			s.solar_event_turns = maxi(s.solar_event_turns, turns)
			lines.append({"text": "☀ Paneles al %d%% durante %d turno%s" % [int(round(mult * 100.0)), turns, "" if turns == 1 else "s"], "good": false, "icon": ICONS["solar"], "num": "%d%%" % int(round(mult * 100.0))})
			continue
		var d := float(fx[k])
		if s.easy and ((d < 0.0 and k != "exposure") or (d > 0.0 and k == "exposure")):
			d *= EASY_RELIEF
		var before := _read(s, k)
		_write(s, k, before + d)
		var delta := _read(s, k) - before
		if absf(delta) >= 0.5:
			var bad := delta > 0.0 if k == "exposure" else delta < 0.0
			lines.append({"text": "%s %s%d" % [LABELS.get(k, k), "+" if delta > 0.0 else "−", int(round(absf(delta)))], "good": not bad,
					"icon": ICONS.get(k, "•"), "num": ("+" if delta > 0.0 else "−") + str(int(round(absf(delta))))})
	return lines


static func _read(s: BaseState, k: String) -> float:
	match k:
		"energy": return s.main + s.backup
		"backup": return s.backup
		"materials": return s.materials
		"exposure": return s.exposure
		"o2": return s.o2
		"water": return s.water
		"ls_cond": return s.ls_cond
		"shield": return s.shield
		"shelter": return s.shelter
		"food": return s.food
		"plant_health": return s.plant_health
		"health": return s.health
	return 0.0


static func _write(s: BaseState, k: String, v: float) -> void:
	match k:
		"energy":
			var cur := s.main + s.backup
			if v >= cur:   # ganar energia: va a la bateria principal
				s.main = minf(SimConfig.MAIN_CAP, s.main + (v - cur))
			else:          # perderla: primero la principal y luego la reserva
				var loss := cur - maxf(0.0, v)
				var from_main := minf(s.main, loss)
				s.main -= from_main
				s.backup = maxf(0.0, s.backup - (loss - from_main))
		"backup": s.backup = clampf(v, 0.0, SimConfig.BACKUP_CAP)
		"materials": s.materials = maxf(0.0, v)
		"exposure": s.exposure = clampf(v, 0.0, EXPOSURE_CEIL)
		"o2": s.o2 = clampf(v, float(FLOORS["o2"]), 100.0)
		"water": s.water = clampf(v, float(FLOORS["water"]), 100.0)
		"ls_cond": s.ls_cond = clampf(v, float(FLOORS["ls_cond"]), 100.0)
		"shield": s.shield = clampf(v, float(FLOORS["shield"]), 100.0)
		"shelter": s.shelter = clampf(v, float(FLOORS["shelter"]), 100.0)
		"food": s.food = clampf(v, 0.0, 100.0)
		"plant_health": s.plant_health = clampf(v, float(FLOORS["plant_health"]), 100.0)
		"health": s.health = clampf(v, float(FLOORS["health"]), 100.0)


## Resuelve una alerta: idx = opcion elegida, o -1 si se acabo el tiempo. `time_left_frac` = fraccion de tiempo que sobraba.
## Aplica los efectos, suma la puntuacion y deja constancia en s.alert_log.
static func resolve(s: BaseState, ev: Dictionary, idx: int, time_left_frac: float = 0.0) -> Dictionary:
	var timed_out := idx < 0
	var fx: Dictionary
	var choice: String
	var text: String
	if timed_out:
		var t: Dictionary = ev["timeout"]
		fx = t["fx"]
		choice = "Sin respuesta a tiempo"
		text = str(t["text"])
	else:
		var o: Dictionary = (ev["options"] as Array)[idx]
		fx = o["fx"]
		choice = str(o["label"])
		text = str(o["result"])
	var lines := apply(s, fx)
	var bonus := SPEED_BONUS if (not timed_out and time_left_frac >= 0.5) else 0
	var score := int(fx.get("score", 0)) + bonus
	s.alert_score += score
	s.alert_log.append({"turn": s.turn, "id": str(ev["id"]), "title": str(ev["title"]), "choice": choice, "timed_out": timed_out, "score": score})
	return {"timed_out": timed_out, "choice": choice, "text": text, "lines": lines, "score": score, "bonus": bonus}
