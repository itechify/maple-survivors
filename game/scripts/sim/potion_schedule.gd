class_name PotionSchedule
extends RefCounted
## The level schedule of automatic potion upgrades (spec #225): balance.potions.schedule is an array of
## {level, kind ("hp"), item} sorted by level. Pure functions over plain data; RunWorld applies the result through
## PotionInventory.upgrade (cooldown kept). It keeps no applied-step state: every level-up and every load re-scans the
## steps up to the character's level, so the result depends only on the level and the items held. Tier C (ours); the
## steps are listed in docs/GAME_DESIGN.md "Constants and provenance".


## The valid steps of `balance` (its potions.schedule), sorted by level (equal levels keep list order). Entries
## without a positive level, a known kind or an item id are ignored.
static func steps(balance: Dictionary) -> Array:
	var raw: Variant = balance.get("potions", {}).get("schedule", [])
	var keyed: Array = []
	if raw is Array:
		for entry: Variant in raw:
			if not entry is Dictionary:
				continue
			var kind := String(entry.get("kind", ""))
			var level := int(entry.get("level", 0))
			var item := int(entry.get("item", 0))
			if level > 0 and item > 0 and kind in PotionInventory.DEFAULT_ITEMS:
				keyed.append([level, keyed.size(), {"level": level, "kind": kind, "item": item}])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out: Array = []
	for k: Array in keyed:
		out.append(k[2])
	return out


## The steps due for a character of `level` holding `current` items ({kind: item id}), in schedule order: for each kind
## the steps with level <= `level` that come after the step whose item the kind holds now. A kind holding no scheduled
## item (the starters) is due all of them; one holding a step's item is never due an earlier step (no downgrades).
static func due(schedule: Array, level: int, current: Dictionary) -> Array:
	var picked: Array[int] = []
	for kind: String in PotionInventory.DEFAULT_ITEMS:
		var held := -1
		for i in schedule.size():
			if String(schedule[i].kind) == kind and int(schedule[i].item) == int(current.get(kind, 0)):
				held = i
		for i in range(held + 1, schedule.size()):
			if String(schedule[i].kind) == kind and int(schedule[i].level) <= level:
				picked.append(i)
	picked.sort()
	var out: Array = []
	for i in picked:
		out.append(schedule[i])
	return out


## Every item id the schedule can switch to, for loading their canonical restore specs.
static func items(balance: Dictionary) -> Array:
	return steps(balance).map(func(s: Dictionary) -> int: return int(s.item))


## The level-up notice, from the v83 String.wz item names ("Red Potion" -> "Orange Potion"). The plural of a name is
## name + "s" unless `plurals` (balance.potions.plural_names, {"<item id>": plural display name}) names it, for items
## whose name is its own plural ("Unagi"; tier C, ours).
static func notice_text(from_id: int, from_name: String, to_id: int, to_name: String, plurals: Dictionary = {}) -> String:
	return "Your %s are now %s." % [_plural(from_id, from_name, plurals), _plural(to_id, to_name, plurals)]


static func _plural(id: int, item_name: String, plurals: Dictionary) -> String:
	var override: Variant = plurals.get(str(id), "")
	return String(override) if override is String and String(override) != "" else item_name + "s"
