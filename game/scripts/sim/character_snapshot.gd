class_name CharacterSnapshot
extends RefCounted
## JSON-safe character format between rounds (tier C: spec #32 owner rules; format 2: spec #33; format 3: spec #282 / #286,
## ADR 0006). THE place that says what a character keeps: its identity and its belongings, never its build.
## format: 3; job_id: integer (the 4th job it was created as, never changes);
## look: {skin, face, hair}, possibly empty (worn equipment is what is drawn over it);
## equipment: {worn: {equip slot: instance}, inventory: [instance, ...]} (Equipment: instance and slot shapes);
## scrolls: {"<scroll item id>": count} (the Use tab's scroll stacks); mesos: integer, 0 for a new character;
## cleared_regions: sorted unique stage keys, the regions of stages.json `progression` the character has cleared (ADR 0007,
## #450). Region i is unlocked iff i == 0 or the previous region is cleared (unlocked_keys); a CLEARED round adds its stage
## (cleared_after_round). It replaces the `tiers_unlocked` counter of ADR 0006: a file that still carries the counter is a
## legacy format-3 file, validated as before and turned into the set by migrate / with_cleared_regions (the format number
## stays 3: what a character keeps is unchanged, only the unlock field is).
## Optional keys (the snapshot writes them only when set; a file without them has no cash equipment and no pet):
##   cash: {slot: item id}, the character's worn cash equipment; slots are CashCatalog.SLOTS (hat, face, eye, earrings,
##     top, bottom, shoes, gloves, cape, weapon, shield). An overall's id is stored under both top and bottom, a
##     two-handed weapon cover's under both weapon and shield.
##   pet: species id of the owned pet that is out (0 or absent = none).
## Cash and pet are only what the character wears and takes out; whether the account owns them is decided each round
## (RunWorld ignores and warns about what it does not own). Fortune from cash slots is computed live, never stored.
## NOT persisted, on purpose: level, EXP, skills and ranks, card ranks and modifiers, AP and attributes, HP, potions,
## map state, buffs, RNG states and timers. Every round starts at Lv1 with the job's starting skill (ADR 0006). Extra
## metadata such as fixture _doc is ignored.
##
## Formats 1 and 2 (specs #32, #33) carried the whole build. They are no longer saved: a save file holding them moves
## its characters to the history (SaveData). Tool files (fixtures, `--character`) still load: validation_error accepts
## them and migrate() keeps just the format-3 part (format 1 first turns its look equipment and Beginner weapon into
## worn instances, with an empty inventory, no scrolls and 0 mesos).

const FORMAT := 3 # tier C: spec #282 drops the build from the character.
## Every format validation_error accepts; RunWorld and SceneFlow migrate older ones on load.
const FORMATS := [1, 2, 3]
## How many leading progression regions a legacy `tiers_unlocked` >= 2 counts as cleared (tier C, #447: the old tier 1 held
## Henesys, Ellinia, Perion and Kerning City, so a character with tier 2 open keeps Sleepywood reachable).
const LEGACY_TIER1_REGIONS := 4
# tier C: the frozen spec #32 weapon rule (old balance.player.weapon_by_job), used only to migrate format 1: a
# Beginner's nonzero beginner_weapon, else the job's creation weapon (JobTree.creation_weapon, including the legacy format1_weapon fallback).


## A format-3 copy of a supported snapshot (format 3 is returned as a detached copy). `equipment_info` ({id: canonical
## info}) gives the items migrated from format 1 their fresh stats and upgrade slots.
## `progression` (stages.json) turns a legacy `tiers_unlocked` into `cleared_regions`.
static func migrate(value: Dictionary, jobs: JobTree, equipment_info: Dictionary, progression: Array) -> Dictionary:
	var source := value
	if int(value.get("format", 0)) == 1:
		source = value.duplicate(true)
		source.equipment = {"worn": Equipment.worn_from_ids(held_item_ids(value, jobs), equipment_info), "inventory": []}
		source.scrolls = {}
		source.mesos = 0
	var out := {"format": FORMAT, "job_id": int(source.get("job_id", 0)), "look": _look_of(source),
		"equipment": source.get("equipment", Equipment.empty_state()).duplicate(true),
		"scrolls": source.get("scrolls", {}).duplicate(true), "mesos": int(source.get("mesos", 0)),
		"cleared_regions": cleared_of(source, progression)}
	for key: String in ["cash", "pet"]:
		if source.has(key):
			out[key] = source[key].duplicate(true) if source[key] is Dictionary else source[key]
	return out


## The cleared region set of a snapshot-shaped Dictionary: its `cleared_regions` (sorted, unique), else the migration of a
## legacy `tiers_unlocked` >= 2 (the first LEGACY_TIER1_REGIONS keys of `progression`, tier C #447), else empty.
static func cleared_of(source: Dictionary, progression: Array) -> Array:
	var keys := []
	if source.get("cleared_regions") is Array:
		for key: Variant in source.cleared_regions:
			if key is String and key not in keys:
				keys.append(key)
	elif int(source.get("tiers_unlocked", 1)) >= 2:
		keys = progression.slice(0, LEGACY_TIER1_REGIONS)
	keys.sort()
	return keys


## A copy of a format-3 snapshot with `cleared_regions` in place of a legacy `tiers_unlocked` (equal to the input when it
## already has the set). SaveData uses it to bring stored characters up to date on load.
static func with_cleared_regions(character: Dictionary, progression: Array) -> Dictionary:
	var out := character.duplicate(true)
	out["cleared_regions"] = cleared_of(character, progression)
	out.erase("tiers_unlocked")
	return out


## The look without the format-1 `equips` list.
static func _look_of(source: Dictionary) -> Dictionary:
	var look: Dictionary = source.get("look", {}).duplicate(true) if source.get("look") is Dictionary else {}
	look.erase("equips")
	return look


## Every item id the character holds: format 2 worn then inventory (Equipment.held_ids); for format 1 (or a
## format-less drawing dictionary without `equipment`) the look's non-weapon equips (the default creation outfit when
## it has none) plus the old rule's weapon.
static func held_item_ids(character: Dictionary, jobs: JobTree) -> Array:
	if character.get("equipment") is Dictionary:
		return Equipment.held_ids(character.equipment)
	var look: Variant = character.get("look", {})
	var equips: Array = look.get("equips", []) if look is Dictionary and look.get("equips") is Array else []
	if equips.is_empty():
		equips = Equipment.DEFAULT_OUTFIT
	var ids := []
	for id: Variant in equips:
		if Equipment.slot_of(int(id)) != "weapon":
			ids.append(int(id))
	var weapon := int(character.get("beginner_weapon", 0))
	if int(character.get("job_id", 0)) != 0 or weapon <= 0:
		weapon = jobs.creation_weapon(int(character.get("job_id", 0)))
	ids.append(weapon)
	return ids


## Structural validation for file/save callers; an empty message means a supported complete snapshot (format 1-3).
static func validation_error(value: Variant) -> String:
	if not value is Dictionary:
		return "expected a CharacterSnapshot object"
	if not _number(value.get("format")) or int(value.format) not in FORMATS:
		return "unsupported CharacterSnapshot format"
	var format := int(value.format)
	var numbers: Array = ["job_id"]
	numbers.append("beginner_weapon" if format == 1 else "mesos")
	for field: String in numbers:
		if not _number(value.get(field)) or float(value[field]) < 0.0:
			return "invalid " + field
	if format == 3:
		var regions_error := _regions_error(value)
		if regions_error != "":
			return regions_error
	if not value.get("look") is Dictionary:
		return "invalid look"
	var cash_message := cash_error(value)
	if cash_message != "":
		return cash_message
	if format == 1:
		return ""
	var equipment_error := Equipment.validation_error(value.get("equipment"))
	if equipment_error != "":
		return equipment_error
	if not value.get("scrolls") is Dictionary:
		return "invalid scrolls"
	for id: Variant in value.scrolls:
		var count: Variant = value.scrolls[id]
		if not String(id).is_valid_int() or not _number(count) or int(count) < 0 or float(count) != floorf(float(count)):
			return "invalid scrolls"
	if float(value.mesos) != floorf(float(value.mesos)):
		return "invalid mesos"
	return ""


## "" when a format-3 snapshot has a valid `cleared_regions` (an array of distinct stage keys) or the legacy
## `tiers_unlocked` (an integer >= 1) it is migrated from.
static func _regions_error(value: Dictionary) -> String:
	if value.has("cleared_regions"):
		if not value.cleared_regions is Array:
			return "invalid cleared_regions"
		var seen := {}
		for key: Variant in value.cleared_regions:
			if not key is String or key.is_empty() or seen.has(key):
				return "invalid cleared_regions"
			seen[key] = true
		return ""
	if not _whole(value.get("tiers_unlocked")) or int(value.tiers_unlocked) < 1:
		return "invalid cleared_regions"
	return ""


## The regions a character may start, in progression order (tier C: spec #447 owner rule): the first, plus every region
## whose predecessor is in `cleared`.
static func unlocked_keys(progression: Array, cleared: Array) -> Array:
	var out := []
	for index in progression.size():
		if index == 0 or progression[index - 1] in cleared:
			out.append(progression[index])
	return out


## Whether `key` is one of unlocked_keys.
static func is_unlocked(progression: Array, cleared: Array, key: String) -> bool:
	return key in unlocked_keys(progression, cleared)


## The cleared set after a round on stage `key`: `cleared` plus `key` when the round was CLEARED (idempotent on a replay),
## sorted; a death or a quit changes nothing.
static func cleared_after_round(cleared: Array, key: String, was_cleared: bool) -> Array:
	var out := cleared.duplicate()
	if was_cleared and key not in out:
		out.append(key)
	out.sort()
	return out


## Validates the optional cash/pet keys of a CharacterSnapshot-shaped Dictionary (also used by the tool account file).
static func cash_error(value: Dictionary) -> String:
	if value.has("cash"):
		if not value.cash is Dictionary:
			return "invalid cash"
		for slot: Variant in value.cash:
			var id: Variant = value.cash[slot]
			if not slot is String or not CashCatalog.SLOTS.has(slot) or not _whole(id) or int(id) <= 0:
				return "invalid cash"
	if value.has("pet") and (not _whole(value.pet) or int(value.pet) < 0):
		return "invalid pet"
	return ""


static func _whole(value: Variant) -> bool:
	return _number(value) and float(value) == floorf(float(value))


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


## Copies integer-valued fields after JSON parsing (which produces floats).
static func integers(values: Dictionary) -> Dictionary:
	var out := {}
	for key: String in values:
		out[key] = int(values[key])
	return out
