extends CanvasLayer

@onready var health_bar_bg: ColorRect = $HealthBarBG
@onready var health_bar_fg: ColorRect = $HealthBarFG
@onready var score_label: Label = $ScoreLabel
@onready var crosshair: Control = $Crosshair
@onready var damage_flash: ColorRect = $DamageFlash
@onready var result_label: Label = $ResultLabel
@onready var restart_label: Label = $RestartLabel
@onready var bot_health_bar: ColorRect = $BotHealthBar
@onready var weapon_hud: Control = $WeaponHUD

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

func show_result(winning_team: int) -> void:
	result_label.text = "YOU WIN" if winning_team == _player_team else "YOU LOSE"
	result_label.visible = true
	restart_label.visible = true
	crosshair.visible = false

func _process(delta: float) -> void:
	if _damage_alpha > 0.0:
		_damage_alpha = move_toward(_damage_alpha, 0.0, delta * 2.0)
		damage_flash.modulate.a = _damage_alpha
	if _player_mech != null:
		var pct: float = _player_mech.health / _player_mech.max_health
		health_bar_fg.offset_right = health_bar_fg.offset_left + 162.0 * pct

	if _match != null:
		var scores: Array = _match.get("scores")
		score_label.text = "A: %d     B: %d" % [scores[0], scores[1]]

	_update_bot_bar()

func _update_bot_bar() -> void:
	if _bot_mech == null or not is_instance_valid(_bot_mech) or not _bot_mech.visible:
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
	# Use offsets — the reliable way to set position+size on a free Control
	var left: float = screen_pos.x - BOT_BAR_FULL_WIDTH * 0.5
	var top: float  = screen_pos.y - BOT_BAR_HEIGHT * 0.5
	bot_health_bar.offset_left   = left
	bot_health_bar.offset_top    = top
	bot_health_bar.offset_right  = left + bar_w
	bot_health_bar.offset_bottom = top + BOT_BAR_HEIGHT
	bot_health_bar.visible = true
