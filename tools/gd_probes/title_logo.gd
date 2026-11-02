extends Node
# T175 probe: the title screen shows the logo lockup (design kit mark + Black Ops One
# wordmark). Guards the imports: a missing/stale .import leaves a blank texture (cf. B54).

func _fail(msg: String) -> void:
	push_error("[probe] title_logo: " + msg)

func _ready() -> void:
	var t: Node = load("res://scenes/ui/TitleScreen.tscn").instantiate()
	add_child(t)
	await get_tree().process_frame
	var mark := t.get_node_or_null("Logo/Mark") as TextureRect
	if mark == null or mark.texture == null:
		_fail("logo mark missing")
	elif mark.texture.get_size() != Vector2(64, 64):
		_fail("logo mark is %s, want 64x64 (svg/scale 0.5 of the 128 px kit SVG)" % mark.texture.get_size())
	for n in ["Logo/Wordmark/Name/Hard", "Logo/Wordmark/Name/Point"]:
		var lbl := t.get_node_or_null(n) as Label
		var f: Font = lbl.get_theme_font("font") if lbl != null else null
		var base: Font = f.base_font if f is FontVariation else f
		if base == null or not base.resource_path.ends_with("BlackOpsOne-Regular.ttf"):
			_fail("%s not in Black Ops One (%s)" % [n, base.resource_path if base != null else "none"])
	print("[probe] title_logo done")
	get_tree().quit(0)
