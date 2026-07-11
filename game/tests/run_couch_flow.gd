extends SceneTree
# Couch versus flow: boots the real scene and plays a full 3-cat round
# through the shell — setup screen, three placements, three pass-the-
# phone runs (all pit deaths), the resolution playback, standings, and
# into round 2. godot --headless -s res://tests/run_couch_flow.gd

func _initialize() -> void:
	var main_scene: Node = load("res://main.tscn").instantiate()
	root.add_child(main_scene)
	var d := Driver.new()
	d.main = main_scene
	root.add_child(d)

class Driver extends Node:
	var main: Node
	var fails := 0
	var stage := "boot"
	var f := 0
	var runs_done := 0
	var stick_on := false

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
			print("\nCOUCH FLOW OK")
		else:
			print("\n%d COUCH FLOW FAILURES" % fails)
		get_tree().quit(1 if fails > 0 else 0)

	func _bail(msg: String) -> void:
		check(msg, false, "stage=%s scene=%s f=%d" % [stage, str(main.get("scene")), f])
		_finish()

	func _place(cx: int, cy: int) -> void:
		main.pending = { "type": "shelf", "cx": cx, "cy": cy, "rot": 0 }
		main._commit_pending()

	func _physics_process(_dt: float) -> void:
		f += 1
		if f > 40000:
			_bail("global timeout")
			return
		match stage:
			"boot":
				if f > 5:
					check("boots to title", str(main.scene) == "title", str(main.scene))
					tap(main._title_couch_rect().get_center())
					stage = "setup"
			"setup":
				if str(main.scene) == "couch":
					check("couch setup reached", true)
					tap(Vector2(416.0 + 120.0, 480.0 * 0.40 + 30.0))   # plus button -> 3 cats
					stage = "setup2"
				elif f > 600:
					_bail("no couch setup")
			"setup2":
				if int(main.vs_setup_n) == 3:
					check("player count steps to 3", true)
					tap(Vector2(416.0, 480.0 * 0.66 + 28.0))            # START
					stage = "placing"
				elif f > 1200:
					_bail("count never reached 3")
			"placing":
				if str(main.scene) == "place" and main.vs != null:
					var placed: int = main.vs.match_log[0].placements.size()
					if placed == 0:
						check("versus placement open, 3 players", int(main.vs.n_players) == 3)
						_place(12, 2)
					elif placed == 1:
						_place(5, 2)
					elif placed == 2:
						_place(16, 2)
				if str(main.scene) == "vs_hand":
					check("all placements in, handoff shown", true)
					stage = "run_race"
				elif f > 4000:
					_bail("placements never completed")
			"run_race":
				if str(main.scene) == "vs_hand":
					tap(Vector2(416.0, 100.0))
				elif str(main.scene) == "race":
					if not stick_on:
						_touch(2, Vector2(100.0, 380.0), true)
						_drag(2, Vector2(140.0, 380.0))
						stick_on = true
					stage = "in_race"
				elif str(main.scene) == "vs_resolve":
					stage = "resolve"
				elif f > 12000:
					_bail("handoff never became a race")
			"in_race":
				if str(main.scene) == "vs_hand":
					runs_done += 1
					stage = "run_race"
				elif str(main.scene) == "vs_resolve":
					runs_done += 1
					check("all three cats ran", runs_done == 3, str(runs_done))
					tap(Vector2(416.0, 240.0))   # speed up playback
					stage = "resolve"
				elif f > 20000:
					_bail("race never resolved")
			"resolve":
				if str(main.scene) == "vs_stand":
					check("standings reached", true)
					check("couch save written", FileAccess.file_exists("user://couch.save"))
					check("nobody scored (all pit deaths, inert shelves)",
						main.vs.scores == [0, 0, 0], str(main.vs.scores))
					tap(Vector2(416.0, 240.0))
					stage = "round2"
				elif f > 30000:
					_bail("playback never reached standings")
			"round2":
				if str(main.scene) == "place" and int(main.vs.round_n) == 2:
					check("round 2 placement reached", true)
					main._clear_couch_save()
					_finish()
				elif f > 36000:
					_bail("round 2 never started")
