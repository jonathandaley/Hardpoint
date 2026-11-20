
2026-11-19|T514|DONE|(this commit)|City plazas 1 cm over the pavement; render hung under Xvfb twice, skipped (geometry is unambiguous); queued T516-T520
2026-11-19|T517/T518|DONE|(these commits)|vertical flicks free for the charge (probe red->green); Kanchenjunga walk 1.035; batch with T514 for one suite
2026-11-19|T516|DONE|(this commit)|spectate: live mates only, TAB from a dead one, per-frame fallback; tab_spectate red->green
2026-11-19|T525|step 1|(this commit)|browser baseline: Forest 54-59, Badlands 46-49, Corvette 34-63, all-MG Corvette 20-30 fps in fights (draws 320 -> 650); bench script + weapons= perf flag
2026-11-19|T525|step 2|(this commit)|FxPool: effects + bullets + smoke in 2 MultiMeshes; fight draws 420-683 -> ~370; renders match old; CPU tick is now the limiter
2026-11-19|T525|step 2 suite|ca9ad2a|219/223: muzzle_tip / patience_beam / patience_hitscan looked for effect nodes -> FxPool.beams() / spheres() (read-only, with ids), same assertions, green; difficulty_steps = T510
2026-11-20|T503|ROOT CAUSE|(prev commit)|server range check dropped the 0.5 hit from a random short gun 20 m off; hit from B itself; 8/8
2026-11-20|T525|step 3|(this commit)|bots decide movement every 2nd tick: ai 1.45 -> 1.1 ms native; legs key (0.37 ms, not the lever)
2026-11-20|T525|step 4|(this commit)|fast web template +3-5% for +46% wasm: not adopted; mechs ~35 draws each = the remaining draw cost -> skinned mechs proposed
