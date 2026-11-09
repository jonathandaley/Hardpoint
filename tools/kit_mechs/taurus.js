// T341: Taurus, a medium mech authored in the design kit's box language (tools/new_mech.py).
// Same M API as design/preview/mech-engine.js; kit space (+Z forward). See tools/kit_mechs/README.md.
// HUMAN_FOUND 2026-11-08: "Red and maroon with some black. Crimson emissives. Shaped like a hunched
// minotaur, horns in front. Light weapons instead of arms."
// palette: armor #741A20, detail #3C0C12, emissive #DC143C e2.6   (Medium - hunched minotaur, charges)
build: function (M) {
  const A = M.armor, D = M.detail, MO = M.mount, SK = M.socket, E = M.emis;

  // ---- HUNCHED TORSO: a high back hump, the chest dropping forward ----
  M.box(1.10, 0.78, 0.82, 0, 1.56, -0.08, A);              // main mass
  M.box(0.92, 0.32, 0.70, 0, 2.02, -0.20, A, 0.28);        // hump, tipped forward
  M.box(0.62, 0.20, 0.52, 0, 2.20, -0.30, D, 0.28);        // hump crest
  M.box(0.10, 0.08, 0.56, 0, 2.32, -0.32, E, 0.28);        // spine ridge (charge glow)
  M.glow(0, 2.36, -0.32, 0.4);
  M.box(0.88, 0.58, 0.44, 0, 1.30, 0.36, D);               // chest, low and forward
  M.box(0.22, 0.20, 0.08, 0, 1.34, 0.60, E);               // chest core
  M.glow(0, 1.34, 0.66, 0.4);
  M.box(0.72, 0.24, 0.52, 0, 1.02, 0.04, D);               // torso-to-pelvis bevel
  [-1, 1].forEach(function (s) {
    M.box(0.08, 0.20, 0.24, s * 0.50, 1.84, -0.48, SK);    // back vents (black)
  });

  // ---- HEAD: low, under the shoulder line, bull snout + horns ----
  M.box(0.42, 0.28, 0.36, 0, 1.66, 0.56, A);               // neck, thrust forward
  M.box(0.48, 0.40, 0.46, 0, 1.58, 0.84, A);               // head
  M.box(0.36, 0.22, 0.26, 0, 1.46, 1.12, D);               // snout
  M.box(0.24, 0.06, 0.04, 0, 1.44, 1.26, SK);              // nostrils
  M.box(0.34, 0.06, 0.06, 0, 1.70, 1.08, E);               // eyes
  M.glow(0, 1.70, 1.14, 0.35);
  [-1, 1].forEach(function (s) {
    M.box(0.30, 0.12, 0.14, s * 0.34, 1.76, 0.82, SK, 0, 0, s * 0.35);   // horn root, out and up
    M.box(0.11, 0.11, 0.40, s * 0.52, 1.90, 1.00, SK, -0.35);            // horn, sweeping forward
    M.box(0.08, 0.08, 0.10, s * 0.52, 2.00, 1.22, E);                    // horn tip glint
  });

  // ---- SHOULDERS + ARMS THAT END IN LIGHT GUNS ----
  [-1, 1].forEach(function (s) {
    M.box(0.42, 0.48, 0.60, s * 0.72, 1.70, 0.00, A);      // pauldron
    M.box(0.44, 0.10, 0.62, s * 0.72, 1.97, 0.00, D);      // pauldron rim
    M.box(0.24, 0.40, 0.26, s * 0.78, 1.38, 0.14, D);      // upper arm, hanging forward
    M.box(0.06, 0.24, 0.20, s * 0.91, 1.40, 0.14, E);      // arm seam
    M.box(0.22, 0.18, 0.26, s * 0.78, 1.18, 0.36, MO);     // light mount: the gun is the forearm
  });

  // ---- PELVIS ----
  M.box(0.70, 0.30, 0.50, 0, 0.94, 0, D);

  // ---- LEGS: thick digitigrade, black hooves ----
  [-1, 1].forEach(function (s) {
    const hx = s * 0.36;
    const hip  = [hx, 0.95,  0.00];
    const knee = [hx, 0.62,  0.18];
    const hock = [hx, 0.34, -0.16];
    const toe  = [hx, 0.12,  0.04];
    M.box(0.30, 0.28, 0.32, hip[0], hip[1], hip[2], A);
    M.between(hip, knee, 0.30, 0.32, A);                   // thigh
    M.between(knee, hock, 0.25, 0.27, D);                  // shin
    M.between(hock, toe, 0.21, 0.22, D);                   // pastern
    M.box(0.32, 0.15, 0.38, hx, 0.075, 0.06, SK);          // hoof
    M.box(0.20, 0.16, 0.10, hx, 0.62, 0.30, SK);           // knee cap (black)
  });
}
