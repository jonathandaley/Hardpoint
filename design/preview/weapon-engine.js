// ============================================================================
// Hardpoint — shared box-model render engine for WEAPON turnaround cards.
// Sibling to mech-engine.js: same flat-shaded / nearest-neighbor / ortho look,
// but framed horizontally for weapons and with a muzzle-HEAT emissive channel
// instead of a team glow.
//
// Local weapon space:  barrel runs along +Z (muzzle = +Z forward),
//                      +Y = up (sights on top, magazine below), +X = right.
//
// buildWeaponStage(cfg):
//   cfg = {
//     armorTex, detailTex : texture URLs (pixel tiles, nearest-neighbor)
//     texRef              : world units per full tile (default 0.55 — weapons
//                           are small, so texels stay chunky like the mech body)
//     heat                : hex int for muzzle-heat glow (default 0xff6a1a)
//     views: [{ id, pos:[x,y,z], frustH, lookY, shadow }]   // one per canvas
//     build(M)            : adds boxes; M is the build API below.
//     bright/keyI/ambI/rimI/ambColor : lighting overrides (as mech-engine)
//   }
//
// Build API M:
//   M.box(sx,sy,sz, px,py,pz, mat, rx,ry,rz)     -> textured/colored box
//   M.tube(a,b, w,h, mat)                         -> box spanning two 3D points
//   M.heat(x,y,z, scale)                          -> muzzle-heat halo + hot core
//   M.armor / M.detail / M.dark / M.mid           -> materials (metal)
//   M.mount / M.socket                            -> neutral hardpoint materials
//   M.emisMat(hex)                                -> flat emissive material (energy)
//   M.g                                           -> the THREE.Group
// ============================================================================
(function () {
  function hexToRgb(h) { return [(h >> 16) & 255, (h >> 8) & 255, h & 255]; }

  window.buildWeaponStage = function (cfg) {
    const NEUTRAL_MOUNT = 0x2b2b34, NEUTRAL_SOCKET = 0x14141a;
    const TEX_REF = cfg.texRef || 1.1;  // match mech world-texel size (mech-engine uses 1.16)
    const HEAT = cfg.heat != null ? cfg.heat : 0xff6a1a;
    const BR = cfg.bright != null ? cfg.bright : 1.34;

    const texManager = new THREE.LoadingManager();
    const texLoader = new THREE.TextureLoader(texManager);
    function pixTex(url) {
      const t = texLoader.load(url);
      t.magFilter = THREE.NearestFilter; t.minFilter = THREE.NearestFilter;
      t.generateMipmaps = false; t.wrapS = t.wrapT = THREE.RepeatWrapping;
      return t;
    }
    const texArmor = pixTex(cfg.armorTex);
    const texDetail = pixTex(cfg.detailTex);

    const matDark = new THREE.MeshLambertMaterial({ color: 0x17181d }); // bore / muzzle steel
    const matMid = new THREE.MeshLambertMaterial({ color: 0x2f333b });  // solid mid metal
    const matMount = new THREE.MeshLambertMaterial({ color: NEUTRAL_MOUNT });
    const matSocket = new THREE.MeshLambertMaterial({ color: NEUTRAL_SOCKET });

    // per-face material array so texels stay square on every face, matching
    // that face's ACTUAL world dimensions (BoxGeometry face order: +x,-x,+y,-y,+z,-z)
    function texMatBox(baseTex, sx, sy, sz) {
      const off = [Math.random() * 0.7, Math.random() * 0.7];
      const faceDims = [[sz, sy], [sz, sy], [sx, sz], [sx, sz], [sx, sy], [sx, sy]];
      return faceDims.map(function (d) {
        const t = baseTex.clone();
        t.needsUpdate = true;
        t.wrapS = t.wrapT = THREE.RepeatWrapping;
        t.magFilter = THREE.NearestFilter; t.minFilter = THREE.NearestFilter;
        t.generateMipmaps = false;
        t.repeat.set(Math.max(0.2, d[0] / TEX_REF), Math.max(0.2, d[1] / TEX_REF));
        t.offset.set(off[0], off[1]);
        return new THREE.MeshLambertMaterial({ map: t });
      });
    }

    function box(parent, sx, sy, sz, px, py, pz, mat, rx, ry, rz) {
      const material = (mat && mat.isTexture) ? texMatBox(mat, sx, sy, sz) : mat;
      const m = new THREE.Mesh(new THREE.BoxGeometry(sx, sy, sz), material);
      m.position.set(px, py, pz);
      if (rx) m.rotation.x = rx;
      if (ry) m.rotation.y = ry;
      if (rz) m.rotation.z = rz;
      parent.add(m);
      return m;
    }

    // box spanning two arbitrary 3D points (local +Y along the span)
    const UP = new THREE.Vector3(0, 1, 0);
    function tube(parent, a, b, w, h, mat) {
      const A = new THREE.Vector3(a[0], a[1], a[2]);
      const B = new THREE.Vector3(b[0], b[1], b[2]);
      const dir = B.clone().sub(A); const len = dir.length();
      const material = (mat && mat.isTexture) ? texMatBox(mat, w, len + 0.02, h) : mat;
      const m = new THREE.Mesh(new THREE.BoxGeometry(w, len + 0.02, h), material);
      m.position.copy(A).add(B).multiplyScalar(0.5);
      m.quaternion.setFromUnitVectors(UP, dir.normalize());
      parent.add(m);
      return m;
    }

    function radialTex(rgb, inner) {
      const s = 64, cv = document.createElement('canvas'); cv.width = cv.height = s;
      const g = cv.getContext('2d');
      const grd = g.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
      const lr = Math.min(255, rgb[0] + 110), lg = Math.min(255, rgb[1] + 80), lb = Math.min(255, rgb[2] + 60);
      grd.addColorStop(0, 'rgba(' + lr + ',' + lg + ',' + lb + ',0.98)');
      grd.addColorStop(inner || 0.3, 'rgba(' + rgb[0] + ',' + rgb[1] + ',' + rgb[2] + ',0.6)');
      grd.addColorStop(1, 'rgba(' + rgb[0] + ',' + rgb[1] + ',' + rgb[2] + ',0)');
      g.fillStyle = grd; g.fillRect(0, 0, s, s);
      return new THREE.CanvasTexture(cv);
    }
    const heatTex = radialTex(hexToRgb(HEAT), 0.3);
    const glowTexCache = {};
    function glowTex(hex) {
      if (!glowTexCache[hex]) glowTexCache[hex] = radialTex(hexToRgb(hex), 0.28);
      return glowTexCache[hex];
    }
    function coloredGlow(parent, hex, x, y, z, scale, coreFrac) {
      const cf = coreFrac != null ? coreFrac : 0.16;
      const core = new THREE.Mesh(
        new THREE.BoxGeometry(scale * cf, scale * cf, scale * cf),
        new THREE.MeshBasicMaterial({ color: hex })
      );
      core.position.set(x, y, z); parent.add(core);
      const sp = new THREE.Sprite(new THREE.SpriteMaterial({
        map: glowTex(hex), blending: THREE.AdditiveBlending,
        transparent: true, depthWrite: false, opacity: 0.95,
      }));
      sp.position.set(x, y, z);
      sp.scale.set(scale, scale, scale);
      parent.add(sp);
    }
    function heat(parent, x, y, z, scale) {
      // hot core box at the muzzle (reads even against additive-blend loss)
      const core = new THREE.Mesh(
        new THREE.BoxGeometry(scale * 0.18, scale * 0.18, scale * 0.06),
        new THREE.MeshBasicMaterial({ color: HEAT })
      );
      core.position.set(x, y, z); parent.add(core);
      const sp = new THREE.Sprite(new THREE.SpriteMaterial({
        map: heatTex, blending: THREE.AdditiveBlending,
        transparent: true, depthWrite: false, opacity: 0.95,
      }));
      sp.position.set(x, y, z + scale * 0.05);
      sp.scale.set(scale, scale, scale);
      parent.add(sp);
    }

    function blobShadow(w, d, z) {
      const s = 64, cv = document.createElement('canvas'); cv.width = cv.height = s;
      const c = cv.getContext('2d');
      const grd = c.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
      grd.addColorStop(0, 'rgba(0,0,0,0.5)');
      grd.addColorStop(0.7, 'rgba(0,0,0,0.24)');
      grd.addColorStop(1, 'rgba(0,0,0,0)');
      c.fillStyle = grd; c.fillRect(0, 0, s, s);
      const mesh = new THREE.Mesh(
        new THREE.PlaneGeometry(w, d),
        new THREE.MeshBasicMaterial({ map: new THREE.CanvasTexture(cv), transparent: true, depthWrite: false })
      );
      mesh.rotation.x = -Math.PI / 2;
      mesh.position.set(0, -0.44, z || 0);
      return mesh;
    }

    function buildScene() {
      const scene = new THREE.Scene();
      const key = new THREE.DirectionalLight(0xfff4e6, (cfg.keyI != null ? cfg.keyI : 1.05) * BR);
      key.position.set(-1.6, 5.2, 5.6); scene.add(key);
      scene.add(new THREE.AmbientLight(cfg.ambColor || 0x39435f, (cfg.ambI != null ? cfg.ambI : 0.6) * BR));
      const rim = new THREE.DirectionalLight(0x2a4a7a, (cfg.rimI != null ? cfg.rimI : 0.55) * BR);
      rim.position.set(4, 1.5, -5); scene.add(rim);
      scene.userData.key = key; scene.userData.rim = rim;
      scene.userData.keyBase = key.position.clone();
      scene.userData.rimBase = rim.position.clone();

      const g = new THREE.Group();
      const M = {
        g: g,
        armor: texArmor, detail: texDetail, dark: matDark, mid: matMid,
        mount: matMount, socket: matSocket,
        emisMat: function (hex) { return new THREE.MeshBasicMaterial({ color: hex }); },
        box: function (sx, sy, sz, px, py, pz, mat, rx, ry, rz) { return box(g, sx, sy, sz, px, py, pz, mat, rx, ry, rz); },
        tube: function (a, b, w, h, mat) { return tube(g, a, b, w, h, mat); },
        heat: function (x, y, z, scale) { return heat(g, x, y, z, scale); },
        glow: function (hex, x, y, z, scale, coreFrac) { return coloredGlow(g, hex, x, y, z, scale, coreFrac); },
      };
      cfg.build(M);
      scene.add(g);
      scene.userData.group = g;
      return scene;
    }

    function init() {
      // ---- single shared WebGL renderer across ALL weapon stages ----
      const renderer = getSharedRenderer();
      const views = cfg.views || [];
      let scene = null;

      function renderAll() {
        if (!scene) return;
        const az0 = views.length ? Math.atan2(views[0].pos[0], views[0].pos[2]) : 0;
        views.forEach(function (v) {
          const canvas = document.getElementById(v.id);
          if (!canvas) return;
          // add/remove the per-view ground shadow
          const g = scene.userData.group;
          if (scene.userData.shadow) { scene.remove(scene.userData.shadow); scene.userData.shadow = null; }
          if (v.shadow) { const sh = blobShadow(v.shadow.w || 2.2, v.shadow.d || 0.9, v.shadow.z || 0); scene.add(sh); scene.userData.shadow = sh; }

          const d = Math.atan2(v.pos[0], v.pos[2]) - az0;
          const cs = Math.cos(d), sn = Math.sin(d);
          const kb = scene.userData.keyBase, rb = scene.userData.rimBase;
          scene.userData.key.position.set(kb.x * cs + kb.z * sn, kb.y, -kb.x * sn + kb.z * cs);
          scene.userData.rim.position.set(rb.x * cs + rb.z * sn, rb.y, -rb.x * sn + rb.z * cs);

          const w = canvas.width, h = canvas.height;
          renderer.setSize(w, h, false);
          const aspect = w / h, fh = v.frustH || 1.5;
          const cam = new THREE.OrthographicCamera(-fh * aspect / 2, fh * aspect / 2, fh / 2, -fh / 2, 0.1, 100);
          cam.position.set(v.pos[0], v.pos[1], v.pos[2]);
          cam.lookAt(0, v.lookY || 0, 0);
          renderer.render(scene, cam);
          const ctx = canvas.getContext('2d');
          ctx.clearRect(0, 0, w, h);
          ctx.drawImage(renderer.domElement, 0, 0, w, h);
        });
      }

      function start() { if (!scene) scene = buildScene(); renderAll(); }
      texManager.onLoad = start;
      if (texArmor.image && texArmor.image.complete && texDetail.image && texDetail.image.complete) start();
    }

    if (window.THREE) init(); else window.addEventListener('load', init);
  };

  // one WebGLRenderer for the whole page — each stage renders into it and
  // blits to its 2D canvases, so N weapons never exhaust the GL context budget.
  let _sharedRenderer = null;
  function getSharedRenderer() {
    if (_sharedRenderer) return _sharedRenderer;
    _sharedRenderer = new THREE.WebGLRenderer({ antialias: false, alpha: true, preserveDrawingBuffer: true });
    _sharedRenderer.setClearColor(0x000000, 0);
    _sharedRenderer.domElement.addEventListener('webglcontextlost', function (e) { e.preventDefault(); }, false);
    return _sharedRenderer;
  }
})();
