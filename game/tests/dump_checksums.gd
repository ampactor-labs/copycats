extends SceneTree
# Writes the per-tick checksum trail that the cross-platform determinism
# matrix diffs byte-for-byte. Two scenarios: a physics soak over the
# standard item set, and a race against the canonical replay's ghost with
# a saw derived from its recorded path. Any platform producing a
# different file has divergent integer simulation — the one failure this
# architecture cannot absorb.
#
# godot --headless -s res://tests/dump_checksums.gd -- --out /path/out.tsv

const L := preload("res://tests/lib.gd")

func _initialize() -> void:
	var out_path := ""
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out_path = args[i + 1]
	if out_path == "":
		push_error("usage: -s res://tests/dump_checksums.gd -- --out FILE")
		quit(2)
		return

	var lines := PackedStringArray()
	lines.append("# copycats determinism dump\tsim_version=%d" % SimC.SIM_VERSION)

	# scenario 1: physics soak
	var log1 := L.rand_log(0xC41C, 900)
	var race1 := SimRace.create(L.test_items(), [])
	for t in range(log1.size()):
		race1.step(log1[t])
		lines.append("s1\t%d\t%d" % [t, race1.checksum()])
	lines.append("s1_final\t%d\t%d\t%d\t%d" % [race1.p.px, race1.p.py, race1.p.vx, race1.p.vy])

	# scenario 2: canonical ghost, saw on its path, fresh player log
	var f := FileAccess.open("res://tests/canonical/run_v1.chkr", FileAccess.READ)
	if f == null:
		push_error("canonical replay missing; mint with gen_canonical.gd --write")
		quit(3)
		return
	var dec := SimReplay.decode(f.get_buffer(f.get_length()))
	if dec.is_empty():
		push_error("canonical replay rejected (version mismatch?); re-mint after SIM_VERSION bump")
		quit(4)
		return
	var lvl0 := SimLevel.build([])
	var st := SimRace.resim(dec.inputs, lvl0)
	var saw := L.fan_on_path(st, lvl0)
	var items2: Array = []
	if not saw.is_empty():
		items2.append({ "type": "fan", "cx": saw.cx, "cy": saw.cy, "rot": 0, "round": 2 })
	var roster := [{ "inputs": dec.inputs, "round": 1, "len": int(st.len) }]
	var race2 := SimRace.create(items2, roster)
	lines.append("s2_fate\t%d\t%d" % [race2.fates[0].death, race2.fates[0].done])
	var log2 := L.rand_log(0xBEEF, 1200)
	for t in range(log2.size()):
		race2.step(log2[t])
		lines.append("s2\t%d\t%d" % [t, race2.checksum()])
	lines.append("s2_final\t%d\t%d\t%d\t%d" % [race2.p.px, race2.p.py, race2.p.vx, race2.p.vy])

	var out := FileAccess.open(out_path, FileAccess.WRITE)
	if out == null:
		push_error("cannot write " + out_path)
		quit(5)
		return
	out.store_string("\n".join(lines) + "\n")
	out.close()
	print("dumped %d lines -> %s" % [lines.size(), out_path])
	quit(0)
