# AUTODEBUG_JOURNAL.md -- append-only run log (newest at bottom)

date|task|outcome|commit|finding|suite
2026-10-31|T138|DONE|81f7b0d|harness peers used the REAL user:// (shared settings, could write real profile.cfg); now isolated per process + per-slot settings overrides|6/6
2026-10-31|T139|DONE|ca12669|proxy works incl. 2-client scenarios; kernel UDP buffer drops ~5% of unpaced 400-pkt bursts (selftest sized under it, irrelevant at game rates)|6/6 direct + 6/6 via proxy
2026-10-31|T140|DONE|f553a44|B-a REPRODUCED both ways: sens mismatch 56.7 deg, 5% loss 2.06-2.41 deg (3/3). New lead queued T158: client one-shot presses (R/1-4/Q) sampled only on send ticks, ~50% lost|8/8 + selftest GREEN
2026-10-31|T141|DONE|92ee4ea|B-a FIXED: aim sent absolute; residual 0.000000 rad on sens-mismatch, 5% loss, and bad net (was 56.7 / 2.4 deg). B38+V47|8/8 + selftest GREEN
