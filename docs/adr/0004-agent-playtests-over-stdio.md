# Agent playtests run the sim headless in lockstep with an external brain over stdio

Agent playtests (spec #91) need an autonomous player that makes a person's judgment calls (cards, job branches,
tactics) with TypeSafe's Jev model, while the round stays the real, deterministic game. The game side is a headless
Godot driver (`game/tools/playtest/`) that plays the real `RunWorld` at fixed 1/60 s ticks; the brain is a Node CLI
(`tools/playtest/`) outside `game/`. At each decision point the driver writes one prefixed JSON line to stdout and
blocks on one answer line from stdin, so the sim is paused while the brain thinks and the round never depends on
wall-clock time or network latency (decided for spec #91, 2026-10-16).

- **Why outside `game/`:** the game is offline by hard rule (`test_offline.gd`), and TypeSafe is a dev aid only
  (owner decision). Keeping every network call and the SDK in a dev-only Node package means the shipped game and the
  importer still contain no networking code, and the TypeSafe key never reaches the game process.
- **Why stdio:** both processes are local and run in lockstep; a pipe needs no ports, no server and no networking
  API on the Godot side, and verified behaviour on the dev PC (lines arrive at once; stdin EOF returns an empty line
  rather than hanging) lets the driver finish a round on its own baseline when the brain disappears.
- **Why decisions are recorded:** a Jev answer is not reproducible run to run. Recording every decision (options in
  screen and presented order, answer, probabilities, confidence, source) with a fingerprint of the round makes any
  run replay exactly without Jev or a key, turns a divergence into a loud failure, and lets a windowed replay
  screenshot the moment a problem happened.

## Considered options

- Jev inside the game through Godot's HTTP classes: rejected, it breaks the offline rule and ships a dev aid.
- Jev frame-by-frame control: rejected, slow and costly; the brain chooses tactics at checkpoints and triggers, and
  deterministic game-side code turns the tactic into input every tick.
- A socket between the two processes: rejected, it puts networking API in `game/` for no gain over a pipe.

## Consequences

- The driver reuses `balance_run.gd`'s run loop through an injectable run policy, so a playtest records every
  balance metric and the sensible personality with a deterministic brain plays the `balance.sh` bot round exactly.
- Production code gained one tool-only seam: RunScene's `options.policy` (absent in every production launch).
- A change to game code can make an old recording diverge; that is intended, and a replay doubles as a regression
  check.
