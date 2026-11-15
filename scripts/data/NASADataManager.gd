extends Node
## Capa HTTP unica del juego: peticiones, JSON, cache en disco y control de errores.
## Nunca bloquea la mision: todo es asincrono (await) y siempre devuelve un Dictionary.
##
## Resultado de get_json():
##   { ok: bool, data: Variant, origin: "network"|"cache_fresh"|"cache_stale"|"none",
##     retrieved_at: float (unix), code: int, error: String }

signal _done(key: String, result: Dictionary)
signal status_changed(source: String, status: Dictionary)

const USER_AGENT := "Zyranth/0.1 (educational game)"
const TIMEOUT_SEC := 8.0
const CACHE_DIR := "user://cache/json"
const DONKI_BASE := "https://api.nasa.gov/DONKI/"
const DONKI_CCMC_BASE := "https://ccmc.gsfc.nasa.gov/DONKI/WS/get/"
const DONKI_TTL := 3 * 3600
const DEFAULT_BACKOFF_SEC := 3600.0
const MAX_BODY_BYTES := 16 * 1024 * 1024

var api_key: String = "DEMO_KEY"
var using_demo_key: bool = true

## Ganchos de prueba (Fase H). Por defecto no cambian nada.
var simulate_offline: bool = false   # toda peticion falla como si no hubiera red
var force_stale: bool = false        # ignora el TTL de la cache (fuerza ir a la red)
var request_count: int = 0           # peticiones HTTP realmente lanzadas

var _inflight: Dictionary = {}
var _backoff_until: Dictionary = {}   # host -> unix time
## source -> {state: "online"|"cache"|"offline"|"rate_limited", code, message, at}
var status: Dictionary = {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	_load_api_key()
	if "--offline" in OS.get_cmdline_user_args():
		simulate_offline = true


func _load_api_key() -> void:
	# Prioridad: variable de entorno > user://nasa_config.cfg > config local (dev) > DEMO_KEY
	var env_key := OS.get_environment("NASA_API_KEY").strip_edges()
	if env_key != "":
		api_key = env_key
		using_demo_key = false
		return
	for path in ["user://nasa_config.cfg", "res://config/nasa_config.local.cfg"]:
		var cfg := ConfigFile.new()
		if cfg.load(path) == OK:
			var k := str(cfg.get_value("nasa", "api_key", "")).strip_edges()
			if k != "" and k != "TU_CLAVE_AQUI":
				api_key = k
				using_demo_key = false
				return
	api_key = "DEMO_KEY"
	using_demo_key = true


# ---------------------------------------------------------------- JSON ----

## Descarga JSON con cache. `secret_param` es el nombre del parametro que lleva la
## clave (se anade a la URL pero NUNCA se guarda en cache ni en logs).
## `cache_id` fija el nombre de cache (para que no dependa de las fechas).
func get_json(source: String, url: String, params: Dictionary = {}, ttl: int = 3600,
		secret_param: String = "", cache_id: String = "") -> Dictionary:
	var key := cache_id if cache_id != "" else _hash_key(url, params)
	var now := Time.get_unix_time_from_system()
	var cached := _read_cache(key)
	if not cached.is_empty() and not force_stale and now - float(cached.get("retrieved_at", 0)) < ttl:
		_set_status(source, "cache", 200, "Cache vigente")
		return _result(true, cached.get("data"), "cache_fresh", float(cached["retrieved_at"]), 200, "")

	# Evita peticiones duplicadas simultaneas a la misma clave.
	if _inflight.has(key):
		while true:
			var args = await _done
			if args[0] == key:
				return args[1]
	_inflight[key] = true
	var res := await _fetch_json(source, url, params, secret_param, key, cached)
	_inflight.erase(key)
	_done.emit(key, res)
	return res


func _fetch_json(source: String, url: String, params: Dictionary, secret_param: String,
		key: String, cached: Dictionary) -> Dictionary:
	var host := _host_of(url)
	var now := Time.get_unix_time_from_system()
	if float(_backoff_until.get(host, 0.0)) > now:
		var wait := int(float(_backoff_until[host]) - now)
		return _fallback(source, cached, 429, "Limite de peticiones; reintento en %d s" % wait, "rate_limited")

	var full_params := params.duplicate()
	if secret_param != "":
		full_params[secret_param] = api_key
	var raw := await _request(_build_url(url, full_params))

	if raw.error != "":
		return _fallback(source, cached, 0, raw.error, "offline")
	var code: int = raw.code
	if code == 429:
		var retry := _retry_after(raw.headers)
		_backoff_until[host] = Time.get_unix_time_from_system() + retry
		return _fallback(source, cached, 429, "HTTP 429 (limite de la API; clave demo=%s)" % str(using_demo_key), "rate_limited")
	if code < 200 or code >= 300:
		return _fallback(source, cached, code, "HTTP %d" % code, "offline")

	var text: String = (raw.body as PackedByteArray).get_string_from_utf8().strip_edges()
	var parsed: Variant = []
	if text != "":
		parsed = JSON.parse_string(text)
		if parsed == null and text != "null":
			return _fallback(source, cached, code, "Respuesta no es JSON valido", "offline")

	var t := Time.get_unix_time_from_system()
	_write_cache(key, {"retrieved_at": t, "params": params, "data": parsed})
	_set_status(source, "online", code, "OK")
	return _result(true, parsed, "network", t, code, "")


func _fallback(source: String, cached: Dictionary, code: int, message: String, state: String) -> Dictionary:
	if not cached.is_empty():
		_set_status(source, "cache", code, "%s - usando cache" % message)
		return _result(true, cached.get("data"), "cache_stale", float(cached.get("retrieved_at", 0)), code, message)
	_set_status(source, state, code, message)
	return _result(false, null, "none", 0.0, code, message)


# --------------------------------------------------------------- BYTES ----

## Descarga binaria (imagenes). Devuelve {ok, code, body, error}.
func get_bytes(source: String, url: String) -> Dictionary:
	var host := _host_of(url)
	if float(_backoff_until.get(host, 0.0)) > Time.get_unix_time_from_system():
		return {"ok": false, "code": 429, "body": PackedByteArray(), "error": "Limite de peticiones"}
	# Las imagenes pesan ~150 KB y GIBS a veces tarda: 20 s y un reintento ante fallo de red.
	var raw := await _request(url, 20.0)
	if raw.error != "" and not simulate_offline:
		raw = await _request(url, 20.0)
	if raw.error != "":
		_set_status(source, "offline", 0, raw.error)
		return {"ok": false, "code": 0, "body": PackedByteArray(), "error": raw.error}
	if raw.code == 429:
		_backoff_until[host] = Time.get_unix_time_from_system() + _retry_after(raw.headers)
	var ok: bool = raw.code >= 200 and raw.code < 300
	_set_status(source, "online" if ok else "offline", raw.code, "OK" if ok else "HTTP %d" % raw.code)
	return {"ok": ok, "code": raw.code, "body": raw.body, "error": "" if ok else "HTTP %d" % raw.code}


# ---------------------------------------------------------------- DONKI ----

## kind: CME, FLR, GST, SEP, WSAEnlilSimulations, notifications
func donki(kind: String, days: int = 30) -> Dictionary:
	var end_t := int(Time.get_unix_time_from_system())
	return await donki_range(kind, end_t - days * 86400, end_t, DONKI_TTL, "donki_" + kind)


## Consulta DONKI para [start_unix, end_unix]. DONKI acepta como maximo 30 dias por consulta
## (verificado 2026-11-14: mas de 30 dias -> HTTP 400), por eso el historial se pide por tramos.
func donki_range(kind: String, start_unix: int, end_unix: int, ttl: int, cache_id: String) -> Dictionary:
	var params := {
		"startDate": Time.get_date_string_from_unix_time(start_unix),
		"endDate": Time.get_date_string_from_unix_time(end_unix),
	}
	if kind == "notifications":
		params["type"] = "all"
	# Verificado 2026-11-14: /DONKI/FLR en api.nasa.gov responde 404 (incluso para mayo 2024),
	# pero el servicio original del CCMC si funciona y no requiere clave.
	# Verificado 2026-11-15: el CCMC responde a TODOS los tipos de DONKI (FLR, CME, GST, SEP, WSA-Enlil, notificaciones)
	# sin clave y con CORS abierto; en cambio api.nasa.gov con la clave de demostracion devuelve 429 casi al instante.
	# Por eso se usa el CCMC como fuente principal (no hace falta clave ni en la version web) y api.nasa.gov solo
	# como respaldo cuando la persona ha configurado su propia clave.
	var res: Dictionary = await get_json("DONKI_" + kind, DONKI_CCMC_BASE + kind, params, ttl, "", cache_id)
	if bool(res.get("ok", false)) and str(res.get("origin", "")) != "cache_stale":
		return res
	if kind != "FLR" and not using_demo_key:
		var alt: Dictionary = await get_json("DONKI_" + kind, DONKI_BASE + kind, params, ttl, "api_key", cache_id)
		if bool(alt.get("ok", false)):
			return alt
	return res


# ------------------------------------------------- EARTHDATA (CMR) ----

const CMR_URL := "https://cmr.earthdata.nasa.gov/search/collections.json"
const CMR_TTL := 7 * 86400   # los metadatos de una coleccion cambian muy rara vez

## Metadatos de una coleccion Earthdata por short_name (sin clave). Devuelve la
## respuesta cruda de get_json(): data = {feed: {entry: [...]}}.
func cmr_collection(short_name: String) -> Dictionary:
	return await get_json("CMR_" + short_name, CMR_URL,
			{"short_name": short_name, "page_size": 1}, CMR_TTL, "", "cmr_" + short_name)


# ------------------------------------------------ NOAA SWPC (aliada) ----

const NOAA_BASE := "https://services.swpc.noaa.gov/products/"
const NOAA_TTL := 30 * 60   # NOAA actualiza cada pocos minutos; 30 min evita peticiones repetidas

## product: "noaa-planetary-k-index" | "noaa-scales" | "alerts". Sin clave.
func noaa(product: String) -> Dictionary:
	return await get_json("NOAA_" + product, NOAA_BASE + product + ".json", {}, NOAA_TTL, "", "noaa_" + product)


# ------------------------------------------------------------- INTERNOS ----

func _request(url: String, timeout: float = TIMEOUT_SEC) -> Dictionary:
	if simulate_offline:
		return {"error": "Sin conexión (simulada)", "code": 0, "headers": [], "body": PackedByteArray()}
	request_count += 1
	var req := HTTPRequest.new()
	req.timeout = timeout
	req.body_size_limit = MAX_BODY_BYTES
	add_child(req)
	var err := req.request(url, PackedStringArray(["User-Agent: " + USER_AGENT, "Accept: */*"]))
	if err != OK:
		req.queue_free()
		return {"error": "No se pudo iniciar la peticion (%d)" % err, "code": 0, "headers": [], "body": PackedByteArray()}
	var r: Array = await req.request_completed   # [result, code, headers, body]
	req.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "Fallo de red (resultado %d)" % r[0], "code": 0, "headers": [], "body": PackedByteArray()}
	return {"error": "", "code": r[1], "headers": r[2], "body": r[3]}


func _build_url(url: String, params: Dictionary) -> String:
	if params.is_empty():
		return url
	var parts: PackedStringArray = []
	for k in params:
		parts.append("%s=%s" % [str(k).uri_encode(), str(params[k]).uri_encode()])
	return url + ("&" if "?" in url else "?") + "&".join(parts)


func _retry_after(headers: Array) -> float:
	for h in headers:
		var s := str(h)
		if s.to_lower().begins_with("retry-after:"):
			var v := s.substr(12).strip_edges()
			if v.is_valid_float():
				return maxf(float(v), 60.0)
	return DEFAULT_BACKOFF_SEC


func _host_of(url: String) -> String:
	var s := url.replace("https://", "").replace("http://", "")
	return s.split("/")[0]


func _hash_key(url: String, params: Dictionary) -> String:
	return (url + JSON.stringify(params)).md5_text()


func _cache_path(key: String) -> String:
	return "%s/%s.json" % [CACHE_DIR, key]


func _read_cache(key: String) -> Dictionary:
	var path := _cache_path(key)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _write_cache(key: String, entry: Dictionary) -> void:
	var f := FileAccess.open(_cache_path(key), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(entry))


func _result(ok: bool, data: Variant, origin: String, retrieved_at: float, code: int, error: String) -> Dictionary:
	return {"ok": ok, "data": data, "origin": origin, "retrieved_at": retrieved_at, "code": code, "error": error}


func _set_status(source: String, state: String, code: int, message: String) -> void:
	status[source] = {"state": state, "code": code, "message": message, "at": Time.get_unix_time_from_system()}
	status_changed.emit(source, status[source])
