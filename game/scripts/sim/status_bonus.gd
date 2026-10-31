class_name StatusBonus
extends RefCounted
## Data-only rarity status grants: catalogue validation and rank arithmetic (M22, #402).
## A catalogue row names the status `kind` (any MobSwarm.STATUS_NAMES entry), `chance` (percent), `time` (seconds) and, for the
## kinds that need them, `level` (poison, below MobSwarm.POISON_LEVEL_BASE), `pulse` (burn), `x` (slow, negative) and `x` / `y`
## (threatened, signed), each a scalar or one value per rank. Validation rejects a row missing what its kind needs, so a grant
## never validates and then silently does nothing.

## Reports malformed catalogue rows and missing grant references in skills or upgrade data.
static func errors(catalogue: Dictionary, root: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in catalogue:
		var entry: Variant = catalogue[id]
		if not entry is Dictionary:
			out.append("status bonus %s must be an object" % id)
			continue
		var kind := String(entry.get("kind", ""))
		if not kind in MobSwarm.STATUS_NAMES:
			out.append("status bonus %s has unknown kind" % id)
		_check_kind_needs(id, kind, entry, out)
		for field: String in ["chance", "time", "level", "repeat_chance"]:
			var raw: Variant = entry.get(field, 0.0)
			if raw is Array and (field == "repeat_chance" or raw.size() != 8):
				out.append("status bonus %s %s needs eight ranks (repeat_chance is scalar)" % [id, field])
			var values: Array = raw if raw is Array else [raw]
			for value: Variant in values:
				if not typeof(value) in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
					out.append("status bonus %s %s must be numeric" % [id, field])
				elif (field == "chance" and (float(value) < 0.0 or float(value) > 100.0)) or float(value) < 0.0:
					out.append("status bonus %s %s is out of range" % [id, field])
	_check_refs(root, catalogue, out)
	return out


## The parameters a status kind needs before MobSwarm.apply_status does anything with a grant of it.
static func _check_kind_needs(id: String, kind: String, entry: Dictionary, out: PackedStringArray) -> void:
	if _largest(entry.get("time", 0.0)) <= 0.0:
		out.append("status bonus %s needs a positive time" % id)
	for field: String in ["x", "y", "pulse"]:
		for value: Variant in _values(entry.get(field, 0.0)):
			if not typeof(value) in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
				out.append("status bonus %s %s must be numeric" % [id, field])
	match kind:
		"poison":
			for value: Variant in _values(entry.get("level", 0)):
				if typeof(value) in [TYPE_INT, TYPE_FLOAT] and (float(value) < 1.0 or float(value) >= MobSwarm.POISON_LEVEL_BASE):
					out.append("status bonus %s level must be 1 to %d" % [id, MobSwarm.POISON_LEVEL_BASE - 1])
		"burn":
			if _smallest(entry.get("pulse", 0.0)) <= 0.0:
				out.append("status bonus %s (burn) needs a positive pulse" % id)
		"slow":
			if _largest(entry.get("x", 0.0)) >= 0.0:
				out.append("status bonus %s (slow) needs a negative x" % id)
		"threatened":
			if _smallest(entry.get("x", 0.0)) >= 0.0 and _smallest(entry.get("y", 0.0)) >= 0.0:
				out.append("status bonus %s (threatened) needs a negative x or y" % id)


static func _values(raw: Variant) -> Array:
	return raw if raw is Array else [raw]


static func _largest(raw: Variant) -> float:
	var best := -INF
	for value: Variant in _values(raw):
		if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
			best = maxf(best, float(value))
	return best


static func _smallest(raw: Variant) -> float:
	var best := INF
	for value: Variant in _values(raw):
		if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
			best = minf(best, float(value))
	return best


static func _check_refs(value: Variant, catalogue: Dictionary, out: PackedStringArray) -> void:
	if value is Dictionary:
		if String(value.get("op", "")) == "grant":
			if String(value.get("stat", "")) != "status" or not catalogue.has(String(value.get("status", ""))):
				out.append("status grant names a missing catalogue id or invalid stat")
		for child: Variant in value.values():
			_check_refs(child, catalogue, out)
	elif value is Array:
		for child: Variant in value:
			_check_refs(child, catalogue, out)


## Resolves the owning skill's rank and accumulated repeat points, capped at 100 percent.
static func resolve(catalogue: Dictionary, ids: Array, rank: int, extra_chances: Dictionary = {}) -> Array:
	var out: Array = []
	for id: String in ids:
		out.append(_resolve_one(id, catalogue[id], rank, float(extra_chances.get(id, 0.0))))
	return out


## Additional percentage points for a repeated award; scale is the rarity bonus's existing diminishing factor.
## tier C (#402): repeat_chance x scale, spec #383 M22.
static func repeat_points(entry: Dictionary, scale: float) -> float:
	return float(entry.get("repeat_chance", 0.0)) * scale


static func _resolve_one(id: String, entry: Dictionary, rank: int, extra_chance: float) -> Dictionary:
	var kind := String(entry.kind)
	var index := MobSwarm.STATUS_NAMES.find(kind)
	var out := {"id": id, "kind": kind, "element": String(entry.get("element", MobSwarm.STATUS_ELEMENTS[index])),
		"chance": minf(100.0, _value(entry.get("chance", 100.0), rank) + extra_chance),
		"time": _value(entry.get("time", 0.0), rank), "level": int(_value(entry.get("level", 1), rank))}
	# Only the parameters a row names ride along, so a poison or stun grant is the dictionary it always was.
	for field: String in ["x", "y"]:
		if entry.has(field):
			out[field] = _value(entry[field], rank)
	if entry.has("pulse"):
		out["pulse"] = int(_value(entry.pulse, rank))
	return out


static func _value(raw: Variant, rank: int) -> float:
	return float(raw[clampi(rank - 1, 0, raw.size() - 1)]) if raw is Array else float(raw)
