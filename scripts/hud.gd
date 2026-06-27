extends CanvasLayer
class_name HUD
## HUD: barras de vida/maná/XP, stats, barra de jefe, panel de mejora,
## pausa y pantalla de muerte. La TIENDA y el INVENTARIO HD viven en sus propios
## scripts (scripts/ui/shop_panel.gd, scripts/ui/inventory_panel.gd); el HUD los
## instancia como hijos y coordina (les pasa el nodo de escena / les delega).

@onready var xp_fill: TextureRect = $XPBar/Fill
@onready var xp_value: Label = $XPBar/XPValue
@onready var level_value: Label = $XPBar/LevelValue
@onready var stats: Label = $StatsLabel
@onready var boss_ui: Control = $BossUI
@onready var boss_fill: TextureRect = $BossUI/BossBarFill
@onready var boss_name: Label = $BossUI/BossName
@onready var up_panel: Control = $UpgradePanel
@onready var up_title: Label = $UpgradePanel/Title
@onready var up_btns: Array = [$UpgradePanel/Up1, $UpgradePanel/Up2, $UpgradePanel/Up3]
@onready var inv_panel: Control = $InventoryPanel
@onready var pause_panel: Control = $PausePanel
@onready var death_panel: Control = $DeathPanel
@onready var death_sub: Label = $DeathPanel/DSub
@onready var death_title: Label = $DeathPanel/DTitle
@onready var life_preview_fill: TextureRect = $LifeManaPreview/LifeFill
@onready var mana_preview_fill: TextureRect = $LifeManaPreview/ManaFill
@onready var life_preview_value: Label = $LifeManaPreview/LifeValue
@onready var mana_preview_value: Label = $LifeManaPreview/ManaValue

# Paneles extraídos (instanciados como hijos en _ready y coordinados desde acá).
var _shop: ShopPanel
var _inv: InventoryPanel

var _choices: Array = []
var _displayed_xp_ratio := 0.0
var _xp_ratio_initialized := false
var _boss_fill_target := 1.0
var _boss_fill_display := 1.0

# --- Cache de valores para evitar trabajo por frame en _process ---
# Solo empujamos shader params / texto de labels cuando el valor cambió respecto
# al frame anterior (set_shader_parameter y reconstruir strings no son gratis).
var _prev_life_ratio := -1.0
var _prev_mana_ratio := -1.0
var _prev_xp_fill := -1.0
var _prev_life_text := ""
var _prev_mana_text := ""
var _prev_xp_text := ""
var _prev_level_text := ""
# Dirty-flag de la línea de stats: GameState no expone equip_changed ni
# potions_changed, así que cacheamos las entradas y solo reconstruimos
# stats.text (que llama attack_damage(), costoso) cuando alguna cambió.
var _prev_stats_level := -1
var _prev_stats_coins := -2147483648
var _prev_stats_potions := -1
var _prev_stats_dmg := -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	boss_ui.visible = false
	up_panel.visible = false
	inv_panel.visible = false
	pause_panel.visible = false
	death_panel.visible = false
	GameState.boss_spawned.connect(_on_boss_spawn)
	GameState.boss_hp_changed.connect(_on_boss_hp)
	GameState.boss_died.connect(_on_boss_died)
	GameState.level_up.connect(_on_level_up)
	GameState.player_died.connect(_on_death)
	GameState.mode_changed.connect(_on_mode)
	for i in 3:
		up_btns[i].pressed.connect(_pick.bind(i))
	$PausePanel/BtnResume.pressed.connect(_toggle_pause)
	$PausePanel/BtnRestartP.pressed.connect(_restart)
	$DeathPanel/BtnRestartD.pressed.connect(_restart)
	_layout_responsive()
	# Inventario HD: se construye DENTRO del nodo InventoryPanel de la escena (el
	# controlador es un hijo aparte, pero opera sobre ese nodo → identidad y layout 1:1).
	_inv = InventoryPanel.new()
	add_child(_inv)
	_inv.setup(inv_panel)
	# Tienda: panel propio (construido 100% por código) que cuelga del HUD.
	_shop = ShopPanel.new()
	add_child(_shop)

# ---------------- Layout responsive (HUD diseñado a 1152×648 → centrado a cualquier res) ----------------
func _layout_responsive() -> void:
	const DCX := 576.0   # centro del diseño original (1152/2, 648/2)
	const DCY := 324.0
	for pname in ["UpgradePanel", "PausePanel", "DeathPanel", "InventoryPanel"]:
		var panel := get_node_or_null(pname) as Control
		if panel == null:
			continue
		_full_rect(panel)
		for child in panel.get_children():
			if child is Control:
				if child.name == "BG":
					_full_rect(child)
				else:
					_center_rel(child, DCX, DCY)
	var bui := get_node_or_null("BossUI") as Control
	if bui:
		_full_rect(bui)
		for child in bui.get_children():
			if child is Control:
				_center_rel(child, DCX, DCY)

func _full_rect(c: Control) -> void:
	c.anchor_left = 0.0; c.anchor_top = 0.0; c.anchor_right = 1.0; c.anchor_bottom = 1.0
	c.offset_left = 0.0; c.offset_top = 0.0; c.offset_right = 0.0; c.offset_bottom = 0.0

## Re-ancla el control al centro de pantalla preservando su posición relativa al
## centro del diseño original → el layout 1152×648 queda centrado a cualquier res.
func _center_rel(c: Control, cx: float, cy: float) -> void:
	var l := c.offset_left; var t := c.offset_top; var r := c.offset_right; var b := c.offset_bottom
	c.anchor_left = 0.5; c.anchor_right = 0.5; c.anchor_top = 0.5; c.anchor_bottom = 0.5
	c.offset_left = l - cx; c.offset_right = r - cx; c.offset_top = t - cy; c.offset_bottom = b - cy

func _process(_delta: float) -> void:
	var p: Player = GameState.player
	if p == null:
		return
	# max_hp() recorre el equip: lo calculamos una sola vez por frame.
	var pmax_hp := p.max_hp()
	var life_ratio := clampf(float(p.hp) / maxf(1.0, pmax_hp), 0.0, 1.0)
	# Vida: solo tocar el shader/label si cambió el ratio o el texto.
	if not is_equal_approx(life_ratio, _prev_life_ratio):
		(life_preview_fill.material as ShaderMaterial).set_shader_parameter("fill_ratio", life_ratio)
		_prev_life_ratio = life_ratio
	var life_text := "%d / %d" % [int(ceil(float(p.hp))), pmax_hp]
	if life_text != _prev_life_text:
		life_preview_value.text = life_text
		_prev_life_text = life_text
	# Maná: idem.
	var mana_ratio := clampf(p.mana / maxf(1.0, p.max_mana), 0.0, 1.0)
	if not is_equal_approx(mana_ratio, _prev_mana_ratio):
		(mana_preview_fill.material as ShaderMaterial).set_shader_parameter("fill_ratio", mana_ratio)
		_prev_mana_ratio = mana_ratio
	var mana_text := "%d / %d" % [int(round(p.mana)), int(p.max_mana)]
	if mana_text != _prev_mana_text:
		mana_preview_value.text = mana_text
		_prev_mana_text = mana_text
	# XP: la barra se interpola suave, así que el lerp sí corre por frame,
	# pero solo empujamos el shader cuando el valor mostrado realmente cambió.
	var xp_ratio := clampf(float(p.xp) / maxf(1.0, p.xp_to_next), 0.0, 1.0)
	if not _xp_ratio_initialized:
		_displayed_xp_ratio = xp_ratio
		_xp_ratio_initialized = true
	else:
		var xp_smoothing := 1.0 - exp(-8.0 * _delta)
		_displayed_xp_ratio = lerpf(_displayed_xp_ratio, xp_ratio, xp_smoothing)
		if absf(_displayed_xp_ratio - xp_ratio) < 0.0005:
			_displayed_xp_ratio = xp_ratio
	if not is_equal_approx(_displayed_xp_ratio, _prev_xp_fill):
		(xp_fill.material as ShaderMaterial).set_shader_parameter("fill_ratio", _displayed_xp_ratio)
		_prev_xp_fill = _displayed_xp_ratio
	var xp_text := "%d / %d" % [p.xp, p.xp_to_next]
	if xp_text != _prev_xp_text:
		xp_value.text = xp_text
		_prev_xp_text = xp_text
	var level_text := str(p.level)
	if level_text != _prev_level_text:
		level_value.text = level_text
		_prev_level_text = level_text
	# Línea de stats: evitamos el costo real (rearmar el string + reasignar
	# Label.text, que dispara text-shaping/redraw) salvo que algo cambie. Como
	# GameState no expone equip_changed ni potions_changed, comparamos contra los
	# valores cacheados (incluido attack_damage(), que es barato: ~6 lookups del
	# equip). attack_damage() cubre el caso de equipar desde la bolsa, que no
	# altera nivel/monedas/pociones; así el daño nunca queda desactualizado.
	var pdmg := p.attack_damage()
	if p.level != _prev_stats_level or p.coins != _prev_stats_coins \
			or p.potions != _prev_stats_potions or pdmg != _prev_stats_dmg:
		stats.text = "Nivel %d    Monedas %d    Pociones %d    Daño %d" % [p.level, p.coins, p.potions, pdmg]
		_prev_stats_level = p.level
		_prev_stats_coins = p.coins
		_prev_stats_potions = p.potions
		_prev_stats_dmg = pdmg

	# Vaciado suave de la barra de jefe (el líquido baja con un pequeño lag).
	if boss_ui.visible:
		_boss_fill_display = lerpf(_boss_fill_display, _boss_fill_target, 1.0 - exp(-7.0 * _delta))
		if absf(_boss_fill_display - _boss_fill_target) < 0.0008:
			_boss_fill_display = _boss_fill_target
		_set_boss_fill(_boss_fill_display)

	if up_panel.visible or death_panel.visible:
		return
	if Input.is_action_just_pressed("inventory"):
		_inv.toggle()
	elif Input.is_action_just_pressed("pause"):
		if _inv.is_open():
			_inv.toggle()
		else:
			_toggle_pause()

# ---------------- Jefe ----------------
func _on_boss_spawn(b: Node) -> void:
	boss_ui.visible = true
	boss_name.text = b.boss_name
	_boss_fill_target = 1.0
	_boss_fill_display = 1.0
	_set_boss_fill(1.0)

func _on_boss_hp(current: int, maximum: int) -> void:
	_boss_fill_target = clampf(float(current) / maxf(1.0, float(maximum)), 0.0, 1.0)

func _set_boss_fill(ratio: float) -> void:
	var mat := boss_fill.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("fill_ratio", ratio)

func _on_boss_died() -> void:
	boss_ui.visible = false

# ---------------- Mejora de nivel ----------------
func _on_level_up(choices: Array) -> void:
	_choices = choices
	up_title.text = "¡Nivel %d! Elegí una mejora" % GameState.player.level
	for i in 3:
		up_btns[i].text = "%s\n%s" % [choices[i].name, choices[i].desc]
	up_panel.visible = true

func _pick(i: int) -> void:
	GameState.player.apply_upgrade(_choices[i].id)
	up_panel.visible = false
	get_tree().paused = false

# ---------------- Pausa ----------------
func _toggle_pause() -> void:
	if pause_panel.visible:
		pause_panel.visible = false
		get_tree().paused = false
	else:
		pause_panel.visible = true
		get_tree().paused = true

# ---------------- Muerte / reinicio ----------------
func _on_death() -> void:
	_show_end("MORISTE", true)

func _on_mode(m: int) -> void:
	# El HUD se muestra en juego/muerte/victoria (la escena lo trae oculto).
	visible = m == GameState.Mode.PLAY or m == GameState.Mode.DEAD or m == GameState.Mode.WIN
	if m == GameState.Mode.WIN:
		_show_end("¡GANASTE!", false)   # main ya registró el récord y limpió el save

func _show_end(title: String, do_record: bool) -> void:
	var p = GameState.player
	var run = GameState.run
	if do_record:
		SaveSystem.record(run, p, false)
		SaveSystem.clear_run()
	death_title.text = title
	var rec := SaveSystem.get_records()
	death_sub.text = "Prof %d · Nivel %d · %d bajas\nRécord: prof %d · %d bajas" % [
		int(run.get("depth", 1)), p.level, int(run.get("kills", 0)),
		int(rec.get("best_depth", 0)), int(rec.get("best_kills", 0))]
	death_panel.visible = true
	get_tree().paused = true

func _restart() -> void:
	get_tree().paused = false
	SaveSystem.clear_run()   # reiniciar = empezar run nueva
	GameState.reset_run()
	GameState.set_mode(GameState.Mode.PLAY)
	get_tree().reload_current_scene()

# ---------------- Tienda / mercader (API pública: merchant.gd llama hud.open_shop) ----------------
## Se mantiene público y delega al ShopPanel para no romper merchant.gd, que hace
## get_node("HUD").open_shop(self) desde afuera.
func open_shop(merchant) -> void:
	_shop.open(merchant)
