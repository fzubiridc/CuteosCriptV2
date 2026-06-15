extends Area2D
class_name Pickup
## Objeto recogible: moneda, XP, corazón, poción o ítem. Se recoge por contacto.

var kind := "coin"
var value := 1
var item_data: Dictionary = {}

@onready var visual: Polygon2D = $Visual

func setup(pos: Vector2, k: String, v: int, idata: Dictionary = {}) -> void:
	global_position = pos
	kind = k
	value = v
	item_data = idata
	_color()
	reset_physics_interpolation()

func _ready() -> void:
	body_entered.connect(_on_body)

func _color() -> void:
	if visual == null:
		return
	match kind:
		"coin": visual.color = Color(1.0, 0.85, 0.2)
		"xp": visual.color = Color(0.4, 0.9, 0.5)
		"heart": visual.color = Color(1.0, 0.3, 0.4)
		"potion": visual.color = Color(0.4, 0.6, 1.0)
		"item": visual.color = Color(Items.rarity_data(item_data.get("rarity", "comun")).color)

func _on_body(body: Node) -> void:
	if not (body is Player):
		return
	match kind:
		"coin": body.add_coins(value)
		"xp": body.gain_xp(value)
		"heart": body.heal(value)
		"potion": body.potions += 1
		"item": body.pick_up_item(item_data)
	var snd: String = {"coin": "coin", "heart": "heal", "potion": "heal", "item": "equip"}.get(kind, "")
	if snd != "":
		Audio.play(snd)
	queue_free()
