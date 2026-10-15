class_name PotionInventory
extends RefCounted
## Unlimited per-kind potion stock and canonical item restore amounts. Survivor data chooses the current item and
## starting count; the item spec comes unchanged from setup.item_info. This module never reads files.

## tier C: conservative fallback stock for synthetic callers; real runs supply balance.potions explicitly.
## Restoration never falls back to a guessed amount.
const START := {"hp": {"item_id": 2000000, "start": 5}, "mp": {"item_id": 2000003, "start": 0}}

var stock := {}
var item_info: Dictionary
var collected := {"hp": 0, "mp": 0}
var used := {"hp": 0, "mp": 0}


func _init(tuning: Dictionary = {}, canonical_items: Dictionary = {}) -> void:
	item_info = canonical_items
	for kind: String in START:
		var entry: Dictionary = tuning.get(kind, START[kind])
		stock[kind] = {"item_id": int(entry.get("item_id", START[kind].item_id)), "count": int(entry.get("start", 0))}


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


## Consumes one potion and returns its canonical restore spec and remaining count, or {} when unavailable.
func consume(kind: String) -> Dictionary:
	if not stock.has(kind) or int(stock[kind].count) <= 0:
		return {}
	var id := int(stock[kind].item_id)
	var item: Dictionary = item_info.get(id, item_info.get(str(id), {}))
	var amount := int(item.get("spec", {}).get(kind, 0))
	if amount <= 0:
		return {}
	stock[kind].count = int(stock[kind].count) - 1
	used[kind] = int(used[kind]) + 1
	return {"item_id": id, "amount": amount, "count": int(stock[kind].count)}
