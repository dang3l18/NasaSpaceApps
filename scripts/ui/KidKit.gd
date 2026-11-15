class_name KidKit
extends RefCounted
## Componentes reutilizables del rediseno infantil: disco de ilustracion, chip de recurso (icono + numero),
## medidor con icono grande y tres estados, globo de dialogo y puntos de progreso.

const FOOD_ICON := "🍎"


## Ilustracion circular: emoji grande sobre un disco de color con borde y sombra.
static func disc(emoji: String, col: Color, size: int = 64) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(size, size)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var st := UI.box(col.darkened(0.25), col.lightened(0.35), 3, size / 2 - 6, 0)
	p.add_theme_stylebox_override("panel", st)
	var l := Label.new()
	l.text = emoji
	l.add_theme_font_size_override("font_size", int(size * 0.56))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## Pastilla pequena: icono + numero opcional ("⚡ −70"). `good` pinta de verde o de rojo.
static func chip(emoji: String, text: String, good: bool, size: int = 18) -> PanelContainer:
	var col := UI.GREEN if good else UI.RED
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(col.darkened(0.62), col, 2, 8, 4))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	p.add_child(h)
	var ic := Label.new()
	ic.text = emoji
	ic.add_theme_font_size_override("font_size", int(size * 1.35))
	h.add_child(ic)
	if text != "":
		h.add_child(UI.lbl(text, size, Color.WHITE))
	return p


## Medidor: icono grande + nombre + simbolo de estado + barra. Devuelve un diccionario para actualizarlo.
static func meter(emoji: String, title: String, base: Color) -> Dictionary:
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	var disc_p := disc(emoji, base, 46)
	root.add_child(disc_p)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 1)
	root.add_child(col)
	var top := HBoxContainer.new()
	col.add_child(top)
	var name_l := UI.lbl(title, 15, UI.TEXT)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_l)
	var val := UI.lbl("", 16, UI.TEXT)
	top.add_child(val)
	var pb := UI.bar(100, 100, UI.GREEN, 16)
	col.add_child(pb)
	return {"root": root, "bar": pb, "val": val, "disc": disc_p, "name": name_l, "title": title}


## Actualiza un medidor: barra, color del semaforo y simbolo (✔ ⚠ ✖) junto al numero. `shown` = numero a mostrar.
static func set_meter(m: Dictionary, value: float, shown: float = -1.0) -> void:
	var lvl := UI.light_of(value)
	var st := KidText.state(lvl)
	var pb: ProgressBar = m["bar"]
	pb.value = clampf(value, 0.0, 100.0)
	UI.set_bar_color(pb, st["col"])
	(m["val"] as Label).text = "%s %d" % [st["icon"], int(round(value if shown < 0.0 else shown))]
	(m["val"] as Label).add_theme_color_override("font_color", st["col"] if lvl < 2 else Color.WHITE)


## Robot asistente simpatico (se dibuja sobre cualquier Control). `t` = tiempo para animar, `hop` 0..1 = salto de alegria.
static func draw_robot(c: Control, origin: Vector2, t: float, hop: float = 0.0, mood: int = 1, k: float = 1.0) -> void:
	var bob := sin(t * 2.0) * 2.0 - hop * 10.0
	var o := origin
	c.draw_set_transform(o, 0.0, Vector2(k, k))
	var body := UI.press_box(Color("5a7bd0"), false)
	body.set_corner_radius_all(10)
	c.draw_style_box(body, Rect2(17, 58 + bob, 28, 20))
	c.draw_circle(Vector2(31, 62 + bob), 5.0, Color("ffd24d"))
	c.draw_circle(Vector2(31, 36 + bob), 27.0, Color("f4f7fc"))
	c.draw_arc(Vector2(31, 36 + bob), 27.0, 0, TAU, 40, Color("aab6cf"), 3.0)
	c.draw_circle(Vector2(31, 37 + bob), 20.0, Color("0c1730"))
	var blink: bool = fmod(t, 3.4) > 3.25
	var ey := 4.0 if not blink else 1.0
	if mood >= 2:   # contento: ojos en arco (^ ^) y sonrisa grande
		c.draw_arc(Vector2(24.5, 36 + bob), 4.5, PI * 1.1, PI * 1.9, 8, Color("5fe0ff"), 3.0)
		c.draw_arc(Vector2(38.5, 36 + bob), 4.5, PI * 1.1, PI * 1.9, 8, Color("5fe0ff"), 3.0)
		c.draw_arc(Vector2(31, 41 + bob), 8.0, 0.1 * PI, 0.9 * PI, 12, Color("5fe0ff"), 3.0)
	else:
		c.draw_rect(Rect2(21, 34 + bob - ey * 0.5, 7, ey * 2.0), Color("5fe0ff"))
		c.draw_rect(Rect2(35, 34 + bob - ey * 0.5, 7, ey * 2.0), Color("5fe0ff"))
	if mood == 1:   # sonrisa; con mood 0 la boca es plana (preocupado)
		c.draw_arc(Vector2(31, 41 + bob), 6.0, 0.15 * PI, 0.85 * PI, 10, Color("5fe0ff"), 2.0)
	elif mood >= 2:
		pass
	else:
		c.draw_line(Vector2(26, 46 + bob), Vector2(36, 46 + bob), Color("5fe0ff"), 2.0)
	c.draw_line(Vector2(31, 9 + bob), Vector2(31, 1 + bob), Color("aab2c4"), 3.0)
	c.draw_circle(Vector2(31, 1 + bob), 3.5, Color("ff5d5d") if fmod(t, 1.0) < 0.5 else Color("ff9d9d"))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Tres vinetas: como se juega (sin parrafos). Devuelve un HBox listo para insertar.
static func how_to_play() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	var steps := [["👆", "Toca un edificio", Color("4f8dff")], ["⚡🧱⏱", "Gasta con cuidado", Color("f1b434")], ["🛡️", "Protege al equipo", Color("3ddc84")]]
	for i in steps.size():
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", UI.box(Color(0.1, 0.16, 0.45, 0.9), steps[i][2], 3, 10, 8))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		card.add_child(v)
		var num := UI.lbl("%d" % (i + 1), 16, steps[i][2])
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(num)
		var ic := Label.new()
		ic.text = steps[i][0]
		ic.add_theme_font_size_override("font_size", 38)
		ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(ic)
		var tx := UI.lbl(steps[i][1], 16, UI.TEXT)
		tx.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(tx)
		row.add_child(card)
		if i < steps.size() - 1:
			row.add_child(UI.lbl("➜", 26, UI.GOLD))
	return row


## «Proteges / Sacrificas» como iconos (el texto largo queda para quien quiera leerlo con el cursor encima).
static func protect_sacrifice(protect: String, sacrifice: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for it in [["🛡️ Proteges", protect, UI.GREEN], ["✂️ Sacrificas", sacrifice, Color("ff9d5d")]]:
		var p := PanelContainer.new()
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.tooltip_text = str(it[1])
		p.add_theme_stylebox_override("panel", UI.box(Color(it[2]).darkened(0.7), it[2], 3, 12, 8))
		var v := VBoxContainer.new()
		p.add_child(v)
		v.add_child(UI.lbl(str(it[0]), 17, it[2]))
		var icons := HFlowContainer.new()
		icons.add_theme_constant_override("h_separation", 6)
		v.add_child(icons)
		for ic in KidText.icons_in(str(it[1])).slice(0, 5):
			icons.add_child(disc(str(ic), it[2], 44))
		row.add_child(p)
	return row


## Puntos de progreso de turnos: llenos (hecho), dorado (turno actual), vacios (pendientes).
static func turn_dots(total: int, get_turn: Callable, night_from: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(total * 22, 24)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		var current: int = int(get_turn.call())
		for i in total:
			var cx := 11.0 + i * 22.0
			var t := i + 1
			var day := t < night_from
			var col := Color("ffd24d") if day else Color("9db4ff")
			if t < current:
				c.draw_circle(Vector2(cx, 12), 8.0, col.darkened(0.15))
			elif t == current:
				c.draw_circle(Vector2(cx, 12), 10.5, Color.WHITE)
				c.draw_circle(Vector2(cx, 12), 8.0, col)
			else:
				c.draw_arc(Vector2(cx, 12), 7.0, 0.0, TAU, 20, col.darkened(0.3), 2.5))
	return c
