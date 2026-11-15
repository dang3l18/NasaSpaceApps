class_name UI
extends RefCounted
## Utilidades de interfaz compartidas (estilo visual del juego).

const BG := Color("02040c")
const PANEL := Color("0a1838")
const BORDER := Color("2f6fd6")
const TEXT := Color("e8f1ff")
const MUTED := Color("8fa8d0")
const GOLD := Color("ffd24d")
const GREEN := Color("2ecc71")
const YELLOW := Color("f1b434")
const RED := Color("ff5d5d")
const SIM := Color("b07cff")
const REF := Color("4fc3f7")


static func box(bg: Color, border: Color, w: int = 2, r: int = 10, margin: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(w)
	s.set_corner_radius_all(r)
	s.set_content_margin_all(margin)
	return s


static func lbl(text: String, size: int = 15, col: Color = TEXT, wrap: bool = false, min_w: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(min_w if min_w > 0 else 120, 0)
	return l


static func btn(text: String, col: Color, cb: Callable = Callable(), size: int = 16, height: int = 40) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_size_override("font_size", size)
	for st in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(st, box(col if st == "normal" else col.lightened(0.15), col.lightened(0.4), 2, 10, 8))
	b.add_theme_stylebox_override("disabled", box(Color("1a2438"), Color("2a3550"), 2, 10, 8))
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


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
	return Color("7b8798")


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
	bgs.bg_color = Color("14213f")
	bgs.set_corner_radius_all(5)
	pb.add_theme_stylebox_override("background", bgs)
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(5)
	pb.add_theme_stylebox_override("fill", fill)
	return pb


static func set_bar_color(pb: ProgressBar, col: Color) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(5)
	pb.add_theme_stylebox_override("fill", fill)
