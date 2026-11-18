// T454: Swift, a light mech authored in the design kit's box language (tools/new_mech.py).
// Same M API as design/preview/mech-engine.js; kit space (+Z forward). See tools/kit_mechs/README.md.
// User 2026-11-17: "add as many mechs as you think are good". Roster gap: lights are speed (Slip),
// stealth (Cesh) and a big gun (Seeker); none can dodge. Swift is the duelist: DASH, a short burst
// in any direction. A slim forward-leaning body, swept-back wing fins, a beak of a head, bird legs.
// palette: armor #C9D3DC, detail #22314A, emissive #FFB23F e2.4   (Light - a swift: swept fins, DASH)
build: function (M) {
  const A = M.armor, D = M.detail, MO = M.mount, SK = M.socket, E = M.emis;

  // ---- BODY: a narrow wedge, nose down ----
  M.box(0.62, 0.46, 0.80, 0, 1.36, 0.02, A, 0.12, 0, 0);   // body, tipped forward
  M.box(0.50, 0.14, 0.70, 0, 1.62, -0.04, D, 0.12, 0, 0);  // dorsal band
  M.box(0.44, 0.04, 0.04, 0, 1.30, 0.43, E);               // chest light
  M.glow(0, 1.30, 0.48, 0.3);
  M.box(0.46, 0.20, 0.46, 0, 1.06, 0.00, D);               // waist

  // ---- HEAD: a beak ----
  M.box(0.30, 0.22, 0.36, 0, 1.70, 0.38, A);               // head
  M.box(0.16, 0.12, 0.26, 0, 1.66, 0.66, D);               // beak
  M.box(0.26, 0.04, 0.04, 0, 1.74, 0.57, E);               // eye slit
  M.glow(0, 1.74, 0.60, 0.25);

  // ---- WING FINS: swept back off the shoulders ----
  [-1, 1].forEach(function (s) {
    M.box(0.70, 0.08, 0.16, s * 0.58, 1.68, -0.22, D, 0, s * 0.5, 0);    // fin spar, swept back
    M.box(0.62, 0.04, 0.36, s * 0.56, 1.64, -0.36, A, 0, s * 0.5, 0);    // fin web
    M.box(0.14, 0.05, 0.10, s * 0.88, 1.68, -0.39, E, 0, s * 0.5, 0);    // fin tip light
    M.box(0.12, 0.16, 0.20, s * 0.20, 1.50, -0.44, SK);                  // thruster
  });

  // ---- ONE LIGHT MOUNT: right flank ----
  M.box(0.20, 0.22, 0.26, 0.42, 1.36, 0.30, MO);

  // ---- PELVIS ----
  M.box(0.44, 0.22, 0.38, 0, 0.92, 0, D);

  // ---- LEGS: long, thin, bird-jointed ----
  [-1, 1].forEach(function (s) {
    const hx = s * 0.26;
    const hip  = [hx, 0.92,  0.00];
    const knee = [hx, 0.58, -0.24];
    const hock = [hx, 0.26,  0.10];
    const toe  = [hx, 0.08, -0.02];
    M.box(0.20, 0.22, 0.24, hip[0], hip[1], hip[2], A);
    M.between(hip, knee, 0.16, 0.20, A);                   // thigh
    M.between(knee, hock, 0.12, 0.14, D);                  // shin
    M.between(hock, toe, 0.10, 0.12, D);                   // pastern
    M.box(0.20, 0.08, 0.40, hx, 0.04, 0.08, SK);           // long toe pad
    M.box(0.06, 0.06, 0.06, hx, 0.58, -0.30, E);           // knee lamp
  });
}
