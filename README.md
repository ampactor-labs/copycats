# copycats

[![ci](https://github.com/ampactor-labs/copycats/actions/workflows/ci.yml/badge.svg)](https://github.com/ampactor-labs/copycats/actions/workflows/ci.yml) [![determinism](https://github.com/ampactor-labs/copycats/actions/workflows/determinism.yml/badge.svg)](https://github.com/ampactor-labs/copycats/actions/workflows/determinism.yml)

A party platformer for phone browsers where every opponent is a copycat: a ghost that replays an earlier run. You play a cat racing them to the dinner bowl, and between runs you knock things over, like cacti and fans, to swat them. The simulation uses only integer math, so a copycat is stored as its run's input log, and CI compares test runs on four platforms, step by step. It is built with Godot 4.7, and a couch mode lets 2 to 8 players share one phone.

**Status: working.** Every mode runs on a single device; the online group-chat multiplayer that [DESIGN.md](DESIGN.md) plans has no code yet.

Live: https://ampactor.dev/copycats/ (phone in landscape, no install)

## Quick start

Open https://ampactor.dev/copycats/ on a phone held in landscape, or in a desktop browser. There is nothing to install, and the title screen has a button for each mode.

To run it from source, download [Godot 4.7](https://godotengine.org/download/archive/4.7-stable/), the version CI uses. From the repository root, with `godot` standing for your Godot 4.7 binary:

```sh
godot --headless --path game --import   # once, to import the project as CI does
godot --path game                       # opens the title screen
```

### Controls

| Action               | Phone                                                     | Keyboard                   |
| -------------------- | --------------------------------------------------------- | -------------------------- |
| Move                 | Slide a thumb on the left side (a floating stick)         | A and D, or Left and Right |
| Jump                 | Tap the right side; hold for a higher jump                | Space, W or Up             |
| Drop through a shelf | Swipe down on the right side                              | S or Down                  |
| Place an object      | Drag a card into the house, then tap the check to lock it | The same, with the mouse   |

In the air, pushing into a wall slides down it and jumping kicks off it. Enter starts a solo match from the title screen, and F1 toggles a debug readout.

## Usage

### Modes

- **Solo** is you against your own copycats in the fixed classic house. Round 1 is a plain run, and from round 2 you place one of three offered objects before each run. Every run that reaches the bowl becomes a copycat, and the three most recent race you.
- **Daily** is solo in a house built from the UTC date, so the house depends only on the day (see How it works). The title screen shows your best result for the day, the fewest rounds to a win, saved on the device.
- **Couch** is 2 to 8 players passing one phone. Each round every player places an object, then each runs the same house in turn against a pool of earlier runs, up to two per player. The round then replays every run at once and credits each swat by pelt name ("SOOT SWATS PEARL"). The match saves after each round, and the Couch screen offers to resume it.

The objects are a shelf (a three-tile plank you can jump up through and drop through), a cushion that bounces you up, and three hazards: a cactus, a box fan and a ball launcher that fires every two seconds. Every offer of three includes at least one hazard. Nothing can be placed in the safe zones around the start and the bowl.

### Scoring

The first side to 9 points wins, and each run has 45 seconds. In solo, reaching the bowl scores 1 plus 1 for each copycat you swatted. If copycats were racing and you swatted none, nobody scores, because everyone landed on their feet. If you die or time runs out, the copycats score 1 for each of them that survived.

In couch, each cat that reaches the bowl scores 1 and the fastest scores 1 more. If every cat makes it, nobody gets those points. Each swat, of a live cat or a copycat, scores 1 for the player who placed the object, even if it swats their own cat.

## How it works

The game is the Godot 4.7 project in [`game/`](game/), written in GDScript, Godot's own scripting language. It has two layers.

- The simulation, in [`game/sim/`](game/sim/), decides every result. It stores positions and speeds as Q16.16 fixed-point numbers: a position is an integer count of 65,536ths of a tile, so fractional movement needs no floating point. It advances in fixed ticks of 1/60 second and never uses Godot's physics engine, and random numbers come from its own generator in [`s_rng.gd`](game/sim/s_rng.gd). It has no scene nodes and runs headless, without a window.
- The shell, [`game/render/main.gd`](game/render/main.gd), handles screens, input, drawing and effects. Each tick it packs the controls into one input byte and steps the simulation with it. Drawing reads the simulation's state and blends positions between ticks. [`audio.gd`](game/render/audio.gd) synthesizes every sound at startup, so the project has no audio files.

I made the simulation deterministic: the same inputs always produce the same state, bit for bit. That turns a run into a small file, its input log, which is all a copycat needs. The online play in DESIGN.md would pass these logs between phones, and any phone could re-simulate a submitted run to check it. GDScript makes no determinism promise, so the simulation sticks to integer math and its own random numbers, and CI checks the result on four platforms (see Testing).

### Replays and copycats

A run is its input log: one byte per tick, holding the stick position (0 to 14) and bits for the jump and down buttons. The byte records held buttons only, and the simulation finds each new press by comparing with the previous tick. A copycat is an input log re-simulated against the house as it stood when the run was recorded, so objects placed later cannot change its path. When a race starts, [`s_race.gd`](game/sim/s_race.gd) computes each copycat's fate: the first tick at which a hazard placed after its run touches it. So an object can swat only runs older than itself, and every fate is known before anyone moves.

[`s_replay.gd`](game/sim/s_replay.gd) defines the replay file: the bytes `CHKR`, a 16-bit sim version, a 16-bit round number, a 32-bit length, then the log. A round lasts at most 45 seconds, or 2,700 ticks, so a full-length run takes 2,712 bytes. The replay the determinism matrix uses, [`run_v1.chkr`](game/tests/canonical/run_v1.chkr), holds a 165-tick run in 177 bytes. A file loads only if its version equals `SIM_VERSION`. So far only the tests read this format; the game keeps solo copycats in memory and saves couch matches as JSON.

### Daily houses

The daily seeds the generator in [`s_gen.gd`](game/sim/s_gen.gd) with the UTC date as a number, such as 20260927, and the same number seeds the offers. The generator lays a rising staircase of three platforms from the ground to the bowl and sizes every step inside the jump, which is tuned to peak at 3.3 tiles. Required climbs are at most 2 tiles and gaps between platforms at most 3, and the one pit in the ground is 2 to 4 tiles wide. Then a chaos bot in [`s_bot.gd`](game/sim/s_bot.gd), which always runs right and jumps in seeded random bursts, has to reach the bowl within 100 bot seeds. If it fails, the generator moves to another house seed, up to 30 times, and after that falls back to the fixed classic house.

### Couch matches

[`s_versus.gd`](game/sim/s_versus.gd) records a couch match as an append-only log, a record that is only ever added to: each round's placements and each player's input log. The game derives everything else, from scores to copycat pools, by replaying that log. The autosave, `user://couch.save`, is the log as JSON, and resuming replays it. DESIGN.md plans to send the same log over the network for online matches.

### Palette

The palette is gruvbox, a warm retro color scheme. Only blue and orange carry meaning: copycats are blue, and in solo play your cat is an orange tabby. Each hazard also has its own shape. I chose this so that red-green color blindness (deuteranopia) hides nothing; no test checks it.

## Project layout

```
game/                 the Godot 4.7 project
  project.godot       settings: 832x480 canvas, GL Compatibility renderer
  main.tscn           the only scene; its script is render/main.gd
  sim/                the deterministic simulation
  render/             main.gd (screens, input, drawing) and audio.gd
  tests/              headless suites, fuzz soak, checksum dump
  tests/canonical/    the replay the determinism matrix re-simulates
  test.sh             the test gate CI runs
  export_presets.cfg  the Web export preset
index.html            the original single-file JavaScript prototype
DESIGN.md             the full design: async multiplayer, levels, build order
.github/workflows/    ci.yml, determinism.yml and deploy.yml
```

`index.html` is the first prototype, one JavaScript file built under the working name chickho. It stays as the reference for how movement should feel, and no workflow deploys it.

## Deploy

GitHub Pages serves the web build at https://ampactor.dev/copycats/, and https://ampactor-labs.github.io/copycats/ redirects there. [`deploy.yml`](.github/workflows/deploy.yml) runs on every push to `main` that changes a non-Markdown file, and on manual dispatch. It downloads Godot 4.7 and its export templates (the prebuilt engines Godot packages a game with), exports the `Web` preset, fails unless `index.html` and `index.wasm` exist, and publishes the result. The preset is Godot's single-threaded web build, so the page needs no cross-origin isolation headers (COOP and COEP), which GitHub Pages cannot send.

To export locally, install the Godot 4.7 export templates, import once as in Quick start, and run:

```sh
mkdir -p game/build/web
godot --headless --path game --export-release Web build/web/index.html
```

The output path is relative to `game/`, and `build/` is gitignored.

## Testing

```sh
GODOT=/path/to/Godot_v4.7-stable_linux.x86_64 bash game/test.sh
```

`GODOT` defaults to `~/Godot/Godot_v4.7-stable_linux.x86_64`, and `FUZZ` sets the number of fuzz matches (10 by default). The script imports the project, then runs four headless suites and stops at the first failure:

- [`run_tests.gd`](game/tests/run_tests.gd) checks movement (jump height, run speed, coyote time and jump buffering), placement rules, scoring in both modes, copycat fates, the replay codec, daily generation and couch resume. Coyote time still allows a jump for 0.1 seconds after running off a ledge, and jump buffering keeps a press made up to 0.12 seconds before landing. The generation checks cover 20 house seeds for fair pits and room for traps, and 8 dates that must never fall back to the classic house. It also runs three determinism gates: one input log run twice gives an identical checksum trail, a re-simulated replay matches the live run position for position, and a 900-tick run must still produce a recorded golden checksum.
- [`run_flow.gd`](game/tests/run_flow.gd) boots the real scene and plays two solo rounds with synthetic touch events. It taps SOLO on the title screen and steers into the pit with the touch stick. It then injects a copycat found by searching bot seeds for a run that reaches the bowl, places a fan on that run's path and checks that the copycat dies. Finding that run also shows that chaotic play can beat the classic house.
- [`run_couch_flow.gd`](game/tests/run_couch_flow.gd) plays a three-cat couch round through the real scene, from the setup screen through the replay and standings to round 2, and checks that the autosave is written.
- [`fuzz.gd`](game/tests/fuzz.gd) plays random matches with random valid placements and random inputs. Each must give an identical checksum trail when run twice and re-simulate its own replay position for position.

A checksum here is a 32-bit hash of the race state that changes from tick to tick, which is mostly the player's movement. In CI, [`ci.yml`](.github/workflows/ci.yml) runs the script with `FUZZ=50` on Ubuntu for every push and pull request that changes a non-Markdown file. [`determinism.yml`](.github/workflows/determinism.yml) runs [`dump_checksums.gd`](game/tests/dump_checksums.gd) on Linux x64, Linux arm64, macOS arm64 and Windows x64. Each platform writes a checksum for every tick of two scenarios: a 900-tick run through four placed objects, and a 1,200-tick race against the canonical replay, `run_v1.chkr`, with a fan on its path. That is 2,104 lines per platform, counted from the script, and a final job fails unless the four files are identical byte for byte. To write the same file locally:

```sh
godot --headless --path game -s res://tests/dump_checksums.gd -- --out "$PWD/checksums.tsv"
```

A simulation change that alters the golden run fails that gate, by design. Bump `SIM_VERSION` in [`s_const.gd`](game/sim/s_const.gd) and re-mint the canonical replay with `godot --headless --path game -s res://tests/gen_canonical.gd -- --write`. Then set `GOLDEN` in `run_tests.gd` to 0, run the suite and paste in the candidate it prints. The matrix rejects a canonical replay from an older version, so skipping the re-mint fails CI.

These are not tested:

- drawing and audio;
- keyboard input, since the flow tests send touch events;
- dragging objects into place, since the flow tests commit placements directly;
- the Daily button and the couch resume button, whose logic is tested directly;
- the exported web build, which CI checks only for `index.html` and `index.wasm`, and play on a real phone;
- determinism of the web build, the daily generator and couch scoring across platforms, since the matrix runs desktop builds on the race scenarios only.

## Limitations

Every match happens on one device. Racing a friend means handing them the phone, and the game sends nothing over the network, so there is no leaderboard and no way to share a replay. [DESIGN.md](DESIGN.md) describes an asynchronous version for a group chat, in which friends play their turns whenever they like and race each other's replays through a small match server. It has no code yet.

- Replays expire with the simulation. Any change that affects it must bump `SIM_VERSION`. Replay files and couch saves from older versions then stop loading, and the Couch screen deletes an old save when you try to resume it. There are no migrations, because an input log reproduces its run only under the simulation that recorded it.
- Solo and daily matches live in memory, so reloading the page ends them. Couch matches save after each completed round, and a round in progress is lost.
- The game is landscape only. The 832 by 480 canvas keeps its aspect ratio, so an upright phone shows it as a strip across the middle.
- The first visit downloads the engine. The live `index.wasm` is 39,509,339 bytes, sent gzip-compressed as 10,246,865 bytes (measured with curl on 27 September 2026).
- The daily is meant to give every player the same house, and no test checks that browsers agree on it. The determinism matrix covers desktop builds and the race simulation only. For everything else the gap matters only once replays travel between devices, and none do yet.

## Roadmap

[DESIGN.md](DESIGN.md) orders the work in milestones. M1 to M3.5 are built: movement feel, the determinism gates, the daily and couch mode. The next two are:

1. M4 adds online matches: a relay on Railway with room codes, invite links, async rounds, strangers' copycats in the daily and a leaderboard. None of it exists yet. It is the first milestone that needs a server, and the daily's stranger pools and leaderboard were deferred to it so that they can share that relay.
2. M5 adds the spectacle: a shareable video of each resolved round, turn notifications, cosmetics and an installable web app. It waits on M4, because the video is how a group chat watches an online round resolve.

## License

No license chosen yet.
