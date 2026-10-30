class_name CastVisualPlan
extends RefCounted
## Expands a skill's `cast_visuals` data into the list of animations the cast plays (spec #332, Arrow Rain).
##
## An entry with a literal `x` plays once at that offset from the cast position, at the cast (Meteor Shower's tiles). An
## entry with `across` (a count) is spread evenly over the cast's box, so it follows `area`: the k-th copy sits at the
## centre of the k-th of `across` equal slices of the box, starts `interval` seconds after the previous one (`delay`) and
## drops `fall` px onto the ground over `fall_time` seconds. Pure data in, plain Dictionaries out (no nodes), so it is tested
## headless; RunScene does the drawing.

## Entries of `visuals` as {path, x, delay, fall, fall_time}: `x` px from the cast position, `delay` seconds after the
## cast, `fall` px dropped (0 = drawn in place), `fall_time` seconds of the drop.
static func expand(visuals: Array, box: Rect2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for visual: Dictionary in visuals:
		var across := int(visual.get("across", 0))
		if across <= 0:
			out.append({"path": String(visual.path), "x": float(visual.get("x", 0.0)), "delay": float(visual.get("delay", 0.0)),
				"fall": float(visual.get("fall", 0.0)), "fall_time": float(visual.get("fall_time", 0.0))})
			continue
		for k in across:
			out.append({"path": String(visual.path), "x": box.position.x + box.size.x * (float(k) + 0.5) / float(across),
				"delay": float(visual.get("interval", 0.0)) * k + float(visual.get("delay", 0.0)),
				"fall": float(visual.get("fall", 0.0)), "fall_time": float(visual.get("fall_time", 0.0))})
	return out
