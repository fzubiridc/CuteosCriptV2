extends Node
## Audio global: música ambiente + SFX por nombre con pool de players.
## cast/boom venían en m4a (no soportado por Godot) → convertidos a wav.

const SFX := {
	"attack": "res://assets/sfx/swing.wav",
	"cast": "res://assets/sfx/cast.wav",    # salida del proyectil del mago
	"boom": "res://assets/sfx/boom.wav",    # impacto del proyectil
	"dash": "res://assets/sfx/dash.mp3",
	"hurt": "res://assets/sfx/hurt.mp3",
	"coin": "res://assets/sfx/coin.wav",
	"heal": "res://assets/sfx/heal.wav",
	"equip": "res://assets/sfx/equip.wav",
	"enemy_death": "res://assets/sfx/rat_death.mp3",
	"chest": "res://assets/sfx/chest.wav",
}

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _footsteps: AudioStreamPlayer   # loop dedicado mientras el jugador camina

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for key in SFX:
		var s = _load_stream(SFX[key])
		if s != null:
			_streams[key] = s
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -14.0
	add_child(_music)
	var m = load("res://assets/music.mp3")
	if m != null:
		if m is AudioStreamMP3:
			m.loop = true
		_music.stream = m
		_music.play()
	# Pasos: sample en loop (igual que el pixi: vol 0.6, playbackRate 1.95).
	_footsteps = AudioStreamPlayer.new()
	_footsteps.volume_db = -8.0
	_footsteps.pitch_scale = 1.95
	add_child(_footsteps)
	var fs = _load_stream("res://assets/sfx/footsteps.mp3")
	if fs != null:
		if fs is AudioStreamMP3:
			fs.loop = true
		_footsteps.stream = fs

## Carga un AudioStream: usa el import si existe; si el archivo aún no fue importado
## por el editor (copiado en caliente), lo lee crudo del disco como fallback.
func _load_stream(path: String) -> AudioStream:
	var s := load(path) as AudioStream
	if s != null:
		return s
	var g := ProjectSettings.globalize_path(path)
	if path.ends_with(".wav"):
		return AudioStreamWAV.load_from_file(g)
	if path.ends_with(".mp3"):
		var f := FileAccess.open(g, FileAccess.READ)
		if f == null:
			return null
		var mp3 := AudioStreamMP3.new()
		mp3.data = f.get_buffer(f.get_length())
		return mp3
	return null

## Pasos en loop: on=true arranca si no suena, on=false lo pausa.
func footsteps(on: bool) -> void:
	if _footsteps == null or _footsteps.stream == null:
		return
	if on and not _footsteps.playing:
		_footsteps.play()
	elif not on and _footsteps.playing:
		_footsteps.stop()

func play(key: String, vol_db := -6.0) -> void:
	var s = _streams.get(key)
	if s == null:
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = s
	p.volume_db = vol_db
	p.play()
