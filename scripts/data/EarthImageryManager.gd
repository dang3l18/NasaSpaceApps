extends Node
## Imagenes reales de la Tierra desde NASA GIBS (WMS). Cache en disco, validacion de
## imagen y retroceso por fecha: GIBS devuelve imagenes casi vacias (~3 KB) para los
## dias mas recientes, asi que se busca la fecha mas nueva con imagen real.

const WMS_URL := "https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi"
const CACHE_DIR := "user://cache/earth"
const META_PATH := "user://cache/earth/meta.cfg"
const CACHE_TTL := 12 * 3600
const MIN_VALID_BYTES := 20000   # una imagen en blanco pesa ~3 KB
const MAX_DAYS_BACK := 10
const IMG_W := 1024
const IMG_H := 512

const LAYERS := {
	"modis_truecolor": {
		"dataset_id": "gibs_modis_truecolor", "layer": "MODIS_Terra_CorrectedReflectance_TrueColor",
		"format": "image/jpeg", "ext": "jpg", "temporal": true,
	},
	"viirs_truecolor": {
		"dataset_id": "gibs_viirs_truecolor", "layer": "VIIRS_SNPP_CorrectedReflectance_TrueColor",
		"format": "image/jpeg", "ext": "jpg", "temporal": true,
	},
	"blackmarble": {
		"dataset_id": "gibs_blackmarble", "layer": "VIIRS_Black_Marble",
		"format": "image/png", "ext": "png", "temporal": false,
	},
}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)


## Devuelve {ok, texture, layer_key, image_date, from_cache, stale, classification, error}.
## image_date: "YYYY-MM-DD" de la imagen realmente usada ("" si la capa no tiene fecha diaria).
func get_earth(layer_key: String = "modis_truecolor") -> Dictionary:
	if not LAYERS.has(layer_key):
		return _fail(layer_key, "Capa desconocida")
	var cfg: Dictionary = LAYERS[layer_key]
	var meta := ConfigFile.new()
	meta.load(META_PATH)
	var now := Time.get_unix_time_from_system()

	# 1) Cache vigente: no se hace ninguna peticion.
	var cached_file := str(meta.get_value(layer_key, "file", ""))
	var cached_date := str(meta.get_value(layer_key, "date", ""))
	var fetched_at := float(meta.get_value(layer_key, "fetched_at", 0.0))
	if cached_file != "" and FileAccess.file_exists(cached_file) and not NASADataManager.force_stale and now - fetched_at < CACHE_TTL:
		var tex := _load_texture(cached_file, cfg.ext)
		if tex:
			_report(layer_key, "cache", cached_date, fetched_at, "Cache vigente")
			return _ok(layer_key, tex, cached_date, true, false, fetched_at)

	# 2) Red: buscar la fecha mas reciente con imagen real.
	var dates: Array = []
	if cfg.temporal:
		for i in range(1, MAX_DAYS_BACK + 1):
			dates.append(Time.get_date_string_from_unix_time(int(now) - i * 86400))
	else:
		dates.append("")
	var last_error := ""
	for d in dates:
		var res: Dictionary = await NASADataManager.get_bytes("GIBS_" + layer_key, _wms_url(cfg, d))
		if not res.ok:
			last_error = res.error
			if res.code == 0 or res.code == 429:
				break   # sin red o limite: no insistir 10 veces
			continue
		var body: PackedByteArray = res.body
		if body.size() < MIN_VALID_BYTES or not _has_magic(body, cfg.ext):
			last_error = "Imagen vacia o no valida para %s" % d
			continue
		var path := "%s/%s_%s.%s" % [CACHE_DIR, layer_key, d if d != "" else "default", cfg.ext]
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			last_error = "No se pudo escribir la cache"
			break
		f.store_buffer(body)
		f.close()
		var tex := _load_texture(path, cfg.ext)
		if tex == null:
			last_error = "No se pudo decodificar la imagen"
			continue
		var t := Time.get_unix_time_from_system()
		meta.set_value(layer_key, "file", path)
		meta.set_value(layer_key, "date", d)
		meta.set_value(layer_key, "fetched_at", t)
		meta.save(META_PATH)
		_report(layer_key, "online", d, t, "OK")
		return _ok(layer_key, tex, d, false, false, t)

	# 3) Respaldo: ultima imagen en cache (aunque este vieja), rotulada como historica.
	if cached_file != "" and FileAccess.file_exists(cached_file):
		var tex := _load_texture(cached_file, cfg.ext)
		if tex:
			_report(layer_key, "cache", cached_date, fetched_at, "%s - usando cache" % last_error)
			return _ok(layer_key, tex, cached_date, true, true, fetched_at)
	_report(layer_key, "offline", "", 0.0, last_error)
	return _fail(layer_key, last_error if last_error != "" else "Sin imagen disponible")


# ------------------------------------------------------------- INTERNOS ----

func _wms_url(cfg: Dictionary, date: String) -> String:
	var url := "%s?SERVICE=WMS&REQUEST=GetMap&VERSION=1.3.0&LAYERS=%s&STYLES=&CRS=EPSG:4326&BBOX=-90,-180,90,180&WIDTH=%d&HEIGHT=%d&FORMAT=%s" % [
		WMS_URL, cfg.layer, IMG_W, IMG_H, cfg.format.uri_encode()]
	if date != "":
		url += "&TIME=" + date
	return url


func _has_magic(b: PackedByteArray, ext: String) -> bool:
	# Los errores WMS llegan como XML con HTTP 200: se descartan comprobando la firma.
	if ext == "jpg":
		return b.size() > 3 and b[0] == 0xFF and b[1] == 0xD8
	return b.size() > 4 and b[0] == 0x89 and b[1] == 0x50 and b[2] == 0x4E and b[3] == 0x47


func _load_texture(path: String, ext: String) -> ImageTexture:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var img := Image.new()
	var err := img.load_jpg_from_buffer(bytes) if ext == "jpg" else img.load_png_from_buffer(bytes)
	if err != OK:
		return null
	return ImageTexture.create_from_image(img)


func _classification(date: String, fetched_at: float, stale: bool) -> String:
	if date == "" or stale:
		return ScientificDataManager.LABEL_HISTORIC
	var t := ScientificDataManager.parse_iso(date + "T00:00:00")
	return ScientificDataManager.classify(t + 86400.0, fetched_at)


func _ok(layer_key: String, tex: ImageTexture, date: String, from_cache: bool, stale: bool, fetched_at: float) -> Dictionary:
	return {
		"ok": true, "texture": tex, "layer_key": layer_key, "image_date": date,
		"from_cache": from_cache, "stale": stale, "retrieved_at": fetched_at,
		"classification": _classification(date, fetched_at, stale), "error": "",
	}


func _fail(layer_key: String, error: String) -> Dictionary:
	return {"ok": false, "texture": null, "layer_key": layer_key, "image_date": "", "from_cache": false,
			"stale": false, "retrieved_at": 0.0, "classification": ScientificDataManager.LABEL_HISTORIC, "error": error}


func _report(layer_key: String, connection: String, date: String, queried: float, note: String) -> void:
	DatasetManager.report(LAYERS[layer_key].dataset_id, {
		"connection": connection, "note": note, "queried_at": queried,
		"data_date": date if date != "" else "capa por defecto (sin fecha diaria)",
		"classification": _classification(date, queried, connection == "offline"),
		"origin": "network" if connection == "online" else "cache",
	})
