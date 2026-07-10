# copycats — the ultimate form

One sentence: an async multiplayer party platformer where a group chat
shares one increasingly boobytrapped house, every run is a
deterministic replay a few KB long, and each round resolves into a
spectacle video the chat watches without installing anything.

The skin: you're a cat racing the spectral copycats of your own past
lives to the dinner bowl, knocking household objects over to swat them
on the way. (Rebranded from the working name chickho, 2026-07-10; the
mechanics predate the cats and are unchanged.)

## Why this is the form

Three facts converge on it.

First, Ultimate Chicken Horse's race phase is already parallel. Racers
don't collide; the game is placement mind-games plus simultaneous solo
runs plus shared scoring. Nothing about the run requires the other
players to be present while you do it.

Second, a deterministic sim turns a run into a file. That's the
two-top thesis transplanted: record the input log, replay it anywhere,
bit-identical. And this game needs the easy half only — no rollback,
no prediction, no resync. Record and replay.

Third, mobile multiplayer is asynchronous whether you design for it or
not. Four friends are never on phones at the same moment, but a group
chat plays a round-per-hour game forever. The chat is the lobby.

Compressed to what survives the phone: knock one thing over on your
own time, run the same locked house as everyone else on your own time,
then watch all the runs race as copycats in one resolution replay
where your fan swats your friend by name.

## The loop, front to back

A match is 2 to 8 people behind an invite link, playing to nine points
with UCH-faithful rules: points for making dinner, a first-dinner
bonus, swats credited to whoever placed the object, and the
landed-on-their-feet rule (everyone finishes, nobody scores).

Each round has two gates. Gate one, placement: everyone gets the same
offer and knocks one piece into the house; the house locks when the
last piece lands or the timer lapses. Gate two, the run: everyone
races the same locked house solo; a recorded input log is the
submission. If you miss the window, your best previous life replays as
your entry — it will probably die to the new hazards, which is both
the punishment and the comedy. Resolution then plays every run
simultaneously as copycats, credits each death ("Dana's fan swats
Alex"), applies scoring, and emits the share card.

Live play falls out instead of being built: couch mode is pass-and-play
placement with hotseat runs, and when the whole group happens to be
online the gates collapse to real-time party play in all but name.

Solo is the daily: one seeded house for everyone, raced against your
own copycats plus three strangers' replays drawn from the day's pool,
with a leaderboard of top cats. It's the game you have before you've
convinced any friends, the content between rounds, and the funnel into
matches.

## Distribution

Products here die on the distribution wall, so the wall is a design
input. Every loop emits an artifact into a chat: the invite is a link,
the turn ping is a notification, and the resolution is a video that
autoplays inline in iMessage or WhatsApp — the Wordle square, except
it's your friend's cat dying to your box fan. Watching costs no click
and no install. The link under the video opens the web build to play
the house immediately; installing (add-to-home-screen PWA first,
stores later if ever) is an upgrade for regulars, never the price of
first contact.

## Tech shape

Godot 4, one codebase, web-first; the same export pipeline covers
Android/iOS later if stores ever earn their keep.

- `sim/` — a pure deterministic module: integer math only, no engine
  physics, own RNG, fixed timestep, input-log in and state out, zero
  node dependencies, runs headless. If GDScript determinism proves
  leaky in practice, the fallback is the two-top `fixed_math` crate
  behind GDExtension; that risk is retired in M2, not discovered in
  M4.
- `render/` — reads sim state, interpolates, carries all juice; never
  writes back.
- replay — versioned format, strict sim_version match, no migrations
  (two-top rule). Any sim-affecting change bumps the version; the web
  player can keep old versions around cheaply.
- server — one thin match service on Railway: Postgres rows for
  replays (they're kilobytes), REST plus pings for turns. Replays are
  the wire format. There are no game servers to run, and determinism
  means any client can re-simulate any submitted replay and refute a
  cheat.
- share video — rendered on-device at resolution time; determinism
  means any client renders identical frames, so the phone that closes
  the round mints the clip.
- CI — the two-top harness pattern ported: cross-platform determinism
  matrix diffing per-tick checksums, plus a replay fuzz soak.

## Income

Cosmetics only: cats, hats, trails, swat taunts, maybe a founder pack.
Hazards and movement are never sold — pay-for-power kills a party
game's trash-talk economy, which is the actual product. No crypto.
The architecture keeps server cost near zero, so the business has to
clear a low bar, not a miracle.

## Named risks

1. Two-gate friction. Async waits twice per round. Mitigations:
   timers with the stale-copycat auto-entry, gates that collapse when
   everyone's online, and the daily filling the gaps.
2. GDScript determinism is a discipline, not a guarantee. The CI
   matrix landed in M2, before any multiplayer existed, because
   retrofitting determinism is the one mistake this architecture
   cannot survive. Green on linux x64/arm64, macOS, and Windows.
3. Async trades the live-race adrenaline for group-chat theater. This
   is the one real gamble; the resolution replay has to carry the
   drama. The grin test is the proxy: if swatting your own copycat is
   funny alone, swatting Dana's is funnier in company.
4. Godot web export weight. Video-first sharing means spectators never
   pay it; players pay it once and the PWA caches it.

## Build order

Every milestone ships something playable.

- M1 feel — Godot project, deterministic sim, touch controls, the
  spike's solo-copycat loop rebuilt properly. Shipped.
- M2 determinism — replay format, versioning, CI matrix, fuzz soak.
  Shipped; the four-platform matrix is green.
- M3 daily — seeded proven-beatable houses and the public web build at
  ampactor.dev/copycats. Shipped; stranger pools and the leaderboard
  move to M4 where they share the relay.
- M4 matches — the Railway relay: room codes, invite links, async
  rounds, stranger-ghost pools, leaderboard, resolution replays.
- M5 spectacle — share video, turn pings, cosmetics, PWA polish.

The HTML spike (`index.html`, and the published artifact) stays as the
feel reference and the cheapest place to test loop variants before
they're worth porting.
