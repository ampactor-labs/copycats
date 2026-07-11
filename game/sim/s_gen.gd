class_name SimGen
extends RefCounted
# Seeded house generation for the daily. The grammar is deliberate: a
# rightward-ascending staircase of three platforms from the spawn ground
# up to the high dinner bowl, every jump sized inside the movement
# envelope so the critical path is reachable BY CONSTRUCTION, not by
# luck. The bowl sits one safe step above the last platform; the ground
# carries one fair-width pit. daily() still farms a finishing bot run as
# the empirical reachability proof and mutates the seed until one passes,
# so the same date yields the same proven house on every device.
#
# Base difficulty is kept low on purpose: this is UCH, so the round-1
# no-trap run should be a gentle climb and the challenge comes from what
# the cats knock into the house. The open airspace above the staircase
# is the trap surface, and there is a lot of it.
#
# Level-authoring metrics, derived from the movement constants (tiles):
#   a full jump peaks at JUMP_H = 3.3 t; run speed is 8.5 t/s.
#   a rising-2 jump carries ~4.3 t horizontally -> SAFE_GAP = 3 (0.7x)
#   a flat jump carries      ~5.1 t horizontally -> SAFE_PIT = 4 (0.8x)
#   required climbs stay at   SAFE_RISE = 2 t     (well under the 3.3 peak)
# Every demand the critical path makes is sized in these units.
const SAFE_RISE := 2
const SAFE_GAP := 3
const SAFE_PIT := 4
const GROUND := 13
const N_PLAT := 3          # a 3-beat staircase spans the width in fair hops

static func generate(seed_v: int, items: Array) -> SimLevel:
	var r := SimRNG.new(seed_v ^ 0x5EED)
	var g: Array = []
	for y in range(SimC.GH):
		var row: Array = []
		for x in range(SimC.GW):
			row.append("#" if (x == 0 or x == SimC.GW - 1) else ".")
		g.append(row)

	# bowl: high on the right, cols 20..24
	var bowl_y := 5 + r.below(3)            # 5..7
	for x in range(20, 25):
		g[bowl_y][x] = "#"

	# distribute the climb over four hops (ground -> p0 -> p1 -> p2 -> bowl),
	# each one or two rows; the trailing hops shrink first, so the final
	# approach to dinner is the gentle one. the platform rows are the first
	# three cumulative stops.
	var climb := GROUND - bowl_y            # 6..8
	var steps: Array = [SAFE_RISE, SAFE_RISE, SAFE_RISE, SAFE_RISE]
	var reduce := 4 * SAFE_RISE - climb     # 0..2
	for k in range(reduce):
		steps[3 - k] = 1
	var rows_at: Array = []
	var ry := GROUND
	for i in range(N_PLAT):
		ry -= int(steps[i])
		rows_at.append(ry)

	# horizontal anchors near 5, 10, 15 keep every gap in [0, SAFE_GAP], and
	# the last platform lands within SAFE_GAP of the bowl by construction.
	var lefts: Array = [5 + r.below(2), 10 + r.below(2), 15]
	for i in range(N_PLAT):
		var w := 3 + r.below(2)
		var lx := int(lefts[i])
		for x in range(lx, mini(lx + w, SimC.GW - 1)):
			g[int(rows_at[i])][x] = "#"

	# ground with one fair-width pit, clear of the spawn and the bowl run
	var pit_w := 2 + r.below(SAFE_PIT - 1)  # 2..4, always a fair flat jump
	var pit_x := 7 + r.below(5)             # 7..11
	for x in range(1, SimC.GW - 1):
		if x < pit_x or x >= pit_x + pit_w:
			g[GROUND][x] = "#"

	# a couple of side ledges for trap variety, only in clear cells; the
	# bot-proof gate rejects any seed whose ledge blocks the path.
	for i in range(r.below(3)):
		var fx := 3 + r.below(14)
		var fy := 3 + r.below(7)
		var fw := 2 + r.below(2)
		var clear := true
		for x in range(fx, fx + fw):
			for yy in range(fy - 1, fy + 2):
				if g[yy][x] == "#":
					clear = false
		if clear:
			for x in range(fx, fx + fw):
				g[fy][x] = "#"

	var rows := PackedStringArray()
	for y in range(SimC.GH):
		rows.append("".join(g[y]))
	var lvl := SimLevel.build(items, rows)
	lvl.spawn_px = (2 + r.below(2)) * SimC.FP + SimC.FP / 2
	lvl.spawn_py = GROUND * SimC.FP
	lvl.bowl_cx = 22 * SimC.FP + SimC.FP / 2
	lvl.bowl_top = bowl_y * SimC.FP - 157286   # 2.4 t of pole above the platform
	lvl.bowl_bot = bowl_y * SimC.FP
	lvl.safe = [[1, 9, 5, 5], [19, bowl_y - 5, 7, 6]]
	return lvl

static func daily(seed_v: int) -> Dictionary:
	for attempt in range(30):
		var lvl := generate(seed_v + attempt * 7919, [])
		var proof := SimBot.farm_finishing(lvl, 100)
		if proof.size() > 0:
			return { "lvl": lvl, "attempt": attempt, "proof_len": proof.size() }
	# never expected; the classic house is the proven fallback
	return { "lvl": SimLevel.build([]), "attempt": -1, "proof_len": 0 }
