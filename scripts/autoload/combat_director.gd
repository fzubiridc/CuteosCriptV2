extends Node
## Director de combate: limita cuántos mobs golpean al jugador a la vez.

var _atk_active: Dictionary = {}   # instance_id → true
const MAX_ATTACKERS := 3

func try_claim(id: int) -> bool:
	if _atk_active.has(id):
		return true
	for k in _atk_active.keys():        # poda ids de mobs ya liberados (regen/muerte sin release)
		if not is_instance_id_valid(k):
			_atk_active.erase(k)
	if _atk_active.size() >= MAX_ATTACKERS:
		return false
	_atk_active[id] = true
	return true

func release(id: int) -> void:
	_atk_active.erase(id)
