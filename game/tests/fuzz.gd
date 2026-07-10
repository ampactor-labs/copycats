extends SceneTree
# Fuzz soak: N random matches, each with random valid placements and a
# random input log. Every match must (a) produce an identical checksum
# trail when run twice and (b) resimulate its own recorded replay
# position-for-position. Catches nondeterminism that a fixed golden
# can't — iteration-order dependence, uninitialized state, float leaks.
#
# godot --headless -s res://tests/fuzz.gd -- --runs 50

const L := preload("res://tests/lib.gd")

func _initialize() -> void:
	var runs := 25
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--runs" and i + 1 < args.size():
			runs = int(args[i + 1])
	var fails := 0
	for k in range(runs):
		var seed_v := 1000 + k
		var items := _random_items(seed_v)
		var log_b := L.rand_log(seed_v, 1200)
		if _trail(items, log_b) != _trail(items, log_b):
			fails += 1
			print("FAIL fuzz %d: checksum trail diverges between identical runs" % seed_v)
		if not _resim_ok(items, log_b):
			fails += 1
			print("FAIL fuzz %d: resim does not reproduce the live run" % seed_v)
	if fails == 0:
		print("FUZZ OK  (%d matches, %d checks)" % [runs, runs * 2])
	else:
		print("%d FUZZ FAILURES" % fails)
	quit(1 if fails > 0 else 0)

func _random_items(seed_v: int) -> Array:
	var r := SimRNG.new(seed_v * 7919)
	var items: Array = []
	var want := 2 + r.below(4)
	for j in range(want):
		var type: String = SimMatch.POOL[r.below(SimMatch.POOL.size())]
		var rots: int = int(SimLevel.DEFS[type].rots)
		for attempt in range(40):
			var cx := 1 + r.below(SimC.GW - 2)
			var cy := 1 + r.below(SimC.GH - 3)
			var rot := r.below(rots)
			if SimLevel.build(items).place_valid(type, cx, cy, rot):
				items.append({ "type": type, "cx": cx, "cy": cy, "rot": rot, "round": 1 + (j % 3) })
				break
	return items

func _trail(items: Array, log_b: PackedByteArray) -> Array:
	var race := SimRace.create(items, [])
	var sums: Array = []
	for t in range(log_b.size()):
		race.step(log_b[t])
		if t % 100 == 0:
			sums.append(race.checksum())
	sums.append(race.checksum())
	return sums

func _resim_ok(items: Array, log_b: PackedByteArray) -> bool:
	var race := SimRace.create(items, [])
	var xs := PackedInt64Array()
	var ys := PackedInt64Array()
	for t in range(log_b.size()):
		if race.player_done():
			break
		race.step(log_b[t])
		xs.append(race.p.px)
		ys.append(race.p.py)
	var st := SimRace.resim(race.inputs, SimLevel.build(items))
	if int(st.len) != xs.size():
		return false
	for i in range(int(st.len)):
		if st.xs[i] != xs[i] or st.ys[i] != ys[i]:
			return false
	return true
