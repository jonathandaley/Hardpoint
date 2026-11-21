class_name Mortar
extends "res://scripts/WeaponBase.gd"
# T458 (user 2026-11-17: "add as many mechs as you think are good. Also maps and weapons."): lobs a
# shell on a high ballistic arc onto the aim point (out to `range`): over walls, onto targets with
# no line of sight. The server solves the launch velocity for a flight time that grows with the
# distance (always a high arc), so the shell lands where it was aimed; it bursts there (direct hit
# + splash, Projectile.explode). Bots lob at their target itself (they may not see it). T532 (user
# 2026-11-20): a player's range is a setting -- the mouse wheel / up-down arrows step it (Mech.lob_range,
# sent with their input) -- and the direction is their horizontal aim only (looking up or down changes
# nothing); a glowing down arrow that fog doesn't hide marks the landing spot, on their screen only.
# Every peer sees the shell fly (reliable: one every few seconds, worth seeing).

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
const LOB_MIN := 8.0       # m (T532)
const LOB_DEFAULT := 40.0  # m: a fresh mech's range
const LOB_STEP := 4.0      # m per wheel notch

## T532: `cur` (Mech.lob_range, < 0 = unset) moved by `steps` wheel notches, inside [LOB_MIN, range].
func step_range(cur: float, steps: float) -> float:
	return clampf(lob_distance(cur) + steps * LOB_STEP, LOB_MIN, range)

func lob_distance(cur: float) -> float:
	return clampf(cur if cur >= 0.0 else LOB_DEFAULT, LOB_MIN, range)

static func flight_time(dist: float) -> float:
	return 1.6 + dist / 60.0

## The launch velocity from `from` that lands on `to` after flight_time(horizontal distance).
static func launch_velocity(from: Vector3, to: Vector3) -> Vector3:
	var dv := to - from
	var t := flight_time(Vector2(dv.x, dv.z).length())
	return Vector3(dv.x / t, (dv.y + 0.5 * G * t * t) / t, dv.z / t)

func _muzzle() -> Vector3:
	return to_global(muzzle_local) if muzzle_local != Vector3.ZERO else global_position

## Where this mortar would land now: a bot's target; else the pilot's range (Mech.lob_range) along their
## horizontal aim, dropped onto whatever is below (ground or roof).
func aim_point() -> Vector3:
	var src: Node = owner_mech.get("_input_source") if owner_mech != null else null
	var tgt = src.get("_target") if src != null and "_target" in src else null
	if tgt is Node3D and is_instance_valid(tgt):
		var p := (tgt as Node3D).global_position
		var d := Vector2(p.x - global_position.x, p.z - global_position.z)
		if d.length() > range:
			var c := Vector2(global_position.x, global_position.z) + d.normalized() * range
			p = Vector3(c.x, p.y, c.y)
		return p
	if owner_mech == null:
		return global_position
	var fwd := -(owner_mech.get("torso") as Node3D).global_transform.basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var at := global_position + flat * lob_distance(float(owner_mech.get("lob_range")))
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 80.0, at + Vector3.DOWN * 150.0)
	q.exclude = owner_mech.get_exclude_rids()
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else Vector3(at.x, owner_mech.global_position.y, at.z)

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

# ---- the landing marker (T532): the local player's own mortar only ----
var _marker: Node3D

## The aim arrow shows through walls/terrain? (user 2026-11-21: "Seeing it through terrain might be part of
## the problem ... toggle it off so I can see if that's part of it") -- off for now; true brings it back.
const ARROW_THROUGH_WALLS := false

## T549 (user 2026-11-21: "Mortar is still too hard to aim. Keep the arrow, but make it bigger, and paint a
## target on the ground under it. Have the arrow go above mechs like it does for terrain"): child 0 "Arrow"
## (2x the T532 one) and child 1 "Target" (rings at the splash radius and half, and a cross) flat on the
## ground; each one merged mesh -> 2 draws. The root sits on the ground point; the arrow lifts over a mech.
static func _arrow(radius := 5.0) -> Node3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # full-bright: reads as glowing
	m.albedo_color = Color(1.0, 0.6, 0.15)
	m.disable_fog = true   # the user: "ignores fog"
	m.no_depth_test = ARROW_THROUGH_WALLS
	m.render_priority = 10
	var root := Node3D.new()
	var head := CylinderMesh.new()  # a cone, point down, tip on the spot
	head.top_radius = 1.8
	head.bottom_radius = 0.0
	head.height = 2.4
	head.radial_segments = 4  # chunky
	head.rings = 1
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.8, 2.8, 0.8)
	var ring_parts: Array = []
	for r in [radius, radius * 0.5]:
		var tm := TorusMesh.new()
		tm.inner_radius = r - 0.3
		tm.outer_radius = r
		tm.rings = 24
		tm.ring_segments = 4
		ring_parts.append([tm, Transform3D(Basis(), Vector3(0, 0.15, 0))])
	var bar := BoxMesh.new()
	bar.size = Vector3(radius * 2.0, 0.06, 0.3)
	ring_parts.append([bar, Transform3D(Basis(), Vector3(0, 0.15, 0))])
	ring_parts.append([bar, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 0.15, 0))])
	for spec in [["Arrow", [[head, Transform3D(Basis(), Vector3(0, 1.2, 0))],
			[shaft, Transform3D(Basis(), Vector3(0, 3.8, 0))]]], ["Target", ring_parts]]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part in spec[1]:
			st.append_from(part[0], 0, part[1])
		var mi := MeshInstance3D.new()
		mi.name = spec[0]
		mi.mesh = st.commit()
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root

## T549: how far above point `g` the arrow rides -- over the top of any mech standing there (its 2 m hit
## capsule is shorter than the body, so the ground ray alone buries the arrow in it), else 0.
func marker_lift(g: Vector3) -> float:
	var top := g.y
	for m in get_tree().get_nodes_in_group("mechs"):
		if m == owner_mech or not is_instance_valid(m) or m.get("is_dead"):
			continue
		var p := (m as Node3D).global_position
		if Vector2(p.x - g.x, p.z - g.z).length() < 2.0 * (m as Node3D).global_transform.basis.get_scale().x:
			# ponytail: twice the body centre's height ~ the top; a real top if a tall mech pokes through
			top = maxf(top, 2.0 * (m.call("center_mass") as Vector3).y - p.y)
	return top - g.y

func _process(_delta: float) -> void:
	var src: Node = owner_mech.get("_input_source") if owner_mech != null else null
	var mine: bool = src != null and src.has_method("is_human_input") and src.is_human_input() \
			and not owner_mech.get("is_dead") and is_visible_in_tree()
	if not mine:
		if _marker != null:
			_marker.visible = false
		return
	if _marker == null:
		_marker = _arrow(splash_radius)
		_marker.top_level = true
		add_child(_marker)
	_marker.visible = true
	var g := aim_point()
	_marker.global_position = g
	(_marker.get_child(0) as Node3D).position.y = marker_lift(g)

func damage_range() -> Vector2:  # T538: splash alone .. direct + splash
	return Vector2(splash_damage, damage + splash_damage)

func damage_text() -> String:
	return "%s direct + %s splash (r %s m)" % [num(damage), num(splash_damage), num(splash_radius)]
