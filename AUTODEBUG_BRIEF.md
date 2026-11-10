# AUTODEBUG_BRIEF.md -- what each /loop iteration does

Start the loop with: `/loop Follow AUTODEBUG_BRIEF.md` (no interval = self-paced).
Plan of record: `docs/MP_AUTODEBUG_PLAN.md` §9. Queue: SPEC.md §T.

## One iteration = one task

0. **Sync.** `git pull --rebase --autostash` (picks up the user's phone edits to
   HUMAN_FOUND_ISSUES.md, tracked since 2026-11-05); new items there get queued as §T rows
   (quote the user). If the user has UNCOMMITTED local edits to their files, never autostash
   (it rewrote the file under their editor once): fetch, `git rev-list --count HEAD..FETCH_HEAD`,
   plain push if 0, else hold; leave their file alone until they commit it or ask you to.
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
4. **Verify.** `python3 tools/run_suite.py` all green (~15 min: ~33 scenarios + ~120 gd_probes,
   probes 6-wide since T292). Sim or RNG code touched → also `python3 tools/selftest.py`. Netcode touched
   (RPCs, snapshots, sync, transitions) → also `python3 tools/run_suite.py --net wifi,bad --no-probes`
   (~15 min, must stay green). Long-run / perf / leak work → `python3 tools/run_suite.py --soak --only
   soak_match` (~15 min).
5. **Ship.** Flip the row to `x`, commit `T<n>: <goal>` (+ attribution lines),
   `git pull --rebase --autostash` then push to main (see memory `git-push-from-claude`;
   the user edits HUMAN_FOUND_ISSUES.md on GitHub, so main can move under us). Only
   pull between suite runs: an autostash empties the working tree for a moment. One commit per task;
   instrumentation commits never mixed with fix commits.
6. **Journal.** Append to `AUTODEBUG_JOURNAL.md`: date, task, outcome
   (DONE / BLOCKED / REVERTED), commit hash, one-line finding, suite result.
7. **Next.** Suites, sweeps and evals run with `run_in_background`; their exit notification wakes
   the loop, so `ScheduleWakeup` is only a 1200-1800 s fallback. End every turn with a short status
   (what changed, what's next) -- the user reads it on their phone.

**Easy-task batches** (user 2026-11-05: "do several things that are easy all at once, and then run
the suite ... for anything tricky, it's better to be careful"). Up to 4 EASY rows from the next ~8
in the queue may share one suite run: small visual / UI / text / map / tuning changes with an
obvious fix. Never batched: netcode (anything that needs the --net sweep), bugs with an unknown
cause, sim/RNG, multi-system features. Each task in a batch still gets its own red-before-green
probe run, then is committed LOCALLY (its own SPEC/journal lines) before the next starts -- so
tasks may share a file. Then one suite run over the stack; green -> push the commits together;
red -> bisect the local commits (git stash / checkout), fix or drop the culprit (journal), rerun.

## Working practice (run 7, 2026-11-08/09 -- the user: "that has been working really well")

- **While a suite / sweep / bot_eval runs:** never edit game or probe files (they're loaded) and
  never start a second CPU-heavy job (Xvfb renders, bot_eval) -- it flakes MP timing. Instead
  investigate read-only and draft the next task as a patch script in the scratchpad
  (`rep(path, old, new)` with exact-count asserts), applied the moment the run ends.
- **Red before green for fixes too.** Write the probe first. Prove it red against the unfixed code
  in a throwaway worktree: `git worktree add -q --detach <scratch>/wt_red HEAD`, copy in the new
  probe files and `.godot`, run it there, `git worktree remove --force`. For a netcode fix, disable
  it in place from a saved copy, run the scenario, restore (check the restore).
- **Flakes:** one red test in a suite -> rerun it alone 6-12x (3-4 in parallel) for a rate before
  theorizing; put the state you need into its failure message; test the theory (e.g. tally the
  suspected cause over old-probe runs); revert a "fix" that doesn't move the rate.
- **Probe rules learned the hard way:** stop a bot with an inert `InputSource` added as a child of
  the probe -- never process-disable a mech (it leaves physics, and an AI node's stale move keeps it
  walking: B126, B133); unshield any mech you shoot (B134); don't assume fixed bot squads (T350 /
  T365 randomize them) -- set squads via `Game.setup_sp_match()` + roster edits when it matters;
  quit cleanly (stop audio, wait out awaits such as the death pod ride: B124); isolate duels on a
  deck at y 400, 300 m apart; stay inside the suite's 6000-frame cap (~30-40 s of game time).
- **Look at visual work.** Render with `xvfb-run` (tools/art/*.gd), Read the PNG, fix what's off,
  and commit the review image to `docs/review/T<n>/` so the user can see it on GitHub.
- **Defaults, not blocks.** A number or taste call the user didn't give: pick a sensible default,
  build it, and add a NEEDS_HUMAN line ("tune if wanted"). Questions never go in HUMAN_FOUND.
- **HUMAN_FOUND hygiene** (user 2026-11-09): remove an item in the same commit that fixes it;
  an item needing their input moves to NEEDS_HUMAN with the question; a design kept for later
  moves to MAYBE_ADD.md. They re-add anything that recurs.
- **The user writes mid-loop:** answer, queue it as a §T row with their words, do it next.
- **Queue empty:** journal it, update the memory status note, push, PushNotification, stop.

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
- **Usage advisory** (`~/.claude/hooks/usage_guard.py`, PostToolUse) adds a USAGE
  ADVISORY note past 90% 5h / 95% 7d; it never blocks (user 2026-11-05: running out
  midway is annoying, not critical). On the note: finish the current task if it's
  close, else commit WIP with "WIP T<n>: stopped at <step>" and push; don't start a
  big task. If the limit itself stops the session, the next run resumes from git.

## Notify the user (PushNotification) when

A task is BLOCKED; a milestone closes (T139, T148, T157); a stop condition fires;
the queue empties. Otherwise stay quiet -- the journal is the status page.

## Environment

Godot `~/bin/godot` (4.6.2); fresh clone needs `godot --headless --editor --quit`
for the class cache. Xvfb installed (`xvfb-run`) for T156. Runs land in
`build/suite_runs/` (gitignored). Read oracle verdicts and `first_tick` /
`pattern` before raw logs; grep logs, don't cat them.
