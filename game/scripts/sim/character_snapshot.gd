class_name CharacterSnapshot
extends RefCounted
## JSON-safe round-boundary character format (tier C: spec #32 owner carry/refill rules; format 2: spec #33).
## format: 2; level/exp/job_id: integers (EXP into this level); attributes: resolved STR/DEX/INT/LUK including
## equipment; base_attributes: original attributes before automatic earned_ap and player_mods; earned_ap: integer;
## base_hp/base_mp/job_mp: accumulated growth and advancement grants, before modifiers/passives;
## skills: {key: {rank: int, mods: {stat: [add, mul]}}}; skill_order: keys in casting/learning order;
## player_mods: {stat: [add, mul]}; card_ranks: {card_id: consumed steps}, preserving card limits;
## fortune: resolved survivor stat; base_fortune: its unmodified starting value;
## Potions are derived from level, never saved; legacy stock is ignored (tier C: spec #237, no format bump).
## look: {skin, face, hair}, possibly empty (worn equipment is what is drawn over it);
## equipment: {worn: {equip slot: instance}, inventory: [instance, ...]} (Equipment: instance and slot shapes; the
## `shield` worn key, #158, is optional and absent for snapshots saved before it: no format bump);
## scrolls: {"<scroll item id>": count} (the Use tab's scroll stacks); mesos: integer, 0 for a new character.
## Optional spec #34 keys, added without a FORMAT bump (valid in format 1 and 2; a file without them has no cash
## equipment and no pet; the snapshot writes them only when set):
##   cash: {slot: item id}, the character's worn cash equipment; slots are CashCatalog.SLOTS (hat, face, eye, earrings,
##     top, bottom, shoes, gloves, cape, weapon, shield). An overall's id is stored under both top and bottom, a
##     two-handed weapon cover's under both weapon and shield.
##   pet: species id of the owned pet that is out (0 or absent = none).
## Optional spec #151 key (#157), also without a FORMAT bump:
##   weapon_path: the latest multi-family advancement choice ("sword", "claw", ...; JobTree.paths_of).
##     Pathless characters infer it from the held family at their deepest multi-family job (tier C: spec #226).
## Both are only what the character wears and takes out; whether the account owns them is decided each round
## (RunWorld ignores and warns about what it does not own). Fortune from cash slots is computed live, never stored:
## base_fortune and fortune above exclude it. Cash equipment is drawn over the worn equipment (AvatarLayers).
## No HP/MP, map state, buffs, statuses, choices, RNG states or timers are persisted. The next round refills
## computed maxima and creates new systems. Extra metadata such as fixture _doc is ignored.
##
## Format 1 (spec #32) had no equipment, scrolls or mesos; its look carried {equips: [top, bottom, shoes]} and a
## separate beginner_weapon. validation_error still accepts it (old saves stay loadable) and migrate() turns it into
## format 2: the look's equipment plus the weapon the old rule resolved become worn instances, the inventory is empty
## and mesos are 0.

const FORMAT := 2 # tier C: spec #33 adds worn equipment, inventory, scrolls and mesos.
## Every format validation_error accepts; RunWorld and SceneFlow migrate older ones on load.
const FORMATS := [1, 2]
## Card ids removed from the game; migrate() drops them from card_ranks (spec #225).
const REMOVED_CARDS := ["magnet", "orange_potion", "white_potion", "mana_elixir"]
# tier C: the frozen spec #32 weapon rule (old balance.player.weapon_by_job), used only to migrate format 1: a
# Beginner's nonzero beginner_weapon, else the nearest job ancestor's `format1_weapon` (data/survivor/jobs.json,
# read with JobTree.lineage_value; Equipment.DEFAULT_OUTFIT's weapon when no job in the line has one).


## A format-2 copy of a supported snapshot (format 2 is returned as a detached copy). `equipment_info` ({id: canonical
## info}) gives the migrated items their fresh stats and upgrade slots.
static func migrate(value: Dictionary, jobs: JobTree, equipment_info: Dictionary) -> Dictionary:
	var out := value.duplicate(true)
	out.erase("potions") # tier C: spec #237; stock and cooldowns never carry between rounds
	# Spec #225: the Magnet and potion-tier cards are gone; their ranks and the radius modifier are dropped (no format
	# bump). PotionSchedule derives items from the loaded level.
	if out.get("card_ranks") is Dictionary:
		for removed: String in REMOVED_CARDS:
			out.card_ranks.erase(removed)
	if out.get("player_mods") is Dictionary:
		out.player_mods.erase("magnet")
	if int(value.get("format", 0)) != FORMAT:
		out.equipment = {"worn": Equipment.worn_from_ids(held_item_ids(value, jobs), equipment_info), "inventory": []}
		out.scrolls = {}
		out.mesos = 0
		out.erase("beginner_weapon")
		if out.get("look") is Dictionary:
			out.look.erase("equips")
		out.format = FORMAT
	if String(out.get("weapon_path", "")) == "":
		var held := WeaponInfo.family(int(out.get("equipment", {}).get("worn", {}).get("weapon", {}).get("id", 0)))
		for j in jobs.lineage(int(out.get("job_id", 0))):
			var paths := jobs.paths_of(j)
			if paths.size() < 2:
				continue
			# tier C: migrate only the deepest multi-family row; an incompatible or missing weapon uses its first path.
			out.weapon_path = String(paths[0].id)
			for p: Dictionary in paths:
				if String(p.family) == held:
					out.weapon_path = String(p.id)
					break
			break
	return out


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


## Structural validation for file/save callers; an empty message means a supported complete snapshot (format 1 or 2).
static func validation_error(value: Variant) -> String:
	if not value is Dictionary:
		return "expected a CharacterSnapshot object"
	if not _number(value.get("format")) or int(value.format) not in FORMATS:
		return "unsupported CharacterSnapshot format"
	var format := int(value.format)
	var numbers: Array = ["level", "exp", "job_id", "earned_ap", "base_hp", "base_mp", "job_mp", "fortune",
		"base_fortune"]
	numbers.append("beginner_weapon" if format == 1 else "mesos")
	for field: String in numbers:
		if not _number(value.get(field)) or float(value[field]) < 0.0:
			return "invalid " + field
	if int(value.level) < 1:
		return "invalid level"
	for field: String in ["attributes", "base_attributes", "skills", "player_mods", "card_ranks", "look"]:
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
	var cash_message := cash_error(value)
	if cash_message != "":
		return cash_message
	if value.has("weapon_path") and not value.weapon_path is String:
		return "invalid weapon_path"
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
