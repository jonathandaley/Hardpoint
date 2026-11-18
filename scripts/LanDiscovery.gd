class_name LanDiscovery
extends Node
## T467 (HUMAN_FOUND 2026-11-18: "Multiplayer should have an \"open to LAN\" option, to avoid typing in
## manually"): a host opened to the LAN says so once a second on UDP PORT (broadcast); the Join tab
## listens and lists what it hears. A beacon is untrusted input (docs/SECURITY.md): small, ASCII,
## our magic, every field type-checked and bounded, a capped table; nothing is joined until the
## player clicks. A dedicated server never broadcasts (only MPEntry sets Game.lan_open).

const PORT := 8920
const MAGIC := "hardpoint-lan"
const EVERY_S := 1.0
const FORGET_S := 3.5
const MAX_BYTES := 512
const MAX_GAMES := 16

signal games_changed

var dest := "255.255.255.255"  # probes aim it at loopback
var games := {}  # listener: "ip:port" -> {ip, port, v, name, map, players, max, seen}
var _info := Callable()  # host: -> {name, port, players, max, map}
var _udp := PacketPeerUDP.new()
var _t := 0.0
var _listening := false

func broadcast(info_fn: Callable) -> void:
	_info = info_fn
	_udp.set_broadcast_enabled(true)
	_udp.set_dest_address(dest, PORT)
	_t = EVERY_S  # the first one at once

func listen() -> bool:
	_listening = _udp.bind(PORT) == OK
	return _listening

func _exit_tree() -> void:
	_udp.close()

func _process(delta: float) -> void:
	if _info.is_valid():
		_t += delta
		if _t >= EVERY_S:
			_t = 0.0
			var d: Dictionary = _info.call()
			d["m"] = MAGIC
			d["v"] = Game.NET_VERSION
			d["name"] = ascii(String(d.get("name", "")))
			d["map"] = ascii(String(d.get("map", "")))
			_udp.put_packet(JSON.stringify(d).to_ascii_buffer())
	if not _listening:
		return
	var now := Time.get_ticks_msec() * 0.001
	var changed := false
	while _udp.get_available_packet_count() > 0:
		var pkt := _udp.get_packet()
		var g := parse(pkt, _udp.get_packet_ip())
		if g.is_empty():
			continue
		var key := "%s:%d" % [g["ip"], g["port"]]
		if not games.has(key) and games.size() >= MAX_GAMES:
			continue
		var old: Dictionary = games.get(key, {})
		g["seen"] = now
		games[key] = g
		old.erase("seen")
		var cmp := g.duplicate()
		cmp.erase("seen")
		changed = changed or old != cmp
	for k in games.keys():
		if now - float(games[k]["seen"]) > FORGET_S:
			games.erase(k)
			changed = true
	if changed:
		games_changed.emit()

## A beacon -> a bounded game entry, or {} for anything that isn't one of ours.
static func parse(pkt: PackedByteArray, ip: String) -> Dictionary:
	if pkt.is_empty() or pkt.size() > MAX_BYTES or ip == "":
		return {}
	for b in pkt:
		if b < 32 or b > 126:
			return {}  # ASCII only: no decoding errors to log for a stranger's bytes (rule 9)
	var j := JSON.new()
	if j.parse(pkt.get_string_from_ascii()) != OK or not j.data is Dictionary:
		return {}
	var d: Dictionary = j.data
	if not d.get("m") is String or d["m"] != MAGIC:
		return {}
	var port := Game.clean_int(d.get("port"), 0, 65535, 0)
	if port < 1:
		return {}
	return {"ip": ip, "port": port, "v": Game.clean_int(d.get("v"), 0, 1000000, 0),
		"name": Game.clean_name(d.get("name"), "Host").left(20), "map": Game.clean_name(d.get("map"), "").left(24),
		"players": Game.clean_int(d.get("players"), 0, 99, 0), "max": Game.clean_int(d.get("max"), 0, 99, 0)}

static func ascii(s: String) -> String:
	var out := ""
	for ch in s.left(24):
		var c := ch.unicode_at(0)
		out += ch if c >= 32 and c <= 126 else "?"
	return out
