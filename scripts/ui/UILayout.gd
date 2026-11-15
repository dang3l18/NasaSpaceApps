class_name UILayout
extends RefCounted
## Disposicion de la interfaz del juego (que paneles se ven y donde estan). Se guarda en
## user://ui_layout.cfg para que se conserve entre partidas. Solo preferencias locales.

const PATH := "user://ui_layout.cfg"

## can_hide=false: el boton Finalizar turno y el de interfaz nunca se pueden ocultar, para que
## la partida no se quede sin forma de avanzar ni de recuperar los paneles.
const ELEMENTS := [
	{"id": "mission", "name": "Cabecera de la misión", "can_hide": true},
	{"id": "indicators", "name": "Cuatro indicadores", "can_hide": true},
	{"id": "robot", "name": "Robot asistente", "can_hide": true},
	{"id": "resources", "name": "Recursos del turno", "can_hide": true},
	{"id": "module", "name": "Panel del módulo", "can_hide": true},
	{"id": "risks", "name": "Riesgos del turno", "can_hide": true},
	{"id": "menu_btn", "name": "Botón Menú", "can_hide": true},
	{"id": "data_btn", "name": "Botón Datos", "can_hide": true},
	{"id": "end_btn", "name": "Botón Finalizar turno", "can_hide": false},
	{"id": "gear", "name": "Botón Interfaz", "can_hide": false},
]

static var _cfg := ConfigFile.new()


static func load_layout() -> void:
	_cfg = ConfigFile.new()
	_cfg.load(PATH)


static func save() -> void:
	_cfg.save(PATH)


static func is_shown(id: String) -> bool:
	return bool(_cfg.get_value("visible", id, true))


static func set_shown(id: String, v: bool) -> void:
	_cfg.set_value("visible", id, v)


## Posicion guardada o null si el panel esta en su sitio original.
static func get_pos(id: String) -> Variant:
	if _cfg.has_section_key("pos", id):
		return _cfg.get_value("pos", id)
	return null


static func set_pos(id: String, p: Vector2) -> void:
	_cfg.set_value("pos", id, p)


static func reset() -> void:
	_cfg = ConfigFile.new()
	_cfg.save(PATH)


static func can_hide(id: String) -> bool:
	for e in ELEMENTS:
		if e["id"] == id:
			return bool(e["can_hide"])
	return true
