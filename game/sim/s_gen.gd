class_name SimGen
extends RefCounted
# Seeded level generation for the daily. generate() lays out ground with
# a pit, a ladder of rise-2 platforms toward a flag platform, and a few
# floaters, all from one deterministic RNG stream. daily() proves each
# candidate beatable by farming a finishing bot run and mutates the seed
# until one passes — the same date therefore yields the same proven
# level on every device.

static func generate(seed_v: int, items: Array) -> SimLevel:
	var r := SimRNG.new(seed_v ^ 0x5EED)
	var g: Array = []
	for y in range(SimC.GH):
		var row: Array = []
		for x in range(SimC.GW):
			row.append("#" if (x == 0 or x == SimC.GW - 1) else ".")
		g.append(row)
	# ground with a pit
	var pit_x := 8 + r.below(6)
	var pit_w := 3 + r.below(3)
	for x in range(1, SimC.GW - 1):
		if x < pit_x or x >= pit_x + pit_w:
			g[13][x] = "#"
	# flag platform, top row 5..7
	var flag_y := 5 + r.below(3)
	for x in range(20, 25):
		g[flag_y][x] = "#"
	# ladder of rise-2 platforms from the ground toward the flag
	var x_cursor := 3 + r.below(3)
	var y_level := 11
	while y_level > flag_y:
		var w := 3 + r.below(2)
		if x_cursor + w > 18:
			x_cursor = 18 - w
		for x in range(x_cursor, x_cursor + w):
			g[y_level][x] = "#"
		x_cursor += w + 1 + r.below(3)
		y_level -= 2
	# up to two floaters in clear space
	for i in range(r.below(3)):
		var fx := 3 + r.below(14)
		var fy := 3 + r.below(8)
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
	lvl.spawn_py = 13 * SimC.FP
	lvl.flag_cx = 22 * SimC.FP + SimC.FP / 2
	lvl.flag_top = flag_y * SimC.FP - 157286   # 2.4 t of pole above the platform
	lvl.flag_bot = flag_y * SimC.FP
	lvl.safe = [[1, 9, 5, 5], [19, flag_y - 5, 7, 6]]
	return lvl

static func daily(seed_v: int) -> Dictionary:
	for attempt in range(30):
		var lvl := generate(seed_v + attempt * 7919, [])
		var proof := SimBot.farm_finishing(lvl, 100)
		if proof.size() > 0:
			return { "lvl": lvl, "attempt": attempt, "proof_len": proof.size() }
	# never expected; the classic level is the proven fallback
	return { "lvl": SimLevel.build([]), "attempt": -1, "proof_len": 0 }
