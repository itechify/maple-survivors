class_name CharacterSnapshot
extends RefCounted
## JSON-safe round-boundary character format (tier C: spec #32 owner carry/refill rules).
## format: 1; level/exp/job_id: integers (EXP into this level); attributes: resolved STR/DEX/INT/LUK;
## base_attributes: original attributes before automatic earned_ap and player_mods; earned_ap: integer;
## base_hp/base_mp/job_mp: accumulated growth and advancement grants, before modifiers/passives;
## skills: {key: {rank: int, mods: {stat: [add, mul]}}}; skill_order: keys in casting/learning order;
## player_mods: {stat: [add, mul]}; card_ranks: {card_id: consumed steps}, preserving card limits;
## fortune: resolved survivor stat; base_fortune: its unmodified starting value;
## potions: {hp: {item_id, count}, mp: {item_id, count}} (item_id IS the potion tier);
## look: {skin, face, hair, equips}, possibly empty; beginner_weapon: item id (0 = job default).
## Optional spec #34 keys, added without a FORMAT bump (a file without them has no cash equipment and no pet; the
## snapshot writes them only when set):
##   cash: {slot: item id}, the character's worn cash equipment; slots are CashCatalog.SLOTS (hat, face, eye, earrings,
##     top, bottom, shoes, gloves, cape, weapon, shield). An overall's id is stored under both top and bottom, a
##     two-handed weapon cover's under both weapon and shield.
##   pet: species id of the owned pet that is out (0 or absent = none).
## Both are only what the character wears and takes out; whether the account owns them is decided each round
## (RunWorld ignores and warns about what it does not own). Fortune from cash slots is computed live, never stored:
## base_fortune and fortune above exclude it.
## No HP/MP, map state, buffs, statuses, choices, RNG states or timers are persisted. The next round refills
## computed maxima and creates new systems. Extra metadata such as fixture _doc is ignored.

const FORMAT := 1 # tier C: initial snapshot schema, spec #32.


## One weapon rule for simulation and all player drawings: Beginner selection, otherwise nearest job ancestor.
static func weapon_id(job_id: int, beginner_weapon: int, weapon_by_job: Dictionary, jobs: JobTree) -> int:
	if job_id == 0 and beginner_weapon > 0:
		return beginner_weapon
	for ancestor in jobs.lineage(job_id):
		if weapon_by_job.has(str(ancestor)):
			return int(weapon_by_job[str(ancestor)])
	return int(weapon_by_job.get("0", 0))


## Structural validation for file/save callers; an empty message means a supported complete snapshot.
static func validation_error(value: Variant) -> String:
	if not value is Dictionary:
		return "expected a CharacterSnapshot object"
	if int(value.get("format", 0)) != FORMAT:
		return "unsupported CharacterSnapshot format"
	for field: String in ["level", "exp", "job_id", "earned_ap", "base_hp", "base_mp", "job_mp",
			"fortune", "base_fortune", "beginner_weapon"]:
		if not _number(value.get(field)) or float(value[field]) < 0.0:
			return "invalid " + field
	if int(value.level) < 1:
		return "invalid level"
	for field: String in ["attributes", "base_attributes", "skills", "player_mods", "card_ranks", "potions", "look"]:
		if not value.get(field) is Dictionary:
			return "invalid " + field
	for field: String in ["attributes", "base_attributes"]:
		for stat: String in ["str", "dex", "int", "luk"]:
			if not _number(value[field].get(stat)):
				return "invalid " + field + "." + stat
	if not value.get("skill_order") is Array or value.skill_order.size() != value.skills.size():
		return "invalid skill_order"
	var seen := {}
	for key: Variant in value.skill_order:
		if not key is String or seen.has(key) or not value.skills.get(key) is Dictionary:
			return "invalid skill_order entry"
		seen[key] = true
		var skill: Dictionary = value.skills[key]
		if not _number(skill.get("rank")) or int(skill.rank) < 1 or not _valid_mods(skill.get("mods")):
			return "invalid skill " + key
	if not _valid_mods(value.player_mods):
		return "invalid player_mods"
	for rank: Variant in value.card_ranks.values():
		if not _number(rank) or int(rank) < 0:
			return "invalid card_ranks"
	for kind: String in ["hp", "mp"]:
		var potion: Variant = value.potions.get(kind)
		if not potion is Dictionary or not _number(potion.get("item_id")) or not _number(potion.get("count")):
			return "invalid potion " + kind
		if int(potion.item_id) <= 0 or int(potion.count) < 0:
			return "invalid potion " + kind
	return cash_error(value)


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


static func _valid_mods(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for pair: Variant in value.values():
		if not pair is Array or pair.size() != 2 or not _number(pair[0]) or not _number(pair[1]):
			return false
	return true


## Restores learned order, ranks, modifiers and consumed card steps into an empty loadout.
static func restore_loadout(character: Dictionary, loadout: Loadout) -> void:
	for key: String in character.get("skill_order", []):
		var skill: Dictionary = character.skills[key]
		loadout.add_skill(key)
		loadout.set_rank(key, int(skill.rank))
		loadout.skill_mods[key] = decode_mods(skill.mods)
	loadout.player_mods = decode_mods(character.get("player_mods", {}))
	loadout.card_ranks = integers(character.get("card_ranks", {}))


## Encodes Loadout's Vector2 modifier pairs as JSON arrays without changing their order.
static func encode_mods(mods: Dictionary) -> Dictionary:
	var out := {}
	for stat: String in mods:
		var pair: Vector2 = mods[stat]
		out[stat] = [pair.x, pair.y]
	return out


## Decodes JSON arrays to the Loadout modifier representation.
static func decode_mods(mods: Dictionary) -> Dictionary:
	var out := {}
	for stat: String in mods:
		var pair: Array = mods[stat]
		out[stat] = Vector2(float(pair[0]), float(pair[1]))
	return out


## Copies integer-valued fields after JSON parsing (which produces floats).
static func integers(values: Dictionary) -> Dictionary:
	var out := {}
	for key: String in values:
		out[key] = int(values[key])
	return out
