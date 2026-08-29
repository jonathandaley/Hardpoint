// Hardpoint UI Kit — repair-bay multi-mech renderer.
// Reuses the canonical box-model build functions from the brand mech-render
// cards so each chassis is authentic (Vesuvius really is the wide dreadnought,
// Slip the light sprinter). Renders each squad mech into its own <canvas> via
// ONE shared WebGL context + a common 3/4 ortho camera, so the whole rank
// shares scale (the heavy towers over the light). Needs window.THREE loaded.
//
//   window.MECH_BAY_SQUAD            — squad metadata for the Hangar UI
//   window.renderMechBay(canvases, texBase) — paint each canvas, in squad order
/* eslint-disable */
(function () {
  // ---- canonical squad: metadata + authentic build fn (verbatim geometry) ----
  var SQUAD = [
    {
      name: "SLIP", klass: "LIGHT", role: "SPRINTER", accent: "#1AD9FF",
      armorTex: "slip-armor.png", detailTex: "slip-detail.png",
      emissive: 0x1AD9FF, texRef: 1.16, status: "READY", repair: 100,
      build: function (M) {
        var A = M.armor, D = M.detail, MO = M.mount, SK = M.socket, E = M.emis;
        M.box(1.16, 0.92, 0.82, 0, 1.58, 0, A);
        M.box(0.70, 0.50, 0.06, 0, 1.60, 0.43, D);
        M.box(0.98, 0.24, 0.70, 0, 1.10, 0, D);
        M.box(1.18, 0.30, 0.30, 0, 1.74, -0.32, D);
        M.box(0.64, 0.16, 0.64, 0, 2.07, 0.00, MO);
        M.box(0.46, 0.12, 0.46, 0, 2.17, 0.02, MO);
        M.box(0.30, 0.14, 0.30, 0, 2.25, 0.02, SK);
        M.box(0.11, 0.22, 0.11, 0, 2.35, 0.02, SK);
        [-1, 1].forEach(function (s) {
          M.box(0.20, 0.62, 0.54, s * 0.66, 1.70, 0.10, A, -0.16);
          M.box(0.10, 0.66, 0.30, s * 0.71, 1.70, 0.04, D, -0.16);
          M.box(0.07, 0.44, 0.16, s * 0.79, 1.72, 0.12, E, -0.16);
          M.glow(s * 0.82, 1.73, 0.15, 0.5);
        });
        M.box(0.76, 0.36, 0.62, 0, 0.94, 0, D);
        [-1, 1].forEach(function (s) {
          var hx = s * 0.40;
          var hip = [hx, 0.95, 0.00], knee = [hx, 0.62, 0.22], hock = [hx, 0.30, -0.26], toe = [hx, 0.12, 0.08];
          M.box(0.33, 0.30, 0.34, hip[0], hip[1], hip[2], A);
          M.between(hip, knee, 0.27, 0.30, A);
          M.between(knee, hock, 0.22, 0.24, D);
          M.between(hock, toe, 0.18, 0.20, D);
          M.box(0.32, 0.12, 0.38, hx, 0.06, 0.08, A);
        });
      },
    },
    {
      name: "CESH", klass: "MEDIUM", role: "STEALTH", accent: "#8fb083",
      armorTex: "cesh-armor.png", detailTex: "cesh-detail.png",
      emissive: null, texRef: 1.1, lookI: 0, status: "READY", repair: 100,
      build: function (M) {
        var A = M.armor, D = M.detail, MO = M.mount;
        M.box(1.22, 0.80, 0.86, 0, 1.34, 0.06, A, -0.18);
        M.box(0.80, 0.52, 0.10, 0, 1.40, 0.50, D, -0.18);
        M.box(1.04, 0.26, 0.74, 0, 0.98, 0.02, D);
        M.box(1.10, 0.34, 0.34, 0, 1.52, -0.34, D, -0.18);
        M.box(0.46, 0.12, 0.14, 0, 1.62, 0.40, M.socket, -0.18);
        [-1, 1].forEach(function (s) {
          M.box(0.40, 0.52, 0.60, s * 0.72, 1.50, 0.04, A, 0, 0, s * 0.34);
          M.box(0.20, 0.30, 0.40, s * 0.88, 1.38, 0.04, D, 0, 0, s * 0.34);
        });
        M.box(0.22, 0.36, 0.44, -0.66, 1.36, 0.06, MO, -0.18);
        M.box(0.18, 0.34, 0.40, 0.66, 1.36, 0.06, D, -0.18);
        M.box(0.13, 0.10, 0.18, 0.72, 1.30, 0.26, D);
        M.box(0.12, 0.20, 0.12, 0.62, 1.58, 0.02, D);
        M.box(0.05, 0.32, 0.05, 0.62, 1.80, 0.02, MO);
        M.box(0.10, 0.07, 0.10, 0.62, 1.98, 0.02, MO);
        M.box(0.82, 0.36, 0.66, 0, 0.82, 0.02, D);
        [-1, 1].forEach(function (s) {
          var hx = s * 0.42;
          var hip = [hx, 0.83, 0.02], knee = [hx, 0.58, 0.30], hock = [hx, 0.26, -0.26], toe = [hx, 0.12, 0.06];
          M.box(0.36, 0.30, 0.36, hip[0], hip[1], hip[2], A);
          M.between(hip, knee, 0.30, 0.32, A);
          M.between(knee, hock, 0.24, 0.26, D);
          M.between(hock, toe, 0.20, 0.22, D);
          M.box(0.36, 0.12, 0.40, hx, 0.06, 0.07, A);
        });
      },
    },
    {
      name: "HORNET", klass: "MEDIUM", role: "JET", accent: "#99CCFF",
      armorTex: "hornet-armor.png", detailTex: "hornet-detail.png",
      emissive: 0x99CCFF, texRef: 1.1, keyI: 1.35, ambI: 0.92, rimI: 0.7,
      status: "REPAIRING", repair: 41,
      build: function (M) {
        var A = M.armor, D = M.detail, MO = M.mount, E = M.emis;
        var PITCH = -0.20;
        M.box(1.02, 0.94, 0.72, 0, 1.50, 0.06, A, PITCH);
        M.box(0.96, 0.24, 0.40, 0, 1.74, -0.30, D, PITCH);
        M.box(0.86, 0.22, 0.56, 0, 1.06, 0.10, D, PITCH);
        M.box(0.50, 0.38, 0.52, 0, 1.92, 0.22, A, -0.34);
        M.box(0.34, 0.18, 0.14, 0, 1.94, 0.48, E, -0.34);
        M.glow(0, 1.95, 0.54, 0.55);
        [-1, 1].forEach(function (s) {
          M.box(0.28, 0.32, 0.40, s * 0.32, 1.62, -0.46, D, PITCH);
          M.box(0.17, 0.20, 0.12, s * 0.32, 1.56, -0.66, E);
          M.glow(s * 0.32, 1.55, -0.72, 0.5);
        });
        [-1, 1].forEach(function (s) {
          M.box(0.30, 0.42, 0.50, s * 0.66, 1.54, 0, A, PITCH);
          M.box(0.56, 0.10, 0.34, s * 0.92, 1.62, -0.18, A, 0, s * 0.55, -s * 0.30);
          M.box(0.30, 0.07, 0.20, s * 1.14, 1.70, -0.34, D, 0, s * 0.55, -s * 0.30);
          M.box(0.22, 0.18, 0.26, s * 0.62, 1.50, 0.26, MO);
        });
        M.box(0.72, 0.32, 0.58, 0, 0.92, 0.02, D);
        [-1, 1].forEach(function (s) {
          var hx = s * 0.38;
          var hip = [hx, 0.92, 0.04], knee = [hx, 0.60, 0.30], hock = [hx, 0.28, -0.24], toe = [hx, 0.12, 0.14];
          M.box(0.31, 0.30, 0.34, hip[0], hip[1], hip[2], A);
          M.between(hip, knee, 0.26, 0.30, A);
          M.between(knee, hock, 0.21, 0.23, D);
          M.between(hock, toe, 0.17, 0.19, D);
          M.box(0.31, 0.12, 0.42, hx, 0.06, 0.14, A);
        });
      },
    },
    {
      name: "PEGASUS", klass: "MEDIUM", role: "JUMP+HEAL", accent: "#FFBF1A",
      armorTex: "pegasus-armor.png", detailTex: "pegasus-detail.png",
      emissive: 0xFFBF1A, texRef: 1.1, keyI: 0.95, ambI: 0.58,
      status: "REPAIRING", repair: 88,
      build: function (M) {
        var A = M.armor, D = M.detail, MO = M.mount, E = M.emis;
        M.box(0.96, 0.94, 0.66, 0, 1.52, 0, A);
        M.box(0.52, 0.48, 0.08, 0, 1.54, 0.33, D);
        M.box(0.24, 0.24, 0.12, 0, 1.52, 0.37, E);
        M.glow(0, 1.52, 0.45, 0.5);
        M.box(0.80, 0.22, 0.50, 0, 1.06, 0, D);
        M.box(0.44, 0.34, 0.46, 0, 2.02, 0.04, A);
        M.box(0.30, 0.09, 0.10, 0, 2.04, 0.24, E);
        M.glow(0, 2.04, 0.30, 0.32);
        M.box(0.09, 0.50, 0.40, 0, 2.34, -0.06, A);
        M.box(0.05, 0.50, 0.07, 0, 2.34, 0.16, E);
        M.glow(0, 2.60, 0.06, 0.4);
        [-1, 1].forEach(function (s) {
          M.box(0.07, 0.32, 0.26, s * 0.13, 2.22, -0.08, A, 0, 0, s * 0.22);
          M.box(0.04, 0.30, 0.05, s * 0.15, 2.22, 0.10, E, 0, 0, s * 0.22);
        });
        M.box(0.62, 0.52, 0.28, 0, 1.64, -0.42, D);
        [-1, 1].forEach(function (s) {
          M.box(0.20, 0.24, 0.20, s * 0.22, 1.40, -0.50, A);
          M.box(0.11, 0.11, 0.09, s * 0.22, 1.34, -0.60, E);
          M.glow(s * 0.22, 1.33, -0.66, 0.4);
        });
        [-1, 1].forEach(function (s) {
          M.box(0.32, 0.44, 0.52, s * 0.66, 1.62, 0, A);
          M.box(0.22, 0.18, 0.26, s * 0.66, 1.56, 0.30, MO);
        });
        M.box(0.70, 0.32, 0.56, 0, 0.90, 0, D);
        [-1, 1].forEach(function (s) {
          var hx = s * 0.38;
          var hip = [hx, 0.90, 0.00], knee = [hx, 0.58, 0.24], hock = [hx, 0.27, -0.26], toe = [hx, 0.12, 0.08];
          M.box(0.31, 0.30, 0.34, hip[0], hip[1], hip[2], A);
          M.between(hip, knee, 0.26, 0.30, A);
          M.between(knee, hock, 0.21, 0.23, D);
          M.between(hock, toe, 0.17, 0.19, D);
          M.box(0.31, 0.12, 0.40, hx, 0.06, 0.08, A);
          M.box(0.09, 0.09, 0.08, hx, 0.30, -0.34, E);
          M.glow(hx, 0.30, -0.40, 0.28);
        });
      },
    },
    {
      name: "VESUVIUS", klass: "HEAVY", role: "DREADNOUGHT", accent: "#FF590D",
      armorTex: "vesuvius-armor.png", detailTex: "vesuvius-detail.png",
      emissive: 0xFF590D, texRef: 1.5, status: "REPAIRING", repair: 72,
      build: function (M) {
        var A = M.armor, D = M.detail, MO = M.mount, SK = M.socket, E = M.emis;
        M.box(1.66, 1.18, 1.08, 0, 1.70, 0, A);
        M.box(1.24, 0.46, 0.10, 0, 1.98, 0.55, D);
        M.box(1.34, 0.40, 0.10, 0, 1.40, 0.55, D);
        M.box(1.46, 0.40, 0.42, 0, 1.98, -0.52, D);
        M.box(0.52, 0.30, 0.16, 0, 1.70, 0.52, E);
        M.glow(0, 1.70, 0.64, 1.5);
        M.box(0.06, 0.78, 0.14, -0.86, 1.66, 0.42, E);
        M.box(0.06, 0.78, 0.14, 0.86, 1.66, 0.42, E);
        M.glow(-0.90, 1.66, 0.46, 0.7); M.glow(0.90, 1.66, 0.46, 0.7);
        M.box(0.52, 0.30, 0.16, 0, 1.70, -0.54, E);
        M.glow(0, 1.70, -0.66, 1.5);
        M.box(0.06, 0.78, 0.14, -0.86, 1.66, -0.42, E);
        M.box(0.06, 0.78, 0.14, 0.86, 1.66, -0.42, E);
        M.glow(-0.90, 1.66, -0.46, 0.7); M.glow(0.90, 1.66, -0.46, 0.7);
        M.box(1.00, 0.10, 0.06, 0, 1.98, -0.74, E);
        M.glow(0, 1.98, -0.80, 1.1);
        M.box(0.46, 0.40, 0.44, 0, 1.98, 0.46, MO);
        M.box(0.32, 0.13, 0.32, 0, 2.16, 0.48, MO);
        M.box(0.66, 0.34, 0.52, 0, 2.36, 0.22, A);
        M.box(0.48, 0.09, 0.12, 0, 2.34, 0.50, E);
        M.glow(0, 2.34, 0.56, 0.6);
        [-1, 1].forEach(function (s) {
          M.box(0.72, 0.78, 0.96, s * 1.14, 2.00, 0, A);
          M.box(0.78, 0.18, 1.00, s * 1.14, 2.41, 0, D);
          M.box(0.42, 0.09, 0.54, s * 1.14, 2.51, 0, E);
          M.glow(s * 1.14, 2.55, 0, 1.0);
          M.box(0.06, 0.50, 0.10, s * 1.14, 1.78, 0.50, E);
          M.box(0.06, 0.50, 0.10, s * 1.14, 1.78, -0.50, E);
          M.glow(s * 1.14, 1.80, -0.54, 0.6);
          M.box(0.42, 0.42, 0.46, s * 1.14, 2.00, 0.60, MO);
          M.box(0.30, 0.30, 0.14, s * 1.14, 2.00, 0.86, MO);
        });
        M.box(1.04, 0.52, 0.84, 0, 1.00, 0, D);
        M.box(1.00, 0.07, 0.12, 0, 0.78, 0.44, E);
        M.glow(0, 0.78, 0.50, 0.7);
        [-1, 1].forEach(function (s) {
          var hx = s * 0.58;
          var hip = [hx, 1.00, 0.00], knee = [hx, 0.66, 0.30], hock = [hx, 0.30, -0.34], toe = [hx, 0.20, 0.14];
          M.box(0.52, 0.44, 0.52, hip[0], hip[1], hip[2], A);
          M.between(hip, knee, 0.46, 0.48, A);
          M.box(0.20, 0.20, 0.20, knee[0], 0.62, 0.26, E);
          M.between(knee, hock, 0.40, 0.40, D);
          M.between(hock, toe, 0.34, 0.34, D);
          M.box(0.58, 0.20, 0.70, hx, 0.10, 0.16, A);
          M.box(0.58, 0.07, 0.12, hx, 0.18, 0.48, E);
        });
      },
    },
  ];

  window.MECH_BAY_SQUAD = SQUAD.map(function (m) {
    return { name: m.name, klass: m.klass, role: m.role, accent: m.accent,
             status: m.status, repair: m.repair };
  });

  window.renderMechBay = function (canvases, texBase) {
    if (!window.THREE) { console.warn("renderMechBay: THREE not loaded"); return; }
    var THREE = window.THREE;
    var mgr = new THREE.LoadingManager();
    var loader = new THREE.TextureLoader(mgr);
    function pixTex(url) {
      var t = loader.load(url);
      t.magFilter = THREE.NearestFilter; t.minFilter = THREE.NearestFilter;
      t.generateMipmaps = false; t.wrapS = t.wrapT = THREE.RepeatWrapping;
      return t;
    }
    var prepared = SQUAD.map(function (m) {
      return { cfg: m, texArmor: pixTex(texBase + m.armorTex), texDetail: pixTex(texBase + m.detailTex) };
    });

    function glowTexture(hex) {
      var rgb = [(hex >> 16) & 255, (hex >> 8) & 255, hex & 255];
      var s = 64, cv = document.createElement("canvas"); cv.width = cv.height = s;
      var g = cv.getContext("2d");
      var grd = g.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
      var lr = Math.min(255, rgb[0] + 90), lg = Math.min(255, rgb[1] + 90), lb = Math.min(255, rgb[2] + 90);
      grd.addColorStop(0, "rgba(" + lr + "," + lg + "," + lb + ",0.95)");
      grd.addColorStop(0.35, "rgba(" + rgb[0] + "," + rgb[1] + "," + rgb[2] + ",0.55)");
      grd.addColorStop(1, "rgba(" + rgb[0] + "," + rgb[1] + "," + rgb[2] + ",0)");
      g.fillStyle = grd; g.fillRect(0, 0, s, s);
      return new THREE.CanvasTexture(cv);
    }
    function blobShadow(w, d) {
      var s = 64, cv = document.createElement("canvas"); cv.width = cv.height = s;
      var c = cv.getContext("2d");
      var grd = c.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
      grd.addColorStop(0, "rgba(0,0,0,0.55)");
      grd.addColorStop(0.7, "rgba(0,0,0,0.28)");
      grd.addColorStop(1, "rgba(0,0,0,0)");
      c.fillStyle = grd; c.fillRect(0, 0, s, s);
      var tex = new THREE.CanvasTexture(cv);
      var mesh = new THREE.Mesh(new THREE.PlaneGeometry(w, d),
        new THREE.MeshBasicMaterial({ map: tex, transparent: true, depthWrite: false }));
      mesh.rotation.x = -Math.PI / 2; mesh.position.set(0, 0.012, 0.06);
      return mesh;
    }

    function buildSceneFor(p) {
      var cfg = p.cfg;
      var scene = new THREE.Scene();
      var key = new THREE.DirectionalLight(0xfff4e6, cfg.keyI != null ? cfg.keyI : 1.05);
      key.position.set(-4, 6, 5); scene.add(key);
      scene.add(new THREE.AmbientLight(cfg.ambColor || 0x39435f, cfg.ambI != null ? cfg.ambI : 0.62));
      var rim = new THREE.DirectionalLight(0x2a4a7a, cfg.rimI != null ? cfg.rimI : 0.5);
      rim.position.set(4, 2, -5); scene.add(rim);
      scene.add(blobShadow(cfg.klass === "HEAVY" ? 3.1 : 2.3, cfg.klass === "HEAVY" ? 2.1 : 1.6));

      var g = new THREE.Group();
      var armorMat = p.texArmor, detailMat = p.texDetail;
      var mount = new THREE.MeshLambertMaterial({ color: 0x2b2b34 });
      var socket = new THREE.MeshLambertMaterial({ color: 0x14141a });
      var emis = new THREE.MeshBasicMaterial({ color: cfg.emissive != null ? cfg.emissive : 0x000000 });
      var TEX_REF = cfg.texRef || 1.16;
      function texMat(baseTex, w, h) {
        var t = baseTex.clone(); t.needsUpdate = true;
        t.wrapS = t.wrapT = THREE.RepeatWrapping;
        t.magFilter = THREE.NearestFilter; t.minFilter = THREE.NearestFilter; t.generateMipmaps = false;
        t.repeat.set(Math.max(0.14, w / TEX_REF), Math.max(0.14, h / TEX_REF));
        t.offset.set(Math.random() * 0.7, Math.random() * 0.7);
        return new THREE.MeshLambertMaterial({ map: t });
      }
      function resolve(mat, w, h) {
        if (mat === armorMat) return texMat(p.texArmor, w, h);
        if (mat === detailMat) return texMat(p.texDetail, w, h);
        return mat;
      }
      function box(sx, sy, sz, px, py, pz, mat, rx, ry, rz) {
        var m = new THREE.Mesh(new THREE.BoxGeometry(sx, sy, sz), resolve(mat, Math.max(sx, sz), sy));
        m.position.set(px, py, pz);
        if (rx) m.rotation.x = rx; if (ry) m.rotation.y = ry; if (rz) m.rotation.z = rz;
        g.add(m); return m;
      }
      function between(a, b, thick, depth, mat) {
        var dy = b[1] - a[1], dz = b[2] - a[2], len = Math.hypot(dy, dz);
        var m = new THREE.Mesh(new THREE.BoxGeometry(thick, len + 0.05, depth), resolve(mat, Math.max(thick, depth), len + 0.05));
        m.position.set((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2);
        m.rotation.x = Math.atan2(dz, dy); g.add(m); return m;
      }
      var glowTex = cfg.emissive != null ? glowTexture(cfg.emissive) : null;
      function glow(x, y, z, scale) {
        if (!glowTex) return;
        var sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTex, blending: THREE.AdditiveBlending, transparent: true, depthWrite: false, opacity: 0.9 }));
        sp.position.set(x, y, z); sp.scale.set(scale, scale, scale); g.add(sp);
      }
      cfg.build({ armor: armorMat, detail: detailMat, mount: mount, socket: socket, emis: emis, box: box, between: between, glow: glow });
      scene.add(g);
      return scene;
    }

    var renderer = new THREE.WebGLRenderer({ antialias: false, alpha: true, preserveDrawingBuffer: true });
    renderer.setClearColor(0x000000, 0);
    var FRUST = 4.7, CAM = [2.7, 2.05, 3.9], LOOK = [0, 1.18, 0];

    function renderAll() {
      prepared.forEach(function (p, i) {
        var canvas = canvases[i]; if (!canvas) return;
        if (!p._scene) p._scene = buildSceneFor(p);
        var w = canvas.width, h = canvas.height;
        renderer.setSize(w, h, false);
        var aspect = w / h;
        var cam = new THREE.OrthographicCamera(-FRUST * aspect / 2, FRUST * aspect / 2, FRUST / 2, -FRUST / 2, 0.1, 100);
        cam.position.set(CAM[0], CAM[1], CAM[2]); cam.lookAt(LOOK[0], LOOK[1], LOOK[2]);
        renderer.render(p._scene, cam);
        var ctx = canvas.getContext("2d");
        ctx.clearRect(0, 0, w, h);
        ctx.drawImage(renderer.domElement, 0, 0, w, h);
      });
    }
    mgr.onLoad = renderAll;
    renderer.domElement.addEventListener("webglcontextrestored", renderAll, false);
    renderer.domElement.addEventListener("webglcontextlost", function (e) { e.preventDefault(); }, false);
  };
})();
