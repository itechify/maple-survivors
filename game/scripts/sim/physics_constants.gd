class_name PhysicsConstants
extends RefCounted
## Movement constants from Map.wz/Physics.img (tier A), plus the few derived constants of the movement model that are
## not in WZ (tier B, NoLifeStory's CVecCtrl description in docs/research/prior-art.md section 1b).
##
## Physics.img forces are in px/s^2 times the implied mass (100); speeds in px/s. Defaults are the verified v83 values
## (docs/research/wz-inventory.md section 2), so `PhysicsConstants.new()` equals `v83_defaults()`.

## Implied body mass the forces are divided by. tier B: NoLifeStory shoe_mass.
const MASS := 100.0
## Down-jump take-off = jumpSpeed x this (1/(2*sqrt 2), ~196 px/s). tier B: NoLifeStory down_jump_multiplier.
const DOWN_JUMP_MULT := 0.35355339
## vy is clamped to this on landing. tier B: NoLifeStory max_land_speed.
const MAX_LAND_SPEED := 162.5
## Air-control speed cap = floatDrag2 x this (~8.93 px/s). tier B: NoLifeStory float_multiplier (1/1120).
const FLOAT_MULT := 0.0008928571
## Footholds steeper than this |sin| make you slip. tier B: NoLifeStory shoe walk_slant.
const WALK_SLANT := 0.9

## WZ key -> field name.
const WZ_KEYS := {
	"walkForce": "walk_force", "walkSpeed": "walk_speed", "walkDrag": "walk_drag",
	"slipForce": "slip_force", "slipSpeed": "slip_speed",
	"floatDrag1": "float_drag1", "floatDrag2": "float_drag2", "floatCoefficient": "float_coefficient",
	"swimForce": "swim_force", "swimSpeed": "swim_speed", "swimSpeedDec": "swim_speed_dec",
	"flyForce": "fly_force", "flySpeed": "fly_speed", "flyJumpDec": "fly_jump_dec",
	"gravityAcc": "gravity_acc", "fallSpeed": "fall_speed", "jumpSpeed": "jump_speed",
	"maxFriction": "max_friction", "minFriction": "min_friction",
}

var walk_force := 140000.0
var walk_speed := 125.0
var walk_drag := 80000.0
var slip_force := 60000.0
var slip_speed := 120.0
var float_drag1 := 100000.0
var float_drag2 := 10000.0
var float_coefficient := 0.01
var swim_force := 120000.0
var swim_speed := 140.0
var swim_speed_dec := 0.9
var fly_force := 120000.0
var fly_speed := 200.0
var fly_jump_dec := 0.35
var gravity_acc := 2000.0
var fall_speed := 670.0
var jump_speed := 555.0
var max_friction := 2.0
var min_friction := 0.05


## The verified GMS v83 Physics.img values.
static func v83_defaults() -> PhysicsConstants:
	return PhysicsConstants.new()


## Reads a Physics.img root (cache JSON). Missing keys keep their v83 value.
static func from_wz(physics_img: Dictionary) -> PhysicsConstants:
	var c := PhysicsConstants.new()
	for key: String in WZ_KEYS:
		var v: Variant = physics_img.get(key)
		if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
			c.set(WZ_KEYS[key], float(v))
	return c


## Ground acceleration while a direction is held, px/s^2 (walkForce / mass = 1400).
func walk_acc() -> float:
	return walk_force / MASS


## Ground deceleration with no input, px/s^2 (walkDrag x clamp(1, minFriction, maxFriction) / mass = 800).
func walk_dec() -> float:
	return clampf(1.0, min_friction, max_friction) * walk_drag / MASS
