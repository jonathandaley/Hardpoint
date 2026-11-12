extends SceneTree
# T290: raw-protocol attacks on the game port: a peer that speaks ENet but not the game.
# No project code runs here (start it OUTSIDE the project: `godot --headless -s <this file>
# -- --sec-port=N [--sec-victim=<peer id>]`), so it can send what no real client would.
# Loopback only (HOST is a constant). Lines: `[sec] <name>: OK | VULN <why>`.
# Packet layout (SceneMultiplayer): byte 0 = command (7 = SYS), SYS byte 1 = 0 AUTH /
# 3 RELAY; an AUTH packet with no payload = "I have completed auth".

const HOST := "127.0.0.1"
const SYS := 7
var _port := 0
var _victim := 0
var _ver := 0  # --sec-ver=<Game.NET_VERSION> (the driver reads it from Game.gd; no project code runs here)
var _join_only := ""  # --sec-join-only=<check name>: just "can an honest stranger join right now?"
var _rng := RandomNumberGenerator.new()

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sec-port="):
			_port = int(a.get_slice("=", 1))
		elif a.begins_with("--sec-victim="):
			_victim = int(a.get_slice("=", 1))
		elif a.begins_with("--sec-ver="):
			_ver = int(a.get_slice("=", 1))
		elif a.begins_with("--sec-join-only="):
			_join_only = a.get_slice("=", 1)
	_rng.seed = 290 + Time.get_ticks_usec() % 1000
	if _join_only != "":
		_say(_join_only, "" if _honest_join() else "an honest player (another address) could not join")
		print("[sec] done")
		quit(0)
		return
	_run()

# An honest stranger: its own address (127.0.0.2, so the attacker's per-address limits
# don't apply to it), one hello, and it expects an answer.
func _honest_join() -> bool:
	var c := _connect(_id(), 3000, "127.0.0.2")
	if c.is_empty():
		return false
	_send(c, _hello("honest%d" % _rng.randi_range(0, 99999)))
	var ok := _welcomed(_pump(c, 3000))
	_close(c)
	return ok

# A current client's hello (T388: token | join ticket | version).
func _hello(token: String) -> PackedByteArray:
	return _auth("token:%s||%d" % [token, _ver])

# Did the server answer a hello with "ok" (lobby) or a live match (late-join state), not a refusal text?
func _welcomed(got: Dictionary) -> bool:
	for p in got["pkts"]:
		if (p as PackedByteArray).slice(2).get_string_from_utf8() == "ok" or (p as PackedByteArray).size() > 100:
			return true
	return false

func _say(check: String, why: String = "") -> void:
	print("[sec] %s: %s" % [check, "OK" if why == "" else "VULN " + why])

# -> [ENetConnection, ENetPacketPeer] or [] (refused / timed out)
func _connect(id: int, wait_ms: int = 3000, bind_ip: String = "") -> Array:
	var host := ENetConnection.new()
	if (host.create_host(1) if bind_ip == "" else host.create_host_bound(bind_ip, 0, 1)) != OK:
		return []
	var peer := host.connect_to_host(HOST, _port, 0, id)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < wait_ms:
		var ev: Array = host.service(20)
		if ev[0] == ENetConnection.EVENT_CONNECT:
			return [host, peer]
		if ev[0] == ENetConnection.EVENT_DISCONNECT:
			break
	host.destroy()
	return []

# Service a connection for `ms`; -> {"pkts": [PackedByteArray], "bytes": int, "dropped": bool}
func _pump(c: Array, ms: int) -> Dictionary:
	var out := {"pkts": [], "bytes": 0, "dropped": false}
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		var ev: Array = (c[0] as ENetConnection).service(10)
		if ev[0] == ENetConnection.EVENT_RECEIVE:
			var p: PackedByteArray = (ev[1] as ENetPacketPeer).get_packet()
			out["pkts"].append(p)
			out["bytes"] += p.size()
		elif ev[0] == ENetConnection.EVENT_DISCONNECT:
			out["dropped"] = true
			break
	return out

func _send(c: Array, bytes: PackedByteArray, reliable := true) -> void:
	if (c[1] as ENetPacketPeer).get_state() == ENetPacketPeer.STATE_CONNECTED:
		(c[1] as ENetPacketPeer).send(0 if reliable else 1, bytes, ENetPacketPeer.FLAG_RELIABLE if reliable else 0)

func _auth(text: String) -> PackedByteArray:
	var b := PackedByteArray([SYS, 0])
	b.append_array(text.to_utf8_buffer())
	return b

func _id() -> int:
	return _rng.randi_range(1000, 2000000000)

func _close(c: Array) -> void:
	if c.is_empty():
		return
	(c[1] as ENetPacketPeer).peer_disconnect_now()
	(c[0] as ENetConnection).flush()
	(c[0] as ENetConnection).destroy()

func _run() -> void:
	# 0. sanity: a plain hello gets an answer (else every check below is meaningless)
	var c := _connect(_id())
	if c.is_empty():
		_say("raw_connect", "could not open an ENet connection to %s:%d (is the server up?)" % [HOST, _port])
		quit(1)
		return
	_send(c, _hello("rawpeer0"))
	var first: Dictionary = _pump(c, 1500)
	var one_reply: int = first["bytes"]
	print("[sec] info: first hello answered with %d bytes in %d packets" % [one_reply, (first["pkts"] as Array).size()])

	_say("honest_hello", "" if _welcomed(first) else "a current-version hello was not welcomed (stale --sec-ver?)")

	# 0b. T388: a hello with no / another / a junk version is told why and never admitted
	for h in ["token:old", "token:old||0", "token:old||%d" % (_ver + 1), "token:old||-1", "token:old||%dx" % _ver,
			"token:old||%d|%d" % [_ver + 1, _ver], "token:old|%d" % _ver, "token:old||" + "9".repeat(40)]:
		var v := _connect(_id())
		if v.is_empty():
			continue
		_send(v, _auth(h))
		var ans: Dictionary = _pump(v, 1200)
		var told := false
		for p in ans["pkts"]:
			var t: String = (p as PackedByteArray).slice(2).get_string_from_utf8()
			told = told or t.contains("Update the game") or t.contains("older version")
		_send(v, PackedByteArray([SYS, 0]))  # "auth complete" anyway
		var after: Dictionary = _pump(v, 2600)
		_say("version_gate(%s)" % h.substr(9).left(12), "" if told and not _welcomed(ans) and bool(after["dropped"])
			else "hello '%s': told=%s welcomed=%s dropped=%s" % [h.left(30), told, _welcomed(ans), after["dropped"]])
		_close(v)

	# 1. repeated hellos: each one must not cost the server another full answer
	for i in 300:
		_send(c, _hello("rawpeer0"))
	var spam: Dictionary = _pump(c, 2500)
	_say("hello_spam", "" if int(spam["bytes"]) <= maxi(one_reply, 64) * 3 or bool(spam["dropped"])
		else "300 repeated hellos (~4 KB) were answered with %d bytes: every one costs the server a fresh reply before any login" % spam["bytes"])
	_close(c)

	# 2. oversized / odd hellos
	c = _connect(_id())
	if not c.is_empty():
		_send(c, _auth("token:" + "A".repeat(200000)))
		_send(c, _auth("token:|||||" + "\n[Server] fake log line\n"))
		_send(c, _auth("\u0000\u0001token:"))
		_send(c, _auth("ready"))
		_send(c, _auth("go"))
		_send(c, _auth("ok"))
		_pump(c, 800)
		_close(c)

	# 3. a peer that never says hello, sending non-auth packets
	c = _connect(_id())
	var noise_dropped := false
	if not c.is_empty():
		for i in 400:
			var b := PackedByteArray([_rng.randi_range(0, 6)])
			for k in _rng.randi_range(0, 40):
				b.append(_rng.randi_range(0, 255))
			_send(c, b, i % 2 == 0)
		noise_dropped = bool(_pump(c, 7000)["dropped"])
		_close(c)
	_say("preauth_noise", "" if noise_dropped else "a peer that never said hello was still connected after 7 s (every junk packet it sends logs a server error)")

	# 4. silent connections hogging the join slots
	var hogs: Array = []
	for i in 40:
		var h := _connect(_id(), 600)
		if not h.is_empty():
			hogs.append(h)
	for h in hogs:
		(h[0] as ENetConnection).service(0)
	_say("slot_hog", "" if _honest_join() else "%d silent connections from one address filled the server: a real player could not join" % hogs.size())
	for h in hogs:
		_close(h)

	# 5. peer ids we have no right to: the server's (1), none (0), a live player's
	for id in [1, 0, _victim]:
		if id == 0 and _victim == 0:
			continue
		c = _connect(id, 1500)
		if not c.is_empty():
			_send(c, _hello("idthief"))
			_pump(c, 1000)
			_close(c)
	print("[sec] info: id collision attempts sent (victim id %d); the driver checks the victim stayed connected" % _victim)

	# 6. become a real (spectating / lobby) peer by hand, then fuzz the packet parser
	c = _connect(_id())
	var admitted := false
	if not c.is_empty():
		_send(c, _hello("fuzzer"))
		var got: Dictionary = _pump(c, 1500)
		var lobby := false
		for p in got["pkts"]:
			if (p as PackedByteArray).size() == 4 and (p as PackedByteArray).slice(2).get_string_from_utf8() == "ok":
				lobby = true
		if not lobby:
			_send(c, _auth("ready"))
			_pump(c, 1500)
		_send(c, PackedByteArray([SYS, 0]))  # "auth complete"
		admitted = int(_pump(c, 1500)["bytes"]) > 0 or true
		var sent := 0
		for round in 3000:
			var cmd := round % 8
			var b := PackedByteArray([cmd | (_rng.randi_range(0, 31) << 3)])
			var n := _rng.randi_range(0, 96)
			if round % 50 == 0:
				n = 60000
			for k in n:
				b.append(_rng.randi_range(0, 255))
			_send(c, b, round % 3 != 0)
			sent += 1
			if round % 200 == 0:
				if bool(_pump(c, 30)["dropped"]):
					break
		# structured: a relay to the victim carrying junk, a path with 1 MiB of text
		if _victim > 0:
			var r := PackedByteArray([SYS, 3, 0, 0, 0, 0])
			r.encode_s32(2, _victim)
			r.append_array(PackedByteArray([0, 255, 255, 255, 255, 255, 255, 255, 255]))
			for i in 200:
				_send(c, r)
		var big := PackedByteArray([1, 255, 255, 255, 127])
		big.append_array("A".repeat(1 << 20).to_utf8_buffer())
		_send(c, big)
		_pump(c, 2000)
		print("[sec] info: fuzz sent %d packets as an admitted peer" % sent)
		_close(c)
	print("[sec] done")
	quit(0)
