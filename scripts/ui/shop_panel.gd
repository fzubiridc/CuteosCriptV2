extends Control
class_name ShopPanel
## Tienda / mercader. Extraído de hud.gd (refactor de mantenibilidad, comportamiento 1:1).
## El HUD instancia este panel como hijo y delega: hud.open_shop(m) -> shop_panel.open(m).
## La construcción es 100% por código (no hay escena). El screen se agrega como hijo de
## este panel (que es full-rect) → renderiza igual que cuando colgaba del CanvasLayer del HUD.

var _shop_panel: Control
var _shop_merchant = null
var _shop_just_opened := false

func _ready() -> void:
	# El árbol se pausa mientras la tienda está abierta, así que necesitamos correr
	# igual para poder cerrarla con E (igual que el HUD original, que era PROCESS_MODE_ALWAYS).
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # sin tienda no bloquea clicks; el dim del screen sí

func _process(_delta: float) -> void:
	# Cerrar tienda con E (con guarda de 1 frame para no cerrarla al abrirla).
	if _shop_panel and is_instance_valid(_shop_panel):
		if _shop_just_opened:
			_shop_just_opened = false
		elif Input.is_action_just_pressed("interact"):
			_close_shop()

# ---------------- Tienda / mercader ----------------
func open(merchant) -> void:
	# Guarda: no abrir la tienda con un mercader inválido (evita crash al leer .stock).
	if not is_instance_valid(merchant):
		return
	_shop_merchant = merchant
	if merchant.stock.is_empty():
		merchant.stock = Items.make_shop_stock(int(GameState.run.get("depth", 1)))
	_shop_just_opened = true
	get_tree().paused = true
	_build_shop()

func _build_shop() -> void:
	# Guarda: si el mercader murió con la tienda abierta, cerramos en vez de crashear.
	if not is_instance_valid(_shop_merchant):
		_close_shop()
		return
	if _shop_panel and is_instance_valid(_shop_panel):
		_shop_panel.queue_free()
	var p = GameState.player
	var stock = _shop_merchant.stock
	# Pantalla completa: dim de fondo (oscurece el juego + bloquea clicks) + panel.
	var screen := Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.theme = UiTheme.get_theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.add_child(dim)
	var root := PanelContainer.new()
	root.anchor_left = 0.5; root.anchor_right = 0.5; root.anchor_top = 0.5; root.anchor_bottom = 0.5
	root.offset_left = -320; root.offset_right = 320; root.offset_top = -210; root.offset_bottom = 210
	screen.add_child(root)
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
	add_child(screen)
	_shop_panel = screen

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
	# Guarda: el mercader pudo morir mientras la tienda seguía abierta.
	if not is_instance_valid(_shop_merchant):
		_close_shop()
		return
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
	# Guarda: el mercader pudo morir mientras la tienda seguía abierta.
	if not is_instance_valid(_shop_merchant):
		_close_shop()
		return
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
