class_name SimBot
extends RefCounted
# The chaos bot: always runs right, jumps in seeded random bursts. It has
# two jobs. In tests it farms ghost runs. In production it is the
# beatability prover for generated levels — a daily level ships with a
# bot run that genuinely reaches the flag, or it doesn't ship.

static func bot_log(seed_v: int) -> PackedByteArray:
	var r := SimRNG.new(seed_v)
	var out := PackedByteArray()
	var hold := 0
	var gap := 2 + r.below(10)
	for t in range(900):
		var b := 14
		if hold > 0:
			b |= SimC.BIT_JUMP
			hold -= 1
		else:
			gap -= 1
			if gap <= 0:
				hold = 6 + r.below(13)
				gap = 3 + r.below(12)
		out.append(b)
	return out

static func farm_finishing(lvl: SimLevel, max_seeds: int) -> PackedByteArray:
	# first bot seed whose run reaches lvl's flag; empty if none do
	for seed_v in range(1, max_seeds + 1):
		var log_b := bot_log(seed_v)
		var st := SimRace.resim(log_b, lvl)
		if st.finished:
			return log_b.slice(0, int(st.len))
	return PackedByteArray()
