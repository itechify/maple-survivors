class_name StatusBonus
extends RefCounted
## Data-only rarity status grants: catalogue validation and rank arithmetic (M22, #402).

## Reports malformed catalogue rows and missing grant references in skills or upgrade data.
static func errors(catalogue: Dictionary, root: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in catalogue:
		var entry: Variant = catalogue[id]
		if not entry is Dictionary:
			out.append("status bonus %s must be an object" % id)
			continue
		if not String(entry.get("kind", "")) in MobSwarm.STATUS_NAMES:
			out.append("status bonus %s has unknown kind" % id)
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
	return {"id": id, "kind": kind, "element": String(entry.get("element", MobSwarm.STATUS_ELEMENTS[index])),
		"chance": minf(100.0, _value(entry.get("chance", 100.0), rank) + extra_chance),
		"time": _value(entry.get("time", 0.0), rank), "level": int(_value(entry.get("level", 1), rank))}


static func _value(raw: Variant, rank: int) -> float:
	return float(raw[clampi(rank - 1, 0, raw.size() - 1)]) if raw is Array else float(raw)
