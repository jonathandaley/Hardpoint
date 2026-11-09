extends Node
# T319 probe (HUMAN_FOUND 2026-11-05: "Targeting reticule should aim for center mass, instead of the
# current spot (appears constant, so it's a little low on a pegasus and very low on a vesuvius)"):
# every roster mech has a centre mass in the middle of its own visible body -- inside its collision
# capsule (local y 0..2) so rays aimed at it still hit, and not one fixed height for all -- and the
# soft-lock box, homing rockets, the arc, bot aim and lock-on all aim there.
# B125 (T339): with every weapon family mounted the centre stays inside the capsule sideways too --
# Seeker's big forward-hung heavy machine gun pulled it 0.84 m out in front of the body, so the
# arc's ray (which ends there) met nothing and homing missiles flew past it.

const ROSTER := ["Everest", "Kestrel", "Pegasus", "Seeker", "Hornet", "Vesuvius", "Slip", "Hippogriff", "Cesh"]
const FAMILIES := ["AerialStrike", "ArcWeapon", "LaserCannon", "MachineGun", "MissileLauncher", "Patience",
	"Rifle", "RocketLauncher", "Shotgun", "Sniper"]
const USERS := {"res://scripts/HUD.gd": "eligible box", "res://scripts/HomingProjectile.gd": "rockets",
	"res://scripts/ArcWeapon.gd": "arc", "res://scripts/AIInputSource.gd": "bot aim", "res://scripts/Mech.gd": "lock-on"}

func _ready() -> void:
	await get_tree().process_frame
	var bad: Array = []
	var ys: Array = []
	for n in ROSTER:
		var md: Resource = load("res://resources/mechs/%s.tres" % n)
		var m: Node3D = md.scene.instantiate()
		m.scale = Vector3.ONE * md.body_scale
		MechVisuals.apply(m, n)
		add_child(m)
		m.set_physics_process(false)
		if not m.has_method("center_mass"):
			bad.append("Mech has no center_mass()")
			m.free()
			break
		var y: float = m.to_local(m.call("center_mass")).y
		ys.append(y)
		if y < 0.6 or y > 1.8:
			bad.append("%s centre mass at local y %.2f, outside its body / capsule" % [n, y])
		for fam in FAMILIES:
			var paths: Array = []
			for sl in md.weapon_slots:
				var p := "res://scenes/weapons/%s%s.tscn" % [fam, "Heavy" if int(sl.slot_size) == 1 else "Light"]
				paths.append(p if ResourceLoader.exists(p) else "")
			MechVisuals.arm_display(m, md, paths)
			var c: Vector3 = m.to_local(m.call("center_mass"))
			if Vector2(c.x, c.z).length() > 0.45 or c.y < 0.1 or c.y > 1.9:  # capsule r 0.5, y 0..2
				bad.append("%s with %s: centre mass %s, outside its hit capsule" % [n, fam, c])
		m.free()
	if ys.size() == ROSTER.size() and ys.max() - ys.min() < 0.2:
		bad.append("centre mass is the same height on every mech (%s)" % str(ys))
	for path in USERS:
		var src: String = (load(path) as Script).source_code
		if not src.contains("center_mass"):
			bad.append("%s (%s) doesn't aim at centre mass" % [USERS[path], path.get_file()])
	if not bad.is_empty():
		push_error("[probe] center_mass FAIL: " + "; ".join(bad))
		get_tree().quit(1)
		return
	print("[probe] center_mass done (local y %.2f .. %.2f)" % [ys.min(), ys.max()])
	get_tree().quit(0)
