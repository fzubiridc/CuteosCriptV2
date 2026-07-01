extends CanvasLayer
## Contador de rendimiento de debug (esquina sup-izq). Toggle con F3.
## FPS + tiempos de frame (CPU/física/resto) + draw calls + VRAM. Godot no expone un "GPU %" directo;
## el "resto" (frame − CPU − física ≈ submit de render + espera de vsync) y VRAM/draws indican carga GPU.

var _label: Label
var _acc := 0.0

func _ready() -> void:
	layer = 128                      # siempre arriba de todo
	_label = Label.new()
	_label.position = Vector2(8, 5)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.65, 1.0, 0.65))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 5)
	add_child(_label)
	visible = OS.is_debug_build()     # en debug arranca VISIBLE (dev); en release oculto. F3 togglea.

func _process(dt: float) -> void:
	if not visible:
		return
	_acc += dt
	if _acc < 0.25:                  # refresca 4x/s (no titila)
		return
	_acc = 0.0
	var fps := Engine.get_frames_per_second()
	var frame_ms := 1000.0 / maxf(fps, 1.0)
	var cpu := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var rest := maxf(frame_ms - cpu - phys, 0.0)   # ≈ render submit + espera de vsync (proxy de GPU)
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var vram := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	_label.text = "FPS %d  (%.1f ms)\nCPU %.1f  ·  Fís %.1f  ·  GPU/vsync~ %.1f ms\nDraws %d  ·  VRAM %d MB" % [
		fps, frame_ms, cpu, phys, rest, draws, int(vram)]

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode == KEY_F3:
		visible = not visible
