# Common brief for every Maple Survivors skill-audit specialist

You are one of five independent specialist auditors of **Maple Survivors**, a Godot 4.7.2 (typed GDScript) game that
combines MapleStory v83 movement/presentation/jobs/progression (rendered from the player's own WZ data via a Rust
importer, `tools/wzimport`) with Vampire-Survivors-style auto-attacks and swarms. This is an AUDIT, not implementation.

## Workspace and hard limits
- Repo (git worktree): `C:\Users\itech\.t3\worktrees\maple-survivors\t3-eb28f480` at commit `a68e74f` (clean tree).
- READ-ONLY. The only file you may create/edit is your own report `evidence/skill-audit/reports/<DOMAIN>.md`
  (gitignored), plus throwaway probe files under `_scratch/audit-<DOMAIN>/` (gitignored) if you truly need one.
  Do not edit source, data, docs, tests, scripts, assets or settings. No git commit/stash/checkout/reset, no `gh` writes
  (read-only `gh issue list/view --repo itechify/maple-survivors` is fine and encouraged), no package/skill installs.
- Never touch `%APPDATA%\MapleSurvivors\save.json`, `settings.cfg` or the shared `asset_cache`. Never commit or copy
  proprietary data. Balance: no tuning, no data changes; seeds only 1..60 and 2026 (held-out ranges are forbidden).

## Skills (the reason for this audit)
The gamedev skills from github.com/gamedev-skills/awesome-gamedev-agent-skills are installed at
`C:\Users\itech\.t3\projects\maple-survivors\.agents\skills\<name>\SKILL.md` (NOT inside the worktree).
Read the full `SKILL.md` of every skill assigned to you before applying it; open its `references/*.md` when a finding
needs that depth. Apply a skill only where the project actually implements that system. Your report must list exactly
which skill files you read, and every finding must name the skill guidance that revealed it.
Do NOT blindly apply defaults: this is an action-survival game with a custom deterministic sim, not a grid roguelike
and not a CharacterBody2D platformer.

## Project docs to read first
`AGENTS.md` (conventions, hard rules, test/playtest/balance procedures), then the doc sections your domain needs:
`docs/ARCHITECTURE.md` (1349 lines), `docs/GAME_DESIGN.md` (5930 lines; use headings: `grep -n "^#" docs/GAME_DESIGN.md`),
`docs/ASSET_PIPELINE.md`, `docs/IMPLEMENTATION_PLAN.md` (performance log), `docs/RESEARCH.md` section 6, `docs/adr/*.md`,
`GLOSSARY.md`. Check `gh issue list --repo itechify/maple-survivors --state all --limit 300` and `gh issue view <n>`
before reporting something as new: only #46 (roadmap) and #77 (deferred AI balance pass) are open.

## Intentional decisions: NOT defects (do not report these as problems)
- `game/scripts/sim/` is a pure deterministic simulation: no nodes, Input, Time, files or autoloads; fixed 1/60 s
  ticks driven by RunScene's accumulator (at most 4 catch-up ticks); events reported in an event list.
- Movement re-implements v83 Physics.img (FootholdMap/PlayerMotion/LadderSet), NOT CharacterBody2D/move_and_slide or
  Godot physics bodies. The owner forbids retuning movement ("movement feels like real MapleStory").
- Swarms use struct-of-arrays Packed*Arrays, pools and RenderingServer canvas items, not per-entity nodes.
- Canonical WZ/canonical data vs survivor tuning (`game/data/survivor/`) are separate; numeric MapleStory IDs kept.
- ADRs 0001-0005 (run of rounds with one character; equipment drops and shops sell scrolls; account-wide cash items;
  web build imports the player's own data in-page; physical combat with weapon-gated skills and no miss).
- Owner design rules: cards are only real v83 skills of the current job tier (no job-neutral/stat cards since #225;
  Power Elixir only as filler); skills start in vanilla v83 form, extra shots/pierce come from cards; one weapon per
  advancement choice (#226); first job at Lv10 for every class; advancing grants no skills; no skill slot caps;
  Skill.wz `req` prerequisites ignored; EXP drops must not disappear; level-up refills MP only; player statuses only
  from bosses; The Tree That Grew is due for an owner mob rework (its early deaths are known); NO balance tuning or
  AI-run balance until the dedicated pass #77 (feature work only runs a regression smoke).
- Offline-only: no networking in `game/` or `tools/wzimport/`; the web shell in `web/` may fetch only its own bundle
  and the import address the player types (ADR 0004).
- Provenance tiers A/B/C on non-WZ constants. The 24 importer warnings "unresolved UOL heal/*/weapon -> ../../swingO2"
  are already documented.

## Runtime checks (coordination)
The lead runs the standard verification centrally; do NOT duplicate it. Outputs land in
`evidence/skill-audit/` progressively, each phase marked by a sentinel file:
- `PERF_DONE`: uncapped playtests `perf/density_hg_s2026`, `perf/finale_hg_s2026`, `perf/density_tree_s2026`
  (summary.json + screenshots, speed 1, --vsync=off, 1600x1200) and `logs/bench_*.log`.
- `CHECKS_DONE`: `logs/test_suite.log` (full `scripts/test.sh` with the real cache), `logs/cargo_test_realwz.log`
  (with MAPLE_WZ_ROOT), `logs/node_tests.log`, `balance/<stage>_<policy>/` (seeds 1 2 2026, both stages, bot/random)
  and `balance/repeat_henesys_hg1_bot/` (same run repeated, for a determinism diff).
- `VISUAL_DONE`: `visual/*/` x4 playtests with screenshots (Henesys default, Tree with real windows, Warrior 110,
  Hunter 310, Dark Cave with the Lv38 F/P fixture). `FLOW_DONE`: `flow/{full,rounds,economy}/` flow-driver shots.
  `EXPORT_DONE`: `export/win`, `export/web` builds and `logs/export_*.log`.
- `pipeline.log` shows what ran and exit codes.
Do not launch any Godot, cargo or node process until `evidence/skill-audit/PERF_DONE` exists (perf is being measured
on a quiet machine). After that, small targeted checks are allowed if they materially confirm a finding: always prefix
`MAPLE_SURVIVORS_CACHE=C:/Users/itech/AppData/Roaming/MapleSurvivors/cache-skill-audit ISOLATE=audit-<DOMAIN>`
(e.g. `bash scripts/test.sh <filter>`, a single-seed `bash scripts/balance.sh 1 --stage=...`, or a headless probe run
against your isolated mirror `_scratch/godot_runs/audit-<DOMAIN>/game`). Any timing you take after PERF_DONE is
contended (other verification runs share the machine): label it so. If a sentinel you depend on is still missing when
you are otherwise finished, wait at most ~10 minutes, then list the dependent check as "not executed / pending lead".

## Finding format (each finding)
1. ID (`<DOMAIN>-<n>`) and title; 2. Category and severity (Critical/High/Medium/Low); 3. Finding type: Confirmed bug,
measured performance issue, maintainability risk, UX concern, or proposed improvement; 4. Evidence: file paths with
line numbers, reproduction steps, test/log/screenshot paths; 5. Skills applied (skill name + the specific guidance);
6. Player/developer impact; 7. Recommended improvement (targeted, respecting the architecture above); 8. Effort S/M/L;
9. Confidence: Confirmed / Likely / Needs validation; 10. Regression test or acceptance criteria.
Add: "False positive if: ..." (what would make this wrong, and whether you checked it) and "Known/intentional check:"
(docs/issues you searched). Severity: Critical = crash/data loss/save corruption/legal or offline violation;
High = player-facing breakage or a correctness defect hit in normal play, or a large measured cost; Medium = real but
bounded impact; Low = polish/minor risk.

Prefer 8-20 strong, evidenced findings over a long checklist. Reject your own speculative items, or put them in an
"Unverified hypotheses" section. Distinguish objective defects from subjective recommendations.

## Report structure (`evidence/skill-audit/reports/<DOMAIN>.md`, aim for under ~700 lines)
1. Skills read (paths) and how each was applied / why any assigned skill did not apply.
2. Scope covered (files/systems read, commands run with exit codes; mark every check as passed / failed / skipped /
   not executed).
3. Strengths worth preserving (with evidence).
4. Findings (format above), most severe first.
5. Considered and rejected (known, intentional, or unsupported), one line each.
6. Unverified hypotheses and what would validate them.
7. Suggested small, independently implementable backlog tasks (each with acceptance criteria and the skills to load).
Your final chat reply: 5-10 lines summarising the top findings, plus the report path.
