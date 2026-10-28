class_name CharacterSnapshot
extends RefCounted
## JSON-safe character format between rounds (tier C: spec #32 owner rules; format 2: spec #33; format 3: spec #282 / #286,
## ADR 0006). THE place that says what a character keeps: its identity and its belongings, never its build.
## format: 3; job_id: integer (the 4th job it was created as, never changes);
## look: {skin, face, hair}, possibly empty (worn equipment is what is drawn over it);
## equipment: {worn: {equip slot: instance}, inventory: [instance, ...]} (Equipment: instance and slot shapes);
## scrolls: {"<scroll item id>": count} (the Use tab's scroll stacks); mesos: integer, 0 for a new character;
## tiers_unlocked: integer >= 1, how many tiers the character may play (tier 1 is always unlocked; clearing a stage of
## tier N unlocks tier N+1, see unlocked_after_round).
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
# tier C: the frozen spec #32 weapon rule (old balance.player.weapon_by_job), used only to migrate format 1: a
# Beginner's nonzero beginner_weapon, else the nearest job ancestor's `format1_weapon` (data/survivor/jobs.json,
# read with JobTree.lineage_value; Equipment.DEFAULT_OUTFIT's weapon when no job in the line has one).


## A format-3 copy of a supported snapshot (format 3 is returned as a detached copy). `equipment_info` ({id: canonical
## info}) gives the items migrated from format 1 their fresh stats and upgrade slots.
static func migrate(value: Dictionary, jobs: JobTree, equipment_info: Dictionary) -> Dictionary:
	var source := value
	if int(value.get("format", 0)) == 1:
		source = value.duplicate(true)
		source.equipment = {"worn": Equipment.worn_from_ids(held_item_ids(value, jobs), equipment_info), "inventory": []}
		source.scrolls = {}
		source.mesos = 0
	var out := {"format": FORMAT, "job_id": int(source.get("job_id", 0)), "look": _look_of(source),
		"equipment": source.get("equipment", Equipment.empty_state()).duplicate(true),
		"scrolls": source.get("scrolls", {}).duplicate(true), "mesos": int(source.get("mesos", 0)),
		"tiers_unlocked": maxi(1, int(source.get("tiers_unlocked", 1)))}
	for key: String in ["cash", "pet"]:
		if source.has(key):
			out[key] = source[key].duplicate(true) if source[key] is Dictionary else source[key]
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
		weapon = int(jobs.lineage_value(int(character.get("job_id", 0)), "format1_weapon", Equipment.DEFAULT_OUTFIT[-1]))
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
	if format == 3:
		numbers.append("tiers_unlocked")
	for field: String in numbers:
		if not _number(value.get(field)) or float(value[field]) < 0.0:
			return "invalid " + field
	if format == 3 and (not _whole(value.tiers_unlocked) or int(value.tiers_unlocked) < 1):
		return "invalid tiers_unlocked"
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


## The tiers a character has unlocked after a round: `unlocked` (>= 1) normally; one more than the played stage's tier
## (`tier`, 0-based) when the round was cleared and that is further, never beyond `tier_count`. Tier 1 is always unlocked,
## and a death or a quit changes nothing (tier C: spec #282 owner rule).
static func unlocked_after_round(unlocked: int, tier: int, cleared: bool, tier_count: int) -> int:
	var now := maxi(1, unlocked)
	return mini(maxi(now, tier + 2), maxi(now, tier_count)) if cleared else now


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
