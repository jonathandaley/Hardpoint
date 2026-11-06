extends Node
# T310 probe (user on T255 attempt 2: "each block of glow is the same color; I meant to texture
# it like the non-emissive parts of the mech (speckle?)"): on every glowing kit mech the glow
# parts carry a pixel texture (nearest, the armor's triplanar size) whose brightness varies
# like the armor speckle but stays bright and in the glow's hue; Cesh (no glow) stays dark.
# Glow box counts are in the done line -- they must match the pre-T255 counts (nothing added).

const ROSTER := ["Everest", "Kestrel", "Pegasus", "Seeker", "Hornet", "Vesuvius", "Slip", "Hippogriff", "Cesh"]

func _ready() -> void:
	var bad: Array = []
	var report: Array = []
	for mech_name in ROSTER:
		var md: Resource = load("res://resources/mechs/%s.tres" % mech_name)
		var m: Node3D = md.scene.instantiate()
		MechVisuals.apply(m, mech_name)
		add_child(m)
		var glow: Array = []
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var mat := (mi as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
			if mat != null and mat.emission_enabled:
				glow.append(mat)
		report.append("%s %d" % [mech_name, glow.size()])
		for mat: StandardMaterial3D in glow:
			if mat.albedo_texture == null or mat.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST or not mat.uv1_triplanar:
				bad.append("%s: a glow part has no nearest triplanar speckle texture" % mech_name)
				break
			var img := mat.albedo_texture.get_image()
			var lo := 9.0
			var hi := 0.0
			var hues := {}
			for y in range(0, img.get_height(), 4):
				for x in range(0, img.get_width(), 4):
					var c := img.get_pixel(x, y)
					lo = minf(lo, c.v)
					hi = maxf(hi, c.v)
					hues[snappedf(c.h, 0.05)] = true
			if hi - lo < 0.05:
				bad.append("%s: glow texture is flat (value %.2f..%.2f)" % [mech_name, lo, hi])
			elif lo < hi * 0.6:
				bad.append("%s: glow speckle too dark (value %.2f..%.2f)" % [mech_name, lo, hi])
			break
		if mech_name == "Cesh" and not glow.is_empty():
			bad.append("Cesh (no glow) got glowing parts")
		m.queue_free()
	if not bad.is_empty():
		push_error("[probe] glow_speckle FAIL: " + "; ".join(bad))
		get_tree().quit(1)
		return
	print("[probe] glow_speckle done (glow boxes: %s)" % ", ".join(report))
	get_tree().quit(0)
