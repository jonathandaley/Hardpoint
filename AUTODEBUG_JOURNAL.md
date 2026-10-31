# AUTODEBUG_JOURNAL.md -- append-only run log (newest at bottom)

date|task|outcome|commit|finding|suite
2026-10-31|T138|DONE|81f7b0d|harness peers used the REAL user:// (shared settings, could write real profile.cfg); now isolated per process + per-slot settings overrides|6/6
2026-10-31|T139|DONE|ca12669|proxy works incl. 2-client scenarios; kernel UDP buffer drops ~5% of unpaced 400-pkt bursts (selftest sized under it, irrelevant at game rates)|6/6 direct + 6/6 via proxy
2026-10-31|T140|DONE|f553a44|B-a REPRODUCED both ways: sens mismatch 56.7 deg, 5% loss 2.06-2.41 deg (3/3). New lead queued T158: client one-shot presses (R/1-4/Q) sampled only on send ticks, ~50% lost|8/8 + selftest GREEN
2026-10-31|T141|DONE|92ee4ea|B-a FIXED: aim sent absolute; residual 0.000000 rad on sens-mismatch, 5% loss, and bad net (was 56.7 / 2.4 deg). B38+V47|8/8 + selftest GREEN
2026-10-31|T158|DONE|e5f83a6,e87b1da|client lost ~50% of R/1-4/Q presses (sampled every 2nd tick); harness hid it (replay pulses latched). Fixed: cumulative press counts per packet; 16/16 on wifi+bad. B39, V47 extended|9/9 + selftest GREEN
2026-10-31|T142|DONE|2456913|B-b FIXED: real cause = client interp wiped mech body_scale (B40), beam 0.41->0.027 m; B-c = 42 deg lock-hold cone (tuning, same in SP) -> NEEDS_HUMAN.md|10/10 + selftest GREEN
2026-10-31|T143|DONE|e12f7a2,748a019|crash_scan allow-list + log_flood; found T159 (RPC before Arena under bad net) and B41 (my aim_desync broke V45; skew-tolerant series oracles)|10/10
2026-10-31|T144|DONE|2c501d3|B-f + B-g REPRODUCED: client stays connected after quit, 141x cached-node errors in 6.5 s; 4 dead-end scenes (static route check)|11/11
