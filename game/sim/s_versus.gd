class_name SimVersus
extends RefCounted
# Versus for 2-8 cats over one house. The entire match is an append-only
# log — placements and input-log entries per round — and everything else
# (scores, pools, fates, standings) derives from replaying it. A couch
# match and a future relay match are the same object at different paces,
# and resume-after-reload is just re-deriving from the log.
#
# Rules: everyone places one object, then everyone runs the same locked
# house. During a run you race the swattable pool of past lives, never
# this round's rivals — those meet in the resolution. Finishers score 1,
# earliest finisher 1 more, both nulled if every live run finished
# (landed-on-their-feet). Any copycat or live cat killed by an object
# credits the object's owner, always — swats pay even on easy rounds,
# and yes, swatting your own past life counts. First to 9.

const MAX_PLAYERS := 8
const POOL_PER_PLAYER := 2
const TARGET := 9

const PELT_NAMES := ["ORANGE", "CREAM", "SOOT", "COCOA", "BUTTER", "PEARL", "TUXEDO", "GINGER"]

var seed_v: int
var rng: SimRNG
var n_players: int
var round_n := 0
var items: Array = []      # {type, cx, cy, rot, round, owner}
var scores: Array = []
var pools: Array = []      # per player: [{inputs, round, len}]
var match_log: Array = []  # per round: {placements: [...], entries: [{player, inputs}]}
var template: SimLevel = null

func _init(seed_in: int, players: int) -> void:
	seed_v = seed_in
	rng = SimRNG.new(seed_in)
	n_players = clampi(players, 2, MAX_PLAYERS)
	for i in range(n_players):
		scores.append(0)
		pools.append([])

func base_level() -> SimLevel:
	return template if template != null else SimLevel.build([])

func begin_round() -> void:
	round_n += 1
	match_log.append({ "placements": [], "entries": [] })

func first_placer() -> int:
	return (round_n - 1) % n_players

func draw_offer() -> Array:
	return SimMatch.draw_offer_from(rng)

func commit_item(player_i: int, type: String, cx: int, cy: int, rot: int) -> void:
	var it := { "type": type, "cx": cx, "cy": cy, "rot": rot, "round": round_n, "owner": player_i }
	items.append(it)
	match_log[round_n - 1].placements.append(it)

func pool_roster() -> Array:
	# flattened in player order; entries carry their recording round
	var out: Array = []
	for pi in range(n_players):
		for g in pools[pi]:
			out.append({ "inputs": g.inputs, "round": g.round, "len": g.len, "owner": pi })
	return out

func make_race() -> SimRace:
	return SimRace.create(items, pool_roster(), template)

func submit_entry(player_i: int, inputs: PackedByteArray) -> void:
	match_log[round_n - 1].entries.append({ "player": player_i, "inputs": inputs })

func entries_done() -> bool:
	return match_log[round_n - 1].entries.size() >= n_players

func resolve_round() -> Dictionary:
	var lvl := SimLevel.derive(base_level(), items)
	var tracks := SimRace.schedule_balls(lvl)
	var roster := pool_roster()
	var deltas: Array = []
	for i in range(n_players):
		deltas.append(0)
	var events: Array = []

	# pool ghosts: killed-by-newer check, swat credit, removal
	var ghost_views: Array = []
	var killed_flat: Array = []
	for g in roster:
		var lvl_g := SimLevel.derive(base_level(), SimLevel.items_upto(items, g.round))
		var st := SimRace.resim(g.inputs, lvl_g)
		var kill := SimRace.find_killer(st, items, tracks, int(g.round))
		var death := int(kill.tick)
		ghost_views.append({ "stream": st, "death": death, "owner": g.owner })
		killed_flat.append(death >= 0)
		if death >= 0:
			var owner_i: int = items[int(kill.item)].owner
			deltas[owner_i] += 1
			events.append({ "tick": death, "kind": "gswat", "who": int(g.owner), "by": owner_i,
				"x": int(st.xs[death]), "y": int(st.ys[death]) })

	# live entries: outcome + kill attribution
	var entry_views: Array = []
	var finishers: Array = []
	for e in match_log[round_n - 1].entries:
		var st := SimRace.resim(e.inputs, lvl)
		var view := { "player": int(e.player), "stream": st, "finished": bool(st.finished),
			"end": int(st.len) }
		entry_views.append(view)
		var last := int(st.len) - 1
		if bool(st.finished):
			finishers.append(view)
			events.append({ "tick": last, "kind": "finish", "who": int(e.player), "by": -1,
				"x": int(st.xs[last]), "y": int(st.ys[last]) })
		else:
			var kill := SimRace.find_killer(st, items, tracks, -1)
			if int(kill.tick) >= 0:
				var kt := int(kill.tick)
				var owner_i: int = items[int(kill.item)].owner
				deltas[owner_i] += 1
				events.append({ "tick": kt, "kind": "swat", "who": int(e.player), "by": owner_i,
					"x": int(st.xs[kt]), "y": int(st.ys[kt]) })
			else:
				events.append({ "tick": last, "kind": "die", "who": int(e.player), "by": -1,
					"x": int(st.xs[last]), "y": int(st.ys[last]) })

	# finish points, nulled when everyone lands on their feet
	var all_made_it := finishers.size() == entry_views.size() and entry_views.size() > 0
	if not all_made_it:
		var first_i := -1
		var first_t := 1 << 30
		for v in finishers:
			deltas[int(v.player)] += 1
			if int(v.end) < first_t:
				first_t = int(v.end)
				first_i = int(v.player)
		if first_i >= 0:
			deltas[first_i] += 1

	for i in range(n_players):
		scores[i] += deltas[i]

	# pools: drop the swatted, add this round's runs (newest first, capped)
	var k := 0
	for pi in range(n_players):
		var kept: Array = []
		for g in pools[pi]:
			if not killed_flat[k]:
				kept.append(g)
			k += 1
		pools[pi] = kept
	for idx in range(entry_views.size()):
		var v: Dictionary = entry_views[idx]
		var pi: int = int(v.player)
		pools[pi].append({ "inputs": match_log[round_n - 1].entries[idx].inputs,
			"round": round_n, "len": int(v.stream.len) })
		if pools[pi].size() > POOL_PER_PLAYER:
			pools[pi].pop_front()

	events.sort_custom(func(a, b): return int(a.tick) < int(b.tick))
	var best := 0
	var winner := -1
	for i in range(n_players):
		if scores[i] >= TARGET and scores[i] > best:
			best = scores[i]
			winner = i
	return { "ghost_views": ghost_views, "entry_views": entry_views, "events": events,
		"deltas": deltas, "all_made_it": all_made_it, "over": winner >= 0, "winner": winner }

func serialize() -> Dictionary:
	var rounds: Array = []
	for r in match_log:
		var placements: Array = []
		for p in r.placements:
			placements.append({ "type": p.type, "cx": p.cx, "cy": p.cy, "rot": p.rot, "owner": p.owner })
		var entries: Array = []
		for e in r.entries:
			entries.append({ "player": e.player, "inputs": Marshalls.raw_to_base64(e.inputs) })
		rounds.append({ "placements": placements, "entries": entries })
	return { "v": SimC.SIM_VERSION, "seed": seed_v, "players": n_players, "rounds": rounds }

static func deserialize(d: Dictionary) -> SimVersus:
	# rebuild by replaying the log; only fully-resolved rounds are kept
	if int(d.get("v", -1)) != SimC.SIM_VERSION:
		return null
	var vs := SimVersus.new(int(d.seed), int(d.players))
	for r in d.rounds:
		if r.entries.size() < vs.n_players:
			break
		vs.begin_round()
		for p in r.placements:
			vs.commit_item(int(p.owner), String(p.type), int(p.cx), int(p.cy), int(p.rot))
		for e in r.entries:
			vs.submit_entry(int(e.player), Marshalls.base64_to_raw(String(e.inputs)))
		vs.resolve_round()
	return vs
