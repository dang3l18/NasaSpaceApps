extends Node
## Tipografia del juego: Fredoka (redondeada, OFL) como fuente por defecto, con respaldo de emojis
## (Twemoji, Mozilla, CC-BY 4.0) y simbolos (DejaVu Sans, licencia libre Bitstream Vera).
## En escritorio Godot usaria los emojis del sistema, pero en la version web no existe ninguno:
## sin esto los iconos de los botones y las tarjetas no se dibujan.

const KID_FONT := "res://assets/fonts/Fredoka.ttf"
const EMOJI_FONT := "res://assets/fonts/Twemoji.Mozilla.ttf"
const SYMBOL_FONT := "res://assets/fonts/DejaVuSans.ttf"
const KID_WEIGHT := 560.0        # un poco mas gruesa que la normal: se lee mejor en ninos
const DEFAULT_SIZE := 18


func _ready() -> void:
	var chain: Array[Font] = []
	for path in [EMOJI_FONT, SYMBOL_FONT]:
		var f: Font = load(path) as Font
		if f == null:
			push_warning("FontSetup: no se pudo cargar %s" % path)
		else:
			chain.append(f)
	var base: Font = load(KID_FONT) as Font
	if base == null:
		push_warning("FontSetup: no se pudo cargar Fredoka; se usa la fuente por defecto")
		for f in [ThemeDB.fallback_font, ThemeDB.get_default_theme().default_font]:
			if f != null:
				f.fallbacks = chain
		return
	var fv := FontVariation.new()
	fv.base_font = base
	var ts := TextServerManager.get_primary_interface()
	if ts != null:
		fv.variation_opentype = {ts.name_to_tag("weight"): KID_WEIGHT}
	fv.fallbacks = chain
	ThemeDB.fallback_font = fv
	ThemeDB.fallback_font_size = DEFAULT_SIZE
	var th := ThemeDB.get_default_theme()
	th.default_font = fv
	th.default_font_size = DEFAULT_SIZE
