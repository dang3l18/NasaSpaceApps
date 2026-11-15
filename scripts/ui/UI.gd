class_name UI
extends RefCounted
## Sistema de diseno infantil de ZYRANTH: colores vivos, bordes muy redondeados, sombras suaves,
## botones grandes que "se hunden" al pulsar y textos legibles. Todo el juego pasa por aqui.

const BG := Color("070b2a")
const PANEL := Color("1b2a72")
const BORDER := Color("6db6ff")
const TEXT := Color("f6f9ff")
const MUTED := Color("c0d0f2")
const GOLD := Color("ffd24d")
const GREEN := Color("3ddc84")
const YELLOW := Color("ffc83d")
const RED := Color("ff6b6b")
const SIM := Color("c39bff")
const REF := Color("5fd0ff")

const MIN_FONT := 14           # nunca se dibuja texto mas pequeno que esto
const FONT_SCALE := 1.1        # todo el texto se agranda un poco


static func box(bg: Color, border: Color, w: int = 2, r: int = 10, margin: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(w)
	s.set_corner_radius_all(r + 6)
	s.set_content_margin_all(margin)
	s.shadow_color = Color(0, 0, 0, 0.32)   # sombra suave
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 3)
	return s


## Panel claro de interfaz (para ventanas, paneles de recursos...).
static func panel_box(alpha: float = 0.94, border: Color = BORDER, margin: int = 10) -> StyleBoxFlat:
	return box(Color(PANEL.r, PANEL.g, PANEL.b, alpha), border, 3, 12, margin)


static func lbl(text: String, size: int = 15, col: Color = TEXT, wrap: bool = false, min_w: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", maxi(MIN_FONT, int(round(size * FONT_SCALE))))
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.18, 0.55))
	l.add_theme_constant_override("outline_size", 3 if size >= 20 else 0)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(min_w if min_w > 0 else 120, 0)
	return l


## Boton grande y redondeado: se ve "en relieve", reacciona al pasar el raton y rebota al pulsarlo.
static func btn(text: String, col: Color, cb: Callable = Callable(), size: int = 16, height: int = 40) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, maxi(height, 44))
	b.add_theme_font_size_override("font_size", maxi(MIN_FONT, int(round(size * FONT_SCALE))))
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color("7f8cab"))
	b.add_theme_color_override("font_outline_color", col.darkened(0.55))
	b.add_theme_constant_override("outline_size", 4)
	b.add_theme_stylebox_override("normal", press_box(col, false))
	b.add_theme_stylebox_override("hover", press_box(col.lightened(0.14), false))
	b.add_theme_stylebox_override("pressed", press_box(col.darkened(0.08), true))
	b.add_theme_stylebox_override("disabled", press_box(Color("3a4468"), false, true))
	b.focus_mode = Control.FOCUS_NONE
	bounce(b)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


## Estilo de boton con borde inferior grueso (parece un boton fisico); al pulsar se "hunde".
static func press_box(col: Color, down: bool, flat: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.border_color = col.darkened(0.38) if not flat else Color("2c3454")
	s.set_border_width_all(2)
	s.border_width_bottom = 2 if down else 6
	s.set_corner_radius_all(18)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 12 if down else 8
	s.content_margin_bottom = 8 if down else 12
	s.shadow_color = Color(0, 0, 0, 0.3)
	s.shadow_size = 3
	s.shadow_offset = Vector2(0, 2)
	return s


## Animacion de boton: crece un poco al pasar el raton y rebota al pulsar. Ligera (solo escala).
static func bounce(b: Control) -> void:
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.mouse_entered.connect(func() -> void:
		if b is BaseButton and (b as BaseButton).disabled:
			return
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2(1.04, 1.04), 0.08))
	b.mouse_exited.connect(func() -> void:
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2.ONE, 0.1))
	if b is BaseButton:
		(b as BaseButton).button_down.connect(func() -> void:
			var tw := b.create_tween()
			tw.tween_property(b, "scale", Vector2(0.94, 0.94), 0.06))
		(b as BaseButton).button_up.connect(func() -> void:
			var tw := b.create_tween()
			tw.tween_property(b, "scale", Vector2(1.0, 1.0), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))


## Semaforo: 2 verde, 1 amarillo, 0 rojo (segun un valor 0-100).
static func light_of(v: float) -> int:
	return 2 if v >= 60.0 else (1 if v >= 30.0 else 0)


static func light_color(level: int) -> Color:
	return [RED, YELLOW, GREEN][clampi(level, 0, 2)]


## Color de la etiqueta de procedencia de un dato.
static func label_color(label: String) -> Color:
	match label:
		ScientificDataManager.LABEL_REAL: return GREEN
		ScientificDataManager.LABEL_HISTORIC: return YELLOW
		ScientificDataManager.LABEL_SIM: return SIM
		ScientificDataManager.LABEL_REF: return REF
		ScientificDataManager.LABEL_PARAM: return SIM
	return Color("9aa8c4")


static func badge(label: String, size: int = 13) -> Label:
	var col := label_color(label)
	var l := lbl(" %s " % label, size, col)
	l.add_theme_stylebox_override("normal", box(col.darkened(0.55), col, 2, 12, 2))
	return l


static func bar(value: float, max_value: float, col: Color, height: int = 12) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(0, height)
	pb.show_percentage = false
	pb.max_value = max_value
	pb.value = value
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = Color("0d1648")
	bgs.set_corner_radius_all(height)
	bgs.set_border_width_all(2)
	bgs.border_color = Color("0a1030")
	pb.add_theme_stylebox_override("background", bgs)
	pb.add_theme_stylebox_override("fill", _fill(col, height))
	return pb


static func set_bar_color(pb: ProgressBar, col: Color) -> void:
	pb.add_theme_stylebox_override("fill", _fill(col, int(pb.custom_minimum_size.y)))


static func _fill(col: Color, height: int) -> StyleBoxFlat:
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(maxi(height, 8))
	fill.border_width_top = 3   # brillo superior: da volumen a la barra
	fill.border_color = col.lightened(0.35)
	return fill
