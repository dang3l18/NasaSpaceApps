class_name AlertOverlay
extends Control
## Pantalla de ALERTA ESPACIAL: grande, animada, con cuenta regresiva y 3 respuestas.
## Se construye por codigo. Cada boton aplica de verdad su efecto (SpaceEvents.resolve) sobre BaseState.
## Si se acaba el tiempo, se aplica la consecuencia por no responder. Al terminar emite `finished(result)`.
## Atajos: teclas 1, 2 y 3 eligen la opcion.

signal finished(result: Dictionary)

const STYLE := {
	1: {"name": "ALERTA", "col": Color("f1b434")},
	2: {"name": "ALERTA GRAVE", "col": Color("ff8a3d")},
	3: {"name": "¡EMERGENCIA!", "col": Color("ff3b3b")},
}

var ev: Dictionary = {}
var s: BaseState
var result: Dictionary = {}
var resolved := false

var _left := 20.0
var _total := 20.0
var _t := 0.0
var _closing := false
var _col := Color("ff8a3d")
var _panel: PanelContainer
var _body: VBoxContainer
var _count: Label
var _bar: ProgressBar
var _icon: Label
var _art: KidArt
var _stripes: Control
var _edge: Control
var _dim: ColorRect
var _buttons: Array[Button] = []


func setup(event: Dictionary, state: BaseState) -> void:
	ev = event
	s = state
	_total = float(ev["seconds"])
	_left = _total
	_col = STYLE[int(ev["tier"])]["col"]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # ya esta dentro del arbol: hay que fijar tambien los margenes
	mouse_filter = Control.MOUSE_FILTER_STOP   # bloquea el juego de abajo mientras dura la alerta
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dim = ColorRect.new()
	_dim.color = Color(0.12, 0.0, 0.0, 0.7)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_edge = Control.new()   # borde rojo que late en toda la pantalla
	_edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.draw.connect(_draw_edge)
	add_child(_edge)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(960, 0)
	_panel.add_theme_stylebox_override("panel", UI.box(Color("14080c"), _col, 5, 18, 0))
	center.add_child(_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	_panel.add_child(outer)
	_stripes = Control.new()
	_stripes.custom_minimum_size = Vector2(0, 26)
	_stripes.clip_contents = true
	_stripes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stripes.draw.connect(_draw_stripes)
	outer.add_child(_stripes)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 18)
	outer.add_child(margin)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	margin.add_child(_body)
	_build_alert_view()
	# Entrada: la tarjeta crece con un rebote y aparece con fundido.
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.5, 0.5)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_panel.pivot_offset = _panel.size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.25)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build_alert_view() -> void:
	for c in _body.get_children():
		c.queue_free()
	_buttons.clear()
	_icon = null
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 18)
	_body.add_child(head)
	# Escena animada: se entiende la situacion mirando
	_art = KidArt.make(str(ev["id"]), Vector2(300, 170))
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UI.box(Color("0b1240"), _col, 4, 14, 0))
	frame.clip_contents = true
	frame.add_child(_art)
	head.add_child(frame)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 6)
	head.add_child(titles)
	titles.add_child(UI.lbl("%s %s" % [ev["icon"], STYLE[int(ev["tier"])]["name"]], 18, _col))
	titles.add_child(UI.lbl(KidText.sentence(str(ev["title"])), 38, Color.WHITE, true, 480))
	# El robot lo cuenta en una frase
	var say := HBoxContainer.new()
	say.add_theme_constant_override("separation", 8)
	titles.add_child(say)
	say.add_child(KidKit.disc("🤖", Color("5a7bd0"), 48))
	var bub := PanelContainer.new()
	bub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bub.add_theme_stylebox_override("panel", UI.box(Color("eaf3ff"), Color("8ec5ff"), 3, 12, 8))
	var bl := UI.lbl(str(ev.get("robot", ev["desc"])), 19, Color("15306b"), true, 360)
	bl.add_theme_constant_override("outline_size", 0)
	bub.add_child(bl)
	say.add_child(bub)
	_count = UI.lbl("", 34, _col)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(_count)
	_bar = UI.bar(_left, _total, _col, 16)
	_body.add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_body.add_child(row)
	var opts: Array = ev["options"]
	for i in opts.size():
		var o: Dictionary = opts[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(290, 200)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", UI.box(Color("22348a"), Color("6db6ff"), 4, 14, 0))
		b.add_theme_stylebox_override("hover", UI.box(Color("2d44a8"), Color("ffd24d"), 4, 14, 0))
		b.add_theme_stylebox_override("pressed", UI.box(Color("3a539c"), Color.WHITE, 5, 14, 0))
		UI.bounce(b)
		b.pressed.connect(choose.bind(i))
		row.add_child(b)
		var m := MarginContainer.new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for side in ["left", "right", "top", "bottom"]:
			m.add_theme_constant_override("margin_" + side, 10)
		b.add_child(m)
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", 6)
		m.add_child(v)
		var pic := KidKit.disc(KidText.illustration(str(o["label"]), str(ev["icon"])), Color("4f8dff"), 64)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(pic)
		var t := UI.lbl("%d · %s" % [i + 1, o["label"]], 17, Color.WHITE, true, 255)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(t)
		var fl := HFlowContainer.new()
		fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fl.alignment = FlowContainer.ALIGNMENT_CENTER
		fl.add_theme_constant_override("h_separation", 5)
		fl.add_theme_constant_override("v_separation", 4)
		v.add_child(fl)
		for c in SpaceEvents.chips_for(o["fx"]):
			var ch := KidKit.chip(str(c["icon"]), str(c["num"]), bool(c["good"]), 16)
			ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
			fl.add_child(ch)
		_buttons.append(b)
	_update_countdown()


func _ignore(l: Label) -> Label:
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(delta: float) -> void:
	_t += delta
	if _icon != null and not resolved:
		var k := 1.0 + 0.12 * sin(_t * 9.0)
		_icon.scale = Vector2(k, k)
		_icon.rotation = sin(_t * 12.0) * 0.06
	_dim.color.a = 0.62 + 0.1 * sin(_t * 6.0)
	_edge.queue_redraw()
	_stripes.queue_redraw()
	if resolved or _closing:
		return
	_left -= delta
	_update_countdown()
	if _left <= 0.0:
		choose(-1)


func _update_countdown() -> void:
	if _count == null:
		return
	var secs := maxi(0, ceili(_left))
	_count.text = "%s %d s" % [str(ev["verb"]), secs]
	var frac := clampf(_left / _total, 0.0, 1.0)
	_bar.max_value = _total
	_bar.value = maxf(0.0, _left)
	var c := _col if frac > 0.34 else Color("ff2a2a")
	UI.set_bar_color(_bar, c)
	_count.add_theme_color_override("font_color", c if frac > 0.34 or int(_t * 4.0) % 2 == 0 else Color.WHITE)


func _input(e: InputEvent) -> void:
	if resolved or _closing:
		return
	if e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo:
		var k := (e as InputEventKey).keycode
		for i in 3:
			if k == KEY_1 + i and i < (ev["options"] as Array).size():
				get_viewport().set_input_as_handled()
				choose(i)
				return


## idx = opcion (0..2) o -1 si se acabo el tiempo. Aplica los efectos y muestra el resultado.
func choose(idx: int) -> void:
	if resolved:
		return
	resolved = true
	for b in _buttons:
		b.disabled = true
	result = SpaceEvents.resolve(s, ev, idx, clampf(_left / _total, 0.0, 1.0))
	_build_result_view()


func _build_result_view() -> void:
	for c in _body.get_children():
		c.queue_free()
	_icon = null
	var timed_out: bool = result["timed_out"]
	# Siempre en positivo: no castigamos, ensenamos
	var head := UI.lbl("⏰ ¡Se acabó el tiempo! Así se aprende." if timed_out else "✅ ¡Decisión tomada!", 30, Color("ffb07a") if timed_out else UI.GREEN)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(head)
	var what := UI.lbl("%s  %s" % [ev["icon"], KidText.sentence(str(ev["title"]))], 22, Color.WHITE)
	what.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(what)
	var say := HBoxContainer.new()
	say.alignment = BoxContainer.ALIGNMENT_CENTER
	say.add_theme_constant_override("separation", 10)
	_body.add_child(say)
	say.add_child(KidKit.disc("🤖", Color("5a7bd0"), 56))
	var bub := PanelContainer.new()
	bub.add_theme_stylebox_override("panel", UI.box(Color("eaf3ff"), Color("8ec5ff"), 3, 12, 10))
	var tx := UI.lbl(KidText.short(str(result["text"]), 100), 20, Color("15306b"), true, 600)
	tx.add_theme_constant_override("outline_size", 0)
	bub.add_child(tx)
	say.add_child(bub)
	# Lo que cambio, en iconos
	var fl := HFlowContainer.new()
	fl.alignment = FlowContainer.ALIGNMENT_CENTER
	fl.add_theme_constant_override("h_separation", 10)
	fl.add_theme_constant_override("v_separation", 8)
	_body.add_child(fl)
	for l in result["lines"]:
		fl.add_child(KidKit.chip(str(l["icon"]), str(l["num"]), bool(l["good"]), 22))
	var sc: int = result["score"]
	var pts := UI.lbl("%s %s%d puntos%s" % ["⭐" if sc >= 0 else "💪", "+" if sc >= 0 else "−", absi(sc), ("   ¡+%d por decidir rápido!" % int(result["bonus"])) if int(result["bonus"]) > 0 else ""],
			24, UI.GOLD if sc >= 0 else Color("ffb07a"))
	pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(pts)
	var fact := UI.lbl("💡 " + str(ev["fact"]), 15, UI.MUTED, true, 820)
	fact.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(fact)
	_body.add_child(UI.btn("¡Seguimos! ▶", Color("28b36a"), close, 24, 58))


## Animacion de salida y fin de la alerta.
func close() -> void:
	if _closing:
		return
	_closing = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "modulate:a", 0.0, 0.25)
	tw.tween_property(_panel, "scale", Vector2(0.8, 0.8), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(_dim, "modulate:a", 0.0, 0.25)
	tw.chain().tween_callback(func() -> void:
		finished.emit(result)
		queue_free())


func _draw_edge() -> void:
	var a := 0.22 + 0.2 * (0.5 + 0.5 * sin(_t * 6.0))
	var sz := _edge.size
	for i in 10:
		var w := float(i) * 9.0
		var c := Color(_col.r, _col.g * 0.4, _col.b * 0.3, a * (1.0 - float(i) / 10.0))
		_edge.draw_rect(Rect2(0, 0, sz.x, w + 9.0), c)
		_edge.draw_rect(Rect2(0, sz.y - w - 9.0, sz.x, w + 9.0), c)
		_edge.draw_rect(Rect2(0, 0, w + 9.0, sz.y), c)
		_edge.draw_rect(Rect2(sz.x - w - 9.0, 0, w + 9.0, sz.y), c)


func _draw_stripes() -> void:
	var sz := _stripes.size
	_stripes.draw_rect(Rect2(Vector2.ZERO, sz), Color("1a0a0a"))
	var off := fmod(_t * 40.0, 52.0)
	var x := -60.0 + off
	while x < sz.x + 30.0:
		_stripes.draw_colored_polygon(PackedVector2Array([Vector2(x, sz.y), Vector2(x + 26.0, sz.y), Vector2(x + 52.0, 0), Vector2(x + 26.0, 0)]), _col)
		x += 52.0
