class_name GuideCoach
## Guia adaptativa del robot: lee las decisiones que tomo el jugador (BaseState.decisions / sacrifices)
## y el estado actual de la base para orientarle. Logica pura (sin nodos): se puede probar sin interfaz.
## Prioridad: 1) consecuencia de la decision reciente  2) punto mas debil  3) (lo decide LunarBase) consejo general.

const NAMES := {"vida": "SOPORTE VITAL", "proteccion": "PROTECCIÓN", "energia": "ENERGÍA", "alimentos": "ALIMENTOS"}
const FOLLOW_TURNS := 2   # cuantos turnos despues de decidir sigue comentando esa decision


## Texto de guia segun las decisiones del jugador, o "" si no hay nada especial que decir.
static func advice(s: BaseState) -> String:
	if s.decisions.is_empty():
		return ""
	var last: Dictionary = s.decisions[s.decisions.size() - 1]
	if s.turn - int(last["turn"]) <= FOLLOW_TURNS:
		var follow := _follow_up(s, last)
		if follow != "":
			return follow
	return _weak_point(s)


## Comenta la consecuencia de la ultima decision, adaptada a como va la base ahora.
static func _follow_up(s: BaseState, last: Dictionary) -> String:
	var sac := str(last.get("sacrifice", ""))
	var title := str(last["choice"])
	match sac:
		"alimentos":
			if s.plant_health < 60.0 or s.food < 40.0:
				return "Elegiste «%s»: las plantas lo notan (comida %d). En cuanto pase el aprieto, sube la luz LED y cuídalas." % [title, int(s.food)]
			return "Elegiste «%s» y las plantas aguantan. Recupera la luz cuando haya energía de sobra." % title
		"descanso":
			return "Apagaste el hogar: la tripulación pierde salud. Reactívalo apenas pase la tormenta y vigila SOPORTE VITAL."
		"obras":
			return "Sin control no puedes construir ni procesar. Guarda materiales y actívalo de nuevo cuando la energía lo permita."
		"reserva de emergencia":
			if s.backup < 150.0:
				return "Gastaste la reserva y ya queda poco (%d). Evita gastos grandes: una fuga ahora no tendría colchón." % int(s.backup)
			return "Usaste parte de la reserva. Mide cada gasto de energía hasta el final."
		"datos":
			var need := int(s.mission.win_extra.get("min_data", 0))
			if need > 0:
				return "Priorizaste el calor: llevas %d de %d paquetes de datos. Cuando la batería alcance, transmite." % [s.data_sent, need]
			return "Dejaste los datos para después: acuérdate de transmitirlos."
		"calefacción":
			return "Sin calefacción baja la salud (%d%%). Es un riesgo: enciéndela en cuanto puedas." % int(s.indicators()["vida"])
		"oxígeno de las plantas":
			return "El aire ahora depende del soporte vital (O₂ %d). Mantenlo y no gastes energía de más." % int(s.o2)
		"soporte vital":
			return "Priorizaste el sellado: vigila el aire (O₂ %d) y la energía del soporte vital." % int(s.o2)
	# Decision sin sacrificio: reconocer y apuntar a lo que quedo peor.
	var weakest := _weakest(s)
	return "Bien pensado: elegiste «%s». Mantén el rumbo, pero vigila %s (%d%%)." % [title, NAMES[weakest[0]], int(weakest[1])]


## Con 2 o mas decisiones, orienta hacia el indicador mas flojo si esta en zona de riesgo.
static func _weak_point(s: BaseState) -> String:
	if s.decisions.size() < 2:
		return ""
	var weakest := _weakest(s)
	if float(weakest[1]) >= 50.0:
		return ""
	var estilo := _style(s)
	return "%sTu punto más débil ahora es %s (%d%%). Dedica este turno a mejorarlo." % [estilo, NAMES[weakest[0]], int(weakest[1])]


## Estilo de juego segun lo sacrificado: devuelve una frase corta (o "").
static func _style(s: BaseState) -> String:
	var food_n := 0
	var safe_n := 0
	for x in s.sacrifices:
		if x == "alimentos" or x == "oxígeno de las plantas":
			food_n += 1
		elif x == "descanso" or x == "obras" or x == "calefacción" or x == "datos":
			safe_n += 1
	if food_n >= 2:
		return "Has protegido la energía a costa de las plantas. "
	if safe_n >= 2:
		return "Estás cuidando la energía recortando otros servicios. "
	return ""


static func _weakest(s: BaseState) -> Array:
	var ind := s.indicators()
	var best := "vida"
	for k in ind:
		if float(ind[k]) < float(ind[best]):
			best = k
	return [best, float(ind[best])]
