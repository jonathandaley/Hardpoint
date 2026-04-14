class_name Arena
extends Node3D

@onready var match_node: BeaconMatch = $BeaconMatch
@onready var player_mech: Mech = $PlayerMech
@onready var bot_mech: Mech = $BotMech

var _player: Player
var _bot_player: Player

func _ready() -> void:
	_wire_beacons()
	_setup_players()
	match_node.match_ended.connect(_on_match_ended)
	match_node.start()
	print("[Arena] Match started. Score to drain: %d" % match_node.score_limit)

func _wire_beacons() -> void:
	for child in get_children():
		if child is Beacon:
			match_node.register_beacon(child)

func _setup_players() -> void:
	# Human player
	_player = Player.new()
	_player.name = "Player"
	_player.team = 0
	var input := PlayerInputSource.new()
	_player.add_child(input)
	_player.input_source = input
	var pilot := Pilot.new()
	pilot.pilot_name = Game.profile.get("pilot_name", "Pilot")
	_player.add_child(pilot)
	_player.pilot = pilot
	add_child(_player)
	_player.possess(player_mech)

	# Bot player
	_bot_player = Player.new()
	_bot_player.name = "BotPlayer"
	_bot_player.team = 1
	var ai_input := AIInputSource.new()
	_bot_player.add_child(ai_input)
	_bot_player.input_source = ai_input
	add_child(_bot_player)
	_bot_player.possess(bot_mech)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func on_player_eliminated(p: Player) -> void:
	if p == _player:
		print("[Arena] Player eliminated — game over.")
	else:
		print("[Arena] Bot eliminated.")

func _on_match_ended(winning_team: int) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("[Arena] Match over. Team %d wins." % winning_team)
