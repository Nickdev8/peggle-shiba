extends Node

const SFX := {
	"last_shot": preload("res://audio/last_shot.wav"),
	"shoot_face": preload("res://audio/shoot/sfx_sounds_high2.wav"),

	"score_displayscreen": preload("res://audio/coints/machinegun_loop.wav"),
	"coint_cluster": [
		preload("res://audio/coints/sfx_coin_cluster1.wav"),
		preload("res://audio/coints/sfx_coin_cluster5.wav"),
		preload("res://audio/coints/sfx_coin_cluster6.wav"),
		preload("res://audio/coints/sfx_coin_cluster7.wav"),
		preload("res://audio/coints/sfx_coin_cluster8.wav"),
		preload("res://audio/coints/sfx_coin_cluster9.wav")
	],

	"hit_face": [
		preload("res://audio/hittingpin/sfx_sounds_impact1.wav"),
		preload("res://audio/hittingpin/sfx_sounds_impact3.wav"),
		preload("res://audio/hittingpin/sfx_sounds_impact4.wav"),
		preload("res://audio/hittingpin/sfx_sounds_impact5.wav"),
		preload("res://audio/hittingpin/sfx_sounds_impact6.wav"),
		preload("res://audio/hittingpin/sfx_sounds_impact7.wav"),
		preload("res://audio/hittingpin/sfx_sounds_impact8.wav")
	],

	"ui_move": preload("res://audio/menu_move.wav"),
	"ui_start": preload("res://audio/menu_move.wav"),
	"ui_load_newscene": preload("res://audio/menu_move.wav"),
}

const MUSIC := {
	"title": preload("res://audio/menu.mp3"),
}

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _active_music: AudioStreamPlayer
var _inactive_music: AudioStreamPlayer

func _ready() -> void:
	randomize() # for varied picks/pitch
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	for p in [_music_a, _music_b]:
		p.bus = "Music"
		p.autoplay = false
		add_child(p)
	_active_music = _music_a
	_inactive_music = _music_b
	_load_volumes()
	
	
	play_music("title")

# --- Helpers ---------------------------------------------------------------
func _pick_stream(dict: Dictionary, key: String) -> AudioStream:
	if not dict.has(key):
		return null
	var v: Variant = dict.get(key)
	if v is Array:
		var arr: Array = v
		if arr.is_empty():
			return null
		var pick: Variant = arr[randi() % arr.size()]
		return pick as AudioStream
	elif v is AudioStream:
		return v as AudioStream

	return null

# ---------- SFX ----------
func play_sfx(name: String, pitch_jitter: float = 0.0, at_global_pos: Vector3 = Vector3.INF) -> void:
	var stream: AudioStream = _pick_stream(SFX, name)
	if stream == null:
		push_warning("SFX '%s' not found or invalid." % name)
		return

	var player: Node
	if at_global_pos != Vector3.INF:
		var p3d := AudioStreamPlayer3D.new()
		p3d.stream = stream
		p3d.bus = "SFX"
		p3d.unit_size = 1.0
		p3d.attenuation_filter_cutoff_hz = 5000.0
		p3d.global_transform.origin = at_global_pos
		player = p3d
	else:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.bus = "SFX"
		player = p

	if pitch_jitter != 0.0 and player is AudioStreamPlayer:
		(player as AudioStreamPlayer).pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	if pitch_jitter != 0.0 and player is AudioStreamPlayer3D:
		(player as AudioStreamPlayer3D).pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)

	add_child(player)
	if player is AudioStreamPlayer:
		(player as AudioStreamPlayer).finished.connect(Callable(player, "queue_free"))
	elif player is AudioStreamPlayer3D:
		(player as AudioStreamPlayer3D).finished.connect(Callable(player, "queue_free"))
	# (Both players have a 'finished' signal in Godot 4)
	(player as Object).call("play")

func play_ui(name: String) -> void:
	var stream: AudioStream = _pick_stream(SFX, name)
	if stream == null:
		push_warning("UI SFX '%s' not found or invalid." % name)
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "UI"
	add_child(p)
	p.finished.connect(Callable(p, "queue_free"))
	p.play()

# ---------- Music ----------
func play_music(name: String, crossfade_sec: float = 1.5, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _pick_stream(MUSIC, name)
	if stream == null:
		push_warning("Music '%s' not found or invalid." % name)
		return

	if _inactive_music == null or _active_music == null:
		push_warning("AudioManager not ready yet, delaying music play.")
		return

	_inactive_music.stop()
	_inactive_music.stream = stream
	_inactive_music.volume_db = -80.0
	_inactive_music.play()

	if crossfade_sec <= 0.0 or not _active_music.playing:
		_active_music.stop()
		_swap_players()
		_active_music.volume_db = volume_db
		return

	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(_active_music, "volume_db", -80.0, crossfade_sec)
	tw.parallel().tween_property(_inactive_music, "volume_db", volume_db, crossfade_sec)
	tw.tween_callback(Callable(self, "_on_crossfade_done"))

func _on_crossfade_done() -> void:
	_active_music.stop()
	_swap_players()

func _swap_players() -> void:
	var tmp: AudioStreamPlayer = _active_music
	_active_music = _inactive_music
	_inactive_music = tmp

func stop_music(fade_sec: float = 0.8) -> void:
	if not _active_music.playing:
		return
	if fade_sec <= 0.0:
		_active_music.stop()
		return
	var tw := create_tween()
	tw.tween_property(_active_music, "volume_db", -80.0, fade_sec)
	tw.tween_callback(Callable(_active_music, "stop"))

# ---------- Volume / Mute ----------
func set_bus_volume(bus: String, db: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, db)
		_save_volumes()

func set_bus_mute(bus: String, mute: bool) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, mute)
		_save_volumes()

# ---------- Persistence ----------
func _save_volumes() -> void:
	var cfg := ConfigFile.new()
	var idx_music := AudioServer.get_bus_index("Music")
	var idx_sfx := AudioServer.get_bus_index("SFX")
	var idx_ui := AudioServer.get_bus_index("UI")
	cfg.set_value("audio", "music_db", AudioServer.get_bus_volume_db(idx_music))
	cfg.set_value("audio", "sfx_db", AudioServer.get_bus_volume_db(idx_sfx))
	cfg.set_value("audio", "ui_db", AudioServer.get_bus_volume_db(idx_ui))
	cfg.save("user://audio.cfg")

func _load_volumes() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://audio.cfg") != OK:
		return
	for pair in [
		["Music", "music_db"],
		["SFX", "sfx_db"],
		["UI", "ui_db"],
	]:
		var idx := AudioServer.get_bus_index(pair[0])
		if idx >= 0 and cfg.has_section_key("audio", pair[1]):
			AudioServer.set_bus_volume_db(idx, cfg.get_value("audio", pair[1]))
