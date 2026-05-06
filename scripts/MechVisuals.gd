class_name MechVisuals

# Apply per-mech body geometry. Call after instantiate() but before add_child()
# so accessories are present when Mech._ready() builds _body_meshes.
static func apply(mech: Node3D, display_name: String) -> void:
	match display_name:
		"Slip":       _slip(mech)
		"Cesh":       _cesh(mech)
		"Seeker":     _seeker(mech)
		"Lynx":       _lynx(mech)
		"Hornet":     _hornet(mech)
		"Hippogriff": _hippogriff(mech)
		"Kestrel":    _kestrel(mech)
		"Pegasus":    _pegasus(mech)
		"Everest":    _everest(mech)
		"Vesuvius":   _vesuvius(mech)
		"Warhog":     _warhog(mech)


# ---- mesh setters ----

static func _bm(mi: MeshInstance3D, sz: Vector3) -> void:
	if mi == null:
		return
	var m := BoxMesh.new()
	m.size = sz
	mi.mesh = m

static func _cyl(mi: MeshInstance3D, tr: float, br: float, h: float, segs: int = 16) -> void:
	if mi == null:
		return
	var m := CylinderMesh.new()
	m.top_radius = tr
	m.bottom_radius = br
	m.height = h
	m.radial_segments = segs
	mi.mesh = m

static func _sph(mi: MeshInstance3D, r: float) -> void:
	if mi == null:
		return
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	mi.mesh = m


# ---- material helpers ----

static func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	return m

static func _mat_e(col: Color, emit: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = emit
	m.emission_energy_multiplier = energy
	return m

static func _paint(mi: MeshInstance3D, mat: StandardMaterial3D) -> void:
	if mi:
		mi.set_surface_override_material(0, mat)

static func _paint_all(parent: Node3D, mat: StandardMaterial3D) -> void:
	if parent == null:
		return
	for child in parent.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).set_surface_override_material(0, mat)


# ---- accessory factories (added as Torso or Legs children) ----

static func _add_box(parent: Node3D, pos: Vector3, sz: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = sz
	mi.mesh = m
	mi.position = pos
	parent.add_child(mi)
	return mi

static func _add_cyl(parent: Node3D, pos: Vector3, tr: float, br: float, h: float, segs: int = 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = tr
	m.bottom_radius = br
	m.height = h
	m.radial_segments = segs
	mi.mesh = m
	mi.position = pos
	parent.add_child(mi)
	return mi


# ---- leg segment helpers ----

static func _leg_segs(l: Node3D, upper: Vector3, mid: Vector3, lower: Vector3) -> void:
	_bm(l.get_node_or_null("LeftHip/UpperLeft") as MeshInstance3D,                         upper)
	_bm(l.get_node_or_null("RightHip/UpperRight") as MeshInstance3D,                       upper)
	_bm(l.get_node_or_null("LeftHip/LeftKnee1/MidLeft") as MeshInstance3D,                 mid)
	_bm(l.get_node_or_null("RightHip/RightKnee1/MidRight") as MeshInstance3D,              mid)
	_bm(l.get_node_or_null("LeftHip/LeftKnee1/LeftKnee2/LowerLeft") as MeshInstance3D,     lower)
	_bm(l.get_node_or_null("RightHip/RightKnee1/RightKnee2/LowerRight") as MeshInstance3D, lower)

# Light class: long thin sprinter legs, blade feet
static func _light_legs(l: Node3D) -> void:
	_leg_segs(l, Vector3(0.18, 0.60, 0.17), Vector3(0.16, 0.60, 0.15), Vector3(0.14, 0.18, 0.32))

# Heavy class: thick pillar legs
static func _heavy_legs(l: Node3D) -> void:
	_leg_segs(l, Vector3(0.28, 0.55, 0.26), Vector3(0.26, 0.55, 0.24), Vector3(0.24, 0.55, 0.22))


# ==== per-mech designs ====
# All positions are in Torso-space (Torso node is at mech root, no offset).
# Mech faces -Z. +Z is back. +X is left when facing mech from front.
# Key Torso-space landmarks (default): Waist Y=1.02, Body Y=1.42, Shoulders Y=1.72 +/-0.68X, Head Y=1.92


# Slip: aerodynamic sprinter -- navy blue armor, cyan visor glow
static func _slip(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	var armor  := _mat(Color(0.22, 0.30, 0.55))
	var detail := _mat(Color(0.14, 0.20, 0.38))
	var glow   := _mat_e(Color(0, 0, 0), Color(0.10, 0.85, 1.0), 3.0)
	if t:
		var body  := t.get_node_or_null("Body") as MeshInstance3D
		var waist := t.get_node_or_null("Waist") as MeshInstance3D
		var head  := t.get_node_or_null("Head") as MeshInstance3D
		var sl    := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr    := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_bm(body,  Vector3(0.72, 0.55, 0.85))
		_bm(waist, Vector3(0.52, 0.14, 0.60))
		_bm(head,  Vector3(0.36, 0.20, 0.44))
		_bm(sl, Vector3(0.15, 0.16, 0.48))
		_bm(sr, Vector3(0.15, 0.16, 0.48))
		if sl: sl.position.x = -0.52
		if sr: sr.position.x =  0.52
		_paint(body, armor); _paint(waist, armor); _paint(head, armor)
		_paint(sl, armor);   _paint(sr, armor)
		# visor slit flush with head front face (head front = z -0.22)
		_paint(_add_box(t, Vector3(0.0, 1.92, -0.21),   Vector3(0.28, 0.05, 0.02)), glow)
		# neck connecting body top (1.695) to head bottom (1.82)
		_paint(_add_box(t, Vector3(0.0, 1.76, 0.0),     Vector3(0.22, 0.14, 0.28)), armor)
		# shoulder brackets
		_paint(_add_box(t, Vector3(-0.44, 1.72, 0.0),   Vector3(0.16, 0.10, 0.36)), detail)
		_paint(_add_box(t, Vector3( 0.44, 1.72, 0.0),   Vector3(0.16, 0.10, 0.36)), detail)
		# front body armor panels
		_paint(_add_box(t, Vector3(-0.20, 1.36, -0.43), Vector3(0.16, 0.18, 0.02)), detail)
		_paint(_add_box(t, Vector3( 0.20, 1.36, -0.43), Vector3(0.16, 0.18, 0.02)), detail)
		# dorsal fin
		_paint(_add_box(t, Vector3(0.0, 1.70, 0.43),    Vector3(0.05, 0.22, 0.02)), detail)
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(0.78, 0.18, 0.44))
		_leg_segs(l, Vector3(0.17, 0.62, 0.16), Vector3(0.15, 0.62, 0.14), Vector3(0.13, 0.16, 0.34))
		_paint_all(l, armor)


# Cesh: hunched stealth predator -- dark olive, no emissive
static func _cesh(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	var armor  := _mat(Color(0.22, 0.28, 0.20))
	var detail := _mat(Color(0.32, 0.40, 0.29))
	if t:
		var body  := t.get_node_or_null("Body") as MeshInstance3D
		var waist := t.get_node_or_null("Waist") as MeshInstance3D
		var head  := t.get_node_or_null("Head") as MeshInstance3D
		var sl    := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr    := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		# body h=0.66: bottom=1.09=waist_top, top=1.75; radius at Y=1.72: r=0.421
		_cyl(body, 0.42, 0.44, 0.66)
		_bm(waist, Vector3(0.56, 0.14, 0.56))
		_bm(head,  Vector3(0.36, 0.20, 0.42))
		_bm(sl, Vector3(0.20, 0.18, 0.52))
		_bm(sr, Vector3(0.20, 0.18, 0.52))
		# shoulder_x = cylinder_r_at_1.72(0.421) + shoulder_hw(0.10) = 0.521
		if sl: sl.position.x = -0.52
		if sr: sr.position.x =  0.52
		_paint(body, armor); _paint(waist, armor); _paint(head, armor)
		_paint(sl, armor);   _paint(sr, armor)
		# sensor pod: base at shoulder_top(1.81), center Y=1.90, X matches shoulder center
		_paint(_add_cyl(t, Vector3(-0.52, 1.90, 0.0), 0.08, 0.08, 0.18, 8), detail)
		# neck: spans body_top(1.75) to head_bottom(1.82)
		_paint(_add_box(t, Vector3(0.0, 1.785, 0.0),  Vector3(0.30, 0.12, 0.38)), armor)
		# backpack plate: cylinder Z-surface at Y=1.58 = 0.425, plate at 0.44
		_paint(_add_box(t, Vector3(0.0, 1.58, 0.44),  Vector3(0.38, 0.26, 0.04)), detail)
		# vent strips: cylinder X at Y=1.42 = 0.43, vent center at 0.44
		_paint(_add_box(t, Vector3( 0.44, 1.42, 0.0), Vector3(0.02, 0.22, 0.32)), detail)
		_paint(_add_box(t, Vector3(-0.44, 1.42, 0.0), Vector3(0.02, 0.22, 0.32)), detail)
		# waist face panels
		_paint(_add_box(t, Vector3(0.0, 1.08, -0.29), Vector3(0.36, 0.06, 0.02)), detail)
		_paint(_add_box(t, Vector3(0.0, 1.08,  0.29), Vector3(0.36, 0.06, 0.02)), detail)
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(0.90, 0.20, 0.52))
		_leg_segs(l, Vector3(0.18, 0.44, 0.17), Vector3(0.16, 0.40, 0.15), Vector3(0.14, 0.38, 0.14))
		_paint_all(l, armor)


# Seeker: dense sensor-ball head, asymmetric heavy shoulder -- slate purple, amber sensor glow
static func _seeker(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	var armor  := _mat(Color(0.32, 0.28, 0.44))
	var detail := _mat(Color(0.20, 0.18, 0.28))
	var glow   := _mat_e(Color(0, 0, 0), Color(1.0, 0.45, 0.05), 3.0)
	if t:
		var body  := t.get_node_or_null("Body") as MeshInstance3D
		var waist := t.get_node_or_null("Waist") as MeshInstance3D
		var head  := t.get_node_or_null("Head") as MeshInstance3D
		var sl    := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr    := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		# body h=0.64: bottom=1.10=waist_top, top=1.74; radius at Y=1.72: r=0.263
		_cyl(body, 0.26, 0.34, 0.64)
		_bm(waist, Vector3(0.56, 0.16, 0.52))
		if head: head.mesh = null  # gun replaces head
		_bm(sl, Vector3(0.20, 0.24, 0.46))
		_bm(sr, Vector3(0.20, 0.24, 0.46))
		# shoulder_x = cylinder_r_at_1.72(0.263) + shoulder_hw(0.10) = 0.363
		if sl: sl.position.x = -0.36
		if sr: sr.position.x =  0.36
		_paint(body, armor); _paint(waist, armor)
		_paint(sl, armor);   _paint(sr, armor)
		# gun mount pedestal: bottom=1.73, body_top=1.74, touching
		_paint(_add_cyl(t, Vector3(0.0, 1.78, 0.0),       0.18, 0.22, 0.10), armor)
		# sensor rings: X matches shoulder center, Y=shoulder_top(1.84)+ring_half_h(0.01)
		_paint(_add_cyl(t, Vector3(-0.36, 1.85, 0.0),     0.12, 0.12, 0.02, 6), glow)
		_paint(_add_cyl(t, Vector3( 0.36, 1.85, 0.0),     0.12, 0.12, 0.02, 6), glow)
		# sensor strip: body front at Y=1.52 = Z=-0.288, strip at -0.30
		_paint(_add_box(t, Vector3(0.0, 1.52, -0.30),     Vector3(0.28, 0.06, 0.02)), glow)
		# collar band: wraps body at Y=1.68 (body r=0.268), ring r=0.28 clears body
		_paint(_add_cyl(t, Vector3(0.0, 1.68, 0.0),       0.28, 0.28, 0.04, 10), detail)
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(0.76, 0.18, 0.46))
		_leg_segs(l, Vector3(0.19, 0.46, 0.18), Vector3(0.17, 0.46, 0.16), Vector3(0.15, 0.46, 0.14))
		_paint_all(l, armor)


# Lynx: lithe cat silhouette -- forest green, amber antenna glow
static func _lynx(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	var armor  := _mat(Color(0.22, 0.40, 0.22))
	var detail := _mat(Color(0.14, 0.26, 0.14))
	var glow   := _mat_e(Color(0, 0, 0), Color(1.0, 0.65, 0.05), 2.5)
	if t:
		var body  := t.get_node_or_null("Body") as MeshInstance3D
		var waist := t.get_node_or_null("Waist") as MeshInstance3D
		var head  := t.get_node_or_null("Head") as MeshInstance3D
		var sl    := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr    := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_cyl(body, 0.30, 0.38, 0.58)
		_bm(waist, Vector3(0.56, 0.14, 0.56))
		_bm(head,  Vector3(0.32, 0.26, 0.46))
		_bm(sl, Vector3(0.16, 0.18, 0.50))
		_bm(sr, Vector3(0.16, 0.18, 0.50))
		if sl: sl.position.x = -0.52
		if sr: sr.position.x =  0.52
		_paint(body, armor); _paint(waist, armor); _paint(head, armor)
		_paint(sl, armor);   _paint(sr, armor)
		# antenna spike
		_paint(_add_box(t, Vector3(0.0, 2.10, 0.0),      Vector3(0.04, 0.20, 0.04)), glow)
		# neck cylinder
		_paint(_add_cyl(t, Vector3(0.0, 1.75, 0.0),      0.16, 0.18, 0.08), armor)
		# cat ear spikes
		_paint(_add_box(t, Vector3(-0.11, 2.08, 0.0),    Vector3(0.04, 0.14, 0.04)), glow)
		_paint(_add_box(t, Vector3( 0.11, 2.08, 0.0),    Vector3(0.04, 0.14, 0.04)), glow)
		# shoulder-body connector brackets
		_paint(_add_box(t, Vector3(-0.44, 1.72, 0.0),    Vector3(0.16, 0.10, 0.36)), detail)
		_paint(_add_box(t, Vector3( 0.44, 1.72, 0.0),    Vector3(0.16, 0.10, 0.36)), detail)
		# lower back tail stub
		_paint(_add_box(t, Vector3(0.0, 1.26, 0.40),     Vector3(0.06, 0.08, 0.04)), detail)
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(0.80, 0.18, 0.46))
		_leg_segs(l, Vector3(0.17, 0.64, 0.16), Vector3(0.15, 0.64, 0.14), Vector3(0.13, 0.20, 0.28))
		_paint_all(l, armor)


# Hornet: F-18 jet -- navy grey, pale blue cockpit glow
static func _hornet(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	var armor  := _mat(Color(0.24, 0.28, 0.44))
	var detail := _mat(Color(0.16, 0.18, 0.30))
	var exhaust := _mat(Color(0.14, 0.14, 0.16))
	var glow   := _mat_e(Color(0, 0, 0), Color(0.60, 0.80, 1.0), 2.0)
	if t:
		var body  := t.get_node_or_null("Body") as MeshInstance3D
		var waist := t.get_node_or_null("Waist") as MeshInstance3D
		var head  := t.get_node_or_null("Head") as MeshInstance3D
		var sl    := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr    := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		# body h=0.64: bottom=1.10(waist_top=1.11, gap=0.01), top=1.74; r at Y=1.72: 0.382
		_cyl(body, 0.38, 0.44, 0.64, 10)
		_bm(waist, Vector3(0.56, 0.18, 0.66))
		_cyl(head, 0.18, 0.24, 0.40, 8)
		_bm(sl, Vector3(0.38, 0.14, 0.70))
		_bm(sr, Vector3(0.38, 0.14, 0.70))
		if sl: sl.position.x = -0.80
		if sr: sr.position.x =  0.80
		_paint(body, armor); _paint(waist, armor); _paint(head, armor)
		_paint(sl, armor);   _paint(sr, armor)
		# twin engine nacelles (front at Z=0.34, body back at Y=1.20 = 0.431, embedded ok)
		_paint(_add_cyl(t, Vector3(-0.22, 1.20, 0.46), 0.10, 0.12, 0.40, 10), exhaust)
		_paint(_add_cyl(t, Vector3( 0.22, 1.20, 0.46), 0.10, 0.12, 0.40, 10), exhaust)
		# arm struts: inner=body_r_at_1.72(0.382), outer=shoulder_inner(0.61), center=0.496, w=0.228
		_paint(_add_box(t, Vector3(-0.496, 1.72, 0.0), Vector3(0.228, 0.10, 0.36)), detail)
		_paint(_add_box(t, Vector3( 0.496, 1.72, 0.0), Vector3(0.228, 0.10, 0.36)), detail)
		# fuselage-cockpit taper ring: body_top=1.74, head_bottom=1.72, bridges step
		_paint(_add_cyl(t, Vector3(0.0, 1.74, 0.0),    0.25, 0.38, 0.04, 10), armor)
		# cockpit visor: head front at Y=1.96 = Z=-0.204, strip at -0.20
		_paint(_add_box(t, Vector3(0.0, 1.96, -0.20),  Vector3(0.28, 0.10, 0.02)), glow)
		# air intake ducts: body front at Y=1.24 = Z=-0.427, ducts at -0.43
		_paint(_add_box(t, Vector3(-0.22, 1.24, -0.43), Vector3(0.14, 0.10, 0.02)), detail)
		_paint(_add_box(t, Vector3( 0.22, 1.24, -0.43), Vector3(0.14, 0.10, 0.02)), detail)
		# nacelle mounting pylons
		_paint(_add_box(t, Vector3(-0.22, 1.20, 0.34),  Vector3(0.08, 0.10, 0.12)), detail)
		_paint(_add_box(t, Vector3( 0.22, 1.20, 0.34),  Vector3(0.08, 0.10, 0.12)), detail)
	if l:
		_paint_all(l, armor)


# Hippogriff: B-29 bomber -- khaki olive, red nose turret glow
static func _hippogriff(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	var armor  := _mat(Color(0.40, 0.40, 0.26))
	var detail := _mat(Color(0.26, 0.26, 0.16))
	var glow   := _mat_e(Color(0, 0, 0), Color(1.0, 0.15, 0.05), 3.0)
	if t:
		var body  := t.get_node_or_null("Body") as MeshInstance3D
		var waist := t.get_node_or_null("Waist") as MeshInstance3D
		var head  := t.get_node_or_null("Head") as MeshInstance3D
		var sl    := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr    := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_cyl(body, 0.46, 0.52, 0.64)
		_bm(waist, Vector3(0.76, 0.22, 0.68))
		_sph(head, 0.24)
		_bm(sl, Vector3(0.42, 0.15, 0.74))
		_bm(sr, Vector3(0.42, 0.15, 0.74))
		if sl: sl.position.x = -0.80
		if sr: sr.position.x =  0.80
		_paint(body, armor); _paint(waist, armor); _paint(head, armor)
		_paint(sl, armor);   _paint(sr, armor)
		# nose turret
		_paint(_add_box(t, Vector3(0.0, 1.92, -0.28),  Vector3(0.09, 0.09, 0.08)), glow)
		# bomb bay door plates
		_paint(_add_box(t, Vector3(-0.16, 1.10, 0.0), Vector3(0.20, 0.02, 0.52)), detail)
		_paint(_add_box(t, Vector3( 0.16, 1.10, 0.0), Vector3(0.20, 0.02, 0.52)), detail)
		# wing struts
		_paint(_add_box(t, Vector3(-0.54, 1.70, 0.0), Vector3(0.22, 0.08, 0.56)), armor)
		_paint(_add_box(t, Vector3( 0.54, 1.70, 0.0), Vector3(0.22, 0.08, 0.56)), armor)
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(1.08, 0.24, 0.60))
		_leg_segs(l, Vector3(0.26, 0.52, 0.24), Vector3(0.24, 0.52, 0.22), Vector3(0.22, 0.52, 0.20))
		_paint_all(l, armor)


# Kestrel: energy shield tech -- indigo, cyan shield emitter glow
static func _kestrel(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	var armor  := _mat(Color(0.20, 0.22, 0.54))
	var detail := _mat(Color(0.13, 0.14, 0.36))
	var glow   := _mat_e(Color(0, 0, 0), Color(0.10, 0.85, 1.0), 4.0)
	if t:
		var body  := t.get_node_or_null("Body") as MeshInstance3D
		var waist := t.get_node_or_null("Waist") as MeshInstance3D
		var head  := t.get_node_or_null("Head") as MeshInstance3D
		var sl    := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr    := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_cyl(body, 0.40, 0.46, 0.62, 6)
		_bm(waist, Vector3(0.65, 0.18, 0.58))
		_cyl(head, 0.17, 0.17, 0.28, 8)
		_cyl(sl, 0.18, 0.20, 0.22, 6)
		_cyl(sr, 0.18, 0.20, 0.22, 6)
		# shoulder_x = body_r_at_1.72(0.401) + shoulder_br(0.20) = 0.601
		if sl: sl.position.x = -0.60
		if sr: sr.position.x =  0.60
		_paint(body, armor); _paint(waist, armor); _paint(head, armor)
		_paint(sl, armor);   _paint(sr, armor)
		# shield emitter cross at waist
		_paint(_add_box(t, Vector3(0.0, 1.02, 0.0), Vector3(1.10, 0.06, 0.04)), glow)
		_paint(_add_box(t, Vector3(0.0, 1.02, 0.0), Vector3(0.04, 0.06, 1.10)), glow)
		# short neck cylinder
		_paint(_add_cyl(t, Vector3(0.0, 1.755, 0.0), 0.15, 0.17, 0.05, 8), armor)
		# hex emitter rings: X matches shoulder center (0.60), Y=shoulder_top(1.83)+ring_half_h(0.01)
		_paint(_add_cyl(t, Vector3(-0.60, 1.84, 0.0), 0.16, 0.16, 0.02, 6), glow)
		_paint(_add_cyl(t, Vector3( 0.60, 1.84, 0.0), 0.16, 0.16, 0.02, 6), glow)
		# energy conduit strip on body front
		_paint(_add_box(t, Vector3(0.0, 1.42, -0.42), Vector3(0.04, 0.52, 0.02)), glow)
	if l:
		_paint_all(l, armor)


# Pegasus: angelic mobility mech -- bright silver, gold jet/crest glow
static func _pegasus(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	var armor  := _mat(Color(0.54, 0.54, 0.58))
	var detail := _mat(Color(0.36, 0.36, 0.40))
	var glow   := _mat_e(Color(0, 0, 0), Color(1.0, 0.75, 0.10), 3.0)
	if t:
		var body  := t.get_node_or_null("Body") as MeshInstance3D
		var waist := t.get_node_or_null("Waist") as MeshInstance3D
		var head  := t.get_node_or_null("Head") as MeshInstance3D
		var sl    := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr    := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_bm(body,  Vector3(0.86, 0.60, 0.72))
		_bm(waist, Vector3(0.58, 0.16, 0.60))
		_bm(head,  Vector3(0.36, 0.34, 0.42))
		_bm(sl, Vector3(0.22, 0.20, 0.58))
		_bm(sr, Vector3(0.22, 0.20, 0.58))
		if sl: sl.position = Vector3(-0.54, 1.82, 0.0)
		if sr: sr.position = Vector3( 0.54, 1.82, 0.0)
		_paint(body, armor); _paint(waist, armor); _paint(head, armor)
		_paint(sl, armor);   _paint(sr, armor)
		# jump jets
		_paint(_add_cyl(t, Vector3(-0.18, 1.32, 0.44), 0.10, 0.12, 0.48, 10), glow)
		_paint(_add_cyl(t, Vector3( 0.18, 1.32, 0.44), 0.10, 0.12, 0.48, 10), glow)
		# head crest
		_paint(_add_box(t, Vector3(0.0, 2.08, 0.0),    Vector3(0.06, 0.18, 0.04)), glow)
		# thin neck
		_paint(_add_box(t, Vector3(0.0, 1.735, 0.0),   Vector3(0.26, 0.03, 0.34)), detail)
		# jet mounting brackets
		_paint(_add_box(t, Vector3(-0.18, 1.32, 0.38), Vector3(0.14, 0.14, 0.08)), detail)
		_paint(_add_box(t, Vector3( 0.18, 1.32, 0.38), Vector3(0.14, 0.14, 0.08)), detail)
		# wing vane plates on shoulder tops
		_paint(_add_box(t, Vector3(-0.54, 1.93, 0.0),  Vector3(0.20, 0.02, 0.42)), detail)
		_paint(_add_box(t, Vector3( 0.54, 1.93, 0.0),  Vector3(0.20, 0.02, 0.42)), detail)
	if l:
		_paint_all(l, armor)


# Everest: fortress paladin -- steel grey, white cross emblem glow
static func _everest(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	var armor  := _mat(Color(0.34, 0.34, 0.36))
	var detail := _mat(Color(0.20, 0.20, 0.22))
	var glow   := _mat_e(Color(0, 0, 0), Color(0.90, 0.90, 1.0), 2.5)
	if t:
		var body  := t.get_node_or_null("Body") as MeshInstance3D
		var waist := t.get_node_or_null("Waist") as MeshInstance3D
		var head  := t.get_node_or_null("Head") as MeshInstance3D
		var sl    := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr    := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_bm(body,  Vector3(1.10, 0.75, 0.86))
		_bm(waist, Vector3(0.80, 0.24, 0.76))
		_bm(head,  Vector3(0.45, 0.44, 0.46))
		_bm(sl, Vector3(0.38, 0.36, 0.72))
		_bm(sr, Vector3(0.38, 0.36, 0.72))
		if head: head.position.y = 2.00
		if sl: sl.position = Vector3(-0.82, 1.82, 0.0)
		if sr: sr.position = Vector3( 0.82, 1.82, 0.0)
		_paint(body, armor); _paint(waist, armor); _paint(head, armor)
		_paint(sl, armor);   _paint(sr, armor)
		# chest cross emblem
		_paint(_add_box(t, Vector3(0.0, 1.52, -0.44), Vector3(0.44, 0.08, 0.04)), glow)
		_paint(_add_box(t, Vector3(0.0, 1.52, -0.44), Vector3(0.08, 0.34, 0.04)), glow)
		# pauldron connectors
		_paint(_add_box(t, Vector3(-0.685, 1.82, 0.0), Vector3(0.18, 0.32, 0.56)), detail)
		_paint(_add_box(t, Vector3( 0.685, 1.82, 0.0), Vector3(0.18, 0.32, 0.56)), detail)
		# helm visor
		_paint(_add_box(t, Vector3(0.0, 2.02, -0.24),  Vector3(0.32, 0.10, 0.02)), glow)
		# chin guard
		_paint(_add_box(t, Vector3(0.0, 1.82, -0.44),  Vector3(0.26, 0.08, 0.02)), detail)
		# shield: white base + red cross (PhysicalShield local space, shield = 1.6x2.2x0.06)
		var shield := t.get_node_or_null("PhysicalShield") as Node3D
		if shield:
			var sm := shield.get_node_or_null("ShieldMesh") as MeshInstance3D
			_paint(sm, _mat(Color(0.92, 0.92, 0.94)))
			var red := _mat(Color(0.78, 0.06, 0.06))
			_paint(_add_box(shield, Vector3(0.0, 0.0, -0.04), Vector3(1.20, 0.34, 0.02)), red)
			_paint(_add_box(shield, Vector3(0.0, 0.0, -0.04), Vector3(0.34, 1.90, 0.02)), red)
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(1.16, 0.28, 0.66))
		_heavy_legs(l)
		_paint_all(l, armor)


# Vesuvius: volcano dreadnought -- dark rust, orange-red lava stack glow
static func _vesuvius(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	var armor  := _mat(Color(0.18, 0.08, 0.06))
	var detail := _mat(Color(0.24, 0.12, 0.08))
	var glow   := _mat_e(Color(0, 0, 0), Color(1.0, 0.35, 0.05), 5.0)
	if t:
		var body  := t.get_node_or_null("Body") as MeshInstance3D
		var waist := t.get_node_or_null("Waist") as MeshInstance3D
		var head  := t.get_node_or_null("Head") as MeshInstance3D
		var sl    := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr    := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_bm(body,  Vector3(1.18, 0.70, 0.88))
		_bm(waist, Vector3(0.82, 0.24, 0.76))
		_cyl(head, 0.18, 0.30, 0.34, 12)
		_bm(sl, Vector3(0.42, 0.40, 0.74))
		_bm(sr, Vector3(0.42, 0.40, 0.74))
		if sl: sl.position.x = -0.84
		if sr: sr.position.x =  0.84
		_paint(body, armor); _paint(waist, armor); _paint(head, armor)
		_paint(sl, detail);  _paint(sr, detail)
		# exhaust stacks
		_paint(_add_cyl(t, Vector3(-0.26, 1.60, 0.48), 0.06, 0.06, 0.44, 8), detail)
		_paint(_add_cyl(t, Vector3( 0.00, 1.66, 0.48), 0.06, 0.06, 0.56, 8), detail)
		_paint(_add_cyl(t, Vector3( 0.26, 1.60, 0.48), 0.06, 0.06, 0.44, 8), detail)
		# stack base collars
		_paint(_add_box(t, Vector3(-0.26, 1.44, 0.44), Vector3(0.18, 0.20, 0.02)), armor)
		_paint(_add_box(t, Vector3( 0.00, 1.50, 0.44), Vector3(0.18, 0.22, 0.02)), armor)
		_paint(_add_box(t, Vector3( 0.26, 1.44, 0.44), Vector3(0.18, 0.20, 0.02)), armor)
		# lava vent slits on body sides
		_paint(_add_box(t, Vector3( 0.60, 1.32, 0.0), Vector3(0.02, 0.14, 0.30)), glow)
		_paint(_add_box(t, Vector3( 0.60, 1.60, 0.0), Vector3(0.02, 0.14, 0.30)), glow)
		_paint(_add_box(t, Vector3(-0.60, 1.32, 0.0), Vector3(0.02, 0.14, 0.30)), glow)
		_paint(_add_box(t, Vector3(-0.60, 1.60, 0.0), Vector3(0.02, 0.14, 0.30)), glow)
		# weapon sponson face plates
		_paint(_add_box(t, Vector3(-0.84, 1.80, -0.39), Vector3(0.26, 0.20, 0.02)), detail)
		_paint(_add_box(t, Vector3( 0.84, 1.80, -0.39), Vector3(0.26, 0.20, 0.02)), detail)
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(1.14, 0.28, 0.66))
		_heavy_legs(l)
		_paint_all(l, armor)


# Warhog: brutish boar tank -- mud brown, no emissive (pure grit)
static func _warhog(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	var armor  := _mat(Color(0.36, 0.30, 0.20))
	var detail := _mat(Color(0.48, 0.40, 0.26))
	if t:
		var body  := t.get_node_or_null("Body") as MeshInstance3D
		var waist := t.get_node_or_null("Waist") as MeshInstance3D
		var head  := t.get_node_or_null("Head") as MeshInstance3D
		var sl    := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr    := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_bm(body,  Vector3(1.12, 0.64, 0.88))
		_bm(waist, Vector3(0.84, 0.22, 0.76))
		_bm(head,  Vector3(0.44, 0.28, 0.58))
		_bm(sl, Vector3(0.36, 0.32, 0.68))
		_bm(sr, Vector3(0.36, 0.32, 0.68))
		if head:
			head.position.y = 1.82
			head.position.z = -0.08
		if sl: sl.position.x = -0.78
		if sr: sr.position.x =  0.78
		_paint(body, armor); _paint(waist, armor); _paint(head, detail)
		_paint(sl, armor);   _paint(sr, armor)
		# tusks
		_paint(_add_box(t, Vector3(-0.14, 1.68, -0.48), Vector3(0.06, 0.05, 0.22)), detail)
		_paint(_add_box(t, Vector3( 0.14, 1.68, -0.48), Vector3(0.06, 0.05, 0.22)), detail)
		# tusk root brackets
		_paint(_add_box(t, Vector3(-0.14, 1.68, -0.40), Vector3(0.10, 0.08, 0.06)), armor)
		_paint(_add_box(t, Vector3( 0.14, 1.68, -0.40), Vector3(0.10, 0.08, 0.06)), armor)
		# armored nose plate
		_paint(_add_box(t, Vector3(0.0, 1.84, -0.40),  Vector3(0.32, 0.18, 0.06)), detail)
		# shoulder-body connector plates
		_paint(_add_box(t, Vector3(-0.58, 1.72, 0.0),  Vector3(0.08, 0.26, 0.50)), armor)
		_paint(_add_box(t, Vector3( 0.58, 1.72, 0.0),  Vector3(0.08, 0.26, 0.50)), armor)
		# command hatch on body top
		_paint(_add_box(t, Vector3(0.0, 1.75, 0.0),    Vector3(0.22, 0.02, 0.32)), detail)
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(1.12, 0.26, 0.64))
		_heavy_legs(l)
		_paint_all(l, armor)
