class_name TutorialGuide
extends Control
## Tutorial progresivo: el robot ensena cada mecanica la PRIMERA VEZ que hace falta, con un anillo que late
## alrededor del elemento, una flecha animada y un globo de dialogo corto. Nunca interrumpe una ventana abierta.
## Lo ya visto se recuerda (user://tutorial.cfg) y se puede repetir con el boton «Repetir ayuda» del robot
## o desde Ajustes. Logica de disparo: LunarBase llama a notify("start" | "select" | "select:ID" | "task" | "turn:N").

const SAVE_PATH := "user://tutorial.cfg"
const STEPS := {
	"energy": {"triggers": ["start"], "text": "⚡ Este rayo muestra la energía de nuestra base."},
	"module": {"triggers": ["select"], "text": "👆 Aquí ves qué hace el edificio y qué puedes hacer."},
	"greenhouse": {"triggers": ["select:greenhouse"], "text": "🌱 Las plantas necesitan luz para crecer."},
	"task": {"triggers": ["task"], "text": "▶ ¡Cuando termines de elegir, pulsa aquí!"},
	"shelter": {"triggers": ["select:shelter", "turn:3"], "text": "🛡️ El escudo nos protege de la radiación del Sol."},
}
const ORDER := ["energy", "module", "greenhouse", "task", "shelter"]

var save_path := SAVE_PATH     # archivo donde se recuerdan los pasos vistos
var targets: Dictionary = {}    # id del paso -> Callable que devuelve el Rect2 (global) del elemento
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


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50
	var cfg := ConfigFile.new()
	if cfg.load(save_path) == OK and cfg.has_section("seen"):
		for k in cfg.get_section_keys("seen"):
			seen[k] = true


## Avisa de que paso algo en el juego; si algun paso lo estaba esperando, se pone en cola.
func notify(trigger: String) -> void:
	for id in ORDER:
		if seen.has(id) or id == active or id in _queue:
			continue
		if trigger in (STEPS[id]["triggers"] as Array):
			_queue.append(id)


## Vuelve a explicar todo desde el principio.
func replay() -> void:
	_close_bubble()
	seen.clear()
	_queue.clear()
	_save()
	notify("start")


func skip_all() -> void:
	for id in ORDER:
		seen[id] = true
	_queue.clear()
	_dismiss()


func _save() -> void:
	var cfg := ConfigFile.new()
	for k in seen:
		cfg.set_value("seen", str(k), true)
	cfg.save(save_path)


func _process(delta: float) -> void:
	_t += delta
	if active == "":
		if not _queue.is_empty() and can_show.is_valid() and bool(can_show.call()):
			_activate(str(_queue.pop_front()))
		return
	# Si de repente hay una ventana o alerta, el consejo espera (se oculta) en vez de estorbar
	var allowed: bool = not can_show.is_valid() or bool(can_show.call())
	if _bubble != null:
		_bubble.visible = allowed
	visible = allowed
	var fn: Callable = targets.get(active, Callable())
	_target_rect = fn.call() if fn.is_valid() else Rect2()
	if _target_rect.size == Vector2.ZERO:
		_dismiss()   # el elemento no esta visible (por ejemplo, oculto en Ajustes): no insistimos
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
	var ok := UI.btn("👍 ¡Entendido!", Color("28b36a"), _dismiss, 17, 44)
	row.add_child(ok)
	var skip := UI.btn("Omitir ayuda", Color("6b7596"), skip_all, 14, 44)
	row.add_child(skip)
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
