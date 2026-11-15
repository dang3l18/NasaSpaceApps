class_name NasaBridge
extends RefCounted
## Puente entre los datos de NASA y las variables de la simulacion.
## Regla: nunca se convierte una actividad solar registrada en una dosis real. La clase del
## evento DONKI solo elige un NIVEL DE ALERTA (1-3), que es un PARAMETRO DE SIMULACION.
## Algunas misiones (p. ej. «Tormenta en el Horizonte») fijan un nivel minimo de alerta como
## ESCENARIO EDUCATIVO; en ese caso el dato se rotula como SIMULACION EDUCATIVA, no como real.

static var event: Dictionary = {}     # ultimo resultado de ScientificDataManager.build_solar_event()
static var forced_min: int = 0        # nivel minimo de alerta que impone la mision (0 = ninguno)


static func has_real_event() -> bool:
	return not event.is_empty() and not event.get("is_fallback", true)


## Nivel segun los datos (2 por defecto si no hay datos), sin el escenario de la mision.
static func data_tier() -> int:
	if not has_real_event():
		return 2
	return clampi(int(event["record"].get("severity", 2)), 1, 3)


## Nivel de alerta 1-3 que usa la simulacion.
static func alert_tier() -> int:
	return maxi(data_tier(), forced_min)


static func is_forced() -> bool:
	return forced_min > data_tier() or (forced_min > 0 and not has_real_event())


static func label() -> String:
	if event.is_empty() or is_forced():
		return ScientificDataManager.LABEL_SIM
	return str(event.get("classification", ScientificDataManager.LABEL_SIM))


## Texto corto: que variable modifica el dato y por que.
static func mapping_text() -> String:
	var tier := alert_tier()
	if is_forced():
		var ctx := ""
		if has_real_event():
			ctx = " DONKI reciente: «%s», que por sí sola daría el nivel %d." % [str(event["record"].get("class_type", event["record"].get("title", "evento"))), data_tier()]
		return "Escenario educativo: esta misión fija la alerta en nivel %d, inspirada en tormentas solares reales.%s Es un parámetro de simulación (SIMULACIÓN EDUCATIVA), no una dosis real." % [tier, ctx]
	if not has_real_event():
		return "Sin datos de DONKI: se usa una alerta de práctica (nivel %d). Es un parámetro de simulación." % tier
	var r: Dictionary = event["record"]
	var what: String = str(r.get("class_type", r.get("title", "evento")))
	return "DONKI registró «%s». El juego lo traduce al nivel de alerta %d (parámetro de simulación). Modifica la exposición de radiación del turno de la alerta. No es una dosis real." % [what, tier]


static func headline() -> String:
	if is_forced():
		return "Tormenta solar de nivel %d (escenario educativo)" % alert_tier()
	if not has_real_event():
		return "Alerta solar de práctica"
	var r: Dictionary = event["record"]
	return "%s (%s)" % [r["title"], Time.get_date_string_from_unix_time(int(r["event_time"]))]
