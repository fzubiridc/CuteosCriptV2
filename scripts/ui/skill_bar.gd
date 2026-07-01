extends Control
class_name SkillBar
## Barra de acción clásica de RPG: 4 slots (teclas 1-4) con ícono + cooldown radial + coste de
## maná. Lee player.skill_slots / player.skill_cd. Incluye un panel de asignación (tecla K) para
## poner cualquier habilidad disponible (AbilityDefs) en cualquier slot.
##
## Se instancia como hijo del HUD (hud.gd _ready). El arte de los íconos lo pone Felipe en
## assets/ui/skills/<id>.png (si no hay, AbilityDefs genera una gema placeholder).

const SLOTS := 4
const SLOT := 54.0       # lado del slot (px)
const GAP := 8.0
const BOTTOM_OFFSET := 150.0   # alto desde el borde inferior (arriba de la barra de XP)

var _slot_bg: Array = []
var _slot_icon: Array = []
var _slot_cd: Array = []        # overlay oscuro de cooldown (se "drena")
var _slot_cd_label: Array = []
var _slot_key: Array = []
var _shown := ["", "", "", ""]  # id de habilidad mostrado en cada slot (evita re-setear la textura por frame)

var _panel: Control             # panel de asignación
var _sel_slot := 0              # slot seleccionado en el panel
var _panel_slot_btns: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_bar()
	_build_panel()
	GameState.skills_changed.connect(_refresh_icons)
	_refresh_icons()

# ---------------- Barra (siempre visible) ----------------
func _build_bar() -> void:
	var root := Control.new()
	root.anchor_left = 0.5; root.anchor_right = 0.5
	root.anchor_top = 1.0; root.anchor_bottom = 1.0
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var total_w := SLOTS * SLOT + (SLOTS - 1) * GAP
	var start_x := -total_w / 2.0
	for i in SLOTS:
		var box := Control.new()
		box.position = Vector2(start_x + i * (SLOT + GAP), -BOTTOM_OFFSET - SLOT)
		box.custom_minimum_size = Vector2(SLOT, SLOT)
		box.size = Vector2(SLOT, SLOT)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(box)
		# Backdrop oscuro: garantiza que el slot se vea aunque slot.png sea sutil o no cargue.
		var back := ColorRect.new()
		back.color = Color(0.05, 0.05, 0.08, 0.74)
		back.set_anchors_preset(Control.PRESET_FULL_RECT)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(back)
		# Fondo del slot (asset del kit UI).
		var bg := TextureRect.new()
		bg.texture = load("res://assets/ui/slot.png")
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(bg)
		_slot_bg.append(bg)
		# Ícono de la habilidad.
		var icon := TextureRect.new()
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 7; icon.offset_top = 7; icon.offset_right = -7; icon.offset_bottom = -7
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(icon)
		_slot_icon.append(icon)
		# Overlay de cooldown (oscurece y se drena de arriba hacia abajo).
		var cd := ColorRect.new()
		cd.color = Color(0.02, 0.03, 0.06, 0.66)
		cd.set_anchors_preset(Control.PRESET_FULL_RECT)
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cd.visible = false
		box.add_child(cd)
		_slot_cd.append(cd)
		# Segundos restantes (sobre el overlay).
		var cdl := Label.new()
		cdl.set_anchors_preset(Control.PRESET_FULL_RECT)
		cdl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cdl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cdl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiTheme.apply_small_ui(cdl, 18, Color(1, 1, 1))
		cdl.visible = false
		box.add_child(cdl)
		_slot_cd_label.append(cdl)
		# Tecla (1-4), esquina sup-izq.
		var key := Label.new()
		key.text = str(i + 1)
		key.position = Vector2(4, 1)
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiTheme.apply_small_ui(key, 15, UiTheme.GOLD)
		box.add_child(key)
		_slot_key.append(key)

## Invalida los íconos mostrados → _process reaplica el correcto el próximo frame (un solo lugar
## que castea/lee al player, evitando castear un objeto liberado desde la señal).
func _refresh_icons() -> void:
	for i in SLOTS:
		_shown[i] = "￿"

func _process(_dt: float) -> void:
	if Input.is_action_just_pressed("skills_menu"):
		_toggle_panel()
	if not is_instance_valid(GameState.player):   # al menú: player liberado → no castear freed
		return
	var p := GameState.player as Player
	for i in SLOTS:
		var id := String(p.skill_slots[i]) if i < p.skill_slots.size() else ""
		# Sincroniza el ícono si cambió (cubre run nueva: la señal skills_changed pudo no llegar).
		if id != _shown[i]:
			_shown[i] = id
			if id != "" and AbilityDefs.has(id):
				_slot_icon[i].texture = AbilityDefs.icon(id)
				_slot_icon[i].visible = true
			else:
				_slot_icon[i].visible = false
		if id == "" or not AbilityDefs.has(id):
			_slot_cd[i].visible = false
			_slot_cd_label[i].visible = false
			continue
		var d := AbilityDefs.get_def(id)
		var total := float(d.get("cooldown", 0.0))
		var rem := float(p.skill_cd[i]) if i < p.skill_cd.size() else 0.0
		if rem > 0.05 and total > 0.0:
			var ratio := clampf(rem / total, 0.0, 1.0)
			_slot_cd[i].visible = true
			_slot_cd[i].offset_top = SLOT * (1.0 - ratio)   # se drena de arriba hacia abajo
			_slot_cd_label[i].visible = true
			_slot_cd_label[i].text = "%d" % int(ceil(rem))
		else:
			_slot_cd[i].visible = false
			_slot_cd_label[i].visible = false
		# Atenúa el ícono si no alcanza el maná.
		var enough: bool = p.mana >= float(d.get("mana", 0.0))
		_slot_icon[i].modulate = Color(1, 1, 1, 1) if enough else Color(0.5, 0.5, 0.55, 0.8)

# ---------------- Panel de asignación (tecla K) ----------------
func _build_panel() -> void:
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.visible = false
	add_child(_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(dim)
	# CenterContainer → el panel se centra y se dimensiona al contenido (nunca se va de pantalla,
	# pase lo que pase con la resolución/stretch).
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(center)
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	center.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	box.add_child(vb)
	var title := UiTheme.section_header_label("HABILIDADES", 26, UiTheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var hint := UiTheme.narrative_label("Elegí un slot y asignale una habilidad.   [K] cerrar", 17, UiTheme.PARCHMENT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint)
	# Fila de los 4 slots (botones).
	var slots_row := HBoxContainer.new()
	slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_row.add_theme_constant_override("separation", 10)
	vb.add_child(slots_row)
	for i in SLOTS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(72, 72)
		b.expand_icon = true
		b.text = str(i + 1)
		b.pressed.connect(_select_slot.bind(i))
		slots_row.add_child(b)
		_panel_slot_btns.append(b)
	var sep := UiTheme.narrative_label("— Habilidades disponibles —", 16, UiTheme.MUTED_WARM)
	sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sep)
	# Grilla de habilidades disponibles.
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(grid)
	for id in AbilityDefs.ids():
		var d := AbilityDefs.get_def(id)
		var ab := Button.new()
		ab.custom_minimum_size = Vector2(150, 52)
		ab.icon = AbilityDefs.icon(id)
		ab.expand_icon = false
		ab.text = "  " + String(d.get("name", id))
		ab.tooltip_text = String(d.get("desc", ""))
		ab.alignment = HORIZONTAL_ALIGNMENT_LEFT
		ab.pressed.connect(_assign.bind(id))
		grid.add_child(ab)

func _toggle_panel() -> void:
	if _panel.visible:
		_panel.visible = false
		get_tree().paused = false
	else:
		if GameState.mode != GameState.Mode.PLAY:
			return
		_select_slot(0)
		_panel.visible = true
		get_tree().paused = true

## ¿El panel de asignación está abierto? (lo usa el watchdog anti-soft-lock del HUD.)
func is_open() -> bool:
	return is_instance_valid(_panel) and _panel.visible

func _select_slot(i: int) -> void:
	_sel_slot = i
	for k in SLOTS:
		var b: Button = _panel_slot_btns[k]
		var id := ""
		var p := GameState.player as Player
		if p != null and k < p.skill_slots.size():
			id = String(p.skill_slots[k])
		b.icon = AbilityDefs.icon(id) if AbilityDefs.has(id) else null
		# Resalta el slot seleccionado.
		b.modulate = Color(1, 1, 1) if k == _sel_slot else Color(0.7, 0.7, 0.75)

func _assign(id: String) -> void:
	var p := GameState.player as Player
	if p == null:
		return
	p.assign_skill(_sel_slot, id)
	_refresh_icons()
	_select_slot(_sel_slot)   # actualiza el ícono del botón del slot
