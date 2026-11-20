class_name OrbitalStrike
extends "res://scripts/WeaponBase.gd"
# T522 (user 2026-11-19: "Orbital Strike: replace aerial. Just a transponder. Makes an antenna bloop graphic,
# locks on. Big circle target graphic centered on locked target's position at time of fire, doesn't move.
# 10 seconds later, big boom from above."): needs a lock (as the aerial strike did). Firing marks the
# ground under the locked target -- fixed, shown to everyone as a big ring -- and DELAY_S later the
# strike lands: area damage from full at the centre to edge_damage at the rim (server), a beam from
# the sky and an explosion everywhere. Anyone who walks out of the ring in time is safe: the
# counterplay. Bots step out of an enemy ring they stand in (AIInputSource._strike_escape).
# Numbers are mine (calibration knobs): radius 10 m, 350 -> 120, 10 s, reload 18 s.

const DELAY_S := 10.0
const RING_COLOR := Color(1.0, 0.25, 0.15, 0.75)
const BLOOP_COLOR := Color(0.55, 0.9, 1.0)

@export var strike_radius: float = 10.0
@export var edge_damage: float = 120.0  # `damage` is the centre hit

## Strikes on their way, every peer: [ground point, radius, seconds left, team, ring node].
static var pending: Array = []

func fire() -> void:
	if owner_mech == null or owner_mech.get("locked_target") == null:
		return
	super.fire()

func _do_fire() -> void:
	var t := owner_mech.get("locked_target") as Node3D
	if not is_instance_valid(t):
		return
	var at := _ground_under(t.global_position)
	var team := int(owner_mech.get("team"))
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		_rpc_mark.rpc(at, team)
	_mark(at, team)

@rpc("authority", "reliable")
func _rpc_mark(at: Vector3, team: int) -> void:
	if not is_inside_tree() or multiplayer.is_server():  # a straggler for a weapon already gone does nothing
		return
	_mark(at, team)

## Every peer: the antenna bloop at the weapon, the ring on the ground, the countdown.
func _mark(at: Vector3, team: int) -> void:
	var fx: Node = VFX._fx()
	if fx != null and is_inside_tree():
		var p := global_position + Vector3.UP * 0.6
		fx.sphere(p, p, 0.15, 1.6, BLOOP_COLOR, 0.0, 0.0, 0.45)  # bloop: a pulse growing out
		fx.sphere(p, p, 0.1, 0.9, BLOOP_COLOR, 0.0, 0.0, 0.3, 0.25)  # and a second, smaller one
	var ring := _make_ring(at)
	var entry := [at, strike_radius, DELAY_S, team, ring]
	pending.append(entry)
	_count_down(entry)

func _count_down(entry: Array) -> void:
	var tree := get_tree()
	var scene := tree.current_scene
	while float(entry[2]) > 0.0:
		await tree.process_frame
		if not is_instance_valid(scene) or tree.current_scene != scene:
			pending.erase(entry)
			return  # the match is gone
		entry[2] = float(entry[2]) - get_process_delta_time() if is_inside_tree() else float(entry[2]) - 1.0 / 60.0
		var ring: Node3D = entry[4]
		if is_instance_valid(ring):  # pulses faster as it comes
			var k := 1.0 - float(entry[2]) / DELAY_S
			ring.scale = Vector3.ONE * (1.0 + 0.04 * sin(Time.get_ticks_msec() * 0.001 * (4.0 + 20.0 * k)))
	pending.erase(entry)
	if is_instance_valid(entry[4]):
		(entry[4] as Node).queue_free()
	_land(entry[0], int(entry[3]))

## The strike: the beam and the boom everywhere; the damage on the server.
func _land(at: Vector3, team: int) -> void:
	var fx: Node = VFX._fx()
	if fx != null:
		fx.beam(at + Vector3.UP * 120.0, at, 3.0, 0.2, Color(1.0, 0.9, 0.7), 0.0, 0.5)
		fx.sphere(at, at, 1.0, strike_radius * 0.8, Color(1.0, 0.85, 0.6), 0.0, 0.0, 0.35)
	VFX.death_explosion(at)
	SoundManager.play_sfx("explosion", at)
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	for m in get_tree().get_nodes_in_group("mechs"):
		if not is_instance_valid(m) or m.get("is_dead") or int(m.get("team")) == team:
			continue
		var d: float = (m as Node3D).global_position.distance_to(at)
		if d > strike_radius:
			continue
		m.call("take_damage", lerpf(damage, edge_damage, d / strike_radius), self)

func _ground_under(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.0, p + Vector3.DOWN * 50.0)
	q.exclude = owner_mech.get_exclude_rids() if owner_mech != null else []
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.get("position", p)

func _make_ring(at: Vector3) -> Node3D:
	if Game.dedicated:
		return null
	var root := Node3D.new()
	for r in [strike_radius, strike_radius * 0.5]:
		var mi := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r - 0.35
		tm.outer_radius = r
		tm.rings = 48
		tm.ring_segments = 4
		mi.mesh = tm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = RING_COLOR
		m.no_depth_test = true  # seen through terrain: it must read from anywhere
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	get_tree().current_scene.add_child(root)
	root.global_position = at + Vector3.UP * 0.15
	return root
