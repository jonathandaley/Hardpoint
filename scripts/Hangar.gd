extends Control

const MechVisuals = preload("res://scripts/MechVisuals.gd")

const DEBUG_BOT_PICKER := false

# T391: one catalog, Lobby's -- the server's squad whitelist (Game.clean_squad_entry) reads the same lists
const _Lobby = preload("res://scripts/Lobby.gd")
const ROSTER: Array = _Lobby.ROSTER
const WEAPON_CATALOG: Array = _Lobby.WEAPON_CATALOG

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

# Single-mech diorama (detail screen)
var _diorama_container: SubViewportContainer = null
var _diorama_viewport: SubViewport = null
var _diorama_spin: Node3D = null
var _diorama_mech_node = null

const MAPS: Array = [
	"res://resources/maps/MathTemple.tres",
	"res://resources/maps/Badlands.tres",
	"res://resources/maps/City.tres",
	"res://resources/maps/Forest.tres",
	"res://resources/maps/Giza.tres",
	"res://resources/maps/Swamp.tres",
	"res://resources/maps/Factory.tres",
	"res://resources/maps/Corvette.tres",
]

var _pilot_stats_label: Label = null
var _prog_nodes_container: Control = null

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	weapon_slot_label.visible = false
	_opaque_tooltips()
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
	# T275 (HUMAN_FOUND 2026-11-05): no team-size picker here any more -- match setup owns it
	# (SP bot counts T251, the lobby). Game.loadout.team_size stays as the SP "fill" default.
	_build_back_btn()
	_setup_lineup_viewport()
	_setup_diorama()
	_init_map_selection()
	_build_pilot_extras()
	_show_tab(0)
	move_child($FindMatchPanel, -1)  # T176: above the controls built in code above
	move_child($PresetPanel, -1)  # T177

func _load_squad() -> void:
	var saved: Array = Game.loadout.get("squad", [])
	_squad_paths.clear()
	for i in SQUAD_SIZE:
		var path: String = saved[i] if i < saved.size() else DEFAULT_SQUAD[i % DEFAULT_SQUAD.size()]
		if not ROSTER.has(path):  # T304: e.g. a squad saved with the removed debug mech
			path = DEFAULT_SQUAD[i % DEFAULT_SQUAD.size()]
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
	_back_btn.name = "BackBtn"
	_back_btn.text = "< BACK"
	_back_btn.offset_left   = 4.0
	_back_btn.offset_top    = 316.0
	_back_btn.offset_right  = 190.0
	_back_btn.offset_bottom = 348.0
	_back_btn.add_theme_font_size_override("font_size", 20)
	_back_btn.pressed.connect(_on_back_pressed)
	add_child(_back_btn)
	_back_btn.visible = false

var _bay: Node3D = null  # T208
const LINEUP_YAW := 215.0  # T220 3/4 view; T227: forward is -Z and the camera is at +Z, so 180 + 35 (35 alone was 3/4 AWAY)

func _setup_lineup_viewport() -> void:
	_lineup_container = SubViewportContainer.new()
	# T220: render the 3D lineup at the window's pixel size (1280x420), shown at half scale
	# in the 640x210 UI area -- stretched from 640x210 the light weapons blurred into the hull
	_lineup_container.offset_left   = 0.0
	_lineup_container.offset_top    = 0.0
	_lineup_container.offset_right  = 1280.0
	_lineup_container.offset_bottom = 420.0
	_lineup_container.scale = Vector2(0.5, 0.5)
	_lineup_container.stretch = false
	mech_panel.add_child(_lineup_container)

	_lineup_viewport = SubViewport.new()
	_lineup_viewport.size              = Vector2i(1280, 420)
	_lineup_viewport.own_world_3d      = true
	_lineup_viewport.transparent_bg    = false
	_lineup_viewport.handle_input_locally = false
	_lineup_container.add_child(_lineup_viewport)

	var env := Environment.new()
	env.background_mode       = Environment.BG_COLOR
	env.background_color      = Color("#0c0e13")  # T208: repair bay (design)
	env.ambient_light_source  = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color   = Color(0.5, 0.5, 0.6)
	env.ambient_light_energy  = 0.35
	var env_node := WorldEnvironment.new()
	env_node.environment = env
	_lineup_viewport.add_child(env_node)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	light.light_energy     = 0.8  # T208: the gantry downlights carry the scene now
	_lineup_viewport.add_child(light)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size       = 5.5
	cam.position   = Vector3(0.0, 3.5, 10.0)
	cam.look_at_from_position(cam.position, Vector3(0.0, 1.2, 0.0))
	_lineup_viewport.add_child(cam)

	# T208: the repair bay around the 5 mech positions (was a plain platform disc)
	_bay = load("res://scripts/HangarBay.gd").new()
	_bay.name = "HangarBay"
	_lineup_viewport.add_child(_bay)

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
		btn.name = "SlotBtn%d" % i  # T176: harness picks the squad by path
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
		# T220/T227: 3/4 view toward the camera (the design's repair bay); weapons visible
		m.rotation_degrees.y = LINEUP_YAW
		_lineup_viewport.add_child(m)
		if _bay != null:
			_bay.set_bay_mech(i, String(md.display_name))
		m.set_physics_process(false)
		m.remove_from_group("mechs")  # T176: a display prop, not a combatant (sync log, AI scans)
		_arm_display(m, md, i)
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
	$TitleButton.visible = true
	$PresetsButton.visible = true
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
	$TitleButton.visible = false
	$PresetsButton.visible = false
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
	var saved: Array = Game.slot_weapons(_detail_slot) if _detail_slot >= 0 \
		else Game.loadout.get("mech_weapon_choices", {}).get(md.resource_path, [])  # T345: this slot's picks
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
		btn.name = "Roster_" + md.resource_path.get_file().get_basename()  # T176: harness path
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
		Game.set_slot_weapons(_detail_slot, [])  # T345: a new mech here starts from its own last picks
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
	# T308: one stat per line under the weapon picker (one 16 px line ran into the preview)
	mech_stats_label.text = "SPEED: %.2f\nHEALTH: %.0f\nSHIELDS: %s" % [md.walk_speed, md.max_health, shield_str]
	_build_weapon_picker(md)

func _build_weapon_picker(md) -> void:
	var existing := mech_panel.get_node_or_null("WeaponPicker")
	if existing:
		# T173: detach first. queue_free alone kept the name taken until frame end, so the
		# rebuilt picker got an auto-name and _show_squad_screen never found it to hide.
		mech_panel.remove_child(existing)
		existing.queue_free()

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
		row.name = "Slot%d" % i  # T176: Slot<i>/Prev, Slot<i>/Weapon, Slot<i>/Next
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
		prev_btn.name = "Prev"
		prev_btn.text = "<"
		prev_btn.custom_minimum_size = Vector2(22, 0)
		prev_btn.add_theme_font_size_override("font_size", 13)
		prev_btn.pressed.connect(_on_weapon_cycle.bind(i, -1))
		row.add_child(prev_btn)

		var cat_idx: int = _weapon_indices[i] if i < _weapon_indices.size() else 0
		var wep_name: String = WEAPON_CATALOG[cat_idx]["long"] if cat_idx >= 0 else "NONE"

		var wep_lbl := Label.new()
		wep_lbl.name = "Weapon"
		wep_lbl.text = wep_name
		wep_lbl.tooltip_text = weapon_tip(cat_idx)  # T283
		wep_lbl.mouse_filter = Control.MOUSE_FILTER_PASS  # labels ignore the mouse by default: no tooltip
		wep_lbl.add_theme_font_size_override("font_size", 13)
		wep_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wep_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wep_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(wep_lbl)
		_weapon_name_labels.append(wep_lbl)

		var next_btn := Button.new()
		next_btn.name = "Next"
		next_btn.text = ">"
		next_btn.custom_minimum_size = Vector2(22, 0)
		next_btn.add_theme_font_size_override("font_size", 13)
		next_btn.pressed.connect(_on_weapon_cycle.bind(i, 1))
		row.add_child(next_btn)

	# T308: from the picker's real height (rows are 26 px, not row_h: 3-slot mechs overlapped)
	var stats_top: float = picker_top + maxf(slots.size() * row_h, picker.get_combined_minimum_size().y) + 8.0
	mech_stats_label.offset_top = stats_top
	mech_stats_label.offset_bottom = stats_top + 3.0 * 17.0 + 4.0
	mech_stats_label.offset_right = 415.0
	mech_stats_label.add_theme_font_size_override("font_size", 13)  # T308: the picker's size

# T283 (user 2026-11-05: range "in a drop-down mouseover menu", not in the name): hover a
# weapon in the picker for its numbers. Read once per weapon scene.
static var _tips := {}

static func weapon_tip(cat_idx: int) -> String:
	if cat_idx < 0:
		return ""
	var path: String = WEAPON_CATALOG[cat_idx]["path"]
	if not _tips.has(path):
		var w: Node = (load(path) as PackedScene).instantiate()
		var lines: Array = ["RANGE  %d m" % roundi(float(w.get("range")))]
		var dmg: float = float(w.get("max_damage")) if "max_damage" in w else float(w.get("damage"))
		if "pellet_count" in w:
			lines.append("DAMAGE  %.0f x %d" % [dmg, int(w.get("pellet_count"))])
		else:
			lines.append("DAMAGE  %.0f" % dmg)
		if "max_charge_time" in w:
			lines.append("CHARGE  %.0f s" % float(w.get("max_charge_time")))
		else:
			var rate: float = float(w.get("max_fire_rate")) if "max_fire_rate" in w else float(w.get("fire_rate"))
			lines.append("FIRE RATE  %.1f /s" % rate)
		var mag: int = int(w.get("max_ammo"))
		lines.append("MAGAZINE  %s" % ("-" if mag < 0 else str(mag)))
		_tips[path] = "\n".join(lines)
		w.free()
	return _tips[path]

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
		if _detail_slot >= 0:
			# T345: other slots of this mech that never had their own picks follow the mech's last
			# picks -- pin them to what they carry now, then change this slot only
			var sw: Array = Game.loadout.get("squad_weapons", [])
			for j in _squad_paths.size():
				if j != _detail_slot and _squad_paths[j] == md.resource_path \
						and (j >= sw.size() or (sw[j] as Array).is_empty()):
					var now: Array = Game.slot_weapons(j)
					if now.is_empty():
						now = md.weapon_slots.map(func(sl) -> String: return sl.weapon_scene.resource_path if sl.weapon_scene != null else "")
					Game.set_slot_weapons(j, now)
			Game.set_slot_weapons(_detail_slot, paths)
		choices[md.resource_path] = paths  # the mech's last picks: a new slot of it starts here
		Game.loadout["mech_weapon_choices"] = choices
		Game.save_loadout()

	if slot_idx < _weapon_name_labels.size() and is_instance_valid(_weapon_name_labels[slot_idx]):
		_weapon_name_labels[slot_idx].text = WEAPON_CATALOG[_weapon_indices[slot_idx]]["long"]
		_weapon_name_labels[slot_idx].tooltip_text = weapon_tip(_weapon_indices[slot_idx])
	_refresh_diorama_mech()  # T188: the shown mech carries the new pick
	_refresh_lineup_mechs()

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
	m.remove_from_group("mechs")  # T176: a display prop, not a combatant
	_arm_display(m, md, _detail_slot)
	_diorama_mech_node = m

# T188: display mechs carry the weapons this mech will fight with (its saved choices,
# as Lobby._build_squad_data sends them; default slots otherwise). Props: the weapon
# nodes don't process (no reload / fire logic in the hangar).
func _arm_display(m: Node, md: Resource, slot := -1) -> void:
	MechVisuals.arm_display(m, md, Game.slot_weapons(slot) if slot >= 0 \
		else Game.loadout.get("mech_weapon_choices", {}).get(md.resource_path, []))  # T345: per slot

func _show_tab(idx: int) -> void:
	mech_panel.visible = idx == 0
	pilot_panel.visible = idx == 1
	$PresetsButton.visible = idx == 0  # T177: squad screen only (re-shown by _show_squad_screen)
	if idx == 0:
		_show_squad_screen()

func _on_mech_tab_pressed() -> void:
	SoundManager.play_sfx_2d("ui_click")
	_show_tab(0)

func _on_pilot_tab_pressed() -> void:
	SoundManager.play_sfx_2d("ui_click")
	_show_tab(1)

# T176: FIND MATCH comes after the squad is set up; then pick the kind of game.
func _on_matchmaking_pressed() -> void:
	SoundManager.play_sfx_2d("ui_click")
	_on_matchmaking_reset()
	$FindMatchPanel.visible = true

# T336 (user on the T283 weapon tooltip: "Make the box background opaque so it's easier to
# read"): the hangar's tooltips sit on a solid dark box (the engine default is see-through).
func _opaque_tooltips() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.07, 0.08, 0.09, 1.0)
	box.border_color = Color(0.45, 0.5, 0.55, 1.0)
	box.set_border_width_all(1)
	box.set_content_margin_all(6)
	var t := Theme.new()
	t.set_stylebox("panel", "TooltipPanel", box)
	theme = t

# T228: SINGLE PLAYER -> pick the map (was buried in Settings) -> the match starts.
func _on_find_sp_pressed() -> void:
	SoundManager.play_sfx_2d("ui_click")
	$FindMatchPanel/Choices.visible = false
	var box: VBoxContainer = get_node_or_null("FindMatchPanel/MapChoices")
	if box == null:
		box = VBoxContainer.new()
		box.name = "MapChoices"
		box.position = Vector2(160, 80)
		box.custom_minimum_size.x = 320
		box.add_theme_constant_override("separation", 6)
		$FindMatchPanel.add_child(box)
		var head := Label.new()
		head.text = "CHOOSE MAP"
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_theme_font_size_override("font_size", 20)
		box.add_child(head)
		var grid := GridContainer.new()  # two columns: 8+ maps fit the 360 px screen
		grid.columns = 2
		box.add_child(grid)
		for i in MAPS.size():
			var btn := Button.new()
			btn.name = "Map%d" % i
			btn.text = String(load(MAPS[i]).map_name).to_upper()
			btn.custom_minimum_size.y = 26
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.add_theme_font_size_override("font_size", 14)
			btn.pressed.connect(_on_sp_map_pressed.bind(i))
			grid.add_child(btn)
		# T251: bot fill is optional -- how many bots join each side (0 = none)
		var bots := HBoxContainer.new()
		bots.name = "BotRow"
		bots.add_theme_constant_override("separation", 6)
		for spec in [["AllyBots", "ALLY BOTS"], ["EnemyBots", "ENEMY BOTS"]]:
			var l := Label.new()
			l.text = spec[1]
			l.add_theme_font_size_override("font_size", 12)
			bots.add_child(l)
			var sb := SpinBox.new()
			sb.name = spec[0]
			sb.min_value = 0
			sb.max_value = 5
			sb.add_theme_font_size_override("font_size", 12)
			bots.add_child(sb)
		box.add_child(bots)
		# T277 (HUMAN_FOUND 2026-11-05: "Map picker in singleplayer should have a play button so
		# that picking a map doesn't immediately start it"): a map button selects; PLAY starts.
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		box.add_child(row)
		var back := Button.new()  # user: PLAY takes BACK's old place, BACK shifts left
		back.text = "BACK"
		back.custom_minimum_size.x = 70
		back.add_theme_font_size_override("font_size", 14)
		back.pressed.connect(func() -> void:
			box.visible = false
			$FindMatchPanel/Choices.visible = true)
		row.add_child(back)
		var dm := CheckBox.new()  # T285: death match -- no beacons, last team with mechs wins
		dm.name = "SpDeathMatch"
		dm.text = "DEATH MATCH"
		dm.add_theme_font_size_override("font_size", 12)
		row.add_child(dm)
		var play := Button.new()
		play.name = "SpPlay"
		play.text = "PLAY"
		play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		play.add_theme_font_size_override("font_size", 14)
		play.pressed.connect(_on_sp_play_pressed)
		row.add_child(play)
	var ts: int = int(Game.loadout.get("team_size", 3))
	var counts = Game.loadout.get("sp_bots")
	if not (counts is Array and counts.size() == 2):
		counts = [maxi(0, ts - 1), ts]  # default: the old fill to team_size
	(box.find_child("AllyBots", true, false) as SpinBox).value = int(counts[0])
	(box.find_child("EnemyBots", true, false) as SpinBox).value = int(counts[1])
	(box.find_child("SpDeathMatch", true, false) as CheckBox).button_pressed = Game.loadout.get("mode", "beacons") == "deathmatch"
	var cur = Game.loadout.get("map_def")
	if cur == null or not MAPS.has(cur.resource_path):
		Game.loadout["map_def"] = load(MAPS[0])  # T277: PLAY always has a map
	_highlight_sp_map(box)
	box.visible = true

func _highlight_sp_map(box: Node) -> void:
	var cur = Game.loadout.get("map_def")
	for i in MAPS.size():  # the current pick is highlighted
		var btn: Button = box.find_child("Map%d" % i, true, false)
		if cur != null and cur.resource_path == MAPS[i]:
			btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
		else:
			btn.remove_theme_color_override("font_color")

func _on_sp_map_pressed(idx: int) -> void:
	SoundManager.play_sfx_2d("ui_click")
	Game.loadout["map_def"] = load(MAPS[idx])
	Game.save_loadout()
	_highlight_sp_map(get_node("FindMatchPanel/MapChoices"))

func _on_sp_play_pressed() -> void:
	SoundManager.play_sfx_2d("ui_click")
	var box := get_node("FindMatchPanel/MapChoices")
	Game.loadout["sp_bots"] = [int((box.find_child("AllyBots", true, false) as SpinBox).value),
		int((box.find_child("EnemyBots", true, false) as SpinBox).value)]  # T251
	Game.loadout["mode"] = "deathmatch" if (box.find_child("SpDeathMatch", true, false) as CheckBox).button_pressed else "beacons"
	Game.save_loadout()
	Game.start_sp_match()  # T184: a local MP match with bot fill

func _on_find_host_pressed() -> void:
	_open_mp_entry(0)

func _on_find_join_pressed() -> void:
	_open_mp_entry(1)

func _open_mp_entry(tab: int) -> void:
	SoundManager.play_sfx_2d("ui_click")
	Game.save_loadout()  # the lobby reads this squad (Lobby._build_squad_data)
	Game.mp_entry_tab = tab
	get_tree().change_scene_to_file("res://scenes/ui/MPEntry.tscn")

# ---- T177: squad presets (whole squad + its weapon choices, by name; Game.save_preset) ----

func _on_presets_pressed() -> void:
	SoundManager.play_sfx_2d("ui_click")
	_rebuild_preset_list()
	$PresetPanel.visible = true

func _on_preset_close_pressed() -> void:
	SoundManager.play_sfx_2d("ui_click")
	$PresetPanel.visible = false

func _on_preset_name_submitted(_text: String) -> void:
	_on_preset_save_pressed()

func _on_preset_save_pressed() -> void:
	var edit: LineEdit = $PresetPanel/Box/SaveRow/NameEdit
	var pname := edit.text.strip_edges()
	if pname.is_empty():
		return
	SoundManager.play_sfx_2d("ui_click")
	Game.save_preset(pname)
	edit.text = ""
	_rebuild_preset_list()

func _rebuild_preset_list() -> void:
	var list: VBoxContainer = $PresetPanel/Box/Scroll/List
	for c in list.get_children():
		list.remove_child(c)  # B72: free the row names now
		c.queue_free()
	var names: Array = Game.loadout.get("presets", {}).keys()
	names.sort()
	for i in names.size():
		var row := HBoxContainer.new()
		row.name = "Preset%d" % i
		var lbl := Label.new()
		lbl.name = "Name"
		lbl.text = names[i]
		lbl.clip_text = true
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 14)
		row.add_child(lbl)
		for b in [["Load", "LOAD", _on_preset_load], ["Delete", "DELETE", _on_preset_delete]]:
			var btn := Button.new()
			btn.name = b[0]
			btn.text = b[1]
			btn.add_theme_font_size_override("font_size", 12)
			btn.pressed.connect((b[2] as Callable).bind(names[i]))
			row.add_child(btn)
		list.add_child(row)
	$PresetPanel/Box/Empty.visible = names.is_empty()

func _on_preset_load(pname: String) -> void:
	SoundManager.play_sfx_2d("ui_click")
	if not Game.load_preset(pname):
		return
	_load_squad()
	_refresh_lineup_mechs()
	_refresh_slot_btn_labels()
	$PresetPanel.visible = false

func _on_preset_delete(pname: String) -> void:
	SoundManager.play_sfx_2d("ui_click")
	Game.delete_preset(pname)
	_rebuild_preset_list()

func _on_find_cancel_pressed() -> void:
	SoundManager.play_sfx_2d("ui_click")
	$FindMatchPanel.visible = false

func _on_matchmaking_reset() -> void:
	$FindMatchPanel/Choices.visible = true
	var box := get_node_or_null("FindMatchPanel/MapChoices")
	if box != null:
		box.visible = false

func _on_settings_pressed() -> void:
	SoundManager.play_sfx_2d("ui_click")
	get_tree().change_scene_to_file("res://scenes/ui/Settings.tscn")

# B-f: the hangar was a dead end -- multiplayer (Title -> MPEntry) was unreachable
# without restarting the game.
func _on_title_pressed() -> void:
	SoundManager.play_sfx_2d("ui_click")
	get_tree().change_scene_to_file("res://scenes/ui/TitleScreen.tscn")

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
	hdr.text = "SKILLS"
	hdr.offset_left   = 16.0
	hdr.offset_top    = 98.0
	hdr.offset_right  = 630.0
	hdr.offset_bottom = 114.0
	hdr.add_theme_font_size_override("font_size", 14)
	pilot_panel.add_child(hdr)

	var scroll := ScrollContainer.new()
	scroll.offset_left   = 0.0
	scroll.offset_top    = 118.0
	scroll.offset_right  = 640.0
	scroll.offset_bottom = 244.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pilot_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	_prog_nodes_container = vbox
	_build_progression_nodes()

func _refresh_pilot_stats() -> void:
	if _pilot_stats_label == null:
		return
	var lv: int    = Game.profile.get("level", 1)
	var xp: int    = Game.profile.get("xp", 0)
	var elo: int   = Game.profile.get("elo", 1000)
	var coins: int = Game.profile.get("coins", 0)
	var sp: int    = Game.skill_points_available()
	var xp_left: int = Game.xp_to_next_level()
	if xp_left > 0:
		_pilot_stats_label.text = "LVL: %d  |  XP: %d (+%d to next)  |  ELO: %d  |  COINS: %d  |  SP: %d" % [
			lv, xp, xp_left, elo, coins, sp]
	else:
		_pilot_stats_label.text = "LVL: %d (MAX)  |  XP: %d  |  ELO: %d  |  COINS: %d  |  SP: %d" % [
			lv, xp, elo, coins, sp]

func _skill_depth(key: String) -> int:
	var def: Dictionary = Game.SKILL_TREE.get(key, {})
	var parents: Array = def.get("parents", [])
	if parents.is_empty():
		return 0
	var max_parent_depth: int = 0
	for p: String in parents:
		max_parent_depth = maxi(max_parent_depth, _skill_depth(p))
	return max_parent_depth + 1

# T347 (HUMAN_FOUND 2026-11-08: "skill tree visual: a real branching tree -- a root system with the
# lowest tiers at the top, like the Age of Empires II tech tree"): one node per skill, tier by tier
# (a skill sits one row below its deepest parent), each row ordered under its parents so the
# lines don't cross; a line from every parent to its child, lit once the parent is owned. A node
# shows the name, level and (T361) the numbers; clicking it buys / upgrades; the tooltip says all.
const TREE_NODE := Vector2(86.0, 30.0)
const TREE_ROW := 38.0
const TREE_W := 640.0

func _build_progression_nodes() -> void:
	if _prog_nodes_container == null:
		return
	for child in _prog_nodes_container.get_children():
		_prog_nodes_container.remove_child(child)  # detached now: the new tree keeps its name
		child.queue_free()
	var rows: Array = []  # depth -> [keys]
	for key: String in Game.SKILL_TREE.keys():
		var d := _skill_depth(key)
		while rows.size() <= d:
			rows.append([])
		rows[d].append(key)
	var pos := {}  # key -> node top-left
	for d in rows.size():
		var row: Array = rows[d]
		if d > 0:  # under its parents: order by the parents' mean x
			row.sort_custom(func(p: String, q: String) -> bool: return _parents_x(p, pos) < _parents_x(q, pos))
		var step := TREE_W / float(row.size())
		for i in row.size():
			pos[row[i]] = Vector2(step * (float(i) + 0.5) - TREE_NODE.x * 0.5, 4.0 + TREE_ROW * float(d))
	var tree := Control.new()
	tree.name = "SkillTree"
	tree.custom_minimum_size = Vector2(TREE_W, 8.0 + TREE_ROW * float(rows.size()))
	_prog_nodes_container.add_child(tree)
	for key: String in Game.SKILL_TREE.keys():  # the lines first: under the nodes
		for p: String in Game.SKILL_TREE[key].get("parents", []):
			var line := Line2D.new()
			line.name = "Edge_%s_%s" % [p, key]
			line.width = 1.5
			line.default_color = Color(0.45, 0.85, 0.5) if Game.skill_level(p) > 0 else Color(0.35, 0.36, 0.4)
			line.add_point(pos[p] + Vector2(TREE_NODE.x * 0.5, TREE_NODE.y))
			line.add_point(pos[key] + Vector2(TREE_NODE.x * 0.5, 0.0))
			tree.add_child(line)
	for key: String in Game.SKILL_TREE.keys():
		tree.add_child(_skill_node(key, pos[key]))

func _parents_x(key: String, pos: Dictionary) -> float:
	var ps: Array = Game.SKILL_TREE[key].get("parents", [])
	var x := 0.0
	for p in ps:
		x += (pos[p] as Vector2).x
	return x / maxf(1.0, float(ps.size()))

func _skill_node(key: String, at: Vector2) -> Button:
	var def: Dictionary = Game.SKILL_TREE[key]
	var lv: int = Game.skill_level(key)
	var label_str: String = def.get("label", key)
	var btn := Button.new()
	btn.name = "Skill_%s" % key
	btn.position = at
	btn.size = TREE_NODE
	btn.clip_text = true
	btn.add_theme_font_size_override("font_size", 8 if label_str.length() <= 14 else 7)  # long names fit
	var tip := label_str
	if lv == 0:
		btn.text = "%s\n%s / lv" % [label_str.to_upper(), Game.skill_effect_text(key, 1)]
		var parents: Array = def.get("parents", [])
		var needs: Array = parents.filter(func(p): return Game.skill_level(p) == 0)
		tip += "  --  LOCKED: %s per level" % Game.skill_effect_text(key, 1)
		if Game.can_unlock(key):
			tip += "\nClick: BUY (1 SP)"
			btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
		elif not needs.is_empty():
			tip += "\nNeeds: %s" % ", ".join(needs.map(func(p): return Game.SKILL_TREE[p].get("label", p)))
			btn.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		btn.pressed.connect(_on_skill_unlock.bind(key))
		btn.disabled = not Game.can_unlock(key)
	elif lv >= 12:
		btn.text = "%s\n12/12  %s" % [label_str.to_upper(), Game.skill_effect_text(key, lv)]
		tip += "  --  LV 12/12  %s  MAX" % Game.skill_effect_text(key, lv)
		btn.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
		btn.disabled = true
	else:
		btn.text = "%s\n%d/12  %s>%s" % [label_str.to_upper(), lv, Game.skill_effect_text(key, lv), Game.skill_effect_text(key, lv + 1)]
		tip += "  --  LV %d/12  %s -> %s  (%d coins to upgrade)" % [lv, Game.skill_effect_text(key, lv),
			Game.skill_effect_text(key, lv + 1), Game._SKILL_FIB_COSTS[lv - 1]]
		btn.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0) if Game.can_upgrade(key) else Color(0.85, 0.85, 0.85))
		btn.pressed.connect(_on_skill_upgrade.bind(key))
		btn.disabled = not Game.can_upgrade(key)
	btn.tooltip_text = tip
	return btn

func _on_skill_unlock(key: String) -> void:
	SoundManager.play_sfx_2d("ui_click")
	var ok := false
	if Game.account.is_empty():
		ok = Game.unlock_skill(key)
	else:
		ok = await Game.account_skill("unlock_skill", key)  # T213: the account's server decides
	if Game.account_notice != "" and is_inside_tree():  # T403: login expired -> log in again
		Game.account_mode = "login"
		get_tree().change_scene_to_file("res://scenes/ui/Account.tscn")
		return
	if ok and is_inside_tree():
		_refresh_pilot_stats()
		_build_progression_nodes()

func _on_skill_upgrade(key: String) -> void:
	SoundManager.play_sfx_2d("ui_click")
	var ok := false
	if Game.account.is_empty():
		ok = Game.upgrade_skill(key)
	else:
		ok = await Game.account_skill("upgrade_skill", key)  # T213: the account's server decides
	if Game.account_notice != "" and is_inside_tree():  # T403: login expired -> log in again
		Game.account_mode = "login"
		get_tree().change_scene_to_file("res://scenes/ui/Account.tscn")
		return
	if ok and is_inside_tree():
		_refresh_pilot_stats()
		_build_progression_nodes()

