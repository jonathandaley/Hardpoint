extends Node
# T238 probe (HUMAN_FOUND_ISSUES 2026-11-04: "Slip's weapon mount is too big, and its guns
# are way too small. The mount should be subtle and the gun impressive"): Slip's default gun
# renders >= MIN_LEN_X its normal length, the kit mount + socket boxes are under MOUNT_FRAC
# of the gun's volume, and the gun sits on the mount (not sunk into the torso, not floating).

const MIN_LEN_X := 1.6
const MOUNT_FRAC := 0.25
const MechKit := preload("res://scripts/MechKit.gd")

func _fail(msg: String) -> void:
	push_error("[probe] slip_gun: " + msg)

func _gun_box(md: Resource, ws: float) -> AABB:
	var m: Node3D = md.scene.instantiate()
	m.scale = Vector3.ONE * md.body_scale
	MechVisuals.apply(m, "Slip")
	add_child(m)
	m.set_physics_process(false)
	m.weapon_scale = ws
	m.configure_weapons(md.weapon_slots)
	var torso: Node3D = m.get("torso")
	var inv := torso.global_transform.affine_inverse()
	var gun := AABB()
	var first := true
	for hp in torso.get_children():
		if hp.name.begins_with("Hardpoint"):
			for mi in hp.find_children("*", "MeshInstance3D", true, false):
				var n := mi as MeshInstance3D
				if n.mesh != null and n.is_visible_in_tree():
					var b: AABB = inv * n.global_transform * n.get_aabb()
					gun = b if first else gun.merge(b)
					first = false
	m.free()
	return gun

func _ready() -> void:
	var md: Resource = load("res://resources/mechs/Slip.tres")
	var gun := _gun_box(md, md.weapon_scale)
	var plain := _gun_box(md, 1.0)
	var mount_vol := 0.0
	var mount_top := -INF
	for b in MechKit.DATA["Slip"]["torso"]:
		if b[9] == "MO" or b[9] == "SO":
			mount_vol += float(b[0]) * float(b[1]) * float(b[2])
			mount_top = maxf(mount_top, float(b[4]) + float(b[1]) * 0.5)
	var gun_vol := gun.size.x * gun.size.y * gun.size.z
	if gun.size.z < plain.size.z * MIN_LEN_X:
		_fail("gun %.2f m long, %.2f unscaled (want >= x%.1f)" % [gun.size.z, plain.size.z, MIN_LEN_X])
	if mount_vol > gun_vol * MOUNT_FRAC:
		_fail("mount %.3f m3 vs gun %.3f m3 (want under %.0f%%)" % [mount_vol, gun_vol, MOUNT_FRAC * 100.0])
	if gun.position.y < mount_top - 0.15 or gun.position.y > mount_top + 0.1:
		_fail("gun bottom at %.2f, mount top at %.2f: sunk or floating" % [gun.position.y, mount_top])
	print("[probe] slip_gun done (gun %.2f m long vs %.2f, mount %.0f%% of gun volume, bottom %.2f / mount top %.2f)" % [
		gun.size.z, plain.size.z, 100.0 * mount_vol / gun_vol, gun.position.y, mount_top])
	get_tree().quit(0)
