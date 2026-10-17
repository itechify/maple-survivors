class_name Scrolls
extends RefCounted
## v83 scrolls on worn equipment (GLOSSARY "Mesos and equipment", #110). Pure and static: plain Dictionaries and a
## seeded RandomNumberGenerator in, results out, no nodes. RunWorld applies it for the live character (use_scroll,
## grant_scrolls); UI and bots go through RunWorld.
##
## A scroll's facts come from WZ `Item.wz/Consume/0204.img/<id>/info` as passed in (`success` percent, `cursed`
## percent for dark scrolls, `inc*` stats, `slotMax`); which ids exist in the game is survivor data
## (game/data/survivor/scrolls.json, see ids()).
##
## use() rules (v83): the scroll must fit the worn item (`(scrollId / 100) % 100 == (itemId / 10000) % 100`) and the
## item needs an upgrade slot left. A roll 0-99 below `success` adds the scroll's `inc*` to the instance and counts a
## scroll; either way one upgrade slot is spent. A failed dark scroll (`cursed` > 0) then destroys the item when a
## second 0-99 roll is below `cursed`. The scroll itself is used up by the caller whatever happens.
##
## Refusals (the scroll is kept, nothing changes): "not_worn" (the target is not an equip slot), "empty" (nothing
## worn there), "scroll_unknown" (no info or no `info/success`: tier C, a scroll without a rate is never usable),
## "scroll_type" (wrong item type) and "scroll_slots" (no upgrade slot left).

## Outcomes of use(); anything else it returns is a refusal.
const OUTCOMES := ["success", "failure", "destroyed"]
## tier A: the v83 Use tab has 24 slots; a stack holds at most info/slotMax scrolls (100 when WZ names none).
const USE_SLOTS := 24
const DEFAULT_SLOT_MAX := 100


## The scroll category of a scroll id (`(id / 100) % 100`), equal to an item's `(id / 10000) % 100` when it fits.
@warning_ignore("integer_division")
static func category_of_scroll(scroll_id: int) -> int:
	return (scroll_id / 100) % 100


## The scroll category an equipment item takes (`(id / 10000) % 100`).
@warning_ignore("integer_division")
static func category_of_item(item_id: int) -> int:
	return (item_id / 10000) % 100


## Every scroll id in the game (scrolls.json `families`), ascending.
static func ids(table: Dictionary) -> Array:
	var out := []
	for family_list: Dictionary in table.get("families", {}).values():
		for family: Dictionary in family_list.values():
			for rate: Variant in family:
				var id := int(family[rate])
				if not id in out:
					out.append(id)
	out.sort()
	return out


## The refusal for scroll `scroll_id` (canonical `info`) on a worn `instance`, "" when it may be used.
static func target_error(scroll_id: int, info: Dictionary, instance: Dictionary) -> String:
	if not info.has("success"):
		return "scroll_unknown"
	if category_of_scroll(scroll_id) != category_of_item(int(instance.id)):
		return "scroll_type"
	if int(instance.slots) <= 0:
		return "scroll_slots"
	return ""


## Applies scroll `scroll_id` (canonical `info`) to the item worn in `slot` of `worn`; returns "success", "failure" or
## "destroyed" (the item is removed from `worn`), or a refusal (see the header) with everything unchanged.
static func use(worn: Dictionary, slot: String, scroll_id: int, info: Dictionary, rng: RandomNumberGenerator) -> String:
	if not slot in Equipment.SLOTS:
		return "not_worn"
	if not worn.has(slot):
		return "empty"
	var instance: Dictionary = worn[slot]
	var reason := target_error(scroll_id, info, instance)
	if reason != "":
		return reason
	instance.slots = int(instance.slots) - 1
	if rng.randi_range(0, 99) < int(info.success):
		for key: Variant in info:
			var value: Variant = info[key]
			if String(key).begins_with("inc") and (value is int or value is float) and int(value) != 0:
				instance.stats[key] = int(instance.stats.get(key, 0)) + int(value)
		instance.scrolls = int(instance.scrolls) + 1
		return "success"
	var cursed := int(info.get("cursed", 0))
	if cursed > 0 and rng.randi_range(0, 99) < cursed:
		worn.erase(slot)
		return "destroyed"
	return "failure"


## Adds up to `count` scrolls of `id` to the Use stacks {"<id>": count}: a stack stops at `slot_max` (0 or less means
## DEFAULT_SLOT_MAX) and a new stack needs one of `max_stacks`. Returns how many were added.
static func add(stacks: Dictionary, id: int, count: int, slot_max: int, max_stacks: int) -> int:
	var key := str(id)
	if count <= 0 or (not stacks.has(key) and stacks.size() >= max_stacks):
		return 0
	var room := (slot_max if slot_max > 0 else DEFAULT_SLOT_MAX) - int(stacks.get(key, 0))
	var added := clampi(count, 0, maxi(0, room))
	if added > 0:
		stacks[key] = int(stacks.get(key, 0)) + added
	return added


## Takes one scroll of `id` out of the stacks (the stack goes with its last scroll); false when there is none.
static func take(stacks: Dictionary, id: int) -> bool:
	var key := str(id)
	var count := int(stacks.get(key, 0))
	if count <= 0:
		return false
	if count == 1:
		stacks.erase(key)
	else:
		stacks[key] = count - 1
	return true
