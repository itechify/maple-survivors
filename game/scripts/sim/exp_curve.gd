class_name ExpCurve
extends RefCounted
## Survivor EXP curve (docs/GAME_DESIGN.md section 5): exp_to_next(L) = round(a + b x L + c x L^2), tier C, from
## `balance.json` `exp_curve` {a, b, c}. Defaults = the tuned design curve: L1 16, L7 256, L29 3600 (812 EXP to Lv 8,
## 37816 to Lv 30).

var a := 4.0
var b := 8.0
var c := 4.0


## Builds the curve from balance.json `exp_curve` (missing keys keep the defaults).
static func from_data(curve: Dictionary) -> ExpCurve:
	var e := ExpCurve.new()
	e.a = float(curve.get("a", e.a))
	e.b = float(curve.get("b", e.b))
	e.c = float(curve.get("c", e.c))
	return e


## EXP needed to go from `level` to level + 1 (at least 1).
func exp_to_next(level: int) -> int:
	var l := float(level)
	return maxi(1, roundi(a + b * l + c * l * l))


## Total EXP from level 1 to reach `level`.
func total_to(level: int) -> int:
	var t := 0
	for l in range(1, level):
		t += exp_to_next(l)
	return t
