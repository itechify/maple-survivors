class_name PotionInventory
extends RefCounted
## Unlimited per-kind potions with independent sim-time cooldowns (tier C: spec #237). Survivor data chooses the
## current item and cooldown; restore amounts come unchanged from canonical item specs. No files or clocks.

## Canonical starter item ids: Red Potion and Blue Potion (tier A).
const DEFAULT_ITEMS := {"hp": 2000000, "mp": 2000003}

var cooldown_left := {"hp": 0.0, "mp": 0.0}
var item_info: Dictionary
var used := {"hp": 0, "mp": 0}
## Potions the pet drank (spec #34); not part of `used`.
var pet_used := {"hp": 0, "mp": 0}

var _items := {}
var _cooldowns: Dictionary


func _init(tuning: Dictionary = {}, canonical_items: Dictionary = {}) -> void:
	item_info = canonical_items
	_cooldowns = tuning.get("cooldown", {})
	for kind: String in DEFAULT_ITEMS:
		var entry: Dictionary = tuning.get(kind, {})
		_items[kind] = int(entry.get("item_id", DEFAULT_ITEMS[kind]))


## The current canonical item for a kind (0 for an unknown kind).
func item_id(kind: String) -> int:
	return int(_items.get(kind, 0))


## The configured cooldown in seconds; tier C values live in balance.potions.cooldown.
func cooldown_total(kind: String) -> float:
	return maxf(0.0, float(_cooldowns.get(kind, 0.0)))


## Whether a known kind can be drunk now.
func is_ready(kind: String) -> bool:
	return _items.has(kind) and float(cooldown_left[kind]) <= 0.0


## Advances both cooldowns by one simulation tick. Paused runs do not call this.
func tick(dt: float) -> void:
	for kind: String in cooldown_left:
		cooldown_left[kind] = maxf(0.0, float(cooldown_left[kind]) - dt)


## Snapshot exposed to presentation as player_state.potions.
func snapshot() -> Dictionary:
	var out := {}
	for kind: String in _items:
		out[kind] = {"item_id": item_id(kind), "cooldown_left": float(cooldown_left[kind]),
			"cooldown_total": cooldown_total(kind)}
	return out


## Changes the current canonical item, preserving its cooldown; false for unavailable restore specs.
func upgrade(kind: String, next_item: int) -> bool:
	if not _items.has(kind) or item_id(kind) == next_item:
		return false
	var item: Dictionary = item_info.get(next_item, item_info.get(str(next_item), {}))
	if int(item.get("spec", {}).get(kind, 0)) <= 0:
		return false
	_items[kind] = next_item
	return true


## Canonical amount one current `kind` potion restores (0 for an unknown kind or a missing restore spec).
func restore_amount(kind: String) -> int:
	var id := item_id(kind)
	var item: Dictionary = item_info.get(id, item_info.get(str(id), {}))
	return int(item.get("spec", {}).get(kind, 0))


## Starts the cooldown and returns its canonical restore spec, or {} when unavailable (no count). A drink by
## the pet (`by_pet`, spec #34) is counted in `pet_used`, never in the player's `used`.
func consume(kind: String, by_pet: bool = false) -> Dictionary:
	if not is_ready(kind):
		return {}
	var id := item_id(kind)
	var amount := restore_amount(kind)
	if amount <= 0:
		return {}
	cooldown_left[kind] = cooldown_total(kind)
	if by_pet:
		pet_used[kind] = int(pet_used[kind]) + 1
	else:
		used[kind] = int(used[kind]) + 1
	return {"item_id": id, "amount": amount}
