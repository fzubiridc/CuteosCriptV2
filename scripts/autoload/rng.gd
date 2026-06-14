extends Node
## Generador de azar global y seedable. Centraliza el RNG para poder
## reproducir runs con una misma semilla (útil para roguelikes / debug).

var _rng := RandomNumberGenerator.new()
var seed_value: int = 0

func _ready() -> void:
	randomize_seed()

func randomize_seed() -> void:
	_rng.randomize()
	seed_value = _rng.seed

func set_seed(s: int) -> void:
	seed_value = s
	_rng.seed = s

## Entero en [a, b] inclusive.
func range_i(a: int, b: int) -> int:
	return _rng.randi_range(a, b)

## Flotante en [a, b].
func range_f(a: float, b: float) -> float:
	return _rng.randf_range(a, b)

## Flotante en [0, 1).
func unit() -> float:
	return _rng.randf()

## True con probabilidad p (0..1).
func chance(p: float) -> bool:
	return _rng.randf() < p

## Elemento al azar de un array no vacío.
func pick(arr: Array) -> Variant:
	return arr[_rng.randi_range(0, arr.size() - 1)]
