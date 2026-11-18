// T456: Etna, a heavy mech authored in the design kit's box language (tools/new_mech.py).
// Same M API as design/preview/mech-engine.js; kit space (+Z forward). See tools/kit_mechs/README.md.
// User 2026-11-17: "add as many mechs as you think are good". Roster gap: heavies have a shield
// (Everest), firepower (Vesuvius) and ANCHOR (Denali); nothing wins a close brawl. Etna is a walking
// volcano: STOMP sends a shockwave through everything near it. Black rock plates stepping up to a
// crater on its back, orange vents glowing through the cracks, massive legs.
// palette: armor #2E2A27, detail #5A3A2A, emissive #FF7A1A e3.0   (Heavy - a volcano: crater vents, STOMP)
build: function (M) {
  const A = M.armor, D = M.detail, MO = M.mount, SK = M.socket, E = M.emis;

  // ---- BODY: a squat cone of rock slabs ----
  M.box(1.40, 0.70, 1.10, 0, 1.36, 0.00, A);              // base slab
  M.box(1.10, 0.40, 0.90, 0, 1.90, -0.06, A);             // middle slab
  M.box(0.80, 0.30, 0.70, 0, 2.24, -0.12, D);             // crater rim
  M.box(0.48, 0.08, 0.40, 0, 2.40, -0.12, E);             // crater glow
  M.glow(0, 2.42, -0.12, 0.6);
  M.box(1.20, 0.05, 0.04, 0, 1.70, 0.56, E);              // crack, base slab lip
  M.box(0.06, 0.40, 0.04, 0.30, 1.40, 0.56, E);           // crack, down the front
  M.box(0.70, 0.36, 0.10, 0, 1.30, 0.58, D);              // chest plate
  M.box(1.00, 0.24, 0.80, 0, 0.96, 0.00, D);              // body-to-pelvis bevel
  [-1, 1].forEach(function (s) {
    M.box(0.16, 0.30, 0.16, s * 0.42, 2.20, -0.48, SK);   // vent stacks
    M.box(0.12, 0.06, 0.12, s * 0.42, 2.38, -0.48, E);    // vent glow
  });

  // ---- HEAD: a low visor in the front slab ----
  M.box(0.50, 0.20, 0.30, 0, 1.98, 0.42, A);
  M.box(0.38, 0.05, 0.04, 0, 2.00, 0.58, E);              // visor
  M.glow(0, 2.00, 0.62, 0.3);

  // ---- SHOULDERS + HEAVY MOUNTS ----
  [-1, 1].forEach(function (s) {
    M.box(0.52, 0.70, 0.90, s * 0.98, 1.56, 0.00, A);     // shoulder boulder
    M.box(0.56, 0.10, 0.94, s * 0.98, 1.94, 0.00, D);     // shoulder rim
    M.box(0.06, 0.30, 0.10, s * 1.25, 1.50, 0.24, E);     // side crack
    M.box(0.42, 0.42, 0.46, s * 1.16, 1.80, 0.58, MO);    // heavy mount
    M.box(0.30, 0.30, 0.14, s * 1.16, 1.80, 0.86, MO);    // mount face
  });

  // ---- PELVIS ----
  M.box(0.96, 0.34, 0.62, 0, 0.92, 0, D);

  // ---- LEGS: columns of rock, wide feet for the stomp ----
  [-1, 1].forEach(function (s) {
    const hx = s * 0.56;
    const hip  = [hx, 0.92,  0.00];
    const knee = [hx, 0.58,  0.14];
    const hock = [hx, 0.30, -0.08];
    const toe  = [hx, 0.12,  0.06];
    M.box(0.42, 0.38, 0.44, hip[0], hip[1], hip[2], A);
    M.between(hip, knee, 0.42, 0.44, A);                  // thigh
    M.between(knee, hock, 0.36, 0.38, D);                 // shin
    M.between(hock, toe, 0.30, 0.30, D);                  // pastern
    M.box(0.56, 0.16, 0.64, hx, 0.08, 0.08, SK);          // broad foot
    M.box(0.30, 0.04, 0.04, hx, 0.17, 0.40, E);           // foot crack glow
  });
}
