class_name PierceCurve
extends RefCounted
## Pure contact-index curve shared by falling and rising piercing projectiles.


## One-based contact n; positive fractions retain the original falloff arithmetic exactly.
static func factor(n: int, fraction: float, floor: float, ceiling: float) -> float:
	if fraction < 0.0:
		return minf(ceiling, 1.0 + absf(fraction) * (n - 1))
	return maxf(floor, 1.0 - fraction * (n - 1))
