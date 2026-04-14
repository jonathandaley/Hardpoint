class_name Arena
extends Node3D

@onready var match_node: Node = $BeaconMatch
@onready var player_mech: CharacterBody3D = $PlayerMech
@onready var bot_mech: CharacterBody3D = $BotMech
@onready var hud: CanvasLayer = $HUD

var _player: Node
var _bot_player: Node
var _match_over: bool = false

func _ready() -> void:
	_create_walls()
	_wire_beacons()
	_setup_players()
	match_node.match_ended.connect(_on_match_ended)
	match_node.start()
	hud.setup(match_node, player_mech, 0)
	print("[Arena] Match started. Score to drain: %d" % match_node.score_limit)

func _create_walls() -> void:
	# Invisible boundary walls at the floor edge (±75m). 10m tall so nothing flies over.
	var walls := [
		[Vector3(  0, 5,  75), Vector3(150, 10, 1)],
		[Vector3(  0, 5, -75), Vector3(150, 10, 1)],
		[Vector3( 75, 5,   0), Vector3(1, 10, 150)],
		[Vector3(-75, 5,   0), Vector3(1, 10, 150)],
	]
	for w in walls:
		var body := StaticBody3D.new()
		body.position = w[0]
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = w[1]
		col.shape = shape
		body.add_child(col)
		add_child(body)

func _wire_beacons() -> void:
	for child in get_children():
		if child.is_in_group("beacons"):
			match_node.register_beacon(child)

func _setup_players() -> void:
	# Human player
	_player = Node.new()
	_player.set_script(load("res://scripts/Player.gd"))
	_player.name = "Player"
	_player.set("team", 0)
	add_child(_player)

	var input := Node.new()
	input.set_script(load("res://scripts/PlayerInputSource.gd"))
	_player.add_child(input)
	_player.set("input_source", input)

	var pilot := Node.new()
	pilot.set_script(load("res://scripts/Pilot.gd"))
	pilot.set("pilot_name", Game.profile.get("pilot_name", "Pilot"))
	_player.add_child(pilot)
	_player.set("pilot", pilot)

	_player.call("possess", player_mech)
	player_mech.died.connect(Callable(_player, "on_pawn_destroyed"))

	# Bot player
	_bot_player = Node.new()
	_bot_player.set_script(load("res://scripts/Player.gd"))
	_bot_player.name = "BotPlayer"
	_bot_player.set("team", 1)
	add_child(_bot_player)

	var ai_input := Node.new()
	ai_input.set_script(load("res://scripts/AIInputSource.gd"))
	_bot_player.add_child(ai_input)
	_bot_player.set("input_source", ai_input)

	_bot_player.call("possess", bot_mech)
	bot_mech.died.connect(Callable(_bot_player, "on_pawn_destroyed"))

func _input(event: InputEvent) -> void:
	if _match_over and event.is_action_pressed("ui_accept"):
		get_tree().reload_current_scene()
		return
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func on_player_eliminated(p: Node) -> void:
	var losing_team: int = p.get("team") if p.get("team") != null else 0
	match_node.force_end(1 - losing_team)
	print("[Arena] Player eliminated." if p == _player else "[Arena] Bot eliminated.")

func _on_match_ended(winning_team: int) -> void:
	_match_over = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_result(winning_team)
	print("[Arena] Match over. Team %d wins." % winning_team)
