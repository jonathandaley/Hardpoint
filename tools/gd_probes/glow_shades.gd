extends Node
# T255 attempt 2 probe (user 2026-11-05: "slight variations in the glowing/emissive parts
# of the mechs that are already glowing. No adding anything new"): on every glowing kit
# mech the glow boxes show more than one shade, all within 0.05 hue of each other (slight,
# not recoloured); no textured (armor/detail) material glows. Glow box counts are in the
# done line -- they must match the pre-T255 counts (nothing new added).

const ROSTER := ["Everest", "Kestrel", "Pegasus", "Seeker", "Hornet", "Vesuvius", "Slip", "Hippogriff", "Cesh"]

func _fail(msg: String) -> void:
	push_error("[probe] glow_shades FAIL: " + msg)

func _ready() -> void:
	var bad := false
	var report: Array = []
	for mech_name in ROSTER:
		var md: Resource = load("res://resources/mechs/%s.tres" % mech_name)
		if md == null:
			continue
		var m: Node3D = md.scene.instantiate()
		MechVisuals.apply(m, mech_name)
		add_child(m)
		var glow: Array = []
		var base := Color.BLACK
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var mat := (mi as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
			if mat == null or not mat.emission_enabled:
				continue
			if mat.albedo_texture != null:
				_fail("%s: a textured (armor/detail) material glows" % mech_name)
				bad = true
			glow.append(mat)
		var shades := {}
		for mat: StandardMaterial3D in glow:
			shades[mat.albedo_color.to_html()] = mat.albedo_color
		report.append("%s %d boxes %d shades" % [mech_name, glow.size(), shades.size()])
		if glow.size() >= 2 and shades.size() < 2:
			_fail("%s: %d glow boxes, all one shade" % [mech_name, glow.size()])
			bad = true
		var cols: Array = shades.values()
		for c: Color in cols:
			var c0: Color = cols[0]
			if absf(c.h - c0.h) > 0.05 and absf(c.h - c0.h) < 0.95:
				_fail("%s: glow shades differ in hue by %.3f" % [mech_name, absf(c.h - c0.h)])
				bad = true
		m.queue_free()
	if bad:
		get_tree().quit(1)
		return
	print("[probe] glow_shades done (%s)" % "; ".join(report))
	get_tree().quit(0)
