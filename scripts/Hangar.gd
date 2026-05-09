extends Control

const DEBUG_BOT_PICKER := false

const ROSTER: Array = [
	"res://resources/mechs/DebugMech.tres",
	"res://resources/mechs/Slip.tres",
	"res://resources/mechs/Cesh.tres",
	"res://resources/mechs/Seeker.tres",
	"res://resources/mechs/Hornet.tres",
	"res://resources/mechs/Hippogriff.tres",
	"res://resources/mechs/Pegasus.tres",
	"res://resources/mechs/Kestrel.tres",
	"res://resources/mechs/Everest.tres",
	"res://resources/mechs/Vesuvius.tres",
]

const WEAPON_CATALOG: Array = [
	{"name": "RIFLE LIGHT",    "path": "res://scenes/weapons/RifleLight.tscn",    "slot_size": 0},
	{"name": "SNIPER LIGHT",   "path": "res://scenes/weapons/SniperLight.tscn",   "slot_size": 0},
	{"name": "MACHINE GUN LIGHT", "path": "res://scenes/weapons/MachineGunLight.tscn", "slot_size": 0},
	{"name": "SHOTGUN LIGHT",        "path": "res://scenes/weapons/ShotgunLight.tscn",        "slot_size": 0},
	{"name": "MISSILE LAUNCHER LT", "path": "res://scenes/weapons/MissileLauncherLight.tscn", "slot_size": 0},
	{"name": "ROCKET LAUNCHER LT",  "path": "res://scenes/weapons/RocketLauncherLight.tscn",  "slot_size": 0},
	{"name": "LASER CANNON LT",     "path": "res://scenes/weapons/LaserCannonLight.tscn",     "slot_size": 0},
	{"name": "RIFLE HEAVY",      "path": "res://scenes/weapons/RifleHeavy.tscn",      "slot_size": 1},
	{"name": "SNIPER HEAVY",     "path": "res://scenes/weapons/SniperHeavy.tscn",     "slot_size": 1},
	{"name": "MACHINE GUN HEAVY", "path": "res://scenes/weapons/MachineGunHeavy.tscn", "slot_size": 1},
	{"name": "SHOTGUN HEAVY",        "path": "res://scenes/weapons/ShotgunHeavy.tscn",        "slot_size": 1},
	{"name": "MISSILE LAUNCHER HV", "path": "res://scenes/weapons/MissileLauncherHeavy.tscn", "slot_size": 1},
	{"name": "LASER CANNON HV",     "path": "res://scenes/weapons/LaserCannonHeavy.tscn",     "slot_size": 1},
	{"name": "ARC WEAPON LT",       "path": "res://scenes/weapons/ArcWeaponLight.tscn",        "slot_size": 0},
	{"name": "ARC WEAPON HV",       "path": "res://scenes/weapons/ArcWeaponHeavy.tscn",        "slot_size": 1},
	{"name": "AERIAL STRIKE HV",    "path": "res://scenes/weapons/AerialStrikeHeavy.tscn",     "slot_size": 1},
	{"name": "PATIENCE HV",         "path": "res://scenes/weapons/PatienceHeavy.tscn",         "slot_size": 1},
]

@onready var mech_panel: Control = $Content/MechPanel
@onready var pilot_panel: Control = $Content/PilotPanel
@onready var pilot_label: Label = $TopBar/PilotLabel
@onready var pilot_name_label: Label = $Content/PilotPanel/PilotName
@onready var pilot_record_label: Label = $Content/PilotPanel/PilotRecord
@onready var mech_name_label: Label = $Content/MechPanel/MechName
@onready var mech_stats_label: Label = $Content/MechPanel/MechStats
@onready var weapon_slot_label: Label = $Content/MechPanel/WeaponSlot
@onready var roster_list: VBoxContainer = $Content/MechPanel/RosterPanel/RosterScroll/RosterList
@onready var bot_roster_list: VBoxContainer = $Content/MechPanel/RosterPanel/BotRosterScroll/BotRosterList

const SQUAD_SIZE := 5
# Default squad uses first 5 non-debug mechs from ROSTER.
const DEFAULT_SQUAD: Array = [
	"res://resources/mechs/Slip.tres",
	"res://resources/mechs/Cesh.tres",
	"res://resources/mechs/Seeker.tres",
	"res://resources/mechs/Hornet.tres",
	"res://resources/mechs/Hippogriff.tres",
]

var _mechs: Array = []
var _selected: int = 0
var _bot_selected: int = 0
var _weapon_indices: Array = []      # WEAPON_CATALOG index per slot for the selected mech
var _weapon_name_labels: Array = []  # Label refs in the picker, updated in-place on cycle
var _team_size_label: Label = null   # shows "1v1", "2v2", etc.

# Squad and mode state
var _squad_paths: Array = []         # 5 mech resource paths
var _squad_mechs: Array = []         # loaded MechDef resources
var _squad_nodes: Array = []         # mech instances in lineup viewport
var _detail_slot: int = -1           # -1 = squad screen, 0-4 = detail for that slot

# Lineup (5-mech) viewport
var _lineup_container: SubViewportContainer = null
var _lineup_viewport: SubViewport = null
var _slot_btns: Array = []
var _slot_labels: Array = []

# Back button (detail screen)
var _back_btn: Button = null
var _team_size_container: Control = null  # programmatic team-size picker root

# Single-mech diorama (detail screen)
var _diorama_container: SubViewportContainer = null
var _diorama_viewport: SubViewport = null
var _diorama_spin: Node3D = null
var _diorama_mech_node = null

const MAPS: Array = [
	"res://resources/maps/MathTemple.tres",
	"res://resources/maps/Ironworks.tres",
	"res://resources/maps/Badlands.tres",
]

var _pilot_stats_label: Label = null
var _prog_nodes_container: Control = null

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	weapon_slot_label.visible = false
	var pilot_name: String = Game.profile.get("pilot_name", "Pilot")
	pilot_label.text = pilot_name
	pilot_name_label.text = "NAME: " + pilot_name.to_upper()
	var wins: int = Game.profile.get("wins", 0)
	var losses: int = Game.profile.get("losses", 0)
	pilot_record_label.text = "WINS: %d   LOSSES: %d" % [wins, losses]
	_load_roster()
	_load_squad()
	_ensure_default_mech()
	_build_roster_buttons()
	if DEBUG_BOT_PICKER:
		_ensure_default_bot()
		_build_bot_roster_buttons()
	else:
		_hide_bot_picker()
		if Game.loadout.get("bot_def") == null and _mechs.size() > 0:
			Game.loadout["bot_def"] = _mechs[0]
	_build_team_size_picker()
	_build_back_btn()
	_setup_lineup_viewport()
	_setup_diorama()
	_init_map_selection()
	_build_pilot_extras()
	_show_tab(0)

func _load_squad() -> void:
	var saved: Array = Game.loadout.get("squad", [])
	_squad_paths.clear()
	for i in SQUAD_SIZE:
		var path: String = saved[i] if i < saved.size() else DEFAULT_SQUAD[i % DEFAULT_SQUAD.size()]
		_squad_paths.append(path)
	_squad_mechs.clear()
	for path in _squad_paths:
		var md = load(path)
		_squad_mechs.append(md)
	Game.loadout["squad"] = _squad_paths
	# Sync mech_def to slot 0
	if _squad_mechs.size() > 0 and _squad_mechs[0] != null:
		Game.loadout["mech_def"] = _squad_mechs[0]

func _build_back_btn() -> void:
	_back_btn = Button.new()
	_back_btn.text = "< BACK"
	_back_btn.offset_left   = 4.0
	_back_btn.offset_top    = 316.0
	_back_btn.offset_right  = 190.0
	_back_btn.offset_bottom = 348.0
	_back_btn.add_theme_font_size_override("font_size", 20)
	_back_btn.pressed.connect(_on_back_pressed)
	add_child(_back_btn)
	_back_btn.visible = false

func _setup_lineup_viewport() -> void:
	_lineup_container = SubViewportContainer.new()
	_lineup_container.offset_left   = 0.0
	_lineup_container.offset_top    = 0.0
	_lineup_container.offset_right  = 640.0
	_lineup_container.offset_bottom = 210.0
	_lineup_container.stretch = true
	mech_panel.add_child(_lineup_container)

	_lineup_viewport = SubViewport.new()
	_lineup_viewport.size              = Vector2i(1280, 420)
	_lineup_viewport.own_world_3d      = true
	_lineup_viewport.transparent_bg    = false
	_lineup_viewport.handle_input_locally = false
	_lineup_container.add_child(_lineup_viewport)

	var env := Environment.new()
	env.background_mode       = Environment.BG_COLOR
	env.background_color      = Color(0.05, 0.05, 0.07)
	env.ambient_light_source  = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color   = Color(0.5, 0.5, 0.6)
	env.ambient_light_energy  = 0.5
	var env_node := WorldEnvironment.new()
	env_node.environment = env
	_lineup_viewport.add_child(env_node)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	light.light_energy     = 1.2
	_lineup_viewport.add_child(light)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size       = 5.5
	cam.position   = Vector3(0.0, 3.5, 10.0)
	cam.look_at_from_position(cam.position, Vector3(0.0, 1.2, 0.0))
	_lineup_viewport.add_child(cam)

	# Platform spanning all 5 mech positions.
	var platform_mi   := MeshInstance3D.new()
	var platform_mesh := CylinderMesh.new()
	platform_mesh.top_radius    = 9.0
	platform_mesh.bottom_radius = 9.0
	platform_mesh.height        = 0.12
	platform_mi.mesh = platform_mesh
	var platform_mat := StandardMaterial3D.new()
	platform_mat.albedo_color = Color(0.18, 0.18, 0.22)
	platform_mat.roughness    = 0.6
	platform_mi.set_surface_override_material(0, platform_mat)
	platform_mi.position = Vector3(0.0, -0.06, 0.0)
	_lineup_viewport.add_child(platform_mi)

	_refresh_lineup_mechs()

	# Transparent hit buttons overlaying each mech + name label below.
	# Compute screen-x centres from world positions (orthographic, size=5.5, display 640px wide).
	var spacing := 3.0
	var start_x := -(SQUAD_SIZE - 1) * spacing * 0.5
	var cam_size := 5.5
	var disp_w  := 640.0
	var disp_h  := 210.0
	var aspect  := disp_w / disp_h
	var world_w := cam_size * aspect  # world units visible horizontally

	var style_normal  := StyleBoxFlat.new()
	style_normal.bg_color = Color(0, 0, 0, 0)
	var style_hover   := StyleBoxFlat.new()
	style_hover.bg_color  = Color(1, 1, 1, 0.22)
	var style_pressed := StyleBoxFlat.new()
	style_pressed.bg_color = Color(1, 1, 1, 0.35)

	var btn_w := disp_w / SQUAD_SIZE  # equal-width zones

	for i in SQUAD_SIZE:
		var world_cx := start_x + i * spacing
		var screen_cx := disp_w * (world_cx / world_w + 0.5)

		var btn := Button.new()
		btn.text = ""
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.offset_left   = screen_cx - btn_w * 0.5
		btn.offset_top    = 0.0
		btn.offset_right  = screen_cx + btn_w * 0.5
		btn.offset_bottom = 244.0
		btn.add_theme_stylebox_override("normal",  style_normal)
		btn.add_theme_stylebox_override("hover",   style_hover)
		btn.add_theme_stylebox_override("pressed", style_pressed)
		btn.pressed.connect(_on_slot_btn_pressed.bind(i))
		mech_panel.add_child(btn)
		_slot_btns.append(btn)

		var lbl := Label.new()
		lbl.text = ""
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.offset_left   = screen_cx - btn_w * 0.5
		lbl.offset_top    = 213.0
		lbl.offset_right  = screen_cx + btn_w * 0.5
		lbl.offset_bottom = 244.0
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mech_panel.add_child(lbl)
		_slot_labels.append(lbl)

	_refresh_slot_btn_labels()

func _refresh_lineup_mechs() -> void:
	for n in _squad_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_squad_nodes.clear()

	# Spacing: 3.0m between mechs, centered at x=0.
	var spacing := 3.0
	var start_x := -(SQUAD_SIZE - 1) * spacing * 0.5
	for i in SQUAD_SIZE:
		var md = _squad_mechs[i] if i < _squad_mechs.size() else null
		if md == null or md.scene == null:
			_squad_nodes.append(null)
			continue
		var m = md.scene.instantiate()
		m.scale = Vector3.ONE * md.body_scale
		MechVisuals.apply(m, md.display_name)
		m.position = Vector3(start_x + float(i) * spacing, 0.0, 0.0)
		_lineup_viewport.add_child(m)
		m.set_physics_process(false)
		_squad_nodes.append(m)

func _refresh_slot_btn_labels() -> void:
	for i in SQUAD_SIZE:
		if i >= _slot_labels.size():
			break
		var md = _squad_mechs[i] if i < _squad_mechs.size() else null
		var text: String = md.display_name.to_upper() if md != null else "EMPTY"
		_slot_labels[i].text = text

func _on_slot_btn_pressed(slot: int) -> void:
	SoundManager.play_sfx_2d("ui_click")
	_show_detail_screen(slot)

func _on_back_pressed() -> void:
	SoundManager.play_sfx_2d("ui_click")
	_show_squad_screen()

func _show_squad_screen() -> void:
	_detail_slot = -1
	_refresh_lineup_mechs()
	_refresh_slot_btn_labels()
	_lineup_container.visible = true
	for btn in _slot_btns:
		btn.visible = true
	_back_btn.visible = false
	$Content/MechPanel/RosterPanel.visible = false
	$Content/MechPanel/RosterDivider.visible = false
	mech_name_label.visible = false
	mech_stats_label.visible = false
	for lbl in _slot_labels:
		lbl.visible = true
	if _diorama_container != null:
		_diorama_container.visible = false
	var picker := mech_panel.get_node_or_null("WeaponPicker")
	if picker:
		picker.visible = false
	# Show bottom bar.
	$BottomDivider.visible = true
	$MatchmakingButton.visible = true
	$SettingsButton.visible = true
	if _team_size_container != null:
		_team_size_container.visible = true
	_back_btn.visible = false

func _show_detail_screen(slot: int) -> void:
	_detail_slot = slot
	# Sync mech_def to the selected slot's mech for weapon picker compatibility.
	var md = _squad_mechs[slot] if slot < _squad_mechs.size() else null
	if md != null:
		Game.loadout["mech_def"] = md
	_selected = _mechs.find(md)
	if _selected < 0:
		_selected = 0
	_init_weapon_overrides()
	_highlight_selected()
	_update_mech_panel()
	_refresh_diorama_mech()

	_lineup_container.visible = false
	for btn in _slot_btns:
		btn.visible = false
	for lbl in _slot_labels:
		lbl.visible = false
	# Hide bottom bar, show back button in its place.
	$BottomDivider.visible = false
	$MatchmakingButton.visible = false
	$SettingsButton.visible = false
	if _team_size_container != null:
		_team_size_container.visible = false
	_back_btn.visible = true
	$Content/MechPanel/RosterPanel.visible = true
	$Content/MechPanel/RosterDivider.visible = true
	mech_name_label.visible = true
	mech_stats_label.visible = true
	if _diorama_container != null:
		_diorama_container.visible = true

func _load_roster() -> void:
	_mechs.clear()
	for path in ROSTER:
		var md = load(path)
		if md != null:
			_mechs.append(md)
		else:
			push_error("[Hangar] Failed to load MechDef: " + path)

func _ensure_default_mech() -> void:
	var current = Game.loadout.get("mech_def")
	if current == null:
		_selected = 1 if _mechs.size() > 1 else 0
		if _mechs.size() > 0:
			Game.loadout.mech_def = _mechs[_selected]
	else:
		for i in _mechs.size():
			if _mechs[i] == current:
				_selected = i
				_init_weapon_overrides()
				return
		_selected = 0
		if _mechs.size() > 0:
			Game.loadout.mech_def = _mechs[0]
	_init_weapon_overrides()

func _hide_bot_picker() -> void:
	for name in ["RosterMidDivider", "BotHeader", "BotRosterScroll"]:
		var n = $Content/MechPanel/RosterPanel.get_node_or_null(name)
		if n:
			n.visible = false
	var scroll = $Content/MechPanel/RosterPanel.get_node_or_null("RosterScroll")
	if scroll:
		scroll.offset_bottom = 240.0

func _ensure_default_bot() -> void:
	var current = Game.loadout.get("bot_def")
	if current == null:
		_bot_selected = 0
		if _mechs.size() > 0:
			Game.loadout["bot_def"] = _mechs[0]
	else:
		for i in _mechs.size():
			if _mechs[i] == current:
				_bot_selected = i
				return
		_bot_selected = 0
		if _mechs.size() > 0:
			Game.loadout["bot_def"] = _mechs[0]

func _build_bot_roster_buttons() -> void:
	for child in bot_roster_list.get_children():
		child.queue_free()
	for i in _mechs.size():
		var md = _mechs[i]
		var btn := Button.new()
		btn.text = "%s\n%s" % [md.display_name.to_upper(), md.class_tag.to_upper()]
		btn.custom_minimum_size = Vector2(160, 44)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_on_bot_roster_selected.bind(i))
		bot_roster_list.add_child(btn)
	_highlight_bot_selected()

func _highlight_bot_selected() -> void:
	var buttons := bot_roster_list.get_children()
	for i in buttons.size():
		var btn: Button = buttons[i]
		if i == _bot_selected:
			btn.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2))
		else:
			btn.remove_theme_color_override("font_color")

func _on_bot_roster_selected(idx: int) -> void:
	SoundManager.play_sfx_2d("ui_click")
	_bot_selected = idx
	Game.loadout["bot_def"] = _mechs[idx]
	Game.save_loadout()
	_highlight_bot_selected()

func _init_weapon_overrides() -> void:
	var md = Game.loadout.get("mech_def")
	if md == null:
		return
	var slots: Array = md.weapon_slots
	_weapon_indices.resize(slots.size())
	var saved: Array = Game.loadout.get("mech_weapon_choices", {}).get(md.resource_path, [])
	var overrides: Array = []
	for i in slots.size():
		var slot = slots[i]
		var s_size: int = int(slot.get("slot_size")) if "slot_size" in slot else 0
		var target_path: String = saved[i] if i < saved.size() else ""
		if target_path == "":
			target_path = slot.weapon_scene.resource_path if slot.weapon_scene != null else ""
		var found: int = -1
		for j in WEAPON_CATALOG.size():
			if WEAPON_CATALOG[j]["slot_size"] == s_size:
				if found < 0:
					found = j
				if WEAPON_CATALOG[j]["path"] == target_path:
					found = j
					break
		_weapon_indices[i] = found if found >= 0 else 0
		var scene: PackedScene = load(WEAPON_CATALOG[_weapon_indices[i]]["path"])
		overrides.append(scene)
	Game.loadout["weapon_overrides"] = overrides

func _build_roster_buttons() -> void:
	for child in roster_list.get_children():
		child.queue_free()
	for i in _mechs.size():
		var md = _mechs[i]
		var btn := Button.new()
		btn.text = "%s\n%s" % [md.display_name.to_upper(), md.class_tag.to_upper()]
		btn.custom_minimum_size = Vector2(160, 44)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_on_roster_selected.bind(i))
		roster_list.add_child(btn)
	_highlight_selected()

func _highlight_selected() -> void:
	var buttons := roster_list.get_children()
	for i in buttons.size():
		var btn: Button = buttons[i]
		if i == _selected:
			btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
		else:
			btn.remove_theme_color_override("font_color")

func _on_roster_selected(idx: int) -> void:
	SoundManager.play_sfx_2d("ui_click")
	_selected = idx
	Game.loadout.mech_def = _mechs[idx]
	# Update squad slot if in detail screen.
	if _detail_slot >= 0 and _detail_slot < SQUAD_SIZE:
		_squad_mechs[_detail_slot] = _mechs[idx]
		_squad_paths[_detail_slot] = _mechs[idx].resource_path
		Game.loadout["squad"] = _squad_paths
		_refresh_slot_btn_labels()
	_init_weapon_overrides()
	Game.save_loadout()
	_highlight_selected()
	_update_mech_panel()
	_refresh_diorama_mech()

func _update_mech_panel() -> void:
	var md = Game.loadout.get("mech_def")
	if md == null:
		return
	mech_name_label.text = "MECH: %s" % md.display_name.to_upper()
	var shield_str: String
	if md.has_shields:
		shield_str = "PHYSICAL (FRONT)"
	elif md.has_energy_shield:
		shield_str = "ENERGY"
	else:
		shield_str = "-"
	mech_stats_label.text = "SPEED: %.2f   HEALTH: %.0f   SHIELDS: %s" % [md.walk_speed, md.max_health, shield_str]
	_build_weapon_picker(md)

func _build_weapon_picker(md) -> void:
	var existing := mech_panel.get_node_or_null("WeaponPicker")
	if existing:
		existing.free()

	var slots: Array = md.weapon_slots
	var row_h := 24.0
	var picker_top := 44.0

	_weapon_name_labels.clear()

	var picker := VBoxContainer.new()
	picker.name = "WeaponPicker"
	picker.offset_left = 200.0
	picker.offset_top = picker_top
	picker.offset_right = 415.0
	picker.offset_bottom = picker_top + slots.size() * row_h
	picker.add_theme_constant_override("separation", 2)
	mech_panel.add_child(picker)

	for i in slots.size():
		var slot = slots[i]
		var s_size: int = int(slot.get("slot_size")) if "slot_size" in slot else 0
		var size_str: String = "HEAVY" if s_size == 1 else "LIGHT"

		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, row_h - 2.0)
		row.add_theme_constant_override("separation", 4)
		picker.add_child(row)

		var slot_lbl := Label.new()
		slot_lbl.text = "%d%s" % [i + 1, "L" if s_size == 0 else "H"]
		slot_lbl.add_theme_font_size_override("font_size", 13)
		slot_lbl.custom_minimum_size = Vector2(24, 0)
		slot_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(slot_lbl)

		var prev_btn := Button.new()
		prev_btn.text = "<"
		prev_btn.custom_minimum_size = Vector2(22, 0)
		prev_btn.add_theme_font_size_override("font_size", 13)
		prev_btn.pressed.connect(_on_weapon_cycle.bind(i, -1))
		row.add_child(prev_btn)

		var cat_idx: int = _weapon_indices[i] if i < _weapon_indices.size() else 0
		var wep_name: String = WEAPON_CATALOG[cat_idx]["name"] if cat_idx >= 0 else "NONE"

		var wep_lbl := Label.new()
		wep_lbl.text = wep_name
		wep_lbl.add_theme_font_size_override("font_size", 13)
		wep_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wep_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wep_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(wep_lbl)
		_weapon_name_labels.append(wep_lbl)

		var next_btn := Button.new()
		next_btn.text = ">"
		next_btn.custom_minimum_size = Vector2(22, 0)
		next_btn.add_theme_font_size_override("font_size", 13)
		next_btn.pressed.connect(_on_weapon_cycle.bind(i, 1))
		row.add_child(next_btn)

	var stats_top: float = picker_top + slots.size() * row_h + 8.0
	mech_stats_label.offset_top = stats_top
	mech_stats_label.offset_bottom = stats_top + 28.0
	mech_stats_label.offset_right = 415.0

func _on_weapon_cycle(slot_idx: int, direction: int) -> void:
	SoundManager.play_sfx_2d("ui_click")
	var md = Game.loadout.get("mech_def")
	if md == null or slot_idx >= md.weapon_slots.size():
		return
	var slot = md.weapon_slots[slot_idx]
	var s_size: int = int(slot.get("slot_size")) if "slot_size" in slot else 0

	var compatible: Array = []
	for i in WEAPON_CATALOG.size():
		if WEAPON_CATALOG[i]["slot_size"] == s_size:
			compatible.append(i)
	if compatible.is_empty():
		return

	var cur: int = _weapon_indices[slot_idx] if slot_idx < _weapon_indices.size() else compatible[0]
	var pos: int = compatible.find(cur)
	if pos < 0:
		pos = 0
	pos = (pos + direction + compatible.size()) % compatible.size()
	_weapon_indices[slot_idx] = compatible[pos]

	var overrides: Array = Game.loadout.get("weapon_overrides", [])
	while overrides.size() <= slot_idx:
		overrides.append(null)
	overrides[slot_idx] = load(WEAPON_CATALOG[_weapon_indices[slot_idx]]["path"])
	Game.loadout["weapon_overrides"] = overrides

	if md != null:
		var choices: Dictionary = Game.loadout.get("mech_weapon_choices", {})
		var paths: Array = []
		for o in overrides:
			paths.append(o.resource_path if o != null else "")
		choices[md.resource_path] = paths
		Game.loadout["mech_weapon_choices"] = choices
		Game.save_loadout()

	if slot_idx < _weapon_name_labels.size() and is_instance_valid(_weapon_name_labels[slot_idx]):
		_weapon_name_labels[slot_idx].text = WEAPON_CATALOG[_weapon_indices[slot_idx]]["name"]

func _build_team_size_picker() -> void:
	# Placed bottom-left, leaving the existing FIND MATCH and SETTINGS buttons in place.
	var container := HBoxContainer.new()
	container.offset_left   = 4.0
	container.offset_top    = 316.0
	container.offset_right  = 190.0
	container.offset_bottom = 348.0
	container.add_theme_constant_override("separation", 4)
	add_child(container)
	_team_size_container = container

	var lbl := Label.new()
	lbl.text = "TEAM SIZE"
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	container.add_child(lbl)

	var prev_btn := Button.new()
	prev_btn.text = "<"
	prev_btn.custom_minimum_size = Vector2(26, 0)
	prev_btn.add_theme_font_size_override("font_size", 14)
	prev_btn.pressed.connect(_on_team_size_change.bind(-1))
	container.add_child(prev_btn)

	_team_size_label = Label.new()
	_team_size_label.add_theme_font_size_override("font_size", 14)
	_team_size_label.custom_minimum_size = Vector2(36, 0)
	_team_size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_team_size_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	container.add_child(_team_size_label)

	var next_btn := Button.new()
	next_btn.text = ">"
	next_btn.custom_minimum_size = Vector2(26, 0)
	next_btn.add_theme_font_size_override("font_size", 14)
	next_btn.pressed.connect(_on_team_size_change.bind(1))
	container.add_child(next_btn)

	_refresh_team_size_label()

func _refresh_team_size_label() -> void:
	if _team_size_label == null:
		return
	var ts: int = clampi(Game.loadout.get("team_size", 1), 1, 6)
	_team_size_label.text = "%dv%d" % [ts, ts]

func _on_team_size_change(delta: int) -> void:
	SoundManager.play_sfx_2d("ui_click")
	var ts: int = clampi(Game.loadout.get("team_size", 1) + delta, 1, 6)
	Game.loadout["team_size"] = ts
	Game.save_loadout()
	_refresh_team_size_label()

func _process(delta: float) -> void:
	if is_instance_valid(_diorama_spin):
		_diorama_spin.rotation.y += delta * 0.6

func _setup_diorama() -> void:
	_diorama_container = SubViewportContainer.new()
	_diorama_container.offset_left   = 420.0
	_diorama_container.offset_top    = 8.0
	_diorama_container.offset_right  = 634.0
	_diorama_container.offset_bottom = 244.0
	_diorama_container.stretch = true
	mech_panel.add_child(_diorama_container)

	_diorama_viewport = SubViewport.new()
	_diorama_viewport.size              = Vector2i(428, 472)
	_diorama_viewport.own_world_3d      = true
	_diorama_viewport.transparent_bg    = false
	_diorama_viewport.handle_input_locally = false
	_diorama_container.add_child(_diorama_viewport)

	var sv_env := Environment.new()
	sv_env.background_mode    = Environment.BG_COLOR
	sv_env.background_color   = Color(0.05, 0.05, 0.07)
	sv_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sv_env.ambient_light_color  = Color(0.5, 0.5, 0.6)
	sv_env.ambient_light_energy = 0.4
	var sv_env_node := WorldEnvironment.new()
	sv_env_node.environment = sv_env
	_diorama_viewport.add_child(sv_env_node)

	var platform_body := StaticBody3D.new()
	var platform_mi   := MeshInstance3D.new()
	var platform_mesh := CylinderMesh.new()
	platform_mesh.top_radius    = 2.8
	platform_mesh.bottom_radius = 2.8
	platform_mesh.height        = 0.1
	platform_mi.mesh = platform_mesh
	var platform_mat := StandardMaterial3D.new()
	platform_mat.albedo_color = Color(0.2, 0.2, 0.25)
	platform_mat.roughness    = 0.6
	platform_mi.set_surface_override_material(0, platform_mat)
	platform_body.add_child(platform_mi)
	platform_body.position = Vector3(0.0, -0.05, 0.0)
	_diorama_viewport.add_child(platform_body)

	_diorama_spin = Node3D.new()
	_diorama_viewport.add_child(_diorama_spin)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size       = 4.2   # vertical world-units visible; sized for Vesuvius to fill frame
	cam.position   = Vector3(0.0, 2.8, 10.0)
	cam.look_at_from_position(cam.position, Vector3(0.0, 1.5, 0.0))
	_diorama_viewport.add_child(cam)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	light.light_energy     = 1.2
	_diorama_viewport.add_child(light)

	_refresh_diorama_mech()

func _refresh_diorama_mech() -> void:
	if not is_instance_valid(_diorama_spin):
		return
	if is_instance_valid(_diorama_mech_node):
		_diorama_mech_node.queue_free()
		_diorama_mech_node = null
	var md = Game.loadout.get("mech_def")
	if md == null or md.scene == null:
		return
	var m = md.scene.instantiate()
	m.scale = Vector3.ONE * md.body_scale
	MechVisuals.apply(m, md.display_name)
	_diorama_spin.add_child(m)
	m.set_physics_process(false)
	_diorama_mech_node = m

func _show_tab(idx: int) -> void:
	mech_panel.visible = idx == 0
	pilot_panel.visible = idx == 1
	if idx == 0:
		_show_squad_screen()

func _on_mech_tab_pressed() -> void:
	SoundManager.play_sfx_2d("ui_click")
	_show_tab(0)

func _on_pilot_tab_pressed() -> void:
	SoundManager.play_sfx_2d("ui_click")
	_show_tab(1)

func _on_matchmaking_pressed() -> void:
	SoundManager.play_sfx_2d("ui_click")
	get_tree().change_scene_to_file("res://scenes/arena/Arena.tscn")

func _on_settings_pressed() -> void:
	SoundManager.play_sfx_2d("ui_click")
	get_tree().change_scene_to_file("res://scenes/ui/Settings.tscn")

func _init_map_selection() -> void:
	if Game.loadout.get("map_def") == null:
		Game.loadout["map_def"] = load(MAPS[0])

# ---- Pilot tab progression UI (T71-T74) ----

func _build_pilot_extras() -> void:
	_pilot_stats_label = Label.new()
	_pilot_stats_label.offset_left   = 16.0
	_pilot_stats_label.offset_top    = 72.0
	_pilot_stats_label.offset_right  = 630.0
	_pilot_stats_label.offset_bottom = 90.0
	_pilot_stats_label.add_theme_font_size_override("font_size", 13)
	pilot_panel.add_child(_pilot_stats_label)
	_refresh_pilot_stats()

	var hdr := Label.new()
	hdr.text = "PROGRESSION"
	hdr.offset_left   = 16.0
	hdr.offset_top    = 98.0
	hdr.offset_right  = 630.0
	hdr.offset_bottom = 114.0
	hdr.add_theme_font_size_override("font_size", 14)
	pilot_panel.add_child(hdr)

	_prog_nodes_container = Control.new()
	_prog_nodes_container.offset_left   = 0.0
	_prog_nodes_container.offset_top    = 118.0
	_prog_nodes_container.offset_right  = 640.0
	_prog_nodes_container.offset_bottom = 244.0
	pilot_panel.add_child(_prog_nodes_container)
	_build_progression_nodes()

func _refresh_pilot_stats() -> void:
	if _pilot_stats_label == null:
		return
	var lv: int    = Game.profile.get("level", 1)
	var xp: int    = Game.profile.get("xp", 0)
	var elo: int   = Game.profile.get("elo", 1000)
	var coins: int = Game.profile.get("coins", 0)
	var xp_left: int = Game.xp_to_next_level()
	if xp_left > 0:
		_pilot_stats_label.text = "LVL: %d  |  XP: %d (+%d to next)  |  ELO: %d  |  COINS: %d" % [
			lv, xp, xp_left, elo, coins]
	else:
		_pilot_stats_label.text = "LVL: %d (MAX)  |  XP: %d  |  ELO: %d  |  COINS: %d" % [
			lv, xp, elo, coins]

func _build_progression_nodes() -> void:
	if _prog_nodes_container == null:
		return
	for child in _prog_nodes_container.get_children():
		child.queue_free()

	const NODE_KEYS: Array   = ["speed", "reload", "damage", "health", "ability"]
	const NODE_LABELS: Array = ["SPEED", "RELOAD", "DAMAGE", "HEALTH", "ABILITY"]
	const BLOCK_W := 118.0
	const BLOCK_GAP := 8.0

	for i in NODE_KEYS.size():
		var node_name: String = NODE_KEYS[i]
		var tier: int = Game.get_progression_tier(node_name)

		var block := VBoxContainer.new()
		block.offset_left   = BLOCK_GAP + float(i) * (BLOCK_W + BLOCK_GAP)
		block.offset_top    = 0.0
		block.offset_right  = BLOCK_GAP + float(i) * (BLOCK_W + BLOCK_GAP) + BLOCK_W
		block.offset_bottom = 124.0
		block.add_theme_constant_override("separation", 3)
		_prog_nodes_container.add_child(block)

		var name_lbl := Label.new()
		name_lbl.text = NODE_LABELS[i]
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		block.add_child(name_lbl)

		var tier_lbl := Label.new()
		tier_lbl.text = "TIER %d/4   +%d%%" % [tier, tier * 5]
		tier_lbl.add_theme_font_size_override("font_size", 12)
		tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		block.add_child(tier_lbl)

		if tier < 4:
			var cost_lbl := Label.new()
			cost_lbl.text = "LV%d  |  %d COINS" % [
				Game.get_prog_next_level_req(node_name),
				Game.get_prog_next_cost(node_name)]
			cost_lbl.add_theme_font_size_override("font_size", 11)
			cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			block.add_child(cost_lbl)

			var can_buy: bool = Game.can_buy_progression(node_name)
			var buy_btn := Button.new()
			buy_btn.text = "BUY TIER %d" % (tier + 1)
			buy_btn.add_theme_font_size_override("font_size", 12)
			buy_btn.disabled = not can_buy
			if can_buy:
				buy_btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
			buy_btn.pressed.connect(_on_prog_buy.bind(node_name))
			block.add_child(buy_btn)
		else:
			var max_lbl := Label.new()
			max_lbl.text = "MAX TIER"
			max_lbl.add_theme_font_size_override("font_size", 12)
			max_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			max_lbl.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
			block.add_child(max_lbl)

func _on_prog_buy(node_name: String) -> void:
	SoundManager.play_sfx_2d("ui_click")
	if Game.buy_progression(node_name):
		_refresh_pilot_stats()
		_build_progression_nodes()
