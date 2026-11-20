extends Node
# T467 probe (HUMAN_FOUND 2026-11-18: "Multiplayer should have an \"open to LAN\" option, to avoid
# typing in manually"): a host opened to the LAN broadcasts a beacon the Join tab lists (name, map,
# players, port) and forgets FORGET_S after it stops; a beacon from a stranger is checked like any
# network input -- garbage, oversized, non-ASCII, wrong magic, a bad port or fields of the wrong type
# are dropped or bounded, without an error; the Join tab shows a found game as a button.

func _fail(msg: String) -> void:
	push_error("[probe] lan_discovery FAIL: " + msg)
	get_tree().quit(1)

func _pkt(s: String) -> PackedByteArray:
	return s.to_ascii_buffer()

func _ready() -> void:
	var bad: Array = []
	var ok := LanDiscovery.parse(_pkt('{"m":"hardpoint-lan","v":3,"port":8910,"name":"Ace","map":"Giza","players":2,"max":6}'), "10.0.0.5")
	if ok.get("port") != 8910 or ok.get("name") != "Ace" or ok.get("map") != "Giza" or ok.get("players") != 2 or ok.get("ip") != "10.0.0.5":
		bad.append("a good beacon parsed as %s" % str(ok))
	var junk := {
		"garbage": _pkt("not json at all"),
		"wrong magic": _pkt('{"m":"other","port":8910}'),
		"no port": _pkt('{"m":"hardpoint-lan","name":"x"}'),
		"port string": _pkt('{"m":"hardpoint-lan","port":"8910"}'),
		"port 0": _pkt('{"m":"hardpoint-lan","port":0}'),
		"magic not a string": _pkt('{"m":7,"port":8910}'),
		"a list": _pkt('[1,2,3]'),
		"oversized": _pkt('{"m":"hardpoint-lan","port":8910,"name":"%s"}' % "A".repeat(600)),
		"high bytes": PackedByteArray([123, 34, 109, 34, 58, 200, 201, 125]),
		"empty": PackedByteArray(),
	}
	for k in junk:
		if not LanDiscovery.parse(junk[k], "10.0.0.5").is_empty():
			bad.append("%s was accepted" % k)
	var odd := LanDiscovery.parse(_pkt('{"m":"hardpoint-lan","port":99999,"name":["x"],"players":-5,"max":1e9,"map":"%s"}' % "B".repeat(100)), "10.0.0.6")
	if odd.get("port") != 65535 or odd.get("name") != "Host" or odd.get("players") != 0 or odd.get("max") != 99 or String(odd.get("map")).length() > 24:
		bad.append("wrong-typed fields weren't bounded: %s" % str(odd))
	# live: a broadcaster aimed at loopback, a listener
	var rx := LanDiscovery.new()
	add_child(rx)
	if not rx.listen():
		_fail("the listener couldn't bind UDP %d" % LanDiscovery.PORT)
		return
	var tx := LanDiscovery.new()
	tx.dest = "127.0.0.1"
	add_child(tx)
	tx.broadcast(func() -> Dictionary: return {"name": "Mesa Ace", "port": 9123, "players": 3, "max": 10, "map": "Badlands"})
	for i in 90:
		await get_tree().process_frame
		if not rx.games.is_empty():
			break
	var g: Dictionary = rx.games.get("127.0.0.1:9123", {})
	if g.get("name") != "Mesa Ace" or g.get("map") != "Badlands" or g.get("players") != 3 or g.get("v") != Game.NET_VERSION:
		bad.append("the listener heard %s (want Mesa Ace / Badlands / 3 / v%d)" % [str(rx.games), Game.NET_VERSION])
	tx.queue_free()
	await get_tree().create_timer(LanDiscovery.FORGET_S + 0.6).timeout
	# its own entry only: a game hosted by another test on this machine meanwhile broadcasts on the same
	# port and is (rightly) listed (suite 2026-11-19: "still listed" with nothing of ours left)
	if rx.games.has("127.0.0.1:9123"):
		bad.append("a host that stopped broadcasting is still listed after %.1f s (%s)" % [LanDiscovery.FORGET_S, str(rx.games.keys())])
	rx.queue_free()
	await get_tree().process_frame
	# the Join tab lists a found game as a button that fills the address
	var e: Node = load("res://scenes/ui/MPEntry.tscn").instantiate()
	add_child(e)
	await get_tree().process_frame
	var lan: LanDiscovery = e.get("_lan")
	lan.games["10.1.2.3:8910"] = {"ip": "10.1.2.3", "port": 8910, "v": Game.NET_VERSION, "name": "Bo", "map": "Giza", "players": 1, "max": 2, "seen": 1.0e12}
	lan.games_changed.emit()
	await get_tree().process_frame
	var btns: Array = (e.get("_lan_list") as Node).get_children().filter(func(n) -> bool: return n is Button and not n.is_queued_for_deletion())
	if btns.size() != 1 or not String(btns[0].text).begins_with("Bo  Giza  1/2"):
		bad.append("the Join tab shows %s for one found game" % str(btns.map(func(b): return b.text)))
	if not e.find_child("LanCheck", true, false) or not (e.find_child("LanCheck", true, false) as CheckBox).button_pressed:
		bad.append("HOST has no OPEN TO LAN box on by default")
	e.queue_free()
	await get_tree().process_frame
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] lan_discovery done")
	get_tree().quit(0)
