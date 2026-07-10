class_name SimLevel
extends RefCounted
# Static level geometry plus placed items. Grid solids never change after
# build(); planks are one-way cells layered on top; hazards are checked
# against boxes derived here. All queries are integer.

const ROWS := [
	"#........................#",
	"#........................#",
	"#........................#",
	"#........................#",
	"#........................#",
	"#........................#",
	"#....................#####",
	"#...............###......#",
	"#........................#",
	"#.........####...........#",
	"#........................#",
	"#....###.................#",
	"#........................#",
	"#.#########....#########.#",
	"#........................#",
]

const SPAWN_PX := 229376          # feet at (3.5, 13.0) tiles
const SPAWN_PY := 851968
const FLAG_TOP := 235930          # goal zone, subunits
const FLAG_BOT := 393216
const FLAG_CX := 1474560          # 22.5 t
const GOAL_HW := 58982            # 0.9 t
# no-placement zones, in cells: around spawn and around the flag
const SAFE := [[1, 9, 5, 5], [19, 1, 7, 6]]

const DEFS := {
	"plank":  { "w": 3, "h": 1, "rots": 1, "hazard": false },
	"spikes": { "w": 2, "h": 1, "rots": 4, "hazard": true },
	"saw":    { "w": 1, "h": 1, "rots": 1, "hazard": true },
	"spring": { "w": 1, "h": 1, "rots": 1, "hazard": false },
	"bow":    { "w": 1, "h": 1, "rots": 2, "hazard": true },
}
const TYPE_ID := { "plank": 0, "spikes": 1, "saw": 2, "spring": 3, "bow": 4 }

var grid := PackedByteArray()
var one_way := {}                 # cell index -> true
var items: Array = []             # {type, cx, cy, rot, round}
var rows := PackedStringArray()   # geometry source, kept for derive()
# per-level geometry; defaults are the classic layout, generators override
var spawn_px: int = SPAWN_PX
var spawn_py: int = SPAWN_PY
var flag_cx: int = FLAG_CX
var flag_top: int = FLAG_TOP
var flag_bot: int = FLAG_BOT
var safe: Array = SAFE

static func build(item_list: Array, rows_in := PackedStringArray()) -> SimLevel:
	var l := SimLevel.new()
	l.rows = rows_in if rows_in.size() == SimC.GH else PackedStringArray(ROWS)
	l.grid.resize(SimC.GW * SimC.GH)
	for y in range(SimC.GH):
		for x in range(SimC.GW):
			if l.rows[y][x] == "#":
				l.grid[y * SimC.GW + x] = 1
	for it in item_list:
		l.add_item(it)
	return l

static func derive(base: SimLevel, item_list: Array) -> SimLevel:
	# same geometry as base, different item set (ghost resim, placement)
	var l := build(item_list, base.rows)
	l.spawn_px = base.spawn_px
	l.spawn_py = base.spawn_py
	l.flag_cx = base.flag_cx
	l.flag_top = base.flag_top
	l.flag_bot = base.flag_bot
	l.safe = base.safe
	return l

static func items_upto(item_list: Array, round_n: int) -> Array:
	var out: Array = []
	for it in item_list:
		if it.round <= round_n:
			out.append(it)
	return out

func add_item(it: Dictionary) -> void:
	items.append(it)
	if it.type == "plank":
		for c in item_cells(it.type, it.cx, it.cy, it.rot):
			one_way[c.y * SimC.GW + c.x] = true

func solid_at(cx: int, cy: int) -> bool:
	if cx < 0 or cx >= SimC.GW:
		return true               # side walls extend forever
	if cy < 0 or cy >= SimC.GH:
		return false              # open sky, open pit
	return grid[cy * SimC.GW + cx] == 1

func one_way_at(cx: int, cy: int) -> bool:
	return one_way.has(cy * SimC.GW + cx)

static func item_size(type: String, rot: int) -> Vector2i:
	var d: Dictionary = DEFS[type]
	if type == "spikes" and (rot == 1 or rot == 3):
		return Vector2i(d.h, d.w)
	return Vector2i(d.w, d.h)

static func item_cells(type: String, cx: int, cy: int, rot: int) -> Array:
	var s := item_size(type, rot)
	var out: Array = []
	for y in range(s.y):
		for x in range(s.x):
			out.append(Vector2i(cx + x, cy + y))
	return out

func place_valid(type: String, cx: int, cy: int, rot: int) -> bool:
	for c in item_cells(type, cx, cy, rot):
		if c.x < 1 or c.x >= SimC.GW - 1 or c.y < 1 or c.y > SimC.GH - 2:
			return false
		if solid_at(c.x, c.y) or one_way_at(c.x, c.y):
			return false
		for it in items:
			for oc in item_cells(it.type, it.cx, it.cy, it.rot):
				if oc == c:
					return false
		for z in safe:
			if c.x >= z[0] and c.x < z[0] + z[2] and c.y >= z[1] and c.y < z[1] + z[3]:
				return false
	return true

static func spike_box(it: Dictionary) -> Dictionary:
	# thin kill slab against the item's base surface, subunits
	var f := SimC.FP
	var t := f / 2
	var inset := (f * 8) / 100
	var cx: int = it.cx
	var cy: int = it.cy
	match it.rot:
		0:  # on a floor, points up
			return { "x0": cx * f + inset, "x1": (cx + 2) * f - inset, "y0": (cy + 1) * f - t, "y1": (cy + 1) * f }
		2:  # on a ceiling, points down
			return { "x0": cx * f + inset, "x1": (cx + 2) * f - inset, "y0": cy * f, "y1": cy * f + t }
		1:  # on a left wall, points right
			return { "x0": cx * f, "x1": cx * f + t, "y0": cy * f + inset, "y1": (cy + 2) * f - inset }
		_:  # on a right wall, points left
			return { "x0": (cx + 1) * f - t, "x1": (cx + 1) * f, "y0": cy * f + inset, "y1": (cy + 2) * f - inset }

func goal_rect() -> Dictionary:
	return { "x0": flag_cx - GOAL_HW, "x1": flag_cx + GOAL_HW, "y0": flag_top, "y1": flag_bot }
