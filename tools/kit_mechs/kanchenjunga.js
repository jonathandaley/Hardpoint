// T456 Etna -> T480 / T481 Kanchenjunga (user 2026-11-18: "Redesign Etna to look less like Denali: put both
// guns on the left side, make its body asymmetrical, and make its legs a little oversized" / "rename Etna to
// Kanchenjunga" / "And recolor to match"). A heavy in the design kit's box language (tools/new_mech.py).
// Five Treasures of Snow: snow-white stepped slabs, slate rock showing through, gold lamps; a tall
// peak climbs its right shoulder, both heavy guns ride stacked on the left; thick legs and broad feet
// for the STOMP. Kit space: +Z forward, the mech's left is -X.
// palette: armor #DCE3EA, detail #4A5A74, emissive #FFC447 e2.5   (Heavy - a snow peak: guns left, STOMP)
build: function (M) {
  const A = M.armor, D = M.detail, MO = M.mount, SK = M.socket, E = M.emis;

  // ---- BODY: stepped snow slabs, offset right (the mountain leans) ----
  M.box(1.40, 0.70, 1.10, 0.04, 1.36, 0.00, A);           // base slab
  M.box(1.12, 0.40, 0.92, 0.12, 1.90, -0.04, A);          // middle slab
  M.box(0.80, 0.26, 0.70, 0.20, 2.22, -0.10, A);          // upper slab
  M.box(1.44, 0.08, 1.14, 0.04, 1.73, 0.00, D);           // slate band, base
  M.box(1.16, 0.06, 0.96, 0.12, 2.11, -0.04, D);          // slate band, middle
  M.box(0.70, 0.36, 0.10, -0.06, 1.30, 0.58, D);          // chest plate
  M.box(0.30, 0.06, 0.04, -0.06, 1.42, 0.64, E);          // chest lamp
  M.box(1.00, 0.24, 0.80, 0.00, 0.96, 0.00, D);           // body-to-pelvis bevel

  // ---- THE PEAK: climbing the right shoulder ----
  M.box(0.70, 0.60, 0.80, 0.92, 2.00, -0.06, A);
  M.box(0.52, 0.40, 0.60, 0.90, 2.48, -0.10, A);
  M.box(0.34, 0.34, 0.40, 0.86, 2.84, -0.14, A);
  M.box(0.18, 0.24, 0.22, 0.84, 3.12, -0.16, A);          // summit
  M.box(0.74, 0.08, 0.84, 0.92, 1.72, -0.06, D);          // slate at its foot
  M.box(0.36, 0.06, 0.42, 0.88, 2.66, -0.12, D);          // slate ledge
  M.box(0.08, 0.08, 0.04, 0.84, 2.92, 0.08, E);           // summit lamp
  M.box(0.06, 0.24, 0.04, 1.28, 1.96, 0.22, E);           // flank lamp

  // ---- HEAD: a low visor off-centre ----
  M.box(0.50, 0.20, 0.30, -0.10, 1.98, 0.42, A);
  M.box(0.38, 0.05, 0.04, -0.10, 2.00, 0.58, E);          // visor

  // ---- LEFT SHOULDER: both heavy mounts, stacked ----
  M.box(0.56, 0.96, 0.92, -0.98, 1.64, 0.00, D);          // gun shoulder block
  M.box(0.60, 0.08, 0.96, -0.98, 2.14, 0.00, A);          // snow cap
  M.box(0.42, 0.40, 0.46, -1.16, 1.98, 0.58, MO);         // upper heavy mount
  M.box(0.30, 0.28, 0.14, -1.16, 1.98, 0.86, MO);
  M.box(0.42, 0.40, 0.46, -1.16, 1.34, 0.58, MO);         // lower heavy mount
  M.box(0.30, 0.28, 0.14, -1.16, 1.34, 0.86, MO);
  M.box(0.06, 0.30, 0.10, -1.28, 1.66, 0.24, E);          // side lamp

  // ---- PELVIS ----
  M.box(1.04, 0.36, 0.66, 0, 0.92, 0, D);

  // ---- LEGS: oversized columns, broad feet for the stomp ----
  [-1, 1].forEach(function (s) {
    const hx = s * 0.60;
    const hip  = [hx, 0.92,  0.00];
    const knee = [hx, 0.58,  0.14];
    const hock = [hx, 0.30, -0.08];
    const toe  = [hx, 0.12,  0.06];
    M.box(0.54, 0.46, 0.56, hip[0], hip[1], hip[2], A);
    M.between(hip, knee, 0.54, 0.56, A);                  // thigh
    M.between(knee, hock, 0.46, 0.48, D);                 // shin
    M.between(hock, toe, 0.38, 0.38, D);                  // pastern
    M.box(0.70, 0.18, 0.80, hx, 0.09, 0.10, SK);          // broad foot
    M.box(0.40, 0.04, 0.04, hx, 0.19, 0.50, E);           // toe lamp
  });
}
