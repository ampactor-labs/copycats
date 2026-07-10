class_name SimMatch
extends RefCounted
# Match-level state: rounds, items, the ghost roster, scoring. Owns the
# deterministic RNG so a match is reproducible from its seed.

const POOL := ["plank", "spikes", "saw", "spring", "bow"]
const HAZARDS := ["spikes", "saw", "bow"]

var rng: SimRNG
var seed_v: int
var round_n: int = 0
var you: int = 0
var foes: int = 0
var items: Array = []             # {type, cx, cy, rot, round}
var roster: Array = []            # {inputs, round, len}
var template: SimLevel = null     # generated level for dailies; null = classic

func _init(match_seed: int) -> void:
	seed_v = match_seed
	rng = SimRNG.new(match_seed)

func base_level() -> SimLevel:
	return template if template != null else SimLevel.build([])

func begin_round() -> Dictionary:
	round_n += 1
	if round_n == 1:
		return { "place": false, "offer": [] }
	return { "place": true, "offer": draw_offer() }

func draw_offer() -> Array:
	var pool := POOL.duplicate()
	var out: Array = []
	while out.size() < 3:
		out.append(pool.pop_at(rng.below(pool.size())))
	var has_hazard := false
	for t in out:
		if SimLevel.DEFS[t].hazard:
			has_hazard = true
	if not has_hazard:
		out[rng.below(3)] = HAZARDS[rng.below(3)]
	return out

func commit_item(type: String, cx: int, cy: int, rot: int) -> void:
	items.append({ "type": type, "cx": cx, "cy": cy, "rot": rot, "round": round_n })

func make_race() -> SimRace:
	return SimRace.create(items, roster, template)

static func score_round(finished: bool, fates: Array) -> Dictionary:
	var dunks := 0
	for f in fates:
		if f.death >= 0:
			dunks += 1
	var survivors := fates.size() - dunks
	if finished:
		if fates.size() == 0:
			return { "d_you": 1, "d_foes": 0, "key": "first", "dunks": 0 }
		if dunks == 0:
			return { "d_you": 0, "d_foes": 0, "key": "too_easy", "dunks": 0 }
		return { "d_you": 1 + dunks, "d_foes": 0, "key": "dunked", "dunks": dunks }
	if survivors > 0:
		return { "d_you": 0, "d_foes": survivors, "key": "horses", "dunks": dunks }
	return { "d_you": 0, "d_foes": 0, "key": "wash", "dunks": dunks }

func finish_race(race: SimRace) -> Dictionary:
	var sc := score_round(race.p.finished, race.fates)
	you += sc.d_you
	foes += sc.d_foes
	if race.p.finished:
		roster.append({ "inputs": race.inputs.duplicate(), "round": round_n, "len": race.inputs.size() })
		if roster.size() > SimC.MAX_GHOSTS:
			roster.pop_front()
	var over := you >= SimC.TARGET_SCORE or foes >= SimC.TARGET_SCORE
	return { "score": sc, "over": over, "won": you >= SimC.TARGET_SCORE }
