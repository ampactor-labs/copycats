class_name SimPlayer
extends RefCounted
# The whole platformer body: run, jump (buffer + coyote + variable height),
# wall slide/jump, one-way planks with drop-through, hazards, goal.
# Feet-anchored AABB. Pure integer state; step() is the only mutator.
# Jump/drop edges are derived from held bits against the previous tick,
# never encoded in the input byte (level signals only, the two-top rule).

const E_SIDE := 3932              # 0.06 t collision sample inset
const E_FOOT := 2621              # 0.04 t
const E_TINY := 1310              # 0.02 t
const CORNER := 22937             # 0.35 t head-bump corner correction
const NUDGE := 655                # 0.01 t
const WALL_PROBE := 3276          # 0.05 t
const WALL_Y := 9830              # 0.15 t
const SPRING_MIN_VY := 1092       # 1 t/s

var px: int
var py: int
var vx: int = 0
var vy: int = 0
var face: int = 1
var grounded: bool = true
var coyote: int = 0
var buffer: int = 0
var wallc: int = 0
var wall_dir: int = 0
var drop: int = 0
var jump_prev: bool = false
var down_prev: bool = false
var dead: bool = false
var finished: bool = false
var done_tick: int = -1

static func spawn(lvl: SimLevel) -> SimPlayer:
	var p := SimPlayer.new()
	p.px = lvl.spawn_px
	p.py = lvl.spawn_py
	return p

func step(lvl: SimLevel, arrows: Array, cushion_last: Dictionary, b: int, tick: int, ev: Array) -> void:
	if dead or finished:
		return
	var axis := (b & 0xF) - 7
	if axis != 0:
		face = 1 if axis > 0 else -1
	var jump_held := (b & SimC.BIT_JUMP) != 0
	var down_held := (b & SimC.BIT_DOWN) != 0
	var jump_edge := jump_held and not jump_prev
	var down_edge := down_held and not down_prev
	jump_prev = jump_held
	down_prev = down_held

	var target := axis * SimC.RUN_V / SimC.AXIS_MAX
	var acc := SimC.AIR_ACC
	if grounded:
		acc = SimC.ACC if axis != 0 else SimC.DEC
	if vx < target:
		vx = mini(target, vx + acc)
	elif vx > target:
		vx = maxi(target, vx - acc)

	coyote = SimC.COYOTE_T if grounded else coyote - 1
	wallc -= 1
	drop -= 1
	buffer = SimC.BUFFER_T if jump_edge else buffer - 1

	if down_edge and grounded and _on_plank(lvl):
		drop = SimC.DROP_T
		grounded = false

	if buffer > 0:
		if coyote > 0:
			vy = SimC.VJUMP
			buffer = 0
			coyote = 0
			ev.append({ "t": "jump", "x": px, "y": py })
		elif wallc > 0:
			vy = SimC.WJ_VY
			vx = -wall_dir * SimC.WJ_VX
			face = -wall_dir
			buffer = 0
			wallc = 0
			ev.append({ "t": "jump", "x": px, "y": py })

	if not jump_held and vy < 0:
		vy = vy * SimC.JCUT_NUM / SimC.JCUT_DEN

	var g := SimC.GRAV if vy < 0 else SimC.FALL_GRAV
	if absi(vy) < SimC.APEX_BAND and not grounded:
		g = SimC.APEX_GRAV
	vy = mini(vy + g, SimC.VFALL_MAX)

	var pushing := (not grounded) and axis != 0 and _touching_wall(lvl, signi(axis))
	if pushing:
		if vy > SimC.WALL_SLIDE_MAX:
			vy = SimC.WALL_SLIDE_MAX
		wallc = SimC.WALLC_T
		wall_dir = signi(axis)

	_move_x(lvl)
	_move_y(lvl, ev)

	if _hazards(lvl, arrows, cushion_last, tick, ev):
		return
	if py - SimC.PH > SimC.GH * SimC.FP + (SimC.FP * 3) / 2:
		_die(tick, ev)
		return
	if py < -8 * SimC.FP:
		py = -8 * SimC.FP
	var gr := lvl.goal_rect()
	if _overlap(gr):
		finished = true
		done_tick = tick
		ev.append({ "t": "finish", "x": px, "y": py })

func _die(tick: int, ev: Array) -> void:
	dead = true
	done_tick = tick
	ev.append({ "t": "die", "x": px, "y": py })

func _overlap(r: Dictionary) -> bool:
	return px - SimC.HW < r.x1 and px + SimC.HW > r.x0 \
		and py - SimC.PH < r.y1 and py > r.y0

func _hazards(lvl: SimLevel, arrows: Array, cushion_last: Dictionary, tick: int, ev: Array) -> bool:
	for i in range(lvl.items.size()):
		var it: Dictionary = lvl.items[i]
		if it.type == "cactus":
			if _overlap(SimLevel.cactus_box(it)):
				_die(tick, ev)
				return true
		elif it.type == "fan":
			if _fan_hit(it):
				_die(tick, ev)
				return true
		elif it.type == "cushion":
			if vy > SPRING_MIN_VY and tick - int(cushion_last.get(i, -999)) > SimC.SPRING_CD_T:
				var f := SimC.FP
				var box := { "x0": it.cx * f + f / 10, "x1": (it.cx + 1) * f - f / 10,
					"y0": it.cy * f + (f * 4) / 10, "y1": (it.cy + 1) * f }
				if _overlap(box):
					vy = SimC.SPRING_VY
					cushion_last[i] = tick
					ev.append({ "t": "cushion", "x": px, "y": py, "i": i })
	for a in arrows:
		if _overlap(a):
			_die(tick, ev)
			return true
	return false

func _fan_hit(it: Dictionary) -> bool:
	var cx: int = it.cx * SimC.FP + SimC.FP / 2
	var cy: int = it.cy * SimC.FP + SimC.FP / 2
	var qx := clampi(cx, px - SimC.HW, px + SimC.HW)
	var qy := clampi(cy, py - SimC.PH, py)
	var dx := cx - qx
	var dy := cy - qy
	return dx * dx + dy * dy < SimC.FAN_R2

func _on_plank(lvl: SimLevel) -> bool:
	var row := SimC.rdiv(py)
	return lvl.one_way_at(SimC.fdiv(px - SimC.HW + E_TINY), row) \
		or lvl.one_way_at(SimC.fdiv(px + SimC.HW - E_TINY), row)

func _touching_wall(lvl: SimLevel, dir: int) -> bool:
	var x := px + dir * (SimC.HW + WALL_PROBE)
	var cx := SimC.fdiv(x)
	return lvl.solid_at(cx, SimC.fdiv(py - WALL_Y)) \
		or lvl.solid_at(cx, SimC.fdiv(py - SimC.PH + WALL_Y))

func _move_x(lvl: SimLevel) -> void:
	px += vx
	var dirv := signi(vx)
	if dirv == 0:
		return
	var cx := SimC.fdiv(px + dirv * SimC.HW)
	for off in [E_SIDE, SimC.PH / 2, SimC.PH - E_SIDE]:
		if lvl.solid_at(cx, SimC.fdiv(py - off)):
			if dirv > 0:
				px = cx * SimC.FP - SimC.HW
			else:
				px = (cx + 1) * SimC.FP + SimC.HW
			vx = 0
			return

func _move_y(lvl: SimLevel, ev: Array) -> void:
	var prev := py
	py += vy
	if vy > 0:
		var row := SimC.fdiv(py)
		var landed := false
		for xs in [px - SimC.HW + E_FOOT, px + SimC.HW - E_FOOT]:
			var cx := SimC.fdiv(xs)
			var solid := lvl.solid_at(cx, row)
			var plank := (not solid) and lvl.one_way_at(cx, row) and drop <= 0 \
				and prev <= row * SimC.FP + E_TINY
			if solid or plank:
				if not grounded and vy > SimC.HARD_LAND_VY:
					ev.append({ "t": "land", "x": px, "y": row * SimC.FP })
				py = row * SimC.FP
				vy = 0
				grounded = true
				landed = true
				break
		if not landed:
			grounded = false
	elif vy < 0:
		grounded = false
		var head := SimC.fdiv(py - SimC.PH)
		for xs in [px - SimC.HW + E_FOOT, px + SimC.HW - E_FOOT]:
			var cx := SimC.fdiv(xs)
			if lvl.solid_at(cx, head):
				var from_l := (px - SimC.HW) - cx * SimC.FP
				var from_r := (cx + 1) * SimC.FP - (px + SimC.HW)
				if from_l > -CORNER and from_l < 0 and not lvl.solid_at(cx - 1, head):
					px = cx * SimC.FP - SimC.HW - NUDGE
					continue
				if from_r > -CORNER and from_r < 0 and not lvl.solid_at(cx + 1, head):
					px = (cx + 1) * SimC.FP + SimC.HW + NUDGE
					continue
				py = (head + 1) * SimC.FP + SimC.PH
				vy = 0
				return
	else:
		if grounded:
			grounded = lvl.solid_at(SimC.fdiv(px - SimC.HW + E_FOOT), SimC.fdiv(py + E_TINY)) \
				or lvl.solid_at(SimC.fdiv(px + SimC.HW - E_FOOT), SimC.fdiv(py + E_TINY)) \
				or _on_plank(lvl)
