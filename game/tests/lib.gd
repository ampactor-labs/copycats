extends RefCounted
# Shared test-input generators. Preloaded by the suites and tools; not a
# global class on purpose — nothing outside tests/ may depend on these.

static func mk(axis: int, jump: bool, down: bool = false) -> int:
	var b := clampi(axis, -7, 7) + 7
	if jump:
		b |= SimC.BIT_JUMP
	if down:
		b |= SimC.BIT_DOWN
	return b

static func rand_log(seed_v: int, n: int) -> PackedByteArray:
	var r := SimRNG.new(seed_v)
	var out := PackedByteArray()
	var jump := false
	var axis := 7
	for t in range(n):
		if r.below(6) == 0:
			axis = r.below(15)
		if r.below(5) == 0:
			jump = not jump
		var down := r.below(40) == 0
		var b := axis
		if jump:
			b |= SimC.BIT_JUMP
		if down:
			b |= SimC.BIT_DOWN
		out.append(b)
	return out

static func bot_log(seed_v: int) -> PackedByteArray:
	return SimBot.bot_log(seed_v)

static func farm_finishing(max_seeds: int) -> PackedByteArray:
	return SimBot.farm_finishing(SimLevel.build([]), max_seeds)

static func saw_on_path(st: Dictionary, lvl: SimLevel) -> Dictionary:
	# first placeable saw cell along a recorded stream; {} if none
	var t: int = int(st.len) / 3
	while t < int(st.len):
		var cx := SimC.fdiv(int(st.xs[t]))
		var cy := SimC.fdiv(int(st.ys[t]) - SimC.FP / 2)
		if lvl.place_valid("saw", cx, cy, 0):
			return { "cx": cx, "cy": cy }
		t += 5
	return {}

static func test_items() -> Array:
	return [
		{ "type": "saw", "cx": 8, "cy": 12, "rot": 0, "round": 1 },
		{ "type": "spikes", "cx": 16, "cy": 12, "rot": 0, "round": 1 },
		{ "type": "spring", "cx": 6, "cy": 12, "rot": 0, "round": 1 },
		{ "type": "bow", "cx": 2, "cy": 8, "rot": 0, "round": 1 },
	]
