class_name CashCatalog
extends RefCounted
## The cash item catalog (survivor data `cash_items.json`), the eleven cash slots and Fortune from worn cash
## equipment (spec #34, ADR 0003). Plain data in, plain data out: no nodes, files or RNG.
##
## Cash slots (exact keys): hat, face, eye, earrings, top, bottom, shoes, gloves, cape, weapon, shield. A slot comes
## from the canonical item id (id / 10000: 100 hat, 101 face, 102 eye, 103 earrings, 104 top, 105 overall, 106 bottom,
## 107 shoes, 108 gloves, 109 shield, 110 cape, 170 weapon cover). An overall fills top and bottom; a catalog item with
## `two_handed: true` (a weapon cover) fills weapon and shield. Rings are not cash slots.
##
## `resolve()` is the one rule for what a character's worn cash equipment and pet are worth in a round: only items the
## account owns count, each filled slot adds its `slot_fortune`, and everything ignored is reported as a warning.

## The cash slots, in display order.
const SLOTS := ["hat", "face", "eye", "earrings", "top", "bottom", "shoes", "gloves", "cape", "weapon", "shield"]
const OVERALL_CATEGORY := 105
const WEAPON_COVER_CATEGORY := 170
## Slot of each single-slot category (id / 10000).
const CATEGORY_SLOT := {100: "hat", 101: "face", 102: "eye", 103: "earrings", 104: "top", 106: "bottom",
	107: "shoes", 108: "gloves", 109: "shield", 110: "cape", WEAPON_COVER_CATEGORY: "weapon"}

## Fortune added by each filled slot (survivor data, tier C placeholders).
var slot_fortune := {}
var _items := {}


## Builds the catalog from setup.data (`data.cash_items`); missing data is an empty catalog with no Fortune.
static func from_data(data: Dictionary) -> CashCatalog:
	var catalog := CashCatalog.new()
	var file: Dictionary = data.get("cash_items", {})
	var fortune: Dictionary = file.get("slot_fortune", {})
	for slot: String in SLOTS:
		if fortune.has(slot):
			catalog.slot_fortune[slot] = float(fortune[slot])
	for item: Dictionary in file.get("items", []):
		catalog._items[int(item.id)] = item
	return catalog


## The catalog entry of `id`, or {} when it is not listed.
func item(id: int) -> Dictionary:
	return _items.get(id, {})


## "equip", "pet" or "pet_upgrade"; "" when the id is not listed.
func kind_of(id: int) -> String:
	return String(item(id).get("kind", ""))


## NX price of a listed item; 0 when it is not listed.
func price_of(id: int) -> int:
	return int(item(id).get("price", 0))


## Every listed item id, ascending.
func ids() -> Array:
	var out: Array = _items.keys()
	out.sort()
	return out


## Whether an item's prerequisites are owned: all of `requires` and at least one of `requires_any`.
func prerequisites_met(id: int, owned: Array) -> bool:
	var entry := item(id)
	for need: Variant in entry.get("requires", []):
		if not Account.owns(owned, int(need)):
			return false
	var any: Array = entry.get("requires_any", [])
	if any.is_empty():
		return true
	for need: Variant in any:
		if Account.owns(owned, int(need)):
			return true
	return false


## The cash slots a worn item fills: one slot, top + bottom for an overall, weapon + shield for a two-handed cover;
## empty for anything that is not cash equipment.
func slots_for(id: int) -> PackedStringArray:
	@warning_ignore("integer_division")
	var category := id / 10000
	if category == OVERALL_CATEGORY:
		return PackedStringArray(["top", "bottom"])
	if not CATEGORY_SLOT.has(category):
		return PackedStringArray()
	if category == WEAPON_COVER_CATEGORY and bool(item(id).get("two_handed", false)):
		return PackedStringArray(["weapon", "shield"])
	return PackedStringArray([CATEGORY_SLOT[category]])


## `cash` ({slot: id}) after wearing catalog equipment `id` (spec #34 #122): the item takes its slots and every item
## that covered one of them leaves ALL the slots it covered, so an overall clears top and bottom, a top or bottom takes
## the overall off, and a two-handed cover takes weapon and shield (a shield or one-handed cover takes it off).
## Anything that is not cash equipment changes nothing. Ownership is the caller's rule (RunWorld.wear_cash).
func wear(cash: Dictionary, id: int) -> Dictionary:
	var slots := slots_for(id)
	var out := _expanded(cash)
	if slots.is_empty() or kind_of(id) != "equip":
		return out
	for slot: String in slots:
		if out.has(slot):
			_clear(out, int(out[slot]))
	for slot: String in slots:
		out[slot] = id
	return out


## `cash` after taking off whatever is worn in `slot`, from every slot that item covers; an empty slot changes nothing.
func take_off(cash: Dictionary, slot: String) -> Dictionary:
	var out := _expanded(cash)
	if out.has(slot):
		_clear(out, int(out[slot]))
	return out


## A copy of `cash` with every item under all the slots it covers (an overall stored under `top` alone fills `bottom`
## too, as resolve() reads it).
func _expanded(cash: Dictionary) -> Dictionary:
	var out := cash.duplicate()
	for slot: String in cash:
		var id := int(cash[slot])
		if slots_for(id).has(slot):
			for filled: String in slots_for(id):
				out[filled] = id
	return out


## Removes item `id` from every slot of `cash` that holds it.
static func _clear(cash: Dictionary, id: int) -> void:
	for slot: String in cash.keys():
		if int(cash[slot]) == id:
			cash.erase(slot)


## What a character's worn cash equipment `cash` ({slot: item id}) and `pet` (species id, 0 = none) are worth when the
## account owns `owned` (item ids): {worn: {slot: id} of every slot actually filled, fortune: float, pet: int (0 when
## there is none or it is not an owned pet), warnings: PackedStringArray of what was ignored}.
func resolve(cash: Dictionary, pet: int, owned: Array) -> Dictionary:
	var worn := {}
	var warnings := PackedStringArray()
	var slots: Array = cash.keys()
	slots.sort_custom(func(a: Variant, b: Variant) -> bool: return SLOTS.find(a) < SLOTS.find(b))
	for slot: String in slots:
		var id := int(cash[slot])
		if not SLOTS.has(slot):
			warnings.append("cash slot '%s' does not exist: item %d ignored" % [slot, id])
		elif not slots_for(id).has(slot):
			warnings.append("cash item %d does not fit the %s slot: ignored" % [id, slot])
		elif not Account.owns(owned, id):
			warnings.append("cash item %d is not owned by the account: ignored" % id)
		else:
			for filled: String in slots_for(id):
				worn[filled] = id
	var fortune := 0.0
	for slot: String in worn:
		fortune += float(slot_fortune.get(slot, 0.0))
	var out_pet := 0
	if pet > 0:
		if kind_of(pet) != "pet":
			warnings.append("item %d is not a pet: ignored" % pet)
		elif not Account.owns(owned, pet):
			warnings.append("pet %d is not owned by the account: ignored" % pet)
		else:
			out_pet = pet
	return {"worn": worn, "fortune": fortune, "pet": out_pet, "warnings": warnings}
