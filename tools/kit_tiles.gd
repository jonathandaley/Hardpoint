extends SceneTree
# T182: copies the design kit's pixel tiles (design/ is .gdignore'd) into assets/hardpoint/textures
# and derives the Lynx and Warhog tiles the kit export lacks: Cesh's tile noise (each pixel's
# ratio to the tile average) re-based onto their palette colours (tools/kit_mechs/*.js).
# Run: ~/bin/godot --headless -s res://tools/kit_tiles.gd

const SRC := "res://design/assets/textures/"
const DST := "res://assets/hardpoint/textures/"
const KIT := ["cesh", "everest", "hippogriff", "hornet", "kestrel", "pegasus", "seeker", "slip", "vesuvius", "weapon-steel"]
const DERIVED := {"lynx": ["#2F5C3A", "#1E3D27"], "warhog": ["#5C4A33", "#7A6342"]}

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DST))
	for n in KIT:
		for ch in ["armor", "detail"]:
			_load("%s%s-%s.png" % [SRC, n, ch]).save_png("%s%s-%s.png" % [DST, n, ch])
	for n in DERIVED:
		for i in 2:
			var ch: String = ["armor", "detail"][i]
			var img := _load("%scesh-%s.png" % [SRC, ch])
			var avg := Color(0, 0, 0)
			for y in img.get_height():
				for x in img.get_width():
					avg += img.get_pixel(x, y)
			avg /= img.get_width() * img.get_height()
			var base := Color.html(DERIVED[n][i])
			for y in img.get_height():
				for x in img.get_width():
					var p := img.get_pixel(x, y)
					img.set_pixel(x, y, Color(base.r * p.r / avg.r, base.g * p.g / avg.g, base.b * p.b / avg.b).clamp())
			img.save_png("%s%s-%s.png" % [DST, n, ch])
	print("[kit_tiles] wrote %d tiles" % ((KIT.size() + DERIVED.size()) * 2))
	quit()

func _load(path: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	img.convert(Image.FORMAT_RGB8)
	return img
