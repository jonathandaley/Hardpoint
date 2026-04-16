class_name Arena
extends Node3D

@onready var match_node: Node = $BeaconMatch
@onready var hud: CanvasLayer = $HUD

var player_mech: CharacterBody3D
var bot_mech: CharacterBody3D

var _player: Node
var _bot_player: Node
var _match_over: bool = false

func _ready() -> void:
	_spawn_mechs()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_create_walls()
	_create_cover()
	_wire_beacons()
	_setup_players()
	match_node.match_ended.connect(_on_match_ended)
	match_node.start()
	_set_mech_color(player_mech, Color(0.25, 0.52, 0.95))
	_set_mech_color(bot_mech,    Color(0.92, 0.28, 0.22))
	hud.setup(match_node, player_mech, 0)
	hud.setup_bot_bar(bot_mech)
	var gun := player_mech.get_node_or_null("Torso/HardpointRight/RaycastGun")
	if gun:
		gun.hit_confirmed.connect(hud.register_hit)
	player_mech.damaged.connect(hud.show_damage)
	print("[Arena] Match started. Score to drain: %d" % match_node.score_limit)

func _spawn_mechs() -> void:
	var mech_def = Game.loadout.get("mech_def")
	if mech_def == null:
		mech_def = load("res://resources/mechs/Hippogriff.tres")

	player_mech = mech_def.scene.instantiate()
	player_mech.name = "PlayerMech"
	player_mech.position = Vector3(-20, 0, 0)
	player_mech.rotation_degrees = Vector3(0, -90, 0)
	player_mech.max_health = mech_def.max_health
	player_mech.base_walk_speed = mech_def.walk_speed
	player_mech.turn_acceleration = mech_def.turn_acceleration
	player_mech.leg_rotation_speed = mech_def.leg_rotation_speed
	add_child(player_mech)

	var bot_def = load("res://resources/mechs/Hippogriff.tres")
	bot_mech = bot_def.scene.instantiate()
	bot_mech.name = "BotMech"
	bot_mech.position = Vector3(20, 0, 0)
	bot_mech.team = 1
	bot_mech.max_health = bot_def.max_health
	bot_mech.base_walk_speed = bot_def.walk_speed
	bot_mech.turn_acceleration = bot_def.turn_acceleration
	bot_mech.leg_rotation_speed = bot_def.leg_rotation_speed
	add_child(bot_mech)

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

func _set_mech_color(mech: Node3D, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.3
	var leg_mat := StandardMaterial3D.new()
	leg_mat.albedo_color = color.darkened(0.2)
	leg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	leg_mat.emission_enabled = true
	leg_mat.emission = color.darkened(0.2)
	leg_mat.emission_energy_multiplier = 0.3
	var torso := mech.get_node_or_null("Torso")
	if torso:
		for mesh in torso.find_children("*", "MeshInstance3D", true, false):
			mesh.set_surface_override_material(0, mat)
	var legs := mech.get_node_or_null("Legs")
	if legs:
		for mesh in legs.find_children("*", "MeshInstance3D", true, false):
			mesh.set_surface_override_material(0, leg_mat)

func _create_cover() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.50, 0.47, 0.44, 1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

	# [world_position, box_size]
	var blocks: Array = [
		# Mid-field: four walls that break the east-west spawn sightline
		# and create cover corridors running north-south
		[Vector3(-10, 1.5,  10), Vector3(2, 3, 8)],
		[Vector3(-10, 1.5, -10), Vector3(2, 3, 8)],
		[Vector3( 10, 1.5,  10), Vector3(2, 3, 8)],
		[Vector3( 10, 1.5, -10), Vector3(2, 3, 8)],
		# Center beacon (0,0,0): short flanking walls east and west
		[Vector3(-6, 1.25, 0), Vector3(1, 2.5, 6)],
		[Vector3( 6, 1.25, 0), Vector3(1, 2.5, 6)],
		# Beacon 2 (-28,0,-28): L-shaped approach cover
		[Vector3(-20, 1.25, -28), Vector3(1, 2.5, 8)],
		[Vector3(-28, 1.25, -20), Vector3(8, 2.5, 1)],
		# Beacon 3 (28,0,28): mirrored L
		[Vector3( 20, 1.25,  28), Vector3(1, 2.5, 8)],
		[Vector3( 28, 1.25,  20), Vector3(8, 2.5, 1)],
	]

	for b in blocks:
		var body := StaticBody3D.new()
		body.position = b[0]
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = b[1]
		col.shape = shape
		body.add_child(col)
		var mesh_inst := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = b[1]
		mesh_inst.mesh = mesh
		mesh_inst.set_surface_override_material(0, mat)
		body.add_child(mesh_inst)
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
		get_tree().change_scene_to_file("res://scenes/ui/Hangar.tscn")
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
