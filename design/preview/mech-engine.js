// ============================================================================
// Hardpoint — shared box-model render engine for mech turnaround cards.
// Box-only (rectangular prisms, Minecraft-style). No cylinders/cones.
// Renders ONE scene into three static 2D canvases (¾ / front / side) so the
// panels survive WebGL context loss. Each mech page calls buildMechStage(cfg).
//
// cfg = {
//   armorTex, detailTex : texture URLs (pixel tiles, nearest-neighbor)
//   emissive            : hex int for the glow channel, or null for no glow
//   texRef              : world units mapped to one full tile (default 1.16)
//   lookY               : camera target height (default 1.08)
//   frustH              : ortho frustum height (default 3.30)
//   iso/front/side      : optional camera overrides {pos:[x,y,z], frustH}
//   build(M)            : adds boxes to the mech; M is the build API below.
// }
//
// Build API M:
//   M.box(sx,sy,sz, px,py,pz, mat, rx,ry,rz)  -> textured/colored box
//   M.between(a,b, thick, depth, mat)         -> box spanning two joints (y-z)
//   M.glow(x,y,z, scale)                      -> emissive halo sprite
//   M.armor / M.detail / M.mount / M.socket / M.emis  -> materials
//   M.g                                       -> the THREE.Group (rarely needed)
// ============================================================================
(function () {
  function hexToRgb(h) {
    return [(h >> 16) & 255, (h >> 8) & 255, h & 255];
  }

  window.buildMechStage = function (cfg) {
    const NEUTRAL_MOUNT = 0x2b2b34;
    const NEUTRAL_SOCKET = 0x14141a;
    const TEX_REF = cfg.texRef || 1.16;
    const LOOK_Y = cfg.lookY != null ? cfg.lookY : 1.08;
    const FRUST = cfg.frustH || 3.30;
    const emissiveHex = cfg.emissive != null ? cfg.emissive : 0x1ad9ff;
    // global brightness multiplier — scales every light so overridden mechs lift too
    const BR = cfg.bright != null ? cfg.bright : 1.32;

    const texManager = new THREE.LoadingManager();
    const texLoader = new THREE.TextureLoader(texManager);
    function pixTex(url) {
      const t = texLoader.load(url);
      t.magFilter = THREE.NearestFilter;
      t.minFilter = THREE.NearestFilter;
      t.generateMipmaps = false;
      t.wrapS = t.wrapT = THREE.RepeatWrapping;
      return t;
    }
    const texArmor = pixTex(cfg.armorTex);
    const texDetail = pixTex(cfg.detailTex);

    // material whose texels are a CONSTANT world size, referenced to the torso,
    // so small parts show fewer/bigger pixels that match the body.
    function texMat(baseTex, w, h) {
      const t = baseTex.clone();
      t.needsUpdate = true;
      t.wrapS = t.wrapT = THREE.RepeatWrapping;
      t.magFilter = THREE.NearestFilter;
      t.minFilter = THREE.NearestFilter;
      t.generateMipmaps = false;
      t.repeat.set(Math.max(0.14, w / TEX_REF), Math.max(0.14, h / TEX_REF));
      t.offset.set(Math.random() * 0.7, Math.random() * 0.7);
      return new THREE.MeshLambertMaterial({ map: t });
    }

    const matArmor = texArmor;
    const matDetail = texDetail;
    const matMount = new THREE.MeshLambertMaterial({ color: NEUTRAL_MOUNT });
    const matSocket = new THREE.MeshLambertMaterial({ color: NEUTRAL_SOCKET });
    const matEmis = new THREE.MeshBasicMaterial({ color: emissiveHex });

    function box(parent, sx, sy, sz, px, py, pz, mat, rx, ry, rz) {
      const material = (mat && mat.isTexture) ? texMat(mat, Math.max(sx, sz), sy) : mat;
      const m = new THREE.Mesh(new THREE.BoxGeometry(sx, sy, sz), material);
      m.position.set(px, py, pz);
      if (rx) m.rotation.x = rx;
      if (ry) m.rotation.y = ry;
      if (rz) m.rotation.z = rz;
      parent.add(m);
      return m;
    }

    // box spanning two joint points in the y-z plane (local +y along the bone)
    function between(parent, a, b, thick, depth, mat) {
      const dy = b[1] - a[1], dz = b[2] - a[2];
      const len = Math.hypot(dy, dz);
      const material = (mat && mat.isTexture) ? texMat(mat, Math.max(thick, depth), len + 0.05) : mat;
      const m = new THREE.Mesh(new THREE.BoxGeometry(thick, len + 0.05, depth), material);
      m.position.set((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2);
      m.rotation.x = Math.atan2(dz, dy);
      parent.add(m);
      return m;
    }

    function glowTexture(rgb) {
      const s = 64, cv = document.createElement('canvas');
      cv.width = cv.height = s;
      const g = cv.getContext('2d');
      const grd = g.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
      const lr = Math.min(255, rgb[0] + 90), lg = Math.min(255, rgb[1] + 90), lb = Math.min(255, rgb[2] + 90);
      grd.addColorStop(0, 'rgba(' + lr + ',' + lg + ',' + lb + ',0.95)');
      grd.addColorStop(0.35, 'rgba(' + rgb[0] + ',' + rgb[1] + ',' + rgb[2] + ',0.55)');
      grd.addColorStop(1, 'rgba(' + rgb[0] + ',' + rgb[1] + ',' + rgb[2] + ',0)');
      g.fillStyle = grd; g.fillRect(0, 0, s, s);
      return new THREE.CanvasTexture(cv);
    }
    const glowTex = glowTexture(hexToRgb(emissiveHex));
    function glow(parent, x, y, z, scale) {
      const sp = new THREE.Sprite(new THREE.SpriteMaterial({
        map: glowTex, blending: THREE.AdditiveBlending,
        transparent: true, depthWrite: false, opacity: 0.9,
      }));
      sp.position.set(x, y, z);
      sp.scale.set(scale, scale, scale);
      parent.add(sp);
    }

    function blobShadow() {
      const s = 64, cv = document.createElement('canvas');
      cv.width = cv.height = s;
      const c = cv.getContext('2d');
      const grd = c.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
      grd.addColorStop(0, 'rgba(0,0,0,0.55)');
      grd.addColorStop(0.7, 'rgba(0,0,0,0.28)');
      grd.addColorStop(1, 'rgba(0,0,0,0)');
      c.fillStyle = grd; c.fillRect(0, 0, s, s);
      const tex = new THREE.CanvasTexture(cv);
      const w = cfg.shadowW || 2.4, d = cfg.shadowD || 1.7;
      const mesh = new THREE.Mesh(
        new THREE.PlaneGeometry(w, d),
        new THREE.MeshBasicMaterial({ map: tex, transparent: true, depthWrite: false })
      );
      mesh.rotation.x = -Math.PI / 2;
      mesh.position.set(0, 0.012, cfg.shadowZ != null ? cfg.shadowZ : 0.04);
      return mesh;
    }

    function buildScene() {
      const scene = new THREE.Scene();
      const key = new THREE.DirectionalLight(0xfff4e6, (cfg.keyI != null ? cfg.keyI : 1.05) * BR);
      key.position.set(-1.5, 6, 6.2);
      scene.add(key);
      scene.add(new THREE.AmbientLight(cfg.ambColor || 0x39435f, (cfg.ambI != null ? cfg.ambI : 0.62) * BR));
      const rim = new THREE.DirectionalLight(0x2a4a7a, (cfg.rimI != null ? cfg.rimI : 0.5) * BR);
      rim.position.set(4, 2, -5);
      scene.add(rim);
      // store light refs + their ¾-baseline positions so renderAll can rotate the
      // rig to follow each camera (constant relative lighting = turntable look).
      scene.userData.key = key;
      scene.userData.rim = rim;
      scene.userData.keyBase = key.position.clone();
      scene.userData.rimBase = rim.position.clone();
      scene.add(blobShadow());

      const g = new THREE.Group();
      const M = {
        g: g,
        armor: matArmor, detail: matDetail, mount: matMount, socket: matSocket, emis: matEmis,
        box: function (sx, sy, sz, px, py, pz, mat, rx, ry, rz) {
          return box(g, sx, sy, sz, px, py, pz, mat, rx, ry, rz);
        },
        between: function (a, b, thick, depth, mat) {
          return between(g, a, b, thick, depth, mat);
        },
        glow: function (x, y, z, scale) { return glow(g, x, y, z, scale); },
      };
      cfg.build(M);
      scene.add(g);
      return scene;
    }

    function whitenTex(tex, alpha) {
      const img = tex.image;
      if (!img || !img.width) return;
      const cv = document.createElement('canvas');
      cv.width = img.width; cv.height = img.height;
      const c = cv.getContext('2d');
      c.drawImage(img, 0, 0);
      c.globalAlpha = alpha;            // overlay white -> lightens toward white, keeps pixel noise
      c.fillStyle = '#ffffff';
      c.fillRect(0, 0, img.width, img.height);
      tex.image = cv;
      tex.needsUpdate = true;
    }

    function init() {
      const renderer = new THREE.WebGLRenderer({
        antialias: false, alpha: true, preserveDrawingBuffer: true
      });
      renderer.setClearColor(0x000000, 0);

      const views = [
        { id: 'v-iso', pos: (cfg.iso && cfg.iso.pos) || [3.0, 1.95, 3.4], frustH: (cfg.iso && cfg.iso.frustH) || FRUST },
        { id: 'v-front', pos: (cfg.front && cfg.front.pos) || [0.0, 1.30, 6.0], frustH: (cfg.front && cfg.front.frustH) || FRUST },
        { id: 'v-side', pos: (cfg.side && cfg.side.pos) || [6.0, 1.30, 0.0], frustH: (cfg.side && cfg.side.frustH) || FRUST },
        { id: 'v-back', pos: (cfg.back && cfg.back.pos) || [0.0, 1.30, -6.0], frustH: (cfg.back && cfg.back.frustH) || FRUST },
      ];

      let scene = null;
      function renderAll() {
        if (!scene) return;
        // azimuth of the ¾ hero camera; every other view rotates the light rig by
        // its azimuth delta so the key always reads from the same upper-left.
        const azIso = Math.atan2(views[0].pos[0], views[0].pos[2]);
        views.forEach(function (v) {
          const canvas = document.getElementById(v.id);
          if (!canvas) return;
          const d = Math.atan2(v.pos[0], v.pos[2]) - azIso;
          const cs = Math.cos(d), sn = Math.sin(d);
          const kb = scene.userData.keyBase, rb = scene.userData.rimBase;
          scene.userData.key.position.set(kb.x * cs + kb.z * sn, kb.y, -kb.x * sn + kb.z * cs);
          scene.userData.rim.position.set(rb.x * cs + rb.z * sn, rb.y, -rb.x * sn + rb.z * cs);
          const w = canvas.width, h = canvas.height;
          renderer.setSize(w, h, false);
          const aspect = w / h;
          const cam = new THREE.OrthographicCamera(
            -v.frustH * aspect / 2, v.frustH * aspect / 2,
            v.frustH / 2, -v.frustH / 2, 0.1, 100
          );
          cam.position.set(v.pos[0], v.pos[1], v.pos[2]);
          cam.lookAt(0, LOOK_Y, 0);
          renderer.render(scene, cam);
          const ctx = canvas.getContext('2d');
          ctx.clearRect(0, 0, w, h);
          ctx.drawImage(renderer.domElement, 0, 0, w, h);
        });
      }

      function start() {
        if (cfg.whitenArmor) whitenTex(texArmor, cfg.whitenArmor);
        if (cfg.whitenDetail) whitenTex(texDetail, cfg.whitenDetail);
        if (!scene) scene = buildScene();
        renderAll();
      }
      texManager.onLoad = start;
      if (texArmor.image && texArmor.image.complete &&
          texDetail.image && texDetail.image.complete) start();
      renderer.domElement.addEventListener('webglcontextlost', function (e) { e.preventDefault(); }, false);
      renderer.domElement.addEventListener('webglcontextrestored', renderAll, false);
    }

    if (window.THREE) init();
    else window.addEventListener('load', init);
  };
})();
