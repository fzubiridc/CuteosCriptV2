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
	"door": "res://assets/sfx/door_open.mp3",   # atravesar puerta/portal
	"growl": "res://assets/sfx/growl_big.mp3",  # gruñido de mob grande (gólem) al detectarte
	"aoe_impact": "res://assets/sfx/aoe_impact.mp3",  # impacto del spell AoE (reemplaza al viejo 'boom')
}

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _footsteps: AudioStreamPlayer   # loop dedicado mientras el jugador camina
var _reverb_base := {}              # snapshot del reverb del bus World (= perfil "dungeon" tuneado en el panel)
var _amb1: AudioStreamPlayer        # capa de ambiente (drone de dungeon, loop)
var _amb2: AudioStreamPlayer        # capa de ambiente (aire/atmósfera, loop)
var _amb3: AudioStreamPlayer        # capa de ambiente (rumble de tierra sutil, loop)
# Stingers de ambiente: sonidos lejanos (rugidos, ratas) que suenan CADA TANTO (random).
const AMBIENT_STINGERS := [
	"res://assets/sfx/roar_distant_1.mp3",
	"res://assets/sfx/roar_distant_2.mp3",
	"res://assets/sfx/rats_distant.mp3",
	"res://assets/sfx/rumble_distant.mp3",   # rumble de motor/tierra lejano
]
var _stinger_streams: Array[AudioStream] = []
var _stinger_player: AudioStreamPlayer
var _stinger_t := 0.0
var _stinger_next := 18.0
# Stinger RARO (puerta cerrándose, lejana) cada ~4-5 min.
var _rare_stream: AudioStream
var _rare_t := 0.0
var _rare_next := 200.0
var _loop_streams := {}            # cache de streams de loop posicional por path (antorchas, fogatas…)
var _torch_t := 0.0                # acumulador para el manejo de cercanía de antorchas
const FLAME_AUDIO_DIST := 480.0    # más allá de esto, el emisor de fuego se silencia (no decodifica)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for key in SFX:
		var s = _load_stream(SFX[key])
		if s != null:
			_streams[key] = s
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "World"   # SFX del mundo → bus con reverb (default_bus_layout.tres)
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -14.0
	_music.bus = "Music"   # música SIN el reverb de ambiente
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
	_footsteps.bus = "World"   # pasos con el eco de la mazmorra
	add_child(_footsteps)
	var fs = _load_stream("res://assets/sfx/footsteps.mp3")
	if fs != null:
		if fs is AudioStreamMP3:
			fs.loop = true
		_footsteps.stream = fs
	_snapshot_world_reverb()   # guardar el reverb tuneado en el panel como perfil "dungeon"
	# Ambiente de dungeon: dos capas en loop (drone + aire) a bajo volumen. Bus Music (sin el
	# reverb del World: ya traen su propia atmósfera). El día del exterior, se cambian acá / en apply_ambient.
	_amb1 = _make_ambient("res://assets/sfx/ambient_dungeon.ogg", -16.0)
	_amb2 = _make_ambient("res://assets/sfx/ambient_dungeon_air.mp3", -20.0)
	_amb3 = _make_ambient("res://assets/sfx/ambient_earth_rumble.mp3", -22.0)   # rumble de tierra sutil pero audible
	# Stingers lejanos (rugidos/ratas) cada tanto: player dedicado, bus World (el reverb los
	# hace sonar a la distancia). Solo en gameplay (hay player), a bajo volumen.
	for spath in AMBIENT_STINGERS:
		var ss := _load_stream(spath)
		if ss != null:
			_stinger_streams.append(ss)
	_stinger_player = AudioStreamPlayer.new()
	_stinger_player.bus = "World"
	add_child(_stinger_player)
	_rare_stream = _load_stream("res://assets/sfx/door_slam_distant.mp3")   # puerta lejana cada 4-5 min

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
	if path.ends_with(".ogg"):
		return AudioStreamOggVorbis.load_from_file(g)
	return null

## Pasos en loop: on=true arranca si no suena, on=false lo pausa.
func footsteps(on: bool) -> void:
	if _footsteps == null or _footsteps.stream == null:
		return
	if on and not _footsteps.playing:
		_footsteps.play()
	elif not on and _footsteps.playing:
		_footsteps.stop()

## Crea un player de ambiente en LOOP (bus Music, sin reverb — ya trae su atmósfera).
func _make_ambient(path: String, vol_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.volume_db = vol_db
	add_child(p)
	var s := _load_stream(path)
	if s != null:
		if s is AudioStreamMP3:
			s.loop = true
		elif s is AudioStreamOggVorbis:
			s.loop = true
		p.stream = s
		p.play()
	return p

func _process(delta: float) -> void:
	# is_instance_valid ANTES del cast: al volver al menú (ESC) GameState.player apunta a un
	# nodo ya liberado; `as Node2D` sobre un objeto freed crashea ("cast freed object").
	if not is_instance_valid(GameState.player):
		return
	var pl := GameState.player as Node2D
	if pl == null:   # solo en gameplay (no en el menú)
		return
	# Stingers lejanos (rugidos/ratas) cada tanto.
	if not _stinger_streams.is_empty():
		_stinger_t += delta
		if _stinger_t >= _stinger_next:
			_stinger_t = 0.0
			_stinger_next = randf_range(20.0, 48.0)
			_stinger_player.stream = _stinger_streams[randi() % _stinger_streams.size()]
			_stinger_player.volume_db = -16.0   # lejano
			_stinger_player.play()
	# Stinger RARO (puerta cerrándose, lejana) cada 4-5 min.
	if _rare_stream != null:
		_rare_t += delta
		if _rare_t >= _rare_next:
			_rare_t = 0.0
			_rare_next = randf_range(240.0, 300.0)
			_stinger_player.stream = _rare_stream
			_stinger_player.volume_db = -20.0   # más tenue/lejano
			_stinger_player.play()
	# Fuego posicional (antorchas, fogatas…): solo los CERCANOS suenan/decodifican; los lejanos se
	# pausan — chequeo cada ~0.4s sobre el grupo "flame_audio".
	_torch_t += delta
	if _torch_t >= 0.4:
		_torch_t = 0.0
		for t in get_tree().get_nodes_in_group("flame_audio"):
			var fp = (t as Node).get_meta("flame_player", null)
			if fp is AudioStreamPlayer2D:
				fp.stream_paused = (t as Node2D).global_position.distance_to(pl.global_position) > FLAME_AUDIO_DIST

func play(key: String, vol_db := -6.0) -> void:
	var s = _streams.get(key)
	if s == null:
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = s
	p.volume_db = vol_db
	p.play()

## Reproduce un SFX POSICIONAL (2D): suena MÁS FUERTE cuanto más cerca está `node` del
## jugador (atenúa por distancia + paneo estéreo). Para growls, antorchas, etc. One-shot.
func play_at(key: String, node: Node2D, vol_db := 0.0, max_dist := 600.0) -> void:
	var s = _streams.get(key)
	if s == null or node == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = s
	p.volume_db = vol_db
	p.bus = "World"
	p.max_distance = max_dist
	p.attenuation = 1.5
	node.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)   # se libera al terminar

## Loop de fuego POSICIONAL con autostop: suena más fuerte al acercarse y se pausa si está lejos
## (no decodifica → barato con muchos emisores). Para antorchas, fogatas, etc. El nodo queda en el
## grupo "flame_audio" y _process gestiona su cercanía.
func loop_at(node: Node2D, stream_path: String, vol_db := -10.0, max_dist := 420.0) -> void:
	if node == null:
		return
	var s: AudioStream = _loop_streams.get(stream_path)
	if s == null:
		s = _load_stream(stream_path)
		if s is AudioStreamMP3:
			s.loop = true
		elif s is AudioStreamOggVorbis:
			s.loop = true
		if s == null:
			return
		_loop_streams[stream_path] = s
	var p := AudioStreamPlayer2D.new()
	p.stream = s
	p.volume_db = vol_db
	p.bus = "World"
	p.max_distance = max_dist
	p.attenuation = 1.6
	p.stream_paused = true   # lo despierta _process si el jugador se acerca
	node.add_child(p)
	p.play()
	node.set_meta("flame_player", p)
	node.add_to_group("flame_audio")

## Antorcha: loop de llama posicional (wrapper de loop_at con el sfx de antorcha).
func attach_flame(torch: Node2D, vol_db := -10.0, max_dist := 420.0) -> void:
	loop_at(torch, "res://assets/sfx/torch_flame.mp3", vol_db, max_dist)

# --- Ambiente (reverb del bus World) ---------------------------------------------
## El reverb del DUNGEON se tunea en el panel Audio del editor (bus World → Reverb).
## En _ready guardamos ese valor como perfil "dungeon"; apply_ambient lo modula para
## otros mapas. El día del mapa exterior: Audio.apply_ambient("exterior") al cargar el piso.
func _snapshot_world_reverb() -> void:
	var bus := AudioServer.get_bus_index("World")
	if bus < 0 or AudioServer.get_bus_effect_count(bus) == 0:
		return
	var rev := AudioServer.get_bus_effect(bus, 0) as AudioEffectReverb
	if rev:
		_reverb_base = {"room": rev.room_size, "damp": rev.damping, "wet": rev.wet, "spread": rev.spread}

## Aplica un perfil de ambiente al bus World. "dungeon"/default restaura lo tuneado en
## el panel; "exterior" lo deja casi seco (espacio abierto). Sumá perfiles según necesites.
func apply_ambient(profile: String) -> void:
	var bus := AudioServer.get_bus_index("World")
	if bus < 0 or AudioServer.get_bus_effect_count(bus) == 0:
		return
	var rev := AudioServer.get_bus_effect(bus, 0) as AudioEffectReverb
	if rev == null:
		return
	match profile:
		"exterior":
			rev.wet = 0.04          # casi seco — espacio abierto
			rev.room_size = 0.5
			rev.damping = 0.2
		_:  # "dungeon" / default → restaura lo tuneado en el panel
			rev.room_size = _reverb_base.get("room", 0.75)
			rev.damping = _reverb_base.get("damp", 0.4)
			rev.wet = _reverb_base.get("wet", 0.18)
			rev.spread = _reverb_base.get("spread", 0.6)
