extends Node
## Audio global: música ambiente + SFX por nombre con pool de players.
## Los m4a (cast/boom) no los soporta Godot; se omiten (attack usa swing).

const SFX := {
	"attack": "res://assets/sfx/swing.wav",
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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for name in SFX:
		var s = load(SFX[name])
		if s != null:
			_streams[name] = s
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

func play(name: String, vol_db := -6.0) -> void:
	var s = _streams.get(name)
	if s == null:
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = s
	p.volume_db = vol_db
	p.play()
