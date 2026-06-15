extends Node
## Generación de ítems (portado de items.js). Un ítem es un Dictionary:
## {slot, rarity, material, mat_name, name, base_name, def, dmg?, weapon_type?, mods{}}

func make_item(depth: int, slot := "") -> Dictionary:
	if slot == "":
		slot = Rng.pick(["arma", "arma", "casco", "coraza", "botas", "anillo", "amuleto"])
	var rarity := _roll_rarity(depth)
	var mat := _roll_material(depth)
	var item := {"slot": slot, "rarity": rarity.id, "material": mat.id, "mat_name": mat.name, "mods": {}, "def": 0, "name": "", "base_name": ""}
	var suffix := ""
	if slot == "arma":
		var wkey: String = Rng.pick(Data.WEAPON_TYPES.keys())
		var wt: Dictionary = Data.WEAPON_TYPES[wkey]
		item["weapon_type"] = wkey
		item["dmg"] = int(round(wt.dmg * mat.mult * rarity.mult))
		item["base_name"] = wt.name
	else:
		var base: Dictionary = Rng.pick(Data.ARMOR_BASES[slot])
		item["base_name"] = base.name
		item["def"] = int(round(float(base.get("def", 0)) * mat.mult * rarity.mult))
		if base.has("spd"): item.mods["spd"] = base.spd
		if base.has("dmg"): item.mods["dmg"] = maxi(1, int(round(float(base.dmg) * mat.mult * rarity.mult)))
		if base.has("hp"): item.mods["hp"] = int(round(float(base.hp) * mat.mult * rarity.mult))
	# Mods aleatorios según rareza.
	var pool := (Data.MODS as Array).duplicate()
	pool.shuffle()
	var nmods: int = rarity.mods
	for i in range(mini(nmods, pool.size())):
		var m: Dictionary = pool[i]
		var val := maxi(1, int(round(m.base * rarity.mult * _depth_mult(depth) * (0.7 + Rng.unit() * 0.6))))
		item.mods[m.key] = int(item.mods.get(m.key, 0)) + val
		if suffix == "":
			suffix = m.suffix
	# Nombre: armas de mago -> nombre de fantasía por tier; resto, base.
	var tier := _material_tier(mat.id)
	var base_name: String = _staff_name(tier) if item.has("weapon_type") else String(item.base_name)
	item["name"] = base_name
	if suffix != "" and base_name.find(",") < 0:
		item["name"] = base_name + " " + suffix
	return item

func make_item_min_rare(depth: int) -> Dictionary:
	var it := {}
	for i in 8:
		it = make_item(depth)
		if it.rarity == "raro" or it.rarity == "epico":
			return it
	return it

func item_score(it: Dictionary) -> float:
	var s := float(it.get("dmg", 0)) * 2 + float(it.get("def", 0)) * 2
	var m: Dictionary = it.get("mods", {})
	s += float(m.get("dmg", 0)) * 2 + float(m.get("def", 0)) * 2 + float(m.get("hp", 0)) * 0.4
	s += float(m.get("spd", 0)) * 0.8 + float(m.get("crit", 0)) + float(m.get("atkspd", 0)) * 0.6
	return s

func rarity_data(id: String) -> Dictionary:
	for r in Data.RARITIES:
		if r.id == id:
			return r
	return Data.RARITIES[0]

## Stock del mercader (referencia Pixi): 3 ítems (depth+1) + poción de vida.
func make_shop_stock(depth: int) -> Dictionary:
	var its: Array = []
	for i in 3:
		var it := make_item(depth + 1)
		it["price"] = int(round(12.0 + item_score(it) * 0.9))
		it["sold"] = false
		its.append(it)
	return {"items": its, "heal_price": 30}

func sell_price(it: Dictionary) -> int:
	return maxi(1, int(round(item_score(it) * 0.45)))

## Texto legible de los stats de un ítem (para la UI).
func describe(it: Dictionary) -> String:
	var parts := []
	if int(it.get("dmg", 0)) != 0:
		parts.append("daño %d" % int(it.dmg))
	if int(it.get("def", 0)) != 0:
		parts.append("def %d" % int(it.def))
	var m: Dictionary = it.get("mods", {})
	for k in m:
		parts.append("%s +%d" % [_mod_label(k), int(m[k])])
	return ", ".join(parts) if not parts.is_empty() else "—"

func _mod_label(k: String) -> String:
	for m in Data.MODS:
		if m.key == k:
			return m.label
	return k

func _roll_rarity(depth: int) -> Dictionary:
	var boost := depth * 2.2
	var ws := []
	for i in Data.RARITIES.size():
		var r: Dictionary = Data.RARITIES[i]
		ws.append(maxf(1.0, r.w + (boost * i if i > 0 else -boost)))
	var total := 0.0
	for w in ws:
		total += w
	var roll := Rng.unit() * total
	for i in Data.RARITIES.size():
		roll -= ws[i]
		if roll <= 0:
			return Data.RARITIES[i]
	return Data.RARITIES[0]

func _roll_material(depth: int) -> Dictionary:
	var center := minf(Data.MATERIALS.size() - 1, (depth - 1) / 1.6)
	var idx := clampi(int(round(center + (Rng.unit() * 2 - 1))), 0, Data.MATERIALS.size() - 1)
	return Data.MATERIALS[idx]

func _depth_mult(depth: int) -> float:
	return 1.0 + (depth - 1) * float(Data.BALANCE.depth_mod_scale)

func _material_tier(mat_id: String) -> int:
	for i in Data.MATERIALS.size():
		if Data.MATERIALS[i].id == mat_id:
			return i
	return 0

func _staff_name(tier: int) -> String:
	var t := clampi(tier, 0, Data.STAFF_NAMES.size() - 1)
	return Rng.pick(Data.STAFF_NAMES[t])
