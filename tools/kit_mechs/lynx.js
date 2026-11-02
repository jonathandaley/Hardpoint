// T181: Lynx, authored in the design kit's box language (the kit has no Lynx render).
// Same M API as design/preview/mech-engine.js; kit space (+Z forward). tools/kit_port.py
// reads this next to the kit's brand-mech-render-*.html.
// palette: armor #2F5C3A, detail #1E3D27, emissive #FFA60D e2.5   (Light · lithe cat, amber tells)
build: function (M) {
  const A = M.armor, D = M.detail, MO = M.mount, SK = M.socket, E = M.emis;

  // ---- TORSO (long, low, leaning into the stride) ----
  M.box(0.86, 0.60, 1.00, 0, 1.50, 0.00, A);               // main mass
  M.box(0.62, 0.40, 0.32, 0, 1.62, 0.58, A);               // chest / neck
  M.box(0.22, 0.10, 0.92, 0, 1.84, -0.04, D);              // spine ridge
  M.box(0.66, 0.24, 0.64, 0, 1.12, 0.00, D);               // torso-to-pelvis bevel

  // ---- HEAD (cat: wedge snout, ears, amber visor) ----
  M.box(0.42, 0.30, 0.46, 0, 1.86, 0.74, A);               // head
  M.box(0.28, 0.16, 0.16, 0, 1.80, 1.02, D);               // snout
  M.box(0.30, 0.07, 0.06, 0, 1.90, 0.98, E);               // visor
  M.glow(0, 1.90, 1.04, 0.4);
  [-1, 1].forEach(function (s) {
    M.box(0.08, 0.18, 0.08, s * 0.14, 2.08, 0.66, D);      // ear
    M.box(0.06, 0.06, 0.06, s * 0.14, 2.20, 0.66, E);      // ear tip
  });

  // ---- TAIL (swept up behind) ----
  M.box(0.10, 0.10, 0.70, 0, 1.66, -0.80, D, 0.5);         // tail
  M.box(0.08, 0.08, 0.10, 0, 1.86, -1.12, E);              // tail tip
  M.glow(0, 1.86, -1.18, 0.3);

  // ---- SHOULDERS + 2 LIGHT HARDPOINTS ----
  [-1, 1].forEach(function (s) {
    M.box(0.24, 0.36, 0.50, s * 0.55, 1.56, 0.16, A);      // shoulder block
    M.box(0.20, 0.16, 0.26, s * 0.62, 1.48, 0.42, MO);     // light mount
    M.box(0.05, 0.26, 0.40, s * 0.44, 1.46, -0.10, E);     // flank seam
    M.glow(s * 0.47, 1.46, -0.10, 0.35);
  });

  // ---- PELVIS ----
  M.box(0.66, 0.30, 0.52, 0, 0.94, 0, D);

  // ---- LEGS (long digitigrade sprinter) ----
  [-1, 1].forEach(function (s) {
    const hx = s * 0.36;
    const hip  = [hx, 0.95,  0.00];
    const knee = [hx, 0.62,  0.24];
    const hock = [hx, 0.30, -0.28];
    const toe  = [hx, 0.12,  0.08];
    M.box(0.28, 0.26, 0.30, hip[0], hip[1], hip[2], A);
    M.between(hip, knee, 0.22, 0.26, A);
    M.between(knee, hock, 0.18, 0.20, D);
    M.between(hock, toe, 0.15, 0.17, D);
    M.box(0.28, 0.12, 0.40, hx, 0.06, 0.08, A);            // toe pad
  });
}
