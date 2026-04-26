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
var _bot_mech: Node = null

func setup(match_node: Node, player_mech: Node, player_team: int) -> void:
	_match = match_node
	_player_mech = player_mech
	_player_team = player_team
	weapon_hud.setup(player_mech)

func setup_bot_bar(bot_mech: Node) -> void:
	_bot_mech = bot_mech

func show_damage() -> void:
	_damage_alpha = 0.45

func register_hit() -> void:
	crosshair.register_hit()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func show_result(winning_team: int, stats: Dictionary = {}) -> void:
	result_label.text = "YOU WIN" if winning_team == _player_team else "YOU LOSE"
	result_label.visible = true
	crosshair.visible = false
	_build_stats_panel(stats)

func _build_stats_panel(stats: Dictionary) -> void:
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
		score_label.text = "A: %d     B: %d" % [scores[0], scores[1]]

	_update_ability_label()
	_update_bot_bar()

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

func _update_bot_bar() -> void:
	if _bot_mech == null or not is_instance_valid(_bot_mech) or not _bot_mech.visible:
		bot_health_bar.visible = false
		return
	if _bot_mech.get("is_stealthy"):
		bot_health_bar.visible = false
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		bot_health_bar.visible = false
		return
	var world_pos: Vector3 = _bot_mech.global_position + BOT_BAR_HEAD_OFFSET
	if not camera.is_position_in_frustum(world_pos):
		bot_health_bar.visible = false
		return
	var screen_pos: Vector2 = camera.unproject_position(world_pos)
	var pct: float = _bot_mech.health / _bot_mech.max_health
	var bar_w: float = BOT_BAR_FULL_WIDTH * pct
	# Use offsets - the reliable way to set position+size on a free Control
	var left: float = screen_pos.x - BOT_BAR_FULL_WIDTH * 0.5
	var top: float  = screen_pos.y - BOT_BAR_HEIGHT * 0.5
	bot_health_bar.offset_left   = left
	bot_health_bar.offset_top    = top
	bot_health_bar.offset_right  = left + bar_w
	bot_health_bar.offset_bottom = top + BOT_BAR_HEIGHT
	bot_health_bar.visible = true
