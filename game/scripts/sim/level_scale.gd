class_name LevelScale
extends RefCounted
## The stage level scale (spec #447, ticket #453): rescales a monster's HP, damage, defence and EXP from its own v83
## level to the region's effective level at that point of the round. Pure data in, numbers out: no nodes, no RNG.
##
## Two inputs. The reference curves (`survivor/level_curve.json`, tools/level_curve: the median ordinary v83 monster
## by level, tier A-derived numbers used for a tier C purpose) hold hp, pad, mad, pdd, mdd and exp for levels 1-200
## (index = level - 1). The stage block `level_scale: {"keyframes": [{"t", "level", "exp_level"?}]}` gives the
## effective level E and the EXP level X along curve time `t` (seconds on the pacing clock, RunWorld.curve_time):
## linear between keyframes, held before the first and after the last, `exp_level` defaulting to `level`.
##
## A monster of canonical level L is scaled by curve(E) / curve(L): HP, weapon attack (contact and physical attacks, pad),
## magic attack (mad), weapon defence (pdd) and magic defence (mdd) with E, EXP with X. A fractional level
## interpolates the curve linearly; E = L gives exactly 1. A stat whose curve is 0 at L scales by 1.

const MAX_LEVEL := 200
## The stats a curve holds, in file order.
const STATS: Array[String] = ["hp", "pad", "mad", "pdd", "mdd", "exp"]

var _curve := {}
var _t := PackedFloat64Array()
var _level := PackedFloat64Array()
var _exp_level := PackedFloat64Array()


## The scale of `stage` over `curve`, or null when the stage has no `level_scale` or the block or curve is invalid
## (stage_errors and curve_errors say why; RunWorld warns).
static func from_stage(stage: Dictionary, curve: Dictionary) -> LevelScale:
	if not stage.has("level_scale"):
		return null
	if not block_errors("", stage.level_scale).is_empty() or not curve_errors(curve).is_empty():
		return null
	var scale := LevelScale.new()
	for stat: String in STATS:
		scale._curve[stat] = PackedFloat64Array(curve[stat])
	for keyframe: Dictionary in stage.level_scale.keyframes:
		scale._t.append(float(keyframe.t))
		scale._level.append(float(keyframe.level))
		scale._exp_level.append(float(keyframe.get("exp_level", keyframe.level)))
	return scale


## Effective level E at curve time t.
func level_at(t: float) -> float:
	return _along(_level, t)


## EXP level X at curve time t.
func exp_level_at(t: float) -> float:
	return _along(_exp_level, t)


## The reference value of `stat` at a (possibly fractional) level, clamped to 1-200.
func value(stat: String, level: float) -> float:
	var values: PackedFloat64Array = _curve[stat]
	var x := clampf(level, 1.0, float(MAX_LEVEL)) - 1.0
	var i := mini(int(x), MAX_LEVEL - 2)
	return lerpf(values[i], values[i + 1], x - float(i))


## curve(stat, level) / curve(stat, canonical_level): what a monster of that canonical level is multiplied by.
func ratio(stat: String, level: float, canonical_level: int) -> float:
	var base := value(stat, float(canonical_level))
	return value(stat, level) / base if base > 0.0 else 1.0


## Messages for the reference curves: every stat needs MAX_LEVEL positive numbers, non-decreasing.
static func curve_errors(curve: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for stat: String in STATS:
		var values: Variant = curve.get(stat)
		if not values is Array or values.size() != MAX_LEVEL:
			errors.append("level_curve.%s needs %d numbers" % [stat, MAX_LEVEL])
			continue
		for i in MAX_LEVEL:
			if not (values[i] is float or values[i] is int) or float(values[i]) <= 0.0:
				errors.append("level_curve.%s[%d] needs a positive number" % [stat, i])
				break
			if i > 0 and float(values[i]) < float(values[i - 1]):
				errors.append("level_curve.%s falls at level %d" % [stat, i + 1])
				break
	return errors


## One message per problem of the stages' `level_scale` blocks (parsed stages.json): a malformed block, and a stage with
## both a level_scale and an opening_ramp (its own or a map's), which would scale the same stats twice.
static func stage_errors(stages_file: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var all: Dictionary = stages_file.get("stages", {})
	for key: String in all:
		var stage: Dictionary = all[key]
		if not stage.has("level_scale"):
			continue
		errors.append_array(block_errors(key, stage.level_scale))
		if stage.has("opening_ramp"):
			errors.append("stage '%s' has both level_scale and opening_ramp" % key)
		for i in stage.get("maps", []).size():
			if stage.maps[i] is Dictionary and stage.maps[i].has("opening_ramp"):
				errors.append("stage '%s' has level_scale and maps[%d] has an opening_ramp" % [key, i])
	return errors


## Messages for one `level_scale` block: keyframes with strictly rising t >= 0 and levels (and exp_level) in 1-200.
static func block_errors(stage_key: String, block: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	var who := "stage '%s' level_scale" % stage_key
	if not block is Dictionary or not block.get("keyframes") is Array or block.keyframes.is_empty():
		errors.append("%s needs a non-empty keyframes list" % who)
		return errors
	var last_t := -1.0
	for i in block.keyframes.size():
		var keyframe: Variant = block.keyframes[i]
		if not keyframe is Dictionary:
			errors.append("%s keyframes[%d] needs an object" % [who, i])
			continue
		var t: Variant = keyframe.get("t")
		if not _is_number(t) or float(t) < 0.0 or float(t) <= last_t:
			errors.append("%s keyframes[%d] needs a t above the previous one (seconds >= 0)" % [who, i])
		else:
			last_t = float(t)
		for field: String in ["level", "exp_level"]:
			if field == "exp_level" and not keyframe.has(field):
				continue
			var level: Variant = keyframe.get(field)
			if not _is_number(level) or float(level) < 1.0 or float(level) > float(MAX_LEVEL):
				errors.append("%s keyframes[%d].%s needs a number from 1 to %d" % [who, i, field, MAX_LEVEL])
	return errors


static func _is_number(v: Variant) -> bool:
	return v is float or v is int


func _along(values: PackedFloat64Array, t: float) -> float:
	if t <= _t[0]:
		return values[0]
	for i in range(1, _t.size()):
		if t < _t[i]:
			return lerpf(values[i - 1], values[i], (t - _t[i - 1]) / (_t[i] - _t[i - 1]))
	return values[values.size() - 1]
