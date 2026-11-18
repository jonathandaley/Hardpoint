class_name Mortar
extends "res://scripts/WeaponBase.gd"
# T458 (user 2026-11-17: "add as many mechs as you think are good. Also maps and weapons."): lobs a
# shell on a high ballistic arc onto the aim point (out to `range`): over walls, onto targets with
# no line of sight. The server solves the launch velocity for a flight time that grows with the
# distance (always a high arc), so the shell lands where it was aimed; it bursts there (direct hit
# + splash, Projectile.explode). Bots lob at their target itself (they may not see it); a player
# lobs at what the crosshair is on, and sees a ring where the shell will land (only on their own
# screen). Every peer sees the shell fly (reliable: one every few seconds, worth seeing).

const PROJECTILE_SCENE := preload("res://scenes/weapons/ProjectileGrey.tscn")
const G := 20.0  # m/s^2 on the shell (Projectile.gravity_y)
const SHELL_SCALE := 4.0  # the bullet sphere grown into a shell you can follow in the sky

static func _shell_look(p: Node) -> void:
	var mesh := p.get_node_or_null("Mesh") as Node3D
	if mesh != null:
		mesh.scale = Vector3(SHELL_SCALE, SHELL_SCALE, SHELL_SCALE * 1.6)
@export var splash_radius: float = 5.0
@export var splash_damage: float = 50.0
var lobs := true  # AIInputSource: fire without a clear line (T458)

static func flight_time(dist: float) -> float:
	return 1.6 + dist / 60.0

## The launch velocity from `from` that lands on `to` after flight_time(horizontal distance).
static func launch_velocity(from: Vector3, to: Vector3) -> Vector3:
	var dv := to - from
	var t := flight_time(Vector2(dv.x, dv.z).length())
	return Vector3(dv.x / t, (dv.y + 0.5 * G * t * t) / t, dv.z / t)

func _muzzle() -> Vector3:
	return to_global(muzzle_local) if muzzle_local != Vector3.ZERO else global_position

## Where this mortar would land now: a bot's target, else what the camera ray hits; inside `range`.
func aim_point() -> Vector3:
	var src: Node = owner_mech.get("_input_source") if owner_mech != null else null
	var tgt = src.get("_target") if src != null and "_target" in src else null
	var p: Vector3
	if tgt is Node3D and is_instance_valid(tgt):
		p = (tgt as Node3D).global_position
	else:
		var cam := owner_mech.get("camera") as Camera3D if owner_mech != null else null
		if cam == null:
			return global_position
		var fwd := -cam.global_transform.basis.z
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + fwd * (range + 40.0))
		q.exclude = owner_mech.get_exclude_rids()
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		p = hit.position if not hit.is_empty() else cam.global_position + fwd * (range + 40.0)
	var d := Vector2(p.x - global_position.x, p.z - global_position.z)
	if d.length() > range:
		var c := Vector2(global_position.x, global_position.z) + d.normalized() * range
		p = Vector3(c.x, p.y, c.y)
	return p

func _do_fire() -> void:
	if owner_mech == null:
		return
	launch_at(aim_point())

## Server: one shell from the muzzle onto `to`.
func launch_at(to: Vector3) -> void:
	var from := _muzzle()
	var v := launch_velocity(from, to)
	var team_i: int = owner_mech.get("team") if owner_mech.get("team") != null else 0
	var proj := PROJECTILE_SCENE.instantiate() as Projectile
	proj.damage = damage
	proj.speed = v.length()
	proj.gravity_y = G
	proj.lifetime = flight_time(Vector2(to.x - from.x, to.z - from.z).length()) + 1.5
	proj.team = team_i
	proj._exclude_rids = owner_mech.get_exclude_rids()
	proj.splash_radius = splash_radius
	proj.splash_damage = splash_damage
	proj.explode = true
	proj.smoke_trail = true
	proj.owner_body = owner_mech
	proj.source_weapon = self
	proj.on_hit = func(body, pos): _emit_hit_if_visible(body, pos, true)
	_shell_look(proj)
	get_tree().current_scene.add_child(proj)
	proj.global_transform = Transform3D(Projectile.basis_along(v), from)
	SoundManager.play_sfx("mortar_fire", from, multiplayer.has_multiplayer_peer() and multiplayer.is_server())
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_shell.rpc(from, v, proj.lifetime, team_i)

@rpc("authority", "reliable")
func _rpc_shell(from: Vector3, v: Vector3, lifetime: float, team_i: int) -> void:
	if not is_inside_tree() or multiplayer.is_server():  # V50 / B130
		return
	var ghost := PROJECTILE_SCENE.instantiate() as Projectile
	ghost.is_ghost = true
	ghost.speed = v.length()
	ghost.gravity_y = G
	ghost.lifetime = lifetime
	ghost.team = team_i
	ghost.explode = true
	ghost.splash_radius = splash_radius
	ghost.smoke_trail = true
	if owner_mech != null:
		ghost._exclude_rids = owner_mech.get_exclude_rids()
	_shell_look(ghost)
	get_tree().current_scene.add_child(ghost)
	ghost.global_transform = Transform3D(Projectile.basis_along(v), from)

# ---- the landing ring: the local player's own mortar only ----
var _ring: MeshInstance3D

func _process(_delta: float) -> void:
	var src: Node = owner_mech.get("_input_source") if owner_mech != null else null
	var mine: bool = src != null and src.has_method("is_human_input") and src.is_human_input() \
			and not owner_mech.get("is_dead") and is_visible_in_tree()
	if not mine:
		if _ring != null:
			_ring.visible = false
		return
	if _ring == null:
		_ring = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = splash_radius - 0.25
		tm.outer_radius = splash_radius
		tm.rings = 32
		tm.ring_segments = 4
		_ring.mesh = tm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1.0, 0.55, 0.15, 0.7)
		m.no_depth_test = true
		_ring.material_override = m
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ring.top_level = true
		add_child(_ring)
	_ring.visible = true
	_ring.global_position = aim_point() + Vector3(0, 0.15, 0)
