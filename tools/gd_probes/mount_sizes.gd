extends Node
# T265 probe (HUMAN_FOUND 2026-11-05: "General weapon mount size/weapon size checkup"): on
# every roster mech, at its weapon_scale, the kit mount boxes under each gun are under half
# the gun's volume -- the gun reads clearly bigger than what holds it (it failed on Kestrel's
# shoulder (1.37x) and Cesh (0.68x) before; mid-size mechs' light guns went to x1.3).

const MechKit := preload("res://scripts/MechKit.gd")
const ROSTER := ["Everest", "Kestrel", "Pegasus", "Seeker", "Hornet", "Vesuvius", "Slip", "Hippogriff", "Cesh"]
const MAX_RATIO := 0.55  # Everest 0.52: heavy guns out of deliberately chunky shoulder pods (render-checked 2026-11-06)

func _ready() -> void:
	var bad := false
	var report: Array = []
	for name in ROSTER:
		var md: Resource = load("res://resources/mechs/%s.tres" % name)
		var m: Node3D = md.scene.instantiate()
		m.scale = Vector3.ONE * md.body_scale
		MechVisuals.apply(m, name)
		add_child(m)
		m.set_physics_process(false)
		m.weapon_scale = md.weapon_scale
		m.configure_weapons(md.weapon_slots)
		var torso: Node3D = m.get("torso")
		var inv := torso.global_transform.affine_inverse()
		var mounts: Array = []
		for b in MechKit.DATA[name]["torso"]:
			if b[9] == "MO" or b[9] == "SO":
				mounts.append(AABB(Vector3(b[3], b[4], b[5]) - Vector3(b[0], b[1], b[2]) * 0.5, Vector3(b[0], b[1], b[2])))
		var worst := 0.0
		for hp in torso.get_children():
			if not hp.name.begins_with("Hardpoint"):
				continue
			var gun := AABB()
			var first := true
			for mi in hp.find_children("*", "MeshInstance3D", true, false):
				var n := mi as MeshInstance3D
				if n.mesh != null:
					var bb: AABB = inv * n.global_transform * n.get_aabb()
					gun = bb if first else gun.merge(bb)
					first = false
			if first:
				continue
			var vol := 0.0
			for mb: AABB in mounts:
				var ox := minf(mb.end.x, gun.end.x) - maxf(mb.position.x, gun.position.x)
				var oz := minf(mb.end.z, gun.end.z) - maxf(mb.position.z, gun.position.z)
				if ox > 0.0 and oz > 0.0:
					vol += mb.size.x * mb.size.y * mb.size.z
			var ratio := vol / maxf(gun.size.x * gun.size.y * gun.size.z, 0.0001)
			worst = maxf(worst, ratio)
			if ratio > MAX_RATIO:
				push_error("[probe] mount_sizes FAIL: %s %s mount %.2fx the gun's volume (want < %.1f)" % [name, hp.name, ratio, MAX_RATIO])
				bad = true
		report.append("%s %.2f" % [name, worst])
		m.free()
	if bad:
		get_tree().quit(1)
		return
	print("[probe] mount_sizes done (worst mount/gun: %s)" % ", ".join(report))
	get_tree().quit(0)
