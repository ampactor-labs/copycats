extends SceneTree
# Headless harness: godot --headless -s res://tests/run_tests.gd
# Unit checks on feel, then the determinism gates: same inputs twice ->
# identical checksums; resimulated replay == live run; golden replay.

const L := preload("res://tests/lib.gd")
var fails := 0
const GOLDEN := 2004298441   # canonical replay checksum; a mismatch means the sim changed -> bump SIM_VERSION

func check(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		print("ok   " + name)
	else:
		fails += 1
		var msg := "FAIL " + name
		if extra != "":
			msg += "  [" + extra + "]"
		print(msg)

func _initialize() -> void:
	test_jump_feel()
	test_run_speed()
	test_coyote_and_buffer()
	test_placement_rules()
	test_determinism()
	test_resim_matches_live()
	test_fates()
	test_scoring()
	test_replay_codec()
	test_gen()
	test_golden()
	if fails == 0:
		print("\nALL OK")
	else:
		print("\n%d FAILURES" % fails)
	quit(1 if fails > 0 else 0)

func test_jump_feel() -> void:
	var race := SimRace.create([], [])
	var min_py := race.p.py
	for t in range(90):
		race.step(L.mk(0, true))
		min_py = mini(min_py, race.p.py)
	var rise := SimLevel.SPAWN_PY - min_py
	check("jump apex near 3.3 tiles", rise > 200000 and rise < 220000, "rise=%d" % rise)
	check("player landed back", race.p.grounded and race.p.py == SimLevel.SPAWN_PY, "py=%d" % race.p.py)

func test_run_speed() -> void:
	var race := SimRace.create([], [])
	for t in range(60):
		race.step(L.mk(7, false))
	check("run speed capped at RUN_V", race.p.vx == SimC.RUN_V, "vx=%d" % race.p.vx)
	check("moved right", race.p.px > SimLevel.SPAWN_PX + 4 * SimC.FP, "px=%d" % race.p.px)

func test_coyote_and_buffer() -> void:
	# coyote: force airborne with a fresh coyote window; a jump must fire
	var race := SimRace.create([], [])
	race.p.grounded = false
	race.p.coyote = 3
	race.step(L.mk(0, true))
	check("coyote jump fires", race.p.vy < -19000, "vy=%d" % race.p.vy)
	# negative control: no coyote, no wall -> no jump
	var race2 := SimRace.create([], [])
	race2.p.grounded = false
	race2.p.coyote = 0
	race2.p.wallc = 0
	race2.step(L.mk(0, true))
	check("no coyote, no jump", race2.p.vy > -19000, "vy=%d" % race2.p.vy)
	# buffer: press while falling just above ground; jump fires on landing
	var race3 := SimRace.create([], [])
	race3.p.grounded = false
	race3.p.coyote = 0
	race3.p.py = SimLevel.SPAWN_PY - SimC.FP / 3
	race3.p.vy = 8000
	race3.step(L.mk(0, true))          # press now, still airborne
	var jumped := false
	for t in range(10):
		race3.step(L.mk(0, true))
		if race3.p.vy < -15000:
			jumped = true
			break
	check("buffered jump fires on landing", jumped, "vy=%d" % race3.p.vy)

func test_placement_rules() -> void:
	var lvl := SimLevel.build(L.test_items())
	check("reject wall cell", not lvl.place_valid("fan", 0, 5, 0))
	check("reject ground cell", not lvl.place_valid("fan", 4, 13, 0))
	check("reject spawn safe zone", not lvl.place_valid("fan", 3, 11, 0))
	check("reject flag safe zone", not lvl.place_valid("fan", 22, 4, 0))
	check("reject item overlap", not lvl.place_valid("fan", 8, 12, 0))
	check("accept open cell", lvl.place_valid("fan", 12, 6, 0))
	check("plank cells span 3", SimLevel.item_cells("shelf", 5, 5, 0).size() == 3)
	check("spikes rotate to vertical", SimLevel.item_size("cactus", 1) == Vector2i(1, 2))

func test_determinism() -> void:
	var log_b := L.rand_log(7, 1500)
	var sums_a := _run_collect(log_b)
	var sums_b := _run_collect(log_b)
	check("identical checksum trail", sums_a == sums_b,
		"a_end=%d b_end=%d" % [sums_a[sums_a.size() - 1], sums_b[sums_b.size() - 1]])

func _run_collect(log_b: PackedByteArray) -> Array:
	var race := SimRace.create(L.test_items(), [])
	var sums: Array = []
	for t in range(log_b.size()):
		race.step(log_b[t])
		if t % 100 == 0:
			sums.append(race.checksum())
	sums.append(race.checksum())
	return sums

func test_resim_matches_live() -> void:
	var log_b := L.rand_log(99, 1200)
	var race := SimRace.create(L.test_items(), [])
	var xs := PackedInt64Array()
	var ys := PackedInt64Array()
	for t in range(log_b.size()):
		if race.player_done():
			break
		race.step(log_b[t])
		xs.append(race.p.px)
		ys.append(race.p.py)
	var lvl := SimLevel.build(L.test_items())
	var st := SimRace.resim(race.inputs, lvl)
	var same: bool = int(st.len) == xs.size()
	if same:
		for i in range(st.len):
			if st.xs[i] != xs[i] or st.ys[i] != ys[i]:
				same = false
				break
	check("resimulated replay == live run", same,
		"live=%d resim=%d" % [xs.size(), st.len])

func test_fates() -> void:
	# any recorded stream works as a ghost; drop a saw on its path
	var log_b := L.rand_log(31, 600)
	var lvl1 := SimLevel.build([])
	var st := SimRace.resim(log_b, lvl1)
	var roster := [{ "inputs": log_b.slice(0, st.len), "round": 1, "len": st.len }]
	var placed := false
	var all_items: Array = []
	var t: int = int(st.len) / 3
	while t < st.len and not placed:
		var cx := SimC.fdiv(int(st.xs[t]))
		var cy := SimC.fdiv(int(st.ys[t]) - SimC.FP / 2)
		if lvl1.place_valid("fan", cx, cy, 0):
			all_items = [{ "type": "fan", "cx": cx, "cy": cy, "rot": 0, "round": 2 }]
			placed = true
		t += 5
	check("found saw cell on ghost path", placed)
	if not placed:
		return
	var race := SimRace.create(all_items, roster)
	check("newer saw kills the ghost", race.fates[0].death >= 0, str(race.fates[0]))
	var race_b := SimRace.create(all_items, roster)
	check("fate is stable across recompute", race.fates[0].death == race_b.fates[0].death)
	# same saw tagged round 1 must NOT kill the round-1 ghost
	var old_items := [{ "type": "fan", "cx": all_items[0].cx, "cy": all_items[0].cy, "rot": 0, "round": 1 }]
	var race_c := SimRace.create(old_items, roster)
	check("same-round saw spares the ghost", race_c.fates[0].death == -1, str(race_c.fates[0]))

func test_scoring() -> void:
	var f_dead := { "death": 10, "done": 10 }
	var f_alive := { "death": -1, "done": 500 }
	var s1 := SimMatch.score_round(true, [])
	check("first flag scores 1", s1.d_you == 1 and s1.key == "first")
	var s2 := SimMatch.score_round(true, [f_alive, f_alive])
	check("too easy scores 0", s2.d_you == 0 and s2.key == "too_easy")
	var s3 := SimMatch.score_round(true, [f_dead, f_dead, f_alive])
	check("finish + 2 dunks = 3", s3.d_you == 3 and s3.dunks == 2)
	var s4 := SimMatch.score_round(false, [f_dead, f_alive])
	check("death: survivor scores for horses", s4.d_foes == 1 and s4.key == "copycats")
	var s5 := SimMatch.score_round(false, [f_dead])
	check("wash scores 0", s5.d_you == 0 and s5.d_foes == 0 and s5.key == "wash")

func test_replay_codec() -> void:
	var inputs := L.rand_log(3, 321)
	var b := SimReplay.encode(4, inputs)
	var d := SimReplay.decode(b)
	check("codec roundtrip", d.has("inputs") and d.inputs == inputs and d.round == 4)
	b[4] = 0xEE   # corrupt version
	check("wrong version rejected", SimReplay.decode(b).is_empty())
	check("garbage rejected", SimReplay.decode(PackedByteArray([1, 2, 3])).is_empty())

func test_gen() -> void:
	var a := SimGen.generate(123, [])
	var b := SimGen.generate(123, [])
	check("gen deterministic", a.rows == b.rows)
	var c := SimGen.generate(124, [])
	check("gen varies by seed", a.rows != c.rows)
	var d := SimGen.daily(20260710)
	check("daily level proven beatable", int(d.attempt) >= 0 and int(d.proof_len) > 0, str(d))
	var lvl: SimLevel = d.lvl
	check("spawn stands on ground", lvl.solid_at(SimC.fdiv(lvl.spawn_px), SimC.fdiv(lvl.spawn_py)))
	check("flag sits on its platform", lvl.solid_at(SimC.fdiv(lvl.bowl_cx), SimC.fdiv(lvl.bowl_bot)))
	var log_b := SimBot.farm_finishing(lvl, 100)
	var st := SimRace.resim(log_b, lvl)
	check("bot finishes the generated level", bool(st.finished))
	var race := SimRace.create([], [{ "inputs": log_b, "round": 1, "len": int(st.len) }], lvl)
	check("generated-level ghost stream matches resim", int(race.ghost_streams[0].len) == int(st.len))
	var saw := L.fan_on_path(st, lvl)
	if not saw.is_empty():
		var race2 := SimRace.create([{ "type": "fan", "cx": saw.cx, "cy": saw.cy, "rot": 0, "round": 2 }],
			[{ "inputs": log_b, "round": 1, "len": int(st.len) }], lvl)
		check("saw dunks ghost on generated level", int(race2.fates[0].death) >= 0)

func test_golden() -> void:
	var log_b := L.rand_log(0xC41C, 900)
	var race := SimRace.create(L.test_items(), [])
	for t in range(log_b.size()):
		race.step(log_b[t])
	var sum := race.checksum()
	if GOLDEN == 0:
		print("     golden candidate: %d  (paste into GOLDEN to arm the gate)" % sum)
	else:
		check("golden replay checksum", sum == GOLDEN, "got %d want %d" % [sum, GOLDEN])
