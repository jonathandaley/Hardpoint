extends Node
# T296 probe: on every roster mech, the drawn laser beam and arc bolt end where the shot lands
# (within 0.3 m) -- the beam lives under the weapon, so the weapon's scale (weapon_scale 1.3 on
# five mechs since T265, body_scale) must not stretch or shrink it.

const SlotDef := preload("res://scripts/WeaponSlotDef.gd")
const Lobby := preload("res://scripts/Lobby.gd")

func _fail(msg: String) -> void:
	push_error("[probe] beam_reach FAIL: " + msg)
	get_tree().quit(1)

func _place(m: Node3D, p: Vector3) -> void:
	m.global_position = p - (m.call("center_mass") - m.global_position)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bad: Array = []
	var rows: Array = []
	for path in Lobby.ROSTER:
		Game.mp_active_match["roster"] = []
		Game.loadout["team_size"] = 1
		Game.loadout["sp_bots"] = [0, 1]
		Game.loadout["mode"] = "deathmatch"
		Game.loadout["squad"] = [path]
		Game.loadout["mech_def"] = load(path)
		var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
		get_tree().root.add_child.call_deferred(arena)
		for i in 2:
			await get_tree().process_frame
		if arena.get("_start_pick_open"):
			arena.get("hud").squad_slot_selected.emit(0)
			arena.get("hud").spawn_selected.emit(0)
		for i in 5:
			await get_tree().physics_frame
		var me: CharacterBody3D = arena.get("player_mech")
		var foe: Node3D = arena.get("_team_mechs")[1 - int(me.get("team"))][0]
		foe.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		foe.process_mode = Node.PROCESS_MODE_DISABLED
		me.invincible = true
		var fwd: Vector3 = -(me.get("torso") as Node3D).global_transform.basis.z
		fwd = Vector3(fwd.x, 0, fwd.z).normalized()
		for wpath in ["res://scenes/weapons/LaserCannonLight.tscn", "res://scenes/weapons/ArcWeaponLight.tscn"]:
			var slot := SlotDef.new()
			slot.slot_size = 0
			slot.position = me.get_weapons()[0].position if not me.get_weapons().is_empty() else Vector3(0, 2.0, 0)
			slot.weapon_scene = load(wpath)
			me.configure_weapons([slot])
			await get_tree().physics_frame
			var w: Node3D = me.get_weapons()[0]
			_place(foe, w.global_position + fwd * 20.0)
			for i in 2:
				await get_tree().physics_frame
			var end_drawn: Vector3
			var end_hit: Vector3
			if wpath.contains("Laser"):
				var cam: Camera3D = me.get("camera")
				cam.look_at(foe.call("center_mass"))
				w.call("_do_fire")
				var beam: MeshInstance3D = w.get("_beam")
				end_drawn = beam.global_transform * Vector3(0, 0, -0.5)
				var ray: Dictionary = w.call("_crosshair_ray")
				end_hit = ray["pos"]
			else:
				me.set("locked_target", foe)
				w.call("_do_fire")
				w.call("_redraw_bolt")  # what _process draws each frame the bolt shows
				var bolt: MeshInstance3D = w.get("_beam_mesh")
				var pts: PackedVector3Array = w.get("_bolt_points")
				end_drawn = bolt.global_transform * pts[pts.size() - 1]
				end_hit = w.global_position + (w.get("_beam_pivot") as Node3D).global_transform.basis.z.normalized() * -float(w.get("_beam_len"))
			var off := end_drawn.distance_to(end_hit)
			rows.append("%s %s %.2f m (scale %.2f)" % [path.get_file().get_basename(), wpath.get_file().get_basename(), off, w.global_transform.basis.get_scale().x])
			if off > 0.3:
				bad.append(rows[-1])
		arena.queue_free()
		for i in 3:
			await get_tree().process_frame
	if not bad.is_empty():
		_fail("the drawn beam ends away from the hit: " + ", ".join(bad))
		return
	print("[probe] beam_reach done (%s)" % ", ".join(rows))
	get_tree().quit(0)
