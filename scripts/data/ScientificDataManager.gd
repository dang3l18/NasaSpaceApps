extends Node
## Normaliza datos cientificos externos a un formato unico, identifica la fuente y
## clasifica cada dato: DATO REAL / DATO HISTORICO / SIMULACION EDUCATIVA.
##
## Regla de clasificacion (nada se presenta como actual si no lo es):
##   - DATO REAL:      evento de <= 7 dias Y consulta de <= 6 h (red o cache vigente).
##   - DATO HISTORICO: el resto (evento antiguo o copia en cache vieja).
##   - SIMULACION EDUCATIVA: modelos (WSA-Enlil) o escenario de respaldo sin datos.

const LABEL_REAL := "DATO REAL"
const LABEL_HISTORIC := "DATO HISTÓRICO"
const LABEL_SIM := "SIMULACIÓN EDUCATIVA"

const REAL_EVENT_MAX_AGE := 7 * 86400
const REAL_QUERY_MAX_AGE := 6 * 3600
const SOLAR_WINDOW_DAYS := 30
const DONKI_DATASET_IDS := {
	"CME": "donki_cme", "FLR": "donki_flr", "GST": "donki_gst", "SEP": "donki_sep",
	"WSAEnlilSimulations": "donki_wsa", "notifications": "donki_notifications",
}


# ------------------------------------------------------------- UTILIDADES ----

## Convierte "2026-11-10T14:36Z" / "2026-11-10T14:36:00Z" a unix (UTC). -1 si falla.
static func parse_iso(s: Variant) -> float:
	if s == null:
		return -1.0
	var t := str(s).replace("Z", "").strip_edges()
	if t.length() == 16:   # YYYY-MM-DDTHH:MM
		t += ":00"
	if t.length() < 19:
		return -1.0
	return float(Time.get_unix_time_from_datetime_string(t.substr(0, 19)))


static func classify(event_unix: float, retrieved_unix: float, simulated: bool = false) -> String:
	if simulated:
		return LABEL_SIM
	var now := Time.get_unix_time_from_system()
	if event_unix > 0 and now - event_unix <= REAL_EVENT_MAX_AGE and now - retrieved_unix <= REAL_QUERY_MAX_AGE:
		return LABEL_REAL
	return LABEL_HISTORIC


# ---------------------------------------------------------- NORMALIZACION ----

## Convierte la respuesta de NASADataManager.donki() en registros comunes.
func normalize_donki(kind: String, res: Dictionary) -> Array:
	var out: Array = []
	if not res.get("ok", false) or not (res.get("data") is Array):
		return out
	var retrieved: float = res["retrieved_at"]
	for item in res["data"]:
		if not (item is Dictionary):
			continue
		var rec := _normalize_one(kind, item, retrieved)
		if not rec.is_empty():
			rec["origin"] = res["origin"]
			out.append(rec)
	return out


func _normalize_one(kind: String, it: Dictionary, retrieved: float) -> Dictionary:
	var rec := {
		"source": "NASA DONKI", "dataset_id": DONKI_DATASET_IDS.get(kind, ""), "kind": kind,
		"retrieved_at": retrieved, "link": str(it.get("link", "")),
		"severity": 0, "id": "", "title": "", "summary": "", "event_time": -1.0,
	}
	var simulated := false
	match kind:
		"FLR":
			var cls := str(it.get("classType", "?"))
			rec["id"] = str(it.get("flrID", ""))
			rec["event_time"] = parse_iso(it.get("peakTime", it.get("beginTime")))
			rec["title"] = "Llamarada solar clase %s" % cls
			rec["summary"] = "Región activa %s, ubicación %s." % [str(int(it["activeRegionNum"])) if it.get("activeRegionNum") != null else "n/d", str(it.get("sourceLocation", "n/d"))]
			rec["severity"] = 3 if cls.begins_with("X") else (2 if cls.begins_with("M") else (1 if cls.begins_with("C") else 0))
			rec["class_type"] = cls
		"CME":
			rec["id"] = str(it.get("activityID", ""))
			rec["event_time"] = parse_iso(it.get("startTime"))
			var speed := 0.0
			var earth := false
			for a in it.get("cmeAnalyses", []) if it.get("cmeAnalyses") is Array else []:
				if a is Dictionary:
					speed = maxf(speed, float(a.get("speed", 0.0) if a.get("speed") != null else 0.0))
					for e in a.get("enlilList", []) if a.get("enlilList") is Array else []:
						if e is Dictionary and e.get("isEarthGB", false):
							earth = true
			rec["title"] = "Eyección de masa coronal (CME)"
			rec["summary"] = "Velocidad estimada: %s km/s. %s" % [("%d" % speed) if speed > 0 else "n/d", "Con componente hacia la Tierra según el modelo." if earth else "Sin impacto terrestre indicado."]
			rec["severity"] = 3 if speed >= 1500 else (2 if speed >= 1000 else (1 if speed >= 500 else 0))
			if earth:
				rec["severity"] = mini(3, int(rec["severity"]) + 1)
			rec["speed"] = speed
		"GST":
			rec["id"] = str(it.get("gstID", ""))
			rec["event_time"] = parse_iso(it.get("startTime"))
			var kp := 0.0
			for k in it.get("allKpIndex", []) if it.get("allKpIndex") is Array else []:
				if k is Dictionary:
					kp = maxf(kp, float(k.get("kpIndex", 0.0)))
			rec["title"] = "Tormenta geomagnética (Kp máx. %s)" % ("%.1f" % kp if kp > 0 else "n/d")
			rec["summary"] = "Perturbación del campo magnético terrestre observada."
			rec["severity"] = 3 if kp >= 7 else (2 if kp >= 5 else 1)
			rec["kp"] = kp
		"SEP":
			rec["id"] = str(it.get("sepID", ""))
			rec["event_time"] = parse_iso(it.get("eventTime"))
			rec["title"] = "Partículas solares energéticas (SEP)"
			rec["summary"] = "Aumento de radiación de protones: riesgo para tripulación en el espacio."
			rec["severity"] = 2
		"WSAEnlilSimulations":
			rec["id"] = str(it.get("simulationID", ""))
			rec["event_time"] = parse_iso(it.get("modelCompletionTime"))
			rec["title"] = "Simulación WSA-Enlil del viento solar"
			rec["summary"] = "Resultado de modelo numérico, no una medición."
			simulated = true
		"notifications":
			rec["id"] = str(it.get("messageID", ""))
			rec["event_time"] = parse_iso(it.get("messageIssueTime"))
			rec["title"] = "Notificación: %s" % str(it.get("messageType", "n/d"))
			rec["summary"] = str(it.get("messageBody", "")).strip_edges().left(500)
			rec["link"] = str(it.get("messageURL", ""))
		_:
			return {}
	rec["classification"] = classify(rec["event_time"], retrieved, simulated)
	return rec


# ----------------------------------------- CONTEXTO EDUCATIVO (EARTHDATA) ----

const LIS_SHORT_NAME := "isslis_v3_fin"

## Metadatos reales del sensor de rayos de la ISS (NASA Earthdata CMR).
## Devuelve {ok, record, connection, error}. El conjunto cubre 2017-2023 (mision terminada),
## por lo que SIEMPRE se clasifica como DATO HISTORICO; nunca se presenta como actual.
func get_station_context() -> Dictionary:
	var res: Dictionary = await NASADataManager.cmr_collection(LIS_SHORT_NAME)
	var st: Dictionary = NASADataManager.status.get("CMR_" + LIS_SHORT_NAME, {})
	var entries: Array = []
	if res.get("ok", false) and res["data"] is Dictionary:
		var feed = res["data"].get("feed", {})
		if feed is Dictionary and feed.get("entry") is Array:
			entries = feed["entry"]
	if entries.is_empty() or not (entries[0] is Dictionary):
		DatasetManager.report("cmr_isslis", {
			"connection": st.get("state", "offline"), "note": st.get("message", "Sin resultados"),
			"classification": "SIN DATOS", "queried_at": res.get("retrieved_at", 0.0),
			"data_date": "-", "origin": res.get("origin", "none"),
		})
		return {"ok": false, "record": {}, "connection": st.get("state", "offline"), "error": res.get("error", "Sin resultados")}

	var e: Dictionary = entries[0]
	var link_data := ""
	var link_docs: Array = []
	for l in e.get("links", []) if e.get("links") is Array else []:
		if not (l is Dictionary):
			continue
		var rel := str(l.get("rel", ""))
		var href := str(l.get("href", ""))
		if rel.ends_with("/data#") and link_data == "":
			link_data = href
		elif rel.ends_with("/documentation#") and link_docs.size() < 3:
			link_docs.append(href)
	var rec := {
		"source": "NASA Earthdata CMR", "dataset_id": "cmr_isslis", "kind": "collection",
		"id": str(e.get("id", "")), "short_name": str(e.get("short_name", "")),
		"title": str(e.get("title", "")), "summary_original": str(e.get("summary", "")),
		"language_original": "en",
		"platform": ", ".join(PackedStringArray(e.get("platforms", []))),
		"data_center": str(e.get("data_center", "")),
		"coverage_start": parse_iso(e.get("time_start")), "coverage_end": parse_iso(e.get("time_end")),
		"retrieved_at": res["retrieved_at"], "origin": res["origin"],
		"link": link_data, "docs": link_docs,
		"classification": LABEL_HISTORIC,
	}
	rec["event_time"] = rec["coverage_end"]
	DatasetManager.report("cmr_isslis", {
		"connection": st.get("state", "offline"), "note": st.get("message", ""),
		"classification": LABEL_HISTORIC, "queried_at": res["retrieved_at"], "origin": res["origin"],
		"data_date": "Cobertura %s a %s" % [_day(rec["coverage_start"]), _day(rec["coverage_end"])],
	})
	return {"ok": true, "record": rec, "connection": st.get("state", "cache"), "error": ""}


## Consulta notificaciones y simulaciones WSA-Enlil de DONKI solo para informar al panel.
func refresh_donki_extras() -> void:
	for kind in ["notifications", "WSAEnlilSimulations"]:
		var res: Dictionary = await NASADataManager.donki(kind, SOLAR_WINDOW_DAYS)
		_report_donki(kind, res, normalize_donki(kind, res))


# --------------------------------- CONTRASTE GEOMAGNETICO (NOAA SWPC) ----

## Segunda fuente (agencia aliada: NOAA SWPC, EE. UU.) para contrastar DONKI.
## Devuelve {ok, kp_now, kp_time, kp_max_72h, g_scale, s_scale, r_scale, classification,
## origin, connection, comparison}. `donki_gst` = registros ya normalizados de DONKI (opcional).
func get_geomagnetic_crosscheck(donki_gst: Array = []) -> Dictionary:
	var kp_res: Dictionary = await NASADataManager.noaa("noaa-planetary-k-index")
	var sc_res: Dictionary = await NASADataManager.noaa("noaa-scales")
	var st: Dictionary = NASADataManager.status.get("NOAA_noaa-planetary-k-index", {})
	var kp_list: Array = kp_res["data"] if kp_res.get("ok", false) and kp_res["data"] is Array else []
	if kp_list.is_empty():
		DatasetManager.report("noaa_swpc", {
			"connection": st.get("state", "offline"), "note": st.get("message", "Sin datos"),
			"classification": "SIN DATOS", "queried_at": kp_res.get("retrieved_at", 0.0),
			"data_date": "-", "origin": kp_res.get("origin", "none"),
		})
		return {"ok": false, "error": kp_res.get("error", "Sin datos"), "connection": st.get("state", "offline")}

	var now_unix := Time.get_unix_time_from_system()
	var last: Dictionary = kp_list[kp_list.size() - 1]
	var kp_time := parse_iso(last.get("time_tag"))
	var kp_max := 0.0
	for k in kp_list:
		if k is Dictionary:
			var t := parse_iso(k.get("time_tag"))
			if t > 0 and now_unix - t <= 72 * 3600:
				kp_max = maxf(kp_max, float(k.get("Kp", 0.0)))

	var g := "n/d"
	var s := "n/d"
	var r := "n/d"
	if sc_res.get("ok", false) and sc_res["data"] is Dictionary and sc_res["data"].get("0") is Dictionary:
		var cur: Dictionary = sc_res["data"]["0"]
		g = _scale(cur, "G")
		s = _scale(cur, "S")
		r = _scale(cur, "R")

	var retrieved: float = kp_res["retrieved_at"]
	var label := classify(kp_time, retrieved)
	var comparison := "NOAA: Kp actual %.1f (escala G%s), máximo en 72 h: %.1f." % [float(last.get("Kp", 0.0)), g, kp_max]
	if donki_gst.is_empty():
		comparison += " DONKI no reporta tormentas geomagnéticas en la ventana consultada."
	else:
		var newest := -1.0
		for d in donki_gst:
			newest = maxf(newest, float(d["event_time"]))
		comparison += " DONKI: última tormenta geomagnética el %s." % Time.get_datetime_string_from_unix_time(int(newest), true)
	DatasetManager.report("noaa_swpc", {
		"connection": st.get("state", "offline"), "note": st.get("message", ""),
		"classification": label, "queried_at": retrieved, "origin": kp_res["origin"],
		"data_date": Time.get_datetime_string_from_unix_time(int(kp_time), true) + " UTC",
	})
	return {
		"ok": true, "kp_now": float(last.get("Kp", 0.0)), "kp_time": kp_time, "kp_max_72h": kp_max,
		"g_scale": g, "s_scale": s, "r_scale": r, "classification": label,
		"origin": kp_res["origin"], "connection": st.get("state", "cache"), "comparison": comparison,
		"source": "NOAA SWPC", "link": "https://www.swpc.noaa.gov/",
	}


static func _scale(cur: Dictionary, key: String) -> String:
	var e = cur.get(key)
	if e is Dictionary and e.get("Scale") != null:
		return str(e["Scale"])
	return "n/d"


static func _day(unix: float) -> String:
	return Time.get_date_string_from_unix_time(int(unix)) if unix > 0 else "n/d"


# ------------------------------------------------------- EVENTO DE LA MISION ----

# ----------------------------------------------- ARCHIVO DONKI 2025-2026 ----

signal history_progress(done: int, total: int)
signal history_ready

const HISTORY_FROM := "2025-01-01"
const CHUNK_DAYS := 30                 # maximo que acepta DONKI por consulta
const CHUNK_TTL_CLOSED := 90 * 86400   # tramos cerrados: no cambian
const KINDS_HISTORY := ["FLR", "CME", "GST", "SEP"]

var history: Array = []                # registros normalizados 2025-2026
var history_stats: Dictionary = {}
var history_loaded := false
var _history_loading := false


## Descarga por tramos de 30 dias todos los eventos DONKI desde 2025 hasta hoy (cache en disco).
## Seguro de llamar varias veces: si ya esta cargando, espera. Nunca bloquea la mision.
func ensure_history() -> void:
	if history_loaded:
		return
	if _history_loading:
		await history_ready
		return
	_history_loading = true
	var start := int(Time.get_unix_time_from_datetime_string(HISTORY_FROM + "T00:00:00"))
	var now := int(Time.get_unix_time_from_system())
	var starts: Array = []
	var s := start
	while s <= now:
		starts.append(s)
		s += CHUNK_DAYS * 86400
	var total := starts.size() * KINDS_HISTORY.size()
	var done := 0
	var seen := {}
	var all: Array = []
	for cs in starts:
		var ce := mini(cs + (CHUNK_DAYS - 1) * 86400, now)
		var is_current: bool = cs + CHUNK_DAYS * 86400 > now
		for kind in KINDS_HISTORY:
			var res: Dictionary = await NASADataManager.donki_range(kind, cs, ce,
					NASADataManager.DONKI_TTL if is_current else CHUNK_TTL_CLOSED, "donki_%s_%d" % [kind, cs])
			for r in normalize_donki(kind, res):
				if not seen.has(r["id"]):
					seen[r["id"]] = true
					all.append(r)
			done += 1
			history_progress.emit(done, total)
	history = all
	history_stats = _compute_stats(all)
	history_loaded = true
	_history_loading = false
	history_ready.emit()


func _compute_stats(recs: Array) -> Dictionary:
	var st := {"total": recs.size(), "by_year": {}, "x_flares": 0, "m_flares": 0, "storms": 0, "g4_plus": 0,
			"max_kp": 0.0, "cmes": 0, "fast_cmes": 0, "seps": 0, "first": -1.0, "last": -1.0}
	for r in recs:
		var year := str(Time.get_datetime_dict_from_unix_time(int(r["event_time"]))["year"])
		st["by_year"][year] = int(st["by_year"].get(year, 0)) + 1
		st["first"] = r["event_time"] if st["first"] < 0 else minf(st["first"], r["event_time"])
		st["last"] = maxf(st["last"], r["event_time"])
		match r["kind"]:
			"FLR":
				var c := str(r.get("class_type", ""))
				if c.begins_with("X"): st["x_flares"] += 1
				elif c.begins_with("M"): st["m_flares"] += 1
			"GST":
				st["storms"] += 1
				st["max_kp"] = maxf(st["max_kp"], float(r.get("kp", 0.0)))
				if float(r.get("kp", 0.0)) >= 8.0: st["g4_plus"] += 1
			"CME":
				st["cmes"] += 1
				if float(r.get("speed", 0.0)) >= 1000.0: st["fast_cmes"] += 1
			"SEP":
				st["seps"] += 1
	return st


## Texto de contexto con cifras reales calculadas del archivo (nada inventado).
func history_summary() -> String:
	if not history_loaded or history.is_empty():
		return ""
	var s := history_stats
	return "Desde %s, NASA DONKI registra %d llamaradas clase X, %d clase M, %d tormentas geomagnéticas (Kp máx. %.1f), %d CME (%d rápidas, ≥1000 km/s) y %d eventos de partículas solares. Eventos por año: %s. [%s · NASA DONKI]" % [
		_day(s["first"]), s["x_flares"], s["m_flares"], s["storms"], s["max_kp"], s["cmes"], s["fast_cmes"], s["seps"],
		", ".join(PackedStringArray(s["by_year"].keys().map(func(y): return "%s: %d" % [y, s["by_year"][y]]))),
		LABEL_HISTORIC]


## Evento mas significativo del archivo (severidad, luego el mas reciente).
func _pick_from_history() -> Dictionary:
	var best: Dictionary = {}
	for r in history:
		if int(r["severity"]) < 2 or r["event_time"] <= 0:
			continue
		if best.is_empty() or int(r["severity"]) > int(best["severity"]) \
				or (int(r["severity"]) == int(best["severity"]) and r["event_time"] > best["event_time"]):
			best = r
	return best


## Construye el evento de actividad solar de la mision a partir de DONKI.
## Devuelve {record, classification, is_fallback, explanation, connection, sources}.
## Nunca falla: sin datos devuelve un escenario SIMULACION EDUCATIVA claramente rotulado.
## Si la ultima ventana (30 dias) no tiene un evento de severidad >= 2 y el archivo 2025-2026
## esta cargado, se usa el evento mas fuerte del archivo, rotulado DATO HISTORICO.
func build_solar_event() -> Dictionary:
	var records: Array = []
	var connection := "offline"
	var any_ok := false
	for kind in ["FLR", "CME", "GST", "SEP"]:
		var res: Dictionary = await NASADataManager.donki(kind, SOLAR_WINDOW_DAYS)
		var recs := normalize_donki(kind, res)
		records.append_array(recs)
		any_ok = any_ok or res.get("ok", false)
		_report_donki(kind, res, recs)
		if res.get("ok", false):
			var origin: String = res["origin"]
			if origin == "network" or (origin == "cache_fresh" and connection != "online"):
				connection = "online" if origin == "network" else "cache"
			elif connection == "offline":
				connection = "cache"

	var best := _pick_best(records)
	if (best.is_empty() or int(best["severity"]) < 2) and history_loaded:
		var h := _pick_from_history()
		if not h.is_empty():
			best = h
			best["classification"] = LABEL_HISTORIC   # del archivo: nunca "real"
			any_ok = true
			connection = connection if connection != "offline" else "cache"
	if best.is_empty():
		var msg := "No hay eventos solares en los últimos %d días." % SOLAR_WINDOW_DAYS if any_ok else "Sin conexión ni caché de DONKI."
		return {
			"record": {}, "classification": LABEL_SIM, "is_fallback": true, "connection": connection,
			"explanation": "%s Se usa un escenario de práctica: una tormenta solar educativa, no un evento real." % msg,
			"sources": [],
		}
	return {
		"record": best, "classification": best["classification"], "is_fallback": false,
		"connection": connection, "explanation": _explain(best), "sources": ["NASA DONKI"],
	}


func _pick_best(records: Array) -> Dictionary:
	var best: Dictionary = {}
	var now := Time.get_unix_time_from_system()
	for r in records:
		if r["classification"] == LABEL_SIM or r["event_time"] <= 0:
			continue
		if best.is_empty():
			best = r
			continue
		# Preferimos eventos recientes (<=14 dias); dentro de ellos, mayor severidad y mas nuevos.
		var r_recent: bool = now - float(r["event_time"]) <= 14 * 86400
		var b_recent: bool = now - float(best["event_time"]) <= 14 * 86400
		if r_recent != b_recent:
			if r_recent:
				best = r
		elif int(r["severity"]) > int(best["severity"]) or (int(r["severity"]) == int(best["severity"]) and r["event_time"] > best["event_time"]):
			best = r
	return best


func _explain(r: Dictionary) -> String:
	var when := Time.get_datetime_string_from_unix_time(int(r["event_time"]), true) + " UTC"
	var why: String = {
		"FLR": "Una llamarada es una explosión en el Sol que libera radiación. Los rayos X llegan en minutos y pueden afectar las comunicaciones.",
		"CME": "Una CME es una nube de plasma lanzada por el Sol. Si llega a la Tierra puede aumentar la radiación y perturbar satélites.",
		"GST": "Una tormenta geomagnética ocurre cuando el viento solar sacude el campo magnético de la Tierra.",
		"SEP": "Las partículas solares energéticas son protones muy rápidos. Por eso los astronautas se protegen en zonas con más blindaje.",
	}.get(r["kind"], "")
	return "%s — %s. %s %s [%s · fuente: NASA DONKI, ID %s]" % [r["title"], when, r["summary"], why, r["classification"], r["id"]]


func _report_donki(kind: String, res: Dictionary, recs: Array) -> void:
	var ds_id: String = DONKI_DATASET_IDS.get(kind, "")
	if ds_id == "":
		return
	var st: Dictionary = NASADataManager.status.get("DONKI_" + kind, {})
	var latest := -1.0
	for r in recs:
		latest = maxf(latest, float(r["event_time"]))
	var label := "SIN DATOS" if recs.is_empty() else LABEL_HISTORIC
	if kind == "WSAEnlilSimulations":
		label = LABEL_SIM
	elif not recs.is_empty():
		label = classify(latest, res.get("retrieved_at", 0.0))
	var archive_n := 0
	for r in history:
		if r["kind"] == kind:
			archive_n += 1
	var archive := (" · archivo %s→hoy: %d eventos" % [HISTORY_FROM, archive_n]) if history_loaded else ""
	DatasetManager.report(ds_id, {
		"connection": st.get("state", "offline"),
		"note": st.get("message", ""),
		"classification": label,
		"queried_at": res.get("retrieved_at", 0.0),
		"data_date": (("último en 30 días: " + Time.get_datetime_string_from_unix_time(int(latest), true) + " UTC") if latest > 0 else "sin eventos en los últimos 30 días") + archive,
		"origin": res.get("origin", "none"),
		"count": recs.size(),
	})
