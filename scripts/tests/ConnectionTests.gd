extends Node
## Fase H: pruebas de conexion, cache y funcionamiento sin conexion (usa la red real).
## Ejecutar: godot --headless --path <proyecto> res://scenes/ConnectionTests.tscn
## Sale con codigo 0 si todo pasa, 1 si algo falla.

var _pass := 0
var _fail := 0


func _ready() -> void:
	print("=== FASE H: pruebas de conexion, cache y offline ===")
	var key_backup := NASADataManager.api_key
	await _t1_cold_online()
	await _t2_warm_cache_no_requests()
	await _t3_offline_aged_cache()
	await _t4_offline_empty_cache()
	await _t5_rate_limit_backoff()
	await _t6_dedupe_inflight()
	await _t7_bad_key_falls_back_to_cache(key_backup)
	NASADataManager.api_key = key_backup
	NASADataManager.simulate_offline = false
	NASADataManager.force_stale = false
	print("\nRESULTADO: %d OK, %d FALLOS" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [OK]    " + msg)
	else:
		_fail += 1
		print("  [FALLO] " + msg)


func _reset(offline := false, stale := false) -> void:
	NASADataManager.simulate_offline = offline
	NASADataManager.force_stale = stale
	NASADataManager._backoff_until.clear()
	NASADataManager.status.clear()


func _clear_cache() -> void:
	for dir in ["user://cache/json", "user://cache/earth"]:
		var d := DirAccess.open(dir)
		if d:
			for f in d.get_files():
				d.remove(f)
	DirAccess.remove_absolute("user://cache/dataset_state.json")


## Envejece la cache: los JSON 8 h y las imagenes 13 h (fuera de los TTL y de la ventana "REAL").
func _age_cache() -> void:
	var d := DirAccess.open("user://cache/json")
	for f in d.get_files():
		var path := "user://cache/json/" + f
		var e: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if e is Dictionary:
			e["retrieved_at"] = float(e["retrieved_at"]) - 8 * 3600
			FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(e))
	var meta := ConfigFile.new()
	if meta.load(EarthImageryManager.META_PATH) == OK:
		for s in meta.get_sections():
			meta.set_value(s, "fetched_at", float(meta.get_value(s, "fetched_at", 0.0)) - 13 * 3600)
		meta.save(EarthImageryManager.META_PATH)


# ------------------------------------------------------------------ PRUEBAS ----

func _t1_cold_online() -> void:
	print("\nT1: cache vacia + con red -> consulta real")
	_clear_cache()
	_reset()
	var n0 := NASADataManager.request_count
	var ev: Dictionary = await ScientificDataManager.build_solar_event()
	_check(NASADataManager.request_count > n0, "se lanzaron peticiones HTTP reales (%d)" % (NASADataManager.request_count - n0))
	_check(not ev.is_fallback, "evento solar construido con datos DONKI (no es respaldo)")
	_check(ev.classification in [ScientificDataManager.LABEL_REAL, ScientificDataManager.LABEL_HISTORIC], "etiqueta valida: %s" % ev.classification)
	_check(ev.connection == "online", "estado de conexion = online")
	var earth: Dictionary = await EarthImageryManager.get_earth("modis_truecolor")
	_check(earth.ok and not earth.from_cache, "imagen GIBS descargada de la red (fecha %s)" % earth.image_date)
	var ctx: Dictionary = await ScientificDataManager.get_station_context()
	_check(ctx.ok and ctx.record.classification == ScientificDataManager.LABEL_HISTORIC, "CMR ISSLIS ok y rotulado HISTORICO")
	var x: Dictionary = await ScientificDataManager.get_geomagnetic_crosscheck([])
	_check(x.ok, "NOAA SWPC ok (Kp %.1f)" % x.get("kp_now", -1.0))


func _t2_warm_cache_no_requests() -> void:
	print("\nT2: cache vigente -> cero peticiones repetidas")
	_reset()
	var n0 := NASADataManager.request_count
	var ev: Dictionary = await ScientificDataManager.build_solar_event()
	await EarthImageryManager.get_earth("modis_truecolor")
	await ScientificDataManager.get_station_context()
	await ScientificDataManager.get_geomagnetic_crosscheck([])
	_check(NASADataManager.request_count == n0, "0 peticiones nuevas (hubo %d)" % (NASADataManager.request_count - n0))
	_check(not ev.is_fallback, "evento solar servido desde cache")


func _t3_offline_aged_cache() -> void:
	print("\nT3: sin red + cache antigua -> usa cache y NO la presenta como actual")
	_age_cache()
	_reset(true, true)
	var n0 := NASADataManager.request_count
	var ev: Dictionary = await ScientificDataManager.build_solar_event()
	_check(NASADataManager.request_count == n0, "sin red no se lanzan peticiones")
	_check(not ev.is_fallback, "el evento solar sigue disponible desde cache")
	_check(ev.classification == ScientificDataManager.LABEL_HISTORIC, "cache de 8 h rotulada HISTORICO (no REAL): %s" % ev.classification)
	var earth: Dictionary = await EarthImageryManager.get_earth("modis_truecolor")
	_check(earth.ok and earth.stale and earth.classification == ScientificDataManager.LABEL_HISTORIC, "imagen GIBS antigua servida y rotulada HISTORICO")
	var ctx: Dictionary = await ScientificDataManager.get_station_context()
	_check(ctx.ok and ctx.record.origin == "cache_stale", "CMR servido desde cache (origen %s)" % ctx.record.get("origin", "-"))
	var x: Dictionary = await ScientificDataManager.get_geomagnetic_crosscheck([])
	_check(x.ok and x.classification == ScientificDataManager.LABEL_HISTORIC, "NOAA desde cache rotulado HISTORICO: %s" % x.get("classification", "-"))
	var st: String = NASADataManager.status.get("DONKI_CME", {}).get("state", "")
	_check(st == "cache", "estado de conexion DONKI = cache (%s)" % st)


func _t4_offline_empty_cache() -> void:
	print("\nT4: sin red + sin cache -> la mision NO se bloquea")
	_clear_cache()
	_reset(true, false)
	var t0 := Time.get_ticks_msec()
	var ev: Dictionary = await ScientificDataManager.build_solar_event()
	_check(ev.is_fallback and ev.classification == ScientificDataManager.LABEL_SIM, "escenario de respaldo rotulado SIMULACION EDUCATIVA")
	_check(ev.record.is_empty(), "no se inventa ningun registro 'real'")
	_check(ev.explanation.contains("no un evento real"), "la explicacion aclara que no es un evento real")
	var earth: Dictionary = await EarthImageryManager.get_earth("modis_truecolor")
	_check(not earth.ok and earth.error != "", "sin imagen: error controlado ('%s')" % earth.error)
	var ctx: Dictionary = await ScientificDataManager.get_station_context()
	_check(not ctx.ok, "CMR sin datos: sin excepcion")
	var x: Dictionary = await ScientificDataManager.get_geomagnetic_crosscheck([])
	_check(not x.ok, "NOAA sin datos: sin excepcion")
	var ms := Time.get_ticks_msec() - t0
	_check(ms < 3000, "todo respondio en %d ms (sin esperas)" % ms)
	var d := DatasetManager.get_dataset("donki_cme")
	_check(str(d.get("connection", "")) == "offline", "el panel marca DONKI como offline")


func _t5_rate_limit_backoff() -> void:
	print("\nT5: limite de la API (429) -> respeta el backoff")
	_clear_cache()
	_reset()
	NASADataManager._backoff_until["api.nasa.gov"] = Time.get_unix_time_from_system() + 600.0
	var n0 := NASADataManager.request_count
	var r: Dictionary = await NASADataManager.donki("CME", 30)
	_check(not r.ok and r.code == 429, "respuesta controlada con codigo 429")
	_check(NASADataManager.request_count == n0, "no se hizo ninguna peticion durante el backoff")
	_check(NASADataManager.status.get("DONKI_CME", {}).get("state", "") == "rate_limited", "estado = rate_limited")
	NASADataManager._backoff_until.clear()


func _t6_dedupe_inflight() -> void:
	print("\nT6: peticiones simultaneas iguales -> una sola peticion")
	_clear_cache()
	_reset()
	var n0 := NASADataManager.request_count
	NASADataManager.donki("SEP", 30)            # lanzada sin await (en vuelo)
	var r: Dictionary = await NASADataManager.donki("SEP", 30)   # espera a la anterior
	_check(r.ok, "ambas llamadas reciben respuesta")
	_check(NASADataManager.request_count - n0 == 1, "solo 1 peticion HTTP (hubo %d)" % (NASADataManager.request_count - n0))


func _t7_bad_key_falls_back_to_cache(real_key: String) -> void:
	print("\nT7: clave invalida -> error controlado y respaldo en cache")
	_clear_cache()
	_reset()
	NASADataManager.api_key = "clave_invalida_de_prueba"
	var bad: Dictionary = await NASADataManager.donki("CME", 30)
	_check(not bad.ok, "sin cache y con clave invalida: ok=false, codigo %d" % bad.code)
	NASADataManager.api_key = real_key
	await NASADataManager.donki("CME", 30)   # llena la cache con la clave buena
	_age_cache()
	NASADataManager.api_key = "clave_invalida_de_prueba"
	_reset(false, true)
	var fb: Dictionary = await NASADataManager.donki("CME", 30)
	_check(fb.ok and fb.origin == "cache_stale", "con cache previa, la clave invalida cae a cache (origen %s)" % fb.origin)
	NASADataManager.api_key = real_key
