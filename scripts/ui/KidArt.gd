class_name KidArt
extends Control
## Ilustraciones animadas, dibujadas en codigo (ligeras): una escena por evento (llamarada, meteorito, fuga...)
## y para los resultados (celebracion). Se usan en alertas y en la pantalla final: la situacion se entiende
## mirando, sin leer.  Uso: add_child(KidArt.make("flare"))

const KINDS := ["flare", "solar_alert", "meteor", "shower", "leak", "power", "thermal", "eclipse", "dust", "win", "lose"]

var kind := "flare"
var _t := 0.0


static func make(art_kind: String, size: Vector2 = Vector2(300, 170)) -> KidArt:
	var a := KidArt.new()
	a.kind = art_kind
	a.custom_minimum_size = size
	a.size = size
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a.clip_contents = true
	return a


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	# Fondo: espacio con degradado y estrellas fijas
	for i in 8:
		draw_rect(Rect2(0, h * i / 8.0, w, h / 8.0 + 1), Color("0b1240").lerp(Color("1d2d78"), float(i) / 7.0))
	for i in 22:
		draw_circle(Vector2(fmod(i * 97.0, w), fmod(i * 53.0, h * 0.7)), 1.2 + (i % 3) * 0.4, Color(1, 1, 1, 0.5 + 0.4 * sin(_t * 2.0 + i)))
	match kind:
		"flare", "solar_alert": _scene_flare(w, h)
		"meteor": _scene_meteor(w, h, 1)
		"shower": _scene_meteor(w, h, 4)
		"leak": _scene_leak(w, h)
		"power": _scene_power(w, h)
		"thermal": _scene_thermal(w, h)
		"eclipse": _scene_eclipse(w, h)
		"dust": _scene_dust(w, h)
		"win": _scene_party(w, h, true)
		"lose": _scene_party(w, h, false)
		_: _ground(w, h)


# ----------------------------------------------------------------- piezas ----

func _ground(w: float, h: float) -> void:
	var pts := PackedVector2Array([Vector2(0, h)])
	for i in 13:
		pts.append(Vector2(w * i / 12.0, h * 0.82 + 5.0 * sin(i * 0.9)))
	pts.append(Vector2(w, h))
	draw_colored_polygon(pts, Color("a3a9c2"))


func _dome(c: Vector2, r: float, col: Color = Color("f1f5ff")) -> void:
	var pts := PackedVector2Array()
	for k in 25:
		var a := PI * k / 24.0
		pts.append(Vector2(c.x - cos(a) * r, c.y - sin(a) * r))
	draw_colored_polygon(pts, col)
	draw_polyline(pts, Color("9db4d8"), 3.0)
	for k in 3:
		draw_circle(Vector2(c.x - r * 0.45 + k * r * 0.45, c.y - r * 0.4), r * 0.09, Color("ffe08a"))


func _astro(p: Vector2, s: float, jump: float = 0.0, arms_up: bool = false) -> void:
	var o := p + Vector2(0, -jump)
	draw_circle(o + Vector2(0, -22 * s), 9.0 * s, Color("f4f7fc"))
	draw_circle(o + Vector2(0, -22 * s), 6.0 * s, Color("0c1730"))
	draw_circle(o + Vector2(-2 * s, -24 * s), 1.8 * s, Color(0.6, 0.85, 1.0, 0.9))
	draw_rect(Rect2(o + Vector2(-8 * s, -14 * s), Vector2(16 * s, 18 * s)), Color("f4f7fc"))
	draw_rect(Rect2(o + Vector2(-3 * s, -9 * s), Vector2(6 * s, 4 * s)), Color("2f6fd6"))
	draw_rect(Rect2(o + Vector2(-7 * s, 4 * s), Vector2(5 * s, 9 * s)), Color("dfe6f5"))
	draw_rect(Rect2(o + Vector2(2 * s, 4 * s), Vector2(5 * s, 9 * s)), Color("dfe6f5"))
	if arms_up:
		draw_line(o + Vector2(-8 * s, -11 * s), o + Vector2(-15 * s, -22 * s), Color("f4f7fc"), 4.0 * s)
		draw_line(o + Vector2(8 * s, -11 * s), o + Vector2(15 * s, -22 * s), Color("f4f7fc"), 4.0 * s)
	else:
		draw_line(o + Vector2(-8 * s, -11 * s), o + Vector2(-12 * s, -2 * s), Color("f4f7fc"), 4.0 * s)
		draw_line(o + Vector2(8 * s, -11 * s), o + Vector2(12 * s, -2 * s), Color("f4f7fc"), 4.0 * s)


func _sun(c: Vector2, r: float, glow: float = 1.0) -> void:
	for i in 4:
		draw_circle(c, r * (2.2 - i * 0.35), Color(1.0, 0.8, 0.2, 0.06 * glow))
	for k in 12:
		var a := _t * 0.9 + TAU * k / 12.0
		var len_k := r * (1.55 + 0.25 * sin(_t * 4.0 + k))
		draw_line(c + Vector2.from_angle(a) * r * 1.15, c + Vector2.from_angle(a) * len_k, Color("ffb92e"), 4.0)
	draw_circle(c, r, Color("ffd23d"))
	draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.35, Color("fff0a0"))


func _shield_arc(c: Vector2, r: float, a: float) -> void:
	draw_arc(c, r, PI * 1.08, PI * 1.92, 28, Color(0.35, 0.7, 1.0, a), 6.0)
	draw_arc(c, r - 6.0, PI * 1.1, PI * 1.9, 28, Color(0.7, 0.9, 1.0, a * 0.6), 3.0)


# ---------------------------------------------------------------- escenas ----

func _scene_flare(w: float, h: float) -> void:
	_ground(w, h)
	_sun(Vector2(w * 0.8, h * 0.24), 24.0)
	# ondas de radiacion que viajan hacia la base
	for i in 4:
		var f := fmod(_t * 0.6 + i * 0.25, 1.0)
		var p := Vector2(w * 0.8, h * 0.24).lerp(Vector2(w * 0.28, h * 0.7), f)
		draw_arc(p, 8.0 + f * 18.0, PI * 0.6, PI * 1.4, 10, Color(1.0, 0.6, 0.2, 1.0 - f), 4.0)
	var dome := Vector2(w * 0.26, h * 0.82)
	_dome(dome, 46.0)
	_shield_arc(dome, 62.0, 0.5 + 0.4 * sin(_t * 5.0))
	# astronautas corriendo al refugio
	for i in 3:
		var f := fmod(_t * 0.28 + i * 0.3, 1.0)
		var x := lerpf(w * 0.78, w * 0.3, f)
		_astro(Vector2(x, h * 0.82), 0.8, absf(sin(_t * 9.0 + i)) * 4.0)


func _scene_meteor(w: float, h: float, n: int) -> void:
	_ground(w, h)
	var dome := Vector2(w * 0.34, h * 0.82)
	_dome(dome, 48.0)
	var close_to_shield := false
	for i in n:
		var f := fmod(_t * (0.45 + 0.1 * i) + i * (1.0 / float(n)), 1.0)
		var start := Vector2(w * (0.95 - 0.1 * i), -10.0)
		var hit := dome + Vector2(-8.0 + 22.0 * i, -50.0)
		var p := start.lerp(hit, f)
		for k in 8:
			var tp := start.lerp(hit, maxf(0.0, f - k * 0.02))
			draw_circle(tp, 9.0 - k, Color(1.0, 0.5 + 0.05 * k, 0.15, 0.55 - k * 0.06))
		draw_circle(p, 9.0, Color("8a7a70"))
		draw_circle(p + Vector2(-2, -2), 4.0, Color("b7a89c"))
		if f > 0.85:
			close_to_shield = true
	_shield_arc(dome, 64.0, 0.85 if close_to_shield else 0.35)
	_astro(Vector2(w * 0.62, h * 0.82), 0.9, 0.0, close_to_shield)


func _scene_leak(w: float, h: float) -> void:
	_ground(w, h)
	var r := Rect2(w * 0.28, h * 0.36, w * 0.44, h * 0.46)
	draw_rect(r, Color("dfe6f5"))
	draw_rect(r, Color("9db4d8"), false, 4.0)
	for k in 3:
		draw_rect(Rect2(r.position.x + 18 + k * 44, r.position.y + 14, 22, 16), Color("ffe08a"))
	# grieta y burbujas de aire que escapan
	draw_line(Vector2(r.end.x, r.position.y + 40), Vector2(r.end.x - 16, r.position.y + 60), Color("ff5d5d"), 4.0)
	for i in 6:
		var f := fmod(_t * 0.7 + i * 0.17, 1.0)
		var p := Vector2(r.end.x + 4 + f * 70.0, r.position.y + 44 - f * 50.0 + sin(f * 8.0 + i) * 6.0)
		draw_circle(p, 3.0 + f * 7.0, Color(0.8, 0.95, 1.0, 0.8 * (1.0 - f)))
	draw_string(ThemeDB.fallback_font, Vector2(r.position.x + 20, r.end.y - 14), "O₂", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("2f6fd6"))
	_astro(Vector2(w * 0.14, h * 0.82), 0.95, absf(sin(_t * 5.0)) * 3.0, true)


func _scene_power(w: float, h: float) -> void:
	_ground(w, h)
	var b := Rect2(w * 0.3, h * 0.28, w * 0.4, h * 0.46)
	draw_rect(Rect2(b.end.x, b.position.y + b.size.y * 0.3, 10, b.size.y * 0.4), Color("aab2c4"))
	draw_rect(b, Color("2a3150"))
	draw_rect(b, Color("aab2c4"), false, 5.0)
	var level := 0.2 + 0.15 * (0.5 + 0.5 * sin(_t * 3.0))
	draw_rect(Rect2(b.position.x + 8, b.end.y - 8 - (b.size.y - 16) * level, b.size.x - 16, (b.size.y - 16) * level), Color("ff5d5d"))
	var flick := fmod(_t, 0.9) > 0.45
	draw_string(ThemeDB.fallback_font, b.position + Vector2(b.size.x * 0.3, b.size.y * 0.62), "⚡", HORIZONTAL_ALIGNMENT_LEFT, -1, 54, Color("ffd23d") if flick else Color(1, 1, 1, 0.3))
	for i in 5:   # bombillas que parpadean
		var on := fmod(_t * 2.0 + i * 0.37, 1.0) > 0.4
		draw_circle(Vector2(w * 0.1 + i * w * 0.2, h * 0.14), 8.0, Color("ffe08a") if on else Color("3a4468"))


func _scene_thermal(w: float, h: float) -> void:
	_ground(w, h)
	var tc := Vector2(w * 0.5, h * 0.2)
	draw_rect(Rect2(tc.x - 9, tc.y, 18, h * 0.5), Color("e8eefc"))
	draw_circle(Vector2(tc.x, tc.y + h * 0.5 + 6), 17.0, Color("ff5d5d"))
	var f := 0.55 + 0.35 * sin(_t * 1.8)
	draw_rect(Rect2(tc.x - 5, tc.y + h * 0.5 * (1.0 - f), 10, h * 0.5 * f + 4), Color("ff5d5d"))
	for i in 5:   # ondas de calor
		var x := w * (0.14 + i * 0.18)
		var pts := PackedVector2Array()
		for k in 12:
			pts.append(Vector2(x + sin(k * 0.8 + _t * 4.0 + i) * 6.0, h * 0.8 - k * 9.0))
		draw_polyline(pts, Color(1.0, 0.55, 0.2, 0.6), 3.0)
	_astro(Vector2(w * 0.86, h * 0.82), 0.85, 0.0, false)


func _scene_eclipse(w: float, h: float) -> void:
	_ground(w, h)
	var sc := Vector2(w * 0.5, h * 0.3)
	_sun(sc, 26.0, 0.6)
	var mx := sc.x + sin(_t * 0.7) * 22.0
	draw_circle(Vector2(mx, sc.y), 29.0, Color("747a92"))
	draw_circle(Vector2(mx - 8, sc.y - 6), 7.0, Color("5f6580"))
	for i in 2:   # paneles que pierden luz
		var pr := Rect2(w * (0.12 + i * 0.58), h * 0.58, w * 0.28, h * 0.2)
		draw_rect(pr, Color("2a4fb0"))
		draw_rect(pr, Color("6a8fe8"), false, 3.0)
		draw_line(pr.position + Vector2(pr.size.x * 0.5, 0), pr.position + Vector2(pr.size.x * 0.5, pr.size.y), Color("6a8fe8"), 2.0)


func _scene_dust(w: float, h: float) -> void:
	_ground(w, h)
	for i in 40:
		var f := fmod(_t * (0.3 + (i % 5) * 0.08) + i * 0.071, 1.0)
		var p := Vector2(f * (w + 40.0) - 20.0, h * (0.2 + 0.6 * fmod(i * 0.37, 1.0)) + sin(_t * 3.0 + i) * 8.0)
		draw_circle(p, 2.5 + (i % 4), Color(0.85, 0.5, 0.3, 0.55))
	var pr := Rect2(w * 0.3, h * 0.6, w * 0.4, h * 0.2)
	draw_rect(pr, Color("2a4fb0"))
	draw_rect(pr, Color("6a8fe8"), false, 3.0)


func _scene_party(w: float, h: float, win: bool) -> void:
	_ground(w, h)
	_dome(Vector2(w * 0.5, h * 0.82), 54.0)
	for i in (3 if win else 2):
		var x := w * (0.2 + i * 0.3) if win else w * (0.3 + i * 0.4)
		_astro(Vector2(x, h * 0.82), 1.05, (absf(sin(_t * 5.0 + i * 1.3)) * 14.0) if win else (absf(sin(_t * 2.0 + i)) * 3.0), win)
	if win:   # confeti
		for i in 36:
			var f := fmod(_t * (0.25 + (i % 4) * 0.07) + i * 0.13, 1.0)
			var p := Vector2(fmod(i * 41.0, w), f * h)
			var cols := [Color("ffd23d"), Color("ff6b6b"), Color("5fe0ff"), Color("7be88a"), Color("c39bff")]
			draw_rect(Rect2(p, Vector2(6, 9)), cols[i % 5])
	else:     # el robot anima: nada de caras tristes
		KidKit.draw_robot(self, Vector2(w * 0.5 - 31.0, h * 0.2), _t, absf(sin(_t * 3.0)) * 0.6, 2, 0.9)
