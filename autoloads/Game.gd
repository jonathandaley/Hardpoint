extends "res://autoloads/game/Progression.gd"  # T393: profile / skills / loadout / settings (it extends game/SyncLog.gd)
# Singleton -- cross-match persistent state.
#
# Data ownership:
#   profile  -- server-owned fields (wins/losses/pilot_name). Keep clean for future sync.
#   loadout  -- server-owned fields (chosen mech, weapon config). Same rule.
#   settings -- local-only fields (mouse sensitivity). Never sent to server.
#
# Also hosts bot-coordination (formerly AIDirector autoload) to stay within the
# three-autoload V5 limit.

## T389: a dedicated server always records; a player's game only with Settings > RECORD MATCHES.
func _records_sessions() -> bool:
	return dedicated or (not OS.has_feature("web") and bool(settings.get("record_matches", false)))  # T420: no files in a browser

# ---- Multiplayer transport (V5: no new autoload; stays in Game.gd) ----

signal mp_peer_connected(id: int)
signal mp_peer_disconnected(id: int)
signal mp_join_failed
signal mp_server_lost

func _ready() -> void:
	_load_profile()
	_load_settings()
	_load_loadout()
	multiplayer.peer_connected.connect(_on_mp_peer_connected)
	multiplayer.peer_disconnected.connect(_on_mp_peer_disconnected)
	multiplayer.connection_failed.connect(_on_mp_connection_failed)
	multiplayer.server_disconnected.connect(_on_mp_server_disconnected)
	# T170 (B64): every connection passes an auth step first; the host refuses mid-match
	# joiners there, so they never enter the connected set (see _on_mp_peer_authenticating).
	var smp := multiplayer as SceneMultiplayer
	smp.auth_callback = _on_mp_auth
	smp.auth_timeout = AUTH_TIMEOUT_S
	smp.peer_authenticating.connect(_on_mp_peer_authenticating)
	smp.peer_authentication_failed.connect(_on_mp_auth_failed)
	set_process(false)
	_parse_sync_log_args()
	set_physics_process(sync_logging_enabled)  # M0.2: zero-cost when flag off
	_maybe_start_harness()  # M0.4: only when --mp-scenario= is present
	_maybe_start_dedicated()  # T204: only when --server is present
	# T420: test switches -- page address ?perf&sp&map=City&bots=4,5 in a browser, or after "--" on a
	# desktop command line (godot --path . -- perf sp map=City): perf = timing overlay, sp = straight into a match
	var flags: PackedStringArray = OS.get_cmdline_user_args()
	if OS.has_feature("web"):
		flags = str(JavaScriptBridge.eval("location.search")).trim_prefix("?").split("&")
		get_tree().process_frame.connect(_check_mouse_lock)
	if "perf" in flags:
		add_child(load("res://scripts/PerfOverlay.gd").new())
	if "sp" in flags:  # optional map=City (a resources/maps name), bots=4,5 (allies, enemies)
		for f in flags:
			var kv: PackedStringArray = f.split("=")
			if kv.size() == 2 and kv[0] == "map" and safe_res("res://resources/maps/%s.tres" % kv[1], "res://resources/maps/", ".tres"):
				loadout["map_def"] = load("res://resources/maps/%s.tres" % kv[1])
			elif kv.size() == 2 and kv[0] == "bots" and kv[1].split(",").size() == 2:
				loadout["sp_bots"] = [clampi(kv[1].split(",")[0].to_int(), 0, 5), clampi(kv[1].split(",")[1].to_int(), 0, 5)]
		start_sp_match.call_deferred()

# M0.4: spin up the autodebug harness driver, isolated from the normal UI path.
func _maybe_start_harness() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for a in args:
		if a.begins_with("--mp-scenario="):
			if not ResourceLoader.exists("res://tools/mp_harness/Harness.gd"):  # T390: release builds ship no tools/
				print("--mp-scenario needs the test harness, which is not part of this build (run from the project folder)")
				get_tree().quit.call_deferred(1)
				return
			var h: Node = load("res://tools/mp_harness/Harness.gd").new()
			h.name = "MPHarness"
			add_child.call_deferred(h)
			return

# ---- T204: dedicated server ----
# `godot --headless --path <project> -- --server[=port] [--team-size=N] [--map=<res path>]
#   [--min-players=N] [--no-bots]`: hosts with no local player and no menus. The lobby
# lives on the server (Lobby scene, no own entry): players JOIN by address, ready up,
# and the match starts LOBBY_COUNTDOWN_S after everyone is ready (a new joiner or an
# unready cancels it); bots fill the teams. Match -> lobby loops with no human host.
const LOBBY_COUNTDOWN_S := 5.0
## T400: once enough players are ready, one who is not gets this long before the match
## starts without it (it watches that match and plays again as soon as it readies up).
## Long on purpose (user: "long enough to never trigger on a legitimate
## game where somebody is just a bit slow").
var lobby_idle_s := 180.0  # server option --lobby-idle=<seconds> (30 or more)
var _waiting_since: Dictionary = {}  # server: peer id -> ticks ms since the ready players began waiting on it
var dedicated := false
var _min_players := 1
var _countdown_id := 0  # bumps on every lobby change; a stale countdown does nothing

func _maybe_start_dedicated() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	var port := -1
	var opts := {}
	for a in args:
		if a == "--server" or a.begins_with("--server="):
			port = int(a.get_slice("=", 1)) if a.contains("=") else 8910
		elif a.begins_with("--team-size="):
			opts["team_size"] = int(a.get_slice("=", 1))
		elif a.begins_with("--map="):
			opts["map_path"] = a.get_slice("=", 1)
		elif a.begins_with("--min-players="):
			opts["min_players"] = int(a.get_slice("=", 1))
		elif a.begins_with("--lobby-idle="):  # T400
			lobby_idle_s = maxf(30.0, float(a.get_slice("=", 1)))
		elif a == "--no-bots":
			opts["bot_fill"] = false
		elif a.begins_with("--mode="):  # T285: beacons | deathmatch
			opts["mode"] = a.get_slice("=", 1)
	if port > 0 and not has_node("MPHarness"):
		start_dedicated.call_deferred(port, opts)

## Also the harness's entry for "dedicated" scenarios (the same code path as --server).
func start_dedicated(port: int, opts: Dictionary = {}) -> void:
	dedicated = true
	_min_players = maxi(1, int(opts.get("min_players", 1)))
	host(port)
	if not multiplayer.multiplayer_peer is ENetMultiplayerPeer:  # offline also "is_server"
		push_error("[Server] could not host on port %d" % port)
		get_tree().quit(1)
		return
	mp_lobby = {
		"peers":      {},
		"bot_fill":   bool(opts.get("bot_fill", true)),
		"team_size":  clampi(int(opts.get("team_size", 5)), 1, 6),
		"map_path":   String(opts.get("map_path", "res://resources/maps/MathTemple.tres")),
		"mode":       String(opts.get("mode", "beacons")),
		"match_seed": 0,
	}
	account_server = load("res://scripts/AccountServer.gd").new()  # T207: accounts on port + 1
	account_server.name = "AccountServer"
	add_child(account_server)
	account_server.start(port + 1)
	print("[Server] dedicated on port %d: team size %d, bots %s, map %s, min players %d" % [port,
		mp_lobby["team_size"], mp_lobby["bot_fill"], mp_lobby["map_path"], _min_players])
	get_tree().change_scene_to_file("res://scenes/ui/Lobby.tscn")

# Server: any lobby change re-arms (or cancels) the start countdown.
func _dedicated_lobby_changed() -> void:
	if not dedicated or not mp_active_match["roster"].is_empty():
		return
	_countdown_id += 1
	var my_id := _countdown_id
	var peers: Dictionary = mp_lobby["peers"]
	var now := Time.get_ticks_msec()
	var ready_n := 0
	for pid in peers:
		ready_n += 1 if bool(peers[pid].get("ready", false)) else 0
	var enough := ready_n >= _min_players
	var idle_left := 0.0  # T400: longest wait still owed to an unready player
	var sat := false
	for pid in peers:
		var e: Dictionary = peers[pid]
		if bool(e.get("ready", false)) or bool(e.get("sitting_out", false)) or not enough:
			_waiting_since.erase(pid)
			continue
		if not _waiting_since.has(pid):
			_waiting_since[pid] = now
		var left: float = lobby_idle_s - (now - int(_waiting_since[pid])) / 1000.0
		if left > 0.0:
			idle_left = maxf(idle_left, left)
		else:
			e["sitting_out"] = true  # until it readies up (_apply_ready)
			sat = true
			print("[Server] peer %d not ready after %.0f s: sits this match out" % [pid, lobby_idle_s])
	var go := enough and idle_left <= 0.0
	var wait_s := int(ceil(idle_left)) if enough else 0
	if bool(mp_lobby.get("starting", false)) != go or int(mp_lobby.get("idle_wait", 0)) != wait_s or sat:
		mp_lobby["starting"] = go
		mp_lobby["idle_wait"] = wait_s  # clients count down from here (Lobby status line)
		_rpc_sync_lobby.rpc(mp_lobby)
	if not go:
		if enough:  # look again when the longest wait runs out
			get_tree().create_timer(idle_left + 0.1).timeout.connect(func() -> void:
				if my_id == _countdown_id:
					_dedicated_lobby_changed())
		return
	print("[Server] %d of %d ready; match in %.0f s" % [ready_n, peers.size(), LOBBY_COUNTDOWN_S])
	get_tree().create_timer(LOBBY_COUNTDOWN_S).timeout.connect(func() -> void:
		if my_id != _countdown_id or not mp_active_match["roster"].is_empty():
			return
		mp_lobby["starting"] = false
		var lobby: Script = load("res://scripts/Lobby.gd")
		var roster: Array = lobby.call("_build_roster")
		mp_lobby["match_seed"] = randi()
		print("[Server] match start: %d players, %d mechs" % [peers.size(), roster.size()])
		_rpc_match_start.rpc(mp_lobby["map_path"], roster, mp_lobby["match_seed"], mp_lobby.get("mode", "beacons")))

# ---- T207: online accounts (client) ----
# Signed in = `account` holds {host, port, email, session, profile}; Game.profile is the
# account's (from the server) and never written to the local profile.cfg (save_profile).
# Passwords only ever go to the account endpoint (TLS, game port + 1); the game connection
# carries the session token (auth handshake). Sessions last for this run of the game.
# var account: in game/Progression.gd (buying a skill checks it)
var account_server: Node = null  # server: AccountServer when dedicated
var account_mode := "login"      # Account screen: "login" | "signup"

## T401 (V62): the official server's certificate ships with the game; a connection to
## that host is accepted ONLY with that certificate, so nobody in between can pose as it
## and read a password. Any other server (a friend's, a LAN one) is encrypted but not
## checked -- there is nothing to check it against.
const OFFICIAL_HOST := "lemon.limedaley.com"
const OFFICIAL_PORT := 25574  # T266: game UDP; accounts TCP = +1 (deploy/README.md)
var account_pin_host := OFFICIAL_HOST                      # vars: probe account_pin swaps them
var account_pin_cert := "res://resources/account_server.crt"

func _account_tls(host_addr: String) -> TLSOptions:
	if host_addr.to_lower() != account_pin_host:
		return TLSOptions.client_unsafe()  # ponytail: no certificate to check an unofficial server against
	var cert := load(account_pin_cert) as X509Certificate if ResourceLoader.exists(account_pin_cert) else null
	# no pinned certificate in this build = an empty trust list: the handshake fails (closed, never unchecked)
	return TLSOptions.client(cert if cert != null else X509Certificate.new())

## One request to a server's account endpoint -> its reply ({"ok": false, "error"} on failure).
func account_request(host_addr: String, port: int, req: Dictionary) -> Dictionary:
	var tcp := StreamPeerTCP.new()
	if tcp.connect_to_host(host_addr, port + 1) != OK:
		return {"ok": false, "error": "cannot reach the server"}
	var tls := StreamPeerTLS.new()
	var t0 := Time.get_ticks_msec()
	while tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() - t0 < 5000:
		tcp.poll()
		await get_tree().process_frame
	if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return {"ok": false, "error": "cannot reach the server"}
	if tls.connect_to_stream(tcp, "hardpoint", _account_tls(host_addr)) != OK:
		return {"ok": false, "error": "secure connection failed"}
	var sent := false
	var buf := PackedByteArray()
	while Time.get_ticks_msec() - t0 < 10000:
		tls.poll()
		var st := tls.get_status()
		if st == StreamPeerTLS.STATUS_CONNECTED:
			if not sent:
				tls.put_data((JSON.stringify(req) + "\n").to_utf8_buffer())
				sent = true
			if tls.get_available_bytes() > 0:
				buf.append_array(tls.get_data(tls.get_available_bytes())[1])
				if buf.find(10) >= 0 or buf.size() > 65536:  # V61: a server's reply is one short line
					break
		elif st != StreamPeerTLS.STATUS_HANDSHAKING:
			break
		await get_tree().process_frame
	tls.disconnect_from_stream()
	var reply = JSON.parse_string(buf.get_string_from_utf8().get_slice("\n", 0)) if buf.find(10) >= 0 else null
	return reply if reply is Dictionary else {"ok": false, "error": "no answer from the server"}

func sign_in(host_addr: String, port: int, email: String, reply: Dictionary) -> void:
	account = {"host": host_addr, "port": port, "email": email, "session": reply["session"], "profile": reply["profile"]}
	profile = (reply["profile"] as Dictionary).duplicate(true)

func sign_out() -> void:
	account = {}
	profile = {"pilot_name": "Pilot", "wins": 0, "losses": 0, "elo": 1000, "xp": 0, "level": 1, "coins": 0, "skills": {}}
	_load_profile()

## T403: the account server forgot this session (it restarted: sessions live in its memory,
## or SESSION_S ran out). Sign out so nothing goes on as a silent guest, and leave the player
## a notice (MPEntry / Account show it). True when that happened.
const SESSION_LOST := "Your login expired (the server restarted). Log in again, or join again as a guest."
var account_notice := ""

func _session_lost(reply: Dictionary) -> bool:
	if account.is_empty() or reply.get("error", "") != "sign in again":  # AccountServer.ERR_SESSION (a wire value: older servers send it too)
		return false
	sign_out()
	account_notice = SESSION_LOST
	return true

## T384 (V61): two limits, on purpose far apart. MAX_PEERS is how many peers we ADMIT
## (6 v 6 is the biggest match; later ones are told "server full" in the handshake).
## ENET_SLOTS is how many connections ENet may hold, admitted or not: a connection costs a
## slot from its first packet, before it has proven anything, so the pool must be much
## bigger than the players it serves or a trickle of half-open connections fills it.
const MAX_PEERS := 12
const ENET_SLOTS := 1024

func host(port: int = 8910) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, ENET_SLOTS)
	if err != OK:
		push_error("Game.host: create_server failed (port %d): %d" % [port, err])
		mp_join_failed.emit()
		return
	_clear_mp_session()
	# V61: clients talk to the server only. With relay on, any client could address packets
	# (and any_peer RPCs) straight at another client through us.
	(multiplayer as SceneMultiplayer).server_relay = false
	multiplayer.multiplayer_peer = peer
	_session_start()

## T385: signed in and joining the server the account lives on -> fetch a single-use join
## ticket over TLS first (the session itself never goes on the unencrypted game
## connection, and never to any other server). A coroutine then; callers don't wait.
## account["game_port"]: where that server's game port is reached when it is not the port
## signed in to (the harness's chaos proxy stands in front of the game port only).
var _join_ticket := ""

func join(ip: String, port: int = 8910) -> void:
	_join_ticket = ""
	if not account.is_empty() and String(account["host"]).to_lower() == ip.to_lower() and int(account.get("game_port", account["port"])) == port:
		var r: Dictionary = await account_request(account["host"], int(account["port"]), {"op": "ticket", "session": account["session"]})
		_join_ticket = r.get("ticket", "") if r.get("ok", false) and r.get("ticket") is String else ""
		if _join_ticket == "" and _session_lost(r):
			mp_join_failed.emit()
			return
		if _join_ticket == "":
			print("[Game] no join ticket (%s): joining as a guest" % r.get("error", "?"))
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		push_error("Game.join: create_client failed (%s:%d): %d" % [ip, port, err])
		mp_join_failed.emit()
		return
	multiplayer.multiplayer_peer = peer
	_session_start()

func disconnect_mp() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_clear_mp_session()
	_session_stop()

# B44: called wherever an MP session starts or ends. No stale lobby peers (a new
# host must start fresh) and no stale roster (Arena._ready treats a non-empty
# roster as "this is an MP match", so a later SP match would spawn as MP).
func _clear_mp_session() -> void:
	mp_lobby["peers"].clear()
	mp_active_match["roster"] = []

# T167 (B59) / T214 (B90): ENet's peer timeout is only the backstop. A dead peer is
# noticed by silence at the game level -- the server takes a client's mech after 5 s
# without input (Arena.INPUT_SILENCE_MS), a client leaves after HOST_SILENCE_MS without a
# snapshot (Arena) -- so the cap can be generous. It must be: ENet drops a peer once one
# reliable packet has gone unacknowledged for the cap, and its retry wait starts at
# rtt + 4 x rtt variance and doubles. Measured on `bad` (80 +- 30 ms, 5% loss, reorder):
# rtt 190-300 ms, variance up to 186 ms -> first wait ~1 s, so 12 s fitted only 4 tries
# (0, 1, 3, 7 s): 4 losses in a row of one packet or its ack (~1e-4) dropped live
# players (B90). 45 s fits 6 tries (0, 1, 3, 7, 15, 31 s): ~1e-6.
const PEER_TIMEOUT_MS := 45000

func _on_mp_peer_connected(id: int) -> void:
	_pending.erase(id)  # admitted (its address stays in _peer_addr until it leaves)
	if dedicated:  # T402: the owner's check that the port forward keeps real addresses (deploy/README.md)
		print("[Server] peer %d joined from %s%s" % [id, _peer_addr.get(id, "?"), " (account)" if _peer_accounts.has(id) else ""])
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet != null and (multiplayer.is_server() or id == 1):  # other clients are relayed, not ENet peers here
		enet.get_peer(id).set_timeout(32, 5000, PEER_TIMEOUT_MS)
		# T200 (B78): ENet's packet throttle drops UNRELIABLE sends on a counter cycle once
		# it sees jittery RTTs, and recovers slowly while traffic is light: after an idle
		# lobby on a jittery link the 20 Hz snapshots went out in bursts (client mechs stood
		# still ~200 ms at a time). Deceleration 0 keeps it at its full-rate start value.
		# ponytail: no back-off of unreliable traffic on a truly congested link (~2 KB/s of
		# snapshots); set a bandwidth limit on the ENet host if that ever matters.
		enet.get_peer(id).throttle_configure(5000, 2, 0)
	if multiplayer.is_server() and not mp_active_match["roster"].is_empty():
		# T206: a late joiner (its Arena was built during auth): spectator, or its old slot
		var arena := get_tree().current_scene
		if arena == null or not arena.has_method("late_join_connected"):
			multiplayer.multiplayer_peer.disconnect_peer(id)  # mid scene change: try again
			return
		mp_lobby["peers"][id] = {"pilot_name": "Peer %d" % id, "elo": 1000, "level": 1, "squad": [], "ready": false}
		arena.late_join_connected(id, _late_tokens.get(id, ""))
		_rpc_request_meta.rpc_id(id)
		return
	mp_peer_connected.emit(id)
	# Lobby._on_peer_connected runs synchronously above, populating mp_lobby["peers"][id].
	# Now request real profile meta so the placeholder is replaced promptly.
	if multiplayer.is_server():
		_rpc_request_meta.rpc_id(id)

## T168: why the host refused us; read (and cleared) by MPEntry.
var mp_refused_reason := ""
## T176: FIND MATCH -> HOST (0) or JOIN (1) opens MPEntry on that tab.
var mp_entry_tab := 0

## T170 (B64): join handshake. A mid-match joiner used to be kicked after it had
## connected: SceneMultiplayer kept it in the connected set until the disconnect landed,
## so every broadcast to the half-closed peer logged 'Unable to send packet' (a flood on
## a lossy link). Now the host answers during SceneMultiplayer auth -- AUTH_OK + complete,
## or the refusal text and never complete -- and a refused peer is never "connected".
const AUTH_OK := "ok"
## Both sides must complete within this; generous for the `bad` net profile. A refused
## joiner leaves on its own as soon as the reason arrives; this only reaps silent ones.
const AUTH_TIMEOUT_S := 15.0

## T206: the joiner opens with its player token; the server answers AUTH_OK in the lobby,
## or, mid-match, with the whole live match (Arena.late_state, var_to_bytes). The joiner
## builds its Arena from that while still unconnected -- no broadcast can reach a node it
## doesn't have yet (B64's flood; T170 refused mid-match joins for that) -- then says
## "ready"; the server answers "go" and completes, the client completes on "go". The
## client must complete LAST: whoever completes last becomes connected first, and a
## server that is connected first streams (unreliable, another channel) into a client
## still authenticating -> engine error per packet (B89). A token that matches a player dropped < Arena.HOLD_S ago
## takes that slot back (Arena.late_state "rejoin_old").
const AUTH_READY := "ready"
const AUTH_GO := "go"
var late_join = null  # client: the late-join state until Arena applies it
## B101 (T245): the server has streamed to us since we joined -- proof it finished our auth.
## Whoever completes auth last is connected first (B89 makes that the client), so until a
## snapshot arrives our packets could reach a server still authenticating us (engine error
## per packet). Mech holds its input stream until then.
var server_heard := false
var _late_tokens: Dictionary = {}  # server: joining peer id -> token
var _peer_accounts: Dictionary = {}  # server: peer id -> account email (its join ticket, T385). Private: never in mp_lobby (V61)

## Client, signed in: ask the account's server; true + profile updated when it agreed.
func account_skill(op: String, key: String) -> bool:
	var reply: Dictionary = await account_request(account["host"], account["port"],
		{"op": op, "session": account["session"], "key": key})
	if _session_lost(reply) or not reply.get("ok", false) or account.is_empty():
		return false
	account["profile"] = reply["profile"]
	profile = (reply["profile"] as Dictionary).duplicate(true)
	return true

# ---- T384 (V61): the join handshake is the only thing a stranger can reach ----
# Before a peer is admitted it may send exactly: one hello ("token:..."), and -- only if
# we answered with a live match -- one "ready". Anything else, a second hello, an oversized
# one, silence past HELLO_TIMEOUT_S, or too many connections from one address drops it at
# once, so an unauthenticated peer can cost us one small reply and one slot for a few seconds.
const HELLO_MAX_BYTES := 256
## T388: both ends must speak the same protocol. Bump in EVERY release that changes gameplay
## (docs/SECURITY.md rule 15): @rpc signatures, hello / handshake, lobby / roster / late-join
## shapes, content (mechs, weapons, maps, modes, skills), server-decided numbers, a Godot
## upgrade. tools/oracles/net_security.py hashes the @rpc signatures and fails the suite
## until this is bumped with them.
const NET_VERSION := 2  # 2: lobby carries idle_wait / sitting_out (T400)
const HELLO_TIMEOUT_S := 4.0
const MAX_PENDING_PER_ADDR := 3   # connections still in the handshake, per address
const MAX_PEERS_PER_ADDR := 8     # calibration knob: players behind one router (LAN party)
var _pending: Dictionary = {}     # server: peer id -> {hello: bool, late: bool, ready: bool}
var _peer_addr: Dictionary = {}   # server: peer id -> remote address (pending and admitted)

func _peer_address(id: int) -> String:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	var p: ENetPacketPeer = enet.get_peer(id) if enet != null else null
	return p.get_remote_address() if p != null else ""

## Server: drop a peer that is still in the handshake. Silent and immediate: no reason
## text for it to parse, and its slot is free again at once.
func _drop_pending(id: int, why: String) -> void:
	if not _pending.has(id):
		return
	net_refuse(id, "handshake: " + why)
	_forget_peer(id)
	var mp := multiplayer.multiplayer_peer
	if mp != null and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		(multiplayer as SceneMultiplayer).disconnect_peer(id)  # out of the pending set, no signals
		if (mp as ENetMultiplayerPeer) != null and (mp as ENetMultiplayerPeer).get_peer(id) != null:
			mp.disconnect_peer(id, true)  # and reset the ENet peer now (frees the slot)

## T400: the server owner's ban list -- user://banned.txt, one address or account email a
## line (# = comment). Read at every join, so an edit needs no restart.
## ponytail: checked at join only; to remove someone who is connected, add the line and restart.
const BAN_FILE := "user://banned.txt"
func _banned(who: String) -> bool:
	if who == "" or not FileAccess.file_exists(BAN_FILE):
		return false
	for ln in FileAccess.get_file_as_string(BAN_FILE).split("\n"):
		if not ln.begins_with("#") and ln.strip_edges().to_lower() == who.to_lower():
			return true
	return false

func _forget_peer(id: int) -> void:
	_pending.erase(id)
	_waiting_since.erase(id)
	_peer_addr.erase(id)
	_late_tokens.erase(id)
	_peer_accounts.erase(id)
	_refusals.erase(id)
	_rate.erase(id)

func _on_mp_auth_failed(id: int) -> void:  # left or timed out mid-handshake
	_forget_peer(id)

# ---- T384 (V61): refusing client input ----
# Every refusal of something a client sent goes through here: one short log line for the
# first few per peer, then silence (a hostile client must not be able to fill the disk
# with our own error messages). Never push_error: a refusal is the server working.
const REFUSAL_LOG_MAX := 5
var _refusals: Dictionary = {}  # peer id -> count
var _rate: Dictionary = {}      # peer id -> {key -> [window start ms, count]}

func net_refuse(id: int, what: String) -> void:
	var n: int = int(_refusals.get(id, 0)) + 1
	_refusals[id] = n
	if n <= REFUSAL_LOG_MAX:
		print("[sec-refused] peer %d: %s%s" % [id, what.left(120).c_escape(),
			" (further refusals for this peer are not logged)" if n == REFUSAL_LOG_MAX else ""])

## At most `per_s` calls a second per peer and key; false = over (the caller drops the call).
func net_rate_ok(id: int, key: String, per_s: int) -> bool:
	var now := Time.get_ticks_msec()
	var r: Dictionary = _rate.get(id, {})
	var w: Array = r.get(key, [now, 0])
	if now - int(w[0]) >= 1000:
		w = [now, 0]
	w[1] = int(w[1]) + 1
	r[key] = w
	_rate[id] = r
	if int(w[1]) > per_s:
		net_refuse(id, "%s: more than %d a second" % [key, per_s])
		return false
	return true

## A display name from a client: printable, no markup or control characters, 16 chars.
static func clean_name(raw, fallback: String = "Pilot") -> String:
	if not raw is String:
		return fallback
	var out := ""
	for ch in (raw as String).left(64):
		var c := ch.unicode_at(0)
		if c >= 32 and c != 127 and not ch in "[]<>{}\\":
			out += ch
	out = out.strip_edges().left(16)
	return out if out != "" else fallback

## An int a client sent (JSON / Variant: int or float, anything else = `fallback`), clamped.
static func clean_int(raw, lo: int, hi: int, fallback: int) -> int:
	if typeof(raw) == TYPE_INT:
		return clampi(raw, lo, hi)
	if typeof(raw) == TYPE_FLOAT and is_finite(raw):
		return clampi(int(clampf(raw, -2.0e9, 2.0e9)), lo, hi)
	return fallback

## Client: a path the SERVER told us to load must be one of the game's own files of the
## expected kind (a hostile server must not pick what we load).
static func safe_res(path, prefix: String, ext: String) -> bool:
	return path is String and (path as String).begins_with(prefix) and (path as String).ends_with(ext) \
		and not (path as String).contains("..") and ResourceLoader.exists(path)

func _on_mp_peer_authenticating(id: int) -> void:
	if multiplayer.is_server():
		# wait for the joiner's token (_on_mp_auth) -- but not for long, and not for many
		var addr := _peer_address(id)
		var pending_here := 0
		var all_here := 0
		for pid in _peer_addr:
			if _peer_addr[pid] == addr:
				all_here += 1
				pending_here += 1 if _pending.has(pid) else 0
		_peer_addr[id] = addr
		_pending[id] = {"hello": false, "late": false, "ready": false}
		if pending_here >= MAX_PENDING_PER_ADDR or all_here >= MAX_PEERS_PER_ADDR:
			_drop_pending.call_deferred(id, "too many connections from %s" % addr)  # not inside the poll
			return
		get_tree().create_timer(HELLO_TIMEOUT_S, true).timeout.connect(func() -> void:
			if _pending.has(id) and not _pending[id]["hello"]:
				_drop_pending(id, "no hello"))
		return
	server_heard = false  # B101
	# hello = token:<rejoin token>|<join ticket or nothing>|<NET_VERSION>
	var hello := "token:%s|%s|%d" % [player_token(), _join_ticket, NET_VERSION]  # T207 / T385: the ticket ties this peer to the account, once
	_join_ticket = ""
	(multiplayer as SceneMultiplayer).send_auth(id, hello.to_utf8_buffer())

func _on_mp_auth(id: int, data: PackedByteArray) -> void:
	var smp := multiplayer as SceneMultiplayer
	if multiplayer.is_server():  # V41: client bytes are only ever read as text
		var p = _pending.get(id)
		if p == null:
			return  # already dropped (its packets were in the same poll)
		if data.size() > HELLO_MAX_BYTES:
			_drop_pending.call_deferred(id, "oversized handshake packet (%d bytes)" % data.size())
			return
		var msg := data.get_string_from_utf8()
		if msg.begins_with("token:") and not p["hello"]:
			p["hello"] = true
			var ver_s := msg.substr(6).get_slice("|", 2)  # T388; absent (a client from before it) = 0
			var ver := int(ver_s) if ver_s.length() <= 6 and ver_s.is_valid_int() else 0
			var sorry := ""
			if ver != NET_VERSION:
				sorry = "Update the game to play here" if ver < NET_VERSION else "This server runs an older version of the game"
			elif multiplayer.get_peers().size() >= MAX_PEERS:
				sorry = "The server is full"
			elif _banned(_peer_addr.get(id, "")):
				sorry = "You are banned from this server"
			if sorry != "":
				smp.send_auth(id, sorry.to_utf8_buffer())  # the joiner shows it and leaves (T168)
				get_tree().create_timer(2.0, true).timeout.connect(_drop_pending.bind(id, sorry))
				return
			_late_tokens[id] = _clean_token(msg.substr(6).get_slice("|", 0))
			var ticket := _clean_token(msg.substr(6).get_slice("|", 1))  # T207 / T385 ("" = guest)
			if ticket != "" and account_server != null:
				var who: String = account_server.redeem(ticket)
				if who != "" and _banned(who):
					smp.send_auth(id, "You are banned from this server".to_utf8_buffer())
					get_tree().create_timer(2.0, true).timeout.connect(_drop_pending.bind(id, "banned account"))
					return
				if who != "":
					_peer_accounts[id] = who  # V61: server-private, never in the broadcast lobby
			var arena := get_tree().current_scene
			if mp_active_match["roster"].is_empty() or arena == null or not arena.has_method("late_state"):
				smp.send_auth(id, AUTH_OK.to_utf8_buffer())
				smp.complete_auth(id)
				return
			p["late"] = true
			var st: Dictionary = arena.late_state(_late_tokens[id])
			st["you"] = id
			smp.send_auth(id, var_to_bytes(st))
		elif msg == AUTH_READY and p["late"] and not p["ready"]:
			p["ready"] = true
			smp.send_auth(id, AUTH_GO.to_utf8_buffer())
			smp.complete_auth(id)
		else:  # a second hello, "ready" out of turn, or anything else
			_drop_pending.call_deferred(id, "unexpected handshake packet")
		return
	var text := data.get_string_from_utf8()
	if text == AUTH_OK or text == AUTH_GO:
		smp.complete_auth(id)
		return
	var st = bytes_to_var(data)  # from the server (no object decoding); paths in it are checked
	if st is Dictionary and st.has("mechs") and safe_res(st.get("map_path"), "res://resources/maps/", ".tres") \
			and st.get("roster") is Array:
		late_join = st
		mp_active_match = {"map_path": st["map_path"], "roster": st["roster"], "match_seed": st["match_seed"],
			"mode": st.get("mode", "beacons")}
		var md = ResourceLoader.load(st["map_path"])
		if md != null:
			loadout["map_def"] = md
		get_tree().change_scene_to_file.call_deferred("res://scenes/arena/Arena.tscn")
		return
	mp_refused_reason = text
	_leave_server.call_deferred()  # not from inside the multiplayer poll

## Client: the late-join Arena is built -- finish the handshake (T206).
func late_join_ready() -> void:
	late_join = null
	(multiplayer as SceneMultiplayer).send_auth(1, AUTH_READY.to_utf8_buffer())  # completes on "go"

## A token / session as a client sent it: up to 64 letters and digits, else "" (none).
static func _clean_token(raw: String) -> String:
	if raw.length() > 64:
		return ""
	for ch in raw:
		if not (ch >= "0" and ch <= "9" or ch >= "a" and ch <= "z" or ch >= "A" and ch <= "Z" or ch == "_" or ch == "-"):
			return ""
	return raw

## Server: the rejoin token a peer presented in its hello ("" = none). Private (V61).
func peer_token(id: int) -> String:
	return _late_tokens.get(id, "")

## T206: per-install id, so a reconnect is recognised (the ENet id changes). Lives in its
## own [net] section: a saved pilot_name is what makes a profile (T192), not this.
func player_token() -> String:
	if profile.get("token", "") == "":
		var cfg := ConfigFile.new()
		cfg.load(_SAVE_PATH)
		var t: String = cfg.get_value("net", "token", "")
		if t == "":
			t = "%08x%08x%08x%08x" % [randi(), randi(), randi(), randi()]
			cfg.set_value("net", "token", t)
			cfg.save(_SAVE_PATH)
		profile["token"] = t
	return profile["token"]

# Server -> client: asks client to send its profile metadata (V36).
@rpc("authority", "call_remote", "reliable")
func _rpc_request_meta() -> void:
	var meta := {
		"pilot_name": profile.get("pilot_name", "Pilot"),
		"elo":        profile.get("elo", 1000),
		"level":      profile.get("level", 1),
		"skills":     profile.get("skills", {}),  # T332
	}
	_rpc_send_meta.rpc_id(1, meta)

# Client -> server: delivers profile metadata (V36, V41).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_send_meta(meta: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	# V41: sender must be a known lobby peer
	if not mp_lobby["peers"].has(sender):
		net_refuse(sender, "_rpc_send_meta: not in the lobby")
		return
	if not net_rate_ok(sender, "meta", 2):
		return
	var entry: Dictionary = mp_lobby["peers"][sender]
	var email: String = _peer_accounts.get(sender, "") if account_server != null else ""
	if email != "":  # T207: a signed-in player's name / ELO / level come from its account
		meta = account_server.profile(email)
	# V61: a guest's profile is its own claim -- shaped and bounded here, never trusted for more
	entry["pilot_name"] = clean_name(meta.get("pilot_name"))
	entry["elo"]        = clean_int(meta.get("elo"), 100, 4000, 1000)
	entry["level"]      = clean_int(meta.get("level"), 1, _LEVEL_THRESHOLDS.size() + 1, 1)
	entry["skills"]     = sanitize_skills(meta.get("skills", {}), entry["level"])  # T332
	if dedicated and email == "":
		entry["skills"] = {}  # T399 (user 2026-11-12): a guest's skills are its own claim -- none on a dedicated server
	broadcast_lobby()

func _on_mp_peer_disconnected(id: int) -> void:
	mp_peer_disconnected.emit(id)
	if not multiplayer.is_server():
		return
	# Case (a): if in lobby (no active match roster), remove peer and rebroadcast.
	if mp_active_match["roster"].is_empty() and mp_lobby["peers"].has(id):
		mp_lobby["peers"].erase(id)
		broadcast_lobby()
	_forget_peer.call_deferred(id)  # after every handler of this signal (Arena reads peer_token)

func _on_mp_connection_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_clear_mp_session()
	_session_stop()
	mp_join_failed.emit()

func _on_mp_server_disconnected() -> void:
	_leave_server()

## Host lost (server_disconnected) or refused us (T170 auth): tear the peer down, then
## the title, or the join screen when there is a reason to show.
func _leave_server() -> void:
	var mp := multiplayer.multiplayer_peer
	if mp != null and mp.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		mp.close()  # refused (still mid-handshake); a lost host's peer is already down
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_clear_mp_session()
	_session_stop()
	mp_server_lost.emit()
	# T153 (V40 exception): host gone -> back to the title, not an offline zombie Arena/Lobby
	# T168: refused join -> the join screen, which shows the reason
	var to := "res://scenes/ui/MPEntry.tscn" if mp_refused_reason != "" else "res://scenes/ui/TitleScreen.tscn"
	get_tree().change_scene_to_file.call_deferred(to)

# ---- Multiplayer lobby state (V39) ----

signal lobby_updated

# Server-authoritative lobby state.  Clients receive a replicated copy via
# _rpc_sync_lobby.  All mutation from clients must go through an @rpc to server
# which then calls broadcast_lobby().
var mp_lobby: Dictionary = {
	"peers":      {},    # peer_id (int) -> {pilot_name, elo, level, squad, ready}
	"bot_fill":   true,
	"team_size":  1,
	"map_path":   "res://resources/maps/MathTemple.tres",
	"match_seed": 0,
}

@rpc("authority", "call_local", "reliable")
func _rpc_sync_lobby(data: Dictionary) -> void:
	mp_lobby = data
	lobby_updated.emit()

# V40: all coordinated scene transitions go through here (server-origin only).
# T159/V52: clients only (call_remote) -- they leave first and ack; the server
# changes after every ack (server_change_scene), so no client RPC is in flight to
# a scene the server already left.
@rpc("authority", "call_remote", "reliable")
func _rpc_change_scene(path: String) -> void:
	if safe_res(path, "res://scenes/", ".tscn"):  # V61: only the game's own scenes
		get_tree().change_scene_to_file(path)
	_rpc_transition_ack.rpc_id(1)

# ---- Scene-transition handshake (T159, V52) ----
# Server-side: true only while every client has the match Arena loaded. The
# continuous unreliable streams (snapshots, beacon progress, scores) send only
# while live, so nothing streams into a scene a client hasn't loaded yet or has
# already left (Godot drops those packets and logs 'Node not found').
var mp_live: bool = false
var _await_acks: Array = []
var _await_then: Callable = Callable()
var _await_id: int = 0

# Server: run `then` once every connected client has acked (or after 5 s).
func server_await_clients(then: Callable) -> void:
	_await_id += 1
	var my_id := _await_id
	_await_acks = Array(multiplayer.get_peers())
	_await_then = then
	if _await_acks.is_empty():
		_finish_await()
		return
	get_tree().create_timer(5.0, true).timeout.connect(func() -> void:
		if my_id == _await_id and _await_then.is_valid():
			push_warning("[Game] transition: no ack from %s after 5 s, continuing" % str(_await_acks))
			_finish_await())

func _finish_await() -> void:
	_await_id += 1
	_await_acks.clear()
	var then := _await_then
	_await_then = Callable()
	if then.is_valid():
		then.call()

# Client -> server: "I'm in the new scene" (Arena loaded, or left for the lobby).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_transition_ack() -> void:
	if not multiplayer.is_server():
		return
	_await_acks.erase(multiplayer.get_remote_sender_id())  # V41: unknown sender = no-op
	if _await_acks.is_empty() and _await_then.is_valid():
		_finish_await()

const STREAM_DRAIN_S := 0.3  # B61: > bad-profile jitter (±30 ms) + snapshot interval (50 ms), with margin

# Server: coordinated scene change (V40). Streams stop, clients leave and ack,
# then the server follows.
func server_change_scene(path: String) -> void:
	mp_live = false
	# B61: snapshots/scores ride unreliable ENet channels, the change rides a reliable one;
	# on a jittery link a snapshot sent just before can land after it, once the client's
	# Arena is gone ('Node not found: Arena'). Let in-flight streams drain first.
	await get_tree().create_timer(STREAM_DRAIN_S).timeout
	# B77: the other direction too -- a client's last unreliable input packets, sent just
	# before its (reliable) ack, can land after it; let them drain into the live Arena.
	server_await_clients(func() -> void:
		get_tree().create_timer(STREAM_DRAIN_S).timeout.connect(func() -> void:
			get_tree().change_scene_to_file(path)))
	_rpc_change_scene.rpc(path)

func broadcast_lobby() -> void:
	if not multiplayer.is_server():
		return
	_rpc_sync_lobby.rpc(mp_lobby)
	_dedicated_lobby_changed()  # T204: every lobby change (join, leave, ready, squad)

# ---- Squad RPC (T113) ----

# V17 / V61: one squad entry as a client sent it -> {mech, weapons} rebuilt from the hangar's
# own lists (Lobby.ROSTER, Lobby.WEAPON_CATALOG), or {} = refused. Nothing the client sent is
# kept as-is: the path must BE a roster mech / a catalog weapon of the slot's size, so no
# debug mech, no arbitrary resource for the server (and every client) to load, no extra keys.
func clean_squad_entry(entry) -> Dictionary:
	var lobby: Script = load("res://scripts/Lobby.gd")
	if not entry is Dictionary or not entry.get("mech") is String or not (lobby.ROSTER as Array).has(entry["mech"]):
		return {}
	var md = ResourceLoader.load(entry["mech"])
	var weapons = entry.get("weapons", [])
	if md == null or not weapons is Array:
		return {}
	var slots: Array = md.weapon_slots if "weapon_slots" in md else []
	var out: Array = []
	for i in mini(slots.size(), (weapons as Array).size()):
		var w = weapons[i]
		if not w is String:
			return {}
		if w != "":
			var slot = slots[i]
			var required: int = slot.slot_size if "slot_size" in slot else 0
			var size := -1
			for c in lobby.WEAPON_CATALOG:
				if c["path"] == w:
					size = int(c["slot_size"])
			if size != required:
				return {}
		out.append(w)
	return {"mech": entry["mech"], "weapons": out}

# Validate + store squad for a peer, then broadcast. Called directly on server,
# or via _rpc_set_squad on clients.
func _apply_squad(peer_id: int, squad: Array) -> void:
	if not mp_lobby["peers"].has(peer_id) or squad.size() != 5:
		net_refuse(peer_id, "squad: not in the lobby / not 5 entries")
		return
	var clean: Array = []
	for entry in squad:
		var e := clean_squad_entry(entry)
		if e.is_empty():
			net_refuse(peer_id, "squad: an entry is not a hangar mech with catalog weapons")
			return
		clean.append(e)
	mp_lobby["peers"][peer_id]["squad"] = clean
	broadcast_lobby()

# Client -> server: send squad selection (V39, V41).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_squad(squad: Array) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if net_rate_ok(sender, "squad", 4):
		_apply_squad(sender, squad)

# ---- Match lifecycle (T115) ----

# Set by _rpc_match_start; read by Arena._ready in T116.
var mp_active_match: Dictionary = {
	"map_path":   "",
	"roster":     [],   # Array[{slot_idx, peer_id, team, squad, bot_id}]
	"match_seed": 0,
	"mode":       "beacons",  # T285: "beacons" | "deathmatch"
}

## T184: single player = a local MP match: the hangar squad as peer 1 plus bot fill,
## through the same roster / Arena / match-end path as MP, on the OfflineMultiplayerPeer
## (no socket: a web build can't host ENet; V56). Fills mp_lobby + mp_active_match only;
## start_sp_match() also loads the Arena. Tools/probes call this and edit the roster.
func setup_sp_match() -> void:
	var lobby := load("res://scripts/Lobby.gd")
	var md: Resource = loadout.get("map_def")
	var map_path: String = md.resource_path if md != null else "res://resources/maps/MathTemple.tres"
	mp_lobby = {"peers": {1: lobby._local_peer_meta()}, "bot_fill": true,
		"team_size": loadout.get("team_size", 1), "map_path": map_path, "match_seed": 0,
		"mode": loadout.get("mode", "beacons")}
	if loadout.get("sp_bots") is Array and (loadout["sp_bots"] as Array).size() == 2:  # T251: the SP picker's exact ally / enemy counts
		mp_lobby["bot_counts"] = loadout["sp_bots"]
	mp_active_match = {"map_path": map_path, "roster": lobby._build_roster(), "match_seed": 0,
		"mode": mp_lobby["mode"]}
	loadout["map_def"] = load(map_path)

func start_sp_match() -> void:
	setup_sp_match()
	get_tree().change_scene_to_file("res://scenes/arena/Arena.tscn")

# Server broadcasts this; all peers store match data and change scene (V40).
@rpc("authority", "call_local", "reliable")
func _rpc_match_start(map_path: String, roster: Array, match_seed: int, mode: String) -> void:
	if multiplayer.is_server():
		# T159: stream nothing until every client has loaded Arena (it acks from Arena._ready);
		# set up before any ack can arrive.
		mp_live = false
		server_await_clients(func() -> void: mp_live = true)
	_sync_next_match()
	mp_active_match = {
		"map_path":   map_path,
		"roster":     roster,
		"match_seed": match_seed,
		"mode":       mode,  # T285
	}
	# Keep SP loadout map_def in sync so Arena SP path still works.
	if safe_res(map_path, "res://resources/maps/", ".tres"):  # V61
		var md = ResourceLoader.load(map_path)
		if md != null:
			loadout["map_def"] = md
	get_tree().change_scene_to_file("res://scenes/arena/Arena.tscn")

# ---- Ready toggle (T114) ----

func _apply_ready(peer_id: int, ready: bool) -> void:
	if not mp_lobby["peers"].has(peer_id):
		net_refuse(peer_id, "ready: not in the lobby")
		return
	mp_lobby["peers"][peer_id]["ready"] = ready
	if ready:
		mp_lobby["peers"][peer_id].erase("sitting_out")  # T400: back in
	broadcast_lobby()

# Client -> server: toggle ready state (V39, V41).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_ready(ready: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if net_rate_ok(sender, "ready", 4):
		_apply_ready(sender, ready)

# ---- Bot coordination (V5: absorbed from former AIDirector autoload) ----

var _bot_intents: Dictionary = {}  # bot Node -> {beacon: Node, team: int}

func ai_director_set_intent(bot: Node, beacon: Node, team: int) -> void:
	_bot_intents[bot] = {"beacon": beacon, "team": team}

func ai_director_clear_intent(bot: Node) -> void:
	_bot_intents.erase(bot)

# ---- Match-end lifecycle (T121) ----

signal match_ended_mp(winner_team: int, stats: Array)

var _mp_return_confirmations: Dictionary = {}
var _mp_return_deadline: float = 0.0

@rpc("authority", "call_local", "reliable")
func _rpc_match_end(winner_team: int, stats: Array) -> void:
	SoundManager.stop_music()
	set_mouse_captured(false)
	match_ended_mp.emit(winner_team, stats)
	_update_mp_profile(winner_team, stats)
	if multiplayer.is_server() and account_server != null:
		_update_account_profiles(winner_team, stats)

# T207: server -- each signed-in player's result goes to its account, then back to it.
func _update_account_profiles(winner_team: int, stats: Array) -> void:
	for entry in mp_active_match["roster"]:
		var pid: int = int(entry.get("peer_id", 0))
		var email: String = _peer_accounts.get(pid, "")
		if pid < 2 or email == "":
			continue
		var before: Dictionary = account_server.profile(email)
		var after := _apply_match_to(before, int(entry.get("team", -1)), winner_team, stats, pid)
		account_server.save_profile(email, after)
		print("[Server] account %s: elo %d -> %d" % [email, int(before.get("elo", 0)), int(after.get("elo", 0))])
		_rpc_account_profile.rpc_id(pid, after)

signal account_profile_updated

@rpc("authority", "reliable")
func _rpc_account_profile(prof: Dictionary) -> void:
	if account.is_empty():
		return
	account["profile"] = prof
	profile = prof.duplicate(true)
	account_profile_updated.emit()

## Human opponents' pre-match ELOs for a player on `my_team`; bot ELO if none (V36).
## ponytail: bot fallback reads THIS peer's bot_difficulty, so the result table's
## guess for another peer's all-bot match can differ from what that peer applies.
func mp_opp_elos(my_team: int, stats: Array) -> Array:
	var roster: Array = mp_active_match["roster"]
	var opp_elos: Array = []
	for stat in stats:
		var sid: int = stat.get("peer_id", 0)
		if sid == 0:
			continue
		var their_team := -1
		for entry in roster:
			if entry.get("peer_id", 0) == sid:
				their_team = entry.get("team", -1)
				break
		if their_team != my_team and their_team != -1:
			var pe: int = stat.get("pre_elo", 0)
			if pe > 0:
				opp_elos.append(pe)
	if opp_elos.is_empty():
		opp_elos.append(get_bot_elo())
	return opp_elos

## ELO change: average K=32 delta across opponents, floor 100. Shared by the profile
## update and the MP result table (T168) so the shown change is the applied one.
## T285: 1 win, 0.5 draw (winner -1, a death match timing out level), 0 loss.
static func match_result(my_team: int, winner_team: int) -> float:
	return 0.5 if winner_team < 0 else float(winner_team == my_team)

func mp_elo_delta(my_elo: int, opp_elos: Array, result_val: float) -> int:
	var d: float = 0.0
	for opp_elo in opp_elos:
		var expected: float = 1.0 / (1.0 + pow(10.0, float(opp_elo - my_elo) / 400.0))
		d += float(_ELO_K) * (result_val - expected)
	return maxi(100, my_elo + roundi(d / float(opp_elos.size()))) - my_elo

# V36: each peer locally recomputes own ELO/XP/coins from broadcast match result.
func _update_mp_profile(winner_team: int, stats: Array) -> void:
	var my_peer_id := multiplayer.get_unique_id()
	var roster: Array = mp_active_match["roster"]
	# Find own team from roster.
	var my_team := -1
	for entry in roster:
		if entry.get("peer_id", 0) == my_peer_id:
			my_team = entry.get("team", -1)
			break
	if my_team == -1 or not account.is_empty():
		return  # T207: a signed-in player's result is applied on the server (_rpc_account_profile)
	_apply_match(my_team, winner_team, stats, my_peer_id)
	save_profile()

# T207: the same result math on an account's profile (server side).
# ponytail: borrows `profile` for the call, so the skill/level helpers need no profile arg.
func _apply_match_to(prof: Dictionary, my_team: int, winner_team: int, stats: Array, pid := 0) -> Dictionary:
	var keep := profile
	profile = prof.duplicate(true)
	_apply_match(my_team, winner_team, stats, pid)
	var out := profile
	profile = keep
	return out

func _apply_match(my_team: int, winner_team: int, stats: Array, my_pid := 0) -> void:
	var won: bool = winner_team == my_team
	if winner_team >= 0:  # T285: a draw is neither (it pays like a loss)
		var wl := "wins" if won else "losses"
		profile[wl] = profile.get(wl, 0) + 1
	var my_elo: int = profile.get("elo", 1000)
	var opp_elos := mp_opp_elos(my_team, stats)
	profile["elo"] = my_elo + mp_elo_delta(my_elo, opp_elos, match_result(my_team, winner_team))
	# XP with avg opponent ELO.
	var avg_opp_elo: int = 0
	for e in opp_elos:
		avg_opp_elo += e
	avg_opp_elo /= opp_elos.size()
	var xp_gain: int
	if won:
		xp_gain = clampi(roundi(50.0 * float(avg_opp_elo) / float(maxi(1, my_elo))), 25, 200)
	else:
		xp_gain = clampi(roundi(15.0 * float(avg_opp_elo) / float(maxi(1, my_elo))), 5, 50)
	xp_gain = roundi(float(xp_gain) * (1.0 + get_skill_effect("xp_bonus")))
	profile["xp"] = profile.get("xp", 0) + xp_gain
	_check_level_up()
	# Coins.
	var base_coins: int = 75 if won else 20
	for e in stats:  # T264: + the coins this player picked up; T364: + what its kills were worth
		if int(e.get("peer_id", -1)) == my_pid and my_pid > 0:
			base_coins += int(e.get("coins", 0)) + int(e.get("kill_coins", 0))
	profile["coins"] = profile.get("coins", 0) + apply_coin_pickup_bonus(base_coins)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_ready_for_next() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not mp_lobby["peers"].has(sender):
		net_refuse(sender, "_rpc_ready_for_next: not in the lobby")
		return
	_mp_return_confirmations[sender] = true
	_check_all_ready_for_next()

func _confirm_ready_for_next_local() -> void:
	_mp_return_confirmations[1] = true
	_check_all_ready_for_next()

func _check_all_ready_for_next() -> void:
	for peer_id in mp_lobby["peers"].keys():
		if not _mp_return_confirmations.has(peer_id):
			return
	_do_return_to_lobby()

func _do_return_to_lobby() -> void:
	_mp_return_confirmations.clear()
	_mp_return_deadline = 0.0
	set_process(false)
	for peer_id in mp_lobby["peers"].keys():
		mp_lobby["peers"][peer_id]["ready"] = false
	broadcast_lobby()
	server_change_scene("res://scenes/ui/Lobby.tscn")

func _process(_delta: float) -> void:
	if _mp_return_deadline > 0.0 and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		if Time.get_ticks_msec() * 0.001 >= _mp_return_deadline:
			_do_return_to_lobby()

# ---- T420: mouse capture. A browser grants the pointer lock only right after a click or key,
# and its own Esc drops the lock without a key event: a click takes the lock back (and doesn't
# fire), a lock lost behind the game's back tells the arena (pause menu). Desktop: plain set. ----
signal mouse_lock_lost
var _want_captured := false
var _had_lock := false

func _check_mouse_lock() -> void:  # web only, every frame (Game's own _process is off most of the time)
	if not _want_captured:
		return
	var locked := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if _had_lock and not locked:
		_had_lock = false
		mouse_lock_lost.emit()
	_had_lock = _had_lock or locked

func set_mouse_captured(on: bool) -> void:
	_want_captured = on
	_had_lock = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE

func _input(event: InputEvent) -> void:
	if OS.has_feature("web") and _want_captured and event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()

func ai_director_intent_count(beacon: Node, team: int) -> int:
	var count := 0
	var stale: Array = []
	for bot in _bot_intents:
		if not is_instance_valid(bot):
			stale.append(bot)
			continue
		var entry: Dictionary = _bot_intents[bot]
		if entry.get("beacon") == beacon and entry.get("team") == team:
			count += 1
	for bot in stale:
		_bot_intents.erase(bot)
	return count
