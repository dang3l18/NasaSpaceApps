extends Node
## AchievementManager (autoload): escucha las señales de MissionManager y desbloquea logros
## ligados a las decisiones del jugador. Se guardan en el JSON de MissionManager.

signal achievement_unlocked(id: String)

const DEFS: Array[Dictionary] = [
	{"id": "first_win", "name": "Primera misión superada", "icon": "🏁", "desc": "Supera cualquier misión."},
	{"id": "field_engineer", "name": "Ingeniero de Campo", "icon": "🛠", "desc": "Supera una misión sin dejar caer ninguno de los 4 sistemas por debajo del 15%."},
	{"id": "human_shield", "name": "Escudo Humano", "icon": "🛡", "desc": "Resiste una alerta solar de nivel máximo priorizando el blindaje sobre la producción."},
	{"id": "space_farmer", "name": "Agricultor Espacial", "icon": "🌱", "desc": "Supera una misión con los alimentos al 100% en todos los turnos."},
	{"id": "trade_off_master", "name": "Maestro del Trade-off", "icon": "⚖", "desc": "Sacrifica un recurso a propósito para salvar la misión y gana."},
	{"id": "data_scientist", "name": "Científico de datos", "icon": "📊", "desc": "Abre el Space Data Center."},
]

## Logros desbloqueados por la ultima partida (lo lee MissionManager para mostrarlos).
var last_new: Array[String] = []


func _ready() -> void:
	MissionManager.mission_finished.connect(_on_mission_finished)


func is_unlocked(id: String) -> bool:
	var ach: Dictionary = MissionManager.data["achievements"]
	return ach.has(id) and bool((ach[id] as Dictionary).get("unlocked", false))


func unlock(id: String) -> bool:
	if is_unlocked(id):
		return false
	(MissionManager.data["achievements"] as Dictionary)[id] = {"unlocked": true, "at": Time.get_datetime_string_from_system(true)}
	MissionManager.save()
	achievement_unlocked.emit(id)
	return true


func def_of(id: String) -> Dictionary:
	for d in DEFS:
		if d["id"] == id:
			return d
	return {}


## Logros que se ganarian con este resultado (sin guardar nada). Funcion pura: facil de probar.
func evaluate(_mission_id: String, won: bool, stats: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if not won:
		return out
	out.append("first_win")
	var min_ind: Dictionary = stats.get("min_ind", {})
	var all_ok := not min_ind.is_empty()
	for k in min_ind:
		if float(min_ind[k]) < 15.0:
			all_ok = false
	if all_ok:
		out.append("field_engineer")
	if int(stats.get("alert_tier", 0)) >= 3 and float(stats.get("shield_at_alert", 0.0)) >= 70.0 \
			and not bool(stats.get("expanded_before_alert", true)):
		out.append("human_shield")
	if float(stats.get("min_food", 0.0)) >= 99.5:
		out.append("space_farmer")
	if (stats.get("sacrifices", []) as Array).size() > 0:
		out.append("trade_off_master")
	var fresh: Array[String] = []
	for id in out:
		if not is_unlocked(id):
			fresh.append(id)
	return fresh


func _on_mission_finished(mission_id: String, won: bool, stats: Dictionary) -> void:
	for id in evaluate(mission_id, won, stats):
		if unlock(id):
			last_new.append(id)
