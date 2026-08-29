// ============================================================================
// Hardpoint — weapon geometry builders (box-model, gunmetal family).
// Shared by the weapon-rack sheet and the HUD-thumbnail generator so both
// render the exact same models. Each fn takes the build API M from
// weapon-engine.js. Local space: muzzle = +Z, +Y up, +X right.
//
// Emissive convention (per direction from design):
//   - Projectile weapons  -> M.heat() at the bore (orange muzzle heat).
//   - Energy weapons      -> the GUN stays inert metal; only a small charged
//                            emitter "tell" glows (M.glow). The bright part is
//                            the SHOT, which lives in-game, not on the model.
// ============================================================================
(function () {
  // roster-tunable: missiles per rack (game source not in this project)
  const MISSILES_L = 8, MISSILES_H = 12;
  // energy tell colors
  const C_LASER = 0x35e0ff;   // focused lens
  const C_ARC = 0x9fd0ff;     // electrode node
  const C_PATIENCE = 0xb061ff; // twin-prong charge (purple)

  // ---------- shared sub-parts ----------
  function grip(M, x, z, rot) {
    M.box(0.13, 0.24, 0.13, x, -0.20, z, M.detail, 0, 0, rot || -0.32);
  }
  function boreHeat(M, x, y, z, s) { M.heat(x, y, z, s); }

  // =========================== RIFLE (Service A) ===========================
  function Rifle(M) {
    const A = M.armor, D = M.detail, MI = M.mid, K = M.dark;
    M.box(0.26, 0.30, 0.72, 0, 0.00, 0.05, A);
    M.box(0.12, 0.06, 0.64, 0, 0.18, 0.02, D);
    M.box(0.10, 0.10, 0.06, 0, 0.24, -0.20, K);
    M.box(0.05, 0.14, 0.05, 0, 0.20, 0.62, K);
    M.box(0.20, 0.18, 0.40, 0, 0.00, 0.42, A);
    [-1, 0, 1].forEach(i => M.box(0.22, 0.03, 0.05, 0, 0.09, 0.34 + i * 0.12, K));
    M.box(0.12, 0.12, 0.62, 0, 0.00, 0.74, MI);
    M.box(0.15, 0.15, 0.12, 0, 0.00, 1.06, K);
    boreHeat(M, 0, 0.00, 1.16, 0.36);
    M.box(0.16, 0.34, 0.22, 0, -0.28, 0.12, D, 0.26);
    M.box(0.16, 0.14, 0.20, 0, -0.44, 0.17, D, 0.26);
    M.box(0.10, 0.05, 0.22, 0, -0.14, -0.02, K);
    grip(M, 0, -0.12, -0.35);
    M.box(0.16, 0.22, 0.50, 0, -0.02, -0.50, A);
    M.box(0.12, 0.06, 0.30, 0, 0.12, -0.45, D);
    M.box(0.18, 0.28, 0.08, 0, -0.02, -0.76, K);
  }

  // =============================== SNIPER (C) ==============================
  function Sniper(M) {
    const A = M.armor, D = M.detail, MI = M.mid, K = M.dark;
    M.box(0.22, 0.26, 0.82, 0, 0.00, -0.10, A);
    M.box(0.10, 0.05, 1.40, 0, 0.16, 0.12, K);           // full-length rail
    M.box(0.06, 0.12, 0.06, 0, 0.24, -0.20, K);
    M.box(0.06, 0.12, 0.06, 0, 0.24, 0.08, K);
    M.box(0.14, 0.14, 0.52, 0, 0.32, -0.06, MI);         // scope tube
    M.box(0.17, 0.17, 0.12, 0, 0.32, 0.22, K);
    M.box(0.15, 0.15, 0.10, 0, 0.32, -0.36, K);
    M.box(0.11, 0.11, 1.10, 0, -0.02, 0.72, MI);         // barrel
    for (let i = 0; i < 7; i++) M.box(0.16, 0.16, 0.03, 0, -0.02, 0.42 + i * 0.13, D);
    M.box(0.20, 0.20, 0.20, 0, -0.02, 1.34, K);          // muzzle brake
    boreHeat(M, 0, -0.02, 1.48, 0.38);
    M.box(0.15, 0.30, 0.20, 0, -0.24, -0.05, D, 0.14);
    grip(M, 0, -0.28, -0.30);
    M.tube([0.0, 0.06, -0.30], [0.0, 0.02, -0.70], 0.09, 0.05, MI);
    M.tube([0.0, -0.16, -0.20], [0.0, -0.08, -0.66], 0.09, 0.05, MI);
    M.box(0.16, 0.34, 0.08, 0, -0.02, -0.74, A);
  }

  // ============================= MACHINE GUN ==============================
  function MachineGun(M) {
    const A = M.armor, D = M.detail, MI = M.mid, K = M.dark;
    M.box(0.34, 0.34, 0.62, 0, 0.00, 0.00, A);           // heavy receiver
    M.box(0.14, 0.06, 0.50, 0, 0.22, 0.00, D);           // top rail
    M.box(0.10, 0.10, 0.08, 0, 0.28, -0.16, K);          // rear sight
    // perforated barrel shroud
    M.box(0.24, 0.24, 0.66, 0, 0.02, 0.55, A);
    for (let i = 0; i < 5; i++) { const z = 0.34 + i * 0.13; [-1, 1].forEach(s => M.box(0.02, 0.14, 0.07, s * 0.13, 0.02, z, K)); M.box(0.14, 0.02, 0.07, 0, 0.14, z, K); }
    M.box(0.13, 0.13, 0.72, 0, 0.02, 0.86, MI);          // thick barrel
    M.box(0.17, 0.17, 0.14, 0, 0.02, 1.24, K);           // flash hider
    boreHeat(M, 0, 0.02, 1.36, 0.44);
    // side drum magazine
    M.box(0.16, 0.40, 0.40, 0.30, -0.06, 0.02, D);
    M.box(0.06, 0.34, 0.34, 0.40, -0.06, 0.02, K);       // drum face
    M.box(0.10, 0.06, 0.14, 0.14, -0.06, 0.10, K);       // belt feed lip
    M.box(0.12, 0.05, 0.22, 0, -0.18, -0.02, K);         // trigger guard
    grip(M, 0, -0.16, -0.30);
    M.box(0.30, 0.34, 0.10, 0, 0.00, -0.34, A);          // butt plate
    // rear bipod-less brace (foregrip under barrel)
    M.box(0.10, 0.18, 0.10, 0, -0.20, 0.62, D, 0.2);
  }

  // ================================ SHOTGUN ================================
  function Shotgun(M) {
    const A = M.armor, D = M.detail, MI = M.mid, K = M.dark;
    M.box(0.28, 0.30, 0.52, 0, 0.00, 0.02, A);           // stubby receiver
    M.box(0.12, 0.05, 0.34, 0, 0.19, 0.00, D);           // top rib + bead
    M.box(0.04, 0.08, 0.04, 0, 0.24, 0.50, K);           // front bead
    // wide barrel + tube mag under it
    M.box(0.20, 0.20, 0.72, 0, 0.06, 0.52, MI);          // fat barrel
    M.box(0.24, 0.24, 0.12, 0, 0.06, 0.92, K);           // wide muzzle / choke
    M.box(0.30, 0.30, 0.04, 0, 0.06, 0.99, K);           // bore mouth ring
    boreHeat(M, 0, 0.06, 1.02, 0.46);
    M.box(0.15, 0.15, 0.60, 0, -0.14, 0.46, D);          // tube magazine
    M.box(0.16, 0.16, 0.10, 0, -0.14, 0.78, K);          // mag cap
    // pump forend
    M.box(0.26, 0.14, 0.24, 0, -0.06, 0.44, A);
    [-1, 0, 1].forEach(i => M.box(0.28, 0.03, 0.04, 0, 0.02, 0.36 + i * 0.10, K));
    M.box(0.10, 0.05, 0.18, 0, -0.16, -0.06, K);
    grip(M, 0, -0.14, -0.30);
    M.box(0.16, 0.24, 0.42, 0, -0.02, -0.42, A);         // stock
    M.box(0.18, 0.28, 0.07, 0, -0.02, -0.64, K);
  }

  // =========================== MISSILE LAUNCHER ===========================
  // rack of small missiles behind an open cellular face (8 L / 12 H)
  function makeMissiles(M, cols, rows) {
    const A = M.armor, D = M.detail, K = M.dark;
    const W = 0.60, H = 0.44, cw = W / cols, ch = H / rows;
    M.box(W + 0.14, H + 0.16, 0.62, 0, 0.06, 0.00, A);   // housing
    M.box(W + 0.02, H + 0.02, 0.06, 0, 0.06, 0.34, K);   // open face plate
    for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) {
      const x = -W / 2 + cw / 2 + c * cw;
      const y = 0.06 - H / 2 + ch / 2 + r * ch;
      M.box(cw * 0.82, ch * 0.82, 0.10, x, y, 0.30, K);            // tube mouth (dark)
      M.box(cw * 0.42, ch * 0.42, 0.16, x, y, 0.40, M.mid);        // missile body
      M.box(cw * 0.30, ch * 0.30, 0.10, x, y, 0.50, D);            // nose cone
    }
    M.box(W + 0.18, H + 0.20, 0.10, 0, 0.06, -0.32, D);  // back plate
    M.box(0.14, 0.22, 0.14, 0, -0.24, -0.10, D, -0.2);   // mount lug / grip
    M.box(0.10, 0.06, 0.30, 0.0, 0.30, 0.05, K);         // top guide rail
  }
  function MissileL(M) { makeMissiles(M, 4, 2); }        // 8
  function MissileH(M) { makeMissiles(M, 4, 3); }        // 12

  // ============================ ROCKET LAUNCHER ===========================
  // fat single tube, angled UP-forward, homing warhead visible at the mouth
  function RocketLauncher(M) {
    const A = M.armor, D = M.detail, MI = M.mid, K = M.dark;
    // angled bore: back-low -> front-high
    const back = [0, -0.02, -0.42], front = [0, 0.30, 0.66];
    M.tube(back, front, 0.30, 0.30, A);                  // launch tube
    // ribs along the tube
    for (let i = 0; i < 4; i++) {
      const t = 0.15 + i * 0.22;
      const x = back[0] + (front[0] - back[0]) * t;
      const y = back[1] + (front[1] - back[1]) * t;
      const z = back[2] + (front[2] - back[2]) * t;
      M.box(0.34, 0.05, 0.05, x, y, z, K, -0.3, 0, 0);
    }
    // warhead nose peeking out of the muzzle
    M.box(0.20, 0.20, 0.20, front[0], front[1] + 0.02, front[2] + 0.02, MI, -0.3);
    M.box(0.14, 0.14, 0.14, front[0], front[1] + 0.08, front[2] + 0.12, K, -0.3); // dark tip
    boreHeat(M, front[0], front[1] + 0.06, front[2] + 0.10, 0.40);
    // rear blast vent
    M.box(0.30, 0.30, 0.12, back[0], back[1], back[2] - 0.06, K, -0.3);
    M.box(0.36, 0.10, 0.10, 0, 0.12, 0.05, D, -0.3);     // top sight rail
    // shoulder mount / grip under the tube
    M.box(0.16, 0.24, 0.22, 0, -0.24, 0.02, D, -0.15);
    M.box(0.40, 0.14, 0.30, 0, -0.30, -0.10, A);         // saddle mount
  }

  // ============================== LASER CANNON ============================
  // inert focusing barrel; only a small charged-lens tell glows
  function LaserCannon(M) {
    const A = M.armor, D = M.detail, MI = M.mid, K = M.dark;
    M.box(0.30, 0.30, 0.58, 0, 0.00, -0.10, A);          // emitter body
    M.box(0.14, 0.08, 0.44, 0, 0.20, -0.08, D);          // top heat-sink rail
    for (let i = 0; i < 6; i++) M.box(0.18, 0.10, 0.02, 0, 0.24, -0.24 + i * 0.07, K); // sink fins
    // focusing barrel with concentric rings
    M.box(0.18, 0.18, 0.70, 0, 0.00, 0.42, MI);
    for (let i = 0; i < 5; i++) M.box(0.26, 0.26, 0.04, 0, 0.00, 0.20 + i * 0.15, D); // focus rings
    M.box(0.30, 0.30, 0.06, 0, 0.00, 0.80, K);           // lens housing
    M.box(0.20, 0.20, 0.04, 0, 0.00, 0.84, MI);          // lens
    M.glow(C_LASER, 0, 0.00, 0.88, 0.30, 0.14);          // small charged-lens tell
    // underside capacitor + grip
    M.box(0.20, 0.18, 0.30, 0, -0.22, -0.06, D);         // capacitor
    grip(M, 0, -0.16, -0.28);
    M.box(0.16, 0.24, 0.40, 0, -0.02, -0.44, A);         // stock
    M.box(0.18, 0.28, 0.07, 0, -0.02, -0.64, K);
  }

  // =============================== ARC WEAPON =============================
  // twin electrode prongs + coil; a charged node sits between the prongs
  function ArcWeapon(M) {
    const A = M.armor, D = M.detail, MI = M.mid, K = M.dark;
    M.box(0.30, 0.32, 0.52, 0, 0.00, -0.08, A);          // body
    M.box(0.14, 0.07, 0.36, 0, 0.21, -0.06, D);          // top rail
    // coil pack (stacked rings) on the barrel
    M.box(0.16, 0.16, 0.46, 0, 0.02, 0.34, MI);
    for (let i = 0; i < 5; i++) M.box(0.24, 0.24, 0.05, 0, 0.02, 0.18 + i * 0.11, D); // coils
    // two forked electrode prongs
    M.box(0.05, 0.05, 0.30, 0, 0.16, 0.66, K);           // upper prong
    M.box(0.05, 0.05, 0.30, 0, -0.12, 0.66, K);          // lower prong
    M.box(0.05, 0.05, 0.05, 0, 0.16, 0.82, MI);          // upper tip
    M.box(0.05, 0.05, 0.05, 0, -0.12, 0.82, MI);         // lower tip
    M.glow(C_ARC, 0, 0.02, 0.80, 0.26, 0.12);            // charged node between prongs
    // underside battery + grip
    M.box(0.20, 0.20, 0.28, 0, -0.22, -0.04, D);
    grip(M, 0, -0.14, -0.26);
    M.box(0.16, 0.24, 0.38, 0, -0.02, -0.40, A);
    M.box(0.18, 0.28, 0.07, 0, -0.02, -0.60, K);
  }

  // ============================ PATIENCE (Heavy) ==========================
  // charge-up energy sniper: twin long prongs (one above the other), inner
  // faces emissive purple; heavy capacitor drum at the base.
  function Patience(M) {
    const A = M.armor, D = M.detail, MI = M.mid, K = M.dark;
    // heavy base receiver
    M.box(0.32, 0.34, 0.70, 0, 0.00, -0.30, A);
    M.box(0.14, 0.06, 0.60, 0, 0.22, -0.30, D);          // top rail
    M.box(0.16, 0.16, 0.14, 0, 0.30, -0.10, K);          // small sight bump
    // capacitor drum (charge store) under/behind
    M.box(0.30, 0.30, 0.30, 0, -0.10, -0.56, MI);
    for (let i = 0; i < 4; i++) M.box(0.36, 0.36, 0.04, 0, -0.10, -0.68 + i * 0.09, D); // drum ribs
    // twin prongs extending forward, gap between them
    const gap = 0.16, PL = 1.00, z0 = 0.10;
    // upper prong
    M.box(0.14, 0.10, PL, 0, gap, z0 + PL / 2 - 0.1, MI);
    // lower prong
    M.box(0.14, 0.10, PL, 0, -gap, z0 + PL / 2 - 0.1, MI);
    // inner emissive faces (thin purple plates facing the gap)
    M.box(0.11, 0.02, PL - 0.06, 0, gap - 0.05, z0 + PL / 2 - 0.1, M.emisMat(C_PATIENCE));
    M.box(0.11, 0.02, PL - 0.06, 0, -gap + 0.05, z0 + PL / 2 - 0.1, M.emisMat(C_PATIENCE));
    // prong tips
    M.box(0.16, 0.12, 0.10, 0, gap, z0 + PL, K);
    M.box(0.16, 0.12, 0.10, 0, -gap, z0 + PL, K);
    // charge glow building in the gap (mid-charge state)
    M.glow(C_PATIENCE, 0, 0, z0 + 0.30, 0.34, 0.12);
    M.glow(C_PATIENCE, 0, 0, z0 + 0.70, 0.30, 0.10);
    // grip + stock
    grip(M, 0, -0.44, -0.34);
    M.box(0.16, 0.24, 0.46, 0, -0.02, -0.78, A);
    M.box(0.18, 0.28, 0.07, 0, -0.02, -1.00, K);
  }

  // =========================== AERIAL STRIKE (H) ==========================
  // near-vertical rocket rack: tubes point UP with slight forward lean
  function AerialStrike(M) {
    const A = M.armor, D = M.detail, MI = M.mid, K = M.dark;
    // base saddle that clamps to the mech shoulder
    M.box(0.72, 0.20, 0.62, 0, -0.34, 0.00, A);
    M.box(0.50, 0.10, 0.50, 0, -0.22, 0.00, M.socket);
    // the upward tube block — dense MLRS-style cluster, ~45 tubes
    const cols = 7, rows = 7, W = 0.62, D2 = 0.62, cw = W / cols, cd = D2 / rows;
    const LEAN = 0.14, PIVOT_Y = 0.14, PIVOT_Z = 0.02;
    M.box(W + 0.12, 0.70, D2 + 0.12, 0, PIVOT_Y, PIVOT_Z, A, LEAN, 0, 0); // housing, slight lean
    // rotate a flat grid point around the housing's pivot so tubes ride its tilt rigidly
    function lean(y, z) {
      const dy = y - PIVOT_Y, dz = z - PIVOT_Z;
      const c = Math.cos(LEAN), s = Math.sin(LEAN);
      return [PIVOT_Y + dy * c - dz * s, PIVOT_Z + dy * s + dz * c];
    }
    let n = 0;
    for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) {
      // drop corners to round the cluster toward a circular pod (~45 tubes)
      const cx = c - (cols - 1) / 2, cz = r - (rows - 1) / 2;
      if (Math.hypot(cx, cz) > (cols - 1) / 2 + 0.15) continue;
      n++;
      const x = -W / 2 + cw / 2 + c * cw;
      const zoff = -D2 / 2 + cd / 2 + r * cd;
      const [my, mz] = lean(0.50, zoff + 0.06);
      const [by, bz] = lean(0.46, zoff + 0.05);
      const [ny, nz] = lean(0.56, zoff + 0.07);
      // tube pointing up (+Y), leaned forward with the housing
      M.box(cw * 0.78, 0.10, cd * 0.78, x, my, mz, K, LEAN);   // tube mouth (up)
      M.box(cw * 0.40, 0.16, cd * 0.40, x, by, bz, MI, LEAN);  // rocket body
      M.box(cw * 0.28, 0.10, cd * 0.28, x, ny, nz, D, LEAN);   // nose up
    }
    M.box(W + 0.16, 0.10, D2 + 0.16, 0, -0.16, 0.0, D);  // bottom plate
    // small fins on the housing sides
    [-1, 1].forEach(s => M.box(0.05, 0.34, 0.30, s * (W / 2 + 0.10), 0.14, 0.0, D, 0.14));
  }

  window.WEAPONS = {
    Rifle, Sniper, MachineGun, Shotgun,
    MissileL, MissileH, RocketLauncher,
    LaserCannon, ArcWeapon, Patience, AerialStrike,
    _meta: { MISSILES_L, MISSILES_H, C_LASER, C_ARC, C_PATIENCE },
  };
})();
