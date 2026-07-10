# copycats

[![ci](https://github.com/ampactor-labs/copycats/actions/workflows/ci.yml/badge.svg)](https://github.com/ampactor-labs/copycats/actions/workflows/ci.yml)
[![determinism](https://github.com/ampactor-labs/copycats/actions/workflows/determinism.yml/badge.svg)](https://github.com/ampactor-labs/copycats/actions/workflows/determinism.yml)

You're a cat. Every run that reaches the dinner bowl comes back as a
copycat — a spectral replay of your own past life, racing you through
the house. Each round you knock one thing over (a shelf, a cactus, a
box fan, a cushion, a ball launcher), then run. Swat your copycats
with what you placed while still making dinner yourself; if everyone
lands on their feet, nobody scores. First to nine.

Play it: **https://ampactor.dev/copycats/** — phone, landscape, no
install. `DESIGN.md` holds the full form this builds toward: async
multiplayer for a group chat, built on deterministic replays instead
of netcode.

## Layout

- `game/` — the real build, Godot 4.7. The sim (`game/sim/`) is pure
  integer math: Q16.16 subunits per tile, fixed 60Hz ticks, own RNG, no
  engine physics, no floats anywhere a checksum can see. A run's replay
  is its input log (`s_replay.gd`), strict SIM_VERSION match, no
  migrations. Copycats are input logs re-simulated against the house as
  it stood when they were recorded.
- `index.html` — the original single-file browser spike (built under
  the working name chickho), kept as the feel reference.

## Run

```sh
godot --path game        # desktop: WASD/arrows + space, S or swipe to drop
bash game/test.sh        # headless: import + sim suite + flow suite + fuzz
```

On a phone the left thumb slides a floating stick, the right thumb taps
to jump (hold for height), swipe down drops through shelves.

## Tests

`tests/run_tests.gd` covers jump feel, coyote and buffer windows,
placement rules, scoring, the replay codec, seeded level generation,
and three determinism gates: the same input log twice yields an
identical checksum trail, a resimulated replay reproduces the live run
position-for-position, and a golden replay checksum pins the sim
against accidental change (any real sim change bumps `SIM_VERSION` and
re-mints the golden).

`tests/run_flow.gd` boots the actual game headless and plays it with
synthetic touch events: title, countdown, stick movement, a pit death,
placement, and a farmed copycat — a seed-searched input log that
genuinely reaches dinner — which the test then kills with a fan placed
on its recorded path. That doubles as a level-sanity property: chaotic
right-running play can beat the starter house.

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

The daily is a seeded house, the same for everyone on a given date,
and every generated house ships with a proof: a chaos-bot run that
genuinely reaches the bowl, found before the level is allowed to
exist.

Palette is gruvbox; meaning rides blue vs orange only (you are the
orange tabby, the copycats are blue) and every hazard is shape-coded —
safe for deuteranopia.
