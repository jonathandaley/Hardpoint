extends Node
# T319 probe (HUMAN_FOUND 2026-11-05: "Targeting reticule should aim for center mass, instead of the
# current spot (appears constant, so it's a little low on a pegasus and very low on a vesuvius)"):
# every roster mech has a centre mass in the middle of its own visible body -- inside its collision
# capsule (local y 0..2) so rays aimed at it still hit, and not one fixed height for all -- and the
# soft-lock box, homing rockets, the arc, bot aim and lock-on all aim there.

const ROSTER := ["Everest", "Kestrel", "Pegasus", "Seeker", "Hornet", "Vesuvius", "Slip", "Hippogriff", "Cesh"]
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
