extends Node3D
# T317 probe (HUMAN_FOUND 2026-11-05: "Make sure muzzle flash is actually at the end of the
# barrel and not at its base. Make its size proportional to the barrel"): for every kit weapon,
# light and heavy, at x1 and x1.8 mech weapon_scale, the muzzle point sits on the model's front
# face, and firing puts the flash there with a radius that follows the barrel width.

const WeaponVisuals := preload("res://scripts/WeaponVisuals.gd")
const WEAPONS := ["RifleLight", "RifleHeavy", "SniperLight", "SniperHeavy", "MachineGunLight", "MachineGunHeavy",
	"ShotgunLight", "ShotgunHeavy", "MissileLauncherLight", "MissileLauncherHeavy", "LaserCannonLight",
	"LaserCannonHeavy", "ArcWeaponLight", "ArcWeaponHeavy", "RocketLauncherLight", "AerialStrikeHeavy", "PatienceHeavy"]

func _ready() -> void:
	await get_tree().process_frame
	var bad: Array = []
	var report: Array = []
	for wname in WEAPONS:
		for mult in [1.0, 1.8]:
			var w: Node3D = (load("res://scenes/weapons/%s.tscn" % wname) as PackedScene).instantiate()
			WeaponVisuals.apply(w, mult)
			add_child(w)
			var front := INF
			for mi in w.find_children("*", "MeshInstance3D", false, false):
				var bb: AABB = (mi as MeshInstance3D).transform * (mi as MeshInstance3D).get_aabb()
				front = minf(front, bb.position.z)
			var mz = w.get("muzzle_local")
			var bw = w.get("barrel_w")
			if not (mz is Vector3) or (mz as Vector3) == Vector3.ZERO or bw == null or float(bw) <= 0.0:
				bad.append("%s x%.1f: no muzzle point / barrel width" % [wname, mult])
			elif absf((mz as Vector3).z - front) > 0.02:
				bad.append("%s x%.1f: muzzle at z %.2f, the model's front is %.2f" % [wname, mult, (mz as Vector3).z, front])
			else:
				if mult == 1.0 and wname.ends_with("Heavy"):
					report.append("%s %.2f m / %.2f" % [wname.trim_suffix("Heavy"), -(mz as Vector3).z, float(bw)])
				var before := get_children().size()
				w.call("_muzzle_flash", false)
				var flash: Array = get_children().slice(before)
				var want: Vector3 = w.to_global(mz)
				if flash.is_empty() or (flash[0] as Node3D).global_position.distance_to(want) > 0.01:
					bad.append("%s x%.1f: no flash at the muzzle" % [wname, mult])
				elif absf((flash[0] as Node3D).scale.x * 0.14 - float(bw) * 1.2) > 0.01:
					bad.append("%s x%.1f: flash radius %.3f, barrel %.3f" % [wname, mult, (flash[0] as Node3D).scale.x * 0.14, float(bw)])
			w.free()
	if not bad.is_empty():
		push_error("[probe] muzzle_tip FAIL: " + "; ".join(bad.slice(0, 6)))
		get_tree().quit(1)
		return
	print("[probe] muzzle_tip done (heavy tip / barrel: %s)" % ", ".join(report))
	get_tree().quit(0)
