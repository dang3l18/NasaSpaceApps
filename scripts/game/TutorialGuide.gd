class_name TutorialGuide
extends Control
## Tutorial progresivo con UNA SERIE DE AYUDAS PARA CADA MISION: el robot ensena cada cosa la primera vez que
## hace falta, con un anillo que late alrededor del elemento, una flecha animada y un globo de dialogo corto.
## Cada mision tiene sus propios pasos ligados a su dilema (tormenta, apagon, ciclo de luz, sombra, grieta)
## mas los pasos basicos que aun no se hayan visto. Nunca interrumpe una ventana abierta.
## Lo ya visto se recuerda (user://tutorial.cfg) y se repite con «Repetir ayuda» (serie de la mision actual).
## LunarBase llama a notify("start" | "select" | "select:ID" | "task" | "turn:N" | "alert").

const SAVE_PATH := "user://tutorial.cfg"

## Cada paso: disparadores, elemento al que apunta (target) y texto. Targets: meter:<id> (medidor de la izquierda),
## module:<id> (edificio del mapa), header (cabecera de la mision), panel:module (ventana del edificio), end (terminar turno).
const STEPS := {
	# --- basicos (se muestran la primera vez que se juega cualquier mision) ---
	"energy": {"triggers": ["start"], "target": "meter:energia", "text": "⚡ Este rayo muestra la energía de nuestra base."},
	"module": {"triggers": ["select"], "target": "panel:module", "text": "👆 Aquí ves qué hace el edificio y qué puedes hacer."},
	"greenhouse": {"triggers": ["select:greenhouse"], "target": "module:greenhouse", "text": "🌱 Las plantas necesitan luz para crecer."},
	"task": {"triggers": ["task"], "target": "end", "text": "▶ ¡Cuando termines de elegir, pulsa aquí!"},
	"shelter": {"triggers": ["select:shelter", "turn:3"], "target": "module:shelter", "text": "🛡️ El escudo nos protege de la radiación del Sol."},
	# --- Tormenta en el Horizonte ---
	"storm_shield": {"triggers": ["start"], "target": "meter:proteccion", "text": "🛡️ Esta barra es tu escudo. ¡Súbela antes de la tormenta!"},
	"storm_energy": {"triggers": ["turn:2"], "target": "module:shelter", "text": "⚡ El refugio gasta energía el día de la tormenta. ¡Guárdala!"},
	"storm_lights": {"triggers": ["select:greenhouse"], "target": "module:greenhouse", "text": "💡 Apagar las luces de las plantas ahorra energía."},
	"storm_day": {"triggers": ["alert"], "target": "module:shelter", "text": "🏠 ¡Hoy el refugio protege al equipo!"},
	# --- Apagón en el Casquete ---
	"black_sun": {"triggers": ["start"], "target": "module:panels", "text": "☀️ Casi no llega luz: los paneles dan poca energía."},
	"black_cmd": {"triggers": ["turn:2", "select:command"], "target": "module:command", "text": "🔌 Aquí apagas lo que no necesitas para ahorrar."},
	"black_reserve": {"triggers": ["select:backup_energy", "turn:3"], "target": "module:backup_energy", "text": "🔋 La reserva es para emergencias. ¡Con cuidado!"},
	# --- La Cosecha de los Tubos de Lava ---
	"lava_air": {"triggers": ["start"], "target": "meter:vida", "text": "💨 Aquí el aire depende de las plantas."},
	"lava_light": {"triggers": ["turn:2", "select:greenhouse"], "target": "module:greenhouse", "text": "💡 Alterna luz alta y oscuridad: ¡así crecen más!"},
	"lava_header": {"triggers": ["turn:3"], "target": "header", "text": "🔦 Aquí ves cuál fue tu última luz."},
	# --- Efecto de Sombra Orbital ---
	"shadow_night": {"triggers": ["start"], "target": "meter:energia", "text": "🌑 La noche es larga: ¡cuida la batería!"},
	"shadow_cmd": {"triggers": ["turn:2", "select:command"], "target": "module:command", "text": "🔥 Calefacción o datos: no alcanza para los dos."},
	"shadow_data": {"triggers": ["turn:3"], "target": "header", "text": "📡 Hay que enviar 4 paquetes de datos a la Tierra."},
	# --- Anomalía en el Escudo Térmico ---
	"therm_crack": {"triggers": ["start"], "target": "meter:proteccion", "text": "🛡️ ¡Hay una grieta en el escudo! Deja pasar radiación."},
	"therm_seal": {"triggers": ["turn:2", "select:shelter"], "target": "module:shelter", "text": "🔧 Aquí sellas la grieta. Gasta energía y aire."},
	"therm_suits": {"triggers": ["turn:3"], "target": "header", "text": "🧑‍🚀 Mira el aire de los trajes: sin él no se sale a reparar."},
}

## Serie de cada mision: primero sus pasos propios y luego los basicos (que solo salen si aun no se vieron).
const BASICS := ["energy", "module", "greenhouse", "task", "shelter"]
const SERIES := {
	"lunar_awakening": ["energy", "module", "greenhouse", "task", "shelter"],
	"storm_horizon": ["storm_shield", "storm_energy", "storm_lights", "storm_day", "energy", "module", "task", "shelter"],
	"lunar_blackout": ["black_sun", "black_cmd", "black_reserve", "energy", "module", "task"],
	"lava_harvest": ["lava_air", "lava_light", "lava_header", "energy", "module", "greenhouse", "task"],
	"orbital_shadow": ["shadow_night", "shadow_cmd", "shadow_data", "energy", "module", "task"],
	"thermal_anomaly": ["therm_crack", "therm_seal", "therm_suits", "energy", "module", "task"],
}

var mission_id := "lunar_awakening"
var save_path := SAVE_PATH     # archivo donde se recuerdan los pasos vistos
var targets: Dictionary = {}    # (opcional) id de paso -> Callable que devuelve el Rect2 global; tiene prioridad
var resolver: Callable          # clave de target ("meter:energia"...) -> Rect2 global (vacio = no visible)
var can_show: Callable          # devuelve true si ahora se puede mostrar un consejo (sin ventanas abiertas)
var active := ""                # paso que se esta mostrando ("" = ninguno)
var seen: Dictionary = {}
var _queue: Array = []
var _bubble: PanelContainer
var _t := 0.0
var _target_rect := Rect2()
var _arrow_dir := Vector2.UP


static func reset_saved() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


## Pasos de la mision actual, en orden.
func order() -> Array:
	return SERIES.get(mission_id, SERIES["lunar_awakening"])


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50
	var cfg := ConfigFile.new()
	if cfg.load(save_path) == OK and cfg.has_section("seen"):
		for k in cfg.get_section_keys("seen"):
			seen[k] = true


## Avisa de que paso algo en el juego; si algun paso de la serie lo estaba esperando, se pone en cola.
func notify(trigger: String) -> void:
	for id in order():
		if seen.has(id) or id == active or id in _queue:
			continue
		if trigger in (STEPS[id]["triggers"] as Array):
			_queue.append(id)


## Vuelve a explicar toda la serie de ESTA mision, paso a paso.
func replay() -> void:
	_close_bubble()
	for id in order():
		seen.erase(id)
	_queue.clear()
	for id in order():
		_queue.append(id)
	_save()


func skip_all() -> void:
	for id in order():
		seen[id] = true
	_queue.clear()
	_dismiss()


func _save() -> void:
	var cfg := ConfigFile.new()
	for k in seen:
		cfg.set_value("seen", str(k), true)
	cfg.save(save_path)


func _rect_for(id: String) -> Rect2:
	var fn: Callable = targets.get(id, Callable())
	if fn.is_valid():
		return fn.call()
	if resolver.is_valid():
		return resolver.call(str(STEPS[id]["target"]))
	return Rect2()


func _process(delta: float) -> void:
	_t += delta
	if active == "":
		while not _queue.is_empty() and can_show.is_valid() and bool(can_show.call()):
			var nxt := str(_queue.pop_front())
			if _rect_for(nxt).size == Vector2.ZERO:
				continue   # su elemento no esta visible ahora: se salta (no insistimos)
			_activate(nxt)
			break
		return
	# Si de repente hay una ventana o alerta, el consejo espera (se oculta) en vez de estorbar
	var allowed: bool = not can_show.is_valid() or bool(can_show.call())
	if _bubble != null:
		_bubble.visible = allowed
	visible = allowed
	_target_rect = _rect_for(active)
	if _target_rect.size == Vector2.ZERO:
		_dismiss()
		return
	_place_bubble()
	queue_redraw()


func _activate(id: String) -> void:
	active = id
	visible = true
	_bubble = PanelContainer.new()
	_bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	_bubble.add_theme_stylebox_override("panel", UI.box(Color("eaf3ff"), Color("ffd24d"), 4, 14, 10))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	_bubble.add_child(h)
	h.add_child(KidKit.disc("🤖", Color("5a7bd0"), 52))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	h.add_child(v)
	var l := UI.lbl(str(STEPS[id]["text"]), 20, Color("15306b"), true, 290)
	l.add_theme_constant_override("outline_size", 0)
	v.add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var pos_in_series: int = order().find(id) + 1
	var ok := UI.btn("👍 ¡Entendido!", Color("28b36a"), _dismiss, 17, 44)
	row.add_child(ok)
	var skip := UI.btn("Omitir ayuda", Color("6b7596"), skip_all, 14, 44)
	row.add_child(skip)
	var step_l := UI.lbl("Ayuda %d de %d" % [pos_in_series, order().size()], 13, Color("5b6b99"))
	step_l.add_theme_constant_override("outline_size", 0)
	v.add_child(step_l)
	add_child(_bubble)
	_bubble.modulate.a = 0.0
	_bubble.scale = Vector2(0.85, 0.85)
	await get_tree().process_frame
	if _bubble == null:
		return
	_bubble.pivot_offset = _bubble.size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_bubble, "modulate:a", 1.0, 0.2)
	tw.tween_property(_bubble, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## El globo va al lado del elemento con mas sitio, sin salirse de la pantalla.
func _place_bubble() -> void:
	if _bubble == null:
		return
	_bubble.reset_size()
	var view := get_viewport_rect().size
	var sz := _bubble.size
	var r := _target_rect
	var pos := Vector2.ZERO
	if r.get_center().x > view.x * 0.5:
		pos = Vector2(r.position.x - sz.x - 70.0, r.get_center().y - sz.y * 0.5)
	else:
		pos = Vector2(r.end.x + 70.0, r.get_center().y - sz.y * 0.5)
	if pos.x < 8.0 or pos.x + sz.x > view.x - 8.0:   # no cabe a los lados: encima o debajo
		pos = Vector2(r.get_center().x - sz.x * 0.5, r.position.y - sz.y - 70.0 if r.position.y > view.y * 0.5 else r.end.y + 70.0)
	pos.x = clampf(pos.x, 8.0, view.x - sz.x - 8.0)
	pos.y = clampf(pos.y, 8.0, view.y - sz.y - 8.0)
	_bubble.position = pos
	_arrow_dir = (_bubble.position + sz * 0.5 - r.get_center()).normalized()


func _dismiss() -> void:
	if active != "":
		seen[active] = true
		_save()
	_close_bubble()


func _close_bubble() -> void:
	active = ""
	if _bubble != null:
		var b := _bubble
		_bubble = null
		var tw := create_tween()
		tw.tween_property(b, "modulate:a", 0.0, 0.15)
		tw.tween_callback(b.queue_free)
	queue_redraw()


func _draw() -> void:
	if active == "" or _target_rect.size == Vector2.ZERO:
		return
	# Anillo que late alrededor del elemento
	var pulse := 0.5 + 0.5 * sin(_t * 6.0)
	var r := _target_rect.grow(6.0 + 3.0 * pulse)
	draw_rect(r, Color(1.0, 0.85, 0.3, 0.2 + 0.2 * pulse), true)
	draw_rect(r, Color(1.0, 0.85, 0.3, 0.7 + 0.3 * pulse), false, 5.0)
	# Flecha animada que va del globo al elemento
	var d := _arrow_dir
	var edge := r.get_center() + d * (maxf(r.size.x * absf(d.x), r.size.y * absf(d.y)) * 0.5 + 4.0)
	var bob := 8.0 * (0.5 + 0.5 * sin(_t * 7.0))
	var tip := edge + d * bob
	var back := tip + d * 38.0
	var side := Vector2(-d.y, d.x) * 17.0
	var tri := PackedVector2Array([tip, back + side, back - side])
	draw_colored_polygon(PackedVector2Array([tip + d * -3.0, back + side * 1.25, back - side * 1.25]), Color("1b2a72"))
	draw_colored_polygon(tri, Color("ffd24d"))
