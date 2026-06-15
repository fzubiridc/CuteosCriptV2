extends CanvasLayer
## HUD: barras de vida/maná/XP, stats, barra de jefe, panel de mejora,
## inventario, pausa y pantalla de muerte.

const BAR_W := 220.0

@onready var hp_fill: ColorRect = $HPFill
@onready var mana_fill: ColorRect = $ManaFill
@onready var xp_fill: ColorRect = $XPFill
@onready var stats: Label = $StatsLabel
@onready var boss_ui: Control = $BossUI
@onready var boss_bar: ProgressBar = $BossUI/BossBar
@onready var boss_name: Label = $BossUI/BossName
@onready var up_panel: Control = $UpgradePanel
@onready var up_title: Label = $UpgradePanel/Title
@onready var up_btns: Array = [$UpgradePanel/Up1, $UpgradePanel/Up2, $UpgradePanel/Up3]
@onready var inv_panel: Control = $InventoryPanel
@onready var inv_equip: Label = $InventoryPanel/EquipLabel
@onready var inv_bag: VBoxContainer = $InventoryPanel/BagList
@onready var pause_panel: Control = $PausePanel
@onready var death_panel: Control = $DeathPanel
@onready var death_sub: Label = $DeathPanel/DSub
@onready var death_title: Label = $DeathPanel/DTitle

var _choices: Array = []
var _shop_panel: Control
var _shop_merchant = null
var _shop_just_opened := false

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
	# Cerrar tienda con E (con guarda de 1 frame para no cerrarla al abrirla).
	if _shop_panel and is_instance_valid(_shop_panel):
		if _shop_just_opened:
			_shop_just_opened = false
		elif Input.is_action_just_pressed("interact"):
			_close_shop()
	var p = GameState.player
	if p == null:
		return
	hp_fill.size.x = BAR_W * clampf(float(p.hp) / maxf(1.0, p.max_hp()), 0.0, 1.0)
	mana_fill.size.x = BAR_W * clampf(p.mana / p.max_mana, 0.0, 1.0)
	xp_fill.size.x = BAR_W * clampf(float(p.xp) / maxf(1.0, p.xp_to_next), 0.0, 1.0)
	stats.text = "Nivel %d    Monedas %d    Pociones %d    Daño %d" % [p.level, p.coins, p.potions, p.attack_damage()]

	if up_panel.visible or death_panel.visible:
		return
	if Input.is_action_just_pressed("inventory"):
		_toggle_inventory()
	elif Input.is_action_just_pressed("pause"):
		if inv_panel.visible:
			_toggle_inventory()
		else:
			_toggle_pause()

# ---------------- Jefe ----------------
func _on_boss_spawn(b: Node) -> void:
	boss_ui.visible = true
	boss_name.text = b.boss_name

func _on_boss_hp(current: int, maximum: int) -> void:
	boss_bar.max_value = maximum
	boss_bar.value = current

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

# ---------------- Inventario ----------------
func _toggle_inventory() -> void:
	if inv_panel.visible:
		inv_panel.visible = false
		get_tree().paused = false
	else:
		_populate_inventory()
		inv_panel.visible = true
		get_tree().paused = true

func _populate_inventory() -> void:
	var p = GameState.player
	var lines := ["[ EQUIPO ]", ""]
	for slot in Data.SLOTS:
		var it = p.equip.get(slot, null)
		if it == null:
			lines.append("%s: (vacío)" % slot.capitalize())
		else:
			lines.append("%s: %s [%s]" % [slot.capitalize(), it.name, Items.rarity_data(it.rarity).name])
			lines.append("    %s" % Items.describe(it))
	inv_equip.text = "\n".join(lines)
	for c in inv_bag.get_children():
		c.queue_free()
	if p.bag.is_empty():
		var empty := Label.new()
		empty.text = "(bolsa vacía)"
		inv_bag.add_child(empty)
		return
	for i in p.bag.size():
		var it: Dictionary = p.bag[i]
		var cur = p.equip.get(it.slot, null)
		var cmp := "▲"
		if cur != null:
			if Items.item_score(it) > Items.item_score(cur): cmp = "▲"
			elif Items.item_score(it) < Items.item_score(cur): cmp = "▼"
			else: cmp = "="
		var btn := Button.new()
		btn.text = "%s [%s] — %s  (%s)" % [it.name, Items.rarity_data(it.rarity).name, Items.describe(it), cmp]
		btn.pressed.connect(_equip_bag.bind(i))
		inv_bag.add_child(btn)

func _equip_bag(index: int) -> void:
	GameState.player.equip_from_bag(index)
	_populate_inventory()

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

# ---------------- Tienda / mercader ----------------
func open_shop(merchant) -> void:
	_shop_merchant = merchant
	if merchant.stock.is_empty():
		merchant.stock = Items.make_shop_stock(int(GameState.run.get("depth", 1)))
	_shop_just_opened = true
	get_tree().paused = true
	_build_shop()

func _build_shop() -> void:
	if _shop_panel and is_instance_valid(_shop_panel):
		_shop_panel.queue_free()
	var p = GameState.player
	var stock = _shop_merchant.stock
	var root := PanelContainer.new()
	root.anchor_left = 0.5; root.anchor_right = 0.5; root.anchor_top = 0.5; root.anchor_bottom = 0.5
	root.offset_left = -320; root.offset_right = 320; root.offset_top = -200; root.offset_bottom = 200
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	root.add_child(vb)
	var t := Label.new(); t.text = "MERCADER"; t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color("ffd84f")); t.add_theme_font_size_override("font_size", 22)
	vb.add_child(t)
	var coins := Label.new(); coins.text = "Tus monedas: ◉ %d" % int(p.coins)
	coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coins.add_theme_color_override("font_color", Color("ffd84f"))
	vb.add_child(coins)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	for i in stock.items.size():
		row.add_child(_shop_card(stock.items[i], i))
	var heal := Button.new(); heal.text = "⚗ Poción de vida   ◉ %d" % int(stock.heal_price)
	heal.pressed.connect(_buy_heal); vb.add_child(heal)
	if p.bag.size() > 0:
		var sl := Label.new(); sl.text = "VENDER (tu mochila):"
		sl.add_theme_color_override("font_color", Color("8a8496")); vb.add_child(sl)
		var srow := HBoxContainer.new(); srow.add_theme_constant_override("separation", 6)
		vb.add_child(srow)
		for j in p.bag.size():
			var it = p.bag[j]
			if it == null:
				continue
			var sb := Button.new()
			sb.text = "%s  ◉%d" % [String(it.get("name", "ítem")), Items.sell_price(it)]
			sb.pressed.connect(_sell_item.bind(j))
			srow.add_child(sb)
	var close := Button.new(); close.text = "Cerrar  [E]"; close.pressed.connect(_close_shop)
	vb.add_child(close)
	add_child(root)
	_shop_panel = root

func _shop_card(it: Dictionary, idx: int) -> Control:
	var card := VBoxContainer.new(); card.custom_minimum_size = Vector2(160, 0)
	var nm := Label.new(); nm.text = String(it.get("name", "ítem"))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.add_theme_color_override("font_color", Color(Items.rarity_data(it.get("rarity", "comun")).color))
	card.add_child(nm)
	var b := Button.new()
	if it.get("sold", false):
		b.text = "VENDIDO"; b.disabled = true
	else:
		b.text = "◉ %d" % int(it.get("price", 0))
		b.pressed.connect(_buy_item.bind(idx))
	card.add_child(b)
	return card

func _buy_item(idx: int) -> void:
	var stock = _shop_merchant.stock
	var it = stock.items[idx]
	var p = GameState.player
	if it.get("sold", false) or p.coins < int(it.price):
		return
	p.coins -= int(it.price)
	it["sold"] = true
	p.pick_up_item(it)
	Audio.play("coin")
	GameState.coins_changed.emit(p.coins)
	_build_shop()

func _buy_heal() -> void:
	var stock = _shop_merchant.stock
	var p = GameState.player
	if p.coins < int(stock.heal_price):
		return
	p.coins -= int(stock.heal_price)
	p.potions += 1
	Audio.play("heal")
	GameState.coins_changed.emit(p.coins)
	_build_shop()

func _sell_item(idx: int) -> void:
	var p = GameState.player
	if idx >= p.bag.size() or p.bag[idx] == null:
		return
	var it = p.bag[idx]
	p.bag.remove_at(idx)
	p.coins += Items.sell_price(it)
	Audio.play("coin")
	GameState.coins_changed.emit(p.coins)
	_build_shop()

func _close_shop() -> void:
	if _shop_panel and is_instance_valid(_shop_panel):
		_shop_panel.queue_free()
	_shop_panel = null
	get_tree().paused = false
