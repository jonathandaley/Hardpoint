// Hardpoint UI Kit — Hangar (REPAIR BAY).
// A lit, lived-in repair bay: the 5-mech squad ranked in gantry-lit bays,
// welder drones throwing sparks over the ones under repair, umbilical cables,
// floor light pools. The authentic chassis are rendered by mech-bay.js
// (Vesuvius the wide dreadnought, Slip the light sprinter — really different).
// The terse loadout/skill picker lives separately in MechPicker.jsx.

/* eslint-disable */

// ---- a welding drone: hovers, points a torch at the hull, throws sparks ----
function WelderBot({ left, top, scale = 1, delay = 0, flip = false, accent = "#ffd27a" }) {
  const sparks = [0, 1, 2, 3].map((k) => (
    <span
      key={k}
      style={{
        position: "absolute",
        left: (flip ? 30 : 2) + (k % 2 ? 2 : -2),
        top: 19,
        width: 2,
        height: 2,
        background: k % 2 ? "#fff3c4" : accent,
        boxShadow: "0 0 4px " + accent,
        animation: `mbSpark 0.7s ${delay + k * 0.13}s ease-out infinite`,
      }}
    />
  ));
  return (
    <div
      style={{
        position: "absolute",
        left,
        top,
        width: 34 * scale,
        height: 26 * scale,
        transform: "translate(-50%,-50%)",
        animation: `mbBob ${2.8 + delay}s ${delay}s ease-in-out infinite`,
        zIndex: 6,
      }}
    >
      <svg viewBox="0 0 34 26" width={34 * scale} height={26 * scale} style={{ overflow: "visible", display: "block", transform: flip ? "scaleX(-1)" : "none" }}>
        {/* lift housing */}
        <rect x="9" y="2" width="12" height="3" fill="#15171c" stroke="#000" strokeWidth="0.5" />
        <rect x="6" y="4" width="3" height="1.4" fill="#3a3d44" />
        <rect x="21" y="4" width="3" height="1.4" fill="#3a3d44" />
        {/* body */}
        <rect x="7" y="6" width="17" height="10" fill="#2a2d34" stroke="#000" strokeWidth="1" />
        <rect x="7" y="6" width="17" height="2.5" fill="#3a3e46" />
        <circle cx="19.5" cy="11" r="2" fill="#1ad9ff" style={{ filter: "drop-shadow(0 0 2px #1ad9ff)" }} />
        {/* torch arm reaching down to the hull */}
        <line x1="9" y1="14" x2="2" y2="22" stroke="#3a3d44" strokeWidth="2" strokeLinecap="round" />
        <line x1="9" y1="14" x2="2" y2="22" stroke="#15171c" strokeWidth="0.6" strokeLinecap="round" />
        {/* weld arc */}
        <circle cx="2" cy="22" r="2.4" fill={accent} style={{ animation: `mbWeld 0.16s ${delay}s steps(2) infinite` }} />
        <circle cx="2" cy="22" r="4.5" fill="none" stroke={accent} strokeWidth="0.5" opacity="0.5" style={{ animation: `mbWeld 0.16s ${delay}s steps(2) infinite` }} />
      </svg>
      {sparks}
    </div>
  );
}

// ---- one bay: gantry downlight, mech canvas, welders, cables, status plate --
function BaySlot({ mech, index, canvasRef }) {
  const repairing = mech.status === "REPAIRING";
  const accent = mech.accent;
  return (
    <div
      style={{
        position: "relative",
        flex: 1,
        minWidth: 0,
        display: "flex",
        flexDirection: "column",
        background: "transparent",
        overflow: "hidden",
      }}
    >

      {/* gantry downlight cone */}
      <div
        style={{
          position: "absolute",
          top: 0,
          left: "50%",
          width: "78%",
          height: "82%",
          transform: "translateX(-50%)",
          background: `linear-gradient(to bottom, ${repairing ? "rgba(255,236,200,0.16)" : "rgba(180,210,255,0.10)"} 0%, transparent 72%)`,
          clipPath: "polygon(34% 0, 66% 0, 100% 100%, 0% 100%)",
          mixBlendMode: "screen",
          animation: repairing ? "mbFlicker 4s ease-in-out infinite" : "none",
          pointerEvents: "none",
        }}
      />

      {/* floor light pool */}
      <div
        style={{
          position: "absolute",
          bottom: 76,
          left: "50%",
          width: "80%",
          height: 60,
          transform: "translateX(-50%)",
          background: `radial-gradient(ellipse at center, ${accent}22 0%, transparent 70%)`,
          filter: "blur(2px)",
          animation: repairing ? "mbPulse 2.6s ease-in-out infinite" : "none",
          pointerEvents: "none",
        }}
      />

      {/* the mech */}
      <div style={{ position: "relative", flex: 1, display: "flex", alignItems: "flex-end", justifyContent: "center", zIndex: 3, minHeight: 0 }}>
        <canvas
          ref={canvasRef}
          width={300}
          height={430}
          style={{ width: "100%", height: "100%", objectFit: "contain", imageRendering: "pixelated", display: "block" }}
        />
        {/* welders only on the mechs under repair */}
        {repairing && (
          <>
            <WelderBot left="38%" top="52%" delay={index * 0.4} accent={accent} />
            <WelderBot left="64%" top="68%" delay={index * 0.4 + 0.6} flip accent={accent} scale={0.9} />
          </>
        )}
      </div>

      {/* status plate */}
      <div style={{ position: "relative", zIndex: 5, padding: "10px 12px 12px", borderTop: "1px solid #1b1d24", background: "linear-gradient(to bottom, rgba(10,11,16,0), rgba(8,9,13,0.9) 40%)" }}>
        <div style={{ display: "flex", alignItems: "baseline", gap: 8 }}>
          <span style={{ fontFamily: "var(--font-mono)", fontSize: 12, color: "var(--fg-3)", letterSpacing: "0.1em" }}>
            {String(index + 1).padStart(2, "0")}
          </span>
          <span style={{ fontFamily: "var(--font-display)", fontSize: 22, letterSpacing: "0.04em", color: "var(--fg-1)" }}>{mech.name}</span>
          <span style={{ width: 7, height: 7, borderRadius: "50%", background: accent, boxShadow: "0 0 6px " + accent, marginLeft: 2 }} />
        </div>
        <div style={{ fontFamily: "var(--font-ui)", fontSize: 10, letterSpacing: "0.16em", textTransform: "uppercase", color: "var(--fg-3)", marginTop: 3 }}>
          {mech.klass} · {mech.role}
        </div>
      </div>
    </div>
  );
}

// ---- background assembly lines: mixed mech + weapon parts on conveyors -----
function AssemblyPart({ kind }) {
  const A = "#3a3e46", D = "#2a2d34", O = "#0a0b10", E = "#5a6472";
  const p = { fill: A, stroke: O, strokeWidth: 0.7 };
  const d = { fill: D, stroke: O, strokeWidth: 0.7 };
  switch (kind) {
    case "torso": return (
      <svg width="30" height="24" viewBox="0 0 30 24" style={{ display: "block" }}>
        <rect x="3" y="4" width="24" height="17" {...p} /><rect x="3" y="4" width="24" height="4" {...d} />
        <rect x="11" y="0" width="8" height="5" {...d} /><line x1="7" y1="12" x2="23" y2="12" stroke={E} strokeWidth="0.8" />
      </svg>
    );
    case "leg": return (
      <svg width="20" height="26" viewBox="0 0 20 26" style={{ display: "block" }}>
        <rect x="6" y="0" width="9" height="9" {...p} /><rect x="7" y="9" width="7" height="9" {...d} />
        <rect x="4" y="18" width="13" height="5" {...p} /><rect x="2" y="22" width="16" height="3" {...d} />
      </svg>
    );
    case "arm": return (
      <svg width="28" height="16" viewBox="0 0 28 16" style={{ display: "block" }}>
        <rect x="0" y="4" width="10" height="9" {...p} /><rect x="10" y="6" width="10" height="5" {...d} />
        <rect x="20" y="3" width="7" height="10" {...p} /><circle cx="23.5" cy="8" r="1.6" fill={E} />
      </svg>
    );
    case "head": return (
      <svg width="16" height="14" viewBox="0 0 16 14" style={{ display: "block" }}>
        <rect x="2" y="2" width="12" height="9" {...p} /><rect x="4" y="5" width="8" height="2" fill="#1ad9ff" opacity="0.7" />
        <rect x="6" y="0" width="4" height="3" {...d} />
      </svg>
    );
    case "barrel": return (
      <svg width="40" height="12" viewBox="0 0 40 12" style={{ display: "block" }}>
        <rect x="0" y="3" width="10" height="7" {...p} /><rect x="10" y="4" width="26" height="4" {...d} />
        <rect x="35" y="2" width="4" height="8" {...p} /><rect x="3" y="4" width="4" height="1.5" fill={E} />
      </svg>
    );
    case "pod": return (
      <svg width="22" height="20" viewBox="0 0 22 20" style={{ display: "block" }}>
        <rect x="2" y="2" width="18" height="16" {...p} />
        {[0,1,2].map(r=>[0,1].map(c=>(<rect key={r+"-"+c} x={6+c*8} y={5+r*4} width="4" height="2.5" fill={O} />)))}
      </svg>
    );
    case "drum": return (
      <svg width="20" height="22" viewBox="0 0 20 22" style={{ display: "block" }}>
        <rect x="4" y="17" width="12" height="4" {...d} /><circle cx="10" cy="9" r="8" {...p} />
        <circle cx="10" cy="9" r="3.5" fill={D} /><circle cx="10" cy="9" r="1" fill="#f7c948" opacity="0.7" />
      </svg>
    );
    default: return null;
  }
}

function AssemblerArm({ left, delay = 0 }) {
  return (
    <div style={{ position: "absolute", left, top: -2, width: 18, height: 42, transform: "translateX(-50%)" }}>
      <div style={{ position: "absolute", left: 6, top: 0, width: 6, height: 6, background: "#14161d", border: "1px solid #000" }} />
      <div className="mb-anim" style={{ position: "absolute", left: 9, top: 5, width: 2, height: 0, transformOrigin: "top center", animation: `mbArm 2.4s ${delay}s ease-in-out infinite` }}>
        <div style={{ position: "absolute", left: -1, top: 0, width: 2, height: 20, background: "#20232b" }} />
        <div style={{ position: "absolute", left: -1.5, top: 19, width: 3, height: 3, borderRadius: "50%", background: "#2a2e37" }} />
        <div style={{ position: "absolute", left: -1, top: 22, width: 2, height: 12, background: "#171922", transform: "rotate(18deg)", transformOrigin: "top" }} />
      </div>
    </div>
  );
}

function AssemblyLine({ top, dir = 1, speed = 26, parts }) {
  return (
    <div className="mb-anim" style={{ position: "absolute", left: "-6%", right: "-6%", top, height: 40, opacity: 0.5, filter: "blur(0.5px) saturate(0.6)", pointerEvents: "none" }}>
      {/* belt frame */}
      <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: 9, background: "linear-gradient(180deg,#20232b,#0c0e13)", borderTop: "1px solid #2a2e37", boxShadow: "0 2px 5px rgba(0,0,0,0.7)" }}>
        <div className="mb-anim" style={{ position: "absolute", inset: 0, background: "repeating-linear-gradient(90deg,#151821 0 8px,#0e1016 8px 16px)", animation: `mbTread 1.3s linear infinite ${dir < 0 ? "reverse" : ""}` }} />
      </div>
      {/* moving parts */}
      <div className="mb-anim" style={{ position: "absolute", left: 0, bottom: 8, display: "flex", gap: 40, alignItems: "flex-end", width: "max-content", animation: `mbBelt ${speed}s linear infinite ${dir < 0 ? "reverse" : ""}` }}>
        {[...parts, ...parts].map((k, i) => <AssemblyPart key={i} kind={k} />)}
      </div>
      {/* overhead assembler arms */}
      {[16, 42, 68, 92].map((x, i) => <AssemblerArm key={i} left={x + "%"} delay={i * 0.35} />)}
    </div>
  );
}

// ---- feeder chute: assembly-belt output dropping parts into the station -----
function FeederChute() {
  const parts = ["torso", "barrel", "leg", "pod", "head", "drum"];
  return (
    <div style={{ position: "absolute", left: "0%", top: "13%", width: "3.6%", height: "66%", zIndex: 2, pointerEvents: "none", opacity: 0.85 }}>
      {/* hopper mouth catching from the belts */}
      <div style={{ position: "absolute", top: 0, left: "-40%", right: "-40%", height: 15, background: "linear-gradient(180deg,#20232b,#0c0e13)", border: "1px solid #2a2e37", clipPath: "polygon(0 0,100% 0,66% 100%,34% 100%)" }} />
      {/* side rails */}
      <div style={{ position: "absolute", top: 13, bottom: 15, left: "18%", width: 2, background: "#171922" }} />
      <div style={{ position: "absolute", top: 13, bottom: 15, right: "18%", width: 2, background: "#171922" }} />
      {/* moving tread surface */}
      <div className="mb-anim" style={{ position: "absolute", top: 13, bottom: 15, left: "24%", right: "24%", background: "repeating-linear-gradient(180deg,#151821 0 8px,#0e1016 8px 16px)", animation: "mbTreadV 1.3s linear infinite" }} />
      {/* descending parts */}
      <div style={{ position: "absolute", top: 13, bottom: 15, left: 0, right: 0, overflow: "hidden" }}>
        <div className="mb-anim" style={{ position: "absolute", top: 0, left: 0, right: 0, display: "flex", flexDirection: "column", alignItems: "center", gap: 26, animation: "mbFeed 15s linear infinite" }}>
          {[...parts, ...parts].map((k, i) => (<div key={i} style={{ transform: "scale(0.5)" }}><AssemblyPart kind={k} /></div>))}
        </div>
      </div>
      {/* outlet into the station */}
      <div style={{ position: "absolute", bottom: 0, left: "12%", right: "12%", height: 15, background: "linear-gradient(180deg,#1a1d24,#0c0e13)", border: "1px solid #2a2e37", borderTop: "none" }} />
    </div>
  );
}

// ---- observation deck: cantilevered glass box, high on the left wall --------
function ObservationDeck() {
  return (
    <div style={{ position: "absolute", left: 0, top: "5%", width: 214, height: 150, zIndex: 4, pointerEvents: "none", transform: "scale(0.62)", transformOrigin: "top left" }}>
      {/* diagonal support struts down to the wall */}
      <div style={{ position: "absolute", left: 10, top: 96, width: 158, height: 3, background: "#14161d", transform: "rotate(15deg)", transformOrigin: "left center" }} />
      <div style={{ position: "absolute", left: 10, top: 74, width: 122, height: 3, background: "#0f1117", transform: "rotate(25deg)", transformOrigin: "left center" }} />
      {/* the box */}
      <div style={{ position: "absolute", left: 0, top: 0, width: 202, height: 94, background: "linear-gradient(180deg,#12141b,#0b0d12)", border: "2px solid #1c1f28", borderLeft: "none", boxShadow: "0 12px 22px rgba(0,0,0,0.6)" }}>
        {/* ceiling light strip */}
        <div style={{ position: "absolute", left: 22, right: 22, top: 3, height: 3, background: "#f7c948", opacity: 0.5, filter: "blur(1px)" }} />
        {/* railing + balusters */}
        <div style={{ position: "absolute", left: 0, right: 0, top: 9, height: 2, background: "#2a2e37" }} />
        <div style={{ position: "absolute", left: 6, right: 6, top: 11, height: 11, background: "repeating-linear-gradient(90deg,#252932 0 1.5px,transparent 1.5px 13px)" }} />
        {/* glass with warm interior glow */}
        <div style={{ position: "absolute", left: 8, top: 28, right: 10, bottom: 18, background: "linear-gradient(180deg, rgba(247,201,72,0.17), rgba(247,201,72,0.05))", boxShadow: "inset 0 0 18px rgba(247,201,72,0.14)" }} />
        <div style={{ position: "absolute", left: 8, top: 28, right: 10, bottom: 18, background: "repeating-linear-gradient(108deg, rgba(180,210,255,0.06) 0 2px, transparent 2px 28px)" }} />
        {/* two operator silhouettes */}
        <div style={{ position: "absolute", left: 46, bottom: 20, width: 13, height: 32, background: "#05060a", borderRadius: "6px 6px 0 0" }} />
        <div style={{ position: "absolute", left: 118, bottom: 20, width: 15, height: 30, background: "#04050a", borderRadius: "7px 7px 0 0" }} />
        {/* label */}
        <div style={{ position: "absolute", left: 10, bottom: 4, fontFamily: "var(--font-mono)", fontSize: 9, letterSpacing: "0.2em", color: "#6c6c76" }}>OBS DECK · 09</div>
      </div>
      {/* corner beacon */}
      <div className="mb-anim" style={{ position: "absolute", right: 4, top: 1, width: 5, height: 5, borderRadius: "50%", background: "#ff6a3d", boxShadow: "0 0 8px #ff6a3d", animation: "mbObsLight 2.2s ease-in-out infinite" }} />
    </div>
  );
}

// ---- a single flying repair drone body -------------------------------------
function DroneSvg() {
  return (
    <svg viewBox="0 0 40 34" width="40" height="34" style={{ display: "block", overflow: "visible" }}>
      <rect x="6" y="3" width="28" height="2.5" fill="#15171c" stroke="#000" strokeWidth="0.5" />
      <rect x="2" y="5" width="4" height="1.6" fill="#3a3d44" />
      <rect x="34" y="5" width="4" height="1.6" fill="#3a3d44" />
      <rect x="9" y="7" width="22" height="12" fill="#2a2d34" stroke="#000" strokeWidth="1" />
      <rect x="9" y="7" width="22" height="3" fill="#3a3e46" />
      <circle cx="25" cy="13" r="2.1" fill="#1ad9ff" style={{ filter: "drop-shadow(0 0 2px #1ad9ff)" }} />
      {/* grip arms + torch reaching down to the carried part */}
      <line x1="15" y1="19" x2="13" y2="27" stroke="#3a3d44" strokeWidth="2" strokeLinecap="round" />
      <line x1="25" y1="19" x2="27" y2="27" stroke="#3a3d44" strokeWidth="2" strokeLinecap="round" />
      <line x1="20" y1="19" x2="20" y2="27" stroke="#20232b" strokeWidth="1.4" strokeLinecap="round" />
    </svg>
  );
}

// ---- the roaming drone swarm: imperative rAF flight, new mech target each trip
function RepairDroneSwarm() {
  const wraps = [useRef(null), useRef(null), useRef(null)];
  useEffect(() => {
    const docks = [{ x: 4, y: 28 }, { x: 4, y: 48 }, { x: 4, y: 68 }];
    const bayC = [15, 34, 53, 72, 91];
    const rnd = (a, b) => a + Math.random() * (b - a);
    const pickMech = () => { const i = Math.floor(Math.random() * 5); return { x: bayC[i] + rnd(-6, 6), y: rnd(46, 78) }; };
    const drones = wraps.map((r, i) => {
      const node = r.current; if (!node) return null;
      const home = docks[i];
      return {
        node, inner: node.querySelector(".dr-inner"), part: node.querySelector(".dr-part"), spark: node.querySelector(".dr-spark"),
        home, x: home.x, y: home.y, tx: home.x, ty: home.y, phase: "grab", timer: rnd(0.3, 1.4), dir: 1, seed: Math.random() * 10,
      };
    }).filter(Boolean);
    drones.forEach((d) => { d.node.style.left = d.x + "%"; d.node.style.top = d.y + "%"; });
    let raf, last = performance.now();
    const step = (now) => {
      const dt = Math.min(0.05, (now - last) / 1000); last = now;
      drones.forEach((d) => {
        const dx = d.tx - d.x, dy = d.ty - d.y, dist = Math.hypot(dx, dy);
        const stepDist = 17 * dt; // constant ~17% / second, even pace end-to-end
        if (dist > stepDist) { d.x += (dx / dist) * stepDist; d.y += (dy / dist) * stepDist; }
        else { d.x = d.tx; d.y = d.ty; }
        if (Math.abs(dx) > 0.3) d.dir = dx > 0 ? 1 : -1;
        const bob = Math.sin(now / 430 + d.seed) * 1.4;
        d.node.style.left = d.x + "%"; d.node.style.top = d.y + "%";
        d.inner.style.transform = `translateY(${bob}px) scaleX(${d.dir})`;
        if (d.phase === "toDock") { if (dist < 1.6) { d.phase = "grab"; d.timer = rnd(0.4, 0.9); } }
        else if (d.phase === "grab") { d.timer -= dt; if (d.timer <= 0) { d.part.style.opacity = "1"; const t = pickMech(); d.tx = t.x; d.ty = t.y; d.phase = "toMech"; } }
        else if (d.phase === "toMech") { if (dist < 1.9) { d.phase = "weld"; d.timer = rnd(0.9, 1.6); d.spark.style.opacity = "1"; } }
        else if (d.phase === "weld") { d.timer -= dt; if (d.timer <= 0) { d.part.style.opacity = "0"; d.spark.style.opacity = "0"; d.tx = d.home.x; d.ty = d.home.y; d.phase = "toDock"; } }
      });
      raf = requestAnimationFrame(step);
    };
    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
  }, []);
  return (
    <div style={{ position: "absolute", inset: 0, zIndex: 6, pointerEvents: "none" }}>
      {wraps.map((r, i) => (
        <div key={i} ref={r} style={{ position: "absolute", left: "50%", top: "50%", width: 0, height: 0 }}>
          <div className="dr-inner" style={{ position: "absolute", left: -20, top: -17, willChange: "transform" }}>
            <DroneSvg />
            <div className="dr-part" style={{ position: "absolute", left: 14, top: 27, width: 12, height: 11, opacity: 0, transition: "opacity 0.2s", background: "linear-gradient(180deg,#4a5566,#20242c)", border: "1px solid #0a0b10", boxShadow: "0 0 5px rgba(26,217,255,0.5)" }}>
              <div style={{ position: "absolute", left: 1, right: 1, top: 1, height: 1, background: "#6a7686" }} />
            </div>
            <div className="dr-spark" style={{ position: "absolute", left: 16, top: 30, opacity: 0, transition: "opacity 0.15s" }}>
              {[0, 1, 2, 3].map((s) => (
                <span key={s} className="mb-anim" style={{ position: "absolute", left: s % 2 ? 2 : -2, top: 0, width: 2, height: 2, background: s % 2 ? "#fff3c4" : "#ffd27a", boxShadow: "0 0 4px #ffd27a", animation: `mbSpark 0.6s ${s * 0.11}s ease-out infinite` }} />
              ))}
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}

// ---- shared environmental backdrop: deep industrial repair hall ----------
function HangarBackdrop() {
  const beams = [6, 25, 44, 62, 81];
  const lights = [
    { left: "13%", c: "#f7c948", drop: 30 },
    { left: "34%", c: "#1ad9ff", drop: 46 },
    { left: "66%", c: "#f7c948", drop: 38 },
    { left: "87%", c: "#ff6a3d", drop: 52 },
  ];
  return (
    <div style={{ position: "absolute", inset: 0, zIndex: 0, overflow: "hidden", pointerEvents: "none" }}>
      {/* base gradient */}
      <div style={{ position: "absolute", inset: 0, background: "linear-gradient(180deg,#0b0d15 0%,#0c0e17 42%,#08090f 78%,#060710 100%)" }} />
      {/* corrugated back-wall panels (upper) */}
      <div style={{ position: "absolute", left: 0, right: 0, top: 0, height: "72%", background: "repeating-linear-gradient(180deg, rgba(255,255,255,0.022) 0 1px, transparent 1px 30px), repeating-linear-gradient(90deg, transparent 0 118px, rgba(0,0,0,0.45) 118px 121px)", maskImage: "linear-gradient(180deg,#000 0%,#000 58%,transparent 100%)", WebkitMaskImage: "linear-gradient(180deg,#000 0%,#000 58%,transparent 100%)" }} />
      {/* background assembly lines (behind vents + beams for depth) */}
      <AssemblyLine top="7.5%" dir={1} speed={30} parts={["torso", "barrel", "leg", "pod", "head", "drum", "arm", "torso", "barrel"]} />
      <AssemblyLine top="16.5%" dir={-1} speed={24} parts={["drum", "leg", "pod", "arm", "barrel", "head", "torso", "pod", "leg"]} />
      {/* two large round wall vents */}
      {["23%", "77%"].map((l, i) => (
        <div key={i} style={{ position: "absolute", left: l, top: "22%", width: 128, height: 128, transform: "translate(-50%,-50%)", borderRadius: "50%", border: "3px solid #14161d", background: "radial-gradient(circle, #0d0f16 40%, #0a0b12 72%)", boxShadow: "inset 0 0 24px rgba(0,0,0,0.85)" }}>
          <div style={{ position: "absolute", inset: 11, borderRadius: "50%", background: "conic-gradient(from 0deg, #11131a, #0a0b11 25%, #11131a 50%, #0a0b11 75%, #11131a)" }} />
          <div style={{ position: "absolute", inset: "42%", borderRadius: "50%", background: "#1a1d25" }} />
        </div>
      ))}
      {/* horizontal conduit run high on the wall */}
      <div style={{ position: "absolute", left: 0, right: 0, top: "31%", height: 6, background: "linear-gradient(180deg,#171922,#0c0d13)", boxShadow: "0 2px 5px rgba(0,0,0,.6)" }} />
      <div style={{ position: "absolute", left: 0, right: 0, top: "35%", height: 3, background: "#101218" }} />
      {/* I-beam structural columns, aligned to the bay dividers */}
      {beams.map((x) => (
        <div key={x} style={{ position: "absolute", left: x + "%", top: 0, bottom: "14%", width: 14, transform: "translateX(-50%)", background: "linear-gradient(90deg,#090a10,#15171f 50%,#090a10)", borderLeft: "1px solid #1c1f28", borderRight: "1px solid #050608" }}>
          {[12, 30, 50, 70, 88].map((p) => (
            <span key={p} style={{ position: "absolute", left: "50%", top: p + "%", width: 3, height: 3, borderRadius: "50%", background: "#23262f", transform: "translate(-50%,-50%)" }} />
          ))}
        </div>
      ))}
      {/* caged work lights on straight chains */}
      {lights.map((g, i) => (
        <div key={i} style={{ position: "absolute", left: g.left, top: 0, transform: "translateX(-50%)", textAlign: "center" }}>
          <div style={{ width: 1, height: g.drop, background: "#1a1c24", margin: "0 auto" }} />
          <div style={{ width: 9, height: 9, borderRadius: "50%", background: g.c, boxShadow: `0 0 10px 3px ${g.c}, 0 0 28px 7px ${g.c}55`, margin: "0 auto" }} />
        </div>
      ))}
      {/* floor band + warm central haze for depth */}
      <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: "24%", background: "linear-gradient(180deg, transparent, rgba(22,19,14,0.35) 42%, rgba(8,8,12,0.72))" }} />
      <div style={{ position: "absolute", left: "50%", bottom: "5%", width: "72%", height: "24%", transform: "translateX(-50%)", background: "radial-gradient(ellipse at 50% 100%, rgba(247,201,72,0.10), transparent 70%)", filter: "blur(7px)" }} />
      {/* vignette */}
      <div style={{ position: "absolute", inset: 0, boxShadow: "inset 0 0 170px 46px rgba(0,0,0,0.72)" }} />
    </div>
  );
}

function Hangar({ onPlay, onSettings }) {
  const squad = window.MECH_BAY_SQUAD || [];
  const refs = useRef(squad.map(() => React.createRef()));

  useEffect(() => {
    if (window.renderMechBay) {
      window.renderMechBay(refs.current.map((r) => r.current), "../../assets/textures/");
    }
  }, []);

  const repairing = squad.filter((m) => m.status === "REPAIRING").length;

  return (
    <div data-screen-label="Hangar" style={{ width: "100%", height: "100%", background: "#07080c", color: "var(--fg-1)", display: "flex", flexDirection: "column", position: "relative", overflow: "hidden" }}>
      {/* keyframes for the bay */}
      <style>{`
        @keyframes mbBob { 0%,100%{ transform: translate(-50%,-50%) translateY(0); } 50%{ transform: translate(-50%,-50%) translateY(-5px); } }
        @keyframes mbSpark { 0%{ opacity:1; transform: translate(0,0) scale(1); } 100%{ opacity:0; transform: translate(-6px, 16px) scale(0.4); } }
        @keyframes mbWeld { 0%{ opacity:0.35; } 100%{ opacity:1; } }
        @keyframes mbFlicker { 0%,100%{ opacity:1; } 47%{ opacity:0.82; } 50%{ opacity:0.6; } 53%{ opacity:0.9; } }
        @keyframes mbPulse { 0%,100%{ opacity:0.7; } 50%{ opacity:1; } }
        @keyframes mbBelt { from{ transform: translateX(0); } to{ transform: translateX(-50%); } }
        @keyframes mbTread { from{ background-position: 0 0; } to{ background-position: 16px 0; } }
        @keyframes mbArm { 0%,100%{ transform: rotate(-7deg); } 50%{ transform: rotate(9deg); } }
        @keyframes mbObsLight { 0%,100%{ opacity:0.35; } 50%{ opacity:1; } }
        @keyframes mbDock { 0%,100%{ opacity:0.3; } 50%{ opacity:1; } }
        @keyframes mbTreadV { from{ background-position: 0 0; } to{ background-position: 0 16px; } }
        @keyframes mbFeed { from{ transform: translateY(-50%); } to{ transform: translateY(0); } }
      `}</style>

      {/* top bar */}
      <div style={{ padding: "12px 18px", display: "flex", alignItems: "center", gap: 14, borderBottom: "2px solid var(--rule)", background: "#0a0b10", zIndex: 10 }}>
        <img src="../../assets/logo-mark.svg" width={28} height={28} style={{ imageRendering: "pixelated" }} alt="" />
        <div style={{ fontFamily: "var(--font-display)", fontSize: 22, letterSpacing: "0.06em" }}>HANGAR</div>
        <div style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--fg-3)", letterSpacing: "0.18em", marginLeft: 2 }}>REPAIR BAY</div>
        <div style={{ flex: 1 }} />
        <Chip tone="elo">ELO 1842</Chip>
        <Chip tone="caution">COINS 8,420</Chip>
        <Chip>WINS 47 · LOSSES 31</Chip>
        <div style={{ fontFamily: "var(--font-ui)", fontWeight: 600, fontSize: 16, letterSpacing: "0.1em" }}>
          PILOT · <span style={{ color: "var(--neon-cyan)" }}>VESPER-09</span>
        </div>
      </div>

      {/* sub-header */}
      <div style={{ padding: "8px 18px", display: "flex", alignItems: "center", gap: 12, borderBottom: "1px solid var(--rule)", background: "#090a0e", zIndex: 10 }}>
        <Micro>SQUAD · 5 LIVES</Micro>
        <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--hp-full)", letterSpacing: "0.12em" }}>● ALL OPERATIONAL</span>
        <div style={{ flex: 1 }} />
        <Micro>NEXT QUEUE · <span style={{ color: "var(--fg-1)" }}>MATH TEMPLE</span> · BEACON DRAIN</Micro>
      </div>

      {/* the bay: gantry beam + 5 slots */}
      <div style={{ flex: 1, position: "relative", minHeight: 0 }}>
        <HangarBackdrop />
        {/* left repair-station column: floor pad, hazard trim, boundary rule */}
        <div style={{ position: "absolute", left: 0, top: 26, bottom: 0, width: "6%", zIndex: 2, pointerEvents: "none" }}>
          <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: 90, background: "linear-gradient(180deg, transparent, rgba(247,201,72,0.07))" }} />
          <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: 5, background: "repeating-linear-gradient(135deg,#f7c948 0 10px,#1a1410 10px 20px)", opacity: 0.4 }} />
          <div style={{ position: "absolute", right: 0, top: 0, bottom: 0, width: 2, background: "linear-gradient(180deg, transparent, #1c1f28 18%, #1c1f28 82%, transparent)" }} />
        </div>
        <ObservationDeck />
        <FeederChute />
        <RepairDroneSwarm />
        {/* gantry beam across the top */}
        <div style={{ position: "absolute", top: 0, left: 0, right: 0, height: 26, background: "linear-gradient(to bottom, #14151b, #0d0e13)", borderBottom: "2px solid #000", display: "flex", alignItems: "center", zIndex: 7, boxShadow: "0 4px 16px rgba(0,0,0,0.6)" }}>
          <div style={{ position: "absolute", inset: 0, background: "repeating-linear-gradient(90deg, transparent 0 60px, rgba(0,0,0,0.5) 60px 62px)" }} />
          <div style={{ position: "absolute", left: 14, top: 9, bottom: 9, width: 60, background: "repeating-linear-gradient(135deg,#f7c948 0 8px,#1a1410 8px 16px)", opacity: 0.7 }} />
          <div style={{ position: "absolute", right: 14, top: 9, bottom: 9, width: 60, background: "repeating-linear-gradient(135deg,#f7c948 0 8px,#1a1410 8px 16px)", opacity: 0.7 }} />
        </div>

        {/* slots */}
        <div style={{ position: "absolute", top: 26, left: "6%", right: 0, bottom: 0, display: "flex", zIndex: 3 }}>
          {squad.map((m, i) => (
            <BaySlot key={m.name} mech={m} index={i} canvasRef={refs.current[i]} />
          ))}
        </div>

        {/* floor hazard line */}
        <div style={{ position: "absolute", bottom: 0, left: 0, right: 0, height: 5, background: "repeating-linear-gradient(135deg,#f7c948 0 14px,#1a1410 14px 28px)", opacity: 0.45, zIndex: 8 }} />
      </div>

      {/* bottom action bar */}
      <div style={{ padding: 18, borderTop: "2px solid var(--rule)", display: "flex", alignItems: "center", gap: 12, background: "#0a0b10", zIndex: 10 }}>
        <Micro>BAY POWER · <span style={{ color: "var(--hp-full)" }}>NOMINAL</span></Micro>
        <div style={{ flex: 1 }} />
        <MBButton variant="ghost" onClick={onSettings}>EDIT LOADOUT</MBButton>
        <MBButton variant="primary" onClick={onPlay} style={{ padding: "12px 32px" }}>FIND MATCH</MBButton>
      </div>
    </div>
  );
}

Object.assign(window, { Hangar, WelderBot, BaySlot, AssemblyLine, ObservationDeck, RepairDroneSwarm });
