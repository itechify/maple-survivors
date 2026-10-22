class_name Shop
extends RefCounted
## The Free Market's scroll shops (GLOSSARY "Mesos and equipment", ADR 0002, #111). Pure and static: plain
## Dictionaries in, results out, no nodes, files or RNG. RunWorld applies it for the live character (shop_stock,
## buy_scroll, sell_item, sell_scrolls) and the bot planner (#112) calls the same functions on a plain snapshot.
##
## Character state: the part of a CharacterSnapshot the shop reads and writes, `{"mesos": int, "scrolls": {"<id>":
## count}, "equipment": {"worn": {...}, "inventory": [...]}}`. Every mutator changes the state in place
## and returns "" on success, otherwise one of these reasons and the state is unchanged:
##   count      - a quantity below 1
##   mesos      - not enough mesos
##   use_full   - the Use tab has no room for the whole quantity (a stack stops at the scroll's slotMax and the tab
##                holds USE_SLOTS stacks); buying is all-or-nothing, as v83 refuses a purchase that does not fit
##   no_item    - nothing at that inventory index / fewer scrolls than asked
##   worn       - worn equipment cannot be sold until it is taken off
##   unsellable - the item has no price (info/price) to be bought back at
##   not_sold   - the NPC does not sell that scroll (RunWorld only)
##
## Stock (stock()): an NPC sells its rates (shops.json npcs[].rates) of every scroll family (scrolls.json) whose
## item category some equipment in the drop list (equipment_drops.json items) can reach for the character's job
## (Equipment.job_allows), unlimited, in file order. A Beginner therefore sees only scrolls for all-job equipment.
## Every scroll costs the price of its slot (shops.json prices), whatever its rate. Selling pays the item's own
## `info/price` (tier B: v83's sell rule); selling never depends on which NPC is open.

## Reasons a sale or purchase can be refused with (see the header).
const REASONS := ["count", "mesos", "use_full", "no_item", "worn", "unsellable", "not_sold"]


## The stock of one NPC for `job_id`, `[{"id": scroll id, "slot": "hat", "family": "DEF", "rate": "100", "price": 35000}]`.
## `npc` is a shops.json npcs entry ({id, rates}), `rules` shops.json (prices), `table` scrolls.json, `drop_items` the
## equipment_drops.json item ids and `infos` the canonical equipment info ({id: info}).
static func stock(npc: Dictionary, rules: Dictionary, table: Dictionary, drop_items: Array, infos: Dictionary,
		job_id: int) -> Array:
	var reachable := reachable_categories(drop_items, infos, job_id)
	var out := []
	var families: Dictionary = table.get("families", {})
	for slot: String in families:
		for family: String in families[slot]:
			var by_rate: Dictionary = families[slot][family]
			for rate: Variant in npc.get("rates", []):
				if not by_rate.has(rate):
					continue
				var id := int(by_rate[rate])
				if not reachable.has(Scrolls.category_of_scroll(id)):
					continue
				out.append({"id": id, "slot": slot, "family": family, "rate": String(rate),
					"price": price_of(slot, rules)})
	return out


## The item categories (Scrolls.category_of_item) of the drop-list equipment `job_id` can wear, as a set {category: true}.
static func reachable_categories(drop_items: Array, infos: Dictionary, job_id: int) -> Dictionary:
	var out := {}
	for raw: Variant in drop_items:
		var id := int(raw)
		var info := Equipment.info_of(infos, id)
		if not info.is_empty() and Equipment.job_allows(info, job_id):
			out[Scrolls.category_of_item(id)] = true
	return out


## What a scroll for `slot` ("hat", "wand", ...) costs: shops.json prices.weapon for its weapon_slots, else prices.armour.
static func price_of(slot: String, rules: Dictionary) -> int:
	var prices: Dictionary = rules.get("prices", {})
	return int(prices.get("weapon", 0)) if slot in rules.get("weapon_slots", []) else int(prices.get("armour", 0))


## How many scroll stacks the Use tab holds. The optional legacy potion state never occupies a slot.
static func use_stack_limit(_potions: Dictionary = {}) -> int:
	return Scrolls.USE_SLOTS


## Whether `count` more scrolls of `id` fit the Use tab (`slot_max` as in Scrolls.add).
static func scrolls_fit(state: Dictionary, id: int, count: int, slot_max: int) -> bool:
	var stacks: Dictionary = state.get("scrolls", {})
	var held := int(stacks.get(str(id), 0))
	if held == 0 and stacks.size() >= use_stack_limit(state.get("potions", {})):
		return false
	var cap := slot_max if slot_max > 0 else Scrolls.DEFAULT_SLOT_MAX
	return held + count <= cap


## Buys `count` of scroll `id` at `price` each: all-or-nothing, mesos first, then room ("mesos", "use_full", "count").
## `slot_max` is the scroll's info/slotMax (0 for none).
static func buy(state: Dictionary, id: int, count: int, price: int, slot_max: int) -> String:
	if count <= 0:
		return "count"
	if int(state.get("mesos", 0)) < price * count:
		return "mesos"
	if not scrolls_fit(state, id, count, slot_max):
		return "use_full"
	if not state.has("scrolls"):
		state["scrolls"] = {}
	Scrolls.add(state.scrolls, id, count, slot_max, use_stack_limit(state.get("potions", {})))
	state["mesos"] = int(state.mesos) - price * count
	return ""


## What a shop pays for an item with canonical `info` (info/price), 0 when it has none.
static func sale_price(info: Dictionary) -> int:
	return maxi(0, int(info.get("price", 0)))


## Sells the spare equipment at inventory `index` for its info/price ("no_item", "unsellable").
static func sell_equipment(state: Dictionary, index: int, info: Dictionary) -> String:
	var inventory: Array = state.get("equipment", {}).get("inventory", [])
	if index < 0 or index >= inventory.size():
		return "no_item"
	var price := sale_price(info)
	if price <= 0:
		return "unsellable"
	inventory.remove_at(index)
	state["mesos"] = int(state.get("mesos", 0)) + price
	return ""


## Worn equipment cannot be sold: "worn" (or "no_item" for an empty slot); nothing ever changes.
static func sell_worn(state: Dictionary, slot: String) -> String:
	return "worn" if state.get("equipment", {}).get("worn", {}).has(slot) else "no_item"


## Sells `count` scrolls of `id` at their info/price ("count", "no_item" when fewer are held, "unsellable").
static func sell_scrolls(state: Dictionary, id: int, count: int, info: Dictionary) -> String:
	if count <= 0:
		return "count"
	var stacks: Dictionary = state.get("scrolls", {})
	var key := str(id)
	if int(stacks.get(key, 0)) < count:
		return "no_item"
	var price := sale_price(info)
	if price <= 0:
		return "unsellable"
	var left := int(stacks[key]) - count
	if left > 0:
		stacks[key] = left
	else:
		stacks.erase(key)
	state["mesos"] = int(state.get("mesos", 0)) + price * count
	return ""
