// T181: Warhog, authored in the design kit's box language (the kit has no Warhog render).
// Same M API as design/preview/mech-engine.js; kit space (+Z forward). tools/kit_port.py
// reads this next to the kit's brand-mech-render-*.html.
// palette: armor #5C4A33, detail #7A6342, emissive none   (Heavy · boar tank, pure grit, no glow)
build: function (M) {
  const A = M.armor, D = M.detail, MO = M.mount, SK = M.socket;

  // ---- TORSO (wide, low, humped) ----
  M.box(1.36, 0.86, 1.10, 0, 1.48, 0.00, A);               // main mass
  M.box(1.10, 0.36, 0.70, 0, 1.98, -0.20, D);              // hump
  M.box(1.10, 0.30, 0.80, 0, 1.02, 0.00, D);               // torso-to-pelvis bevel
  [-1, 1].forEach(function (s) {
    M.box(0.08, 0.40, 0.80, s * 0.72, 1.20, 0.00, D);      // armour skirt
    M.box(0.18, 0.40, 0.18, s * 0.36, 2.10, -0.52, SK);    // exhaust stack
  });

  // ---- HEAD (low snout, tusks) ----
  M.box(0.62, 0.46, 0.56, 0, 1.42, 0.76, A);               // head
  M.box(0.50, 0.30, 0.10, 0, 1.38, 1.06, D);               // snout plate
  [-1, 1].forEach(function (s) {
    M.box(0.10, 0.08, 0.04, s * 0.12, 1.36, 1.12, SK);     // nostril
    M.box(0.10, 0.06, 0.04, s * 0.18, 1.58, 1.04, SK);     // eye slit (no glow)
    M.box(0.08, 0.08, 0.34, s * 0.26, 1.24, 1.06, D, -0.5); // tusk
    M.box(0.07, 0.14, 0.07, s * 0.26, 1.40, 1.22, D);      // tusk tip
  });

  // ---- SHOULDERS: heavy mount (left in kit space = game slot 0) + light mount ----
  [-1, 1].forEach(function (s) {
    M.box(0.48, 0.66, 0.86, s * 0.92, 1.62, 0.00, A);      // shoulder block
    M.box(0.52, 0.14, 0.90, s * 0.92, 2.00, 0.00, D);      // shoulder cap
  });
  M.box(0.40, 0.40, 0.46, 0.92, 1.66, 0.50, MO);           // heavy mount
  M.box(0.30, 0.30, 0.14, 0.92, 1.66, 0.76, MO);           // heavy mount collar
  M.box(0.22, 0.20, 0.28, -0.92, 1.60, 0.50, MO);          // light mount

  // ---- PELVIS ----
  M.box(1.10, 0.48, 0.80, 0, 0.94, 0.00, D);

  // ---- LEGS (thick, short, planted) ----
  [-1, 1].forEach(function (s) {
    const hx = s * 0.58;
    const hip  = [hx, 0.96, -0.02];
    const knee = [hx, 0.64,  0.26];
    const hock = [hx, 0.30, -0.34];
    const toe  = [hx, 0.20,  0.10];
    M.box(0.52, 0.44, 0.52, hip[0], hip[1], hip[2], A);
    M.between(hip, knee, 0.46, 0.48, A);
    M.between(knee, hock, 0.40, 0.40, D);
    M.between(hock, toe, 0.34, 0.34, D);
    M.box(0.60, 0.20, 0.72, hx, 0.10, 0.14, A);            // big foot
  });
}
