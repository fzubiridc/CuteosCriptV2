extends Control
class_name NarrationPlayer

@export_file("*.json") var sequence_path := "res://assets/narration/intro/intro_sequence.json"
@export var auto_start := true

var _data := {}
var _cues: Array = []
var _current_cue := -1
var _elapsed := 0.0
var _cue_started_at := 0.0
var _crawl_pixels_per_second := 28.0
var _full_text := ""
var _allow_skip := true
var _auto_finish_when_voice_ends := true
var _voice_finished := false
var _has_voice := false
var _finish_delay := 0.0
var _finishing := false
var _paused_project_audio: Array[AudioStreamPlayer] = []
var _last_view_size := Vector2.ZERO
var _text_width := 0.0
var _text_height := 0.0
var _active_crawl_speed := 28.0
var _active_text_start_y_ratio := 1.05
var _active_font_size := 28
var _active_wrapped_text := ""

var _art: TextureRect
var _text_label: Label
var _voice_player: AudioStreamPlayer
var _music_player: AudioStreamPlayer
var _skip_button: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	_build_ui()
	if auto_start:
		start(sequence_path)


func start(path: String) -> void:
	sequence_path = path
	_data = _load_sequence(sequence_path)
	_cues = _data.get("cues", [])
	_crawl_pixels_per_second = float(_data.get("crawl_pixels_per_second", 28.0))
	_allow_skip = bool(_data.get("allow_skip", true))
	_auto_finish_when_voice_ends = bool(_data.get("auto_finish_when_voice_ends", true))
	_elapsed = 0.0
	_current_cue = -1
	_voice_finished = false
	_finish_delay = 0.0
	_finishing = false
	_pause_project_audio()
	_setup_audio()
	if not _cues.is_empty():
		_apply_cue(0)
	_fade_in()
	set_process(true)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_art = TextureRect.new()
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.22)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	_text_label = Label.new()
	_text_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.apply_narrative(_text_label, 28, Color("f6e8c8"))
	_text_label.label_settings.outline_size = 4
	_text_label.label_settings.outline_color = Color(0, 0, 0, 0.92)
	_text_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_text_label.add_theme_constant_override("shadow_offset_x", 2)
	_text_label.add_theme_constant_override("shadow_offset_y", 3)
	add_child(_text_label)

	_skip_button = Button.new()
	_skip_button.text = "SALTAR"
	_skip_button.anchor_left = 0.86
	_skip_button.anchor_right = 0.96
	_skip_button.anchor_top = 0.04
	_skip_button.anchor_bottom = 0.11
	_skip_button.focus_mode = Control.FOCUS_NONE
	_skip_button.pressed.connect(_on_skip_pressed)
	add_child(_skip_button)

	_voice_player = AudioStreamPlayer.new()
	_voice_player.bus = "Master"
	_voice_player.finished.connect(_on_voice_finished)
	add_child(_voice_player)

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)


func _load_sequence(path: String) -> Dictionary:
	var raw := FileAccess.get_file_as_string(path)
	if raw.is_empty():
		push_error("Narration sequence is empty or missing: %s" % path)
		return {}
	var parsed = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed
	push_error("Narration sequence is not valid JSON: %s" % path)
	return {}


func _setup_audio() -> void:
	_has_voice = false
	# Audio apagado hasta tener el mp3 real (audio_enabled=false en el JSON).
	if not bool(_data.get("audio_enabled", true)):
		return

	var voice := _load_audio_stream(str(_data.get("voice", "")))
	if voice != null:
		_voice_player.stream = voice
		_voice_player.volume_db = float(_data.get("voice_volume_db", 0.0))
		_voice_player.play()
		_has_voice = true

	var music := _load_audio_stream(str(_data.get("music", "")))
	if music != null:
		if music is AudioStreamMP3:
			music.loop = true
		elif music is AudioStreamOggVorbis:
			music.loop = true
		_music_player.stream = music
		_music_player.volume_db = float(_data.get("music_volume_db", -24.0))
		_music_player.play()


func _load_audio_stream(path: String) -> AudioStream:
	if path.is_empty():
		return null
	var stream := load(path) as AudioStream
	if stream != null:
		return stream
	var global_path := ProjectSettings.globalize_path(path)
	if path.ends_with(".mp3"):
		var file := FileAccess.open(global_path, FileAccess.READ)
		if file == null:
			return null
		var mp3 := AudioStreamMP3.new()
		mp3.data = file.get_buffer(file.get_length())
		return mp3
	if path.ends_with(".ogg"):
		return AudioStreamOggVorbis.load_from_file(global_path)
	if path.ends_with(".wav"):
		return AudioStreamWAV.load_from_file(global_path)
	return null


func _process(delta: float) -> void:
	if _finishing:
		return
	_elapsed += delta
	_apply_cue_for_time()
	_layout_text_if_needed()
	_update_text_motion()
	_check_finish(delta)


func _check_finish(delta: float) -> void:
	var dur := float(_data.get("duration", 0.0))
	if dur > 0.0 and _elapsed >= dur:
		_finish()
		return
	if _has_voice and _auto_finish_when_voice_ends:
		if _voice_finished:
			_finish_delay += delta
			if _finish_delay >= 2.0:
				_finish()
		return
	# Sin voz: terminar cuando el crawl del último cue ya pasó del todo (o por "duration").
	if _text_label != null and _text_height > 0.0 and _current_cue >= _cues.size() - 1:
		if _text_label.position.y + _text_height <= 0.0:
			_finish_delay += delta
			if _finish_delay >= 1.5:
				_finish()


func _apply_cue_for_time() -> void:
	if _cues.is_empty():
		return
	var next_index := _current_cue
	for i in _cues.size():
		var cue := _cues[i] as Dictionary
		if _elapsed >= float(cue.get("start", 0.0)):
			next_index = i
	if next_index != _current_cue:
		_apply_cue(next_index)


func _apply_cue(index: int) -> void:
	_current_cue = index
	_cue_started_at = _elapsed
	var cue := _cues[index] as Dictionary
	_art.texture = _load_texture(str(cue.get("image", "")))
	_art.scale = Vector2.ONE
	_art.position = Vector2.ZERO
	_full_text = _text_from_cue(cue)
	_active_crawl_speed = float(cue.get("crawl_pixels_per_second", _crawl_pixels_per_second))
	_active_text_start_y_ratio = float(cue.get("text_start_y_ratio", 1.05))
	_active_font_size = int(cue.get("font_size", 28))
	_text_label.label_settings.font_size = _active_font_size
	_last_view_size = Vector2.ZERO
	_layout_text_if_needed(true)
	_update_text_motion()


func _load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var texture := load(path) as Texture2D
	if texture != null:
		return texture
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


func _text_from_cue(cue: Dictionary) -> String:
	var text_data = cue.get("text", "")
	if text_data is Array:
		var parts := PackedStringArray()
		for part in text_data:
			parts.append(str(part))
		return "\n\n".join(parts)
	return str(text_data)


func _update_text_motion() -> void:
	if _text_label == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var start_y := _active_text_start_y_ratio * size.y
	_text_label.position.y = start_y - maxf(0.0, _elapsed - _cue_started_at) * _active_crawl_speed


func _layout_text_if_needed(force := false) -> void:
	if _text_label == null or size.x <= 0.0 or size.y <= 0.0:
		return
	if not force and _last_view_size == size:
		return
	_last_view_size = size
	var text_width: float = minf(size.x * 0.78, 1080.0)
	_text_width = text_width
	_active_wrapped_text = _wrap_text(_full_text, text_width, _active_font_size)
	_text_label.text = _active_wrapped_text
	_text_label.custom_minimum_size = Vector2(text_width, 0)
	_text_label.size.x = text_width
	var line_count: int = maxi(1, _active_wrapped_text.count("\n") + 1)
	var line_height: float = float(_active_font_size) + float(_data.get("crawl_line_spacing", 10.0))
	_text_height = maxf(size.y * 0.35, float(line_count) * line_height)
	_text_label.size.y = _text_height
	_text_label.position.x = (size.x - text_width) * 0.5


func _wrap_text(text: String, width: float, font_size: int) -> String:
	var average_char_width: float = float(font_size) * float(_data.get("crawl_average_char_width_ratio", 0.43))
	var max_chars: int = maxi(24, int(width / maxf(1.0, average_char_width)))
	var paragraphs: PackedStringArray = text.split("\n\n", false)
	var wrapped_paragraphs := PackedStringArray()
	for paragraph in paragraphs:
		wrapped_paragraphs.append(_wrap_paragraph(paragraph.strip_edges(), max_chars))
	return "\n\n".join(wrapped_paragraphs)


func _wrap_paragraph(paragraph: String, max_chars: int) -> String:
	if paragraph.is_empty():
		return ""
	var words: PackedStringArray = paragraph.split(" ", false)
	var lines := PackedStringArray()
	var line := ""
	for word in words:
		var candidate := word if line.is_empty() else line + " " + word
		if candidate.length() <= max_chars:
			line = candidate
		else:
			if not line.is_empty():
				lines.append(line)
			line = word
	if not line.is_empty():
		lines.append(line)
	return "\n".join(lines)


func _on_skip_pressed() -> void:
	if not _allow_skip or _finishing:
		return
	_finish()


func _unhandled_input(event: InputEvent) -> void:
	if not _allow_skip or _finishing:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("pause"):
		_on_skip_pressed()
		get_viewport().set_input_as_handled()


func _on_voice_finished() -> void:
	_voice_finished = true


func _fade_in() -> void:
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, float(_data.get("fade_in_seconds", 1.2)))


func _finish() -> void:
	if _finishing:
		return
	_finishing = true
	var fade := float(_data.get("fade_out_seconds", 1.0))
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, fade)
	if _music_player.playing:
		tween.parallel().tween_property(_music_player, "volume_db", -60.0, fade)
	if _voice_player.playing:
		tween.parallel().tween_property(_voice_player, "volume_db", -60.0, fade)
	await tween.finished
	_restore_project_audio()
	var next_scene := str(_data.get("next_scene", ""))
	if not next_scene.is_empty():
		get_tree().change_scene_to_file(next_scene)


func _pause_project_audio() -> void:
	_paused_project_audio.clear()
	var audio := get_node_or_null("/root/Audio")
	if audio == null:
		return
	for child in audio.get_children():
		if child is AudioStreamPlayer and child.playing and not child.stream_paused:
			child.stream_paused = true
			_paused_project_audio.append(child)


func _restore_project_audio() -> void:
	for player in _paused_project_audio:
		if is_instance_valid(player):
			player.stream_paused = false
	_paused_project_audio.clear()


func _exit_tree() -> void:
	_restore_project_audio()
