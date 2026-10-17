# Agent playtests

An agent playtest plays real rounds of the real game (the real `RunWorld`, the v83 map and mob data from the asset
cache, real bosses, job advancements and cards) with an autonomous player, and writes a report you can act on. Use
it to answer "did my change break or worsen how the game plays?". Design: spec #91 and
[ADR 0004](adr/0004-agent-playtests-over-stdio.md). Terms (agent playtest, playtest personality, tactic, decision
point, brain, replay) are defined in [`GLOSSARY.md`](../GLOSSARY.md).

`bash scripts/agent_playtest.sh --help` lists every flag; this guide covers what `--help` can't tell you.

## Quick start

```bash
ISOLATE=me bash scripts/agent_playtest.sh                 # the smoke scenario: 3 min of Henesys, seed 2026, sensible
```

- It needs the asset cache (`bash scripts/import.sh` once) and Node 24. The first run installs
  `tools/playtest/node_modules` (`npm ci`).
- Always set `ISOLATE=<name>` when another agent might run Godot. Each run then plays from a private project mirror
  under `_scratch/godot_runs/<name>/`; a matrix gives each parallel slot its own `<name>_j<slot>` mirror.
- The run directory is printed at the end and defaults to
  `evidence/agent-playtest/<scenario>_<stage>_<personality>_s<seed>_<time>/` (gitignored; `--out=<dir>` overrides).
  Open its `report.md`.
- The exit code is the verdict you can script on (see [Exit codes](#exit-codes)).

Common variants:

```bash
ISOLATE=me bash scripts/agent_playtest.sh --personality=aggressive --seed=7 --minutes=10
ISOLATE=me bash scripts/agent_playtest.sh --scenario=matrix           # 6 personalities x seeds 1, 2, 2026
ISOLATE=me bash scripts/agent_playtest.sh --replay=evidence/agent-playtest/<run dir>
ISOLATE=me bash scripts/agent_playtest.sh --replay=<run dir> --windowed --shots-at=304.2
```

Seeds: only training seeds (1..60 and 2026) are accepted; prefer 1, 2 and 2026 (AGENTS.md "Balance").

## Flags

Every flag is `--name=value` (booleans: `--name`, `--name=true|false`). A flag given on the command line overrides
the scenario's matching field; one left out takes the scenario's value, then the default.

| Flag | Default | What |
|---|---|---|
| `--scenario=<name>` | `smoke` | a scenario file in `tools/playtest/scenarios/` (see [Scenarios](#scenarios)) |
| `--stage=<key>` | `henesys_hg1` | stage key from `game/data/survivor/stages.json`; with `--tier` it is tier 1's stage |
| `--seed=<n>` | 2026 | the run seed (training seeds only); one seed replaces the scenario's list |
| `--minutes=<m>` | 3 | simulated time cap per round in minutes (0 = the stage's own cap); TIMEOUT at the cap |
| `--personality=<name>` | `sensible` | a file in `tools/playtest/personalities/`; one name replaces the scenario's list |
| `--brain=auto\|jev\|fallback\|builtin` | `auto` | who answers the decisions ([Brains](#brains)) |
| `--model=<id>` | `jev-latest` | the TypeSafe model for the Jev brain and the evaluations |
| `--jev-max-requests=<n>` | 400 | Jev requests per run, the brain's and the evaluations' together ([Cost and caps](#cost-and-caps)) |
| `--evaluations[=true\|false]` | on with `auto` / `jev`, off with `fallback` / `builtin` | the Jev-assisted evaluations after the round |
| `--strict-eval` | off | Jev-flagged evaluation results count toward exit code 1 |
| `--character=<path>` | none | start the round from this CharacterSnapshot JSON (one round; not with `--tier` >= 2); relative to the working directory |
| `--tier=<n>` | 1 | play a tier chain from tier 1 through tier n (only a CLEARED round feeds the next) |
| `--warp=<s>` | 0 | the first s run seconds are answered by the sensible baseline (decision source `warp`: BotInput's cards and jobs, tactic `kite`), then the brain decides. Every tick is still played; this is **not** `scripts/playtest.sh --warp`, which fast-forwards the presentation without drawing |
| `--stuck-px=<px>`, `--stuck-s=<s>` | 24, 20 | the stuck detector's box and window |
| `--inject-finding=<kind>` | none | test only: one fake finding of that kind at 0:10, to check the reporting path (exit 1) |
| `--liveness-s=<s>` | 60 | kill the game after this long without output (exit 2) |
| `--out=<dir>` | `evidence/agent-playtest/...` | the run directory (a matrix: its root) |
| `--jobs=<n>` | min(4, cores/2) | parallel Godot processes of a multi-cell scenario |
| `--replay=<run dir>` | none | replay a recorded run exactly ([Replay and screenshots](#replay-and-screenshots)) |
| `--windowed` | off | with `--replay`: in the real game window, with screenshots |
| `--shots-at=<s,s,...>` | none | with `--windowed`: run seconds to screenshot |
| `--speed=<k>` | 4 | with `--windowed`: sim ticks per 60 Hz frame (drawing speed only) |
| `--skip-to=<s>` | none | with `--windowed`: fast-forward to that run time before drawing (every tick still plays) |
| `--summarize=<matrix dir>` | none | rewrite a matrix's `summary.md` / `summary.json` from its cells, without playing |
| `--cluster-window-s=<s>`, `--cluster-share=<f>` | 90, 0.4 | matrix summary: a death cluster is a window of that many run seconds holding the deaths of at least that share of the cells |
| `--help` | | print every flag |

The report's live re-run command repeats every flag that changes decisions or output, so it plays the same run
again (a Jev run may still decide differently; the exact path is `--replay`).

## Brains

The **brain** answers each decision point: which card, which job branch, which tactic. Tick-by-tick movement stays
in deterministic game-side code (`tactic_controller.gd`) that carries out the current tactic.

| `--brain=` | Who decides | Network |
|---|---|---|
| `auto` (default) | Jev if a TypeSafe key resolves, else the fallback | yes, with a key |
| `jev` | Jev; exit 2 before Godot starts when no key resolves | yes |
| `fallback` | the personality's deterministic policy (seeded; identical runs for identical seeds) | no (evaluations off unless `--evaluations=true`) |
| `builtin` | the driver answers itself with the sensible baseline, no pipe (tactics always `kite`) | no (evaluations off unless `--evaluations=true`) |
| replay | `--replay=<dir>`: the recorded answers, in order | no |

- The report header always says which brain was requested and used, the Jev model (`jev-1.13.0` behind
  `jev-latest`), the run's Jev requests and tokens (`Jev total`), and **why** any fallback happened ("key absent in process env", "API error
  500", "Jev request cap (400) reached"). Never read a fallback run as a Jev run; check the header.
- A failed Jev request falls back for that decision only, with the reason recorded in `decisions.jsonl`. After a 401
  or 403, Jev is switched off for the rest of the run. Error texts are redacted: the key and anything shaped like a
  bearer token never reach a reason.
- **A Jev run is not reproducible live**: the same seed can take different cards and end differently. The
  reproducible path is `--replay`.
- Confidence: a Jev tactic answer below the personality's `min_confidence` (default 0.35) keeps the current tactic.
  For a personality with `emergency`, a "danger of dying" probability above 0.7 forces `defensive`. Card and job
  answers act on Jev's top choice and record the confidence.
- Jev never sees raw arithmetic: code turns facts into named buckets ("HP low", "crowd", "boss attacking") first,
  and options are shown in a seeded, recorded shuffle so Jev has no first-option bias.

### The TypeSafe key

- The key comes from `TYPESAFE_API_KEY` in the process environment. On Windows, when the shell did not inherit it
  (Git Bash often doesn't), the CLI reads the Windows **user** environment variable through `powershell.exe`.
- Set it in the environment only. It is never written to a run directory, a log or a commit, and it is removed from
  the environment of every Godot process the CLI starts (the import pass, the driver, the windowed replay).
- Hide the key for a keyless run: `TYPESAFE_API_KEY= AGENT_PLAYTEST_NO_USER_KEY=1 bash scripts/agent_playtest.sh`.
  `AGENT_PLAYTEST_NO_USER_KEY=1` turns off the Windows user-env lookup.
- **Fully offline** means no key resolves (as above), or `--brain=fallback` / `--brain=builtin`: without Jev deciding,
  the evaluations are off by default too, so those runs stay deterministic and offline. `--evaluations=true` turns
  them on (and then needs the key).

### Cost and caps

- A Jev decision is one request of about 1k input tokens (`$0.042/Mtok`). `sensible` makes about a dozen requests
  in 5 minutes (cards and jobs only); personalities that also decide tactics make 40-60; the evaluations add up to
  three; an 18-cell matrix made about 950. A round costs well under a cent.
- One cap and one total per run: `--jev-max-requests` (default 400) counts the brain's requests and the
  evaluations' together. Once it is reached, later decisions use the fallback and later evaluation requests fail
  (the header and `evaluations.json` `errors` say so). The header's `Jev total` line gives the combined requests
  and tokens with the brain / evaluations breakdown; `report.json` `jev` has the run's totals, `evaluations.json`
  the evaluations' share.
- A personality with a single allowed tactic (`sensible`) asks no tactic decisions at all, so it only pays for cards
  and jobs.

## Personalities

A **playtest personality** is a kind of player: it changes what the brain decides (the player text Jev reads, the
allowed tactics, the fallback card, job and tactic policies) and how the controller moves (reaction delay, mistake
bursts, potion thresholds). One JSON file each in `tools/playtest/personalities/`; the schema is the header of
`tools/playtest/src/maple/personality.ts`.

| Name | Plays like | Use it to find |
|---|---|---|
| `sensible` | today's `BotInput`: kite only, `BotInput.pick_card_for` and `pick_job`, no noise | the baseline; with `--brain=fallback` or `builtin` it plays the `balance.sh` bot round exactly |
| `inexperienced` | 15-tick reactions, a wrong-way or frozen burst every ~4 s, drinks HP late, random cards | whether a new player survives |
| `aggressive` | closes on mobs and duels bosses while HP holds, damage and count cards | damage-build and contact-damage balance |
| `defensive` | kites when calm, backs off in danger, drinks early, HP and defence cards | runs nobody careful can win |
| `exploratory` | walks, climbs and takes portals to the least-visited platforms | navigation bugs, unreachable spots |
| `completionist` | sweeps every drop, takes every new skill, ranks to max | unreachable drops, card pools that run dry |

`sensible` with `--brain=jev` is not BotInput play: Jev chooses its cards.

## Tactics

A **tactic** is the play style the controller carries out until the brain changes it: `kite` (exactly
`BotInput.decide`), `aggressive`, `defensive`, `explore`, `collect`, `hold`. The policy asks a tactic decision at the
round start, every `checkpoint_s` of run time (default 8 s), and on triggers: HP falls to low, a boss spawns, the
crowd near the player grows two buckets, a card window resolves. A switched tactic is held at least `hold_s`
(default 4 s) unless HP falls to critical. The report's Tactics section shows time shares, switches and a switch log.

## Scenarios

A scenario is a repeatable playtest in one name: `tools/playtest/scenarios/<name>.json`, schema in the header of
`tools/playtest/src/maple/scenario.ts`. A flag given on the command line overrides the matching field.

| Scenario | What |
|---|---|
| `smoke` (default) | one 3-minute Henesys round, sensible, seed 2026 |
| `henesys_full` | one personality through the Henesys finale, 30-minute cap |
| `matrix` | every shipped personality x seeds 1, 2, 2026 on Henesys, 10-minute cap, cells in parallel, one summary |
| `tier_chain` | a tier-1 round chained into tier 2 through the real character carry (only a CLEARED round feeds the next) |
| `fixture_dark_cave` | the committed Lv38 F/P fixture on Dark Cave |

A matrix runs `--jobs` cells at once (default min(4, cores/2)) and writes `summary.md` / `summary.json` beside the
cell directories: an outcomes table, problems de-duplicated by kind and location, **Patterns** (death clusters:
the 90 s window holding the deaths of at least 40% of the cells, with a representative cell to replay), Jev opinions
grouped by kind, metric spreads and decisions by source. `--summarize=<matrix dir>` rewrites the summary from
existing cells without playing.

## Reading a report

`report.md` starts with a **Verdict** line (outcome, problem counts, exit code) and a **Next** command. Then:

1. **Header**: scenario, stage, seed, personality, brain requested and used, fallback reason, Jev model, the brain's
   requests and tokens, `Jev total` (the run's requests against the cap and its one token total, split into brain
   and evaluations), evaluations.
2. **Outcome**: DEAD, CLEARED or TIMEOUT. TIMEOUT means the time cap ended a living round; it is never a clear.
3. **Problems**, in three tiers that mean different things:
   - **Deterministic failures**: invariant findings and `SCRIPT ERROR` / `ERROR:` lines in `game.log`. These are
     bugs. Each has run time, tick, a state snapshot (position, platform, HP/MP, tactic, nearest mobs) and re-run,
     replay and windowed replay commands.
   - **Jev-flagged**: an evaluation past its threshold with confidence >= 0.6. A judgment call with its probability,
     not a bug.
   - **Needs human review**: past the threshold with low confidence. Never a finding on its own.
4. **Metrics** (the same record `scripts/balance.sh` produces: milestones, a per-minute table, potions, boss fights,
   MP short), **Cards taken**, **Tactics**, **Personality**, **Evaluations** (every result, flagged or not),
   **Rounds** for a tier chain, **Screenshots** for a windowed replay, **Reproduce**.

The invariants (game side, every tick and at every decision): HP and MP inside 0..max; position finite and inside
the map bounds plus 64 px; level and EXP never decrease (except the EXP reset at a level-up); state transitions
follow the pause protocol (ARCHITECTURE 4.4.2); card offers follow the owner's rules (never empty, distinct, known,
the job-line rule, nothing at max rank, at most one Elixir); no new `world.warnings`; no missing assets (a round that
still builds with failed asset lookups reports each as `missing_asset` on its first tick, and `record.json` `missing`
lists them; no cache or no map is exit 2 instead); and the
**stuck** detector (the player stays inside a 24 px box for 20 s while pressing movement, ignoring `hold`, ropes and
idle play; `--stuck-px` / `--stuck-s` tune it). Repeats of one finding within 96 px and 30 s count once.

The evaluations (Jev, after the round, from facts code prepared): death fairness and "could a careful player have
avoided it", dullness per run minute, stuck or awkward movement, and the meaningfulness of every card offer. They
are skipped on a replay, without a key, with `--evaluations=false`, and by default with `--brain=fallback` or
`builtin`; the report says so.

Run directory files: `scenario.json` (every resolved flag), `personality.json`, `decisions.jsonl` (`situation_shown`:
the exact state sent to Jev, or the buckets and tactic state a fallback or warp answer used; options in screen and
presented order, answer, probabilities, confidence, source, latency, fallback reason; a replay ignores
`situation_shown`, and recordings without it still replay),
`findings.jsonl`, `timeline.jsonl` (one row per run second), `hits.jsonl` (every landed hit), `record.json`
(`record_tier<N>.json` in a chain), `fingerprint.json`, `evaluations.json` (results and the exact states sent),
`game.log`, `report.md`, `report.json`.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | clean: no deterministic problems (Jev opinions and patterns never count) |
| 1 | deterministic problems: an invariant finding (including `missing_asset`), a `SCRIPT ERROR` / `ERROR:` in `game.log`, or a replay divergence; with `--strict-eval`, Jev-flagged results too ("needs review" never counts) |
| 2 | infrastructure error: Godot missing, a round that cannot start (no asset cache, no map), an invalid personality or scenario, `--brain=jev` without a key, a protocol violation, no `end` message, no output for `--liveness-s` (default 60 s) |

A matrix exits with the worst code over its cells. A windowed replay exits 0 on a match, 1 on a divergence, 2 on an
infrastructure error.

## Replay and screenshots

`--replay=<run dir>` re-runs a recording exactly: options come from its `scenario.json`, the personality from its
own `personality.json`, and each answer from `decisions.jsonl` in order. It never resolves a key or calls Jev. Each
decide must match the recording's kind, options (in on-screen order) and tick, and every `hello` and fingerprint
field must be equal (ticks, state, time, level, job, kills, cards taken, a hash of the answers and a hash of the
timeline). Any mismatch is one `replay_divergence` problem naming the earliest difference, and exit 1. A replay of a
recording made before a code change is also a regression check: it diverges when the change alters the round.

- Replay one cell directory at a time; a matrix root directory is not replayable as a whole.
- A replay writes a new `<run dir>_replay_<time>/` beside the recording (`--out` overrides), so the recording stays
  byte-for-byte replayable. Inside a matrix directory, `--summarize` skips these and `_windowed_` directories.

`--replay=<run dir> --windowed` plays the same decisions in the real game window (RunScene with the playtest policy
and a forced 800x600 view), then checks the fingerprint the same way:

- Screenshots are saved at each `--shots-at` time (comma separated run seconds), at every timed finding of the
  recording, and at RunScene's own event shots: every level-up (RunScene's tool-only `shot_every_level_up`; normal
  runs keep levels <= 2 and every 10th), job changes, bosses, death, clear.
- Output goes to a new `<run dir>_windowed_<time>/` directory (`shots/`, `replay.json`, `report.md`); the
  recording's `report.md` gets a "Windowed replays" pointer.
- `--skip-to=<s>` fast-forwards without drawing (every tick still plays); shots before it are skipped. `--speed`
  (default 4) changes only how fast it is drawn, never which ticks run.
- **Keep the window visible.** An occluded or minimized window draws no frames, so its shots are reported as not
  saved. Don't run the test suite or another windowed run at the same time.
- Tier chains can't be replayed windowed (replay them headless); invariants don't run in the windowed replay.
- Look at the screenshots yourself (the Read tool shows PNGs). Numbers alone don't show a broken sprite.

## Extending

The Node package keeps game-agnostic infrastructure in `tools/playtest/src/core/` (protocol, session, recorder,
replay, Jev client, key resolution, shuffle, report registry, findings, log scan, aggregate, flag registry, exit
codes) and Maple Survivors in `tools/playtest/src/maple/` (launcher, Jev questions, fallbacks, personalities,
scenarios, evaluations, report sections). The game side is `game/tools/playtest/` (driver, policy, decision points,
tactic controller, motor noise, situation, invariants, timeline, fingerprint, replay link). Rules for that code:
typed GDScript with `##` docs and a `# tier C:` comment on every threshold, erasable TypeScript only (no `enum`, no
`namespace`, no parameter properties; relative imports with `.ts`), no network in tests (mock the Jev transport),
and no networking anywhere in `game/` (`test_offline.gd`). Each recipe is done when `ISOLATE=<name> bash
scripts/test.sh playtest` and `cd tools/playtest && node --test` pass and the stated real run shows the change.

### Add a personality

1. Copy the closest file in `tools/playtest/personalities/` to `<name>.json` (lower_snake_case; `name` must equal the
   file name). Edit it against the schema in `src/maple/personality.ts`: `description` and `goals` are what Jev reads
   as the player; `tactics.allowed` / `default` / `checkpoint_s` / `hold_s`; `emergency`; `motor`; `fallback`
   (`cards`: `sensible` | `random` | `weighted` with `weights`; `job`; `tactic_rules` over bucket names). Put the
   reason for tier-C numbers in `_doc`.
2. To ship it, add the name to `SHIPPED_PERSONALITIES` in `src/maple/personality.ts` (the tests assert that the
   directory and the list agree) and, if the matrix should cover it, to `scenarios/matrix.json`. Add a case to
   `test/personality_fallback.test.ts` if its fallback picks differently.
3. Check: `node --test` passes, and
   `ISOLATE=me bash scripts/agent_playtest.sh --personality=<name> --brain=fallback --minutes=3` exits 0 and its
   report's Personality section and tactic shares show the new player. A Jev run (`--brain=jev`) shows whether Jev
   reads the description the way you meant; if not, rewrite the description and goals, not the code (#97 did this
   for `inexperienced` and `defensive`).

### Add a scenario

1. Add `tools/playtest/scenarios/<name>.json` with the fields in the `src/maple/scenario.ts` header (`stage`,
   `seeds`, `personalities` or `"all"`, `minutes`; optional `warp`, `character`, `tier`, `brain`, `evaluations`,
   `invariants`, `jobs`, `description`). Training seeds only; held-out seeds are rejected.
2. Check: `node --test` passes (`test/scenario.test.ts` loads every shipped scenario) and
   `ISOLATE=me bash scripts/agent_playtest.sh --scenario=<name>` runs its cells.

### Add a decision kind

A decision kind has four parts, one per side of the protocol:

1. **Game side**: a new `game/tools/playtest/<kind>_decision.gd` extending `decision_point.gd` (the smallest example
   is `tactic_decision.gd`). Set `kind` in `_init`, and implement `options(w)` (ids are strings, in on-screen order),
   `baseline(w, policy)` (the sensible answer from real game code; called once per decision, before the brain, so any
   RNG it uses is consumed in a fixed order), optionally `situation(w)`, and `apply(w, policy, answer)`. A kind that
   opens like a window (`pending(w)` true) goes into `decision_points` in `playtest_policy.gd` `_init`; a kind asked
   at moments of your choosing is called through `PlaytestPolicy.decide(point, w)`, as the tactic checkpoints are.
2. **Protocol**: no new message type; the `decide` carries your `kind`. Document the situation keys you add in the
   `playtest_situation.gd` header and type them in `src/maple/situation.ts`. Keep answer lines short (the driver
   reads with a 4096-byte buffer).
3. **Jev question**: a request builder in `src/maple/jev_brain.ts` beside `cardRequest` / `jobRequest` /
   `tacticRequest`, added to the `d.kind` dispatch. State goes in as named buckets and words, options as a Choice in
   the seeded shuffle (`core/shuffle.ts`), and any gate on confidence is explicit code with a tier-C constant.
4. **Fallback**: a `kind` branch in `src/maple/personality_fallback.ts` (and `fallback.ts` for the file-less sensible
   brain) that answers deterministically from the baseline or the buckets.
5. Tests: a GDScript test that the driver emits a valid `decide` for your kind and applies an answer (see
   `test_playtest_protocol.gd`), a Node test for the request shape with a mocked transport, and a fallback test. A
   recorded run must still replay with `replay: match`.

### Add an invariant

1. In `game/tools/playtest/playtest_invariants.gd`, add the kind to `KINDS` and call `report(w, kind, key, message)`
   from `observe` (every tick) or `on_decision` (window open / applied). `key` groups repeats for de-duplication.
   Put any threshold in a `# tier C:` constant, and add a driver flag only if agents need to tune it.
2. Add the same kind to `FINDING_KINDS` in `src/maple/invariant_flags.ts` (`test/checks.test.ts` asserts the two lists
   agree; that makes `--inject-finding=<kind>` accept it).
3. Tests in `game/tests/unit/test_playtest_invariants.gd`: it fires on a constructed violation and stays silent over
   the normal synthetic run.
4. Check: `--inject-finding=<kind> --brain=fallback --minutes=1` exits 1 and the report lists it; a normal
   `--brain=builtin --minutes=30` run on both stages still finds nothing.

### Add an evaluation

1. Facts: a function in `src/maple/eval_facts.ts` that reads the run directory and returns a `state` whose every value
   is a string (words and buckets; a test fails on any number).
2. Question and policy: in `src/maple/evaluations.ts`, add the request to `evaluationRequests` (one request per state;
   independent questions batched in it), a rule to `RULES` (`score` or `noul`, `threshold`, which direction is worse;
   tier C), the result in `runEvaluations`, and its report entry in `opinionsOf`.
3. Tests in `test/evaluations.test.ts`: the request shape, the classification at the threshold, and skipping without
   Jev.
4. Check: a run with a key shows the new result in the report's Evaluations section, and `evaluations.json` holds the
   exact state sent.

### An adapter for another game

`core/` knows nothing about Maple Survivors: it spawns a driver, speaks protocol v1 (`core/protocol.ts` and the
GDScript twin `playtest_protocol.gd` document every message), records decisions, replays them, calls Jev, renders a
report from registered sections and maps problems to exit codes. A new game needs:

- a driver in that game that plays at fixed ticks, writes `@@PT `-prefixed JSON lines (`hello`, `decide`, `finding`,
  `end`, `error`) to stdout, blocks on one answer line per `decide`, and finishes on its own baseline at stdin EOF;
- an adapter folder beside `maple/`: a launcher (how to start the driver), Jev question builders and fallbacks per
  decision kind, report sections (`registerSection`, optional `setSnapshotFormatter`), its flags on the
  `FlagRegistry`, and its personalities and scenarios;
- a CLI entry like `src/cli.ts` that composes `core` with the adapter.
