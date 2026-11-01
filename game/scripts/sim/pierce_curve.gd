class_name PierceCurve
extends RefCounted
## Pure contact-index curve shared by falling and rising piercing projectiles.


## One-based contact n; positive fractions retain the original falloff arithmetic exactly.
static func factor(n: int, fraction: float, floor_fraction: float, ceiling_fraction: float) -> float:
	if fraction < 0.0:
		# A ceiling below 100% would turn a rise into a fall: the first contact always deals the full hit.
		return minf(maxf(1.0, ceiling_fraction), 1.0 + absf(fraction) * (n - 1))
	return maxf(floor_fraction, 1.0 - fraction * (n - 1))
