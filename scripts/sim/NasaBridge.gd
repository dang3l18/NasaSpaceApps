class_name NasaBridge
extends RefCounted
## Puente entre los datos de NASA y las variables de la simulacion.
## Regla: nunca se convierte una actividad solar registrada en una dosis real. La clase del
## evento DONKI solo elige un NIVEL DE ALERTA (1-3), que es un PARAMETRO DE SIMULACION.

static var event: Dictionary = {}     # ultimo resultado de ScientificDataManager.build_solar_event()


static func has_real_event() -> bool:
	return not event.is_empty() and not event.get("is_fallback", true)


## Nivel de alerta 1-3 usado por la simulacion (2 por defecto si no hay datos).
static func alert_tier() -> int:
	if not has_real_event():
		return 2
	return clampi(int(event["record"].get("severity", 2)), 1, 3)


static func label() -> String:
	if event.is_empty():
		return ScientificDataManager.LABEL_SIM
	return str(event.get("classification", ScientificDataManager.LABEL_SIM))


## Texto corto: que variable modifica el dato y por que.
static func mapping_text() -> String:
	var tier := alert_tier()
	if not has_real_event():
		return "Sin datos de DONKI: se usa una alerta de práctica (nivel %d). Es un parámetro de simulación." % tier
	var r: Dictionary = event["record"]
	var what: String = str(r.get("class_type", r.get("title", "evento")))
	return "DONKI registró «%s». El juego lo traduce al nivel de alerta %d (parámetro de simulación). Modifica la exposición de radiación del turno %d. No es una dosis real." % [what, tier, SimConfig.ALERT_TURN]


static func headline() -> String:
	if not has_real_event():
		return "Alerta solar de práctica"
	var r: Dictionary = event["record"]
	return "%s (%s)" % [r["title"], Time.get_date_string_from_unix_time(int(r["event_time"]))]
