# chickho

A mobile-first Ultimate Chicken Horse-like: place one trap, then race
the ghost horses of your own past runs. Traps placed after a ghost was
recorded can kill it; finish while your old selves die to score; first
to 12. `DESIGN.md` holds the full form this is building toward — async
multiplayer for a group chat, built on deterministic replays instead of
netcode.

## Layout

- `game/` — the real build, Godot 4.7. The sim (`game/sim/`) is pure
  integer math: Q16.16 subunits per tile, fixed 60Hz ticks, own RNG, no
  engine physics, no floats anywhere a checksum can see. The shell
  (`game/render/`) draws sim state and feeds it input bytes; it never
  reaches back in. A run's replay is its input log (`s_replay.gd`),
  strict SIM_VERSION match, no migrations.
- `index.html` — the original single-file browser spike, kept as the
  feel reference. Same tuned numbers, same rules.

## Run

```sh
godot --path game        # desktop: WASD/arrows + space, S or swipe to drop
bash game/test.sh        # headless: import + sim suite + flow suite
```

On a phone the left thumb slides a floating stick, the right thumb taps
to jump (hold for height), swipe down drops through planks.

## Tests

`tests/run_tests.gd` covers jump feel, coyote and buffer windows,
placement rules, scoring, the replay codec, and three determinism
gates: the same input log twice yields an identical checksum trail, a
resimulated replay reproduces the live run position-for-position, and a
golden replay checksum pins the sim against accidental change (any real
sim change bumps `SIM_VERSION` and re-mints the golden).

`tests/run_flow.gd` boots the actual game headless and plays it with
synthetic touch events: title, countdown, stick movement, a pit death,
placement, and a farmed ghost — a seed-searched input log that genuinely
finishes the level — which the test then kills with a saw placed on its
recorded path. That last part doubles as a level-sanity property:
chaotic right-running play can beat the starter layout.

`tests/fuzz.gd` soaks N random matches (random valid placements, random
inputs), requiring identical checksum trails across repeat runs and
replay-perfect resimulation each time.

CI runs the gate on linux and a determinism matrix on linux x64,
linux arm64, macOS arm64, and Windows: each platform re-simulates the
canonical scenarios (`tests/canonical/run_v1.chkr`, minted by
`gen_canonical.gd --write`) and dumps a per-tick checksum trail via
`dump_checksums.gd`; the trails must match byte for byte. Bumping
`SIM_VERSION` re-mints the canonical or the matrix rejects its own
demo — that's deliberate.

Palette is gruvbox; meaning rides blue vs orange only and every hazard
is shape-coded — safe for deuteranopia.
