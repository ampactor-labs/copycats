extends SceneTree
# Mints the canonical replay the determinism matrix re-simulates on every
# platform. Re-run with --write after any SIM_VERSION bump and commit the
# result: dump_checksums.gd strict-decodes it, so a stale canonical fails
# the matrix loudly instead of silently testing nothing (two-top lesson —
# the gate must reject its own demo on version drift).
#
# godot --headless -s res://tests/gen_canonical.gd -- --write

const L := preload("res://tests/lib.gd")
const PATH := "res://tests/canonical/run_v1.chkr"

func _initialize() -> void:
	var farmed := L.farm_finishing(500)
	if farmed.is_empty():
		push_error("no finishing bot run in 500 seeds; level or bot changed?")
		quit(1)
		return
	var bytes := SimReplay.encode(1, farmed)
	if OS.get_cmdline_user_args().has("--write"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/canonical"))
		var f := FileAccess.open(PATH, FileAccess.WRITE)
		f.store_buffer(bytes)
		f.close()
		print("wrote %s  (sim_version=%d, run len %d, %d bytes)" % [PATH, SimC.SIM_VERSION, farmed.size(), bytes.size()])
	else:
		print("candidate run: len %d, %d bytes; pass --write to mint %s" % [farmed.size(), bytes.size(), PATH])
	quit(0)
