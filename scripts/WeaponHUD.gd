extends Control
# Bottom-right weapon panel. Call setup(player_mech) once after the mech is
# in the scene. Weapons are sourced via mech.get_weapons() so the layout
# automatically reflects any number of equipped weapons.

const SLOT_W   := 36.0
const ICON_H   := 22.0
const NUM_H    := 10.0
const AMMO_H   := 10.0
const SLOT_H   := NUM_H + ICON_H + AMMO_H   # 42 px
const SLOT_GAP := 4.0
const PADDING  := 8.0

var _entries: Array = []   # [{weapon, icon, ammo_fg, bar_left}]
var _player_mech: Node = null

func setup(player_mech: Node) -> void:
	for child in get_children():
		child.queue_free()
	_entries.clear()
	_player_mech = player_mech

	var weapons: Array = player_mech.get_weapons() if player_mech.has_method("get_weapons") else []

	if weapons.is_empty():
		return

	var n       := float(weapons.size())
	var total_w := n * SLOT_W + (n - 1.0) * SLOT_GAP
	var vp      := get_viewport_rect().size

	offset_left   = vp.x - total_w - PADDING
	offset_right  = vp.x - PADDING
	offset_top    = vp.y - SLOT_H  - PADDING
	offset_bottom = vp.y - PADDING

	for i in range(weapons.size()):
		var x := float(i) * (SLOT_W + SLOT_GAP)
		var icon_and_ammo := _build_slot(weapons[i], i + 1, x)
		_entries.append({"weapon": weapons[i], "icon": icon_and_ammo[0], "ammo_fg": icon_and_ammo[1], "bar_left": x})

func _build_slot(weapon: Node, number: int, x: float) -> Array:
	# Number-key indicator
	var num_lbl := Label.new()
	num_lbl.text = str(number)
	num_lbl.add_theme_font_size_override("font_size", 8)
	num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	num_lbl.offset_left   = x
	num_lbl.offset_right  = x + SLOT_W
	num_lbl.offset_top    = 0.0
	num_lbl.offset_bottom = NUM_H
	add_child(num_lbl)

	# Weapon icon - placeholder colored rect; replace with TextureRect when art exists
	var icon := ColorRect.new()
	icon.color = _weapon_color(weapon)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.offset_left   = x
	icon.offset_right  = x + SLOT_W
	icon.offset_top    = NUM_H
	icon.offset_bottom = NUM_H + ICON_H
	add_child(icon)

	# Ammo bar - background track + foreground fill
	var bar_top    := NUM_H + ICON_H + 2.0
	var bar_bottom := SLOT_H - 2.0

	var ammo_bg := ColorRect.new()
	ammo_bg.color = Color(0.15, 0.15, 0.15, 0.9)
	ammo_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_bg.offset_left   = x
	ammo_bg.offset_right  = x + SLOT_W
	ammo_bg.offset_top    = bar_top
	ammo_bg.offset_bottom = bar_bottom
	add_child(ammo_bg)

	var ammo_fg := ColorRect.new()
	ammo_fg.color = Color(0.2, 0.85, 0.3, 1.0)
	ammo_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_fg.offset_left   = x
	ammo_fg.offset_right  = x + SLOT_W   # full on spawn; updated each frame
	ammo_fg.offset_top    = bar_top
	ammo_fg.offset_bottom = bar_bottom
	add_child(ammo_fg)

	return [icon, ammo_fg]

func _weapon_color(weapon: Node) -> Color:
	var path: String = weapon.get_script().resource_path
	if "RaycastGun" in path:
		return Color(1.0, 0.85, 0.2, 1.0)   # yellow - hitscan
	if "Sniper" in path:
		return Color(0.85, 0.3, 1.0, 1.0)   # purple - sniper
	if "Rifle" in path:
		return Color(0.4, 0.75, 1.0, 1.0)   # blue - rifle
	if "ProjectileGun" in path:
		return Color(1.0, 0.45, 0.1, 1.0)   # orange - projectile
	return Color(0.4, 0.4, 0.4, 1.0)

func _process(_delta: float) -> void:
	var active_set: Array = []
	if _player_mech != null and is_instance_valid(_player_mech) \
			and _player_mech.has_method("get_active_set"):
		active_set = _player_mech.get_active_set()

	for i in _entries.size():
		var entry: Dictionary = _entries[i]
		if not is_instance_valid(entry["weapon"]):
			continue

		# Ammo bar
		var max_ammo = entry["weapon"].get("max_ammo")
		var pct := 1.0
		if max_ammo != null and int(max_ammo) > 0:
			pct = clampf(float(int(entry["weapon"].get("ammo"))) / float(int(max_ammo)), 0.0, 1.0)
		entry["ammo_fg"].offset_right = entry["bar_left"] + SLOT_W * pct

		var reloading: bool = entry["weapon"].has_method("is_reloading") \
				and entry["weapon"].is_reloading()
		entry["ammo_fg"].color = Color(0.5, 0.5, 0.5, 0.7) if reloading \
				else Color(0.2, 0.85, 0.3, 1.0)

		# Dim icon when not in right-click active set
		var active: bool = active_set.is_empty() or (i < active_set.size() and active_set[i])
		entry["icon"].modulate.a = 1.0 if active else 0.35
