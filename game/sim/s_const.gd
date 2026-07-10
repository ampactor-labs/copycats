class_name SimC
extends RefCounted
# Deterministic sim constants. Everything is integer math on Q16.16
# subunits per tile; velocities are subunits per tick at 60 ticks/s.
# The float comments are the feel spec, carried over from the spike.

const FP := 65536                 # subunits per tile
const TICKS := 60                 # sim rate
const GW := 26
const GH := 15
const ROUND_TICKS := 45 * 60
const TARGET_SCORE := 9
const MAX_GHOSTS := 3
const SIM_VERSION := 1

# movement                        # feel spec (tiles, seconds)
const RUN_V := 9284               # 8.5 t/s
const ACC := 1638                 # 90 t/s^2
const DEC := 1274                 # 70 t/s^2
const AIR_ACC := 1001             # 55 t/s^2

# jump: derived from height 3.3 t, time-to-apex 0.34 s
const GRAV := 1039                # rising gravity
const FALL_GRAV := 1766           # x1.7 falling
const APEX_GRAV := 572            # x0.55 near apex
const APEX_BAND := 2731           # |vy| < 2.5 t/s
const VJUMP := -21203             # -19.41 t/s
const VFALL_MAX := 24030          # 22 t/s
const JCUT_NUM := 8075            # gentle per-tick cut while rising unheld
const JCUT_DEN := 10000

const COYOTE_T := 6               # 0.10 s
const BUFFER_T := 7               # 0.12 s
const WALLC_T := 5                # 0.08 s
const DROP_T := 13                # 0.22 s ignoring one-way planks
const WALL_SLIDE_MAX := 4915      # 4.5 t/s
const WJ_VX := 9612               # 8.8 t/s
const WJ_VY := -18022             # -16.5 t/s
const SPRING_VY := -28399         # -26 t/s
const SPRING_CD_T := 12
const HARD_LAND_VY := 6553        # 6 t/s, cosmetic threshold

# bodies
const HW := 20316                 # player half width, 0.31 t
const PH := 57672                 # player height, 0.88 t
const FAN_R := 51118              # 0.78 t
const FAN_R2 := FAN_R * FAN_R
const BALL_V := 13107            # 12 t/s
const BALL_FIRST := 30
const BALL_EVERY := 120
const BALL_HW := (FP * 28) / 100
const BALL_HH := (FP * 9) / 100

# input byte layout: bits 0-3 axis+7 (0..14), bit 4 jump held, bit 5 down held.
const BIT_JUMP := 16
const BIT_DOWN := 32
const AXIS_MAX := 7

static func fdiv(a: int) -> int:
	# floor-divide a subunit coordinate into a cell index (handles negatives)
	if a >= 0:
		return a / FP
	return -((-a + FP - 1) / FP)

static func rdiv(a: int) -> int:
	# round to nearest cell row/col; sim positions here are non-negative
	return (a + FP / 2) / FP

static func fnv_seed() -> int:
	return 0x811C9DC5

static func fnv_int(h: int, v: int) -> int:
	# FNV-1a over 8 little-endian bytes, kept in 32 bits so products
	# stay well inside int64 (portable, no overflow wrap needed)
	for i in range(8):
		h = h ^ ((v >> (i * 8)) & 0xFF)
		h = (h * 0x01000193) & 0xFFFFFFFF
	return h
