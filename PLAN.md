# Zero Replication Fault Harness — PLAN

Contract document for all agent sessions. Read fully before writing code. Do not expand scope beyond this file without explicit instruction.

## Goal

Black-box randomized fault-injection harness for Zero's (rocicorp/mono) replication path: Postgres → replication manager → SQLite replica. Find safety bugs (replica divergence), liveness bugs (failure to converge), and efficiency bugs (unwarranted full resyncs). Produce reproducible, self-contained failure bundles suitable for a public write-up and for pasting into a coding agent for localization.

## Context / prior findings (do not re-derive)

- Zero has solid *deterministic* scenario coverage: `initial-sync.pg.test.ts`, `change-source.pg.test.ts`, `replication-resumption.pg.test.ts` (the one real fault test), and `chinook-zero-cache-fuzzer` (query/write parity vs PG — do NOT duplicate its query-equivalence oracle).
- The gap is the *interleaving space*: randomized crash/fault timing across lifecycle boundaries (initial sync, slot creation, backup restore, AutoReset, change-DB truncation), WAL-retention exhaustion, and DDL/TOAST under concurrent writes.
- Known skipped test: `change-source.toasted-values.pg.test.ts` (ordinary TOAST updates) — checked separately, not part of this harness.
- Expected finding class skews toward efficiency (unwarranted AutoReset/resync) over corruption. That is still a valid finding.

## Non-goals (hard boundaries)

- No deterministic runtime / DST scheduler. Determinism only via seeded inputs + recorded fault timeline. Add fake clocks/transport ONLY if a failing seed proves irreproducible (>1 in ~5 replays fail to reproduce).
- No formal verification, no coverage-guided fuzzing, no view-syncer/ZQL testing, no Zero client in v1.
- No modifications to the Zero codebase. Harness drives zero-cache purely through its public config/CLI surface. Own repo.
- No UI, no framework, minimal deps. TypeScript + Node, plain scripts.

## Architecture

- `docker-compose.yml`: Postgres 16 (`wal_level=logical`, `max_slot_wal_keep_size` configurable via env), nothing else. zero-cache runs as a **child process** of the runner (not a container) so we can SIGKILL with precise timing and read stdout directly. `ZERO_LOG_FORMAT=json`, `ZERO_LOG_LEVEL=debug`, `ZERO_ENABLE_TELEMETRY=false`, `ZERO_REPLICA_FILE` inside the run dir.
- `runner.ts`: executes one seed end-to-end. All randomness from a single seeded PRNG. Phases: reset env → start zero-cache → start workload → inject faults per schedule → stop workload → wait for quiescence → run oracles → write verdict.
- `workload.ts`: seeded transaction generator against PG. v1 tables: a few simple typed tables incl. one with a large TEXT column (TOAST-sized values), FK pair, and compound PK. Ops: insert/update/delete, multi-statement transactions, occasional aborted transactions, occasional burst mode (for WAL pressure).
- `faults.ts`: seeded fault schedule. v1 fault types:
  1. `kill-zerocache` — SIGKILL at seeded delay, including *during initial sync*; restart after seeded pause.
  2. `wal-exhaust` — kill zero-cache, run write burst exceeding `max_slot_wal_keep_size`, restart. (Weekend two.)
  3. `pg-restart` — `docker restart` Postgres mid-stream. (Weekend two.)
  - Deferred: DDL churn, ALTER PUBLICATION, connection-level drops.
- `oracles.ts`:
  1. **State equivalence (safety):** after quiescence, dump replicated tables from PG and from the SQLite replica, normalize types, diff. Must be identical.
  2. **LSN monotonicity (safety):** sample `pg_replication_slots.confirmed_flush_lsn` throughout; must never regress.
  3. **Convergence (liveness):** oracle 1 must pass within TIMEOUT (default 60s) after workload stop.
  4. **No unwarranted resync (efficiency):** scan JSON logs for resync markers (list below). A resync is *warranted* only if the fault schedule contains a cause that legitimately invalidates the slot/replica (e.g. wal-exhaust). Kill/restart alone does NOT warrant a resync — flag it.
- `sweep.ts`: run N seeds sequentially, keep run dirs only on failure (plus every 50th success as baseline), emit summary table (seed, verdict, markers seen, lag stats).

## Resync log markers (grep set for oracle 4)

`resetting replica ` · `shutting down for auto-reset` · `reset required by replication stream` · `error restoring backup. resyncing the replica:` · `resyncing` · `replication slot .* is missing` · `replication slot .* has been invalidated for exceeding the max_slot_wal_keep_size` · `No replication slot for replica at version` · `error starting replication stream` · `Data in cdc tables @.* is incompatible` · `Synced .* rows of .* tables .* up to` (full initial sync completed — flag if boot count > 1)

## Run directory layout (one per seed, keyed `runs/<seed>/`)

- `meta.json` — seed, config, git SHAs (harness + zero version), verdict, oracle results
- `faults.jsonl` — every injected fault with monotonic timestamp
- `zerocache.log` — full JSON stdout/stderr
- `postgres.log`
- `lsn.jsonl` — sampled slot state (`confirmed_flush_lsn`, `wal_status`, retained bytes) every 500ms
- `diff.txt` — oracle 1 output on failure
- `replica.db` — SQLite replica retained on failure

A failure bundle must be self-contained: someone (or an agent) with only this directory + PLAN.md can understand what happened.

## Milestones

- **M0 (done):** repo recon (`zero-recon.md`).
- **M1 (in progress):** single seed, `kill-zerocache` only, all four oracles, run dir written. Green end-to-end on a no-fault seed AND a kill seed. ← everything is interactive/supervised until here. First step done: Nix/direnv dev shell for harness tooling.
- **M2:** `sweep.ts`, 500-seed overnight run, summary report. First calibration: how often does kill-during-initial-sync trigger resync?
- **M3:** `wal-exhaust` + `pg-restart` fault types; second sweep.
- **M4:** regression encoding — recreate known replication issues from Zero's tracker/Discord as fixed seeds; verify harness detects them.
- **M5:** write-up draft: method, findings (incl. "nothing found after N seeds" if so), testability notes on Zero, harness repo public.

## Session rules for agents

- Consult this file at session start; update the Milestones section status at session end.
- Prefer boring code. No cleverness in the runner; cleverness budget goes to generators and oracles.
- Any environment friction (compose, PG config, zero-cache env) — surface it and ask, don't burn >15 min guessing.
- Never delete `runs/` failure dirs.
- If an oracle fires, STOP the sweep design work; reproduce the seed 5x, record reproduction rate in `meta.json`, then report.
