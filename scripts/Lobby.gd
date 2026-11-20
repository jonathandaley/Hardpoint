extends Control

const _MAP_OPTIONS: Array = [
	{"name": "Math Temple", "path": "res://resources/maps/MathTemple.tres"},
	{"name": "Badlands",    "path": "res://resources/maps/Badlands.tres"},
	{"name": "Sydney",      "path": "res://resources/maps/City.tres"},
	{"name": "Redwood Forest", "path": "res://resources/maps/Forest.tres"},
	{"name": "Giza", "path": "res://resources/maps/Giza.tres"},
	{"name": "Swamp", "path": "res://resources/maps/Swamp.tres"},
	{"name": "Factory", "path": "res://resources/maps/Factory.tres"},
	{"name": "Corvette", "path": "res://resources/maps/Corvette.tres"},
	{"name": "Glacier", "path": "res://resources/maps/Glacier.tres"},  # T459 / T460
	{"name": "Caldera", "path": "res://resources/maps/Caldera.tres"},
]

# T434: game modes, [mode string, menu label] -- the lobby and the single-player picker
const MODES: Array = [["beacons", "BEACONS"], ["rush", "BEACON RUSH"], ["deathmatch", "DEATH MATCH"]]

static func mode_index(mode: String) -> int:
	for i in MODES.size():
		if MODES[i][0] == mode:
			return i
	return 0

const ROSTER: Array = [
	"res://resources/mechs/Slip.tres",
	"res://resources/mechs/Cesh.tres",
	"res://resources/mechs/Swift.tres",
	"res://resources/mechs/Seeker.tres",
	"res://resources/mechs/Hornet.tres",
	"res://resources/mechs/Hippogriff.tres",
	"res://resources/mechs/Pegasus.tres",
	"res://resources/mechs/Kestrel.tres",
	"res://resources/mechs/Heron.tres",
	"res://resources/mechs/Everest.tres",
	"res://resources/mechs/Vesuvius.tres",
	"res://resources/mechs/Taurus.tres",
	"res://resources/mechs/Denali.tres",
	"res://resources/mechs/Kanchenjunga.tres",
]

# T391: the one weapon list (the hangar reads this too): `name` = short label (HUD, lobby, bot kits),
# `long` = the hangar's label. Order within a slot size = the hangar's cycle order.
const WEAPON_CATALOG: Array = [
	{"name": "RIFLE LT",      "path": "res://scenes/weapons/RifleLight.tscn",           "long": "RIFLE LIGHT", "slot_size": 0},
	{"name": "SNIPER LT",     "path": "res://scenes/weapons/SniperLight.tscn",          "long": "SNIPER LIGHT", "slot_size": 0},
	{"name": "MG LT",         "path": "res://scenes/weapons/MachineGunLight.tscn",      "long": "MACHINE GUN LIGHT", "slot_size": 0},
	{"name": "SHOTGUN LT",    "path": "res://scenes/weapons/ShotgunLight.tscn",         "long": "SHOTGUN LIGHT", "slot_size": 0},
	{"name": "MISSILE LT",    "path": "res://scenes/weapons/MissileLauncherLight.tscn", "long": "MISSILE LAUNCHER LT", "slot_size": 0},
	{"name": "ROCKET LT",     "path": "res://scenes/weapons/RocketLauncherLight.tscn",  "long": "ROCKET LAUNCHER LT", "slot_size": 0},
	{"name": "LASER LT",      "path": "res://scenes/weapons/LaserCannonLight.tscn",     "long": "LASER CANNON LT", "slot_size": 0},
	{"name": "ARC LT",        "path": "res://scenes/weapons/ArcWeaponLight.tscn",       "long": "ARC WEAPON LT", "slot_size": 0},
	{"name": "INFERNO LT",    "path": "res://scenes/weapons/FlamerLight.tscn",          "long": "INFERNO LIGHT", "slot_size": 0},  # T457
	{"name": "RIFLE HV",      "path": "res://scenes/weapons/RifleHeavy.tscn",           "long": "RIFLE HEAVY", "slot_size": 1},
	{"name": "SNIPER HV",     "path": "res://scenes/weapons/SniperHeavy.tscn",          "long": "SNIPER HEAVY", "slot_size": 1},
	{"name": "MG HV",         "path": "res://scenes/weapons/MachineGunHeavy.tscn",     "long": "MACHINE GUN HEAVY", "slot_size": 1},
	{"name": "SHOTGUN HV",    "path": "res://scenes/weapons/ShotgunHeavy.tscn",        "long": "SHOTGUN HEAVY", "slot_size": 1},
	{"name": "MISSILE HV",    "path": "res://scenes/weapons/MissileLauncherHeavy.tscn","long": "MISSILE LAUNCHER HV", "slot_size": 1},
	{"name": "LASER HV",      "path": "res://scenes/weapons/LaserCannonHeavy.tscn",    "long": "LASER CANNON HV", "slot_size": 1},
	{"name": "ARC HV",        "path": "res://scenes/weapons/ArcWeaponHeavy.tscn",      "long": "ARC WEAPON HV", "slot_size": 1},
	{"name": "MORTAR HV",     "path": "res://scenes/weapons/MortarHeavy.tscn",         "long": "MORTAR HEAVY", "slot_size": 1},  # T458
	{"name": "INFERNO HV",    "path": "res://scenes/weapons/FlamerHeavy.tscn",         "long": "INFERNO HEAVY", "slot_size": 1},  # T457
	{"name": "ORBITAL HV",    "path": "res://scenes/weapons/OrbitalStrikeHeavy.tscn",  "long": "ORBITAL STRIKE HV", "slot_size": 1},  # T522: replaced AERIAL HV
	{"name": "PATIENCE HV",   "path": "res://scenes/weapons/PatienceHeavy.tscn",        "long": "PATIENCE HV", "slot_size": 1},
]

@onready var _peer_list: VBoxContainer = $PeerList
@onready var _host_controls: VBoxContainer = $HostControls
@onready var _bot_fill_check: CheckBox = $HostControls/BotFillRow/BotFillCheck
@onready var _mode_option: OptionButton = $HostControls/BotFillRow/ModeOption  # T285/T434
@onready var _team_size_spin: SpinBox = $HostControls/TeamSizeRow/TeamSizeSpin
@onready var _map_option: OptionButton = $HostControls/MapRow/MapOption
@onready var _start_button: Button = $StartButton
@onready var _status_label: Label = $StatusLabel
@onready var _ready_btn: Button = $ReadyBtn

func _ready() -> void:
	Game.set_mouse_captured(false)
	Game.lobby_updated.connect(_on_lobby_updated)
	Game.mp_peer_connected.connect(_on_peer_connected)
	Game.mp_peer_disconnected.connect(_on_peer_disconnected)

	_setup_map_option()
	for m in MODES:  # T434: a menu (was the T285 death match checkbox)
		_mode_option.add_item(m[1])
	_mode_option.item_selected.connect(func(i: int) -> void:
		Game.mp_lobby["mode"] = MODES[i][0]
		Game.broadcast_lobby())

	# B44: Lobby also loads on the V40 return after a match -- the match is over, and
	# the connected peers must NOT be wiped (only a fresh host session starts empty).
	Game.mp_active_match["roster"] = []
	if multiplayer.is_server() and not Game.mp_lobby["peers"].is_empty():
		# B62: the match just changed everyone's ELO/level; the lobby copy (match stats'
		# pre_elo, peer list) was from join time. Refresh own entry, re-ask every client.
		var me: Dictionary = Game.mp_lobby["peers"].get(multiplayer.get_unique_id(), {})
		me["elo"] = Game.profile.get("elo", 1000)
		me["level"] = Game.profile.get("level", 1)
		Game._rpc_request_meta.rpc()
		Game.broadcast_lobby()
	elif multiplayer.is_server() and Game.dedicated:
		pass  # T204: Game.start_dedicated set the lobby up; the server is not a player
	elif multiplayer.is_server():
		Game.mp_lobby = {
			"peers":      {},
			"bot_fill":   true,
			"team_size":  Game.loadout.get("team_size", 1),
			"map_path":   "res://resources/maps/MathTemple.tres",
			"mode":       "beacons",
			"match_seed": 0,
		}
		var my_id := multiplayer.get_unique_id()
		Game.mp_lobby["peers"][my_id] = _local_peer_meta()
		Game.broadcast_lobby()
	else:
		# Auto-send current squad so server has it immediately.
		Game._rpc_set_squad.rpc_id(1, _build_squad_data())

	_build_hangar_pick()  # T477
	_build_team_pick()  # T476
	_update_host_controls_visibility()
	_rebuild_peer_list()
	_sync_host_controls_to_lobby()
	_update_start_button()
	_update_ready_btn()

# T477 (HUMAN_FOUND 2026-11-18, with T467: "Team selection, hangar selection, etc"): a HANGAR menu by
# READY UP brings one of the hangar's saved squads (T177 presets) without leaving the lobby. It becomes
# the hangar's squad too; the server gets it the usual way (_rpc_set_squad, cleaned there), the host's
# straight into its own lobby entry.
var _hangar_opt: OptionButton = null

func _build_hangar_pick() -> void:
	var names: Array = (Game.loadout.get("presets", {}) as Dictionary).keys()
	names.sort()
	_hangar_opt = OptionButton.new()
	_hangar_opt.name = "HangarPick"
	_hangar_opt.add_theme_font_size_override("font_size", 13)
	_hangar_opt.add_item("HANGAR: CURRENT")
	for n in names:
		_hangar_opt.add_item("HANGAR: " + String(n).to_upper())
		_hangar_opt.set_item_metadata(_hangar_opt.item_count - 1, n)
	_hangar_opt.disabled = names.is_empty()
	_hangar_opt.position = Vector2(275.0, 183.0)
	_hangar_opt.size = Vector2(160.0, 27.0)  # T476: TEAM takes the rest of the row
	_hangar_opt.item_selected.connect(_on_hangar_picked)
	add_child(_hangar_opt)

# T476 (HUMAN_FOUND 2026-11-18/19: "Team selection" / "Multiplayer should allow picking teams. Also named
# Elite bots, as well as specific difficulty for each slot."): a TEAM menu (AUTO / A / B) for every
# player; the host gets BOT SLOTS -- a difficulty per bot slot of each side and, on Elite, a named
# Elite (BotNames.ELITE_KIT) -- kept in Game.mp_lobby["bot_setup"] for _build_roster.
const _DIFFS := ["DEFAULT", "EASY", "NORMAL", "MEDIUM", "HARD", "ELITE"]  # index - 1 = difficulty (-1 = setting)
var _team_opt: OptionButton = null
var _bots_panel: PanelContainer = null

func _build_team_pick() -> void:
	_team_opt = OptionButton.new()
	_team_opt.name = "TeamPick"
	_team_opt.add_theme_font_size_override("font_size", 13)
	for t in ["TEAM: AUTO", "TEAM: A", "TEAM: B"]:
		_team_opt.add_item(t)
	var mine: Dictionary = Game.mp_lobby.get("peers", {}).get(multiplayer.get_unique_id(), {})
	_team_opt.select(clampi(int(mine.get("team_pref", -1)), -1, 1) + 1)
	_team_opt.position = Vector2(440.0, 183.0)
	_team_opt.size = Vector2(90.0, 27.0)
	_team_opt.item_selected.connect(_on_team_picked)
	add_child(_team_opt)
	if multiplayer.is_server():
		var b := Button.new()
		b.name = "BotSlotsBtn"
		b.text = "BOT SLOTS"
		b.add_theme_font_size_override("font_size", 12)
		$HostControls/TeamSizeRow.add_child(b)
		$HostControls/TeamSizeRow.move_child(b, 1)
		b.pressed.connect(_open_bot_slots)
		# T507 (user: "Should be able to pick different numbers of bots per side in multiplayer."): with
		# Bot Fill off, the host sets each side's bot count (as the SP picker's ALLY / ENEMY BOTS, T251)
		for t in 2:
			var sp := SpinBox.new()
			sp.name = "BotsSpin%s" % "AB"[t]
			sp.prefix = "BOTS %s" % "AB"[t]
			sp.min_value = 0
			sp.max_value = 5
			sp.get_line_edit().add_theme_font_size_override("font_size", 13)
			sp.get_line_edit().expand_to_text_length = true
			sp.value_changed.connect(func(_v: float) -> void: _on_bot_counts_changed())
			$HostControls/BotFillRow.add_child(sp)
			$HostControls/BotFillRow.move_child(sp, 2 + t)
			_bots_spin.append(sp)
		_sync_host_controls_to_lobby()

func _on_team_picked(i: int) -> void:
	SoundManager.play_sfx_2d("ui_click")
	if multiplayer.is_server():
		Game._apply_team(multiplayer.get_unique_id(), i - 1)
		_rebuild_peer_list()
	else:
		Game._rpc_set_team.rpc_id(1, i - 1)

var _bots_spin: Array = []  # T507: [BOTS A, BOTS B], host only, shown while Bot Fill is off

func _on_bot_counts_changed() -> void:
	Game.mp_lobby["bot_counts"] = [int(_bots_spin[0].value), int(_bots_spin[1].value)]
	Game.broadcast_lobby()
	_update_start_button()

func _bot_setup() -> Array:
	var s = Game.mp_lobby.get("bot_setup")
	if not (s is Array and (s as Array).size() == 2):
		s = [[], []]
		Game.mp_lobby["bot_setup"] = s
	return s

func _open_bot_slots() -> void:
	SoundManager.play_sfx_2d("ui_click")
	if _bots_panel != null:
		_bots_panel.queue_free()
	_bots_panel = PanelContainer.new()
	_bots_panel.name = "BotSlotsPanel"
	_bots_panel.position = Vector2(110, 40)
	_bots_panel.size = Vector2(420, 270)
	var bg := StyleBoxFlat.new()  # opaque: the lobby mustn't show through the rows
	bg.bg_color = Color(0.07, 0.08, 0.09, 1.0)
	bg.border_color = Color(0.45, 0.5, 0.55, 1.0)
	bg.set_border_width_all(1)
	bg.set_content_margin_all(6)
	_bots_panel.add_theme_stylebox_override("panel", bg)
	var box := VBoxContainer.new()
	_bots_panel.add_child(box)
	var head := Label.new()
	head.text = "BOT SLOTS (filled after the players, per side)"
	head.add_theme_font_size_override("font_size", 13)
	box.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 200)
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	scroll.add_child(grid)
	var setup := _bot_setup()
	var ts: int = clampi(int(Game.mp_lobby.get("team_size", 1)), 1, 6)
	var counts = Game.mp_lobby.get("bot_counts")  # T507: a row per bot the side will actually get
	var rows: Array = [ts, ts] if not (counts is Array and (counts as Array).size() == 2) \
		else [clampi(int(counts[0]), 0, 5), clampi(int(counts[1]), 0, 5)]
	var elites: Array = BotNames.ELITE_KIT.keys()
	elites.sort()
	for team in 2:
		while (setup[team] as Array).size() < rows[team]:
			(setup[team] as Array).append({"d": -1, "e": ""})
		for k in rows[team]:
			_bot_slot_row(grid, setup[team][k], team, k, elites)
	var close := Button.new()
	close.text = "DONE"
	close.pressed.connect(func() -> void:
		_bots_panel.queue_free()
		_bots_panel = null)
	box.add_child(close)
	add_child(_bots_panel)

func _bot_slot_row(grid: GridContainer, slot: Dictionary, team: int, k: int, elites: Array) -> void:
	var lbl := Label.new()
	lbl.text = "%s%d" % ["AB"[team], k + 1]
	lbl.add_theme_font_size_override("font_size", 12)
	grid.add_child(lbl)
	var dopt := OptionButton.new()
	dopt.name = "Diff_%d_%d" % [team, k]
	dopt.add_theme_font_size_override("font_size", 12)
	for d in _DIFFS:
		dopt.add_item(d)
	dopt.select(clampi(int(slot.get("d", -1)), -1, 4) + 1)
	grid.add_child(dopt)
	var eopt := OptionButton.new()
	eopt.name = "Elite_%d_%d" % [team, k]
	eopt.add_theme_font_size_override("font_size", 12)
	eopt.add_item("ANY PILOT")
	for n in elites:
		eopt.add_item(String(n).to_upper())
		eopt.set_item_metadata(eopt.item_count - 1, n)
		if slot.get("e") is String and n == slot["e"]:
			eopt.select(eopt.item_count - 1)
	eopt.disabled = int(slot.get("d", -1)) != 4
	grid.add_child(eopt)
	dopt.item_selected.connect(func(i: int) -> void:
		slot["d"] = i - 1
		eopt.disabled = i - 1 != 4
		if i - 1 != 4:
			slot["e"] = ""
			eopt.select(0)
		Game.broadcast_lobby())
	eopt.item_selected.connect(func(i: int) -> void:
		var n = eopt.get_item_metadata(i)
		slot["e"] = n if n is String else ""
		Game.broadcast_lobby())

func _on_hangar_picked(i: int) -> void:
	var pname = _hangar_opt.get_item_metadata(i)
	if not pname is String or not Game.load_preset(pname):
		return
	SoundManager.play_sfx_2d("ui_click")
	Game.save_loadout()
	if multiplayer.is_server():
		var me := multiplayer.get_unique_id()
		if Game.mp_lobby["peers"].has(me):
			Game.mp_lobby["peers"][me]["squad"] = _build_squad_data()
			Game.broadcast_lobby()
		_rebuild_peer_list()
	else:
		Game._rpc_set_squad.rpc_id(1, _build_squad_data())

# ---- Peer meta helpers ----

func _mech_short_name(path: String) -> String:
	return path.get_file().get_basename()

static func _build_squad_data() -> Array:
	var squad_paths: Array = Game.loadout.get("squad", [])
	var result: Array = []
	for i in squad_paths.size():
		result.append({"mech": squad_paths[i], "weapons": Game.slot_weapons(i)})  # T345: per slot
	while result.size() < 5:
		var fallback: String = ROSTER[0] if ROSTER.size() > 0 else ""
		result.append({"mech": fallback, "weapons": []})
	return result

static func _local_peer_meta() -> Dictionary:
	return {
		"pilot_name": Game.profile.get("pilot_name", "Pilot"),
		"elo":        Game.profile.get("elo", 1000),
		"level":      Game.profile.get("level", 1),
		"skills":     Game.profile.get("skills", {}),  # T332
		"squad":      _build_squad_data(),
		"ready":      false,
	}

# ---- Peer list ----

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	# Game._on_mp_peer_connected already added placeholder + broadcast.
	# Just ensure the entry exists (guard for future ordering changes).
	if not Game.mp_lobby["peers"].has(id):
		Game.mp_lobby["peers"][id] = {
			"pilot_name": "Peer %d" % id,
			"elo": 1000, "level": 1, "squad": [], "ready": false,
		}
		Game.broadcast_lobby()

func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	Game.mp_lobby["peers"].erase(id)
	Game.broadcast_lobby()

func _on_lobby_updated() -> void:
	_idle_until = Time.get_ticks_msec() + 1000 * int(Game.mp_lobby.get("idle_wait", 0))
	_update_status()
	_rebuild_peer_list()
	_sync_host_controls_to_lobby()
	_update_start_button()
	_update_ready_btn()

# T204 / T400: the dedicated server's start line. While it waits on unready pilots it shows
# how long they have left before the match starts without them.
var _idle_until := 0
func _update_status() -> void:
	var left := int(ceil((_idle_until - Time.get_ticks_msec()) / 1000.0))
	var me: Dictionary = Game.mp_lobby.get("peers", {}).get(multiplayer.get_unique_id(), {})
	if Game.mp_lobby.get("starting", false):
		_status_label.text = "MATCH STARTING..."
	elif int(Game.mp_lobby.get("idle_wait", 0)) > 0 and left > 0:
		_status_label.text = "WAITING FOR ALL PILOTS - STARTING WITHOUT THE REST IN %d:%02d" % [left / 60, left % 60]
		get_tree().create_timer(1.0).timeout.connect(_update_status)
	elif me.get("sitting_out", false):
		_status_label.text = "YOU ARE SITTING OUT - PRESS READY TO PLAY"
	else:
		_status_label.text = ""

func _rebuild_peer_list() -> void:
	for child in _peer_list.get_children():
		child.queue_free()
	var peers: Dictionary = Game.mp_lobby.get("peers", {})
	for id in peers:
		var entry: Dictionary = peers[id]
		var row := HBoxContainer.new()

		var name_lbl := Label.new()
		name_lbl.text = entry.get("pilot_name", "?")
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 13)

		var elo_lbl := Label.new()
		elo_lbl.text = "ELO %d" % entry.get("elo", 0)
		elo_lbl.custom_minimum_size.x = 75
		elo_lbl.add_theme_font_size_override("font_size", 13)

		var squad_lbl := Label.new()
		var sq: Array = entry.get("squad", [])
		if sq.is_empty():
			squad_lbl.text = "[no squad]"
		else:
			var names: Array = []
			for e in sq:
				names.append(_mech_short_name(str(e.get("mech", ""))))
			squad_lbl.text = ", ".join(names)
		squad_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		squad_lbl.add_theme_font_size_override("font_size", 11)
		squad_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))

		var ready_lbl := Label.new()
		ready_lbl.text = "[RDY]" if entry.get("ready", false) else "[   ]"
		var pref: int = int(entry.get("team_pref", -1)) if typeof(entry.get("team_pref", -1)) == TYPE_INT else -1
		if pref >= 0:  # T476: the player's team wish
			name_lbl.text += "  [%s]" % "AB"[pref]
		ready_lbl.custom_minimum_size.x = 45
		ready_lbl.add_theme_font_size_override("font_size", 13)

		row.add_child(name_lbl)
		row.add_child(elo_lbl)
		row.add_child(squad_lbl)
		row.add_child(ready_lbl)
		_peer_list.add_child(row)

# ---- Host controls ----

func _setup_map_option() -> void:
	_map_option.clear()
	for i in _MAP_OPTIONS.size():
		_map_option.add_item(_MAP_OPTIONS[i]["name"], i)

func _update_host_controls_visibility() -> void:
	_host_controls.visible = multiplayer.is_server()
	_start_button.visible = multiplayer.is_server()

func _sync_host_controls_to_lobby() -> void:
	if not multiplayer.is_server():
		return
	_bot_fill_check.set_pressed_no_signal(Game.mp_lobby.get("bot_fill", true))
	var counts = Game.mp_lobby.get("bot_counts")
	for t in _bots_spin.size():
		_bots_spin[t].visible = not Game.mp_lobby.get("bot_fill", true)
		_bots_spin[t].set_value_no_signal(int(counts[t]) if counts is Array and (counts as Array).size() == 2 else 0)
	_mode_option.select(mode_index(Game.mp_lobby.get("mode", "beacons")))
	_team_size_spin.set_value_no_signal(Game.mp_lobby.get("team_size", 1))
	var map_path: String = Game.mp_lobby.get("map_path", "")
	for i in _MAP_OPTIONS.size():
		if _MAP_OPTIONS[i]["path"] == map_path:
			_map_option.select(i)
			break

func _update_start_button() -> void:
	if not multiplayer.is_server():
		return
	var bot_fill: bool = Game.mp_lobby.get("bot_fill", true)
	var peers: Dictionary = Game.mp_lobby.get("peers", {})
	var counts = Game.mp_lobby.get("bot_counts")  # T507: bots set per side = someone to play against
	if bot_fill or (counts is Array and (counts as Array).size() == 2 and int(counts[0]) + int(counts[1]) > 0):
		_start_button.disabled = peers.is_empty()
	else:
		var all_ready := peers.size() >= 2
		for id in peers:
			if not peers[id].get("ready", false):
				all_ready = false
				break
		_start_button.disabled = not all_ready

func _on_bot_fill_toggled(pressed: bool) -> void:
	Game.mp_lobby["bot_fill"] = pressed
	if pressed:  # T507: fill to team size; off = the BOTS A / B counts (0 / 0 = players only, as before)
		Game.mp_lobby.erase("bot_counts")
	for sp in _bots_spin:
		sp.visible = not pressed
	if not pressed and not _bots_spin.is_empty():
		Game.mp_lobby["bot_counts"] = [int(_bots_spin[0].value), int(_bots_spin[1].value)]
	Game.broadcast_lobby()
	_update_start_button()

func _on_team_size_changed(value: float) -> void:
	var sz := int(value)
	Game.mp_lobby["team_size"] = sz
	Game.loadout["team_size"] = sz
	Game.broadcast_lobby()

func _on_map_selected(index: int) -> void:
	if index >= 0 and index < _MAP_OPTIONS.size():
		Game.mp_lobby["map_path"] = _MAP_OPTIONS[index]["path"]
		Game.broadcast_lobby()

# ---- Squad picker ----

func _update_ready_btn() -> void:
	var my_id := multiplayer.get_unique_id()
	var my_entry: Dictionary = Game.mp_lobby.get("peers", {}).get(my_id, {})
	_ready_btn.text = "UNREADY" if my_entry.get("ready", false) else "READY UP"

func _on_ready_btn_pressed() -> void:
	var my_id := multiplayer.get_unique_id()
	var my_entry: Dictionary = Game.mp_lobby.get("peers", {}).get(my_id, {})
	var new_ready: bool = not my_entry.get("ready", false)
	if multiplayer.is_server():
		Game._apply_ready(my_id, new_ready)
	else:
		Game._rpc_set_ready.rpc_id(1, new_ready)

func _on_start_pressed() -> void:
	var roster := _build_roster()
	var match_seed := randi()
	Game.mp_lobby["match_seed"] = match_seed
	var map_path: String = Game.mp_lobby.get("map_path", "res://resources/maps/MathTemple.tres")
	Game._rpc_match_start.rpc(map_path, roster, match_seed, Game.mp_lobby.get("mode", "beacons"))

# T184: static -- Game.setup_sp_match builds the SP roster with these too.
const BotNames := preload("res://scripts/BotNames.gd")

static func _build_roster() -> Array:
	var roster: Array = []
	var slot_idx := 0
	var bot_id := 0
	var team_size: int = clampi(Game.mp_lobby.get("team_size", 1), 1, 6)

	# Deterministic peer ordering by peer_id.
	var peer_ids: Array = Game.mp_lobby.get("peers", {}).keys().filter(func(p) -> bool:
		return not Game.mp_lobby["peers"][p].get("sitting_out", false))  # T400: never readied up -> watches this one
	peer_ids.sort()

	var team_counts := [0, 0]
	# T476: a player's team wish (team_pref 0 / 1) holds while that team has room; AUTO (-1) and the
	# overflow fill whichever side is smaller (ties alternate, as the old i % 2 did)
	var teams := {}
	for pid in peer_ids:
		var pref: int = clampi(int(Game.mp_lobby["peers"][pid].get("team_pref", -1)), -1, 1)
		if pref >= 0 and team_counts[pref] < team_size:
			teams[pid] = pref
			team_counts[pref] += 1
	var alt := 0
	for pid in peer_ids:
		if teams.has(pid):
			continue
		var t: int = 0 if team_counts[0] < team_counts[1] else (1 if team_counts[1] < team_counts[0] else alt)
		alt = 1 - alt
		teams[pid] = t
		team_counts[t] += 1
	team_counts = [0, 0]
	for i in peer_ids.size():
		var pid: int = peer_ids[i]
		var team: int = teams[pid]
		var entry: Dictionary = Game.mp_lobby["peers"][pid]
		var sq: Array = entry.get("squad", [])
		roster.append({
			"slot_idx": slot_idx,
			"peer_id":  pid,
			"team":     team,
			"squad":    sq if not sq.is_empty() else _default_bot_squad(0),  # T384: none accepted yet
			"bot_id":   -1,
		})
		slot_idx += 1
		team_counts[team] += 1

	# T251 (SP) / T507 (MP, Bot Fill off): exact bot counts per side ([A, B]; 0 = none), at most 6 a
	# side; else Bot Fill pads each side to team_size (V29: bot_id used for RNG seed). Either way the
	# host's per-slot setup (T476) applies.
	var counts = Game.mp_lobby.get("bot_counts", null)
	var exact: bool = counts is Array and counts.size() == 2
	if exact or Game.mp_lobby.get("bot_fill", true):
		var setup: Array = Game.mp_lobby.get("bot_setup", [[], []]) if Game.mp_lobby.get("bot_setup") is Array else [[], []]
		for team in range(2):
			var k := 0
			var target: int = mini(team_counts[team] + clampi(int(counts[team]), 0, 5), 6) if exact else team_size
			while team_counts[team] < target:
				var e := {
					"slot_idx": slot_idx,
					"peer_id":  0,
					"team":     team,
					"squad":    _default_bot_squad(bot_id),
					"bot_id":   bot_id,
				}
				# T476 ("named Elite bots, as well as specific difficulty for each slot"): the host's setup
				var ts: Array = setup[team] if team < setup.size() and setup[team] is Array else []
				if k < ts.size() and ts[k] is Dictionary:
					var d: int = Game.clean_int(ts[k].get("d", -1), -1, 4, -1)
					if d >= 0:
						e["difficulty"] = d
					if ts[k].get("e") is String and BotNames.ELITE_KIT.has(ts[k]["e"]):
						e["elite"] = ts[k]["e"]
				roster.append(e)
				k += 1
				slot_idx += 1
				team_counts[team] += 1
				bot_id += 1

	# T325: callsigns ride the roster to every peer -- players keep theirs, bots draw from the deck.
	# T332: so do pilot skills -- players' (sanitized), ELITE bots' named builds (T335), others none.
	var taken: Array = []
	for e in roster:
		if int(e["peer_id"]) != 0:
			var meta: Dictionary = Game.mp_lobby["peers"].get(e["peer_id"], {})
			e["name"] = str(meta.get("pilot_name", "Pilot"))
			e["skills"] = Game.sanitize_skills(meta.get("skills", {}), int(meta.get("level", 1)))
			taken.append(e["name"])
	for e in roster:  # T476: the host's named Elites first, so the deck can't hand their names out
		if int(e["peer_id"]) == 0 and e.has("elite") and not e["elite"] in taken:
			taken.append(e["elite"])
	for e in roster:
		if int(e["peer_id"]) == 0:
			var e_elite: bool = int(e.get("difficulty", Game.settings.get("bot_difficulty", 1))) >= 4
			if e.has("elite"):
				e["name"] = e["elite"]
				e["difficulty"] = 4  # a named Elite flies as an Elite
				e_elite = true
			else:
				e["name"] = BotNames.next_name(taken, e_elite)
			e["skills"] = (BotNames.ELITE.get(e["name"], {}) as Dictionary).duplicate()
			if e_elite and BotNames.ELITE_KIT.has(e["name"]):  # T350: the pilot's own hangar and style
				var kit: Dictionary = BotNames.ELITE_KIT[e["name"]]  # T377/T434: a hangar per mode
				var key: String = {"deathmatch": "squad_dm", "rush": "squad_rush"}.get(Game.mp_lobby.get("mode", "beacons"), "squad")
				e["squad"] = kit_squad(kit.get(key, kit["squad"]))
				e["personality"] = (BotNames.ELITE_KIT[e["name"]]["personality"] as Dictionary).duplicate()
			if not e["name"] in taken:
				taken.append(e["name"])
	return roster

## T354 (HUMAN_FOUND 2026-11-08: "remove Cesh from bot rosters at lower difficulties"): Cesh's
## camouflage only makes sense with Hard / Elite's stealth tactics (T295); Easy..Medium bots use
## no abilities, so they get the rest of the roster.
## T368 (user on T357: "Medium should get Cesh. Actually, bots with active abilities should start at
## Medium for all mechs."): Medium has the tactics (abilities) since T357, so Cesh joins from Medium.
static func bot_roster() -> Array:
	if int(Game.settings.get("bot_difficulty", 1)) >= 2:
		return ROSTER
	return ROSTER.filter(func(p) -> bool: return not String(p).ends_with("/Cesh.tres"))

## T350: [[mech name, weapon family], ...] -> squad entries; a slot size the family lacks gets the rifle.
static func kit_squad(kit: Array) -> Array:
	var out: Array = []
	for k in kit:
		var md: Resource = load("res://resources/mechs/%s.tres" % k[0])
		var weapons: Array = []
		for sl in md.weapon_slots:
			var pick := ""
			var rifle := ""
			for w in WEAPON_CATALOG:
				if int(w["slot_size"]) != int(sl.slot_size):
					continue
				if String(w["name"]).get_slice(" ", 0) == String(k[1]):
					pick = w["path"]
				elif String(w["name"]).begins_with("RIFLE"):
					rifle = w["path"]
			weapons.append(pick if pick != "" else rifle)
		out.append({"mech": md.resource_path, "weapons": weapons})
	return out

## T365 (user 2026-11-09: "Regular difficulties have random mechs, with weapons weighted to make sense
## with the mech. Elites each have a custom roster that makes sense with their abilities" -- Elites:
## T350): a regular bot's 5 squad slots are each a random mech from the difficulty's pool, each with
## a weapon family drawn by BOT_WEAPON_WEIGHTS. `bot_id` is unused now (was: one mech per bot slot).
static func _default_bot_squad(_bot_id: int) -> Array:
	if Game.fixed_bots != "":  # T376: probes
		var kit: Array = []
		for _i in 5:
			kit.append([Game.fixed_bots, "RIFLE"])
		return kit_squad(kit)
	var pool := bot_roster()
	var rng := RandomNumberGenerator.new()
	rng.randomize()  # roster is broadcast, so peers never re-derive it (no determinism needed)
	var result: Array = []
	for _i in 5:
		var mech_path: String = pool[rng.randi() % pool.size()]
		result.append({"mech": mech_path, "weapons": bot_weapon_paths(load(mech_path), rng)})
	return result

## T365: how much each mech suits each weapon family (the user: "weapons weighted to make sense
## with the mech"); a family missing here weighs 1, 0 rules it out. Fast lights snipe or brawl, the
## stealth Cesh ambushes up close, Seeker's single heavy mount carries the big guns, mediums take
## all-rounders by their gimmick (Pegasus jumps in with rifles / shotguns, Kestrel's shield holds a
## laser on target, Hippogriff's three mounts fire missiles), heavies hose MG and drop strikes.
const BOT_WEAPON_WEIGHTS := {
	"Slip":       {"SNIPER": 4, "RIFLE": 3, "SHOTGUN": 2, "MG": 2},
	"Cesh":       {"SHOTGUN": 4, "MG": 3, "ARC": 2, "ROCKET": 2, "SNIPER": 0},
	"Seeker":     {"SNIPER": 4, "ORBITAL": 3, "PATIENCE": 3, "RIFLE": 2, "SHOTGUN": 0},
	"Hornet":     {"MG": 3, "MISSILE": 3, "RIFLE": 2, "SHOTGUN": 2, "LASER": 2},
	"Hippogriff": {"MISSILE": 4, "MG": 3, "RIFLE": 2, "LASER": 2},
	"Kestrel":    {"LASER": 4, "RIFLE": 3, "ARC": 2, "MG": 2},
	"Pegasus":    {"RIFLE": 4, "SHOTGUN": 3, "LASER": 2, "MG": 2},
	"Everest":    {"MG": 4, "LASER": 3, "ORBITAL": 2, "PATIENCE": 2, "RIFLE": 2, "MORTAR": 2},
	"Vesuvius":   {"MG": 3, "MISSILE": 3, "ORBITAL": 3, "PATIENCE": 2, "RIFLE": 2, "LASER": 2, "MORTAR": 3},
	"Taurus":     {"SHOTGUN": 4, "MG": 3, "INFERNO": 2, "RIFLE": 2, "SNIPER": 0},  # T363: rams in, fights up close (T457 flamer)
	"Denali":     {"RIFLE": 4, "LASER": 3, "MG": 2, "PATIENCE": 2, "MORTAR": 2},  # T430: plants (ANCHOR) and trades shots at range
	"Kanchenjunga": {"SHOTGUN": 4, "MG": 4, "INFERNO": 3, "ARC": 2, "RIFLE": 1},  # T456: walks in and stomps (T457 flamer)
	"Heron":      {"RIFLE": 4, "LASER": 3, "MG": 2, "MISSILE": 2},  # T455: medic, stays with the squad at mid range
	"Swift":      {"MG": 4, "SHOTGUN": 3, "RIFLE": 2, "ARC": 2, "INFERNO": 2},  # T454: dashes in close
}

## T171: random bot loadout -- ONE weapon family (RIFLE, MG, ...) in every slot of
## `mech_def`, sized per slot; mixed loadouts fight worse (ranges, lead, lock all differ).
## Only families that exist in every slot size the mech has (ORBITAL/PATIENCE: heavy only).
## T365: the family is drawn by the mech's BOT_WEAPON_WEIGHTS, not uniformly.
static func bot_weapon_paths(mech_def: Resource, rng: RandomNumberGenerator) -> Array:
	var fams := {}  # "RIFLE" -> {slot_size: path}
	for w in WEAPON_CATALOG:
		var f: String = w["name"].get_slice(" ", 0)
		if not fams.has(f):
			fams[f] = {}
		fams[f][w["slot_size"]] = w["path"]
	var fits: Array = fams.keys().filter(func(f: String) -> bool:
		return mech_def.weapon_slots.all(func(sl) -> bool: return fams[f].has(sl.slot_size)))
	if fits.is_empty():
		return mech_def.weapon_slots.map(func(_sl) -> String: return "")
	var weights: Dictionary = BOT_WEAPON_WEIGHTS.get(String(mech_def.display_name), {})
	var total := 0.0
	for f in fits:
		total += float(weights.get(f, 1))
	var pick: String = fits[rng.randi() % fits.size()]  # all weights 0: fall back to uniform
	if total > 0.0:
		var roll := rng.randf() * total
		for f in fits:
			roll -= float(weights.get(f, 1))
			if roll < 0.0:
				pick = f
				break
	var fam: Dictionary = fams[pick]
	return mech_def.weapon_slots.map(func(sl) -> String: return fam[sl.slot_size])

func _on_back_pressed() -> void:
	Game.disconnect_mp()
	get_tree().change_scene_to_file("res://scenes/ui/Hangar.tscn")  # T176: squads are set up there
