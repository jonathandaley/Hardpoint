# AUTODEBUG_JOURNAL.md -- append-only run log (newest at bottom)

date|task|outcome|commit|finding|suite
2026-10-31|T138|DONE|81f7b0d|harness peers used the REAL user:// (shared settings, could write real profile.cfg); now isolated per process + per-slot settings overrides|6/6
2026-10-31|T139|DONE|ca12669|proxy works incl. 2-client scenarios; kernel UDP buffer drops ~5% of unpaced 400-pkt bursts (selftest sized under it, irrelevant at game rates)|6/6 direct + 6/6 via proxy
