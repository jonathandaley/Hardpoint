extends Node3D
# T321 probe (HUMAN_FOUND 2026-11-05: Redwood bark "coarsened and made higher contrast ...
# aligning the dark and light parts vertically for a few pixels at a time"): the standing trunks
# wear a nearest-filtered, world-triplanar bark texture whose same-shade runs are much longer
# down a column than across a row, with clear contrast; fallen logs keep the plain material.

func _ready() -> void:
	var we := WorldEnvironment.new()  # the map makes the arena's environment its own
	we.name = "WorldEnvironment"
	we.environment = Environment.new()
	add_child(we)
	var md: Resource = load("res://resources/maps/Forest.tres")
	var map: Node3D = (load(md.get("scene_path")) as PackedScene).instantiate()
	add_child(map)
	map.call("build")
	await get_tree().process_frame
	var bad: Array = []
	var bark: StandardMaterial3D = null
	for mi in map.find_children("*", "MeshInstance3D", true, false):
		var n := mi as MeshInstance3D
		if n.mesh is CylinderMesh and (n.mesh as CylinderMesh).height > 10.0:
			bark = n.material_override as StandardMaterial3D
			break
	if bark == null or bark.albedo_texture == null:
		bad.append("standing trunks have no bark texture")
	else:
		if bark.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST or not bark.uv1_world_triplanar:
			bad.append("bark not nearest-filtered / world-triplanar")
		var img: Image = bark.albedo_texture.get_image()
		var vr := _runs(img, true)
		var hr := _runs(img, false)
		var lum: Array = []
		for y in img.get_height():
			for x in img.get_width():
				lum.append(img.get_pixel(x, y).get_luminance())
		var mean := 0.0
		for v in lum:
			mean += v
		mean /= lum.size()
		var sd := 0.0
		for v in lum:
			sd += (v - mean) * (v - mean)
		sd = sqrt(sd / lum.size())
		if vr < hr * 2.0:
			bad.append("streaks not vertical (run %.1f down vs %.1f across)" % [vr, hr])
		if sd < 0.05:
			bad.append("low contrast (luma sd %.3f)" % sd)
		var texel := 1.0 / (bark.uv1_scale.x * img.get_width())  # T355: user wants 15 cm pixels
		if absf(texel - 0.15) > 0.005:
			bad.append("bark texels %.2f m, not 0.15" % texel)
	if not bad.is_empty():
		push_error("[probe] forest_bark FAIL: " + "; ".join(bad))
		get_tree().quit(1)
		return
	print("[probe] forest_bark done")
	get_tree().quit(0)

## mean length of same-colour runs down columns (vertical) or along rows
func _runs(img: Image, vertical: bool) -> float:
	var total := 0
	var count := 0
	var a := img.get_width() if vertical else img.get_height()
	var b := img.get_height() if vertical else img.get_width()
	for i in a:
		var run := 1
		for j in range(1, b):
			var p := img.get_pixel(i, j) if vertical else img.get_pixel(j, i)
			var q := img.get_pixel(i, j - 1) if vertical else img.get_pixel(j - 1, i)
			if p.is_equal_approx(q):
				run += 1
			else:
				total += run
				count += 1
				run = 1
		total += run
		count += 1
	return float(total) / count
