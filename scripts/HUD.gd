extends CanvasLayer

@onready var health_bar_bg: ColorRect = $HealthBarBG
@onready var health_bar_fg: ColorRect = $HealthBarFG
@onready var score_label: Label = $ScoreLabel
@onready var crosshair: Control = $Crosshair
@onready var damage_flash: ColorRect = $DamageFlash
@onready var result_label: Label = $ResultLabel
@onready var restart_label: Label = $RestartLabel
@onready var shield_bar_bg: ColorRect = $ShieldBarBG
@onready var shield_bar_fg: ColorRect = $ShieldBarFG
@onready var bot_health_bar: ColorRect = $BotHealthBar
@onready var weapon_hud: Control = $WeaponHUD
@onready var eligible_indicator: Control = $EligibleIndicator
@onready var ability_label: Label = $AbilityLabel

# T236 (HUMAN_FOUND_ISSUES 2026-11-04: bars "obstruct vision too much"): 32 x 6 -> 20 x 3 px
const BOT_BAR_FULL_WIDTH := 20.0
const BOT_BAR_HEIGHT     := 3.0
const BOT_BAR_HEAD_OFFSET := Vector3(0.0, 3.5, 0.0)

var _damage_alpha: float = 0.0

var _match: Node = null
var _player_mech: Node = null
var _player_team: int = 0
var _bot_mechs: Array = []
var _bot_health_bars: Array = []   # red foreground health rects
var _bot_bg_bars: Array = []       # black background rects (constant full width)
var _ally_mechs: Array = []
var _ally_health_bars: Array = []  # green foreground health rects
var _ally_bg_bars: Array = []      # black background rects
var _name_tags: Array = []         # T325: [bot tags..., ally tags...] parallel to the bars
var _feed: RichTextLabel = null    # T324: kill feed + chat stub under the ability marker
var _feed_lines: Array = []        # [bbcode, age s]
const FEED_LINES := 4
const FEED_LIFE_S := 6.0
var _spectate_label: Label = null

var _beacons: Array = []
var _beacon_dots: Array = []       # BeaconDot per beacon, top-center ownership circles
var _score_bars: Array = []        # [{bg, fg, max_w}] team 0 and 1 score bars
var _team_count_labels: Array = [] # [team0_label, team1_label] alive counters
var _clock_label: Label = null     # T285: death match countdown (top centre, no score bars)

var _original_player_mech: Node = null  # keeps the original ref after spectate switch
var _squad_picker: Control = null

signal squad_slot_selected(slot_idx: int)

func setup(match_node: Node, player_mech: Node, player_team: int) -> void:
	_match = match_node
	_player_mech = player_mech
	_original_player_mech = player_mech
	_player_team = player_team
	weapon_hud.setup(player_mech)
	score_label.visible = false

const MINIMAP_PX := 100.0  # HUD base px (shown 2x at 1280x720); clears the top-centre score bars
var minimap: Control = null  # T202

func setup_minimap(arena: Node, team: int, center: Vector2, half: float,
		outline: PackedVector2Array, beacons: Array) -> void:
	if minimap == null:
		minimap = load("res://scripts/Minimap.gd").new()
		minimap.name = "Minimap"
		minimap.process_mode = Node.PROCESS_MODE_ALWAYS  # the spawn picker runs while SP is paused
		add_child(minimap)
	_minimap_corner()
	minimap.arena = arena
	minimap.local_team = team
	minimap.center = center
	minimap.half = half
	minimap.outline = outline
	minimap.beacons = beacons
	minimap.set_features(arena.get("_map") if arena != null else null)  # T239 (after half: it sizes the filter)

func _minimap_corner() -> void:
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.offset_left = -MINIMAP_PX - 16.0
	minimap.offset_right = -16.0
	minimap.offset_top = 16.0
	minimap.offset_bottom = 16.0 + MINIMAP_PX

# T203: the minimap, full size in the middle, with a numbered button on each of the
# team's spawn points (world positions). Emits spawn_selected(index).
signal spawn_selected(idx: int)
signal spawn_back  # T322: BACK from the spawn picker to the mech picker
var _squad_args: Array = []  # T322: the last squad picker's [squad, slot_used, heading]
const SPAWN_MAP_PX := 280.0
var _spawn_ui: Array = []

func show_spawn_picker(points: Array) -> void:
	hide_spawn_picker()
	if minimap == null:
		return
	minimap.set_anchors_preset(Control.PRESET_CENTER)
	minimap.offset_left = -SPAWN_MAP_PX * 0.5
	minimap.offset_right = SPAWN_MAP_PX * 0.5
	minimap.offset_top = -SPAWN_MAP_PX * 0.5 + 20.0
	minimap.offset_bottom = SPAWN_MAP_PX * 0.5 + 20.0
	minimap.bg_alpha = 0.85
	var head := Label.new()
	head.text = "SELECT SPAWN POINT"
	head.position = Vector2(6, 2)
	minimap.add_child(head)
	_spawn_ui.append(head)
	var sb := StyleBoxFlat.new()
	sb.bg_color = minimap.ALLY
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1)
	sb.set_corner_radius_all(4)
	var sb_hover := sb.duplicate() as StyleBoxFlat
	sb_hover.bg_color = minimap.ALLY.lightened(0.35)
	# T322 (HUMAN_FOUND 2026-11-05: "During a match, the spawnpoint picker should have a back
	# button that goes back to the mech picker")
	if not _squad_args.is_empty():
		var back := Button.new()
		back.name = "SpawnBack"
		back.text = "< BACK"
		back.add_theme_font_size_override("font_size", 12)
		back.position = Vector2(6, SPAWN_MAP_PX - 30.0)
		back.pressed.connect(func() -> void:
			hide_spawn_picker()
			spawn_back.emit()
			show_squad_picker_mp(_squad_args[0], _squad_args[1], _squad_args[2]))
		minimap.add_child(back)
		_spawn_ui.append(back)
	for i in points.size():
		var b := Button.new()
		b.name = "Spawn%d" % i
		b.text = str(i + 1)
		b.size = Vector2(26, 26)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb_hover)
		b.add_theme_stylebox_override("pressed", sb_hover)
		b.position = minimap.to_map(points[i]) - b.size * 0.5
		b.pressed.connect(func() -> void: spawn_selected.emit(i))
		minimap.add_child(b)
		_spawn_ui.append(b)

func hide_spawn_picker() -> void:
	for n in _spawn_ui:
		if is_instance_valid(n):
			n.queue_free()
	_spawn_ui.clear()
	if minimap != null:
		minimap.bg_alpha = 0.55
		_minimap_corner()

func setup_bot_bars(mechs: Array) -> void:
	_clear_name_tags()
	# Free all dynamically created bars from a previous call.
	for bar in _bot_health_bars:
		if is_instance_valid(bar) and bar != bot_health_bar:
			bar.queue_free()
	for bar in _bot_bg_bars:
		if is_instance_valid(bar):
			bar.queue_free()
	_bot_health_bars.clear()
	_bot_bg_bars.clear()
	_bot_mechs = mechs
	for i in mechs.size():
		# Black background - z_index -1 ensures it always renders behind the fg.
		var bg := ColorRect.new()
		bg.color = Color(0.0, 0.0, 0.0, 0.85)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.z_index = -1
		bg.visible = false
		add_child(bg)
		_bot_bg_bars.append(bg)

		# Red foreground health bar.
		if i == 0:
			_bot_health_bars.append(bot_health_bar)
		else:
			var bar := ColorRect.new()
			bar.color = Color(1.0, 0.15, 0.1, 1)
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.visible = false
			add_child(bar)
			_bot_health_bars.append(bar)

func setup_ally_bars(mechs: Array) -> void:
	_clear_name_tags()
	for bar in _ally_health_bars:
		if is_instance_valid(bar):
			bar.queue_free()
	for bar in _ally_bg_bars:
		if is_instance_valid(bar):
			bar.queue_free()
	_ally_health_bars.clear()
	_ally_bg_bars.clear()
	_ally_mechs = mechs
	for _i in mechs.size():
		var bg := ColorRect.new()
		bg.color = Color(0.0, 0.0, 0.0, 0.85)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.z_index = -1
		bg.visible = false
		add_child(bg)
		_ally_bg_bars.append(bg)
		var bar := ColorRect.new()
		bar.color = Color(0.2, 0.85, 0.2, 1.0)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.visible = false
		add_child(bar)
		_ally_health_bars.append(bar)

const _DOT_SIZE   := 18.0
const _DOT_GAP    := 4.0
const _BAR_W      := 120.0
const _BAR_H      := 14.0
const _BAR_Y      := 6.0
const _BAR_GAP    := 8.0   # gap between bar and dot strip

func setup_beacon_bars(beacons: Array) -> void:
	for dot in _beacon_dots:
		if is_instance_valid(dot): dot.queue_free()
	_beacon_dots.clear()
	for entry in _score_bars:
		if is_instance_valid(entry.bg): entry.bg.queue_free()
		if is_instance_valid(entry.fg): entry.fg.queue_free()
	_score_bars.clear()
	# Sort beacons left-to-right by world X so dot positions match spatial layout.
	# Ties (same X column) broken by Z descending (upper map first).
	var sorted := beacons.duplicate()
	sorted.sort_custom(func(a, b):
		if absf(a.position.x - b.position.x) > 0.5:
			return a.position.x < b.position.x
		return a.position.z > b.position.z)
	_beacons = sorted

	var n := sorted.size()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var strip_w: float = float(n) * _DOT_SIZE + float(max(0, n - 1)) * _DOT_GAP
	var strip_x: float = (vp.x - strip_w) * 0.5

	# Beacon dot circles
	var dot_script := load("res://scripts/BeaconDot.gd")
	for i in n:
		var dot: Control = dot_script.new()
		var dx: float = strip_x + float(i) * (_DOT_SIZE + _DOT_GAP)
		dot.offset_left   = dx
		dot.offset_right  = dx + _DOT_SIZE
		dot.offset_top    = _BAR_Y + (_BAR_H - _DOT_SIZE) * 0.5
		dot.offset_bottom = dot.offset_top + _DOT_SIZE
		add_child(dot)
		_beacon_dots.append(dot)

	# Team score bars flanking the dot strip
	var colors: Array = [Color(0.2, 0.5, 1.0), Color(1.0, 0.3, 0.2)]
	for t in 2:
		var bar_left: float
		var bar_right: float
		if t == 0:
			bar_right = strip_x - _BAR_GAP
			bar_left  = bar_right - _BAR_W
		else:
			bar_left  = strip_x + strip_w + _BAR_GAP
			bar_right = bar_left + _BAR_W
		var bg := ColorRect.new()
		bg.color = Color(0.08, 0.08, 0.08, 0.88)
		bg.offset_left   = bar_left
		bg.offset_right  = bar_right
		bg.offset_top    = _BAR_Y
		bg.offset_bottom = _BAR_Y + _BAR_H
		add_child(bg)
		var fg := ColorRect.new()
		fg.color = colors[t]
		fg.offset_left   = bar_left
		fg.offset_right  = bar_right
		fg.offset_top    = _BAR_Y
		fg.offset_bottom = _BAR_Y + _BAR_H
		add_child(fg)
		_score_bars.append({"bg": bg, "fg": fg, "left": bar_left, "right": bar_right, "max_w": _BAR_W})
		if _match != null and _match.get("deathmatch"):  # T285: no score at all
			bg.visible = false
			fg.visible = false
	if _match != null and _match.get("deathmatch") and _clock_label == null:
		_clock_label = Label.new()
		_clock_label.add_theme_font_size_override("font_size", 14)
		_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_clock_label.offset_left = strip_x - 40.0  # the hidden bars leave room for "10:00"
		_clock_label.offset_right = strip_x + 40.0
		_clock_label.offset_top = _BAR_Y - 4.0
		_clock_label.offset_bottom = _BAR_Y + _BAR_H + 4.0
		add_child(_clock_label)

	# Alive-count labels just below each score bar.
	for entry in _team_count_labels:
		if is_instance_valid(entry):
			entry.queue_free()
	_team_count_labels.clear()
	var count_colors: Array = [Color(0.45, 0.75, 1.0), Color(1.0, 0.5, 0.4)]
	for t in 2:
		var bar: Dictionary = _score_bars[t]
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", count_colors[t])
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.offset_left   = bar["left"]
		lbl.offset_right  = bar["right"]
		lbl.offset_top    = _BAR_Y + _BAR_H + 2.0
		lbl.offset_bottom = _BAR_Y + _BAR_H + 16.0
		add_child(lbl)
		_team_count_labels.append(lbl)

# T195: an isolated hit (rifle, sniper, rocket) flashes; hits arriving within STREAM_GAP
# of each other (laser, MG) are one continuous stream that holds a steady tint instead
# (re-flashing every MG hit was a 0.45 -> 0.25 sawtooth flicker). Same-tick hits
# (shotgun pellets) are one hit. Frame time, not the wall clock (headless runs).
const FLASH_A := 0.45
const TINT_A := 0.22
const STREAM_GAP := 0.3
var _since_hit := INF
var _streaming := false
var _last_hit_tick := -1

func show_damage() -> void:
	var tick := Engine.get_physics_frames()
	if tick == _last_hit_tick:
		return
	_last_hit_tick = tick
	_streaming = _since_hit < STREAM_GAP
	_since_hit = 0.0
	if not _streaming:
		_damage_alpha = FLASH_A

func register_hit() -> void:
	crosshair.register_hit()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func start_spectating(mech: Node) -> void:
	_player_mech = mech
	crosshair.visible = false
	weapon_hud.visible = false
	if _spectate_label == null:
		_spectate_label = Label.new()
		_spectate_label.add_theme_font_size_override("font_size", 14)
		_spectate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_spectate_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_spectate_label.offset_top = 12.0
		_spectate_label.offset_left  = -200.0
		_spectate_label.offset_right =  200.0
		_spectate_label.offset_bottom = 30.0
		add_child(_spectate_label)
	var mech_team: int = mech.get("team") if "team" in mech else -1
	var is_ally: bool = mech_team == _player_team
	var tag: String = "ALLY" if is_ally else "ENEMY"
	var col: Color = Color(0.45, 0.80, 1.0) if is_ally else Color(1.0, 0.45, 0.35)
	_spectate_label.text = "SPECTATING %s: %s" % [tag, mech.name.to_upper()]
	_spectate_label.add_theme_color_override("font_color", col)
	_spectate_label.visible = true

func stop_spectating() -> void:
	if _spectate_label != null:
		_spectate_label.visible = false
	crosshair.visible = true
	weapon_hud.visible = true

func show_result_mp(winner_team: int, stats: Array) -> void:
	result_label.visible = false
	crosshair.visible = false
	_build_stats_panel_mp(winner_team, stats)

const RESULT_ROWS_H := 170.0  # ~7 rows visible; the rest scroll (T215)

func _build_stats_panel_mp(winner_team: int, stats: Array) -> void:
	var backdrop := ColorRect.new()
	backdrop.process_mode = Node.PROCESS_MODE_ALWAYS
	backdrop.color = Color(0, 0, 0, 1)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.process_mode = Node.PROCESS_MODE_ALWAYS
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 0)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)
	center.add_child(panel)

	var header := Label.new()
	header.text = "DRAW" if winner_team < 0 else "YOU WIN" if winner_team == _player_team else "YOU LOSE"  # T285
	header.add_theme_font_size_override("font_size", 28)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.modulate = Color(0.9, 0.9, 0.5) if winner_team < 0 else Color(0.2, 1.0, 0.2) if winner_team == _player_team else Color(1.0, 0.3, 0.3)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())

	var col_hdr := HBoxContainer.new()
	for col_text: String in ["PLAYER", "ELO", "DEALT", "TAKEN", "CAPS"]:
		var lbl := Label.new()
		lbl.text = col_text
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col_hdr.add_child(lbl)
	vbox.add_child(col_hdr)
	vbox.add_child(HSeparator.new())
	# T215: the player rows scroll; title, columns and button stay put. A 5v5 table pushed
	# the button below the 360 px screen -- the match looked frozen (SP for good, MP
	# until the 30 s auto-return).
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, RESULT_ROWS_H)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	vbox.add_child(scroll)

	for entry: Dictionary in stats:
		var peer_id: int = entry.get("peer_id", 0)
		var pilot_name: String
		var elo_str: String
		if peer_id == 0:
			pilot_name = "[BOT] " + str(entry.get("name", "")) if str(entry.get("name", "")) != "" else "[BOT]"  # T325
			elo_str = "-"
		else:
			var pdata: Dictionary = Game.mp_lobby["peers"].get(peer_id, {})
			pilot_name = pdata.get("pilot_name", "Peer %d" % peer_id)
			# T168: new rating + change, same math as Game._update_mp_profile.
			var pre: int = entry.get("pre_elo", 0)
			var t: int = entry.get("team", -1)
			var d := Game.mp_elo_delta(pre, Game.mp_opp_elos(t, stats), Game.match_result(t, winner_team))
			elo_str = "%d (%+d)" % [pre + d, d] if pre > 0 else "-"
		if entry.get("disconnected", false):
			pilot_name = "[DC] " + pilot_name
		var row := HBoxContainer.new()
		for cell_text: String in [
			pilot_name,
			elo_str,
			"%.0f" % entry.get("dealt", 0.0),
			"%.0f" % entry.get("taken", 0.0),
			"%d" % entry.get("captures", 0),
		]:
			var lbl := Label.new()
			lbl.text = cell_text
			lbl.add_theme_font_size_override("font_size", 14)
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)
		rows.add_child(row)

	vbox.add_child(HSeparator.new())

	var btn := Button.new()
	btn.name = "BackToLobbyBtn"
	btn.text = "BACK TO LOBBY"
	btn.add_theme_font_size_override("font_size", 15)
	if Game.multiplayer.multiplayer_peer is OfflineMultiplayerPeer:  # T184: SP -> hangar
		btn.text = "RETURN TO HANGAR"
		btn.pressed.connect(func():
			Game._clear_mp_session()
			get_tree().change_scene_to_file("res://scenes/ui/Hangar.tscn"))
	elif Game.multiplayer.is_server():
		btn.pressed.connect(func(): Game._confirm_ready_for_next_local())
	else:
		btn.pressed.connect(func(): Game._rpc_ready_for_next.rpc_id(1))
	vbox.add_child(btn)
	btn.grab_focus.call_deferred()

func show_squad_picker_mp(squad: Array, slot_used: Array, heading := "SELECT NEXT MECH") -> void:
	hide_squad_picker_mp()
	_squad_args = [squad, slot_used, heading]  # T322: BACK from the spawn picker reopens this
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.85)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.z_index = 10  # T323: over the name tags / kill feed made after it
	add_child(backdrop)
	_squad_picker = backdrop
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)
	var title := Label.new()
	title.text = heading
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	# T323 (HUMAN_FOUND 2026-11-05 late): a miniature hangar lineup -- each mech with the weapons
	# it carries, so two of the same mech can be told apart; no bay dressing (no cones, drones)
	var row := HBoxContainer.new()
	row.name = "MechCards"
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)
	for i in range(squad.size()):
		var sq: Dictionary = squad[i]
		var mech_path: String = sq.get("mech", "")
		if mech_path == "":
			continue
		if i < slot_used.size() and slot_used[i]:
			continue
		var md = ResourceLoader.load(mech_path)
		var label_text: String = md.display_name if md != null and "display_name" in md else mech_path.get_file()
		var card := VBoxContainer.new()
		card.name = "Card%d" % i
		card.add_theme_constant_override("separation", 2)
		row.add_child(card)
		var guns: Array = []
		if md != null and md.get("scene") != null:
			guns = _mini_bay(card, md, sq.get("weapons", []))
		var btn := Button.new()
		btn.text = label_text.to_upper()
		btn.add_theme_font_size_override("font_size", 12)
		var idx := i
		btn.pressed.connect(func(): squad_slot_selected.emit(idx))
		card.add_child(btn)
		var wl := Label.new()  # the loadout in words too: two of a mech differ here at a glance
		wl.text = " / ".join(guns)
		wl.add_theme_font_size_override("font_size", 8)
		wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wl.custom_minimum_size.x = CARD_PX.x
		card.add_child(wl)

const CARD_PX := Vector2i(108, 140)  # HUD px; the 3D renders at 2x (the window's pixels)

const _Lobby := preload("res://scripts/Lobby.gd")

## A card's 3D view; returns the short names of the weapons the mech carries.
func _mini_bay(card: Node, md: Resource, weapon_paths: Array) -> Array:
	var box := SubViewportContainer.new()
	box.custom_minimum_size = Vector2(CARD_PX)
	box.stretch = true
	box.stretch_shrink = 2  # viewport at 2x, shown at HUD scale: weapons stay crisp
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.size = CARD_PX * 2
	box.add_child(vp)
	card.add_child(box)  # in the tree first: the mech's _ready (torso, hardpoints) runs on add
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#1c212b")  # a touch lighter than the hangar: dark guns read
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.65)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	vp.add_child(sun)
	var m: Node3D = md.scene.instantiate()
	m.scale = Vector3.ONE * md.body_scale
	MechVisuals.apply(m, md.display_name)
	m.rotation_degrees.y = 215.0  # the hangar lineup's 3/4 view (Hangar.LINEUP_YAW)
	vp.add_child(m)
	m.set_physics_process(false)
	m.remove_from_group("mechs")  # a display prop, not a combatant
	MechVisuals.arm_display(m, md, weapon_paths)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 4.2 * maxf(1.0, md.body_scale)
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 2.6, 8.0) * maxf(1.0, md.body_scale), Vector3(0.0, 1.5 * md.body_scale, 0.0))
	cam.current = true  # not the mech's own chase camera
	var names: Array = []
	for w in m.get_weapons():
		var p := String(w.scene_file_path)
		var nm := p.get_file().get_basename()
		for e in _Lobby.WEAPON_CATALOG:
			if e["path"] == p:
				nm = e["name"]
		names.append(nm)
	return names

func hide_squad_picker_mp() -> void:
	if _squad_picker != null and is_instance_valid(_squad_picker):
		_squad_picker.queue_free()
	_squad_picker = null

func switch_player_mech(new_mech: Node) -> void:
	_player_mech = new_mech
	_original_player_mech = new_mech
	weapon_hud.setup(new_mech)

func _process(delta: float) -> void:
	_since_hit += delta
	if _streaming and _since_hit < STREAM_GAP:
		_damage_alpha = move_toward(_damage_alpha, TINT_A, delta * 2.0)  # ease into the steady tint
	elif _damage_alpha > 0.0:
		_damage_alpha = move_toward(_damage_alpha, 0.0, delta * 2.0)
	damage_flash.modulate.a = _damage_alpha
	if is_instance_valid(_player_mech):
		var lp: float = _player_mech.get("lock_progress") if "lock_progress" in _player_mech else 0.0
		crosshair.set_lock_progress(lp)
		_update_eligible_indicator()
		var pct: float = _player_mech.health / _player_mech.max_health
		health_bar_fg.offset_right = health_bar_fg.offset_left + 162.0 * pct
		var es: Node = _player_mech.get_node_or_null("EnergyShield")
		if es != null and es.get("_active"):
			var spct: float = es.shield_hp / es.max_shield_hp
			shield_bar_fg.offset_right = shield_bar_fg.offset_left + 162.0 * spct
			shield_bar_bg.visible = true
			shield_bar_fg.visible = true
		else:
			shield_bar_bg.visible = false
			shield_bar_fg.visible = false

	if _clock_label != null and _match != null:
		var left := ceili(maxf(0.0, float(_match.get("time_limit")) - float(_match.get("elapsed"))))
		_clock_label.text = "%d:%02d" % [left / 60, left % 60]
	if _match != null:
		var scores: Array = _match.get("scores")
		var s_limit: int = _match.get("score_limit") if "score_limit" in _match else 1000
		for t in _score_bars.size():
			var entry: Dictionary = _score_bars[t]
			var pct: float = clampf(float(scores[t]) / float(s_limit), 0.0, 1.0)
			var fg: ColorRect = entry.fg
			if t == 0:
				fg.offset_left  = entry.left
				fg.offset_right = entry.left + entry.max_w * pct
			else:
				fg.offset_right = entry.right
				fg.offset_left  = entry.right - entry.max_w * pct

	_update_ability_label()
	_update_bog_status()
	_update_bot_bar()
	_update_beacon_bars()
	_update_team_counts()

# T256 + T274 (user 2026-11-05: "make the only rangefinder be always-active, and only show
# distance to an enemy that's in the targeting reticle. So no range shown looking at a wall,
# unless there's an enemy behind it"): distance from our mech to the locked / lock-eligible
# enemy (the soft-lock box: the crosshair ray or the acquisition cone, no line of sight
# needed), beside the reticle; hidden when there is none. No raycast of its own any more
# (B108's _physics_process placement kept anyway).
var rangefinder: Label = null

func _physics_process(_delta: float) -> void:
	_update_rangefinder()

func _update_rangefinder() -> void:
	if rangefinder == null:
		rangefinder = Label.new()
		rangefinder.name = "Rangefinder"
		rangefinder.add_theme_font_size_override("font_size", 9)
		rangefinder.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 0.85))
		rangefinder.add_theme_constant_override("outline_size", 2)
		rangefinder.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		rangefinder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rangefinder)
	var target: Node3D = null
	if is_instance_valid(_player_mech) and crosshair.visible and not _player_mech.get("is_dead"):
		var locked = _player_mech.get("locked_target")
		target = locked if is_instance_valid(locked) else _player_mech.get("lock_eligible_target")
	if not is_instance_valid(target):
		rangefinder.visible = false
		return
	rangefinder.text = "%d m" % roundi(target.global_position.distance_to((_player_mech as Node3D).global_position))
	rangefinder.position = get_viewport().get_visible_rect().size * 0.5 + Vector2(10, 5)
	rangefinder.visible = true

# T284 (HUMAN_FOUND 2026-11-05: "Bogged down status effect should have a HUD icon and
# slowdown % listed. This should go under the minimap"): while terrain slows our mech (swamp
# wading, Mech.terrain_speed < 1) a small water icon + "BOGGED -N%" sits under the minimap.
var bog_status: Control = null

class BogIcon extends Control:  # three wavy water lines
	func _draw() -> void:
		for k in 3:
			var pts := PackedVector2Array()
			for x in 9:
				pts.append(Vector2(x * 1.25, 2.5 + k * 3.0 + sin(x * 1.6) * 0.9))
			draw_polyline(pts, Color(0.55, 0.75, 0.45, 0.95), 1.0, true)

func _update_bog_status() -> void:
	if bog_status == null:
		bog_status = HBoxContainer.new()
		bog_status.name = "BogStatus"
		bog_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bog_status.add_theme_constant_override("separation", 3)
		var icon := BogIcon.new()
		icon.name = "BogIcon"
		icon.custom_minimum_size = Vector2(11, 10)
		bog_status.add_child(icon)
		var lbl := Label.new()
		lbl.name = "BogLabel"
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color", Color(0.75, 0.9, 0.6))
		lbl.add_theme_constant_override("outline_size", 2)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		bog_status.add_child(lbl)
		add_child(bog_status)
	var slow := 0.0
	if is_instance_valid(_player_mech) and not _player_mech.get("is_dead"):
		slow = 1.0 - float(_player_mech.get("terrain_speed"))
	var pct := roundi(slow * 100.0)
	if pct <= 0 or minimap == null or not minimap.visible:
		bog_status.visible = false
		return
	(bog_status.get_node("BogLabel") as Label).text = "BOGGED -%d%%" % pct
	var r := minimap.get_global_rect()
	bog_status.position = Vector2(r.position.x, r.end.y + 3.0)
	bog_status.visible = true

const ELIGIBLE_HALF := 9.5

func _update_eligible_indicator() -> void:
	var target: Node3D = _player_mech.get("lock_eligible_target") if "lock_eligible_target" in _player_mech else null
	if target == null or not is_instance_valid(target):
		eligible_indicator.visible = false
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null or not camera.is_position_in_frustum(target.global_position):
		eligible_indicator.visible = false
		return
	var aim: Vector3 = target.call("center_mass") if target.has_method("center_mass") else target.global_position + BOT_BAR_HEAD_OFFSET * 0.20
	var screen_pos := camera.unproject_position(aim)  # T319: centre mass, not a fixed height
	eligible_indicator.position = screen_pos - Vector2(ELIGIBLE_HALF, ELIGIBLE_HALF)
	eligible_indicator.size = Vector2(ELIGIBLE_HALF * 2.0, ELIGIBLE_HALF * 2.0)
	eligible_indicator.visible = true
	eligible_indicator.queue_redraw()

func _update_ability_label() -> void:
	if _player_mech == null:
		ability_label.visible = false
		return
	var cooldowns: Dictionary = _player_mech.get("_ability_cooldowns") if "_ability_cooldowns" in _player_mech else {}
	var active_timers: Dictionary = _player_mech.get("_ability_active_timers") if "_ability_active_timers" in _player_mech else {}
	var abilities: Array = _player_mech.get("_abilities") if "_abilities" in _player_mech else []
	var actives: Array = abilities.filter(func(a): return a.trigger == 0)
	if actives.is_empty():
		ability_label.visible = false
		return
	var ability = actives[0]
	var key: String = ability.effect_key
	var remaining_active: float = active_timers.get(key, 0.0)
	var cd: float = cooldowns.get(key, 0.0)
	if remaining_active > 0.0:
		ability_label.text = "SPACE: %s  %.1fs" % [ability.ability_name, remaining_active]
	elif cd > 0.0:
		ability_label.text = "SPACE: %s  RECHARGING %.1fs" % [ability.ability_name, cd]
	else:
		ability_label.text = "SPACE: %s  READY" % ability.ability_name
	ability_label.visible = true

func _update_beacon_bars() -> void:
	for i in _beacons.size():
		if i >= _beacon_dots.size():
			break
		var beacon: Node = _beacons[i]
		var dot: Control = _beacon_dots[i]
		if not is_instance_valid(beacon) or not is_instance_valid(dot):
			continue
		dot.set("state",    beacon.get("state")             if "state"             in beacon else 0)
		dot.set("progress", beacon.get("_capture_progress") if "_capture_progress" in beacon else 0.0)
		dot.set("cap_team", beacon.get("_capturing_team")   if "_capturing_team"   in beacon else -1)
		dot.queue_redraw()

# T325: the callsign (roster "name") over each health bar, shown with it.
func _clear_name_tags() -> void:
	for t in _name_tags:
		if is_instance_valid(t):
			t.queue_free()
	_name_tags.clear()

func _update_name_tags() -> void:
	var mechs: Array = _bot_mechs + _ally_mechs
	var bgs: Array = _bot_bg_bars + _ally_bg_bars
	while _name_tags.size() < mechs.size():
		var tag := Label.new()
		tag.add_theme_font_size_override("font_size", 7)
		tag.add_theme_constant_override("outline_size", 2)
		tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.visible = false
		add_child(tag)
		_name_tags.append(tag)
	var roster: Array = Game.mp_active_match["roster"]
	for i in mechs.size():
		var tag: Label = _name_tags[i]
		var bg: ColorRect = bgs[i]
		tag.visible = bg.visible
		if not tag.visible:
			continue
		if tag.text == "":
			var ri: int = int(mechs[i].get("roster_idx"))
			tag.text = str(roster[ri].get("name", "")) if ri >= 0 and ri < roster.size() else ""
		tag.offset_left = bg.offset_left - 50.0
		tag.offset_right = bg.offset_right + 50.0
		tag.offset_top = bg.offset_top - 11.0
		tag.offset_bottom = bg.offset_top - 1.0

func _update_bot_bar() -> void:
	_update_bot_bar_impl()
	_update_name_tags()
	_update_feed(get_process_delta_time())

# T324 (HUMAN_FOUND 2026-11-05 late: "Top left of HUD, under the ability marker, should have a
# readout, small text, listing kills and chat. Chat as a stub; kills very simple. Should take up
# very little space and not be distracting"): FEED_LINES newest lines, each gone after FEED_LIFE_S.
const _ALLY_HEX := "7fb8ff"
const _ENEMY_HEX := "ff7f6e"

func add_kill(killer: String, killer_ally: bool, victim: String, victim_ally: bool) -> void:
	var v := "[color=#%s]%s[/color]" % [_ALLY_HEX if victim_ally else _ENEMY_HEX, _bb(victim)]
	if killer == "":
		_feed_add("%s [color=#aaaaaa]destroyed[/color]" % v)
	else:
		_feed_add("[color=#%s]%s[/color] [color=#aaaaaa]>[/color] %s" % [
			_ALLY_HEX if killer_ally else _ENEMY_HEX, _bb(killer), v])

# player names and chat are other players' text: no bbcode tags from them
static func _bb(t: String) -> String:
	return t.replace("[", "[lb]")

## Chat stub: nothing sends chat yet; a message shows in the feed like a kill.
func add_chat(sender: String, text: String) -> void:
	_feed_add("[color=#dddddd]%s:[/color] %s" % [_bb(sender), _bb(text)])

func _feed_add(line: String) -> void:
	_feed_lines.append([line, 0.0])
	while _feed_lines.size() > FEED_LINES:
		_feed_lines.pop_front()
	_redraw_feed()

func _update_feed(delta: float) -> void:
	if _feed_lines.is_empty():
		return
	for e in _feed_lines:
		e[1] += delta
	var n := _feed_lines.size()
	_feed_lines = _feed_lines.filter(func(e): return e[1] < FEED_LIFE_S)
	if _feed_lines.size() != n:
		_redraw_feed()

func _redraw_feed() -> void:
	if _feed == null:
		_feed = RichTextLabel.new()
		_feed.name = "KillFeed"
		_feed.bbcode_enabled = true
		_feed.scroll_active = false
		_feed.fit_content = true
		_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_feed.add_theme_font_size_override("normal_font_size", 9)
		_feed.position = Vector2(16, 64)  # under the ability marker (AbilityLabel 44..62)
		_feed.size = Vector2(230, 0)
		add_child(_feed)
	_feed.text = "\n".join(_feed_lines.map(func(e): return e[0]))
	_feed.visible = not _feed_lines.is_empty()

func _update_bot_bar_impl() -> void:
	var camera := get_viewport().get_camera_3d()
	for i in _bot_mechs.size():
		var m: Node = _bot_mechs[i]
		var fg: ColorRect = _bot_health_bars[i]
		var bg: ColorRect = _bot_bg_bars[i]
		if m == null or not is_instance_valid(m) or not m.visible:
			fg.visible = false
			bg.visible = false
			continue
		if m.get("is_stealthy"):
			fg.visible = false
			bg.visible = false
			continue
		if camera == null:
			fg.visible = false
			bg.visible = false
			continue
		var world_pos: Vector3 = m.global_position + BOT_BAR_HEAD_OFFSET
		if not camera.is_position_in_frustum(world_pos):
			fg.visible = false
			bg.visible = false
			continue
		var screen_pos: Vector2 = camera.unproject_position(world_pos)
		var pct: float = m.health / m.max_health
		var left: float = screen_pos.x - BOT_BAR_FULL_WIDTH * 0.5
		var top: float  = screen_pos.y - BOT_BAR_HEIGHT * 0.5
		# Background always spans the full width.
		bg.offset_left   = left
		bg.offset_top    = top
		bg.offset_right  = left + BOT_BAR_FULL_WIDTH
		bg.offset_bottom = top + BOT_BAR_HEIGHT
		bg.visible = true
		# Foreground shrinks with health.
		fg.offset_left   = left
		fg.offset_top    = top
		fg.offset_right  = left + BOT_BAR_FULL_WIDTH * pct
		fg.offset_bottom = top + BOT_BAR_HEIGHT
		fg.visible = pct > 0.0
	for i in _ally_mechs.size():
		var m: Node = _ally_mechs[i]
		var fg: ColorRect = _ally_health_bars[i]
		var bg: ColorRect = _ally_bg_bars[i]
		if m == null or not is_instance_valid(m) or not m.visible:
			fg.visible = false
			bg.visible = false
			continue
		if camera == null:
			fg.visible = false
			bg.visible = false
			continue
		var world_pos: Vector3 = m.global_position + BOT_BAR_HEAD_OFFSET
		if not camera.is_position_in_frustum(world_pos):
			fg.visible = false
			bg.visible = false
			continue
		var screen_pos: Vector2 = camera.unproject_position(world_pos)
		var pct: float = m.health / m.max_health
		var left: float = screen_pos.x - BOT_BAR_FULL_WIDTH * 0.5
		var top: float  = screen_pos.y - BOT_BAR_HEIGHT * 0.5
		bg.offset_left   = left
		bg.offset_top    = top
		bg.offset_right  = left + BOT_BAR_FULL_WIDTH
		bg.offset_bottom = top + BOT_BAR_HEIGHT
		bg.visible = true
		fg.offset_left   = left
		fg.offset_top    = top
		fg.offset_right  = left + BOT_BAR_FULL_WIDTH * pct
		fg.offset_bottom = top + BOT_BAR_HEIGHT
		fg.visible = pct > 0.0

# T217: players, not mech objects -- the old count summed every mech a team had spawned
# (each respawn, and the first mech swapped out at the start pick, added one).
var arena: Node = null  # set by Arena._setup_hud

func _update_team_counts() -> void:
	if _team_count_labels.size() < 2 or arena == null:
		return
	var own: Vector2i = arena.team_counts(_player_team)
	var opp: Vector2i = arena.team_counts(1 - _player_team)
	_team_count_labels[0].text = "%d / %d" % [own.x, own.y]
	_team_count_labels[1].text = "%d / %d" % [opp.x, opp.y]
