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

var _entries: Array = []   # [{weapon, icon, ammo_fg, charge_fg, cooldown_fg, bar_left}]
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
		_entries.append({"weapon": weapons[i], "icon": icon_and_ammo[0], "ammo_fg": icon_and_ammo[1], "charge_fg": icon_and_ammo[2], "cooldown_fg": icon_and_ammo[3], "bar_left": x})

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

	var icon_path := _weapon_icon_path(weapon)
	var icon: Control
	var tex: Texture2D = null
	if icon_path != "" and ResourceLoader.exists(icon_path):
		tex = load(icon_path) as Texture2D
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.offset_left   = x
		tr.offset_right  = x + SLOT_W
		tr.offset_top    = NUM_H
		tr.offset_bottom = NUM_H + ICON_H
		icon = tr
	else:
		var cr := ColorRect.new()
		cr.color = _weapon_color(weapon)
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cr.offset_left   = x
		cr.offset_right  = x + SLOT_W
		cr.offset_top    = NUM_H
		cr.offset_bottom = NUM_H + ICON_H
		icon = cr
	add_child(icon)

	# Charge overlay - yellow fill grows left-to-right over the icon (Patience only)
	var charge_fg := ColorRect.new()
	charge_fg.color = Color(UIColors.CAUTION, 0.72)
	charge_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	charge_fg.offset_left   = x
	charge_fg.offset_right  = x           # zero width until charging
	charge_fg.offset_top    = NUM_H
	charge_fg.offset_bottom = NUM_H + ICON_H
	add_child(charge_fg)

	# Cooldown overlay - gray shrinks left-to-right as cooldown expires (Sniper only)
	var cooldown_fg := ColorRect.new()
	cooldown_fg.color = Color(UIColors.BG_RAISED, 0.78)
	cooldown_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cooldown_fg.offset_left   = x
	cooldown_fg.offset_right  = x           # zero width when ready
	cooldown_fg.offset_top    = NUM_H
	cooldown_fg.offset_bottom = NUM_H + ICON_H
	add_child(cooldown_fg)

	# Ammo bar - background track + foreground fill
	var bar_top    := NUM_H + ICON_H + 2.0
	var bar_bottom := SLOT_H - 2.0

	var ammo_bg := ColorRect.new()
	ammo_bg.color = Color(UIColors.BG_BAR, 0.9)
	ammo_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_bg.offset_left   = x
	ammo_bg.offset_right  = x + SLOT_W
	ammo_bg.offset_top    = bar_top
	ammo_bg.offset_bottom = bar_bottom
	add_child(ammo_bg)

	var ammo_fg := ColorRect.new()
	ammo_fg.color = UIColors.HP_FULL
	ammo_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_fg.offset_left   = x
	ammo_fg.offset_right  = x + SLOT_W   # full on spawn; updated each frame
	ammo_fg.offset_top    = bar_top
	ammo_fg.offset_bottom = bar_bottom
	add_child(ammo_fg)

	return [icon, ammo_fg, charge_fg, cooldown_fg]

func _weapon_icon_path(weapon: Node) -> String:
	var path: String = weapon.get_script().resource_path
	if "AerialStrike" in path:    return "res://assets/hardpoint/hud-icon-aerial.png"
	if "ArcWeapon" in path:       return "res://assets/hardpoint/hud-icon-arc.png"
	if "LaserCannon" in path:     return "res://assets/hardpoint/hud-icon-laser.png"
	if "MachineGun" in path:      return "res://assets/hardpoint/hud-icon-mgun.png"
	if "MissileLauncher" in path: return "res://assets/hardpoint/hud-icon-missile.png"
	if "Patience" in path:        return "res://assets/hardpoint/hud-icon-patience.png"
	if "RocketLauncher" in path:  return "res://assets/hardpoint/hud-icon-rocket.png"
	if "Shotgun" in path:         return "res://assets/hardpoint/hud-icon-shotgun.png"
	if "Sniper" in path:          return "res://assets/hardpoint/hud-icon-sniper.png"
	if "RaycastGun" in path or "Rifle" in path: return "res://assets/hardpoint/hud-icon-rifle.png"
	return ""

func _weapon_color(weapon: Node) -> Color:
	var path: String = weapon.get_script().resource_path
	if "RaycastGun" in path:
		return Color(1.0, 0.85, 0.2, 1.0)   # yellow - hitscan
	if "Sniper" in path:
		return Color(0.85, 0.3, 1.0, 1.0)   # purple - sniper
	if "MachineGun" in path:
		return Color(1.0, 0.35, 0.1, 1.0)   # red-orange - machine gun
	if "Shotgun" in path:
		return Color(0.6, 0.9, 0.2, 1.0)    # yellow-green - shotgun
	if "MissileLauncher" in path:
		return Color(1.0, 0.15, 0.15, 1.0)  # red - missile launcher
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
		var reloading: bool = entry["weapon"].has_method("is_reloading") \
				and entry["weapon"].is_reloading()
		var pct := 1.0
		if reloading and entry["weapon"].has_method("get_reload_progress"):
			pct = entry["weapon"].get_reload_progress()
		else:
			var max_ammo = entry["weapon"].get("max_ammo")
			if max_ammo != null and int(max_ammo) > 0:
				pct = clampf(float(int(entry["weapon"].get("ammo"))) / float(int(max_ammo)), 0.0, 1.0)
		entry["ammo_fg"].offset_right = entry["bar_left"] + SLOT_W * pct
		entry["ammo_fg"].color = Color(UIColors.FG_DIM, 0.9) if reloading \
				else UIColors.HP_FULL

		# Charge overlay (Patience)
		if entry["weapon"].has_method("get_charge_progress"):
			var cp: float = entry["weapon"].get_charge_progress()
			entry["charge_fg"].offset_right = entry["bar_left"] + SLOT_W * cp

		# Cooldown overlay (Sniper only)
		var wpath: String = entry["weapon"].get_script().resource_path
		if "Sniper" in wpath and entry["weapon"].has_method("get_cooldown_fraction"):
			var cf: float = entry["weapon"].get_cooldown_fraction()
			entry["cooldown_fg"].offset_right = entry["bar_left"] + SLOT_W * cf

		# Dim icon when not in right-click active set
		var active: bool = active_set.is_empty() or (i < active_set.size() and active_set[i])
		entry["icon"].modulate.a = 1.0 if active else 0.35
