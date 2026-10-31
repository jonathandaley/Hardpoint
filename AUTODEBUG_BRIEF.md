# AUTODEBUG_BRIEF.md -- what each /loop iteration does

Start the loop with: `/loop Follow AUTODEBUG_BRIEF.md` (no interval = self-paced).
Plan of record: `MP_AUTODEBUG_PLAN.md` §9. Queue: SPEC.md §T.

## One iteration = one task

1. **Pick.** First §T row in table order (rows may be inserted out of number
   order to reprioritize) with status `.` or `~`, T138 or later, that
   `AUTODEBUG_JOURNAL.md` does not list as BLOCKED. None left → journal "queue
   empty", PushNotification, `ScheduleWakeup stop:true`. Done.
2. **Context.** Read the row, its cites (§V, earlier §T, §B), the last ~5 journal
   entries, and the code it names. Don't reread whole files you only need a slice of.
3. **Build** with the build skill (auto mode: no waiting for plan OK).
   - New oracle → **red before green**: it must FAIL on a known-bad input
     (synthetic log, archived run, or stashed fix) before its PASS counts (B36, B37).
   - Repro tasks (expected RED): the new scenario lands with the oracle marked
     expect_fail (strict xfail in sync_compare) so the suite stays green; the fix
     task removes the xfail.
   - Bug found → backprop skill (§B row, §V if it would catch recurrence).
4. **Verify.** `python3 tools/run_suite.py` all green (~3 min, 6 scenarios as of 2026-10-31). Sim or RNG
   code touched → also `python3 tools/selftest.py`.
5. **Ship.** Flip the row to `x`, commit `T<n>: <goal>` (+ attribution lines),
   push to main (see memory `git-push-from-claude`). One commit per task;
   instrumentation commits never mixed with fix commits.
6. **Journal.** Append to `AUTODEBUG_JOURNAL.md`: date, task, outcome
   (DONE / BLOCKED / REVERTED), commit hash, one-line finding, suite result.
7. **Next.** `ScheduleWakeup` 60s with the same prompt.

## Guardrails

- **3 strikes.** Three distinct failed approaches on one task → revert
  uncommitted work, journal BLOCKED with symptoms + what was tried, leave row `~`,
  PushNotification, move on. Never loop on one bug.
- **Change budget.** Touch only files the task needs. No refactors, no "while
  I'm here". Respect every §V and the §C GDScript landmines.
- **Revert rules.** Fix breaks determinism selftest → revert, BLOCK. >20% of
  suite red after a change → revert. Build won't load → revert to last green;
  still broken → journal, PushNotification, stop the loop.
- **Out of scope** (feel, smoothing, audio taste, anything needing human eyes the
  oracles can't give) → append to `NEEDS_HUMAN.md` (date, task, what to look
  at, file path, why), never block on it.
- **Never:** install packages, write outside the repo (except `~/.claude/`
  memory), force-push or rewrite history, use extra usage credits, start a
  second loop.
- **Usage guard** (`~/.claude/hooks/usage_guard.py`) blocks tools near the limit.
  When it fires: `git` commit WIP with "WIP T<n>: stopped at <step>", push, end
  the turn. Do not retry other tools. Next run resumes the `~` row.

## Notify the user (PushNotification) when

A task is BLOCKED; a milestone closes (T139, T148, T157); a stop condition fires;
the queue empties. Otherwise stay quiet -- the journal is the status page.

## Environment

Godot `~/bin/godot` (4.6.2); fresh clone needs `godot --headless --editor --quit`
for the class cache. Xvfb installed (`xvfb-run`) for T156. Runs land in
`build/suite_runs/` (gitignored). Read oracle verdicts and `first_tick` /
`pattern` before raw logs; grep logs, don't cat them.
