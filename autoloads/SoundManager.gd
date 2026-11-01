extends Node

# SFX key → res:// path. One-shots are WAV (T166/B53: starting an Ogg Vorbis playback
# costs ~0.9 ms of decoder setup per play -- ~1 ms per shot/hit on every peer);
# only the rarely-started loops stay .ogg (their scripts set AudioStreamOggVorbis.loop).
const _SFX_PATHS: Dictionary = {
	"rifle_fire":      "res://audio/sfx/weapons/rifle_fire.wav",
	"shotgun_fire":    "res://audio/sfx/weapons/shotgun_fire.wav",
	"machinegun_fire": "res://audio/sfx/weapons/machinegun_fire.wav",
	"sniper_fire":     "res://audio/sfx/weapons/sniper_fire.wav",
	"missile_launch":  "res://audio/sfx/weapons/missile_launch.wav",
	"rocket_launch":   "res://audio/sfx/weapons/rocket_launch.wav",
	"aerial_strike":   "res://audio/sfx/weapons/aerial_strike.wav",
	"patience_shot":   "res://audio/sfx/weapons/patience_shot.wav",
	"laser_loop":      "res://audio/sfx/weapons/laser_loop.ogg",
	"arc_loop":        "res://audio/sfx/weapons/arc_loop.ogg",
	"hit_impact":      "res://audio/sfx/weapons/hit_impact.wav",
	"mech_death":      "res://audio/sfx/mech/death_explosion.wav",
	"damage_hit":      "res://audio/sfx/mech/damage_hit.wav",
	"footstep":        "res://audio/sfx/mech/footstep.wav",
	"ui_click":        "res://audio/sfx/ui/click.wav",
}

const _MUSIC_PATHS: Dictionary = {
	"arena": "res://audio/music/arena_loop.ogg",
}

var _streams: Dictionary = {}
var _music_player: AudioStreamPlayer = null

func _ready() -> void:
	_setup_buses()

func _setup_buses() -> void:
	if AudioServer.get_bus_index("Music") < 0:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "Music")
		AudioServer.set_bus_send(idx, "Master")
	if AudioServer.get_bus_index("SFX") < 0:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "SFX")
		AudioServer.set_bus_send(idx, "Master")

# 3D positional SFX - attenuates with distance from pos
func play_sfx(key: String, pos: Vector3 = Vector3.ZERO, broadcast: bool = false) -> void:
	if broadcast and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_play_sfx.rpc(key, pos)
	var stream := _load_sfx(key)
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = "SFX"
	player.position = pos
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.unit_size = 10.0
	player.max_distance = 80.0
	get_tree().root.add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

@rpc("authority", "unreliable")
func _rpc_play_sfx(key: String, pos: Vector3) -> void:
	if multiplayer.is_server():
		return
	play_sfx(key, pos)

# 2D non-positional SFX - UI hits, crosshair flashes, etc.
func play_sfx_2d(key: String, volume_db: float = 0.0, broadcast: bool = false) -> void:
	if broadcast and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_play_sfx_2d.rpc(key, volume_db)
	var stream := _load_sfx(key)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "SFX"
	player.volume_db = volume_db
	get_tree().root.add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

@rpc("authority", "unreliable")
func _rpc_play_sfx_2d(key: String, volume_db: float) -> void:
	if multiplayer.is_server():
		return
	play_sfx_2d(key, volume_db)

func play_music(key: String, loop: bool = true) -> void:
	if not _MUSIC_PATHS.has(key):
		return
	var path: String = _MUSIC_PATHS[key]
	var stream: AudioStream = _streams.get(key)
	if stream == null:
		# The music assets are not authored yet; skip the load so the engine does
		# not log "Resource file not found" on every arena load. Re-enables itself
		# automatically once the .ogg exists.
		if not ResourceLoader.exists(path, "AudioStream"):
			return
		stream = ResourceLoader.load(path, "AudioStream") as AudioStream
		if stream == null:
			return
		_streams[key] = stream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	if _music_player == null:
		_music_player = AudioStreamPlayer.new()
		_music_player.bus = "Music"
		add_child(_music_player)
	if _music_player.stream == stream and _music_player.playing:
		return
	_music_player.stream = stream
	_music_player.play()

func stop_music() -> void:
	if _music_player != null:
		_music_player.stop()

func set_bus_volume(bus_name: String, db: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, db)

func get_sfx_stream(key: String) -> AudioStream:
	return _load_sfx(key)

func _load_sfx(key: String) -> AudioStream:
	if _streams.has(key):
		return _streams[key]
	if not _SFX_PATHS.has(key):
		return null
	var path: String = _SFX_PATHS[key]
	var stream := ResourceLoader.load(path, "AudioStream") as AudioStream
	if stream == null:
		push_warning("SoundManager: file not found: " + path)
		return null
	_streams[key] = stream
	return stream
