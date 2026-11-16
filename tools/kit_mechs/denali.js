// T430: Denali, a heavy mech authored in the design kit's box language (tools/new_mech.py).
// Same M API as design/preview/mech-engine.js; kit space (+Z forward). See tools/kit_mechs/README.md.
// The user left the design to Claude (2026-11-16). Roster gap: the only heavies (Everest, Vesuvius)
// have no ability. Denali is the siege heavy: a stepped mountain of a torso on a wide, low stance,
// two shoulder cannons, and ANCHOR (it plants its feet; the knee spikes and green ridge lights sell it).
// palette: armor #A8946A, detail #4E3D2A, emissive #6CFF4A e2.8   (Heavy - stepped mountain, plants its feet)
build: function (M) {
  const A = M.armor, D = M.detail, MO = M.mount, SK = M.socket, E = M.emis;

  // ---- TORSO: three tiers stepping in, a mountain from the front ----
  M.box(1.36, 0.66, 0.90, 0, 1.40, 0.00, A);              // base tier, widest
  M.box(1.04, 0.38, 0.78, 0, 1.92, -0.04, D);             // middle tier (dark band: the steps read)
  M.box(0.64, 0.26, 0.60, 0, 2.23, -0.08, A);             // summit tier
  M.box(1.10, 0.05, 0.04, 0, 1.74, 0.46, E);              // ridge light, base tier lip
  M.box(0.80, 0.05, 0.04, 0, 2.11, 0.36, E);              // ridge light, middle tier lip
  M.glow(0, 1.90, 0.50, 0.5);
  M.box(0.74, 0.38, 0.10, 0, 1.40, 0.48, D);              // chest plate
  M.box(0.30, 0.12, 0.06, 0, 1.44, 0.54, E);              // core slit
  M.box(0.96, 0.22, 0.62, 0, 0.98, 0.00, D);              // torso-to-pelvis bevel
  [-1, 1].forEach(function (s) {
    M.box(0.10, 0.26, 0.30, s * 0.56, 2.00, -0.40, SK);   // back exhausts
  });

  // ---- HEAD: sunk into the summit, only the visor shows ----
  M.box(0.42, 0.24, 0.32, 0, 2.08, 0.34, A);              // head
  M.box(0.32, 0.06, 0.04, 0, 2.10, 0.51, E);              // visor
  M.glow(0, 2.10, 0.56, 0.3);

  // ---- SHOULDERS + HEAVY CANNON MOUNTS ----
  [-1, 1].forEach(function (s) {
    M.box(0.50, 0.66, 0.84, s * 0.94, 1.66, 0.00, A);     // shoulder block
    M.box(0.54, 0.10, 0.88, s * 0.94, 2.03, 0.00, D);     // shoulder rim
    M.box(0.06, 0.34, 0.12, s * 1.20, 1.66, 0.22, E);     // side running light
    M.box(0.42, 0.42, 0.46, s * 1.14, 1.92, 0.56, MO);    // heavy mount
    M.box(0.30, 0.30, 0.14, s * 1.14, 1.92, 0.84, MO);    // mount face
  });

  // ---- PELVIS ----
  M.box(0.90, 0.32, 0.58, 0, 0.94, 0, D);

  // ---- LEGS: short, thick, wide stance; knee spikes that dig in on ANCHOR ----
  [-1, 1].forEach(function (s) {
    const hx = s * 0.52;
    const hip  = [hx, 0.95,  0.00];
    const knee = [hx, 0.60,  0.16];
    const hock = [hx, 0.32, -0.10];
    const toe  = [hx, 0.12,  0.06];
    M.box(0.38, 0.36, 0.40, hip[0], hip[1], hip[2], A);
    M.between(hip, knee, 0.38, 0.40, A);                  // thigh
    M.between(knee, hock, 0.32, 0.34, D);                 // shin
    M.between(hock, toe, 0.28, 0.28, D);                  // pastern
    M.box(0.48, 0.16, 0.56, hx, 0.08, 0.08, SK);          // broad foot
    M.box(0.22, 0.12, 0.08, hx, 0.62, 0.36, E);           // knee lamp
    M.box(0.08, 0.34, 0.08, hx + s * 0.22, 0.30, -0.20, SK, 0, 0, s * 0.4);  // anchor spike
  });
}
