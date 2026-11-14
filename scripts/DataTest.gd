extends Node
## Prueba de las Fases D: DONKI + GIBS. Imprime resultados reales y sale.
## Ejecutar: Godot --headless --path <proyecto>   (o abrir en el editor)


func _ready() -> void:
	print("=== Prueba de integracion de datos (Fase D) ===")
	print("Clave NASA: %s" % ("DEMO_KEY (limitada)" if NASADataManager.using_demo_key else "personal (cargada)"))

	var t0 := Time.get_ticks_msec()
	var n0 := NASADataManager.request_count
	await ScientificDataManager.ensure_history()
	print("\n--- DONKI: archivo 2025-2026 (%d peticiones, %d ms) ---" % [NASADataManager.request_count - n0, Time.get_ticks_msec() - t0])
	print(ScientificDataManager.history_summary())

	var ev: Dictionary = await ScientificDataManager.build_solar_event()
	print("\n--- DONKI: evento solar de la mision ---")
	print("Clasificacion: %s | fallback: %s | conexion: %s" % [ev.classification, ev.is_fallback, ev.connection])
	print(ev.explanation)
	for kind in NASADataManager.status:
		if kind.begins_with("DONKI_"):
			var s: Dictionary = NASADataManager.status[kind]
			print("  %s -> %s (HTTP %s) %s" % [kind, s.state, s.code, s.message])

	print("\n--- GIBS: imagenes de la Tierra ---")
	for key in ["modis_truecolor", "blackmarble"]:
		var r: Dictionary = await EarthImageryManager.get_earth(key)
		if r.ok:
			var img: Image = (r.texture as ImageTexture).get_image()
			print("%s: OK %dx%d | fecha=%s | cache=%s | %s" % [key, img.get_width(), img.get_height(), r.image_date, r.from_cache, r.classification])
		else:
			print("%s: FALLO -> %s" % [key, r.error])

	print("\n--- Earthdata CMR: contexto educativo de la estacion (Fase E) ---")
	var ctx: Dictionary = await ScientificDataManager.get_station_context()
	if ctx.ok:
		var r: Dictionary = ctx.record
		print("%s\n  id=%s | centro=%s | plataforma=%s | %s" % [r.title, r.id, r.data_center, r.platform, r.classification])
		print("  cobertura: %s -> %s | origen=%s" % [Time.get_date_string_from_unix_time(int(r.coverage_start)), Time.get_date_string_from_unix_time(int(r.coverage_end)), r.origin])
		print("  enlace: %s" % r.link)
		print("  resumen: %s..." % r.summary_original.left(160))
	else:
		print("CMR sin datos: %s" % ctx.error)

	print("\n--- NOAA SWPC: contraste geomagnetico (Fase F) ---")
	var gst_recs := ScientificDataManager.normalize_donki("GST", await NASADataManager.donki("GST", 30))
	var x: Dictionary = await ScientificDataManager.get_geomagnetic_crosscheck(gst_recs)
	if x.ok:
		print("%s | %s | origen=%s | escalas G%s S%s R%s" % [x.comparison, x.classification, x.origin, x.g_scale, x.s_scale, x.r_scale])
	else:
		print("NOAA sin datos: %s" % x.error)

	print("\n--- Estado de datasets (para el panel) ---")
	for d in DatasetManager.get_all(["D", "E", "F"]):
		print("%-26s | %-12s | %-22s | dato: %s | consulta: %s" % [
			d.id, d.get("connection", "sin consulta"), d.get("classification", "-"),
			d.get("data_date", "-"), DatasetManager.format_time(d.get("queried_at", 0.0))])
	get_tree().quit()
