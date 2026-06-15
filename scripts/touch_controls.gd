extends CanvasLayer
## Controles táctiles (mobile): joystick virtual (mover) + botones (atacar/dash/
## poción/interactuar). Multitouch real (TouchScreenButton + ScreenTouch/Drag para
## el joystick). Solo visible si hay pantalla táctil; en desktop se oculta.

const MOVE := ["move_left", "move_right", "move_up", "move_down"]

var _tex: Texture2D
var _joy_base: Sprite2D
var _joy_knob: Sprite2D
var _joy_idx := -1
var _joy_origin := Vector2.ZERO
var _radius := 90.0
var _home := Vector2.ZERO

const FORCE_TEST := false   # solo se muestran si hay pantalla táctil

func _ready() -> void:
	layer = 4   # sobre el HUD (2), debajo del panel de luz (5)
	if not FORCE_TEST and not DisplayServer.is_touchscreen_available():
		visible = false
		set_process_input(false)
		return
	Touch.active = true
	_tex = _make_circle(128)
	var vp := get_viewport().get_visible_rect().size
	_home = Vector2(210, vp.y - 210)
	_joy_base = _disc(_home, 1.4, Color(1, 1, 1, 0.12))
	_joy_knob = _disc(_home, 0.72, Color(1, 1, 1, 0.22))
	var bx := vp.x - 175.0
	var by := vp.y - 175.0
	_button("attack", Vector2(bx, by), 1.3, "⚔")
	_button("dash", Vector2(bx - 165, by - 30), 0.95, "»")
	_button("potion", Vector2(bx - 30, by - 175), 0.95, "♥")
	_button("interact", Vector2(bx - 185, by - 165), 0.85, "E")

func _disc(pos: Vector2, scl: float, col: Color) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = _tex
	s.position = pos
	s.scale = Vector2(scl, scl)
	s.modulate = col
	add_child(s)
	return s

func _button(action: String, center: Vector2, scl: float, glyph: String) -> void:
	var tb := TouchScreenButton.new()
	tb.texture_normal = _tex
	tb.scale = Vector2(scl, scl)
	tb.position = center - Vector2(_tex.get_width(), _tex.get_height()) * 0.5 * scl
	tb.modulate = Color(1, 1, 1, 0.28)
	tb.action = action
	var shape := CircleShape2D.new()
	shape.radius = _tex.get_width() * 0.5
	tb.shape = shape
	add_child(tb)
	var l := Label.new()
	l.text = glyph
	l.add_theme_font_size_override("font_size", 40)
	l.position = Vector2(_tex.get_width() * 0.5 - 18, _tex.get_height() * 0.5 - 28)
	l.modulate = Color(1, 1, 1, 2.2)   # >1 para que resalte sobre el disco translúcido
	tb.add_child(l)

func _input(event: InputEvent) -> void:
	# Casts explícitos: en export el parser no estrecha el tipo de `event` dentro
	# de condiciones compuestas (elif ... and ...), así que tipamos a mano.
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _joy_idx == -1 and t.position.x < get_viewport().get_visible_rect().size.x * 0.5:
				_joy_idx = t.index
				_joy_origin = t.position
				_joy_base.position = t.position
				_joy_knob.position = t.position
		elif t.index == _joy_idx:
			_joy_idx = -1
			_release_move()
			_joy_base.position = _home
			_joy_knob.position = _home
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _joy_idx:
			var off: Vector2 = d.position - _joy_origin
			if off.length() > _radius:
				off = off.normalized() * _radius
			_joy_knob.position = _joy_origin + off
			_apply_move(off)

func _apply_move(off: Vector2) -> void:
	var dz := _radius * 0.3
	_set_action("move_left", off.x < -dz)
	_set_action("move_right", off.x > dz)
	_set_action("move_up", off.y < -dz)
	_set_action("move_down", off.y > dz)

func _set_action(a: String, on: bool) -> void:
	if on and not Input.is_action_pressed(a):
		Input.action_press(a)
	elif not on and Input.is_action_pressed(a):
		Input.action_release(a)

func _release_move() -> void:
	for a in MOVE:
		Input.action_release(a)

func _make_circle(s: int) -> ImageTexture:
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s / 2.0, s / 2.0)
	for y in s:
		for x in s:
			var d := Vector2(x, y).distance_to(c) / (s / 2.0)
			var a := clampf((0.95 - d) / 0.12, 0.0, 1.0)   # disco lleno, borde suave
			# anillo apenas más marcado
			var ring := 1.0 - clampf(absf(d - 0.82) / 0.12, 0.0, 1.0)
			var v := clampf(0.75 + 0.25 * ring, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v, a))
	return ImageTexture.create_from_image(img)
