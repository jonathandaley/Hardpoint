class_name Arena
extends Node3D

const _BlobShadow := preload("res://scripts/BlobShadow.gd")
const MechVisuals = preload("res://scripts/MechVisuals.gd")

@onready var match_node: Node = $BeaconMatch
@onready var hud: CanvasLayer = $HUD
@onready var pause_menu: CanvasLayer = $PauseMenu

var player_mech: CharacterBody3D
var _team_mechs: Array = [[], []]   # mechs per team; player_mech is _team_mechs[0][0]

var _player: Node                   # human player (team 0)
var _players: Array = []            # all Player nodes across both teams
var _spectated_mech: Node = null    # mech whose camera is currently active
var _local_team: int = 0            # local player's team index (set in setup)
var _match_over: bool = false
var _beacons_captured: Array[int] = [0, 0]
var _disconnected_peers: Dictionary = {}  # peer_id -> true; set on mid-match disconnect
var _peer_slot_used: Dictionary = {}      # peer_id -> Array[bool] of 5 squad slot used flags
var _nav_region: NavigationRegion3D = null
var _movement_logger: Node = null   # MovementLogger instance (not an autoload, owned here)

# Free-floating spectator camera (activated when player mech dies).
var _spec_pivot: Node3D = null
var _spec_arm: SpringArm3D = null
var _spec_cam: Camera3D = null
var _spec_yaw: float = 0.0
var _spec_pitch: float = -0.3

func _ready() -> void:
	# T161 (B46): Arena stays pausable. It used to be PROCESS_MODE_ALWAYS (so Esc
	# could unpause), which every child inherited -- pausing froze nothing. Esc while
	# paused is now handled by PauseMenu (PROCESS_MODE_ALWAYS).
	pause_menu.resume_requested.connect(_on_pause_resume)
	pause_menu.quit_requested.connect(_on_pause_quit)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_apply_map_theme()
	$Sun.shadow_enabled = Game.settings.get("shadows", "blob") == "full"  # T193: BLOB = discs instead
	# T184: SP is a local MP match (Game.start_sp_match); opened directly (tools, F6) = SP defaults
	if Game.mp_active_match["roster"].is_empty():
		Game.setup_sp_match()
	# T210: the map is its own scene (geometry, beacons, spawn points); built after the spawn
	var md = Game.loadout.get("map_def")
	var map_path: String = md.scene_path if md != null and md.get("scene_path") else "res://scenes/maps/MathTemple.tscn"
	_map = load(map_path).instantiate()
	_map.name = "Map"
	add_child(_map)
	var late = Game.late_join  # T206: joined mid-match, the state came with the handshake
	if late != null:
		_apply_late_state(late)
	else:
		_spawn_mechs_mp()
	_map.build()
	_map.add_surface_detail()  # T241
	_wire_beacons()
	if late != null:
		_apply_late_beacons(late)
		_setup_late_player(late)
		Game.late_join_ready.call_deferred()  # finish the handshake once the scene is in
	else:
		_setup_players_mp()
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		pass  # SP: no clients to stream snapshots to
	elif multiplayer.is_server():
		_start_snapshot_timer()
	elif late == null:
		Game._rpc_transition_ack.rpc_id(1)  # T159: Arena loaded, server may stream
	Game.match_ended_mp.connect(_on_mp_match_ended)
	Game.mp_peer_disconnected.connect(_on_peer_disconnected_in_match)
	if multiplayer.is_server():  # bots (the only nav users) run server-side (T40); SP = offline server
		_create_nav_region()
	match_node.match_ended.connect(_on_match_ended)
	match_node.start()
	# ponytail: MovementLogger records a CSV + prints a stuck-% analysis on EVERY
	# arena load, prod included (115-line diagnostic). Gate behind a debug flag or
	# only instantiate when profiling, so shipped matches don't pay for it.
	_movement_logger = load("res://autoloads/MovementLogger.gd").new()
	add_child(_movement_logger)
	_movement_logger.start_session()
	SoundManager.play_music("arena")
	print("[Arena] Match started. Score to drain: %d" % match_node.score_limit)



var _overhead_cam: Camera3D

func _apply_map_theme() -> void:
	var map_def = Game.loadout.get("map_def")
	if map_def == null:
		return
	var we: WorldEnvironment = $WorldEnvironment
	if we == null or we.environment == null:
		return
	we.environment.ambient_light_color  = map_def.ambient_color
	we.environment.ambient_light_energy = map_def.ambient_energy

func _toggle_overhead() -> void:
	if _overhead_cam == null:
		_overhead_cam = Camera3D.new()
		_overhead_cam.position = Vector3(0, 160, 0)
		_overhead_cam.rotation_degrees = Vector3(-90, 0, 0)
		_overhead_cam.far = 350.0
		add_child(_overhead_cam)
	_overhead_cam.current = not _overhead_cam.current

# Perpendicular to the SW-NE team axis; mechs fan out along this direction.
const _SPAWN_SPACING := 8.0   # metres between mechs in a team line

func _slots_with_weapon_paths(slots: Array, weapon_paths: Array) -> Array:
	if weapon_paths.is_empty():
		return slots
	var result: Array = []
	for i in slots.size():
		if i < weapon_paths.size() and weapon_paths[i] != "":
			var scene: PackedScene = ResourceLoader.load(weapon_paths[i])
			if scene != null:
				var s = slots[i].duplicate()
				s.weapon_scene = scene
				result.append(s)
			else:
				result.append(slots[i])
		else:
			result.append(slots[i])
	return result

var _map: MapScene = null  # T210: the map scene (MapDef.scene_path)
const DEBUG_OVERHEAD := false  # F5 overhead camera (was DEBUG_PENROSE)

# T203/T210: the map's spawn points for `team` (world positions).
func spawn_points(team: int) -> Array:
	return _map.spawn_points(team)

func _spawn_one_mech(mech_def, team: int, idx: int, count: int, weapon_paths: Array = [], mech_name := "",
		spawn := 0) -> CharacterBody3D:
	var perp_offset: float = (float(idx) - float(count - 1) * 0.5) * _SPAWN_SPACING
	var base: Vector3 = spawn_points(team)[spawn]
	var to_c: Vector2 = _map.center - Vector2(base.x, base.z)
	var facing_y: float = rad_to_deg(atan2(-to_c.x, -to_c.y))  # face the map centre
	# the line runs across the facing; team 1 mirrored, which keeps the pre-T203 slot order
	var perp := Basis(Vector3.UP, deg_to_rad(facing_y)).x * (1.0 if team == 0 else -1.0)
	var sx: float = base.x + perp.x * perp_offset
	var sz: float = base.z + perp.z * perp_offset
	var m: CharacterBody3D = mech_def.scene.instantiate()
	m.name = mech_name if mech_name != "" else "Mech_%d_%d" % [team, idx]
	m.set_meta("spawn", [mech_def.resource_path, weapon_paths])  # T206: rebuilt by late joiners
	m.position = Vector3(sx, _ground_y(sx, sz) + 1.0, sz)
	m.rotation_degrees = Vector3(0, facing_y, 0)
	m.team = team
	m.scale = Vector3.ONE * mech_def.body_scale
	m.max_health = mech_def.max_health
	m.base_walk_speed = mech_def.walk_speed
	m.turn_acceleration = mech_def.turn_acceleration
	m.leg_rotation_speed = mech_def.leg_rotation_speed
	MechVisuals.apply(m, mech_def.display_name)
	add_child(m)
	if Game.settings.get("shadows", "blob") == "blob":  # T193
		var blob := MeshInstance3D.new()
		blob.set_script(_BlobShadow)
		blob.radius = 1.1 * mech_def.body_scale
		m.add_child(blob)
	m.configure_legs(mech_def.leg_hip_sweep, mech_def.leg_bob_magnitude, mech_def.leg_cycle_rate)
	m.configure_shield(mech_def.has_shields, mech_def.shield_max_hp)
	m.configure_energy_shield(mech_def.has_energy_shield, mech_def.energy_shield_max_hp,
		mech_def.energy_shield_regen_rate, mech_def.energy_shield_regen_delay)
	m.weapon_scale = mech_def.weapon_scale
	m.configure_weapons(_slots_with_weapon_paths(mech_def.weapon_slots, weapon_paths))
	m.configure_abilities(mech_def.abilities)
	m.invincible = mech_def.invincible
	_team_mechs[team].append(m)
	return m

func _spawn_mechs_mp() -> void:
	var roster: Array = Game.mp_active_match["roster"]
	var team_counts := [0, 0]
	for entry in roster:
		var t: int = entry["team"]
		if t == 0 or t == 1:
			team_counts[t] += 1
	var team_idx := [0, 0]
	for ri in roster.size():
		var entry: Dictionary = roster[ri]
		var t: int = entry["team"]
		if t < 0 or t >= 2:
			continue
		var squad: Array = entry["squad"]
		if squad.is_empty():
			push_error("[Arena] MP: empty squad for peer %d" % entry["peer_id"])
			continue
		var mech_path: String = squad[0].get("mech", "")
		var mech_def = ResourceLoader.load(mech_path) if mech_path != "" else null
		if mech_def == null:
			push_error("[Arena] MP: cannot load mech_def '%s'" % mech_path)
			continue
		var wpn_paths: Array = squad[0].get("weapons", [])
		var m: CharacterBody3D = _spawn_one_mech(mech_def, t, team_idx[t], team_counts[t], wpn_paths)
		m.owner_peer_id = entry["peer_id"]
		m.roster_idx = ri
		if entry["peer_id"] != 0 and entry["peer_id"] == multiplayer.get_unique_id() and player_mech == null:
			player_mech = m
			if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
				m.apply_pilot_skills()  # SP only, as before T184
		if entry["peer_id"] != 0:
			_peer_slot_used[entry["peer_id"]] = [true, false, false, false, false]
		team_idx[t] += 1

func _setup_players_mp() -> void:
	var roster: Array = Game.mp_active_match["roster"]
	var my_id: int = multiplayer.get_unique_id()
	var team_idx := [0, 0]
	for ri in roster.size():
		var entry: Dictionary = roster[ri]
		var t: int = entry["team"]
		if t < 0 or t >= 2:
			continue
		var mech: CharacterBody3D = _team_mechs[t][team_idx[t]]
		var tidx: int = team_idx[t]
		team_idx[t] += 1
		if entry["peer_id"] == 0:
			# T198: bots burn through their squads like humans (5 lives, server respawns)
			var bp := _spawn_bot_player(mech, t, tidx)
			bp.set("lives", _squad_lives(entry))
			if multiplayer.is_server():
				mech.died.connect(_on_bot_mech_died.bind(bp, ri))
		elif entry["peer_id"] == my_id:
			# T127: squad lives -- count valid slots and set lives; wire squad picker.
			_make_local_player(t, _squad_lives(entry), mech)
		else:
			var p := Node.new()
			p.set_script(load("res://scripts/Player.gd"))
			p.name = "RemotePlayer_%d" % entry["peer_id"]
			p.set("team", t)
			add_child(p)
			var net_input := Node.new()
			net_input.set_script(load("res://scripts/NetworkInputSource.gd"))
			p.add_child(net_input)
			p.set("input_source", net_input)
			p.call("possess", mech)
			mech.died.connect(Callable(p, "on_pawn_destroyed"))
			_players.append(p)
			# T127: set remote player lives from squad valid slot count.
			p.set("lives", _squad_lives(entry))
	# T122: HUD perspective — team-relative (own=green/blue, opp=red) regardless of server team id.
	if player_mech != null and _player != null:
		_setup_hud(_player.get("team"), player_mech)
		for weapon in player_mech.get_weapons():
			if weapon.has_signal("hit_confirmed"):
				weapon.hit_confirmed.connect(hud.register_hit)
		player_mech.damaged.connect(hud.show_damage)
		_open_start_pick.call_deferred()

# The local human: Player node + keyboard/mouse input + pilot; flies `mech` when given
# (null = a late rejoiner whose mech is gone: the picker or spectating follows).
func _make_local_player(t: int, lives: int, mech: Node) -> void:
	_player = Node.new()
	_player.set_script(load("res://scripts/Player.gd"))
	_player.name = "Player"
	_player.set("team", t)
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
	_players.append(_player)
	_player.set("lives", lives)
	hud.squad_slot_selected.connect(_on_squad_slot_selected)
	hud.spawn_selected.connect(_on_spawn_selected)
	if mech == null:
		return
	_player.call("possess", mech)
	mech.make_camera_current()
	mech.died.connect(Callable(_player, "on_pawn_destroyed"))
	mech.mark_requested.connect(_on_mark_requested)
	_spectated_mech = mech
	mech.died.connect(_on_spectated_mech_died)
	mech.died.connect(_on_local_mech_died_mp)

## T217: (alive, total) players on `team`: one per roster entry however many mechs it
## has used; alive = its current mech is in the fight.
func team_counts(team: int) -> Vector2i:
	var roster: Array = Game.mp_active_match["roster"]
	var out := Vector2i.ZERO
	for ri in roster.size():
		if int(roster[ri].get("team", -1)) != team:
			continue
		out.y += 1
		for m in _team_mechs[team]:
			if is_instance_valid(m) and m.roster_idx == ri and not m.is_dead and m.visible:
				out.x += 1
				break
	return out

# HUD bars, beacons and minimap from `team`'s side, following `mech` (own or spectated).
func _setup_hud(team: int, mech: Node) -> void:
	_local_team = team
	hud.arena = self  # T217: team counts
	hud.setup(match_node, mech, team)
	var ally_mechs: Array = []
	for m in _team_mechs[team]:
		if m != mech:
			ally_mechs.append(m)
	hud.setup_bot_bars(_team_mechs[1 - team])
	hud.setup_ally_bars(ally_mechs)
	hud.setup_beacon_bars(get_tree().get_nodes_in_group("beacons"))
	hud.setup_minimap(self, team, _map.center, _map.minimap_half,
		_map.minimap_outline(), get_tree().get_nodes_in_group("beacons"))











func _wire_beacons() -> void:
	for child in _map.get_children():
		if child.is_in_group("beacons"):
			var n3d := child as Node3D
			n3d.position.y = _map.ground_y(n3d.position.x, n3d.position.z)
			match_node.register_beacon(child)
			child.captured.connect(func(team: int): _beacons_captured[team] += 1)

# Attach a NavigationAgent3D directly to the mech so path queries use its position.
func _add_nav_agent(mech: Node) -> void:
	var nav_agent := NavigationAgent3D.new()
	nav_agent.name = "NavAgent"
	nav_agent.path_desired_distance = 1.5
	nav_agent.target_desired_distance = 2.5
	mech.add_child(nav_agent)

func _spawn_bot_player(mech: CharacterBody3D, team: int, idx: int) -> Node:
	_add_nav_agent(mech)

	var p := Node.new()
	p.set_script(load("res://scripts/Player.gd"))
	p.name = "BotPlayer_%d_%d" % [team, idx]
	p.set("team", team)
	add_child(p)
	var ai_input := Node.new()
	ai_input.set_script(load("res://scripts/AIInputSource.gd"))
	# T169: unique per bot. Unset, every bot seeded 0 ^ match_seed -> one shared RNG
	# stream -> the same role for all (all defenders ~1 match in 4: bots camp own beacons).
	ai_input.bot_id = 1 + team * 100 + idx  # set before add_child: _ready seeds from it
	p.add_child(ai_input)
	p.set("input_source", ai_input)
	p.call("possess", mech)
	mech.died.connect(Callable(p, "on_pawn_destroyed"))
	_players.append(p)
	return p

func _on_spectated_mech_died() -> void:
	if _match_over:
		return
	for m in _team_mechs[_local_team]:
		if is_instance_valid(m) and m.visible and m != _spectated_mech:
			_switch_spectator(m)
			return

func _create_spectator_camera() -> void:
	_spec_pivot = Node3D.new()
	_spec_arm = SpringArm3D.new()
	_spec_arm.spring_length = 5.0
	_spec_arm.collision_mask = 1
	_spec_arm.position = Vector3.ZERO
	_spec_pivot.add_child(_spec_arm)
	_spec_cam = Camera3D.new()
	_spec_cam.position = Vector3(0, 0, 5)
	_spec_arm.add_child(_spec_cam)
	add_child(_spec_pivot)

func _switch_spectator(m: Node) -> void:
	if _spectated_mech != null and is_instance_valid(_spectated_mech):
		if _spectated_mech.died.is_connected(_on_spectated_mech_died):
			_spectated_mech.died.disconnect(_on_spectated_mech_died)
	_spectated_mech = m
	if _spec_pivot == null:
		_create_spectator_camera()
		# Initialise yaw from the mech's current facing so there is no jump.
		var torso: Node3D = m.get_node_or_null("Torso")
		_spec_yaw = torso.global_rotation.y if torso else m.global_rotation.y
	_spec_cam.make_current()
	m.died.connect(_on_spectated_mech_died)
	hud.start_spectating(m)

func _cycle_spectator() -> void:
	var alive: Array = []
	for m in _team_mechs[_local_team]:
		if is_instance_valid(m) and m.visible:
			alive.append(m)
	if alive.size() <= 1:
		return
	var idx: int = alive.find(_spectated_mech)
	_switch_spectator(alive[(idx + 1) % alive.size()])

func _process(_delta: float) -> void:
	_check_host_silence()  # T214
	if _spec_pivot == null or _spectated_mech == null or not is_instance_valid(_spectated_mech):
		return
	# Position pivot at the mech's camera-arm world position for a stable anchor.
	var arm: SpringArm3D = _spectated_mech.get("camera_arm")
	if arm != null:
		_spec_pivot.global_position = arm.global_position
	# Apply player mouse input to the spectator yaw/pitch.
	var input_src = _player.get("input_source") if _player != null else null
	if input_src != null:
		var look: Vector2 = input_src.call("get_look_delta")
		var sens: float = Game.settings.get("mouse_sensitivity", 0.003)
		_spec_yaw   -= look.x * sens
		_spec_pitch  = clamp(_spec_pitch - look.y * sens, -1.2, 0.4)
	_spec_pivot.rotation.y = _spec_yaw
	_spec_arm.rotation.x   = _spec_pitch
	_spec_arm.position.x = 1.3 * Game.shoulder  # T196: spectate over the same shoulder

func _input(event: InputEvent) -> void:
	if DEBUG_OVERHEAD and event is InputEventKey and event.pressed and event.keycode == KEY_F5:
		_toggle_overhead()
		return
	if _spec_pivot != null and event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_cycle_spectator()
		return
	if event.is_action_pressed("ui_cancel") and not _match_over and not _start_pick_open:  # T187
		get_viewport().set_input_as_handled()  # PauseMenu must not see this same Esc
		_toggle_pause()

func _toggle_pause() -> void:
	if pause_menu.visible:
		_on_pause_resume()
		return
	# T161: SP pauses the match; MP can't pause a shared simulation (a host pause
	# would freeze the server for everyone), so it only opens the menu.
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_menu.show()

func _on_pause_resume() -> void:
	pause_menu.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_pause_quit() -> void:
	if _movement_logger != null:
		_movement_logger.stop_and_analyze()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		Game._clear_mp_session()  # T184: SP match state (roster/lobby) ends with the match
	else:
		# V40 exception (B-g/B-f): a local quit from an MP match closes the peer FIRST
		# (else the server keeps streaming RPCs into an Arena we no longer have).
		Game.disconnect_mp()
	# T186: the hangar for MP too -- FIND MATCH there reaches HOST / JOIN again (T176)
	get_tree().change_scene_to_file("res://scenes/ui/Hangar.tscn")

func on_player_eliminated(p: Node) -> void:
	if not multiplayer.is_server():
		return  # T185: match end is server-side (T40); a client's own count must not end it
	var losing_team: int = p.get("team") if p.get("team") != null else 0
	print("[Arena] %s eliminated (team %d)." % [p.name, losing_team])
	# Only end the match when the entire team has been wiped out.
	for pl in _players:
		if pl.get("team") == losing_team and (pl.get("lives") == null or pl.get("lives") > 0):
			return
	match_node.force_end(1 - losing_team)

func _on_match_ended(winning_team: int) -> void:
	_match_over = true
	if Game.sync_logging_enabled:
		Game.sync_log_event("match_end", "", {"winner": winning_team})  # T155 loop_audio
	if _movement_logger != null:
		_movement_logger.stop_and_analyze()
	# Disable all mechs (deferred so in-flight _physics_process finishes first - B17).
	for team_mechs in _team_mechs:
		for m in team_mechs:
			if is_instance_valid(m):
				m.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
	if multiplayer.is_server():  # SP = offline server: same stats + result path (T184)
		var stats := _build_mp_stats()
		if not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):  # V56: MP only
			Game._mp_return_confirmations.clear()
			Game._mp_return_deadline = Time.get_ticks_msec() * 0.001 + 30.0
			Game.set_process(true)
		Game._rpc_match_end.rpc(winning_team, stats)
	# Clients: _on_mp_match_ended fires via Game.match_ended_mp signal.

func _build_mp_stats() -> Array:
	var stats: Array = []
	var roster: Array = Game.mp_active_match["roster"]
	for ri in roster.size():
		var entry: Dictionary = roster[ri]
		var peer_id: int = entry.get("peer_id", 0)
		var t: int = entry.get("team", 0)
		# T168: whole squad's totals (dead mechs stay in _team_mechs, hidden).
		var dealt := 0.0
		var taken := 0.0
		for m in _team_mechs[t]:
			if is_instance_valid(m) and m.roster_idx == ri:
				dealt += m.damage_dealt_total
				taken += m.damage_taken_total
		var pre_elo: int = 0
		if peer_id != 0 and Game.mp_lobby["peers"].has(peer_id):
			pre_elo = Game.mp_lobby["peers"][peer_id].get("elo", 0)
		stats.append({
			"peer_id":      peer_id,
			"kills":        0,
			"team":         t,
			"dealt":        dealt,
			"taken":        taken,
			"captures":     _beacons_captured[t] if t >= 0 and t < _beacons_captured.size() else 0,
			"pre_elo":      pre_elo,
			"disconnected": _disconnected_peers.has(peer_id),
		})
	return stats

func _on_peer_disconnected_in_match(id: int) -> void:
	if not multiplayer.is_server():
		return
	var tok: String = Game.mp_lobby["peers"].get(id, {}).get("token", "")
	if tok != "" and not _match_over:
		_held[tok] = {"old": id, "t": Time.get_ticks_msec() * 0.001}  # T206: slot held HOLD_S
	if _match_over or _disconnected_peers.has(id):
		return  # T167: the silence check may have taken over already
	for team in range(2):
		for mech in _team_mechs[team]:
			if not is_instance_valid(mech) or mech.get("is_dead"):
				continue
			if mech.owner_peer_id != id:
				continue
			_bot_ify_disconnected_mech(mech, id)
	_disconnected_peers[id] = true

func _bot_ify_disconnected_mech(mech: CharacterBody3D, peer_id: int) -> void:
	if mech.get_node_or_null("NavAgent") == null:
		_add_nav_agent(mech)
	var ai_input := Node.new()
	ai_input.set_script(load("res://scripts/AIInputSource.gd"))
	ai_input.bot_id = peer_id
	# AIInputSource reads get_parent().get("pawn") — must be parented to the Player node.
	var remote_player: Node = null
	for p in _players:
		if p.name == "RemotePlayer_%d" % peer_id:
			remote_player = p
			break
	if remote_player != null:
		remote_player.add_child(ai_input)
		remote_player.set("input_source", ai_input)
		remote_player.call("possess", mech)
	else:
		mech.add_child(ai_input)
		mech.set_input_source(ai_input)
	ai_input.set_mp_seed(match_node.match_seed ^ peer_id)

# ---- T206: late join + rejoin ----
# A peer joining mid-match gets the live match during the auth handshake (Game._on_mp_auth):
# every mech in _team_mechs order (snapshots address mechs by that index), beacons, scores,
# used squad slots, remote lives. It spectates -- or, if its token belongs to a player who
# dropped < HOLD_S ago (the bot has been flying that mech, T123), it takes the slot back:
# roster, mechs, slots and lobby entry move to the new peer id on every peer.
const HOLD_S := 30.0
var _held: Dictionary = {}  # server: token -> {old: peer id, t: s}

func late_state(token: String) -> Dictionary:
	var mechs: Array = []
	for t in 2:
		for m in _team_mechs[t]:
			if not is_instance_valid(m):
				mechs.append({"t": t, "def": ""})
				continue
			var spawn: Array = m.get_meta("spawn", ["", []])
			mechs.append({"t": t, "name": String(m.name), "def": spawn[0], "w": spawn[1],
				"owner": m.owner_peer_id, "ri": m.roster_idx, "dead": bool(m.is_dead),
				"hp": m.health, "pos": m.global_position})
	var beacons: Array = []
	for b in get_tree().get_nodes_in_group("beacons"):
		beacons.append([String(b.name), b.owner_team, b.state, b._capture_progress])
	var lives := {}
	for p in _players:
		if String(p.name).begins_with("RemotePlayer_"):
			lives[int(String(p.name).substr(13))] = p.get("lives")
	var old := 0
	var h = _held.get(token)
	if h != null and Time.get_ticks_msec() * 0.001 - float(h["t"]) <= HOLD_S:
		old = int(h["old"])
	return {"map_path": Game.mp_active_match["map_path"], "roster": Game.mp_active_match["roster"],
		"match_seed": Game.mp_active_match["match_seed"], "mechs": mechs, "beacons": beacons,
		"scores": (match_node.get("scores") as Array).duplicate(), "slot_used": _peer_slot_used.duplicate(true),
		"lives": lives, "rejoin_old": old}

# Server: the late joiner finished the handshake.
func late_join_connected(id: int, token: String) -> void:
	var h = _held.get(token)
	if h == null or Time.get_ticks_msec() * 0.001 - float(h["t"]) > HOLD_S:
		print("[Arena] late join: peer %d spectates" % id)
		return
	_held.erase(token)
	print("[Arena] rejoin: peer %d takes back the slot of %d" % [id, int(h["old"])])
	_rpc_reassign.rpc(int(h["old"]), id)

# Joiner: build the match as the server has it (the roster came with it, Game).
func _apply_late_state(st: Dictionary) -> void:
	var me := int(st["you"])
	var old := int(st.get("rejoin_old", 0))
	if old > 0:
		_remap_peer(old, me)
	for e in st["mechs"]:
		var def = ResourceLoader.load(e["def"]) if String(e["def"]) != "" else null
		if def == null:
			_team_mechs[int(e["t"])].append(null)
			continue
		var m: CharacterBody3D = _spawn_one_mech(def, int(e["t"]), 0, 1, e["w"], e["name"])
		var owner: int = int(e["owner"])
		m.owner_peer_id = me if old > 0 and owner == old else owner
		m.roster_idx = int(e["ri"])
		m.health = float(e["hp"])
		m.position = e["pos"]
		if e["dead"]:
			m.is_dead = true
			m.visible = false
			m.process_mode = Node.PROCESS_MODE_DISABLED
			(m.get_node("CollisionShape3D") as CollisionShape3D).disabled = true
	_peer_slot_used = st["slot_used"]
	if old > 0 and _peer_slot_used.has(old):
		_peer_slot_used[me] = _peer_slot_used[old]
		_peer_slot_used.erase(old)

func _apply_late_beacons(st: Dictionary) -> void:
	for b in st["beacons"]:
		var node := _map.get_node_or_null(String(b[0]))
		if node != null:
			node.call("_sync_state", int(b[1]), int(b[2]), float(b[3]))
	match_node.set("scores", st["scores"])

func _setup_late_player(st: Dictionary) -> void:
	var me := multiplayer.get_unique_id()
	for entry in Game.mp_active_match["roster"]:
		if int(entry.get("peer_id", 0)) != me:
			continue
		var t: int = entry["team"]
		var mine: Node = null
		for m in _team_mechs[t]:
			if is_instance_valid(m) and m.owner_peer_id == me and not m.is_dead:
				mine = m
		var lives: int = int(st["lives"].get(int(st["rejoin_old"]), _squad_lives(entry)))
		_make_local_player(t, lives, mine)
		if mine != null:
			player_mech = mine
			_setup_hud(t, mine)
			mine.damaged.connect(hud.show_damage)
			for weapon in mine.get_weapons():
				if weapon.has_signal("hit_confirmed"):
					weapon.hit_confirmed.connect(hud.register_hit)
		else:
			_late_spectate(t)
			if lives > 0:
				_on_local_mech_died_mp()  # its mech died while it was away: the picker
		print("[Arena] rejoined as peer %d (mech %s, lives %d)" % [me, mine.name if mine else "none", lives])
		return
	_late_spectate(0)

func _late_spectate(team: int) -> void:
	for t in [team, 1 - team]:
		for m in _team_mechs[t]:
			if is_instance_valid(m) and not m.is_dead:
				_setup_hud(team, m)
				_switch_spectator(m)
				return

# Peer `old` came back as `new`: its roster entry, mechs and slots follow it (V35 T206).
func _remap_peer(old: int, new: int) -> void:
	for entry in Game.mp_active_match["roster"]:
		if int(entry.get("peer_id", 0)) == old:
			entry["peer_id"] = new
	for t in 2:
		for m in _team_mechs[t]:
			if is_instance_valid(m) and m.owner_peer_id == old:
				m.owner_peer_id = new
	if _peer_slot_used.has(old):
		_peer_slot_used[new] = _peer_slot_used[old]
		_peer_slot_used.erase(old)

@rpc("authority", "call_local", "reliable")
func _rpc_reassign(old: int, new: int) -> void:
	_remap_peer(old, new)  # the joiner applied it already; a no-op there
	if not multiplayer.is_server():
		return
	_disconnected_peers.erase(old)
	var lobby: Dictionary = Game.mp_lobby["peers"]
	if lobby.has(old):
		var e: Dictionary = lobby[old]
		lobby.erase(old)
		e["ready"] = false
		lobby[new] = e
	var rp := get_node_or_null("RemotePlayer_%d" % old)
	if rp == null:
		return
	rp.name = "RemotePlayer_%d" % new
	for t in 2:
		for m in _team_mechs[t]:
			if is_instance_valid(m) and m.owner_peer_id == new and not m.is_dead:
				var ai: Node = rp.get("input_source")
				var net_input := Node.new()
				net_input.set_script(load("res://scripts/NetworkInputSource.gd"))
				rp.add_child(net_input)
				rp.set("input_source", net_input)
				rp.call("possess", m)
				m.last_input_ms = Time.get_ticks_msec()
				if ai != null and ai != net_input:
					ai.queue_free()

func _on_mp_match_ended(winner_team: int, stats: Array) -> void:
	_last_snapshot_ms = 0  # T214: the stream stops at match end by design
	# T205/T206: the server froze every mech (_on_match_ended); a predicting client stops too
	if not multiplayer.is_server() and is_instance_valid(player_mech):
		player_mech.call("snap_to_server")  # T270: where the server froze it, not where we predicted
		player_mech.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
	hud.hide_squad_picker_mp()
	hud.show_result_mp(winner_team, stats)
	print("[Arena] MP match over. Team %d wins." % winner_team)

# T167 (B59): a client that crashes or loses its link stops streaming input (every 2nd
# tick, V47). ENet needs ~20 s to time it out (Game.PEER_TIMEOUT_MS notes why it can't be
# cut further); after this much silence the bot takes the mech (T123); ENet drops the
# dead peer itself later. Outages shorter than this (outage_recovery: 1.5 s) ride through.
# ponytail: no kick (disconnect_peer on a dead peer floods 'Unable to send packet' until
# ENet gives up); a client that merely froze 5 s keeps watching its bot -- kick + reason
# message if that ever matters.
const INPUT_SILENCE_MS := 5000
# T269 (B106): a mech whose owner has never sent input is timed from the first live check
# that saw it (since T245 a client sends nothing until its first snapshot, so one that
# dies before that never set last_input_ms and was skipped until ENet's 45 s timeout).
# Per mech, not from match start: a late joiner's / respawned mech gets the same grace.
var _silence_since: Dictionary = {}  # mech instance id -> first live check with no input yet

func _check_input_silence() -> void:
	if _match_over:
		return
	var now := Time.get_ticks_msec()
	for team in range(2):
		for m in _team_mechs[team]:
			if not is_instance_valid(m) or m.get("is_dead"):
				continue
			var pid: int = m.owner_peer_id
			var last: int = m.last_input_ms
			if last == 0 and pid >= 2:
				last = int(_silence_since.get(m.get_instance_id(), now))
				_silence_since[m.get_instance_id()] = last
			if pid < 2 or _disconnected_peers.has(pid) or now - last < INPUT_SILENCE_MS:
				continue
			print("[Arena] peer %d silent for %d ms: bot takes over" % [pid, now - last])
			_on_peer_disconnected_in_match(pid)

# T127: show squad picker when local mech dies and lives remain.
func _on_local_mech_died_mp() -> void:
	if _match_over or _player == null:
		return
	if _player.get("lives") <= 0:
		# T128: squad exhausted — spectate an alive teammate until match ends.
		for m in _team_mechs[_local_team]:
			if is_instance_valid(m) and m.visible and m != player_mech:
				_switch_spectator(m)
				return
		return
	var my_id := multiplayer.get_unique_id()
	if not _peer_slot_used.has(my_id):
		return
	var squad: Array = []
	for entry in Game.mp_active_match["roster"]:
		if entry.get("peer_id", 0) == my_id:
			squad = entry["squad"]
			break
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_squad_picker_mp(squad, _peer_slot_used[my_id])

# Server-side validation and dispatch for squad slot selection (V35, V41).
func _process_pick_next_mech(sender: int, slot_idx: int, spawn: int) -> void:
	if not _peer_slot_used.has(sender):
		push_error("[Arena] _process_pick_next_mech: unknown sender %d" % sender)
		return
	var slot_used: Array = _peer_slot_used[sender]
	if slot_idx < 0 or slot_idx >= slot_used.size():
		push_error("[Arena] _process_pick_next_mech: invalid slot %d for %d" % [slot_idx, sender])
		return
	if slot_used[slot_idx]:
		push_error("[Arena] _process_pick_next_mech: slot %d already used by %d" % [slot_idx, sender])
		return
	var roster: Array = Game.mp_active_match["roster"]
	var squad: Array = []
	var peer_team := -1
	for entry in roster:
		if entry.get("peer_id", 0) == sender:
			squad = entry["squad"]
			peer_team = entry.get("team", -1)
			break
	if squad.is_empty() or slot_idx >= squad.size():
		return
	if squad[slot_idx].get("mech", "") == "":
		push_error("[Arena] _process_pick_next_mech: empty mech at slot %d for %d" % [slot_idx, sender])
		return
	if spawn < 0 or spawn >= spawn_points(peer_team).size():
		push_error("[Arena] _process_pick_next_mech: invalid spawn %d for %d" % [spawn, sender])
		return
	_peer_slot_used[sender][slot_idx] = true
	_rpc_spawn_next_mech.rpc(sender, slot_idx, peer_team, spawn)

# Client -> server: request next squad mech (V41).
@rpc("any_peer", "reliable")
func _rpc_pick_next_mech(slot_idx: int, spawn: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	_process_pick_next_mech(sender, slot_idx, spawn)

# Server -> all: spawn a peer's next squad mech (V35).
@rpc("authority", "call_local", "reliable")
func _rpc_spawn_next_mech(peer_id: int, slot_idx: int, team: int, spawn: int) -> void:
	var roster: Array = Game.mp_active_match["roster"]
	var squad: Array = []
	var team_size: int = 0
	var roster_idx := -1
	var tidx := 0  # lane in the spawn line: the entry's place in its team (T203; was the slot)
	for ri in roster.size():
		var entry: Dictionary = roster[ri]
		if entry.get("peer_id", 0) == peer_id:
			squad = entry["squad"]
			roster_idx = ri
			tidx = team_size
		if entry.get("team", -1) == team:
			team_size += 1
	if squad.is_empty() or slot_idx >= squad.size():
		return
	var mech_path: String = squad[slot_idx].get("mech", "")
	if mech_path == "":
		return
	var mech_def = ResourceLoader.load(mech_path)
	if mech_def == null:
		push_error("[Arena] _rpc_spawn_next_mech: cannot load '%s'" % mech_path)
		return
	if _peer_slot_used.has(peer_id) and slot_idx < _peer_slot_used[peer_id].size():
		_peer_slot_used[peer_id][slot_idx] = true  # B80: clients' pickers read their own copy
	var wpn_paths: Array = squad[slot_idx].get("weapons", [])
	if spawn < 0 or spawn >= spawn_points(team).size():
		spawn = 0
	var new_mech: CharacterBody3D = _spawn_one_mech(mech_def, team, tidx, team_size, wpn_paths,
		"Mech_r%d_s%d" % [roster_idx, slot_idx], spawn)
	new_mech.owner_peer_id = peer_id
	new_mech.roster_idx = roster_idx
	var my_id := multiplayer.get_unique_id()
	if peer_id == my_id:
		player_mech = new_mech
		if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
			new_mech.apply_pilot_skills()
		_player.call("possess", new_mech)
		# T185 (B76): before _on_local_mech_died_mp, which reads the lives this decrements.
		# Missing, only the first squad mech cost a life: the picker came back after the
		# last one and the team could never be eliminated.
		new_mech.died.connect(Callable(_player, "on_pawn_destroyed"))
		new_mech.mark_requested.connect(_on_mark_requested)
		new_mech.damaged.connect(hud.show_damage)
		new_mech.died.connect(_on_local_mech_died_mp)
		# Audit #27: mirror _setup_players_mp -- without this, landing hits after
		# a squad respawn no longer flashes the hit-confirm X.
		for weapon in new_mech.get_weapons():
			if weapon.has_signal("hit_confirmed"):
				weapon.hit_confirmed.connect(hud.register_hit)
		# Reconnect spectated-mech died tracking without switching to spec cam.
		if _spectated_mech != null and is_instance_valid(_spectated_mech):
			if _spectated_mech.died.is_connected(_on_spectated_mech_died):
				_spectated_mech.died.disconnect(_on_spectated_mech_died)
		_spectated_mech = new_mech
		new_mech.died.connect(_on_spectated_mech_died)
		if _spec_cam != null and is_instance_valid(_spec_cam):
			_spec_cam.current = false
		new_mech.make_camera_current()
		hud.hide_squad_picker_mp()
		hud.stop_spectating()
		hud.switch_player_mech(new_mech)
	elif multiplayer.is_server():
		var net_input := Node.new()
		net_input.set_script(load("res://scripts/NetworkInputSource.gd"))
		net_input.name = "NetInput_%d_%d" % [peer_id, slot_idx]
		for p in _players:
			if p.name == "RemotePlayer_%d" % peer_id:
				p.add_child(net_input)
				p.set("input_source", net_input)
				p.call("possess", new_mech)
				new_mech.died.connect(Callable(p, "on_pawn_destroyed"))
				break
	_refresh_team_bars(team)

# ---- T187: first mech pick ----
# Everyone still spawns in squad slot 0 (harness, oracles and snapshot order rely on it);
# the local player then gets the squad picker over the live start. Keeping slot 0 just
# closes it; another slot retires the first mech (no death, no life lost, its slot back
# in the pool) and spawns the pick through the normal respawn path. SP pauses until the
# pick; MP closes the picker after START_PICK_S (keeps slot 0) so nobody stalls a match.
const START_PICK_S := 10.0
var _start_pick_open := false
var _start_picked: Dictionary = {}  # server: peer_id -> true once its start pick is spent

func _my_squad() -> Array:
	for entry in Game.mp_active_match["roster"]:
		if entry.get("peer_id", 0) == multiplayer.get_unique_id():
			return entry["squad"]
	return []

func _open_start_pick() -> void:
	var my_id := multiplayer.get_unique_id()
	if _player == null or player_mech == null or not _peer_slot_used.has(my_id) or Game.has_node("MPHarness"):
		return  # scripted runs drive slot 0 from tick 0 and check the HUD
	var squad := _my_squad()
	if squad.filter(func(sq) -> bool: return sq.get("mech", "") != "").size() < 2:
		return
	_start_pick_open = true
	# T216: the mech you're standing in waits for the pick (MP doesn't pause): no input
	# until the start + spawn pick close (_close_start_pick hands it back)
	player_mech.set_input_source(null)
	var used: Array = _peer_slot_used[my_id].duplicate()
	used[0] = false  # the mech you're standing in is a choice too
	hud.show_squad_picker_mp(squad, used, "SELECT FIRST MECH")
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		(hud.get("_squad_picker") as Node).process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().paused = true
	else:
		get_tree().create_timer(START_PICK_S).timeout.connect(func() -> void:
			if _start_pick_open:  # a mech already chosen still goes in, at spawn 0
				_send_pick(maxi(_pending_slot, 0), 0))

func _close_start_pick() -> void:
	_start_pick_open = false
	_pending_slot = -1
	hud.hide_squad_picker_mp()
	hud.hide_spawn_picker()
	if _player != null and is_instance_valid(player_mech) and not player_mech.is_dead:
		_player.call("possess", player_mech)  # T216: input back (a swap re-possesses the new one)
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# T203: mech first, then where: the squad picker hands over to the spawn picker (the
# minimap, full size), and the pair goes to the server together.
var _pending_slot := -1

func _on_squad_slot_selected(si: int) -> void:
	_pending_slot = si
	hud.hide_squad_picker_mp()
	hud.show_spawn_picker(spawn_points(_local_team))

func _on_spawn_selected(sp: int) -> void:
	var si := _pending_slot
	if si < 0:
		return
	_pending_slot = -1
	hud.hide_spawn_picker()
	_send_pick(si, sp)

func _send_pick(si: int, sp: int) -> void:
	var my_id := multiplayer.get_unique_id()
	if _start_pick_open:
		_close_start_pick()
		if si == 0 and sp == 0:
			return  # keep the mech you're in, where it stands
		if multiplayer.is_server():
			_process_start_pick(my_id, si, sp)
		else:
			_rpc_start_pick.rpc_id(1, si, sp)
	elif multiplayer.is_server():
		_process_pick_next_mech(my_id, si, sp)
	else:
		_rpc_pick_next_mech.rpc_id(1, si, sp)

# Server: one swap per peer, only out of an untouched first mech, only early.
# Slot 0 at another spawn = the same mech, moved (retire + respawn, no life lost).
func _process_start_pick(sender: int, slot: int, spawn: int) -> void:
	if _match_over or _start_picked.has(sender) or not _peer_slot_used.has(sender):
		return
	_start_picked[sender] = true
	var used: Array = _peer_slot_used[sender]
	var squad: Array = []
	var team := -1
	for entry in Game.mp_active_match["roster"]:
		if entry.get("peer_id", 0) == sender:
			squad = entry["squad"]
			team = entry.get("team", -1)
	if team < 0 or slot < 0 or slot >= used.size() or (slot > 0 and used[slot]) or slot >= squad.size() \
			or squad[slot].get("mech", "") == "" or match_node.elapsed > START_PICK_S + 2.0 \
			or spawn < 0 or spawn >= spawn_points(team).size() or (slot == 0 and spawn == 0):
		return
	var first_idx := -1
	for i in _team_mechs[team].size():
		var m: Node = _team_mechs[team][i]
		if is_instance_valid(m) and m.owner_peer_id == sender and not m.get("is_dead"):
			first_idx = i
	if first_idx < 0 or _team_mechs[team][first_idx].health < _team_mechs[team][first_idx].max_health:
		return  # no swapping out of a fight
	_rpc_retire_first_mech.rpc(sender, team, first_idx)
	_rpc_spawn_next_mech.rpc(sender, slot, team, spawn)

# Client -> server: start pick (V41: server validates).
@rpc("any_peer", "reliable")
func _rpc_start_pick(slot: int, spawn: int) -> void:
	if multiplayer.is_server():
		_process_start_pick(multiplayer.get_remote_sender_id(), slot, spawn)

# Server -> all: the first mech leaves without a death (no life, no VFX); slot 0 is free again.
@rpc("authority", "call_local", "reliable")
func _rpc_retire_first_mech(peer_id: int, team: int, idx: int) -> void:
	if idx < 0 or idx >= _team_mechs[team].size():
		return
	var m: Node = _team_mechs[team][idx]
	m.is_dead = true  # out of snapshots, targeting and input-silence checks
	m.visible = false
	m.process_mode = Node.PROCESS_MODE_DISABLED
	(m.get_node("CollisionShape3D") as CollisionShape3D).set_deferred("disabled", true)
	if _peer_slot_used.has(peer_id):
		_peer_slot_used[peer_id][0] = false

func _refresh_team_bars(team: int) -> void:
	if team == _local_team:
		var ally_mechs: Array = []
		for m in _team_mechs[team]:
			if m != player_mech:
				ally_mechs.append(m)
		hud.setup_ally_bars(ally_mechs)
	else:
		hud.setup_bot_bars(_team_mechs[team])

func _squad_lives(entry: Dictionary) -> int:
	var n := 0
	for sq in entry.get("squad", []):
		if sq.get("mech", "") != "":
			n += 1
	return maxi(1, n)

# ---- T198: bot squads ----
# A dead bot comes back in its next squad mech after about the time a human spends in
# the picker. Physics-tick timer (deterministic in ticks, V-determinism) and pause-aware.
const BOT_RESPAWN_S := 3.0
var _bot_slot_next: Dictionary = {}  # roster_idx -> next squad slot to try

func _on_bot_mech_died(bp: Node, ri: int) -> void:
	if _match_over or bp.get("lives") <= 0:
		return
	await get_tree().create_timer(BOT_RESPAWN_S, false, true).timeout
	if _match_over or not is_instance_valid(bp):
		return
	var squad: Array = Game.mp_active_match["roster"][ri]["squad"]
	var slot: int = _bot_slot_next.get(ri, 1)
	while slot < squad.size() and squad[slot].get("mech", "") == "":
		slot += 1
	if slot >= squad.size():
		return
	_bot_slot_next[ri] = slot + 1
	_rpc_spawn_next_bot.rpc(ri, slot, bot_spawn(Game.mp_active_match["roster"][ri]["team"]))

# T203: a bot spawns where its team is needed: near beacons the team doesn't hold
# (neutral, enemy, contested), away from enemies already standing there. Server-only
# (beacon state + positions are authoritative there), result rides the spawn RPC.
const SPAWN_THREAT_R := 40.0
func bot_spawn(team: int) -> int:
	var best := 0
	var best_s := -INF
	var pts := spawn_points(team)
	for i in pts.size():
		var p: Vector3 = pts[i]
		var s := 0.0
		for b in get_tree().get_nodes_in_group("beacons"):
			if b.get("state") != team + 1:
				s += 30.0 / (30.0 + p.distance_to(b.global_position))
		for m in _team_mechs[1 - team]:
			if is_instance_valid(m) and not m.is_dead and p.distance_to(m.global_position) < SPAWN_THREAT_R:
				s -= 0.5
		if s > best_s:
			best_s = s
			best = i
	return best

# Server -> all: spawn a bot's next squad mech (same order on every peer: snapshots
# address mechs by their index in _team_mechs).
@rpc("authority", "call_local", "reliable")
func _rpc_spawn_next_bot(ri: int, slot: int, spawn: int) -> void:
	var roster: Array = Game.mp_active_match["roster"]
	if ri < 0 or ri >= roster.size() or slot >= roster[ri]["squad"].size():
		return
	var entry: Dictionary = roster[ri]
	var mech_def = ResourceLoader.load(entry["squad"][slot].get("mech", ""))
	if mech_def == null:
		push_error("[Arena] _rpc_spawn_next_bot: cannot load squad slot %d of roster %d" % [slot, ri])
		return
	var team: int = entry["team"]
	var team_size := 0
	var tidx := -1
	for i in roster.size():
		if roster[i].get("team", -1) == team:
			if i == ri:
				tidx = team_size
			team_size += 1
	if spawn < 0 or spawn >= spawn_points(team).size():
		spawn = 0
	var m: CharacterBody3D = _spawn_one_mech(mech_def, team, tidx, team_size,
		entry["squad"][slot].get("weapons", []), "Mech_r%d_s%d" % [ri, slot], spawn)
	m.owner_peer_id = 0
	m.roster_idx = ri
	var bp: Node = get_node_or_null("BotPlayer_%d_%d" % [team, tidx])
	if bp != null:
		_add_nav_agent(m)
		bp.call("possess", m)
		m.died.connect(Callable(bp, "on_pawn_destroyed"))
		if multiplayer.is_server():
			m.died.connect(_on_bot_mech_died.bind(bp, ri))
	_refresh_team_bars(team)

# T203: spawn height = the real floor under the spot. The Penrose terraces don't follow
# the bowl formula's circles exactly: a lane near a riser spawned mechs inside the step above
# (stuck, falling in place). The match-start spawn runs before the floor exists = formula.
func _ground_y(x: float, z: float) -> float:
	var y0 := _map.ground_y(x, z)
	if not is_inside_tree():
		return y0
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, y0 + 4.5, z), Vector3(x, y0 - 4.0, z))
	var ex: Array[RID] = []
	for m in get_tree().get_nodes_in_group("mechs"):
		ex.append((m as CollisionObject3D).get_rid())
	q.exclude = ex
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if not hit.is_empty() else y0




func _on_mark_requested(pos: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.0)
	mat.emission_energy_multiplier = 3.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.4
	mesh.height = 0.8
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	mi.position = pos + Vector3(0, 0.4, 0)
	add_child(mi)

func _create_nav_region() -> void:
	_nav_region = NavigationRegion3D.new()
	var nav_mesh := NavigationMesh.new()
	# Agent dimensions: mechs are ~3m tall and 2m wide; keep radius snug so
	# bots fit through Penrose wall gaps.
	nav_mesh.agent_radius     = 0.75  # whole cells: Godot ceils to cell_size (0.8 -> 1.5 m)
	nav_mesh.agent_height     = 3.9   # 13 x cell_height
	# B67: a mech steps up at most Mech._MAX_STEP (0.37 m); the old 2.2 m climb let paths
	# run up ledges no mech can climb. 0.6 m (2 cells) still reaches every beacon by stairs.
	nav_mesh.agent_max_climb  = 0.6
	nav_mesh.agent_max_slope  = 60.0
	# 0.75m cells give good wall-gap resolution without blowing up bake time.
	nav_mesh.cell_size        = 0.75
	nav_mesh.cell_height      = 0.3
	# B67: the default source is the region's own children (none) -> 0 polygons, every
	# bot path came back empty and bots steered straight into walls. Bake from the
	# arena's static colliders instead (mechs are CharacterBody3D, not parsed).
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nav_mesh.geometry_source_group_name = &"nav_source"
	add_to_group(&"nav_source")
	_nav_region.navigation_mesh = nav_mesh
	add_child(_nav_region)
	# Bake on a background thread so the first frame isn't blocked.
	_nav_region.bake_finished.connect(func():
		print("[Arena] NavMesh baked OK"))
	_nav_region.bake_navigation_mesh(true)

func _start_snapshot_timer() -> void:
	var t := Timer.new()
	t.name = "SnapshotTimer"
	t.wait_time = 1.0 / 20.0
	t.autostart = true
	t.timeout.connect(_snapshot_tick)
	add_child(t)

func _snapshot_tick() -> void:
	if not Game.mp_live:
		return  # T159/V52: a client hasn't loaded Arena yet, or everyone is leaving
	_check_input_silence()
	var snapshots: Array = []
	var st := Time.get_ticks_msec() * 0.001  # T150: server send time, the interpolation timeline
	for team in range(2):
		for idx in range(_team_mechs[team].size()):
			var m = _team_mechs[team][idx]
			if not is_instance_valid(m) or m.get("is_dead"):
				continue
			var e := {
				"st": st,
				"team": team,
				"idx": idx,
				"pos": m.global_position,
				"quat": m.global_transform.basis.get_rotation_quaternion(),
				"vel": m.velocity,
				"torso_y": m.torso.rotation.y,
			}
			if m.owner_peer_id > 1:  # T205: a client's mech -> its prediction's reference
				e["ack"] = m.input_ack
				e["ackt"] = m.input_ack_ticks
			snapshots.append(e)
	if snapshots.is_empty():
		return
	_rpc_snapshot.rpc(snapshots)

# T150: client clock offset = min(receive - server send) ~ clock offset + minimum
# one-way delay. Mapping server send times through it strips network jitter from
# the interpolation timeline. Relaxes upward slowly so clock drift can't strand it.
var _snap_clock_offset: float = INF

# T214 (B90): a client notices a dead or unreachable server by silence: the server streams
# snapshots at 20 Hz all match long, so this long without one means it's gone (ENet's own
# timeout is a 45 s backstop now, Game.PEER_TIMEOUT_MS). Armed by the first snapshot (a
# client waits silently for live), off at match end (the stream stops by design).
const HOST_SILENCE_MS := 6000
var _last_snapshot_ms := 0

func _check_host_silence() -> void:
	if _last_snapshot_ms == 0 or _match_over or multiplayer.is_server() \
			or not multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		return
	if Time.get_ticks_msec() - _last_snapshot_ms > HOST_SILENCE_MS:
		_last_snapshot_ms = 0
		print("[Arena] no snapshot from the server for %.0f s: leaving" % (HOST_SILENCE_MS / 1000.0))
		Game._leave_server()

@rpc("authority", "unreliable_ordered")
func _rpc_snapshot(snapshots: Array) -> void:
	_last_snapshot_ms = Time.get_ticks_msec()  # T214
	Game.server_heard = true  # B101: the server has us connected; our input may flow
	var now := Time.get_ticks_msec() * 0.001
	var st: float = float(snapshots[0].get("st", now)) if not snapshots.is_empty() else now
	_snap_clock_offset = minf(_snap_clock_offset + 0.0002, now - st)
	var local_t := st + _snap_clock_offset
	for entry in snapshots:
		var t: int = entry.get("team", -1)
		var i: int = entry.get("idx", -1)
		if t < 0 or t >= 2 or i < 0 or i >= _team_mechs[t].size():
			continue
		var m = _team_mechs[t][i]
		if is_instance_valid(m):
			m.receive_snapshot(entry, local_t)

