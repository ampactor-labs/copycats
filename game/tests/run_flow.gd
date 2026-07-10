extends SceneTree
# End-to-end flow: boots the real main scene headless and drives it with
# synthetic touch events (Input.parse_input_event), so the touch zones,
# scene flow, placement commit, and ghost/dunk paths all execute for real.
# godot --headless -s res://tests/run_flow.gd
#
# The ghost is "farmed": we search seeds for a right-running random-jump
# input log that genuinely finishes the level, then inject it as a
# round-1 roster entry. That doubles as a level-sanity property — chaotic
# play can beat the starter level.

func _initialize() -> void:
	var main_scene: Node = load("res://main.tscn").instantiate()
	root.add_child(main_scene)
	var d := Driver.new()
	d.main = main_scene
	root.add_child(d)

class Driver extends Node:
	const L := preload("res://tests/lib.gd")
	var main: Node
	var fails := 0
	var stage := "boot"
	var f := 0
	var waited := 0
	var farmed := PackedByteArray()
	var px0 := 0
	var moved := false

	func _ready() -> void:
		Engine.time_scale = 8.0

	func check(name: String, cond: bool, extra: String = "") -> void:
		if cond:
			print("ok   " + name)
		else:
			fails += 1
			var msg := "FAIL " + name
			if extra != "":
				msg += "  [" + extra + "]"
			print(msg)

	func _win(pos: Vector2) -> Vector2:
		# parse_input_event takes window coords; the engine inverse-stretches
		# them into the 832x480 canvas, so pre-apply the forward transform
		return main.get_viewport().get_screen_transform() * pos

	func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
		var e := InputEventScreenTouch.new()
		e.index = idx
		e.position = _win(pos)
		e.pressed = pressed
		Input.parse_input_event(e)

	func _drag(idx: int, pos: Vector2) -> void:
		var e := InputEventScreenDrag.new()
		e.index = idx
		e.position = _win(pos)
		Input.parse_input_event(e)

	func tap(pos: Vector2) -> void:
		_touch(0, pos, true)
		_touch(0, pos, false)

	func _finish() -> void:
		if fails == 0:
			print("\nFLOW OK")
		else:
			print("\n%d FLOW FAILURES" % fails)
		get_tree().quit(1 if fails > 0 else 0)

	func _bail(msg: String) -> void:
		check(msg, false, "stage=%s scene=%s f=%d" % [stage, str(main.scene), f])
		_finish()

	func _physics_process(_dt: float) -> void:
		f += 1
		if f > 30000:
			_bail("global timeout")
			return
		match stage:
			"boot":
				if f > 5:
					check("boots to title", str(main.scene) == "title", str(main.scene))
					tap(Vector2(416, 200))
					stage = "wait_cd"
			"wait_cd":
				if str(main.scene) == "countdown":
					check("tap starts round 1 countdown", true)
					stage = "wait_race"
				elif f > 600:
					_bail("no countdown after title tap")
			"wait_race":
				if str(main.scene) == "race":
					px0 = int(main.race.p.px)
					_touch(2, Vector2(100.0, 380.0), true)   # left thumb down
					_drag(2, Vector2(140.0, 380.0))          # slide right
					stage = "race1"
				elif f > 1200:
					_bail("countdown never became race")
			"race1":
				if str(main.scene) == "race" and not moved and int(main.race.p.px) > px0 + SimC.FP:
					moved = true
				if str(main.scene) == "recap":
					check("touch stick drove the player right", moved)
					check("round 1 ends in a death recap (pit)", bool(main.race.p.dead))
					_farm_and_inject()
					stage = "recap1"
				elif f > 6000:
					_bail("race 1 never resolved")
			"recap1":
				if str(main.scene) == "place":
					check("round 2 placement reached", int(main.m.round_n) == 2, str(main.m.round_n))
					check("offer has 3 cards", main.offer.size() == 3, str(main.offer))
					_place_saw_on_ghost_path()
					stage = "wait_race2"
				elif f > 8000:
					_bail("recap 1 never advanced")
			"wait_race2":
				if str(main.scene) == "race":
					if farmed.size() > 0:
						check("ghost present in race 2", main.race.ghost_streams.size() == 1)
						check("saw fate kills the ghost", int(main.race.fates[0].death) >= 0,
							str(main.race.fates))
					stage = "race2"
				elif f > 12000:
					_bail("race 2 never started")
			"race2":
				if str(main.scene) == "recap":
					check("round 2 resolved", true)
					check("dead player scores nothing for dunks",
						int(main.m.you) == 0 and int(main.m.foes) == 0,
						"you=%s foes=%s" % [str(main.m.you), str(main.m.foes)])
					stage = "recap2"
				elif f > 20000:
					_bail("race 2 never resolved")
			"recap2":
				if str(main.scene) == "place":
					check("round 3 placement reached", int(main.m.round_n) == 3, str(main.m.round_n))
					_finish()
				elif f > 26000:
					_bail("recap 2 never advanced")

	func _farm_and_inject() -> void:
		farmed = L.farm_finishing(300)
		if farmed.size() > 0:
			main.m.roster.append({ "inputs": farmed, "round": 1, "len": farmed.size() })
			check("farmed a finishing run (level beatable by chaotic play)", true)
		else:
			check("farmed a finishing run (level beatable by chaotic play)", false, "300 seeds, none finished")

	func _place_saw_on_ghost_path() -> void:
		var saw := {}
		if farmed.size() > 0:
			var lvl := SimLevel.build([])
			saw = L.saw_on_path(SimRace.resim(farmed, lvl), lvl)
			check("found a saw cell on the ghost path", not saw.is_empty())
		if saw.is_empty():
			saw = { "cx": 12, "cy": 6 }
		main.pending = { "type": "saw", "cx": saw.cx, "cy": saw.cy, "rot": 0 }
		main._commit_pending()
