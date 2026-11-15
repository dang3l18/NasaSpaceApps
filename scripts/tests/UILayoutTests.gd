extends Node
## Pruebas de la interfaz movible/ocultable: ocultar, mover, guardar, restaurar y restablecer.
## Respalda y restaura tu user://ui_layout.cfg real para no pisar tus preferencias.
## Ejecutar: godot --headless --path <proyecto> res://scenes/UILayoutTests.tscn

var _pass := 0
var _fail := 0


func _check(c: bool, msg: String) -> void:
	if c:
		_pass += 1
		print("  [OK]    " + msg)
	else:
		_fail += 1
		print("  [FALLO] " + msg)


func _new_game() -> Control:
	var g: Control = load("res://scenes/LunarBase.tscn").instantiate()
	g._simulated = true
	add_child(g)
	await get_tree().process_frame
	return g


func _ready() -> void:
	NASADataManager.simulate_offline = true
	print("=== PRUEBAS DE INTERFAZ MOVIBLE ===")
	var backup := PackedByteArray()
	if FileAccess.file_exists(UILayout.PATH):
		backup = FileAccess.get_file_as_bytes(UILayout.PATH)
	UILayout.reset()

	var g := await _new_game()
	var robot: Control = g._ui["robot"]["node"]
	var module: Control = g._ui["module"]["node"]
	var end_btn: Control = g._ui["end_btn"]["node"]
	_check(g._ui.size() == UILayout.ELEMENTS.size(), "los %d paneles y botones están registrados" % g._ui.size())

	g._set_element_shown(false, "robot")
	_check(not robot.visible, "se puede ocultar el robot asistente")
	g._set_element_shown(false, "end_btn")
	_check(end_btn.visible, "el botón Finalizar turno NO se puede ocultar")
	_check(UILayout.can_hide("robot") and not UILayout.can_hide("gear"), "el botón de interfaz tampoco se puede ocultar")

	g._set_move_mode(true)
	_check(g._overlays.has("module") and not g._overlays.has("robot"), "el modo mover cubre los paneles visibles (no los ocultos)")
	var start: Vector2 = module.position
	var mv := InputEventMouseMotion.new()
	mv.relative = Vector2(-150, 40)
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT
	g._drag_panel(mv, "module")
	_check(module.position == start + Vector2(-150, 40), "arrastrar mueve el panel del módulo")
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	g._drag_panel(rel, "module")
	var far := InputEventMouseMotion.new()
	far.relative = Vector2(-5000, -5000)
	far.button_mask = MOUSE_BUTTON_MASK_LEFT
	g._drag_panel(far, "module")
	_check(module.position.x > -module.size.x and module.position.y >= 0.0, "no se puede sacar un panel por completo de la pantalla")
	g._drag_panel(mv, "module")
	g._drag_panel(rel, "module")
	var saved_pos: Vector2 = module.position
	g.queue_free()
	await get_tree().process_frame

	var g2 := await _new_game()
	_check(not (g2._ui["robot"]["node"] as Control).visible, "al reabrir el juego el robot sigue oculto")
	_check((g2._ui["module"]["node"] as Control).position == saved_pos, "al reabrir el juego el panel está donde lo dejaste")
	g2._reset_layout()
	_check((g2._ui["robot"]["node"] as Control).visible and (g2._ui["module"]["node"] as Control).position == g2._ui["module"]["def"], "restablecer devuelve todo a su sitio")
	g2.queue_free()
	await get_tree().process_frame

	# Restaura las preferencias reales del usuario.
	if backup.size() > 0:
		var f := FileAccess.open(UILayout.PATH, FileAccess.WRITE)
		f.store_buffer(backup)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(UILayout.PATH))
	print("\nRESULTADO: %d OK, %d FALLOS" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
