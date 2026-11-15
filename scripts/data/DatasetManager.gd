extends Node
## Registro de datasets: metadatos, procedencia, enlaces originales, formato y licencia.
## El estado de ejecucion (ultima consulta, fecha del dato, conexion) se guarda en
## user://cache/dataset_state.json para que el panel funcione sin conexion.

signal dataset_updated(id: String)

const REGISTRY_PATH := "res://data/datasets.json"
const STATE_PATH := "user://cache/dataset_state.json"

var _datasets: Array = []
var _index: Dictionary = {}
var _state: Dictionary = {}
var _fixed_state: Dictionary = {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://cache")
	_load_registry()
	_load_state()


func _load_registry() -> void:
	var parsed: Variant = Lang._read_json(REGISTRY_PATH)   # funciona tambien en el juego exportado (web)
	if parsed is Dictionary:
		_datasets = parsed.get("datasets", [])
	else:
		push_error("DatasetManager: no se pudo leer %s" % REGISTRY_PATH)
	var sci := preload("res://scripts/data/ScientificDataManager.gd")
	for d in _datasets:
		_index[d["id"]] = d
		# Referencias y parametros no se "consultan": se rotulan por su naturaleza.
		var kind := str(d.get("kind", ""))
		if kind == "reference" or kind == "parameter":
			_fixed_state[d["id"]] = {
				"connection": "ref",
				"classification": sci.LABEL_REF if kind == "reference" else sci.LABEL_PARAM,
				"data_date": "Documentación de NASA (enlace verificado el 2026-11-14)" if kind == "reference" else "Valores del juego (no son datos reales)",
				"queried_at": 0.0, "note": "", "origin": "doc",
			}


func _load_state() -> void:
	if FileAccess.file_exists(STATE_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STATE_PATH))
		if parsed is Dictionary:
			_state = parsed


func _save_state() -> void:
	var f := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_state))


## Lista de datasets (metadatos + estado en ejecucion). `phase_filter` opcional: "D","E","F".
func get_all(phases: Array = []) -> Array:
	var out: Array = []
	for d in _datasets:
		if phases.is_empty() or d.get("phase", "") in phases:
			out.append(get_dataset(d["id"]))
	return out


func get_dataset(id: String) -> Dictionary:
	if not _index.has(id):
		return {}
	var d: Dictionary = (_index[id] as Dictionary).duplicate()
	d.merge(_state.get(id, {}), true)
	d.merge(_fixed_state.get(id, {}), true)
	return d


## Registra el resultado de una consulta real. Campos esperados en `info`:
## connection ("online"|"cache"|"offline"|"rate_limited"), classification, data_date (texto),
## queried_at (unix), origin, note.
func report(id: String, info: Dictionary) -> void:
	if not _index.has(id):
		push_warning("DatasetManager: dataset desconocido '%s'" % id)
		return
	_state[id] = info
	_save_state()
	dataset_updated.emit(id)


static func format_time(unix: float) -> String:
	if unix <= 0.0:
		return "sin consulta"
	return Time.get_datetime_string_from_unix_time(int(unix), true) + " UTC"
