extends Node
# M0.4: headless two-process loopback entry for the MP autodebug harness.
# Instantiated by Game._ready ONLY when --mp-scenario=<file> is present, so none
# of this touches the normal (UI) code path. It bypasses Title/SignIn/MPEntry/
# Lobby and drives the real match-start flow directly: host or join over loopback
# ENet, build a roster, reuse Game._rpc_match_start, then swap a ReplayInputSource
# onto the local player mech (mech.set_input_source) so the run is deterministic.
# Identical netcode path to a real LAN game.
#
# Scenario JSON (untyped, V14):
#   {
#     "seed": 1337,
#     "port": 8910,
#     "map_path": "res://resources/maps/MathTemple.tres",
#     "mech": "res://resources/mechs/Hippogriff.tres",
#     "duration_ticks": 600,
#     "peers": {
#       "server":   {"input": {...ReplayInputSource spec...}},
#       "client_1": {"input": {...}, "settings": {"mouse_sensitivity": 0.006}}
#     }
#   }
# "settings" (optional, T138) overrides Game.settings for that roster slot.
# "net" (optional, T139): chaos profile name or dict; clients go through
# tools/mp_harness/netem_proxy.py (run_scenario.py --net overrides).
# Each process runs with its own user:// (run_scenario.py sets XDG_DATA_HOME).
# role + scenario path come from cmdline (--role=, --mp-scenario=).

const ReplaySrc := preload("res://scripts/ReplayInputSource.gd")
const DEFAULT_MECH := "res://resources/mechs/Hippogriff.tres"

var _scenario: Dictionary = {}
var _role: String = "server"
var _port: int = 8910
var _connect_port: int = -1  # T139: client dials the chaos proxy instead of the server
var _expected_clients: int = 1
var _connected: Array = []
var _match_started: bool = false
var _override_done: bool = false
var _deadline_frame: int = -1
# T144: scenario "actions" for this roster slot, e.g.
#   "actions": [{"tick": 200, "peer": "client_1", "action": "pause_quit"}]
# tick counts from the input override, like replay keyframes.
var _key: String = ""
var _override_frame: int = -1
var _actions: Array = []
var _quit_frame: int = -1
var _peer_checked: bool = false
var _lobby_check_frame: int = -1
var _lobby_wait: bool = false  # T159: server enters Lobby only after client acks
# T147: HUD layout dumps at these ticks (from override); scenario "hud_dump_ticks".
var _hud_ticks: Array = []
var _hud_file_started: bool = false  # first dump truncates (reruns into the same dir)
var _live_logged: bool = false  # T162: server prints the sync tick it went live (all clients in)
# T152 soak: perf/leak samples every 600 ticks; server ends the run 300 ticks after match end.
var _perf_next: int = -1
var _match_end_frame: int = -1
var _match_seen_running: bool = false  # Match.running is false before start too
# T163: scenario "matches": N plays N matches in one session. After a lobby_check the
# server starts the next match (same peers); every peer re-binds input to its new mech.
# Actions take "match": n (default 1). Match 2+ logs land in <run>/match<n>/ (Game).
var _matches: int = 1
var _match_n: int = 0
var _mine: Node = null

func _ready() -> void:
	var path := ""
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for a in args:
		if a.begins_with("--mp-scenario="):
			path = a.get_slice("=", 1)
		elif a.begins_with("--role="):
			_role = a.get_slice("=", 1)
		elif a.begins_with("--connect-port="):
			_connect_port = int(a.get_slice("=", 1))
	if path == "":
		push_error("[Harness] no --mp-scenario= given")
		get_tree().quit(1)
		return
	_scenario = _load_json(path)
	if _scenario.is_empty():
		push_error("[Harness] could not load scenario %s" % path)
		get_tree().quit(1)
		return
	_port = int(_scenario.get("port", 8910))
	_matches = int(_scenario.get("matches", 1))
	var peers: Dictionary = _scenario.get("peers", {})
	_expected_clients = 0
	for k in peers:
		if k != "server":
			_expected_clients += 1
	print("[Harness] role=%s port=%d expected_clients=%d" % [_role, _port, _expected_clients])
	# T138: run_scenario.py checks this path is inside the run folder (own user://).
	print("[Harness] user_data_dir=%s" % OS.get_user_data_dir())
	# T154: per-peer profile seed (process role; e.g. {"elo": 1200}) before any lobby meta goes out
	var seed_profile: Dictionary = peers.get(_sync_role(), {}).get("profile", {})
	for k in seed_profile:
		Game.profile[k] = seed_profile[k]
	Game.match_ended_mp.connect(_on_match_ended_mp)
	if _scenario.get("dedicated", false) and _role == "server":
		# T204: the real --server mode (Game.start_dedicated); clients JOIN through the menus
		Game.start_dedicated(_port, _scenario.get("server_opts", {}))
	elif _scenario.get("menu", false):
		_menu_flow()
	elif _role == "server":
		_start_server()
	else:
		_start_client()

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else {}

func _start_server() -> void:
	Game.host(_port)
	# Register the host like Lobby._ready does (B44 relies on a populated lobby).
	Game.mp_lobby["peers"][1] = {"pilot_name": "Host", "elo": Game.profile.get("elo", 1000),  # as Lobby._local_peer_meta
		"level": Game.profile.get("level", 1), "squad": [], "ready": false}
	if _expected_clients <= 0:
		_begin_match.call_deferred()
		return
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(func(id: int) -> void:  # T153 bot_takeover
		print("[Harness] peer_disconnected id=%d at sync tick %d" % [id,
			Engine.get_physics_frames() - int(Game.get("_sync_start_frame"))]))

func _on_peer_connected(id: int) -> void:
	if _match_started:
		print("[Harness] late peer connected: %d (mid-match; game decides)" % id)
		return  # T153: a mid-match join is the game's to handle, not the harness's
	if not _connected.has(id):
		_connected.append(id)
	# No Lobby scene in harness mode, so register the peer the way Lobby does;
	# otherwise the client's _rpc_send_meta reply trips the V41 unknown-sender guard.
	if not Game.mp_lobby["peers"].has(id):
		Game.mp_lobby["peers"][id] = {
			"pilot_name": "Peer %d" % id, "elo": 1000, "level": 1, "squad": [], "ready": false,
		}
	print("[Harness] client connected: %d (%d/%d)" % [id, _connected.size(), _expected_clients])
	if _connected.size() >= _expected_clients and not _match_started:
		_begin_match()

func _begin_match() -> void:
	_match_started = true
	var roster := _build_roster()
	var seed := int(_scenario.get("seed", 0))
	var map_path: String = _scenario.get("map_path", "res://resources/maps/MathTemple.tres")
	print("[Harness] starting match: %d mechs, seed=%d" % [roster.size(), seed])
	# call_local: the server also receives this and loads Arena.
	Game._rpc_match_start.rpc(map_path, roster, seed, String(_scenario.get("mode", "beacons")))

func _build_roster() -> Array:
	var mech_path: String = _scenario.get("mech", DEFAULT_MECH)
	var roster: Array = []
	# Server is peer 1, team 0.
	roster.append(_roster_entry(0, 1, 0, mech_path))
	# Each client gets the next team, in connection order (sorted for determinism).
	var ids := _connected.duplicate()
	ids.sort()
	var slot := 1
	for cid in ids:
		roster.append(_roster_entry(slot, cid, 1, mech_path))
		slot += 1
	# T152: filler bots (same entry shape as Lobby._build_roster bot fill)
	for i in int(_scenario.get("bots_per_team", 0)) * 2:
		var bot := _roster_entry(slot, 0, i % 2, mech_path)
		bot["bot_id"] = i
		roster.append(bot)
		slot += 1
	return roster

func _roster_entry(slot_idx: int, peer_id: int, team: int, mech_path: String) -> Dictionary:
	# M2.1: scenario may pin per-slot weapon scenes ("weapons": ["res://...tscn"])
	# so a scenario controls mag type / fire behavior instead of MechDef defaults.
	var weapons: Array = _scenario.get("weapons", [])
	var squad: Array = []
	for _i in 5:
		squad.append({"mech": mech_path, "weapons": weapons})
	return {
		"slot_idx": slot_idx,
		"peer_id": peer_id,
		"team": team,
		"squad": squad,
		"bot_id": -1,
	}

func _start_client() -> void:
	Game.join("127.0.0.1", _connect_port if _connect_port > 0 else _port)
	_quit_with_server()

func _quit_with_server() -> void:
	# T152: a client whose server is gone ends its run -- otherwise it keeps playing an
	# offline match and pollutes the logs (and the wall-clock tick alignment).
	# T153: first give the game 90 frames to route itself (V40 exception: peer torn
	# down, back to the title) and print where it went (peer_closed oracle).
	# T170: Game.mp_server_lost = host lost OR join refused during auth (a refused peer
	# never connects, so multiplayer.server_disconnected never fires for it)
	Game.mp_server_lost.connect(func() -> void:
		print("[Harness] server gone, quitting (%s)" % _role)
		for _i in 90:
			await get_tree().process_frame
		if _quitting:  # B124: our own deadline came first and is settling -- it routed us, not the loss
			return
		var scene := get_tree().current_scene
		print("[Harness] server_lost_check %s: connected=%s scene=%s rejoin=%s" % [_key, str(_mp_connected()).to_lower(),
			scene.name if scene != null else "<none>", str(_rejoining).to_lower()])
		_quit_clean(0))

func _mp_connected() -> bool:
	var mp := multiplayer.multiplayer_peer
	return mp != null and not (mp is OfflineMultiplayerPeer) \
		and mp.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED

# T164/T176: "menu": true -> reach the match through the real UI, as a player does:
# Title PLAY -> SignIn CONFIRM -> Hangar (squad: slot -> roster mech -> weapon arrows,
# BACK) -> FIND MATCH -> HOST / JOIN -> MPEntry (port / IP) -> Lobby (ready, start).
# Buttons get real mouse clicks at their on-screen centre (a hidden, covered or
# disabled button fails the step); OptionButton items are chosen by text via
# select()+item_selected (ponytail: popup clicks skipped). Per-peer "squad":
# [{"mech": "Slip", "weapons": ["MG LT"]}, ...] keyed by process role (client_1 ...):
# ponytail: process role, not roster slot -- fine for one client; two clients
# whose ENet ids sort opposite to their process names swap pick vs input spec.
# A stuck step prints "[Harness] MENU FAIL ..." and exits 3 (crash_scan, menu_flow).
func _menu_flow() -> void:
	var acct: Dictionary = _scenario.get("peers", {}).get(_sync_role(), {}).get("account", {})
	if not acct.is_empty() and not await _account_signup(acct):
		return
	var squad: Array = _scenario.get("peers", {}).get(_sync_role(), {}).get("squad", [])
	if not await _menu_connect(squad):
		return
	if not await _wait_scene("Lobby"):
		return
	await get_tree().process_frame
	if not _menu_pick.is_empty():  # picked offline in the hangar; the real peer id exists now
		print("[Harness] menu_pick peer=%d max_hp=%d weapons=%s mech=%s" % [multiplayer.get_unique_id(),
			_menu_pick[0], _menu_pick[1], _menu_pick[2]])
	if _role != "server":
		_click("ReadyBtn")
		return  # the server's START loads Arena here; _process binds input as usual
	var map_opt: OptionButton = get_tree().current_scene.get_node("HostControls/MapRow/MapOption")
	var lobby_maps: Array = get_tree().current_scene.get("_MAP_OPTIONS")
	for i in lobby_maps.size():
		if lobby_maps[i]["path"] == _scenario.get("map_path", lobby_maps[0]["path"]):
			_choose(map_opt, lobby_maps[i]["name"])
	var all_ready := func() -> bool:
		var peers: Dictionary = Game.mp_lobby["peers"]
		if peers.size() < _expected_clients + 1:
			return false
		for pid in peers:
			if pid != 1 and not peers[pid].get("ready", false):
				return false
		return true
	if not await _wait_until(all_ready, "every client in the lobby and ready"):
		return
	await get_tree().process_frame
	_click("StartButton")

# T207: sign up on the server's account endpoint the way the Account screen does
# (Game.account_request + Game.sign_in); the menus then run signed in.
func _account_signup(acct: Dictionary) -> bool:
	var req := {"op": "signup", "email": acct["email"], "password": acct["password"], "callsign": acct.get("callsign", "Pilot")}
	var reply: Dictionary = await Game.account_request("127.0.0.1", _port, req)
	if not reply.get("ok", false):
		_menu_fail("account signup: %s" % reply.get("error", "?"))
		return false
	Game.sign_in("127.0.0.1", _port, String(acct["email"]).to_lower(), reply)
	print("[Harness] account signed in: %s" % Game.account["email"])
	Game.account_profile_updated.connect(func() -> void:
		print("[Harness] account_profile elo=%d" % int(Game.profile.get("elo", 0))))
	return true

# Title -> SignIn -> Hangar (optional squad) -> FIND MATCH -> HOST or JOIN -> MPEntry by real clicks.
func _menu_connect(squad: Array = []) -> bool:
	# T186: a fresh start begins at the title; a rejoin after a pause-quit, in the hangar
	var start := func() -> bool:
		var cs := get_tree().current_scene
		return cs != null and (cs.name == "TitleScreen" or cs.name == "Hangar")
	if not await _wait_until(start, "scene TitleScreen or Hangar"):
		return false
	if get_tree().current_scene.name == "TitleScreen":
		_click("PlayButton")  # T192: PLAY AS GUEST -> callsign; a saved profile -> straight to the hangar
		var next := func() -> bool:
			var cs := get_tree().current_scene
			return cs != null and (cs.name == "SignIn" or cs.name == "Hangar")
		if not await _wait_until(next, "scene SignIn or Hangar"):
			return false
		if get_tree().current_scene.name == "SignIn":
			_click("ConfirmButton")
			if not await _wait_scene("Hangar"):
				return false
	await get_tree().process_frame
	if not squad.is_empty() and not await _menu_pick_squad(squad):
		return false
	_click("MatchmakingButton")
	await get_tree().process_frame
	_click("FindMatchPanel/Choices/" + ("HostBtn" if _role == "server" else "JoinBtn"))
	if not await _wait_scene("MPEntry"):
		return false
	await get_tree().process_frame  # MPEntry opened on the HOST / JOIN tab (T176)
	var entry := get_tree().current_scene
	if _role == "server":
		entry.get_node("TabContainer/Host/PortEdit").text = str(_port)
		_click("TabContainer/Host/HostButton")
	else:
		entry.get_node("TabContainer/Join/IPEdit").text = "127.0.0.1"
		entry.get_node("TabContainer/Join/JoinPortEdit").text = str(_connect_port if _connect_port > 0 else _port)
		_click("TabContainer/Join/JoinButton")
		if not _rejoining:
			_quit_with_server()
	return _menu_failed == ""

# T176: squads are set up in the hangar (the lobby picker is gone): per squad slot,
# click the slot, the roster mech (scrolled into view, as a player would), then each
# weapon row's ">" until it shows the wanted weapon, then BACK.
func _menu_pick_squad(squad: Array) -> bool:
	var hangar := get_tree().current_scene
	# scenarios name weapons as the lobby catalog does ("RIFLE LT"); the hangar shows its
	# own labels ("RIFLE LIGHT") -- translate through the scene path
	var catalog: Array = preload("res://scripts/Lobby.gd").WEAPON_CATALOG
	var hangar_name := {}
	for c in hangar.get("WEAPON_CATALOG"):
		hangar_name[c["path"]] = c["name"]
	var roster := "Content/MechPanel/RosterPanel/RosterScroll/RosterList/Roster_"
	for i in squad.size():
		_click("Content/MechPanel/SlotBtn%d" % i)
		await get_tree().process_frame
		var mech := String(squad[i].get("mech", ""))
		var rb := hangar.get_node_or_null(roster + mech) as Control
		if rb != null:
			(hangar.get_node("Content/MechPanel/RosterPanel/RosterScroll") as ScrollContainer).ensure_control_visible(rb)
			await get_tree().process_frame
		_click(roster + mech)
		await get_tree().process_frame  # weapon picker rebuilt for the new mech
		var wnames: Array = squad[i].get("weapons", [])
		var wpaths: Array = []
		for w in wnames.size():
			var path := ""
			for c in catalog:
				if c["name"] == wnames[w]:
					path = c["path"]
			var want: String = hangar_name.get(path, "?" + String(wnames[w]))
			var row := "Content/MechPanel/WeaponPicker/Slot%d" % w
			for _n in catalog.size():  # at most one lap of the catalog
				var lbl := hangar.get_node_or_null(row + "/Weapon") as Label
				if _menu_failed != "" or lbl == null or lbl.text == want:
					break
				_click(row + "/Next")
			var shown := hangar.get_node_or_null(row + "/Weapon") as Label
			if shown == null or shown.text != want:
				_menu_fail("hangar slot %d weapon row %d never showed %s" % [i, w, want])
				return false
			wpaths.append(path)
		if i == 0:  # slot 0 spawns first (menu_flow oracle checks it on every peer)
			var mech_path := "res://resources/mechs/%s.tres" % mech
			var md = load(mech_path)
			_menu_pick = [int(md.max_health) if md != null else -1, JSON.stringify(wpaths), mech_path]
		_click("BackBtn")
		await get_tree().process_frame
	return _menu_failed == ""

var _menu_failed: String = ""
var _menu_pick: Array = []  # T176: [max_hp, weapons json, mech path] of squad slot 0
var _rejoining: bool = false

func _menu_fail(why: String) -> void:
	if _menu_failed != "":
		return
	_menu_failed = why
	print("[Harness] MENU FAIL (%s): %s" % [_role, why])
	push_error("[Harness] MENU FAIL: " + why)
	get_tree().quit(3)

func _click(path: String) -> void:
	var b := get_tree().current_scene.get_node_or_null(path) as BaseButton
	if b == null or not b.is_visible_in_tree() or b.disabled:
		_menu_fail("%s not clickable (%s)" % [path, "missing" if b == null else
			"visible=%s disabled=%s" % [b.is_visible_in_tree(), b.disabled]])
		return
	var hits := [0]
	var count := func() -> void: hits[0] += 1
	b.pressed.connect(count)
	var at := b.get_global_rect().get_center()
	# headless: the OS never reports the mouse entering the window, and a Button only
	# takes a mouse press while hovered -> say so, then move onto it first
	get_viewport().notification(Node.NOTIFICATION_VP_MOUSE_ENTER)
	var mv := InputEventMouseMotion.new()
	mv.position = at
	mv.global_position = at
	get_viewport().push_input(mv, true)  # canvas coords (viewport is stretched 640x360 -> window)
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = at
		ev.global_position = at
		get_viewport().push_input(ev, true)
	if is_instance_valid(b):
		b.pressed.disconnect(count)
	print("[Harness] menu click %s" % path)
	if hits[0] != 1:  # something else is on top of it, or it ignores mouse input
		_menu_fail("click on %s at %s did not press it" % [path, at])

func _choose(opt: OptionButton, text: String) -> void:
	for i in opt.item_count:
		if opt.get_item_text(i) == text:
			opt.select(i)
			opt.item_selected.emit(i)
			return
	_menu_fail("no item '%s' in %s" % [text, opt.get_path()])

func _wait_scene(scene_name: String) -> bool:
	var there := func() -> bool:
		return get_tree().current_scene != null and get_tree().current_scene.name == scene_name
	return await _wait_until(there, "scene " + scene_name)

func _wait_until(cond: Callable, what: String) -> bool:
	for _i in 600:  # 10 s at 60 fps
		if _menu_failed != "":
			return false
		if cond.call():
			return true
		await get_tree().process_frame
	_menu_fail("timed out waiting for " + what)
	return false
	# Arena loads automatically when the server's _rpc_match_start (call_local)
	# reaches us; _process polls for our local mech and then overrides input.

# T206: after a rejoin, report how this client came back into the running match.
var _rejoin_logged := false
func _check_rejoined() -> void:
	var scn := get_tree().current_scene
	if _rejoin_logged or scn == null or scn.name != "Arena" or not _mp_connected():
		return
	_rejoin_logged = true
	var mine := "none"
	for m in get_tree().get_nodes_in_group("mechs"):
		if int(m.get("owner_peer_id")) == multiplayer.get_unique_id() and not m.get("is_dead"):
			mine = String(m.name)
	print("[Harness] rejoined peer=%d mech=%s spectating=%s" % [multiplayer.get_unique_id(), mine,
		str(scn.get("_spec_pivot") != null).to_lower()])

func _process(_delta: float) -> void:
	if _rejoining:
		_check_rejoined()
	if _role == "server" and not _live_logged and Game.mp_live:
		_live_logged = true
		print("[Harness] live at sync tick %d" % (Engine.get_physics_frames() - int(Game.get("_sync_start_frame"))))
	_lobby_tick()
	if _override_done and _match_n < _matches and not is_instance_valid(_mine):
		_override_done = false  # T163: match over; bind to the next match's mech
		_live_logged = false
		var old := get_node_or_null("ReplayInput")
		if old != null:
			old.name = "ReplayInputOld"
			old.queue_free()
	if not _override_done:
		_try_override_input()
		return
	var t := Engine.get_physics_frames() - _override_frame
	if _scenario.get("soak", false):
		Game.prof_on = true  # T165
		if _perf_next < 0 or Engine.get_physics_frames() >= _perf_next:
			_perf_sample()
			_perf_next = Engine.get_physics_frames() + 600
		var scn := get_tree().current_scene
		var mn = scn.get("match_node") if scn != null else null
		if mn != null and bool(mn.get("running")):
			_match_seen_running = true
		if _role == "server" and _match_seen_running and _match_end_frame < 0 and mn != null and not bool(mn.get("running")):
			_match_end_frame = Engine.get_physics_frames()
			print("[Harness] match ended at sync tick %d" % (_match_end_frame - int(Game.get("_sync_start_frame"))))
		if _match_end_frame >= 0 and Engine.get_physics_frames() >= _match_end_frame + 300:
			_deadline_frame = Engine.get_physics_frames()  # soak = exactly one match
	while not _actions.is_empty() and int(_actions[0].get("tick", 0)) <= t:
		_run_action(_actions.pop_front())
	if not _shot_damaged and is_instance_valid(_mine) and _mine is CharacterBody3D and float(_mine.get("health")) < float(_mine.get("max_health")):
		_shot_damaged = true
		_shot_later("damaged", 10)
	while not _hud_ticks.is_empty() and int(_hud_ticks[0]) <= t:
		_dump_hud(int(_hud_ticks.pop_front()))
	if _quit_frame >= 0 and not _peer_checked and Engine.get_physics_frames() - _quit_frame >= 60:
		_peer_checked = true
		var mp := multiplayer.multiplayer_peer
		var connected := mp != null and not (mp is OfflineMultiplayerPeer) \
			and mp.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED
		var scene := get_tree().current_scene
		print("[Harness] peer_check %s: connected=%s scene=%s" % [_key, str(connected).to_lower(),
			scene.name if scene != null else "<none>"])
	if _deadline_frame >= 0 and Engine.get_physics_frames() >= _deadline_frame and not _quitting:
		print("[Harness] duration reached, quitting (%s)" % _role)
		if not Game.account.is_empty():  # T207: account results must not land in the local file
			var cfg := ConfigFile.new()
			cfg.load("user://profile.cfg")
			print("[Harness] local_profile elo=%s" % str(cfg.get_value("profile", "elo", "none")))
		Game.disconnect_mp()
		_quit_clean(0)

# B124: quitting mid-match leaked at exit -> crash_scan FAIL (arc_audio@bad: the client's mech died
# in the last ~2 s): (a) a sound still playing (the death explosion) -- the dummy audio thread
# needs real time to drop a stopped playback (4 in 10 in a repro -> 0 in 10); (b) a coroutine
# still suspended (the 0.75 s death-camera pod ride awaits) leaks its function state + Variants.
# Stop every player and let QUIT_SETTLE_S of real time pass first.
const QUIT_SETTLE_S := 1.0
var _quitting := false

func _quit_clean(code: int) -> void:
	if _quitting:
		return
	_quitting = true
	Game.sync_logging_enabled = false  # the settle second isn't the match: log nothing more
	for n in get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false) \
			+ get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
		n.stop()
	await get_tree().create_timer(QUIT_SETTLE_S, true, false, true).timeout
	get_tree().quit(code)

func _lobby_tick() -> void:
	if _lobby_wait and get_tree().current_scene != null and get_tree().current_scene.name == "Lobby":
		_lobby_wait = false
		_lobby_check_frame = Engine.get_physics_frames() + 90  # 90 ticks after ARRIVING
	if _lobby_check_frame >= 0 and Engine.get_physics_frames() >= _lobby_check_frame:
		_lobby_check_frame = -1
		var peers: Dictionary = Game.mp_lobby["peers"]
		var squads := 0
		for pid in peers:
			squads += 1 if not (peers[pid].get("squad", []) as Array).is_empty() else 0
		print("[Harness] lobby_check peers=%d expected=%d squads=%d roster=%d" % [peers.size(),
			_expected_clients + 1, squads, (Game.mp_active_match["roster"] as Array).size()])
		if _role == "server" and _match_n < _matches:
			_begin_match()  # T163: next match from the lobby, same peers

# Once our local player mech exists (Arena spawned it), swap its input source
# for a ReplayInputSource driven by this role's scripted sequence.
func _try_override_input() -> void:
	# T162: the server's script starts when the match goes live (mechs are held
	# until then), so choreography isn't eaten by the wait for clients.
	if _role == "server" and _expected_clients > 0 and not Game.mp_live:
		return
	if Game.dedicated:
		_dedicated_match_live()
		return
	var my_id := multiplayer.get_unique_id()
	var mine: Node = null
	for m in get_tree().get_nodes_in_group("mechs"):
		if int(m.get("owner_peer_id")) == my_id:
			mine = m
			break
	if mine == null:
		return
	var peers: Dictionary = _scenario.get("peers", {})
	# M2.4: bind the input spec to the ROSTER SLOT, not the launch process.
	# ENet connect order is a race, so "which client process am I" is
	# nondeterministic across runs; "which roster slot is my mech in" is not
	# (server sorts ids before building the roster). The Nth client slot always
	# runs the "client_N" spec, whichever process ended up owning it. Process
	# log filenames still follow --sync-role, so a log file's name need not
	# match the spec its mech ran; oracles key on mech_id and don't care.
	var key := "server"
	if _role != "server":
		var nth := 0
		for entry in Game.mp_active_match.get("roster", []):
			if int(entry.get("peer_id", 0)) > 1:
				nth += 1
				if int(entry["peer_id"]) == my_id:
					key = "client_%d" % nth
					break
	var spec: Dictionary = peers.get(key, {}).get("input", {})
	if peers.get(key, {}).get("bot", false):
		_attach_bot(mine)
		_finish_override(key, mine)
		return
	# T138: per-slot settings overrides (e.g. client mouse_sensitivity != server),
	# bound to the roster slot like the input spec (V43).
	var overrides: Dictionary = peers.get(key, {}).get("settings", {})
	for k in overrides:
		Game.settings[k] = overrides[k]
	if not overrides.is_empty():
		print("[Harness] settings override (%s): %s" % [key, overrides])
	var replay := ReplaySrc.new()
	replay.name = "ReplayInput"
	replay.mech_id = mine.name
	add_child(replay)
	replay.load_spec(spec)
	mine.set_input_source(replay)
	_finish_override(key, mine)

# T204: a dedicated server has no mech to bind; its clock (actions, deadline) starts
# when each match goes live. _mine = the Arena, freed on the way back to the lobby,
# which re-arms this for the next match (the _process match-2 check).
func _dedicated_match_live() -> void:
	var scn := get_tree().current_scene
	if scn == null or scn.name != "Arena":
		return
	_override_done = true
	_key = "server"
	_mine = scn
	_match_n += 1
	_override_frame = Engine.get_physics_frames()
	for a in _scenario.get("actions", []):
		if String(a.get("peer", "")) == "server" and int(a.get("match", 1)) == _match_n:
			_actions.append(a)
	# the last match: outlive the clients, which log until their own deadline
	_deadline_frame = _override_frame + int(_scenario.get("duration_ticks", 600)) + 180 \
		if _match_n >= _matches else -1
	print("[Harness] dedicated server: match %d live" % _match_n)

# T204: a player after a match on a dedicated server: BACK TO LOBBY, then READY again.
func _back_to_lobby_ready() -> void:
	for i in 20:
		await get_tree().process_frame  # the result panel is built on the same signal
	var b := get_tree().current_scene.find_child("BackToLobbyBtn", true, false)
	if b == null:
		_menu_fail("no BACK TO LOBBY button after match %d" % _match_n)
		return
	_click(String(get_tree().current_scene.get_path_to(b)))
	if await _wait_scene("Lobby"):
		await get_tree().process_frame
		_click("ReadyBtn")

func _finish_override(key: String, mine: Node) -> void:
	_override_done = true
	_key = key
	_mine = mine
	_match_n += 1
	_hud_file_started = false  # match 2+ dumps go to the new match dir
	_override_frame = Engine.get_physics_frames()
	for a in _scenario.get("actions", []):
		if String(a.get("peer", "")) == key and int(a.get("match", 1)) == _match_n:
			_actions.append(a)
	_actions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("tick", 0)) < int(b.get("tick", 0)))
	_arm_shots(mine)
	_hud_ticks = _scenario.get("hud_dump_ticks", []).duplicate()
	_hud_ticks.sort()
	_deadline_frame = Engine.get_physics_frames() + int(_scenario.get("duration_ticks", 600))
	print("[Harness] input override done for %s (mech %s, match %d); deadline frame %d" % [_role, mine.name, _match_n, _deadline_frame])
	if _scenario.get("menu", false):  # T164: what actually spawned, for the menu_flow oracle
		for m in get_tree().get_nodes_in_group("mechs"):
			var wp: Array = []
			for w in m.get("_weapons"):
				wp.append(w.scene_file_path)
			print("[Harness] spawned owner=%d max_hp=%d weapons=%s mech=%s" % [int(m.get("owner_peer_id")),
				int(m.get("max_health")), JSON.stringify(wp), m.name])

# T144: lifecycle actions go through the game's real code paths, never a
# harness shortcut, so a fix in the game is what turns the oracles green.
func _run_action(a: Dictionary) -> void:
	var action := String(a.get("action", ""))
	print("[Harness] action %s (%s)" % [action, _key])
	match action:
		"pause_quit":
			# = pause menu QUIT (PauseMenu -> Arena._on_pause_quit)
			get_tree().current_scene.call("_on_pause_quit")
			_quit_frame = Engine.get_physics_frames()
		"kill_client":
			# T153: SIGKILL -- no ENet goodbye; the server only learns via its peer timeout
			OS.kill(OS.get_process_id())
		"rejoin":
			# T153: a player who quit joins again mid-match through the real menus
			# T206: expected back in the match, flying its old mech again (rejoined line)
			_rejoining = true
			_menu_connect()
		"end_match":
			# T154: the real match end (Match.force_end, as on a team wipe) -> Game._rpc_match_end
			get_tree().current_scene.get("match_node").force_end(int(a.get("winner", 0)))
		"kill_mech":
			# T155: server kills the mech flown by roster slot "slot" (e.g. client_1) through take_damage
			var nth := 0
			for e in Game.mp_active_match.get("roster", []):
				var pid := int(e.get("peer_id", 0))
				if pid > 1:
					nth += 1
				if (pid == 1 and a.get("slot") == "server") or (pid > 1 and a.get("slot") == "client_%d" % nth):
					for m in get_tree().get_nodes_in_group("mechs"):
						if int(m.get("owner_peer_id")) == pid and not m.get("is_dead"):
							m.take_damage(float(a.get("amount", float(m.get("health")) + 1000.0)))
		"lobby_after_match":
			# T154: the real post-match return (all ready / 30 s timeout -> Game._do_return_to_lobby)
			Game._do_return_to_lobby()
			_lobby_wait = true
		"return_to_lobby":
			# = match end -> lobby: Game.server_change_scene, the V40/T159 coordinated
			# change that Game._do_return_to_lobby (T121) uses, mid-stream (T146/T159)
			Game.server_change_scene("res://scenes/ui/Lobby.tscn")
			_lobby_wait = true
		_:
			push_error("[Harness] unknown action %s" % action)

# T147: one JSON line per visible HUD Control: path, class, global rect, text.
# Headless still computes Control layout (offsets/anchors -> rects).
func _dump_hud(tick: int, tag: String = "") -> void:
	var hud: Node = get_tree().current_scene.get_node_or_null("HUD") if get_tree().current_scene else null
	if hud == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var rows: Array = []
	var stack: Array = [hud]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Control and (n as Control).is_visible_in_tree():
			var r := (n as Control).get_global_rect()
			rows.append({"path": String(hud.get_path_to(n)), "class": n.get_class(),
				"rect": [r.position.x, r.position.y, r.size.x, r.size.y],
				"text": String(n.get("text")) if "text" in n else ""})
	var path: String = String(Game.get("_sync_dir")).path_join("%s.hud.jsonl" % _sync_role())
	var f := FileAccess.open(path, FileAccess.READ_WRITE if _hud_file_started else FileAccess.WRITE)
	_hud_file_started = true
	f.seek_end()
	f.store_line(JSON.stringify({"tick": tick, "tag": tag, "slot": _key, "viewport": [vp.x, vp.y], "controls": rows}))
	f.close()
	if DisplayServer.get_name() != "headless":  # rendered run (Xvfb): save what the player sees
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			String(Game.get("_sync_dir")).path_join("%s.hud_%s.png" % [_sync_role(), tag if tag != "" else str(tick)]))

# T154: each peer's profile after it applied the match result (profile_parity oracle)
func _on_match_ended_mp(_winner: int, _stats: Array) -> void:
	await get_tree().process_frame  # Game._update_mp_profile runs right after the signal
	var team := -1
	for e in Game.mp_active_match.get("roster", []):
		if int(e.get("peer_id", 0)) == multiplayer.get_unique_id():
			team = int(e.get("team", -1))
	var p: Dictionary = Game.profile
	print("[Harness] profile_after match=%d team=%d elo=%d xp=%d coins=%d level=%d" % [_match_n, team,
		int(p.get("elo", 0)), int(p.get("xp", 0)), int(p.get("coins", 0)), int(p.get("level", 0))])
	if _scenario.get("dedicated", false) and _role != "server" and _match_n < _matches:
		_back_to_lobby_ready()

# T156: event-driven screenshots ("shots": ["spawn", "damaged", "dead", "match_end"]) --
# a rendered peer runs ~4x slower than the server, so tick-scheduled shots would miss
# server-driven moments. PNG only on a rendered peer (_dump_hud), JSON layout everywhere.
var _shot_damaged: bool = false

func _arm_shots(mine: Node) -> void:
	var shots: Array = _scenario.get("shots", [])
	_shot_damaged = not shots.has("damaged")
	if shots.has("spawn"):
		_shot_later("spawn", 30)
	if shots.has("dead"):
		mine.died.connect(func() -> void: _shot_later("dead", 45), CONNECT_ONE_SHOT)
	if shots.has("match_end"):
		Game.match_ended_mp.connect(func(_w: int, _s: Array) -> void: _shot_later("match_end", 45), CONNECT_ONE_SHOT)

func _shot_later(tag: String, ticks: int) -> void:
	for _i in ticks:  # physics ticks: a slow rendered peer runs up to 8 per drawn frame
		await get_tree().physics_frame
	_dump_hud(Engine.get_physics_frames() - _override_frame, tag)
	print("[Harness] shot %s" % tag)

func _sync_role() -> String:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--sync-role="):
			return a.get_slice("=", 1)
	return _role

# T152: drive this peer's own mech with the game's bot AI (as Arena does for a
# disconnected player, _bot_ify_disconnected_mech). On a client the AI's input
# goes through the real network path (_maybe_forward_input -> _rpc_input).
func _attach_bot(mech: Node) -> void:
	if mech.get_node_or_null("NavAgent") == null:
		var nav := NavigationAgent3D.new()
		nav.name = "NavAgent"
		nav.path_desired_distance = 1.5
		nav.target_desired_distance = 2.5
		mech.add_child(nav)
	var ai: Node = load("res://scripts/AIInputSource.gd").new()
	ai.name = "HarnessBot"
	ai.bot_id = 100 + int(Game.mp_active_match.get("roster", []).size())
	mech.add_child(ai)
	mech.set_input_source(ai)
	ai.set_mp_seed(int(_scenario.get("seed", 0)) ^ multiplayer.get_unique_id())
	print("[Harness] bot drives %s (%s)" % [mech.name, _key if _key != "" else _role])

# T152: one perf/leak sample line (Performance monitors) for the soak oracle.
func _perf_sample() -> void:
	var tick := Engine.get_physics_frames() - int(Game.get("_sync_start_frame"))
	print("[Harness] perf tick=%d phys_ms=%.3f objects=%d nodes=%d orphans=%d mem=%d" % [tick,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), Performance.get_monitor(Performance.MEMORY_STATIC)])
	# T165: average ms per physics frame per instrumented system over the window
	var prof: Dictionary = Game.prof_take()
	var parts: Array = []
	for k in prof:  # avg/max ms per physics frame over the window
		var e: Array = prof[k]
		parts.append("%s=%.2f/%.2f" % [k, float(e[0]) / 600.0 / 1000.0, float(e[1]) / 1000.0])
	print("[Harness] prof tick=%d %s" % [tick, " ".join(parts)])

func _physics_process(_delta: float) -> void:
	if Game.prof_on:
		Game.prof_end_frame()  # T165: per-frame boundary for the profiler
