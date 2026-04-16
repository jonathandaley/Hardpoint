extends Control
# Bottom-right weapon panel. Call setup(player_mech) once after the mech is
# in the scene. Slots are built dynamically from the mech's hardpoints so
# the layout automatically reflects whatever weapons are equipped.
#
# Hardpoint scan order: HardpointLeft → HardpointRight (left slot = left gun).
# A centre hardpoint can be added later — insert it between Left and Right in
# HARDPOINT_ORDER and the layout will accommodate it automatically.

const HARDPOINT_ORDER := ["HardpointLeft", "HardpointRight"]

const SLOT_W   := 36.0
const ICON_H   := 22.0
const NUM_H    := 10.0
const AMMO_H   := 10.0
const SLOT_H   := NUM_H + ICON_H + AMMO_H   # 42 px
const SLOT_GAP := 4.0
const PADDING  := 8.0

var _entries: Array = []   # [{weapon, ammo_label}]

func setup(player_mech: Node) -> void:
	for child in get_children():
		child.queue_free()
	_entries.clear()

	var weapons := []
	for hp_name in HARDPOINT_ORDER:
		var hp := player_mech.get_node_or_null("Torso/" + hp_name)
		if hp == null:
			continue
		for weapon in hp.get_children():
			if weapon.has_method("fire"):
				weapons.append(weapon)

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
		var ammo_lbl := _build_slot(weapons[i], i + 1, x)
		_entries.append({"weapon": weapons[i], "ammo_label": ammo_lbl})

func _build_slot(weapon: Node, number: int, x: float) -> Label:
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

	# Weapon icon — placeholder colored rect; replace with TextureRect when art exists
	var icon := ColorRect.new()
	icon.color = _weapon_color(weapon)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.offset_left   = x
	icon.offset_right  = x + SLOT_W
	icon.offset_top    = NUM_H
	icon.offset_bottom = NUM_H + ICON_H
	add_child(icon)

	# Ammo count
	var ammo_lbl := Label.new()
	ammo_lbl.add_theme_font_size_override("font_size", 8)
	ammo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ammo_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_lbl.offset_left   = x
	ammo_lbl.offset_right  = x + SLOT_W
	ammo_lbl.offset_top    = NUM_H + ICON_H
	ammo_lbl.offset_bottom = SLOT_H
	add_child(ammo_lbl)

	return ammo_lbl

func _weapon_color(weapon: Node) -> Color:
	var path: String = weapon.get_script().resource_path
	if "RaycastGun" in path:
		return Color(1.0, 0.85, 0.2, 1.0)   # yellow — hitscan
	if "ProjectileGun" in path:
		return Color(1.0, 0.45, 0.1, 1.0)   # orange — projectile
	return Color(0.4, 0.4, 0.4, 1.0)

func _process(_delta: float) -> void:
	for entry in _entries:
		if not is_instance_valid(entry["weapon"]):
			continue
		var max_ammo = entry["weapon"].get("max_ammo")
		if max_ammo == null or int(max_ammo) < 0:
			entry["ammo_label"].text = "∞"
		else:
			entry["ammo_label"].text = str(entry["weapon"].get("ammo"))
