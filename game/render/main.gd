extends Node2D
# The whole presentation shell: scene flow, touch/keyboard input, juice,
# and immediate-mode drawing of sim state. Everything cosmetic lives
# here; the sim never sees floats, this file never mutates sim state
# except by feeding input bytes and advancing the round flow.

const TILE := 32.0
const W := 832.0
const H := 480.0

# gruvbox; meaning rides blue<->orange only, shapes double-encode hazards
const C_VOID := Color("141617")
const C_BG := Color("1d2021")
const C_TILE := Color("3c3836")
const C_TILE_TOP := Color("504945")
const C_TILE_EDGE := Color("665c54")
const C_TEXT := Color("ebdbb2")
const C_DIM := Color("a89984")
const C_FAINT := Color("7c6f64")
const C_YOU := Color("fabd2f")
const C_YOU_DK := Color("d79921")
const C_GHOST := Color("83a598")
const C_GOAL := Color("83a598")
const C_SPRING := Color("458588")
const C_SPRING_HI := Color("8ec5c5")
const C_HAZ := Color("fe8019")
const C_HAZ_DK := Color("d65d0e")
const C_WOOD := Color("bdae93")
const C_WOOD_DK := Color("a89984")

# pelt roster for couch versus; names are the identity system, colors are flavor
const PELTS := [
	{ "name": "ORANGE", "body": Color("fabd2f"), "dark": Color("d79921") },
	{ "name": "SOOT", "body": Color("928374"), "dark": Color("665c54") },
	{ "name": "PEARL", "body": Color("ebdbb2"), "dark": Color("a89984") },
	{ "name": "COCOA", "body": Color("a9744f"), "dark": Color("7c5136") },
	{ "name": "TUXEDO", "body": Color("504945"), "dark": Color("32302f") },
	{ "name": "BUTTER", "body": Color("d8a657"), "dark": Color("b47109") },
	{ "name": "CREAM", "body": Color("d5c4a1"), "dark": Color("bdae93") },
	{ "name": "GINGER", "body": Color("e78a4e"), "dark": Color("c35e0e") },
]
const COUCH_SAVE := "user://couch.save"

var scene := "title"
var m: SimMatch
var race: SimRace
var place_level: SimLevel
var vs: SimVersus = null
var vs_placer := -1
var vs_runner := -1
var vs_setup_n := 2
var playback := {}
var standings_res := {}
var offer: Array = []
var dragging := {}
var pending := {}
var recap := {}
var over_won := false
var cd_ticks := 0

var elapsed := 0.0
var fxp: Array = []
var pops: Array = []
var banner := {}
var shake := 0.0
var shk_v := Vector2.ZERO
var hitstop := 0
var sq := 0.0
var run_ph := 0.0
var prev_px := 0.0
var prev_py := 0.0
var cur_px := 0.0
var cur_py := 0.0
var cushion_hits := {}
var ghost_trail: Array = []

var touches := {}
var stick := {}
var jump_touch := {}
var down_pulse := 0
var debug_on := false

const AudioLib := preload("res://render/audio.gd")
var audio: Node
var muted := false
var best_rounds := 0
var daily_mode := false
var daily_key := ""
var daily_date := ""
var daily_best_today := 0
var font_v: Font

func _ready() -> void:
	font_v = ThemeDB.fallback_font
	RenderingServer.set_default_clear_color(C_VOID)
	audio = AudioLib.new()
	add_child(audio)
	_load_cfg()
	audio.muted = muted

func _today() -> Dictionary:
	var d := Time.get_datetime_dict_from_system(true)
	var num: int = d.year * 10000 + d.month * 100 + d.day
	return { "num": num, "key": "daily_%d" % num, "date": "%04d-%02d-%02d" % [d.year, d.month, d.day] }

func _load_cfg() -> void:
	var c := ConfigFile.new()
	if c.load("user://copycats.cfg") == OK:
		muted = bool(c.get_value("s", "muted", false))
		best_rounds = int(c.get_value("s", "best", 0))
		daily_best_today = int(c.get_value("d", String(_today().key), 0))

func _save_cfg() -> void:
	var c := ConfigFile.new()
	c.load("user://copycats.cfg")
	c.set_value("s", "muted", muted)
	c.set_value("s", "best", best_rounds)
	if daily_key != "" and daily_best_today > 0:
		c.set_value("d", daily_key, daily_best_today)
	c.save("user://copycats.cfg")

# ---------- match flow ----------

func _start_match(daily: bool = false) -> void:
	vs = null
	daily_mode = daily
	if daily:
		var t := _today()
		daily_key = t.key
		daily_date = t.date
		m = SimMatch.new(int(t.num))
		m.template = SimGen.daily(int(t.num)).lvl
	else:
		m = SimMatch.new(randi() & 0x7FFFFFFF)
	_next_round()

func _next_round() -> void:
	pending = {}
	dragging = {}
	var rd := m.begin_round()
	if rd.place:
		offer = rd.offer
		place_level = SimLevel.derive(m.base_level(), m.items)
		scene = "place"
		if m.round_n == 2:
			_set_banner([["KNOCK SOMETHING OVER", C_TEXT]], 1.8, "your last life races you as a copycat. swat it.")
		else:
			_set_banner([["KNOCK SOMETHING OVER", C_TEXT]], 1.2, "")
	else:
		_begin_race()
		_set_banner([["GET TO DINNER", C_TEXT]], 1.8, "left thumb: move    right thumb: jump")

func _begin_race() -> void:
	race = m.make_race()
	cushion_hits = {}
	ghost_trail = []
	for i in range(race.ghost_streams.size()):
		ghost_trail.append([])
	cur_px = px_of(race.p.px)
	cur_py = px_of(race.p.py)
	prev_px = cur_px
	prev_py = cur_py
	sq = 0.0
	run_ph = 0.0
	cd_ticks = 120
	scene = "countdown"

func _commit_pending() -> void:
	var s := SimLevel.item_size(pending.type, int(pending.rot))
	burst((pending.cx + s.x * 0.5) * TILE, (pending.cy + 0.5) * TILE, C_TEXT, 10, 3.0)
	audio.play("place")
	if in_vs():
		vs.commit_item(vs_placer, pending.type, int(pending.cx), int(pending.cy), int(pending.rot))
		pending = {}
		_vs_after_place()
		return
	m.commit_item(pending.type, pending.cx, pending.cy, pending.rot)
	pending = {}
	_begin_race()

func _end_round() -> void:
	var res := m.finish_race(race)
	recap = { "res": res, "t": 0.0 }
	if res.score.key == "too_easy":
		audio.play("too_easy")
	scene = "recap"

func _after_recap() -> void:
	var res: Dictionary = recap.res
	if res.over:
		over_won = res.won
		if over_won:
			if daily_mode:
				if daily_best_today == 0 or m.round_n < daily_best_today:
					daily_best_today = m.round_n
					_save_cfg()
			elif best_rounds == 0 or m.round_n < best_rounds:
				best_rounds = m.round_n
				_save_cfg()
			audio.play("win")
		else:
			audio.play("lose")
		scene = "over"
	else:
		_next_round()

# ---------- couch versus flow ----------

func in_vs() -> bool:
	return vs != null

func _pelt_name(i: int) -> String:
	return String(PELTS[i].name)

func _start_couch(n: int) -> void:
	vs = SimVersus.new(randi() & 0x7FFFFFFF, n)
	_vs_begin_placement()

func _resume_couch() -> void:
	var f := FileAccess.open(COUCH_SAVE, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		_clear_couch_save()
		return
	var loaded := SimVersus.deserialize(parsed)
	if loaded == null:
		_clear_couch_save()
		return
	vs = loaded
	_vs_begin_placement()

func _save_couch() -> void:
	var f := FileAccess.open(COUCH_SAVE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(vs.serialize()))
		f.close()

func _clear_couch_save() -> void:
	if FileAccess.file_exists(COUCH_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(COUCH_SAVE))

func _vs_begin_placement() -> void:
	vs.begin_round()
	pending = {}
	dragging = {}
	vs_placer = vs.first_placer()
	_vs_place_turn()

func _vs_place_turn() -> void:
	offer = vs.draw_offer()
	place_level = SimLevel.derive(vs.base_level(), vs.items)
	scene = "place"
	_set_banner([[_pelt_name(vs_placer) + ": KNOCK SOMETHING OVER", C_TEXT]], 1.4, "")

func _vs_after_place() -> void:
	var placed: int = vs.match_log[vs.round_n - 1].placements.size()
	if placed < vs.n_players:
		vs_placer = (vs.first_placer() + placed) % vs.n_players
		_vs_place_turn()
	else:
		vs_runner = vs.first_placer()
		scene = "vs_hand"

func _begin_race_vs() -> void:
	race = vs.make_race()
	cushion_hits = {}
	ghost_trail = []
	for i in range(race.ghost_streams.size()):
		ghost_trail.append([])
	cur_px = px_of(race.p.px)
	cur_py = px_of(race.p.py)
	prev_px = cur_px
	prev_py = cur_py
	sq = 0.0
	run_ph = 0.0
	cd_ticks = 120
	scene = "countdown"
	_set_banner([[_pelt_name(vs_runner) + ": GET TO DINNER", C_TEXT]], 1.6, "")

func _vs_after_run() -> void:
	vs.submit_entry(vs_runner, race.inputs.duplicate())
	if not vs.entries_done():
		var done: int = vs.match_log[vs.round_n - 1].entries.size()
		vs_runner = (vs.first_placer() + done) % vs.n_players
		scene = "vs_hand"
	else:
		standings_res = vs.resolve_round()
		_save_couch()
		if bool(standings_res.over):
			_clear_couch_save()
		_start_playback()

func _start_playback() -> void:
	var max_t := 0
	for v in standings_res.entry_views:
		max_t = maxi(max_t, int(v.stream.len))
	for g in standings_res.ghost_views:
		var d: int = int(g.death)
		max_t = maxi(max_t, d if d >= 0 else int(g.stream.len))
	playback = { "tick": 0, "speed": 1, "max_t": max_t, "ev_i": 0 }
	scene = "vs_resolve"
	_set_banner([["THE ROUND, ALL AT ONCE", C_TEXT]], 1.2, "tap to speed up")

func _playback_step() -> void:
	for s in range(int(playback.speed)):
		playback.tick = int(playback.tick) + 1
		var evs: Array = standings_res.events
		while int(playback.ev_i) < evs.size() and int(evs[playback.ev_i].tick) <= int(playback.tick):
			_playback_event(evs[playback.ev_i])
			playback.ev_i = int(playback.ev_i) + 1
	if int(playback.tick) > int(playback.max_t) + 50:
		scene = "vs_stand"

func _playback_event(ev: Dictionary) -> void:
	var kind := String(ev.kind)
	var ex := px_of(int(ev.x))
	var ey := px_of(int(ev.y)) - 26.0
	if kind == "finish":
		audio.play("finish")
		burst(ex, ey, C_GOAL, 16, 6.0)
		pop(ex, ey, _pelt_name(int(ev.who)) + ": DINNER", C_YOU)
	elif kind == "swat":
		audio.play("swat")
		shake = maxf(shake, 5.0)
		burst(ex, ey, PELTS[int(ev.who)].body, 18, 7.0)
		pop(ex, ey, "%s SWATS %s" % [_pelt_name(int(ev.by)), _pelt_name(int(ev.who))], C_HAZ)
	elif kind == "gswat":
		audio.play("swat")
		shake = maxf(shake, 4.0)
		burst(ex, ey, C_GHOST, 14, 6.0)
		pop(ex, ey, "%s SWATS %s'S ECHO" % [_pelt_name(int(ev.by)), _pelt_name(int(ev.who))], C_HAZ)
	elif kind == "die":
		audio.play("die")
		burst(ex, ey, PELTS[int(ev.who)].body, 14, 6.0)
		pop(ex, ey, _pelt_name(int(ev.who)) + " ATE IT", C_DIM)

# ---------- ticking ----------

func _physics_process(_dt: float) -> void:
	if scene == "countdown":
		var n0 := (cd_ticks + 59) / 60
		cd_ticks -= 1
		var n1 := (cd_ticks + 59) / 60
		if n1 != n0 and cd_ticks > 0:
			audio.play("tick")
		if cd_ticks <= 0:
			scene = "race"
			_set_banner([["GO!", C_YOU]], 0.5, "")
			audio.play("go")
	elif scene == "race":
		if hitstop > 0:
			hitstop -= 1
			return
		var steps := 1
		if race.player_done() and not race.ghosts_done():
			steps = 3
		for s in range(steps):
			prev_px = cur_px
			prev_py = cur_py
			race.step(_input_byte())
			cur_px = px_of(race.p.px)
			cur_py = px_of(race.p.py)
			_drain_events()
			_push_trails()
			if race.resolved():
				if in_vs():
					_vs_after_run()
				else:
					_end_round()
				break
		if down_pulse > 0:
			down_pulse -= 1
	elif scene == "vs_resolve":
		_playback_step()

func _input_byte() -> int:
	var axis := 0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		axis -= 7
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		axis += 7
	if not stick.is_empty() and touches.has(stick.index):
		var t: Dictionary = touches[stick.index]
		var dx: float = t.pos.x - float(stick.anchor)
		var lever := TILE * 1.15
		var mag := absf(dx) / lever
		if mag > 0.16:
			var a := signf(dx) * minf(1.0, (mag - 0.16) / 0.84)
			axis = clampi(roundi(a * 7.0), -7, 7)
		else:
			axis = 0
	var jump := Input.is_physical_key_pressed(KEY_SPACE) \
		or Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP) \
		or jump_touch.size() > 0
	var down := Input.is_physical_key_pressed(KEY_S) \
		or Input.is_physical_key_pressed(KEY_DOWN) or down_pulse > 0
	var b := clampi(axis, -7, 7) + 7
	if jump:
		b |= SimC.BIT_JUMP
	if down:
		b |= SimC.BIT_DOWN
	return b

func _drain_events() -> void:
	for e in race.events:
		match e.t:
			"jump":
				sq = -0.25
				dust(px_of(e.x), px_of(e.y), 4)
				audio.play("jump")
			"land":
				sq = 0.3
				dust(px_of(e.x), px_of(e.y), 5)
				audio.play("land")
			"cushion":
				sq = -0.4
				cushion_hits[e.i] = race.tick
				dust(px_of(e.x), px_of(e.y), 8)
				audio.play("cushion")
			"die":
				hitstop = 7
				shake = 9.0
				burst(px_of(e.x), px_of(e.y) - 13.0, C_YOU, 22, 8.0)
				burst(px_of(e.x), px_of(e.y) - 13.0, C_HAZ, 10, 6.0)
				audio.play("die")
			"finish":
				burst(px_of(race.level.bowl_cx), px_of(race.level.bowl_top), C_GOAL, 26, 7.0)
				burst(px_of(race.level.bowl_cx), px_of(race.level.bowl_top), C_YOU, 18, 6.0)
				audio.play("finish")
			"swat":
				burst(px_of(e.x), px_of(e.y) - 13.0, C_GHOST, 18, 6.0)
				pop(px_of(e.x), px_of(e.y) - 27.0, "SWATTED", C_HAZ)
				shake = maxf(shake, 5.0)
				audio.play("swat")
			"gfinish":
				burst(px_of(race.level.bowl_cx), px_of(race.level.bowl_top), C_GHOST, 12, 5.0)
			"time":
				pop(px_of(e.x), px_of(e.y) - 45.0, "TIME!", C_HAZ)
	race.events.clear()

func _push_trails() -> void:
	if race.tick % 4 != 0:
		return
	for i in range(race.ghost_streams.size()):
		var t := race.tick - 1
		var st: Dictionary = race.ghost_streams[i]
		var f: Dictionary = race.fates[i]
		if t < 0 or t >= int(st.len):
			continue
		if f.death >= 0 and t > int(f.death):
			continue
		var tr: Array = ghost_trail[i]
		tr.append(Vector2(px_of(st.xs[t]), px_of(st.ys[t])))
		if tr.size() > 3:
			tr.pop_front()

func _process(dt: float) -> void:
	elapsed += dt
	shake *= pow(0.0005, dt)
	sq *= pow(0.001, dt)
	if scene == "race" and race != null and race.p.grounded:
		run_ph += dt * absf(race.p.vx) * 60.0 / 65536.0 * 1.6
	var alive: Array = []
	for p in fxp:
		p.t += dt
		if p.t < p.life:
			p.x += p.vx * dt * TILE / 6.0
			p.y += p.vy * dt * TILE / 6.0
			p.vy += p.grav * dt
			alive.append(p)
	fxp = alive
	var alive_pops: Array = []
	for p in pops:
		p.t += dt
		if p.t < 1.0:
			alive_pops.append(p)
	pops = alive_pops
	if not banner.is_empty():
		banner.t += dt
		if banner.t > banner.dur:
			banner = {}
	if scene == "recap":
		recap.t += dt
		if recap.t > 2.4:
			_after_recap()
	queue_redraw()

# ---------- input events ----------

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
	elif event is InputEventScreenDrag:
		_touch_move(event.index, event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F1:
			debug_on = not debug_on
		elif event.physical_keycode == KEY_ENTER:
			if scene == "title":
				audio.play("ui")
				_start_match(false)
			elif scene == "over":
				audio.play("ui")
				_start_match(daily_mode)
			elif scene == "recap" and recap.t > 0.4:
				_after_recap()

func _touch_down(i: int, pos: Vector2) -> void:
	var zone := "ui"
	if scene == "race" or scene == "countdown":
		zone = "move" if pos.x < W * 0.42 else "jump"
	touches[i] = { "pos": pos, "start": pos, "ms": Time.get_ticks_msec(), "zone": zone }
	match scene:
		"title":
			if absf(pos.x - W / 2.0) < 80.0 and absf(pos.y - H * 0.88) < 20.0:
				muted = not muted
				audio.muted = muted
				_save_cfg()
				if not muted:
					audio.play("ui")
			elif _title_play_rect().has_point(pos):
				audio.play("ui")
				vs = null
				_start_match(false)
			elif _title_couch_rect().has_point(pos):
				audio.play("ui")
				scene = "couch"
			elif _title_daily_rect().has_point(pos):
				audio.play("ui")
				vs = null
				_start_match(true)
		"couch":
			_couch_down(pos)
		"vs_hand":
			audio.play("ui")
			_begin_race_vs()
		"vs_resolve":
			playback.speed = 3 if int(playback.speed) == 1 else 1
		"vs_stand":
			audio.play("ui")
			if bool(standings_res.over):
				vs = null
				scene = "title"
			else:
				_vs_begin_placement()
		"over":
			audio.play("ui")
			_start_match(daily_mode)
		"recap":
			if recap.t > 0.7:
				_after_recap()
		"place":
			_place_down(pos)
		"race", "countdown":
			if zone == "move":
				stick = { "index": i, "anchor": pos.x, "y": pos.y }
			else:
				jump_touch[i] = true

func _couch_down(pos: Vector2) -> void:
	if Rect2(20, 16, 90, 40).has_point(pos):
		audio.play("ui")
		scene = "title"
		return
	if Rect2(W / 2.0 - 150.0, H * 0.40, 60, 60).has_point(pos):
		vs_setup_n = maxi(2, vs_setup_n - 1)
		audio.play("ui")
		return
	if Rect2(W / 2.0 + 90.0, H * 0.40, 60, 60).has_point(pos):
		vs_setup_n = mini(SimVersus.MAX_PLAYERS, vs_setup_n + 1)
		audio.play("ui")
		return
	if Rect2(W / 2.0 - 130.0, H * 0.66, 260, 56).has_point(pos):
		audio.play("ui")
		_start_couch(vs_setup_n)
		return
	if FileAccess.file_exists(COUCH_SAVE) and Rect2(W / 2.0 - 130.0, H * 0.80, 260, 44).has_point(pos):
		audio.play("ui")
		_resume_couch()

func _touch_move(i: int, pos: Vector2) -> void:
	if touches.has(i):
		var t: Dictionary = touches[i]
		t.pos = pos
		if t.zone == "move" and not stick.is_empty() and int(stick.index) == i:
			var lever := TILE * 1.15
			var dx := pos.x - float(stick.anchor)
			if absf(dx) > lever:
				stick.anchor = pos.x - signf(dx) * lever
			stick.y = pos.y
		if t.zone == "jump" and pos.y - t.start.y > 34.0 \
				and Time.get_ticks_msec() - int(t.ms) < 260:
			down_pulse = 8
			t.start = Vector2(pos.x, 99999.0)
	if scene == "place" and not dragging.is_empty():
		_drag_move(pos)

func _touch_up(i: int) -> void:
	if touches.has(i):
		if touches[i].zone == "jump":
			jump_touch.erase(i)
		if not stick.is_empty() and int(stick.index) == i:
			stick = {}
		touches.erase(i)
	if scene == "place" and not dragging.is_empty():
		_drag_drop()

# ---------- placement ----------

func _card_rect(i: int) -> Rect2:
	var total := 3.0 * 118.0 + 2.0 * 14.0
	return Rect2((W - total) / 2.0 + i * 132.0, H - 92.0, 118.0, 80.0)

func _place_down(pos: Vector2) -> void:
	if not pending.is_empty():
		var b := _pending_buttons()
		if pos.distance_to(b.ok) < 30.0:
			_commit_pending()
			return
		if b.has("rot") and pos.distance_to(b.rot) < 30.0:
			pending.rot = (int(pending.rot) + 1) % int(SimLevel.DEFS[pending.type].rots)
			audio.play("rotate")
			return
		if pos.distance_to(b.no) < 30.0:
			offer.append(pending.type)
			pending = {}
			audio.play("ui")
			return
		var r := _cells_rect_px(SimLevel.item_cells(pending.type, pending.cx, pending.cy, pending.rot)).grow(10.0)
		if r.has_point(pos):
			dragging = { "type": pending.type, "rot": pending.rot, "x": pos.x, "y": pos.y }
			pending = {}
			_drag_move(pos)
			return
	for i in range(offer.size()):
		if _card_rect(i).has_point(pos):
			dragging = { "type": offer[i], "rot": 0, "x": pos.x, "y": pos.y }
			offer.remove_at(i)
			audio.play("ui")
			_drag_move(pos)
			return

func _drag_move(pos: Vector2) -> void:
	dragging.x = pos.x
	dragging.y = pos.y
	var s := SimLevel.item_size(dragging.type, int(dragging.rot))
	var lift := 1.6 * TILE
	dragging.cx = roundi(pos.x / TILE - s.x / 2.0)
	dragging.cy = roundi((pos.y - lift) / TILE - s.y / 2.0)
	dragging.valid = place_level.place_valid(dragging.type, int(dragging.cx), int(dragging.cy), int(dragging.rot))

func _drag_drop() -> void:
	if bool(dragging.valid):
		pending = { "type": dragging.type, "cx": dragging.cx, "cy": dragging.cy, "rot": dragging.rot }
		audio.play("ui")
	else:
		offer.append(dragging.type)
		audio.play("too_easy")
	dragging = {}

func _cells_rect_px(cells: Array) -> Rect2:
	var x0 := 99.0
	var y0 := 99.0
	var x1 := -1.0
	var y1 := -1.0
	for c in cells:
		x0 = minf(x0, c.x)
		y0 = minf(y0, c.y)
		x1 = maxf(x1, c.x + 1.0)
		y1 = maxf(y1, c.y + 1.0)
	return Rect2(x0 * TILE, y0 * TILE, (x1 - x0) * TILE, (y1 - y0) * TILE)

func _pending_buttons() -> Dictionary:
	var r := _cells_rect_px(SimLevel.item_cells(pending.type, pending.cx, pending.cy, pending.rot))
	var mx := r.position.x + r.size.x / 2.0
	var by := r.position.y - 46.0
	if by < 40.0:
		by = r.position.y + r.size.y + 46.0
	var has_rot: bool = int(SimLevel.DEFS[pending.type].rots) > 1
	var spread := 64.0 if has_rot else 44.0
	var out := {
		"ok": Vector2(clampf(mx + spread, 40.0, W - 40.0), by),
		"no": Vector2(clampf(mx - spread, 40.0, W - 40.0), by),
	}
	if has_rot:
		out["rot"] = Vector2(clampf(mx, 40.0, W - 40.0), by)
	return out

# ---------- fx helpers ----------

func px_of(v: int) -> float:
	return v / 2048.0

func burst(x: float, y: float, col: Color, n: int, spd: float) -> void:
	for i in range(n):
		var a := randf() * TAU
		var v := (0.3 + randf()) * spd
		fxp.append({ "x": x, "y": y, "vx": cos(a) * v, "vy": sin(a) * v - 3.0,
			"life": 0.5 + randf() * 0.4, "t": 0.0, "col": col, "sz": 2.0 + randf() * 3.0, "grav": 24.0 })

func dust(x: float, y: float, n: int) -> void:
	for i in range(n):
		fxp.append({ "x": x + (randf() - 0.5) * 16.0, "y": y, "vx": (randf() - 0.5) * 3.0,
			"vy": -randf() * 1.5, "life": 0.35, "t": 0.0, "col": C_DIM, "sz": 2.0, "grav": -2.0 })

func pop(x: float, y: float, s: String, col: Color) -> void:
	pops.append({ "x": x, "y": y, "txt": s, "col": col, "t": 0.0 })

func _set_banner(lines: Array, dur: float, sub: String) -> void:
	banner = { "lines": lines, "dur": dur, "sub": sub, "t": 0.0 }

func ca(col: Color, alpha: float) -> Color:
	return Color(col.r, col.g, col.b, col.a * alpha)

# ---------- drawing ----------

func txt_c(x: float, y: float, s: String, size: int, col: Color) -> void:
	draw_string(font_v, Vector2(x - 400.0, y), s, HORIZONTAL_ALIGNMENT_CENTER, 800.0, size, col)

func txt_l(x: float, y: float, s: String, size: int, col: Color) -> void:
	draw_string(font_v, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func rect(x: float, y: float, w: float, h: float, col: Color) -> void:
	draw_rect(Rect2(Vector2(x, y) + shk_v, Vector2(w, h)), col)

func _draw() -> void:
	shk_v = Vector2((randf() - 0.5) * shake, (randf() - 0.5) * shake)
	draw_rect(Rect2(0, 0, W, H), C_BG)
	for y in range(1, SimC.GH, 2):
		for x in range(1, SimC.GW, 2):
			draw_rect(Rect2(x * TILE + 15, y * TILE + 15, 2, 2), Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, 0.025))
	if scene == "title":
		_draw_title()
		return
	if scene == "couch":
		_draw_couch()
		return
	var lvl := _current_level()
	if lvl == null:
		return
	_draw_level(lvl)
	_draw_world_items(lvl)
	_draw_bowl(lvl)
	if scene == "vs_resolve":
		for a in SimRace.balls_at(race.tracks, int(playback.tick)):
			_draw_ball(px_of(a.xc), px_of(a.yc), int(a.dir))
		_draw_playback_cats()
	else:
		if race != null and scene != "place":
			for a in SimRace.balls_at(race.tracks, maxi(race.tick - 1, 0)):
				_draw_ball(px_of(a.xc), px_of(a.yc), int(a.dir))
		_draw_ghosts()
		if race != null and scene != "place" and scene != "vs_hand" and scene != "vs_stand" and not race.p.dead:
			var alpha := Engine.get_physics_interpolation_fraction()
			var dx := lerpf(prev_px, cur_px, alpha)
			var dy := lerpf(prev_py, cur_py, alpha)
			_draw_cat(dx, dy, race.p.face, 1.0, 1.0, true, vs_runner if in_vs() else 0)
	for p in fxp:
		draw_rect(Rect2(Vector2(p.x - p.sz / 2.0, p.y - p.sz / 2.0) + shk_v, Vector2(p.sz, p.sz)), ca(p.col, 1.0 - p.t / p.life))
	for p in pops:
		txt_c(p.x, p.y - p.t * 30.0, p.txt, 15, ca(p.col, 1.0 - p.t))
	_draw_hud()
	if scene == "place":
		_draw_place_ui()
	elif scene == "countdown":
		var n := (cd_ticks + 59) / 60
		var ph := 1.0 - fmod(cd_ticks / 60.0, 1.0)
		txt_c(W / 2.0, H / 2.0 - 30.0, str(n), int(64 + ph * 20.0), ca(C_TEXT, 1.0 - ph * 0.5))
	elif scene == "recap":
		_draw_recap()
	elif scene == "over":
		_draw_over()
	elif scene == "vs_hand":
		_draw_handoff()
	elif scene == "vs_stand":
		_draw_standings()
	_draw_banner()
	if debug_on:
		_draw_debug()

func _current_level() -> SimLevel:
	if scene == "place":
		return place_level
	if race != null:
		return race.level
	if scene == "vs_hand" and place_level != null:
		return place_level
	return null

func _draw_playback_cats() -> void:
	var t := int(playback.tick)
	for g in standings_res.ghost_views:
		var st: Dictionary = g.stream
		var d := int(g.death)
		if d >= 0 and t > d:
			continue
		var idx := mini(t, int(st.len) - 1)
		_draw_copycat(px_of(st.xs[idx]), px_of(st.ys[idx]), int(st.faces[idx]), 0.4)
	for v in standings_res.entry_views:
		var st: Dictionary = v.stream
		var last := int(st.len) - 1
		if t > last:
			continue
		var idx := mini(t, last)
		var pi := int(v.player)
		_draw_cat(px_of(st.xs[idx]), px_of(st.ys[idx]), int(st.faces[idx]), 1.0, 1.0, false, pi)
		txt_c(px_of(st.xs[idx]), px_of(st.ys[idx]) - 46.0, _pelt_name(pi), 10, PELTS[pi].body)

func _draw_couch() -> void:
	var cx := W / 2.0
	txt_l(24.0, 42.0, "< back", 14, C_DIM)
	txt_c(cx, H * 0.16, "COUCH", 40, C_TEXT)
	txt_c(cx, H * 0.16 + 26.0, "pass one screen around. every cat runs the same house.", 13, C_DIM)
	draw_rect(Rect2(cx - 150.0, H * 0.40, 60, 60), C_TILE)
	txt_c(cx - 120.0, H * 0.40 + 38.0, "-", 30, C_TEXT)
	draw_rect(Rect2(cx + 90.0, H * 0.40, 60, 60), C_TILE)
	txt_c(cx + 120.0, H * 0.40 + 38.0, "+", 30, C_TEXT)
	txt_c(cx, H * 0.40 + 42.0, "%d CATS" % vs_setup_n, 32, C_YOU)
	for i in range(vs_setup_n):
		var px0 := cx - (vs_setup_n - 1) * 24.0 + i * 48.0
		_draw_cat(px0, H * 0.60, 1, 1.0, 0.7, false, i)
	var sr := Rect2(cx - 130.0, H * 0.66, 260, 56)
	draw_rect(sr, C_TILE)
	draw_rect(sr, C_YOU, false, 2.0)
	txt_c(cx, H * 0.66 + 35.0, "START", 20, C_YOU)
	if FileAccess.file_exists(COUCH_SAVE):
		var rr := Rect2(cx - 130.0, H * 0.80, 260, 44)
		draw_rect(rr, C_TILE)
		draw_rect(rr, C_GHOST, false, 2.0)
		txt_c(cx, H * 0.80 + 28.0, "RESUME MATCH", 15, C_GHOST)

func _draw_handoff() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(C_VOID.r, C_VOID.g, C_VOID.b, 0.72))
	var cx := W / 2.0
	txt_c(cx, H * 0.34, "PASS TO", 18, C_DIM)
	_draw_cat(cx, H * 0.56, 1, 1.0, 2.2, false, vs_runner)
	txt_c(cx, H * 0.66, _pelt_name(vs_runner), 34, PELTS[vs_runner].body)
	txt_c(cx, H * 0.78 + sin(elapsed * 4.0) * 3.0, "tap when you have the screen", 14, C_GOAL)

func _draw_standings() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(C_VOID.r, C_VOID.g, C_VOID.b, 0.72))
	var cx := W / 2.0
	var over := bool(standings_res.over)
	if over:
		txt_c(cx, H * 0.16, _pelt_name(int(standings_res.winner)) + " IS TOP CAT", 34, PELTS[int(standings_res.winner)].body)
	else:
		txt_c(cx, H * 0.16, "STANDINGS", 26, C_TEXT)
	var order: Array = []
	for i in range(vs.n_players):
		order.append(i)
	order.sort_custom(func(a, b): return vs.scores[a] > vs.scores[b])
	for rank in range(order.size()):
		var pi: int = order[rank]
		var y := H * 0.26 + rank * 36.0
		_draw_cat(cx - 130.0, y + 12.0, 1, 1.0, 0.55, false, pi)
		txt_l(cx - 100.0, y + 6.0, _pelt_name(pi), 16, PELTS[pi].body)
		var delta := int(standings_res.deltas[pi])
		var line := "%d" % vs.scores[pi]
		if delta > 0:
			line += "   (+%d)" % delta
		txt_l(cx + 40.0, y + 6.0, line, 16, C_TEXT)
	if bool(standings_res.all_made_it):
		txt_c(cx, H * 0.26 + order.size() * 36.0 + 10.0, "everyone landed on their feet - no dinner points", 12, C_DIM)
	txt_c(cx, H * 0.90 + sin(elapsed * 4.0) * 3.0, "TAP: BACK TO TITLE" if over else "TAP: NEXT ROUND", 15, C_GOAL)

func _draw_level(lvl: SimLevel) -> void:
	for y in range(SimC.GH):
		for x in range(SimC.GW):
			if not lvl.solid_at(x, y):
				continue
			rect(x * TILE, y * TILE, TILE, TILE, C_TILE)
			if not lvl.solid_at(x, y - 1):
				rect(x * TILE, y * TILE, TILE, 4.0, C_TILE_TOP)
			if (x * 7 + y * 13) % 5 == 0:
				rect(x * TILE + float((x * 11 + y * 3) % 20) + 4.0, y * TILE + float((x * 5 + y * 17) % 20) + 6.0, 4.0, 4.0, Color(0, 0, 0, 0.12))
	rect(0.0, (SimC.GH - 0.35) * TILE, W, TILE * 0.35, ca(C_HAZ, 0.10))

func _draw_world_items(lvl: SimLevel) -> void:
	for i in range(lvl.items.size()):
		var it: Dictionary = lvl.items[i]
		var x: float = it.cx * TILE
		var y: float = it.cy * TILE
		match it.type:
			"shelf":
				_draw_shelf_px(x, y)
			"cactus":
				_draw_cactus_px(it)
			"fan":
				_draw_fan_px(x + TILE / 2.0, y + TILE / 2.0)
			"cushion":
				var hit: bool = race != null and cushion_hits.has(i) and race.tick - int(cushion_hits[i]) < 10
				_draw_cushion_px(x, y, hit)
			"launcher":
				_draw_launcher_px(x, y, 1 if int(it.rot) == 0 else -1)

func _draw_shelf_px(x: float, y: float) -> void:
	rect(x, y + 4.0, TILE * 3.0, 12.0, C_WOOD)
	for i in range(3):
		rect(x + i * TILE + 6.0, y + 7.0, TILE - 12.0, 2.0, C_WOOD_DK)
	draw_dashed_line(Vector2(x + 2.0, y + 17.0) + shk_v, Vector2(x + TILE * 3.0 - 2.0, y + 17.0) + shk_v, Color(C_BG.r, C_BG.g, C_BG.b, 0.5), 1.5, 4.0)

func _draw_cactus_px(it: Dictionary) -> void:
	var b := SimLevel.cactus_box(it)
	var x0 := px_of(b.x0)
	var x1 := px_of(b.x1)
	var y0 := px_of(b.y0)
	var y1 := px_of(b.y1)
	var rot := int(it.rot)
	var horiz := rot == 0 or rot == 2
	var n := int(round((x1 - x0) / TILE * 3.0)) if horiz else int(round((y1 - y0) / TILE * 3.0))
	for i in range(n):
		var pts := PackedVector2Array()
		if rot == 0:
			var x := x0 + (i + 0.5) * (x1 - x0) / n
			pts = PackedVector2Array([Vector2(x - 5, y1), Vector2(x + 5, y1), Vector2(x, y0)])
		elif rot == 2:
			var x := x0 + (i + 0.5) * (x1 - x0) / n
			pts = PackedVector2Array([Vector2(x - 5, y0), Vector2(x + 5, y0), Vector2(x, y1)])
		elif rot == 1:
			var yy := y0 + (i + 0.5) * (y1 - y0) / n
			pts = PackedVector2Array([Vector2(x0, yy - 5), Vector2(x0, yy + 5), Vector2(x1, yy)])
		else:
			var yy := y0 + (i + 0.5) * (y1 - y0) / n
			pts = PackedVector2Array([Vector2(x1, yy - 5), Vector2(x1, yy + 5), Vector2(x0, yy)])
		for k in range(pts.size()):
			pts[k] += shk_v
		draw_colored_polygon(pts, C_HAZ)
	if rot == 0:
		rect(x0, y1 - 4.0, x1 - x0, 4.0, C_HAZ_DK)
	elif rot == 2:
		rect(x0, y0, x1 - x0, 4.0, C_HAZ_DK)
	elif rot == 1:
		rect(x0, y0, 4.0, y1 - y0, C_HAZ_DK)
	else:
		rect(x1 - 4.0, y0, 4.0, y1 - y0, C_HAZ_DK)

func _draw_fan_px(cx: float, cy: float) -> void:
	var r := 0.78 * TILE
	for i in range(3):
		draw_set_transform(Vector2(cx, cy) + shk_v, elapsed * 10.0 + i * TAU / 3.0, Vector2.ONE)
		draw_colored_polygon(PackedVector2Array([Vector2(3, -3), Vector2(r - 3.0, -9), Vector2(r - 3.0, 5)]), C_HAZ)
	draw_set_transform(Vector2(cx, cy) + shk_v, 0.0, Vector2.ONE)
	draw_arc(Vector2.ZERO, r - 1.0, 0.0, TAU, 28, C_HAZ_DK, 3.0)
	draw_circle(Vector2.ZERO, 4.5, C_HAZ_DK)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_cushion_px(x: float, y: float, hit: bool) -> void:
	var cy := y + (16.0 if hit else 8.0)
	rect(x + 2.0, cy, TILE - 4.0, y + TILE - cy, C_SPRING)
	rect(x + 1.0, cy, TILE - 2.0, 7.0, C_SPRING_HI)
	rect(x + 9.0, cy + 12.0, 3.0, 3.0, ca(C_BG, 0.4))
	rect(x + 20.0, cy + 12.0, 3.0, 3.0, ca(C_BG, 0.4))

func _draw_launcher_px(x: float, y: float, dir: int) -> void:
	rect(x + 3.0, y + 10.0, TILE - 6.0, TILE - 14.0, C_TILE_EDGE)
	rect(x + TILE / 2.0 + (1.0 if dir > 0 else -13.0), y + TILE / 2.0 - 4.0, 12.0, 8.0, C_HAZ_DK)
	draw_circle(Vector2(x + TILE / 2.0 + dir * 10.0, y + TILE / 2.0) + shk_v, 4.5, C_HAZ)
	rect(x + 5.0, y + TILE - 4.0, 5.0, 4.0, C_HAZ_DK)
	rect(x + TILE - 10.0, y + TILE - 4.0, 5.0, 4.0, C_HAZ_DK)

func _draw_ball(x: float, y: float, dir: int) -> void:
	draw_line(Vector2(x - dir * 22.0, y) + shk_v, Vector2(x - dir * 9.0, y) + shk_v, ca(C_HAZ, 0.35), 3.0)
	draw_circle(Vector2(x, y) + shk_v, 6.0, C_HAZ)
	draw_arc(Vector2(x, y) + shk_v, 3.8, 0.7, 2.5, 10, C_HAZ_DK, 1.5)

func _draw_bowl(lvl: SimLevel) -> void:
	var x := px_of(lvl.bowl_cx)
	var top := px_of(lvl.bowl_top)
	var bot := px_of(lvl.bowl_bot)
	rect(x - 16.0, top - 4.0, 32.0, bot - top + 8.0, ca(C_GOAL, 0.12))
	rect(x - 13.0, bot - 9.0, 26.0, 9.0, C_GOAL)
	rect(x - 15.0, bot - 11.0, 30.0, 4.0, C_GOAL)
	rect(x - 7.0, bot - 14.0, 4.0, 4.0, C_YOU_DK)
	rect(x - 1.0, bot - 15.0, 4.0, 5.0, C_YOU_DK)
	rect(x + 4.0, bot - 14.0, 4.0, 4.0, C_YOU_DK)
	for k in range(2):
		var ph0 := elapsed * 2.2 + k * 2.4
		var wx := x - 5.0 + k * 10.0
		var span := bot - 18.0 - top
		var prev := Vector2(wx + sin(ph0) * 4.0, bot - 18.0) + shk_v
		for i in range(1, 7):
			var cur := Vector2(wx + sin(ph0 + i * 0.9) * 4.0, bot - 18.0 - span * i / 6.0) + shk_v
			draw_line(prev, cur, ca(C_GOAL, 0.55 - i * 0.07), 2.0)
			prev = cur

func _draw_cat(x: float, y: float, face: int, alpha: float, sc: float, animate: bool, pelt: int = 0) -> void:
	var sqv := sq if animate else 0.0
	var bob := 0.0
	var ph := 0.0
	var air := false
	if animate and race != null:
		air = not race.p.grounded
		if race.p.grounded and absi(race.p.vx) > 600:
			bob = sin(run_ph * 6.0) * 1.5
			ph = sin(run_ph * 6.0)
	var body_c: Color = PELTS[pelt].body
	var dark_c: Color = PELTS[pelt].dark
	draw_set_transform(Vector2(x, y + bob) + shk_v, 0.0, Vector2(face * sc * (1.0 + sqv * 0.8), sc * (1.0 - sqv)))
	var leg := ca(dark_c, alpha)
	draw_line(Vector2(-7, -8), Vector2(-7 + (-2.0 if air else ph * 4.0), 0), leg, 3.0)
	draw_line(Vector2(5, -8), Vector2(5 + (2.0 if air else -ph * 4.0), 0), leg, 3.0)
	var tail := ca(body_c, alpha)
	draw_line(Vector2(-11, -18), Vector2(-17, -25), tail, 3.0)
	draw_line(Vector2(-17, -25), Vector2(-14, -31), tail, 3.0)
	draw_rect(Rect2(-12, -22, 24, 14), ca(body_c, alpha))
	draw_rect(Rect2(-6, -22, 3, 14), ca(dark_c, alpha))
	draw_rect(Rect2(1, -22, 3, 14), ca(dark_c, alpha))
	draw_rect(Rect2(4, -34, 14, 13), ca(body_c, alpha))
	draw_colored_polygon(PackedVector2Array([Vector2(5, -34), Vector2(7, -40), Vector2(10, -34)]), ca(body_c, alpha))
	draw_colored_polygon(PackedVector2Array([Vector2(12, -34), Vector2(15, -40), Vector2(17, -34)]), ca(body_c, alpha))
	draw_rect(Rect2(12, -30, 3, 3), ca(C_BG, alpha))
	draw_colored_polygon(PackedVector2Array([Vector2(18, -26), Vector2(20, -25), Vector2(18, -24)]), ca(C_HAZ_DK, alpha))
	var wisk := ca(C_TEXT, alpha * 0.65)
	draw_line(Vector2(17, -27), Vector2(22, -28), wisk, 1.0)
	draw_line(Vector2(17, -25), Vector2(22, -24), wisk, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_copycat(x: float, y: float, face: int, alpha: float, sc: float = 1.0) -> void:
	var bob := sin(elapsed * 6.0 + x * 0.03) * 1.5
	draw_set_transform(Vector2(x, y + bob) + shk_v, 0.0, Vector2(face * sc, sc))
	var g := ca(C_GHOST, alpha)
	draw_line(Vector2(-7, -8), Vector2(-7, 0), g, 3.0)
	draw_line(Vector2(5, -8), Vector2(5, 0), g, 3.0)
	draw_line(Vector2(-11, -18), Vector2(-16, -24), g, 3.0)
	draw_line(Vector2(-16, -24), Vector2(-12, -29), g, 3.0)
	draw_line(Vector2(-12, -29), Vector2(-16, -33), g, 3.0)
	draw_rect(Rect2(-12, -22, 24, 14), g)
	draw_rect(Rect2(4, -34, 14, 13), g)
	draw_colored_polygon(PackedVector2Array([Vector2(5, -34), Vector2(7, -40), Vector2(10, -34)]), g)
	draw_colored_polygon(PackedVector2Array([Vector2(12, -34), Vector2(15, -40), Vector2(17, -34)]), g)
	draw_rect(Rect2(12, -30, 3, 3), ca(C_BG, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_ghosts() -> void:
	if scene == "place":
		var n_pool: int = vs.pool_roster().size() if in_vs() else m.roster.size()
		for i in range(n_pool):
			_draw_copycat(px_of(place_level.spawn_px) + (i - 1) * 16.0, px_of(place_level.spawn_py), 1, 0.45)
		return
	if race == null:
		return
	var alpha_i := Engine.get_physics_interpolation_fraction()
	for i in range(race.ghost_streams.size()):
		var st: Dictionary = race.ghost_streams[i]
		var f: Dictionary = race.fates[i]
		var racing := scene == "race" or scene == "recap"
		var t := maxi(race.tick - 1, 0) if racing else 0
		if racing:
			if int(f.death) >= 0 and t > int(f.death):
				continue
			if t >= int(st.len):
				continue
		var gx := px_of(st.xs[t])
		var gy := px_of(st.ys[t])
		if racing and t > 0:
			gx = lerpf(px_of(st.xs[t - 1]), gx, alpha_i)
			gy = lerpf(px_of(st.ys[t - 1]), gy, alpha_i)
		for tr in ghost_trail[i]:
			draw_rect(Rect2(Vector2(tr.x - 12.0, tr.y - 24.0) + shk_v, Vector2(24.0, 18.0)), ca(C_GHOST, 0.08))
		var a := 0.45 + sin(elapsed * 3.0 + i * 2.0) * 0.06
		var off := 0.0 if racing else (i - 1) * 16.0
		_draw_copycat(gx + off, gy, int(st.faces[t]), a)

# ---------- hud + screens ----------

func _draw_hud() -> void:
	if in_vs():
		var total_w := vs.n_players * 74.0
		var x0 := W / 2.0 - total_w / 2.0
		for i in range(vs.n_players):
			var ccx := x0 + i * 74.0 + 22.0
			var hilite: bool = (scene == "race" or scene == "countdown") and i == vs_runner
			_draw_cat(ccx, 46.0, 1, 1.0 if hilite else 0.75, 0.5, false, i)
			txt_l(ccx + 14.0, 38.0, "%d" % vs.scores[i], 16, PELTS[i].body)
		txt_c(W / 2.0, 14.0, "COUCH  -  ROUND %d  -  FIRST TO %d" % [vs.round_n, SimVersus.TARGET], 12, C_DIM)
		if scene == "race":
			var left_vs := maxi(0, (SimC.ROUND_TICKS - race.tick + 59) / 60)
			txt_c(W - 40.0, 38.0, "%ds" % left_vs, 15, C_HAZ if left_vs <= 10 else C_TEXT)
		_draw_race_aids(vs.round_n)
		return
	_draw_cat(26.0, 42.0, 1, 1.0, 0.62, false)
	txt_l(44.0, 32.0, "%02d" % m.you, 19, C_YOU)
	_draw_copycat(W - 28.0, 42.0, -1, 0.8, 1.0)
	draw_string(font_v, Vector2(W - 446.0, 32.0), "%02d" % m.foes, HORIZONTAL_ALIGNMENT_RIGHT, 400.0, 19, C_GHOST)
	var head := "DAILY  -  " if daily_mode else ""
	txt_c(W / 2.0, 20.0, head + "ROUND %d  -  FIRST TO %d" % [m.round_n, SimC.TARGET_SCORE], 13, C_DIM)
	if scene == "race":
		var left := maxi(0, (SimC.ROUND_TICKS - race.tick + 59) / 60)
		txt_c(W / 2.0, 42.0, "%ds" % left, 17, C_HAZ if left <= 10 else C_TEXT)
	_draw_race_aids(m.round_n)
	if (scene == "race" or scene == "recap") and race != null and race.fates.size() > 0:
		for i in range(race.fates.size()):
			var f: Dictionary = race.fates[i]
			var x := W / 2.0 - (race.fates.size() - 1) * 14.0 + i * 28.0
			var y := 58.0
			draw_rect(Rect2(x - 9.0, y - 9.0, 18.0, 18.0), C_GHOST, false, 1.5)
			if race.tick > int(f.done) or scene == "recap":
				if int(f.death) >= 0:
					draw_line(Vector2(x - 5, y - 5), Vector2(x + 5, y + 5), C_HAZ, 3.0)
					draw_line(Vector2(x + 5, y - 5), Vector2(x - 5, y + 5), C_HAZ, 3.0)
				else:
					draw_line(Vector2(x - 5, y), Vector2(x - 1, y + 4), C_GOAL, 3.0)
					draw_line(Vector2(x - 1, y + 4), Vector2(x + 5, y - 4), C_GOAL, 3.0)
			else:
				draw_rect(Rect2(x - 4.0, y - 4.0, 8.0, 8.0), C_GHOST)
func _draw_race_aids(round_now: int) -> void:
	if scene == "race" and round_now == 1 and race.tick < 240:
		var a := 0.6 * (1.0 - race.tick / 240.0)
		draw_dashed_line(Vector2(W * 0.42, H * 0.55), Vector2(W * 0.42, H - 12.0), ca(C_DIM, a), 1.5, 7.0)
		txt_c(W * 0.21, H - 30.0, "< slide to move >", 13, ca(C_DIM, a))
		txt_c(W * 0.71, H - 30.0, "tap: jump  -  hold: higher", 13, ca(C_DIM, a))
	if scene == "race" and not stick.is_empty() and touches.has(stick.index):
		var t: Dictionary = touches[stick.index]
		draw_arc(Vector2(float(stick.anchor), float(stick.y)), TILE * 1.15, 0.0, TAU, 32, ca(C_TEXT, 0.25), 2.0)
		draw_circle(Vector2(t.pos.x, float(stick.y)), 12.0, ca(C_TEXT, 0.25))

func _draw_place_ui() -> void:
	rect(0.0, H - 126.0, W, 126.0, Color(C_VOID.r, C_VOID.g, C_VOID.b, 0.55))
	var hint := "tap the check to lock it in" if not pending.is_empty() else "drag a piece into the level"
	txt_c(W / 2.0, H - 104.0, hint, 13, C_DIM)
	for z in place_level.safe:
		rect(z[0] * TILE, z[1] * TILE, z[2] * TILE, z[3] * TILE, ca(C_GOAL, 0.10))
	for i in range(offer.size()):
		_draw_card(offer[i], _card_rect(i))
	if not dragging.is_empty():
		_draw_preview(dragging.type, int(dragging.cx), int(dragging.cy), int(dragging.rot), bool(dragging.valid))
		draw_arc(Vector2(float(dragging.x), float(dragging.y)), 14.0, 0.0, TAU, 24, ca(C_TEXT, 0.3), 2.0)
	if not pending.is_empty():
		_draw_preview(pending.type, int(pending.cx), int(pending.cy), int(pending.rot), true)
		var b := _pending_buttons()
		_draw_btn(b.no, "no")
		if b.has("rot"):
			_draw_btn(b.rot, "rot")
		_draw_btn(b.ok, "ok")

func _draw_card(type: String, r: Rect2) -> void:
	draw_rect(r, C_TILE)
	draw_rect(r, C_TILE_EDGE, false, 2.0)
	var cx := r.position.x + r.size.x / 2.0
	var cy := r.position.y + 30.0
	var sc := 0.55 if type == "shelf" else 0.8
	draw_set_transform(Vector2(cx, cy), 0.0, Vector2(sc, sc))
	match type:
		"shelf":
			_draw_shelf_px(-TILE * 1.5, -TILE / 2.0)
		"cactus":
			_draw_cactus_px({ "type": "cactus", "cx": -1, "cy": -1, "rot": 0 })
		"fan":
			_draw_fan_px(0.0, 0.0)
		"cushion":
			_draw_cushion_px(-TILE / 2.0, -TILE / 2.0, false)
		"launcher":
			_draw_launcher_px(-TILE / 2.0, -TILE / 2.0, 1)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var d: Dictionary = SimLevel.DEFS[type]
	var name_col := C_HAZ if bool(d.hazard) else C_TEXT
	txt_c(cx, r.position.y + r.size.y - 18.0, type.to_upper(), 13, name_col)

func _draw_preview(type: String, cx: int, cy: int, rot: int, valid: bool) -> void:
	match type:
		"shelf":
			_draw_shelf_px(cx * TILE, cy * TILE)
		"cactus":
			_draw_cactus_px({ "type": "cactus", "cx": cx, "cy": cy, "rot": rot })
		"fan":
			_draw_fan_px((cx + 0.5) * TILE, (cy + 0.5) * TILE)
		"cushion":
			_draw_cushion_px(cx * TILE, cy * TILE, false)
		"launcher":
			_draw_launcher_px(cx * TILE, cy * TILE, 1 if rot == 0 else -1)
	var r := _cells_rect_px(SimLevel.item_cells(type, cx, cy, rot)).grow(3.0)
	var col := C_GOAL if valid else C_HAZ
	draw_rect(r, col, false, 2.5)
	if not valid:
		var mx := r.position.x + r.size.x / 2.0
		var my := r.position.y - 14.0
		draw_line(Vector2(mx - 6, my - 6), Vector2(mx + 6, my + 6), C_HAZ, 3.0)
		draw_line(Vector2(mx + 6, my - 6), Vector2(mx - 6, my + 6), C_HAZ, 3.0)

func _draw_btn(at: Vector2, kind: String) -> void:
	draw_circle(at, 26.0, C_TILE)
	var col := C_GOAL
	if kind == "no":
		col = C_HAZ
	elif kind == "rot":
		col = C_TEXT
	draw_arc(at, 26.0, 0.0, TAU, 32, col, 2.5)
	if kind == "ok":
		draw_line(at + Vector2(-8, 0), at + Vector2(-2, 6), col, 3.5)
		draw_line(at + Vector2(-2, 6), at + Vector2(9, -6), col, 3.5)
	elif kind == "no":
		draw_line(at + Vector2(-7, -7), at + Vector2(7, 7), col, 3.5)
		draw_line(at + Vector2(7, -7), at + Vector2(-7, 7), col, 3.5)
	else:
		draw_arc(at, 9.0, 0.6, TAU - 0.6, 20, col, 3.0)
		var tip := at + Vector2(cos(0.6), sin(0.6)) * 9.0
		draw_colored_polygon(PackedVector2Array([tip + Vector2(-2, -6), tip + Vector2(6, 2), tip + Vector2(2, 6)]), col)

func _draw_recap() -> void:
	var t: float = minf(1.0, recap.t * 3.5)
	var ease := 1.0 - pow(1.0 - t, 3.0)
	draw_rect(Rect2(0, 0, W, H), Color(C_VOID.r, C_VOID.g, C_VOID.b, 0.55 * ease))
	var res: Dictionary = recap.res
	var sc: Dictionary = res.score
	var title := ""
	var col := C_TEXT
	var sub := ""
	match sc.key:
		"first":
			title = "FIRST DINNER"
			sub = "this run now races you as a copycat"
		"too_easy":
			title = "TOO EASY"
			sub = "everyone landed on their feet. no points."
		"swatted":
			title = "%d COPYCAT%s SWATTED" % [sc.dunks, "S" if int(sc.dunks) > 1 else ""]
			col = C_YOU
			sub = "+1 dinner  +%d swat%s" % [sc.dunks, "s" if int(sc.dunks) > 1 else ""]
		"copycats":
			title = "THE COPYCATS SCORE"
			col = C_HAZ
			sub = "%d copycat%s got to dinner without you" % [sc.d_foes, "s" if int(sc.d_foes) > 1 else ""]
		"wash":
			title = "WASH"
			sub = "everybody ate it. no points."
	txt_c(W / 2.0, H / 2.0 - 26.0, title, int(24 + 10 * ease), col)
	txt_c(W / 2.0, H / 2.0 + 4.0, sub, 14, C_DIM)
	if int(sc.d_you) > 0:
		txt_c(W / 2.0, H / 2.0 + 34.0, "+%d YOU" % sc.d_you, 20, C_YOU)
	elif int(sc.d_foes) > 0:
		txt_c(W / 2.0, H / 2.0 + 34.0, "+%d COPYCATS" % sc.d_foes, 20, C_GHOST)
	if recap.t > 0.9:
		txt_c(W / 2.0, H / 2.0 + 66.0, "tap to continue", 12, C_FAINT)

func _draw_over() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(C_VOID.r, C_VOID.g, C_VOID.b, 0.75))
	txt_c(W / 2.0, H / 2.0 - 52.0, "TOP CAT" if over_won else "DINNER STOLEN", 44, C_YOU if over_won else C_GHOST)
	txt_c(W / 2.0, H / 2.0 - 18.0, "you outran every copy of yourself" if over_won else "your copycats ate your dinner", 15, C_TEXT)
	txt_c(W / 2.0, H / 2.0 + 10.0, "YOU %d  -  COPYCATS %d  -  %d ROUNDS" % [m.you, m.foes, m.round_n], 14, C_DIM)
	if daily_mode:
		var s := "daily %s" % daily_date
		if daily_best_today > 0:
			s += "  -  best %d rounds" % daily_best_today
		txt_c(W / 2.0, H / 2.0 + 32.0, s, 13, C_FAINT)
	elif over_won and best_rounds > 0:
		txt_c(W / 2.0, H / 2.0 + 32.0, "best: %d rounds" % best_rounds, 13, C_FAINT)
	txt_c(W / 2.0, H / 2.0 + 68.0 + sin(elapsed * 4.0) * 3.0, "TAP TO GO AGAIN", 17, C_GOAL)

func _draw_title() -> void:
	var cx := W / 2.0
	_draw_cat(cx - 150.0, H * 0.46, 1, 1.0, 1.6, false)
	_draw_copycat(cx + 150.0, H * 0.46, -1, 0.55, 1.6)
	var word := "COPYCATS"
	var x := cx - 133.0
	for i in range(word.length()):
		var col := C_GHOST if i < 4 else C_YOU
		var dy := sin(elapsed * 3.0 + i * 0.7) * 4.0
		txt_c(x, H * 0.24 + dy, word[i], 58, col)
		x += 38.0
	txt_c(cx, H * 0.36, "knock stuff over. race the copycats of your past lives.", 14, C_TEXT)
	txt_c(cx, H * 0.36 + 20.0, "reach dinner while they fall - first to %d wins" % SimC.TARGET_SCORE, 14, C_DIM)
	var pr := _title_play_rect()
	draw_rect(pr, C_TILE)
	draw_rect(pr, C_YOU, false, 2.0)
	txt_c(pr.get_center().x, pr.get_center().y + 6.0, "SOLO", 20, C_YOU)
	var cr := _title_couch_rect()
	draw_rect(cr, C_TILE)
	draw_rect(cr, C_TEXT, false, 2.0)
	txt_c(cr.get_center().x, cr.position.y + 26.0, "COUCH", 20, C_TEXT)
	var couch_sub := "2-8 cats, one screen"
	if FileAccess.file_exists(COUCH_SAVE):
		couch_sub = "match in progress"
	txt_c(cr.get_center().x, cr.position.y + 48.0, couch_sub, 11, C_DIM)
	var dr := _title_daily_rect()
	draw_rect(dr, C_TILE)
	draw_rect(dr, C_GHOST, false, 2.0)
	txt_c(dr.get_center().x, dr.position.y + 26.0, "DAILY", 20, C_GHOST)
	var sub: String = _today().date
	if daily_best_today > 0:
		sub += "  best %d" % daily_best_today
	txt_c(dr.get_center().x, dr.position.y + 48.0, sub, 11, C_DIM)
	txt_c(cx, H * 0.74, "phone: left thumb slides to move - right thumb taps to jump - swipe down drops", 12, C_FAINT)
	txt_c(cx, H * 0.74 + 18.0, "desktop: arrows / WASD + space", 12, C_FAINT)
	txt_c(cx, H * 0.88, "[ sound off ]" if muted else "[ sound on ]", 13, C_FAINT if muted else C_TEXT)
	if best_rounds > 0:
		txt_c(cx, H * 0.88 + 20.0, "best win: %d rounds" % best_rounds, 11, C_FAINT)

func _title_play_rect() -> Rect2:
	return Rect2(W / 2.0 - 290.0, H * 0.52, 180.0, 60.0)

func _title_couch_rect() -> Rect2:
	return Rect2(W / 2.0 - 90.0, H * 0.52, 180.0, 60.0)

func _title_daily_rect() -> Rect2:
	return Rect2(W / 2.0 + 110.0, H * 0.52, 180.0, 60.0)

func _draw_banner() -> void:
	if banner.is_empty():
		return
	var t: float = minf(1.0, banner.t * 5.0)
	var out: float = maxf(0.0, (banner.t - (banner.dur - 0.25)) / 0.25)
	var ease := (1.0 - pow(1.0 - t, 3.0)) * (1.0 - out)
	var lines: Array = banner.lines
	for i in range(lines.size()):
		txt_c(W / 2.0, H * 0.30 + i * 40.0, lines[i][0], int(28 + 10 * ease), ca(lines[i][1], ease))
	if banner.sub != "":
		txt_c(W / 2.0, H * 0.30 + lines.size() * 40.0 + 6.0, banner.sub, 14, ca(C_TEXT, ease))

func _draw_debug() -> void:
	if race == null:
		return
	txt_l(8.0, H - 10.0, "fps %d  tick %d  vy %d  coy %d  buf %d  g %d" % [
		Engine.get_frames_per_second(), race.tick, race.p.vy, race.p.coyote, race.p.buffer,
		1 if race.p.grounded else 0], 11, C_TEXT)
