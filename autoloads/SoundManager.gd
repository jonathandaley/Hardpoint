extends Node

# SFX key → res:// path. Drop .ogg files here to activate sounds.
const _SFX_PATHS: Dictionary = {
	"rifle_fire":      "res://audio/sfx/weapons/rifle_fire.ogg",
	"shotgun_fire":    "res://audio/sfx/weapons/shotgun_fire.ogg",
	"machinegun_fire": "res://audio/sfx/weapons/machinegun_fire.ogg",
	"sniper_fire":     "res://audio/sfx/weapons/sniper_fire.ogg",
	"missile_launch":  "res://audio/sfx/weapons/missile_launch.ogg",
	"rocket_launch":   "res://audio/sfx/weapons/rocket_launch.ogg",
	"aerial_strike":   "res://audio/sfx/weapons/aerial_strike.ogg",
	"patience_shot":   "res://audio/sfx/weapons/patience_shot.ogg",
	"laser_loop":      "res://audio/sfx/weapons/laser_loop.ogg",
	"arc_loop":        "res://audio/sfx/weapons/arc_loop.ogg",
	"hit_impact":      "res://audio/sfx/weapons/hit_impact.ogg",
	"mech_death":      "res://audio/sfx/mech/death_explosion.ogg",
	"damage_hit":      "res://audio/sfx/mech/damage_hit.ogg",
	"footstep":        "res://audio/sfx/mech/footstep.ogg",
	"ui_click":        "res://audio/sfx/ui/click.ogg",
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
