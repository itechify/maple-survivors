class_name MesoCharge
extends RefCounted
## Pure arithmetic behind the meso charge (M23, spec #383): an amount-driven gain that carries its remainder and the
## decay clock of a meter. A meso charge is a counter filled by pickups, never a currency: nothing here touches mesos.
## No nodes, no RNG, no clock of its own; PlayerMeter owns the carry and the clock and calls these with them.

## Float slack so 360 ticks of 1/60 s count as the six seconds they are (tier C: ours, no gameplay effect).
const CLOCK_EPSILON := 1e-6


## Whole `units` earned by `mesos` more mesos when `per_mesos` buy one, and the `carry` left over (0..per_mesos-1).
## A non-positive amount or rate changes nothing, so no mesos are ever rounded away.
static func take(carry: int, mesos: int, per_mesos: int) -> Dictionary:
	if mesos <= 0 or per_mesos <= 0:
		return {"units": 0, "carry": carry}
	var total := carry + mesos
	@warning_ignore("integer_division")
	return {"units": total / per_mesos, "carry": total % per_mesos}


## One decay step: `dt` more seconds on `clock` while `value` is held, `amount` leaving per whole `interval`.
## Returns the new `clock` and how many units are `lost` (never more than `value`). The clock only runs while
## something is held and is cleared when it empties, so an empty meter never banks time toward its next pip.
static func decay(clock: float, dt: float, interval: float, value: int, amount: int) -> Dictionary:
	if value <= 0 or interval <= 0.0 or amount <= 0:
		return {"clock": 0.0, "lost": 0}
	var t := clock + dt
	var lost := 0
	while t + CLOCK_EPSILON >= interval and lost < value:
		t = maxf(0.0, t - interval)
		lost += mini(amount, value - lost)
	if lost >= value:
		t = 0.0
	return {"clock": t, "lost": lost}
