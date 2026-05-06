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


# Slip: aerodynamic sprinter -- narrow side profile, blade feet, dorsal fin, visor
static func _slip(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	if t:
		_bm(t.get_node_or_null("Body") as MeshInstance3D,          Vector3(0.72, 0.55, 0.85))
		_bm(t.get_node_or_null("Waist") as MeshInstance3D,         Vector3(0.52, 0.14, 0.60))
		_bm(t.get_node_or_null("Head") as MeshInstance3D,          Vector3(0.36, 0.20, 0.44))
		var sl := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_bm(sl, Vector3(0.15, 0.16, 0.48))
		_bm(sr, Vector3(0.15, 0.16, 0.48))
		if sl: sl.position.x = -0.52
		if sr: sr.position.x =  0.52
		# visor slit flush with head front face (head front = z -0.22)
		_add_box(t, Vector3(0.0, 1.92, -0.21),  Vector3(0.28, 0.05, 0.02))
		# neck connecting body top (1.695) to head bottom (1.82)
		_add_box(t, Vector3(0.0, 1.76, 0.0),    Vector3(0.22, 0.14, 0.28))
		# shoulder brackets bridging gap between body edge and shoulder inner edge
		_add_box(t, Vector3(-0.44, 1.72, 0.0),  Vector3(0.16, 0.10, 0.36))
		_add_box(t, Vector3( 0.44, 1.72, 0.0),  Vector3(0.16, 0.10, 0.36))
		# front body armor panels flush with body front face (z -0.425)
		_add_box(t, Vector3(-0.20, 1.36, -0.43), Vector3(0.16, 0.18, 0.02))
		_add_box(t, Vector3( 0.20, 1.36, -0.43), Vector3(0.16, 0.18, 0.02))
		# dorsal fin on upper back (body back face = z 0.425)
		_add_box(t, Vector3(0.0, 1.70, 0.43),   Vector3(0.05, 0.22, 0.02))
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(0.78, 0.18, 0.44))
		_leg_segs(l,
			Vector3(0.17, 0.62, 0.16),
			Vector3(0.15, 0.62, 0.14),
			Vector3(0.13, 0.16, 0.34))


# Cesh: hunched stealth predator -- wide low body, sensor pod on shoulder
static func _cesh(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	if t:
		_bm(t.get_node_or_null("Body") as MeshInstance3D,          Vector3(1.04, 0.50, 0.76))
		_bm(t.get_node_or_null("Waist") as MeshInstance3D,         Vector3(0.62, 0.12, 0.60))
		_bm(t.get_node_or_null("Head") as MeshInstance3D,          Vector3(0.38, 0.18, 0.44))
		_bm(t.get_node_or_null("ShoulderLeft") as MeshInstance3D,  Vector3(0.24, 0.20, 0.58))
		_bm(t.get_node_or_null("ShoulderRight") as MeshInstance3D, Vector3(0.24, 0.20, 0.58))
		# sensor pod sitting on top of left shoulder (shoulder top = 1.72+0.10 = 1.82)
		_add_cyl(t, Vector3(-0.68, 1.91, 0.0), 0.08, 0.08, 0.18, 8)
		# wide hunched neck connecting body top (1.67) to head bottom (1.83)
		_add_box(t, Vector3(0.0, 1.75, 0.0),   Vector3(0.30, 0.16, 0.42))
		# sensor backpack plate flush with body back (z 0.38)
		_add_box(t, Vector3(0.0, 1.62, 0.40),  Vector3(0.40, 0.28, 0.04))
		# camo vent strips on body sides (body right face = x 0.52)
		_add_box(t, Vector3( 0.53, 1.42, 0.0), Vector3(0.02, 0.22, 0.32))
		_add_box(t, Vector3(-0.53, 1.42, 0.0), Vector3(0.02, 0.22, 0.32))
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(0.96, 0.20, 0.54))
		_leg_segs(l,
			Vector3(0.18, 0.56, 0.17),
			Vector3(0.16, 0.50, 0.15),
			Vector3(0.14, 0.50, 0.14))


# Seeker: dense sensor-ball head, asymmetric heavy weapon shoulder
static func _seeker(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	if t:
		_bm(t.get_node_or_null("Body") as MeshInstance3D,  Vector3(0.90, 0.60, 0.72))
		_bm(t.get_node_or_null("Waist") as MeshInstance3D, Vector3(0.68, 0.18, 0.62))
		_sph(t.get_node_or_null("Head") as MeshInstance3D, 0.22)
		_bm(t.get_node_or_null("ShoulderLeft") as MeshInstance3D,  Vector3(0.18, 0.20, 0.44))
		var sr := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_bm(sr, Vector3(0.32, 0.36, 0.62))
		if sr: sr.position.x = 0.72
		# smoothing collar: short cylinder where body top meets sphere base
		# body top=1.72, sphere center=1.92 radius=0.22, sphere bottom=1.70 (overlaps body)
		_add_cyl(t, Vector3(0.0, 1.78, 0.0), 0.18, 0.22, 0.10)
		# targeting reticle bars on sensor head front (sphere front = z -0.22)
		_add_box(t, Vector3(0.0, 1.92, -0.23), Vector3(0.20, 0.02, 0.02))  # horizontal
		_add_box(t, Vector3(0.0, 1.92, -0.23), Vector3(0.02, 0.20, 0.02))  # vertical
		# sensor panel on heavy shoulder front (shoulder front = z -0.31)
		_add_box(t, Vector3(0.84, 1.78, -0.33), Vector3(0.14, 0.12, 0.02))
		# body front sensor strip
		_add_box(t, Vector3(0.0, 1.55, -0.37), Vector3(0.30, 0.06, 0.02))
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(0.84, 0.20, 0.50))
		_leg_segs(l,
			Vector3(0.22, 0.50, 0.20),
			Vector3(0.20, 0.50, 0.18),
			Vector3(0.18, 0.50, 0.16))


# Lynx: lithe cat silhouette -- tapered cylinder torso, long legs, antenna spike
static func _lynx(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	if t:
		_cyl(t.get_node_or_null("Body") as MeshInstance3D, 0.30, 0.38, 0.58)
		_bm(t.get_node_or_null("Waist") as MeshInstance3D, Vector3(0.56, 0.14, 0.56))
		_bm(t.get_node_or_null("Head") as MeshInstance3D,  Vector3(0.32, 0.26, 0.46))
		var sl := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_bm(sl, Vector3(0.16, 0.18, 0.50))
		_bm(sr, Vector3(0.16, 0.18, 0.50))
		if sl: sl.position.x = -0.52
		if sr: sr.position.x =  0.52
		# antenna spike (confirmed embedded: head top=2.05, antenna bottom=2.00)
		_add_box(t, Vector3(0.0, 2.10, 0.0), Vector3(0.04, 0.20, 0.04))
		# neck cylinder bridging body top (1.71) to head bottom (1.79)
		_add_cyl(t, Vector3(0.0, 1.75, 0.0), 0.16, 0.18, 0.08)
		# cat ear spikes on head top (head top=2.05; ear bottom=2.01 = 0.04m embedded)
		_add_box(t, Vector3(-0.11, 2.08, 0.0), Vector3(0.04, 0.14, 0.04))
		_add_box(t, Vector3( 0.11, 2.08, 0.0), Vector3(0.04, 0.14, 0.04))
		# shoulder-body connector brackets (body cyl edge ~0.36, shoulder inner ~0.44)
		_add_box(t, Vector3(-0.44, 1.72, 0.0), Vector3(0.16, 0.10, 0.36))
		_add_box(t, Vector3( 0.44, 1.72, 0.0), Vector3(0.16, 0.10, 0.36))
		# lower back tail stub (cyl back ~z 0.38)
		_add_box(t, Vector3(0.0, 1.26, 0.40), Vector3(0.06, 0.08, 0.04))
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(0.80, 0.18, 0.46))
		_leg_segs(l,
			Vector3(0.17, 0.64, 0.16),
			Vector3(0.15, 0.64, 0.14),
			Vector3(0.13, 0.20, 0.28))


# Hornet: F-18 jet -- wide flat fuselage, tall cockpit canopy, swept pylons, engine nacelles
static func _hornet(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	if t:
		_bm(t.get_node_or_null("Body") as MeshInstance3D,  Vector3(1.12, 0.48, 0.82))
		_bm(t.get_node_or_null("Waist") as MeshInstance3D, Vector3(0.58, 0.16, 0.68))
		_bm(t.get_node_or_null("Head") as MeshInstance3D,  Vector3(0.38, 0.40, 0.50))
		var sl := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_bm(sl, Vector3(0.38, 0.16, 0.72))
		_bm(sr, Vector3(0.38, 0.16, 0.72))
		if sl: sl.position.x = -0.80
		if sr: sr.position.x =  0.80
		# twin engine nacelles lower back
		_add_cyl(t, Vector3(-0.22, 1.20, 0.46), 0.10, 0.12, 0.40, 10)
		_add_cyl(t, Vector3( 0.22, 1.20, 0.46), 0.10, 0.12, 0.40, 10)
		# wide flat neck bridging body top (1.66) to head bottom (1.72)
		_add_box(t, Vector3(0.0, 1.69, 0.0),    Vector3(0.32, 0.06, 0.44))
		# cockpit tinted window strip flush with head front (z -0.25)
		_add_box(t, Vector3(0.0, 1.94, -0.26),  Vector3(0.32, 0.14, 0.02))
		# air intake ducts on body front lower (body front = z -0.41)
		_add_box(t, Vector3(-0.22, 1.24, -0.42), Vector3(0.14, 0.10, 0.02))
		_add_box(t, Vector3( 0.22, 1.24, -0.42), Vector3(0.14, 0.10, 0.02))
		# nacelle mounting pylons spanning body back (z 0.41) to nacelle body
		_add_box(t, Vector3(-0.22, 1.20, 0.34),  Vector3(0.08, 0.10, 0.12))
		_add_box(t, Vector3( 0.22, 1.20, 0.34),  Vector3(0.08, 0.10, 0.12))


# Hippogriff: B-29 bomber -- round fuselage, nose dome, wide wing sponsons
static func _hippogriff(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	if t:
		_cyl(t.get_node_or_null("Body") as MeshInstance3D, 0.46, 0.52, 0.64)
		_bm(t.get_node_or_null("Waist") as MeshInstance3D, Vector3(0.76, 0.22, 0.68))
		_sph(t.get_node_or_null("Head") as MeshInstance3D, 0.24)
		var sl := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_bm(sl, Vector3(0.42, 0.15, 0.74))
		_bm(sr, Vector3(0.42, 0.15, 0.74))
		if sl: sl.position.x = -0.80
		if sr: sr.position.x =  0.80
		# nose turret on head front (sphere front ~z -0.24)
		_add_box(t, Vector3(0.0, 1.92, -0.28), Vector3(0.09, 0.09, 0.08))
		# bomb bay door plates flush with body underside (cyl bottom ~y 1.10)
		_add_box(t, Vector3(-0.16, 1.10, 0.0), Vector3(0.20, 0.02, 0.52))
		_add_box(t, Vector3( 0.16, 1.10, 0.0), Vector3(0.20, 0.02, 0.52))
		# wing struts connecting body to sponson inner edges (body edge ~0.48, shoulder inner ~0.59)
		_add_box(t, Vector3(-0.54, 1.70, 0.0), Vector3(0.22, 0.08, 0.56))
		_add_box(t, Vector3( 0.54, 1.70, 0.0), Vector3(0.22, 0.08, 0.56))
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(1.08, 0.24, 0.60))
		_leg_segs(l,
			Vector3(0.26, 0.52, 0.24),
			Vector3(0.24, 0.52, 0.22),
			Vector3(0.22, 0.52, 0.20))


# Kestrel: energy shield tech -- hexagonal prism body, octagonal sensor head, shield emitter cross
static func _kestrel(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	if t:
		_cyl(t.get_node_or_null("Body") as MeshInstance3D,  0.40, 0.46, 0.62, 6)
		_bm(t.get_node_or_null("Waist") as MeshInstance3D,  Vector3(0.65, 0.18, 0.58))
		_cyl(t.get_node_or_null("Head") as MeshInstance3D,  0.17, 0.17, 0.28, 8)
		_cyl(t.get_node_or_null("ShoulderLeft") as MeshInstance3D,  0.18, 0.20, 0.22, 6)
		_cyl(t.get_node_or_null("ShoulderRight") as MeshInstance3D, 0.18, 0.20, 0.22, 6)
		# shield emitter cross at waist
		_add_box(t, Vector3(0.0, 1.02, 0.0), Vector3(1.10, 0.06, 0.04))
		_add_box(t, Vector3(0.0, 1.02, 0.0), Vector3(0.04, 0.06, 1.10))
		# neck cylinder bridging body top (1.73) to head bottom (1.78)
		_add_cyl(t, Vector3(0.0, 1.755, 0.0), 0.15, 0.17, 0.05, 8)
		# hex emitter rings sitting on shoulder cap tops (shoulder top = 1.72+0.11 = 1.83)
		_add_cyl(t, Vector3(-0.68, 1.84, 0.0), 0.16, 0.16, 0.02, 6)
		_add_cyl(t, Vector3( 0.68, 1.84, 0.0), 0.16, 0.16, 0.02, 6)
		# energy conduit strip on body front face (~z -0.42)
		_add_box(t, Vector3(0.0, 1.42, -0.42), Vector3(0.04, 0.52, 0.02))


# Pegasus: angelic mobility mech -- slim body, raised wing shoulders, jump jet pack, head crest
static func _pegasus(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	if t:
		_bm(t.get_node_or_null("Body") as MeshInstance3D,  Vector3(0.86, 0.60, 0.72))
		_bm(t.get_node_or_null("Waist") as MeshInstance3D, Vector3(0.58, 0.16, 0.60))
		_bm(t.get_node_or_null("Head") as MeshInstance3D,  Vector3(0.36, 0.34, 0.42))
		var sl := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_bm(sl, Vector3(0.22, 0.20, 0.58))
		_bm(sr, Vector3(0.22, 0.20, 0.58))
		if sl: sl.position.y = 1.82
		if sr: sr.position.y = 1.82
		# jump jets on lower back
		_add_cyl(t, Vector3(-0.18, 1.32, 0.44), 0.10, 0.12, 0.48, 10)
		_add_cyl(t, Vector3( 0.18, 1.32, 0.44), 0.10, 0.12, 0.48, 10)
		# head crest (base embedded in head top: head top=2.09, crest bottom=1.99)
		_add_box(t, Vector3(0.0, 2.08, 0.0), Vector3(0.06, 0.18, 0.04))
		# thin neck connecting body top (1.72) to head bottom (1.75)
		_add_box(t, Vector3(0.0, 1.735, 0.0), Vector3(0.26, 0.03, 0.34))
		# jet mounting brackets flush with body back (z 0.36), bridging to jet fronts
		_add_box(t, Vector3(-0.18, 1.32, 0.38), Vector3(0.14, 0.14, 0.08))
		_add_box(t, Vector3( 0.18, 1.32, 0.38), Vector3(0.14, 0.14, 0.08))
		# wing vane plates sitting on raised shoulder tops (shoulder top = 1.82+0.10 = 1.92)
		_add_box(t, Vector3(-0.68, 1.93, 0.0), Vector3(0.20, 0.02, 0.42))
		_add_box(t, Vector3( 0.68, 1.93, 0.0), Vector3(0.20, 0.02, 0.42))


# Everest: fortress paladin -- massive box, huge pauldrons, pillar legs, chest cross emblem
static func _everest(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	if t:
		_bm(t.get_node_or_null("Body") as MeshInstance3D,  Vector3(1.10, 0.75, 0.86))
		_bm(t.get_node_or_null("Waist") as MeshInstance3D, Vector3(0.80, 0.24, 0.76))
		var head := t.get_node_or_null("Head") as MeshInstance3D
		_bm(head, Vector3(0.45, 0.44, 0.46))
		if head: head.position.y = 2.00
		var sl := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_bm(sl, Vector3(0.38, 0.36, 0.72))
		_bm(sr, Vector3(0.38, 0.36, 0.72))
		if sl: sl.position = Vector3(-0.82, 1.82, 0.0)
		if sr: sr.position = Vector3( 0.82, 1.82, 0.0)
		# chest cross emblem on front face (body front = z -0.43)
		_add_box(t, Vector3(0.0, 1.52, -0.44), Vector3(0.44, 0.08, 0.04))
		_add_box(t, Vector3(0.0, 1.52, -0.44), Vector3(0.08, 0.34, 0.04))
		# pauldron connectors bridging body edge (x 0.55) to shoulder inner (x 0.63)
		# body and shoulders overlap vertically, so these are lateral fill pieces
		_add_box(t, Vector3(-0.685, 1.82, 0.0), Vector3(0.18, 0.32, 0.56))
		_add_box(t, Vector3( 0.685, 1.82, 0.0), Vector3(0.18, 0.32, 0.56))
		# helm visor slit flush with head front (head front = z -0.23, head at y=2.00)
		_add_box(t, Vector3(0.0, 2.02, -0.24),  Vector3(0.32, 0.10, 0.02))
		# chin guard plate below visor
		_add_box(t, Vector3(0.0, 1.82, -0.44),  Vector3(0.26, 0.08, 0.02))
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(1.16, 0.28, 0.66))
		_heavy_legs(l)


# Vesuvius: volcano dreadnought -- broad weapon platform, tapered volcanic head, exhaust stacks
static func _vesuvius(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	if t:
		_bm(t.get_node_or_null("Body") as MeshInstance3D,  Vector3(1.18, 0.70, 0.88))
		_bm(t.get_node_or_null("Waist") as MeshInstance3D, Vector3(0.82, 0.24, 0.76))
		_cyl(t.get_node_or_null("Head") as MeshInstance3D, 0.18, 0.30, 0.34, 12)
		var sl := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_bm(sl, Vector3(0.42, 0.40, 0.74))
		_bm(sr, Vector3(0.42, 0.40, 0.74))
		if sl: sl.position.x = -0.84
		if sr: sr.position.x =  0.84
		# exhaust stacks on back (body back = z 0.44)
		_add_cyl(t, Vector3(-0.26, 1.60, 0.48), 0.06, 0.06, 0.44, 8)
		_add_cyl(t, Vector3( 0.00, 1.66, 0.48), 0.06, 0.06, 0.56, 8)
		_add_cyl(t, Vector3( 0.26, 1.60, 0.48), 0.06, 0.06, 0.44, 8)
		# stack base collars flush with body back, grounding each chimney
		_add_box(t, Vector3(-0.26, 1.44, 0.44), Vector3(0.18, 0.20, 0.02))
		_add_box(t, Vector3( 0.00, 1.50, 0.44), Vector3(0.18, 0.22, 0.02))
		_add_box(t, Vector3( 0.26, 1.44, 0.44), Vector3(0.18, 0.20, 0.02))
		# lava vent slits on body sides (body right face = x 0.59)
		_add_box(t, Vector3( 0.60, 1.32, 0.0), Vector3(0.02, 0.14, 0.30))
		_add_box(t, Vector3( 0.60, 1.60, 0.0), Vector3(0.02, 0.14, 0.30))
		_add_box(t, Vector3(-0.60, 1.32, 0.0), Vector3(0.02, 0.14, 0.30))
		_add_box(t, Vector3(-0.60, 1.60, 0.0), Vector3(0.02, 0.14, 0.30))
		# weapon sponson face plates on shoulder fronts (shoulder front = z -0.37)
		_add_box(t, Vector3(-0.84, 1.80, -0.39), Vector3(0.26, 0.20, 0.02))
		_add_box(t, Vector3( 0.84, 1.80, -0.39), Vector3(0.26, 0.20, 0.02))
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(1.14, 0.28, 0.66))
		_heavy_legs(l)


# Warhog: brutish boar tank -- squat wide body, forward snout head, tusks, heavy shoulders
static func _warhog(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	if t:
		_bm(t.get_node_or_null("Body") as MeshInstance3D,  Vector3(1.12, 0.64, 0.88))
		_bm(t.get_node_or_null("Waist") as MeshInstance3D, Vector3(0.84, 0.22, 0.76))
		var head := t.get_node_or_null("Head") as MeshInstance3D
		_bm(head, Vector3(0.44, 0.28, 0.58))
		if head:
			head.position.y = 1.82
			head.position.z = -0.08
		var sl := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_bm(sl, Vector3(0.36, 0.32, 0.68))
		_bm(sr, Vector3(0.36, 0.32, 0.68))
		if sl: sl.position.x = -0.78
		if sr: sr.position.x =  0.78
		# tusks (back face at z -0.37 = head front face; barely touching)
		_add_box(t, Vector3(-0.14, 1.68, -0.48), Vector3(0.06, 0.05, 0.22))
		_add_box(t, Vector3( 0.14, 1.68, -0.48), Vector3(0.06, 0.05, 0.22))
		# tusk root brackets connecting tusk backs to head front face
		_add_box(t, Vector3(-0.14, 1.68, -0.40), Vector3(0.10, 0.08, 0.06))
		_add_box(t, Vector3( 0.14, 1.68, -0.40), Vector3(0.10, 0.08, 0.06))
		# armored nose plate flush with snout front (head front = z -0.08-0.29 = -0.37)
		_add_box(t, Vector3(0.0, 1.84, -0.40), Vector3(0.32, 0.18, 0.06))
		# shoulder-body connector plates (body edge x 0.56, shoulder inner ~0.60)
		_add_box(t, Vector3(-0.58, 1.72, 0.0), Vector3(0.08, 0.26, 0.50))
		_add_box(t, Vector3( 0.58, 1.72, 0.0), Vector3(0.08, 0.26, 0.50))
		# command hatch on body top (body top = 1.42+0.32 = 1.74)
		_add_box(t, Vector3(0.0, 1.75, 0.0), Vector3(0.22, 0.02, 0.32))
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(1.12, 0.26, 0.64))
		_heavy_legs(l)
