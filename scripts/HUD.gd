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

const BOT_BAR_FULL_WIDTH := 32.0
const BOT_BAR_HEIGHT     := 6.0
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
var _spectate_label: Label = null

var _beacons: Array = []
var _beacon_dots: Array = []       # BeaconDot per beacon, top-center ownership circles
var _score_bars: Array = []        # [{bg, fg, max_w}] team 0 and 1 score bars
var _team_count_labels: Array = [] # [team0_label, team1_label] alive counters

var _original_player_mech: Node = null  # keeps the original ref after spectate switch

func setup(match_node: Node, player_mech: Node, player_team: int) -> void:
	_match = match_node
	_player_mech = player_mech
	_original_player_mech = player_mech
	_player_team = player_team
	weapon_hud.setup(player_mech)
	score_label.visible = false

func setup_bot_bars(mechs: Array) -> void:
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
		# Black background — z_index -1 ensures it always renders behind the fg.
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

func show_damage() -> void:
	_damage_alpha = 0.45

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

func show_result(winning_team: int, stats: Dictionary = {}) -> void:
	result_label.visible = false
	crosshair.visible = false
	_build_stats_panel(winning_team == _player_team, stats)

func _build_stats_panel(won: bool, stats: Dictionary) -> void:
	var backdrop := ColorRect.new()
	backdrop.process_mode = Node.PROCESS_MODE_ALWAYS
	backdrop.color = Color(0, 0, 0, 1)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	# Full-screen centering container
	var center := CenterContainer.new()
	center.process_mode = Node.PROCESS_MODE_ALWAYS
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	center.add_child(panel)

	var header := Label.new()
	header.text = "YOU WIN" if won else "YOU LOSE"
	header.add_theme_font_size_override("font_size", 28)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.modulate = Color(0.2, 1.0, 0.2) if won else Color(1.0, 0.3, 0.3)
	vbox.add_child(header)
	vbox.add_child(HSeparator.new())

	var rows := [
		["DAMAGE DEALT",     "%.0f" % stats.get("damage_dealt",     0.0)],
		["DAMAGE TAKEN",     "%.0f" % stats.get("damage_taken",     0.0)],
		["BEACONS CAPTURED", "%d"   % stats.get("beacons_captured", 0)],
		["ENEMY BEACONS",    "%d"   % stats.get("bot_beacons",      0)],
	]
	for row in rows:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 32)
		var lbl := Label.new()
		lbl.text = row[0]
		lbl.add_theme_font_size_override("font_size", 15)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var val := Label.new()
		val.text = row[1]
		val.add_theme_font_size_override("font_size", 15)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hbox.add_child(lbl)
		hbox.add_child(val)
		vbox.add_child(hbox)

	vbox.add_child(HSeparator.new())

	var btn := Button.new()
	btn.text = "RETURN TO HANGAR"
	btn.add_theme_font_size_override("font_size", 15)
	btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ui/Hangar.tscn"))
	vbox.add_child(btn)
	# focus so Enter activates it
	btn.grab_focus.call_deferred()

func _process(delta: float) -> void:
	if _damage_alpha > 0.0:
		_damage_alpha = move_toward(_damage_alpha, 0.0, delta * 2.0)
		damage_flash.modulate.a = _damage_alpha
	if _player_mech != null:
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
	_update_bot_bar()
	_update_beacon_bars()
	_update_team_counts()

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
	var screen_pos := camera.unproject_position(target.global_position + BOT_BAR_HEAD_OFFSET * 0.20)
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

func _update_bot_bar() -> void:
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

func _update_team_counts() -> void:
	if _team_count_labels.size() < 2:
		return
	# Team 0: original player mech + ally bots.
	var t0_total := 1 + _ally_mechs.size()
	var t0_alive := 0
	if is_instance_valid(_original_player_mech) and _original_player_mech.visible:
		t0_alive += 1
	for m in _ally_mechs:
		if is_instance_valid(m) and m.visible:
			t0_alive += 1
	# Team 1: enemy bots.
	var t1_total := _bot_mechs.size()
	var t1_alive := 0
	for m in _bot_mechs:
		if is_instance_valid(m) and m.visible:
			t1_alive += 1
	_team_count_labels[0].text = "%d / %d" % [t0_alive, t0_total]
	_team_count_labels[1].text = "%d / %d" % [t1_alive, t1_total]
