extends CanvasLayer
## Barra de jefe. Se muestra al aparecer un jefe y se actualiza con su vida.

@onready var ui: Control = $BossUI
@onready var bar: ProgressBar = $BossUI/BossBar
@onready var name_label: Label = $BossUI/BossName

func _ready() -> void:
	ui.visible = false
	GameState.boss_spawned.connect(_on_spawn)
	GameState.boss_hp_changed.connect(_on_hp)
	GameState.boss_died.connect(_on_died)

func _on_spawn(b: Node) -> void:
	ui.visible = true
	name_label.text = b.boss_name

func _on_hp(current: int, maximum: int) -> void:
	bar.max_value = maximum
	bar.value = current

func _on_died() -> void:
	ui.visible = false
