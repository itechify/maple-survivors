class_name Equipment
extends RefCounted
## A character's equipment (GLOSSARY "Mesos and equipment"): equipment instances, equip slots, v83 requirements and
## the stat sums the combat math reads. Pure and static: plain JSON-safe Dictionaries in and out, no nodes.
##
## Equipment instance: {"id": int, "stats": {"incMAD": 23, ...}, "slots": int, "scrolls": int}. `stats` holds only
## the non-zero `inc*` values under their WZ key names (a fresh instance copies its Character.wz `info`; drops roll
## their own later), `slots` is the remaining upgrade slots (`info/tuc` when fresh) and `scrolls` counts successful
## scrolls. Item-level facts (`req*`, `attackSpeed`, `afterImage`, `sfx`, `price`) stay in the canonical info node,
## which callers pass in (RunWorld: `setup.equipment_info`).
##
## Equipment state: {"worn": {equip slot: instance}, "inventory": [instance, ...]} (CharacterSnapshot format 2
## `equipment`). Equip slots are SLOTS; an overall fills the top and bottom slots together, so "overall" is never worn
## beside "top" or "bottom", and a two-handed weapon (WeaponInfo.is_two_handed: tier B, Cosmic isTwoHanded) is never
## worn beside a "shield": wearing either moves the other to the inventory (`displaced_slots`). The inventory (Equip tab) holds at most `capacity` instances
## (balance.player.inventory_slots).
##
## Mutators change the state in place and return "" on success, otherwise a reason and the state is unchanged:
##   reqLevel, reqJob, reqSTR, reqDEX, reqINT, reqLUK - the v83 requirement the character fails (requirement_error)
##   inventory_full - the items that would move to the inventory do not fit
##   no_item - no inventory item at that index; empty - nothing worn in that slot
##   not_equipment - the item has no equip slot
## RunWorld applies them for the live character (equip_item, unequip_item, discard_item); UI and bots go through it.

## Equip slots in display/drawing order.
const SLOTS := ["hat", "top", "bottom", "overall", "shoes", "gloves", "weapon", "shield"]
## Item category (id / 10000) -> equip slot: Cap, Coat, Longcoat, Pants, Shoes, Glove, Shield (tier A: v83 Character.wz
## folders). Weapons are categories 130..169 (Weapon folder; 170 is cash weapon covers).
const CATEGORY_SLOTS := {100: "hat", 104: "top", 105: "overall", 106: "bottom", 107: "shoes", 108: "gloves", 109: "shield"}
## tier A: a new character's first MakeCharInfo option per field (Etc.wz/MakeCharInfo.img Info/CharMale "0":
## top, bottom, shoes, weapon); what a character without a snapshot wears.
const DEFAULT_OUTFIT := [1040002, 1060002, 1072001, 1302000]
## tier B: the v83 movement limits (speed 140%, jump 123%; client and server caps, emulator RE).
const SPEED_CAP := 140
const JUMP_CAP := 123
## tier A: v83 reqJob bits by job branch (job id / 100): 1 Warrior, 2 Magician, 4 Bowman, 8 Thief, 16 Pirate.
const JOB_BIT_THIEF := 8
const JOB_BITS := {1: 1, 2: 2, 3: 4, 4: JOB_BIT_THIEF, 5: 16}
## Requirement fields checked against the character's total main stats, in reporting order.
const STAT_REQS := {"reqSTR": "str", "reqDEX": "dex", "reqINT": "int", "reqLUK": "luk"}


## The equip slot of an item id ("" when it is not equipment worn in one of SLOTS).
@warning_ignore("integer_division")
static func slot_of(id: int) -> String:
	var category := id / 10000
	if category >= 130 and category < 170:
		return "weapon"
	return String(CATEGORY_SLOTS.get(category, ""))


## A fresh instance of item `id` from its canonical info: every non-zero numeric `inc*` value, `tuc` upgrade slots.
static func create(id: int, info: Dictionary) -> Dictionary:
	var stats := {}
	for key: Variant in info:
		var value: Variant = info[key]
		if String(key).begins_with("inc") and (value is int or value is float) and int(value) != 0:
			stats[String(key)] = int(value)
	return {"id": id, "stats": stats, "slots": maxi(0, int(info.get("tuc", 0))), "scrolls": 0}


## Spread cap per `inc*` key for a dropped item's random stats. tier B: the v83 server's rule (open server
## reimplementations): a stat varies by up to 10% of its base, rounded up, capped at 5 for these keys and at 10 for the
## defence and HP/MP keys; keys in neither list (resistances, craft) keep their base.
const DROP_SPREAD_CAP := {"incSTR": 5, "incDEX": 5, "incINT": 5, "incLUK": 5, "incPAD": 5, "incMAD": 5, "incACC": 5,
	"incEVA": 5, "incSpeed": 5, "incJump": 5, "incPDD": 10, "incMDD": 10, "incMHP": 10, "incMMP": 10}


## A dropped instance of item `id`: like create(), but every non-zero `inc*` stat in DROP_SPREAD_CAP is rolled uniformly
## by a whole number up to its spread either side of the canonical base (never below 0; a result of 0 is left out).
## Upgrade slots (`tuc`) never vary. All randomness comes from `rng`.
static func create_drop(id: int, info: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var instance := create(id, info)
	var rolled := {}
	for key: String in instance.stats:
		var base := int(instance.stats[key])
		var cap: int = DROP_SPREAD_CAP.get(key, 0)
		if cap > 0 and base > 0:
			var spread := mini(cap, ceili(float(base) * 0.1))
			base = maxi(0, base + rng.randi_range(-spread, spread))
		if base != 0:
			rolled[key] = base
	instance.stats = rolled
	return instance


## Whether `info`'s reqJob admits `job_id`: 0 admits every job, otherwise the branch's bit must be set (Beginner,
## job 0, has no bit and so only wears all-job items).
@warning_ignore("integer_division")
static func job_allows(info: Dictionary, job_id: int) -> bool:
	var mask := int(info.get("reqJob", 0))
	return mask == 0 or mask & int(JOB_BITS.get(job_id / 100, 0)) != 0


## An empty equipment state.
static func empty_state() -> Dictionary:
	return {"worn": {}, "inventory": []}


## Worn equipment from item ids (fresh instances from `infos`, {id: info}); ids without an equip slot are skipped.
static func worn_from_ids(ids: Array, infos: Dictionary) -> Dictionary:
	var worn := {}
	for raw: Variant in ids:
		var id := int(raw)
		var slot := slot_of(id)
		if slot == "":
			continue
		for gone: String in displaced_slots(worn, id):
			worn.erase(gone)
		worn[slot] = create(id, info_of(infos, id))
	return worn


## The canonical info of `id` in an {id: info} table with int or String keys ({} when absent).
static func info_of(infos: Dictionary, id: int) -> Dictionary:
	return infos.get(id, infos.get(str(id), {}))


## Worn item ids in SLOTS order (what is drawn).
static func worn_ids(worn: Dictionary) -> Array:
	var ids := []
	for slot: String in SLOTS:
		if worn.has(slot):
			ids.append(int(worn[slot].id))
	return ids


## Every held item id: worn (SLOTS order), then the inventory in order.
static func held_ids(state: Dictionary) -> Array:
	var ids := worn_ids(state.get("worn", {}))
	for instance: Dictionary in state.get("inventory", []):
		ids.append(int(instance.id))
	return ids


## Sum of one `inc*` stat over worn equipment.
static func total(worn: Dictionary, key: String) -> float:
	var sum := 0.0
	for instance: Dictionary in worn.values():
		sum += float(instance.stats.get(key, 0))
	return sum


## The first v83 requirement of `info` that `character` ({level, job_id, str, dex, int, luk}, total main stats
## including equipment) fails, as its WZ field name; "" when every requirement is met.
@warning_ignore("integer_division")
static func requirement_error(info: Dictionary, character: Dictionary) -> String:
	if int(character.get("level", 1)) < int(info.get("reqLevel", 0)):
		return "reqLevel"
	var mask := int(info.get("reqJob", 0))
	if mask != 0 and mask & int(JOB_BITS.get(int(character.get("job_id", 0)) / 100, 0)) == 0:
		return "reqJob"
	for field: String in STAT_REQS:
		if int(character.get(STAT_REQS[field], 0)) < int(info.get(field, 0)):
			return field
	return ""


## Why item `id` is not worn the moment it is picked up (#222), "" when it is: not equipment ("not_equipment"), its slot
## is taken or wearing it would take something off - an overall beside a top or bottom, a top or bottom beside an
## overall, a shield beside a two-handed weapon ("occupied") - or the `character` fails a requirement (the
## requirement_error field). Nothing is ever replaced, so the check is exactly "equip would displace nothing and pass".
static func auto_wear_error(worn: Dictionary, id: int, info: Dictionary, character: Dictionary) -> String:
	if slot_of(id) == "":
		return "not_equipment"
	if not displaced_slots(worn, id).is_empty():
		return "occupied"
	return requirement_error(info, character)


## Wears inventory[index] (canonical `info` for its requirements) after checking `character`'s requirements; the item
## it replaces (a worn top and bottom for an overall, a worn overall for a top or bottom) takes its inventory place,
## any second one is appended.
static func equip(state: Dictionary, index: int, info: Dictionary, character: Dictionary, capacity: int) -> String:
	var inventory: Array = state.inventory
	if index < 0 or index >= inventory.size():
		return "no_item"
	var instance: Dictionary = inventory[index]
	var slot := slot_of(int(instance.id))
	if slot == "":
		return "not_equipment"
	var reason := requirement_error(info, character)
	if reason != "":
		return reason
	var displaced := displaced_slots(state.worn, int(instance.id))
	if inventory.size() - 1 + displaced.size() > capacity:
		return "inventory_full"
	inventory.remove_at(index)
	for i in displaced.size():
		var moved: Dictionary = state.worn[displaced[i]]
		state.worn.erase(displaced[i])
		if i == 0:
			inventory.insert(index, moved)
		else:
			inventory.append(moved)
	state.worn[slot] = instance
	return ""


## Moves the item worn in `slot` to the end of the inventory.
static func unequip(state: Dictionary, slot: String, capacity: int) -> String:
	if not state.worn.has(slot):
		return "empty"
	if state.inventory.size() >= capacity:
		return "inventory_full"
	state.inventory.append(state.worn[slot])
	state.worn.erase(slot)
	return ""


## Removes inventory[index] for good (worn equipment cannot be discarded).
static func discard(state: Dictionary, index: int) -> String:
	if index < 0 or index >= state.inventory.size():
		return "no_item"
	state.inventory.remove_at(index)
	return ""


## Wears a granted instance without requirement checks; what it replaces moves to the inventory. Returns "" or
## "inventory_full" when the replaced items do not all fit: the grant is then skipped and the state is unchanged
## (tier C: nothing is ever destroyed; the character keeps what it wears).
static func grant(state: Dictionary, instance: Dictionary, capacity: int) -> String:
	var slot := slot_of(int(instance.id))
	var displaced := displaced_slots(state.worn, int(instance.id))
	if state.inventory.size() + displaced.size() > capacity:
		return "inventory_full"
	for moved_slot: String in displaced:
		state.inventory.append(state.worn[moved_slot])
		state.worn.erase(moved_slot)
	state.worn[slot] = instance
	return ""


## The worn slots (SLOTS order) that wearing item `id` takes off: its own slot; for an overall the top and bottom, for a
## top or bottom the overall; for a two-handed weapon the shield, and for a shield a worn two-handed weapon.
static func displaced_slots(worn: Dictionary, id: int) -> Array:
	var slot := slot_of(id)
	var slots: Array = ["top", "bottom", "overall"] if slot == "overall" \
		else [slot, "overall"] if slot in ["top", "bottom"] \
		else [slot, "shield"] if slot == "weapon" and WeaponInfo.is_two_handed(id) \
		else [slot, "weapon"] if slot == "shield" and worn.has("weapon") \
			and WeaponInfo.is_two_handed(int(worn.weapon.id)) \
		else [slot]
	return SLOTS.filter(func(s: String) -> bool: return s in slots and worn.has(s))


## Structural validation of an equipment state (snapshot `equipment`); "" when valid.
static func validation_error(value: Variant) -> String:
	if not value is Dictionary or not value.get("worn") is Dictionary or not value.get("inventory") is Array:
		return "invalid equipment"
	for slot: Variant in value.worn:
		if not slot is String or not slot in SLOTS:
			return "invalid equip slot"
		var error := _instance_error(value.worn[slot])
		if error != "":
			return error
		if slot_of(int(value.worn[slot].id)) != slot:
			return "equipment worn in the wrong slot"
	if value.worn.has("overall") and (value.worn.has("top") or value.worn.has("bottom")):
		return "an overall is worn with a top or bottom"
	if value.worn.has("shield") and value.worn.has("weapon") and WeaponInfo.is_two_handed(int(value.worn.weapon.id)):
		return "a two-handed weapon is worn with a shield"
	for instance: Variant in value.inventory:
		var error := _instance_error(instance)
		if error != "":
			return error
	return ""


static func _instance_error(value: Variant) -> String:
	if not value is Dictionary or not value.get("stats") is Dictionary:
		return "invalid equipment instance"
	for field: String in ["id", "slots", "scrolls"]:
		if not _whole(value.get(field)):
			return "invalid equipment " + field
	if slot_of(int(value.id)) == "":
		return "invalid equipment id"
	for key: Variant in value.stats:
		if not key is String or not String(key).begins_with("inc") or not _number(value.stats[key]):
			return "invalid equipment stat"
	return ""


## A validated state with every number as an int again (JSON parses numbers as float), detached from the input.
static func normalized(value: Dictionary) -> Dictionary:
	var worn := {}
	for slot: String in value.worn:
		worn[slot] = normalized_instance(value.worn[slot])
	var inventory := []
	for instance: Dictionary in value.inventory:
		inventory.append(normalized_instance(instance))
	return {"worn": worn, "inventory": inventory}


## One instance with integer fields and stats, detached from the input.
static func normalized_instance(instance: Dictionary) -> Dictionary:
	var stats := {}
	for key: String in instance.stats:
		stats[key] = int(instance.stats[key])
	return {"id": int(instance.id), "stats": stats, "slots": int(instance.slots), "scrolls": int(instance.scrolls)}


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _whole(value: Variant) -> bool:
	return _number(value) and float(value) >= 0.0 and float(value) == floorf(float(value))
