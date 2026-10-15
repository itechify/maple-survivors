class_name PotionInventory
extends RefCounted
## Unlimited per-kind potion stock and canonical item restore amounts. Survivor data chooses the current item and
## starting count; the item spec comes unchanged from setup.item_info. This module never reads files.

## Potion kinds and their fallback starter items (Red 2000000, Blue 2000003, as balance.potions). Starting counts live
## only in balance.potions (0 without data); restoration never falls back to a guessed amount.
const DEFAULT_ITEMS := {"hp": 2000000, "mp": 2000003}

var stock := {}
var item_info: Dictionary
var collected := {"hp": 0, "mp": 0}
var used := {"hp": 0, "mp": 0}


func _init(tuning: Dictionary = {}, canonical_items: Dictionary = {}) -> void:
	item_info = canonical_items
	for kind: String in DEFAULT_ITEMS:
		var entry: Dictionary = tuning.get(kind, {})
		stock[kind] = {"item_id": int(entry.get("item_id", DEFAULT_ITEMS[kind])), "count": int(entry.get("start", 0))}


## Snapshot exposed to presentation as player_state.potions.
func snapshot() -> Dictionary:
	return stock.duplicate(true)


## Adds collected potions to unlimited stock; false for an unknown kind or non-positive bundle.
func add(kind: String, count: int = 1) -> bool:
	if not stock.has(kind) or count <= 0:
		return false
	stock[kind].count = int(stock[kind].count) + count
	collected[kind] = int(collected[kind]) + count
	return true


## Changes a kind's current canonical item while preserving stock; false for unavailable restore specs.
func upgrade(kind: String, item_id: int) -> bool:
	if not stock.has(kind) or int(stock[kind].item_id) == item_id:
		return false
	var item: Dictionary = item_info.get(item_id, item_info.get(str(item_id), {}))
	if int(item.get("spec", {}).get(kind, 0)) <= 0:
		return false
	stock[kind].item_id = item_id
	return true


## Canonical amount one current `kind` potion restores (0 for an unknown kind or a missing restore spec).
func restore_amount(kind: String) -> int:
	if not stock.has(kind):
		return 0
	var id := int(stock[kind].item_id)
	var item: Dictionary = item_info.get(id, item_info.get(str(id), {}))
	return int(item.get("spec", {}).get(kind, 0))


## Consumes one potion and returns its canonical restore spec and remaining count, or {} when unavailable.
func consume(kind: String) -> Dictionary:
	if not stock.has(kind) or int(stock[kind].count) <= 0:
		return {}
	var id := int(stock[kind].item_id)
	var amount := restore_amount(kind)
	if amount <= 0:
		return {}
	stock[kind].count = int(stock[kind].count) - 1
	used[kind] = int(used[kind]) + 1
	return {"item_id": id, "amount": amount, "count": int(stock[kind].count)}
