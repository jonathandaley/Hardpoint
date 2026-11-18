// T455: Heron, a medium mech authored in the design kit's box language (tools/new_mech.py).
// Same M API as design/preview/mech-engine.js; kit space (+Z forward). See tools/kit_mechs/README.md.
// User 2026-11-17: "add as many mechs as you think are good". Roster gap: nobody supports the team.
// Heron is the field medic: FIELD REPAIR heals it and every ally within 18 m for 5 s. A wading bird:
// tall thin legs, a slim body, a long neck carrying the head forward, a repair mast on its back.
// palette: armor #7C8C99, detail #2E3A40, emissive #5CFF9A e2.4   (Medium - a heron: stilt legs, FIELD REPAIR)
build: function (M) {
  const A = M.armor, D = M.detail, MO = M.mount, SK = M.socket, E = M.emis;

  // ---- BODY: slim, high on the legs ----
  M.box(0.72, 0.52, 0.96, 0, 1.70, -0.04, A);              // body
  M.box(0.60, 0.12, 0.84, 0, 1.99, -0.06, D);              // back plate
  M.box(0.50, 0.24, 0.50, 0, 1.36, -0.02, D);              // belly
  M.box(0.40, 0.05, 0.04, 0, 1.72, 0.45, E);               // chest light
  M.glow(0, 1.72, 0.50, 0.3);

  // ---- NECK + HEAD: forward and up ----
  M.box(0.18, 0.56, 0.18, 0, 2.08, 0.42, D, -0.5, 0, 0);   // neck, leaning forward
  M.box(0.30, 0.22, 0.38, 0, 2.34, 0.62, A);               // head
  M.box(0.10, 0.08, 0.34, 0, 2.30, 0.94, D);               // bill
  M.box(0.24, 0.04, 0.04, 0, 2.38, 0.82, E);               // eye slit
  M.glow(0, 2.38, 0.86, 0.25);

  // ---- REPAIR MAST: a short mast with a green emitter ring on the back ----
  M.box(0.08, 0.50, 0.08, 0, 2.26, -0.30, SK);             // mast
  M.box(0.36, 0.06, 0.36, 0, 2.52, -0.30, E);              // emitter
  M.box(0.24, 0.10, 0.24, 0, 2.58, -0.30, D);              // emitter cap
  M.glow(0, 2.52, -0.30, 0.4);

  // ---- TWO LIGHT MOUNTS: body flanks ----
  [-1, 1].forEach(function (s) {
    M.box(0.20, 0.22, 0.28, s * 0.46, 1.66, 0.28, MO);
    M.box(0.06, 0.30, 0.50, s * 0.38, 1.78, -0.30, D);     // folded wing plate
  });

  // ---- PELVIS ----
  M.box(0.46, 0.22, 0.40, 0, 1.24, 0, D);

  // ---- LEGS: long stilts, backward knees ----
  [-1, 1].forEach(function (s) {
    const hx = s * 0.26;
    const hip  = [hx, 1.24,  0.00];
    const knee = [hx, 0.80, -0.20];
    const hock = [hx, 0.34,  0.10];
    const toe  = [hx, 0.08,  0.00];
    M.box(0.22, 0.24, 0.26, hip[0], hip[1], hip[2], A);
    M.between(hip, knee, 0.16, 0.18, A);                   // thigh
    M.between(knee, hock, 0.10, 0.12, D);                  // shin
    M.between(hock, toe, 0.10, 0.10, D);                   // pastern
    M.box(0.28, 0.06, 0.52, hx, 0.03, 0.10, SK);           // splayed foot
    M.box(0.06, 0.06, 0.06, hx, 0.80, -0.26, E);           // knee lamp
  });
}
