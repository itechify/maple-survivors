class_name CashShop
extends RefCounted
## The rules of the Cash Shop (spec #34 #118, ADR 0003): what is on each v83 tab, why an item is locked, and buying.
## Pure functions over the catalog (CashCatalog), the account's owned ids and a SaveData; no nodes. The screen
## (scenes/ui/cash_shop.gd) only draws and forwards clicks.
##
## Tabs: the v83 EQUIP. and PET tabs (the other tabs of the client are out of scope). An item is filed under the tab and
## sub-tab of its Commodity SN: SN = Category * 10^7 + CategorySub * 10^5 + index (Etc.wz/Category.img; tier A, so
## earrings sit under Face and shields under Weapon as in v83). Survivor-only items without an SN (VAC) are filed under
## Pet Equip. and listed last. Rings and the empty Premium sub-tab are left out.
##
## Buying (`buy`): the item must be listed, not owned, have its prerequisites owned and cost no more than the NX balance.
## The price is deducted and the item added in one SaveData.set_account write, so a refusal or a failed write changes
## nothing. There is no selling back.

## Refusal reasons returned by `buy`/`refusal`, in the order they are checked.
const REASONS := ["unlisted", "owned", "locked", "nx", "save"]
## The shop tabs and their sub-tabs, in the client's order (Category 2 = EQUIP., 6 = PET).
const TABS := [
	{"key": "equip", "name": "EQUIP.", "category": 2, "subs": ["Hat", "Face", "Eye", "Overall", "Top", "Bottom", "Shoes",
		"Glove", "Weapon", "Cape"]},
	{"key": "pet", "name": "PET", "category": 6, "subs": ["Pet", "Pet Equip."]},
]
## CategorySub index of each sub-tab name (tier A: Etc.wz/Category.img).
const SUB_INDEX := {"Hat": 0, "Face": 1, "Eye": 2, "Overall": 3, "Top": 4, "Bottom": 5, "Shoes": 6, "Glove": 7,
	"Weapon": 8, "Cape": 11, "Pet": 0, "Pet Equip.": 1}
## Character.wz folder of each equipment category (id / 10000) for icons.
const ICON_DIRS := {100: "Cap", 101: "Accessory", 102: "Accessory", 103: "Accessory", 104: "Coat", 105: "Longcoat",
	106: "Pants", 107: "Shoes", 108: "Glove", 109: "Shield", 110: "Cape", 170: "Weapon"}
const PET_CATEGORY := 6
const PET_EQUIP_SUB := 1
const MESSAGES := {
	"unlisted": "This item is not for sale.", # tier C: wording ours
	"owned": "You already own this item.", # tier C
	"locked": "You can't buy this item yet.", # tier C
	"nx": "You don't have enough NX.", # tier C: v83 shop notice, wording from memory
	"save": "Could not save your purchase. Check that the save folder is writable.", # tier C
}


## The tabs: [{key, name, category, subs: [sub-tab names]}].
static func tabs() -> Array:
	return TABS


## Catalog ids shown on a tab's sub-tab and not yet owned, in catalog order (survivor-only items last).
static func listing(catalog: CashCatalog, owned: Array, tab_key: String, sub: String) -> Array:
	var category := _category_of_tab(tab_key)
	var out: Array = []
	var survivor_only: Array = []
	for id: int in catalog.ids():
		if Account.owns(owned, id):
			continue
		var entry := catalog.item(id)
		var filed := _filing(entry)
		if filed.x != category or filed.y != int(SUB_INDEX.get(sub, -1)):
			continue
		if entry.has("sn"):
			out.append(id)
		else:
			survivor_only.append(id)
	out.sort_custom(func(a: int, b: int) -> bool: return int(catalog.item(a).sn) < int(catalog.item(b).sn))
	return out + survivor_only


## Why `id` can't be bought yet, as sentences ("Needs a pet."); empty when its prerequisites are owned. `name_of` maps an
## item id to its display name.
static func lock_reasons(catalog: CashCatalog, owned: Array, id: int, name_of: Callable) -> PackedStringArray:
	var out := PackedStringArray()
	var entry := catalog.item(id)
	for need: Variant in entry.get("requires", []):
		if not Account.owns(owned, int(need)):
			out.append("Needs %s." % name_of.call(int(need)))
	var any: Array = entry.get("requires_any", [])
	var have_any := any.is_empty()
	for need: Variant in any:
		have_any = have_any or Account.owns(owned, int(need))
	if not have_any:
		var all_pets := true
		for need: Variant in any:
			all_pets = all_pets and catalog.kind_of(int(need)) == "pet"
		if all_pets:
			out.append("Needs a pet.")
		else:
			var names := PackedStringArray()
			for need: Variant in any:
				names.append(String(name_of.call(int(need))))
			out.append("Needs one of: %s." % ", ".join(names))
	return out


## "" when `id` can be bought with `account` ({nx, owned}); else the first refusal reason (see REASONS).
static func refusal(account: Dictionary, catalog: CashCatalog, id: int) -> String:
	if catalog.item(id).is_empty():
		return "unlisted"
	var owned: Array = account.owned
	if Account.owns(owned, id):
		return "owned"
	if not catalog.prerequisites_met(id, owned):
		return "locked"
	if int(account.nx) < catalog.price_of(id):
		return "nx"
	return ""


## Buys `id` for the account in `save`: "" on success (saved), else the refusal reason; nothing changes on a refusal or when
## the write fails ("save").
static func buy(save: SaveData, catalog: CashCatalog, id: int) -> String:
	var account := save.account
	var reason := refusal(account, catalog, id)
	if reason != "":
		return reason
	var owned: Array = account.owned
	owned.append(id)
	if save.set_account({"nx": int(account.nx) - catalog.price_of(id), "owned": owned}) != OK:
		return "save"
	return ""


## `cash` ({slot: id}) after trying `id` on the preview avatar: the item takes its slots and drops any other item it
## overlaps (an overall leaves both top and bottom when a top is tried on). Anything that is not cash equipment changes nothing.
static func try_on(catalog: CashCatalog, cash: Dictionary, id: int) -> Dictionary:
	var slots := catalog.slots_for(id)
	var out := cash.duplicate()
	if slots.is_empty() or catalog.kind_of(id) != "equip":
		return out
	for slot: String in cash:
		if int(cash[slot]) != id and not _shares_slot(catalog.slots_for(int(cash[slot])), slots):
			continue
		for filled: String in catalog.slots_for(int(cash[slot])):
			out.erase(filled)
	for slot: String in slots:
		out[slot] = id
	return out


## WZ path of the 32x32 icon of a catalog item (survivor-only items name theirs in `icon`).
static func icon_path(catalog: CashCatalog, id: int) -> String:
	var entry := catalog.item(id)
	if entry.has("icon"):
		return String(entry.icon)
	@warning_ignore("integer_division")
	var category := id / 10000
	if category == 500:
		return "Item.wz/Pet/%07d.img/info/icon" % id
	if category == 181:
		return "Character.wz/PetEquip/%08d.img/info/icon" % id
	if not ICON_DIRS.has(category):
		return ""
	return "Character.wz/%s/%08d.img/info/icon" % [ICON_DIRS[category], id]


## Display name: the survivor entry's `name`, else String.wz (Pet.img, Eqp.img); "" when unknown or without a cache (`lib` null).
static func item_name(lib: AssetLibrary, catalog: CashCatalog, id: int) -> String:
	var own := String(catalog.item(id).get("name", ""))
	return own if own != "" else _string_field(lib, id, "name")


## Description, resolved like item_name.
static func item_desc(lib: AssetLibrary, catalog: CashCatalog, id: int) -> String:
	var own := String(catalog.item(id).get("desc", ""))
	return own if own != "" else _string_field(lib, id, "desc")


## The notice text for a refusal reason.
static func message(reason: String) -> String:
	return String(MESSAGES.get(reason, ""))


static func _shares_slot(a: PackedStringArray, b: PackedStringArray) -> bool:
	for slot: String in a:
		if b.has(slot):
			return true
	return false


static func _string_field(lib: AssetLibrary, id: int, field: String) -> String:
	if lib == null:
		return ""
	var v: Variant = null
	@warning_ignore("integer_division")
	if id / 10000 == 500:
		v = lib.find("String.wz/Pet.img/%d/%s" % [id, field])
	else:
		var eqp: Variant = lib.find("String.wz/Eqp.img/Eqp")
		if eqp is Dictionary:
			for group: Variant in (eqp as Dictionary).values():
				if group is Dictionary and (group as Dictionary).has(str(id)):
					v = (group[str(id)] as Dictionary).get(field, "")
					break
	return String(v) if v is String else ""


## (category, sub) of a catalog entry from its SN; survivor-only pet upgrades go under Pet Equip.
static func _filing(entry: Dictionary) -> Vector2i:
	if entry.has("sn"):
		var sn := int(entry.sn)
		@warning_ignore("integer_division")
		return Vector2i(sn / 10000000, (sn / 100000) % 100)
	return Vector2i(PET_CATEGORY, PET_EQUIP_SUB)


static func _category_of_tab(tab_key: String) -> int:
	for tab: Dictionary in TABS:
		if tab.key == tab_key:
			return int(tab.category)
	return -1
