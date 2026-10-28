class_name BotShop
extends RefCounted
## What the autoplay bots do with equipment and mesos (spec #33, #112): wearing the best item they own, and one shop plan
## per Free Market visit. Pure and static: plain Dictionaries and a seeded RandomNumberGenerator in, results out, no nodes.
## Beside BotInput; used by scripts/balance.sh (chain boundaries, mid-round), RunScene's autoplay and the hub's bot hook.
## Everything it changes goes through RunWorld's public equipment/shop API (equip_item, sell_item, buy_scroll,
## use_scroll), the same calls the windows make.
##
## Value of equipment: an instance scores the sum of weight x value over its `inc*` stats (balance.bot.equipment_weights,
## survivor data, tier C; a Magician wants M.ATT, INT, then defences). Scrolls already read onto an item are part of its
## stats, so they count.

## tier C: weights when balance.bot.equipment_weights is absent (W.ATT and M.ATT only).
const DEFAULT_WEIGHTS := {"incPAD": 1.0, "incMAD": 1.0}
## Most equip changes one auto_equip call makes (every change raises the worn score, so it ends long before this).
const EQUIP_GUARD := 32


## The stat weights for `job_id`: balance.bot.equipment_weights keyed by job id ("0" Beginner, "200" Magician, ...),
## the entry of the job or its nearest ancestor (JobTree.lineage), else "default", else DEFAULT_WEIGHTS.
static func weights_for(balance: Dictionary, job_id: int, jobs: JobTree) -> Dictionary:
	var table: Dictionary = balance.get("bot", {}).get("equipment_weights", {})
	for j in jobs.lineage(job_id):
		if table.has(str(j)):
			return table[str(j)]
	return table.get("default", DEFAULT_WEIGHTS)


## What `stats` ({"incMAD": 23, ...}) is worth under `weights`.
static func stats_score(stats: Dictionary, weights: Dictionary) -> float:
	var sum := 0.0
	for key: Variant in stats:
		sum += float(weights.get(key, 0.0)) * float(stats[key])
	return sum


## What an equipment instance is worth under `weights`.
static func item_score(instance: Dictionary, weights: Dictionary) -> float:
	return stats_score(instance.get("stats", {}), weights)


## Whether drained events contain an equipment pickup that warrants checking the equipment again.
static func equip_trigger(events: Array) -> bool:
	for e: Dictionary in events:
		var type := String(e.get("type", ""))
		if type == "pickup_collected" and String(e.get("kind", "")) == "equip":
			return true
	return false


## The mid-round hook of every bot loop: auto_equip when `events` (the drained RunWorld events) are an equip_trigger, else
## nothing. Returns how many items it put on.
static func equip_after(w: RunWorld, events: Array) -> int:
	return auto_equip(w) if equip_trigger(events) else 0


## Wears, for every equip slot, the best wearable item of the Equip tab: one that scores higher than what it replaces (an
## overall against the top and bottom it displaces, an empty slot against nothing) and that the item's job class and the
## tab's room allow. Repeats until nothing improves (a better top can raise INT enough for a wand). Returns how many items
## it put on. No RNG.
static func auto_equip(w: RunWorld) -> int:
	var weights := weights_for(w.balance, w.progression.job_id, w.jobs)
	var worn_count := 0
	for _pass in EQUIP_GUARD:
		var candidates: Array = []
		for index in w.equipment.inventory.size():
			var instance: Dictionary = w.equipment.inventory[index]
			var slot := Equipment.slot_of(int(instance.id))
			if slot == "":
				continue
			var gain := item_score(instance, weights) - _displaced_score(w.equipment.worn, int(instance.id), weights)
			if gain > 1e-9:
				candidates.append(Vector2(gain, index))
		candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x > b.x or (a.x == b.x and a.y < b.y))
		var improved := false
		for c: Vector2 in candidates:
			if w.equip_item(int(c.y)) == "":
				worn_count += 1
				improved = true
				break
		if not improved:
			break
	return worn_count


## Score of what wearing item `id` takes off (Equipment.displaced_slots: a top or bottom displaces an overall, an overall
## both, a two-handed weapon the shield, a shield a held two-handed weapon).
static func _displaced_score(worn: Dictionary, id: int, weights: Dictionary) -> float:
	var sum := 0.0
	for s: String in Equipment.displaced_slots(worn, id):
		sum += item_score(worn[s], weights)
	return sum


# --- the Free Market visit ---

## Card policies (balance_run's `random`) map to these two shopping policies.
const POLICY_SENSIBLE := "sensible"
const POLICY_CARELESS := "careless"
## tier C: the sensible bot buys only the 100% and 60% scrolls (never the dark ones, whose failure destroys the item).
const SENSIBLE_RATES := ["100", "60"]
## tier C: the order a sensible bot spends on: weapon, overall and gloves first (the owner's rule), then the rest.
const SLOT_PRIORITY := ["weapon", "overall", "gloves", "hat", "top", "bottom", "shoes", "shield"]
## Most plans one visit applies: a plan is redone after a dark scroll destroys an item, nothing else changes it.
const MAX_PASSES := 8
## Most scrolls a careless plan buys (31 upgrade slots on a full set of seven-slot items is far below it).
const CARELESS_GUARD := 400


## The shopping policy of balance card policy `policy`: `random` is the careless player, every other policy the sensible one.
static func policy_for(policy: String) -> String:
	return POLICY_CARELESS if policy == "random" else POLICY_SENSIBLE


## The part of live character `w` that plan() reads: {level, job_id, stats {str, dex, int, luk}, mesos, scrolls,
## equipment {worn, inventory}}, detached from the world.
static func character_of(w: RunWorld) -> Dictionary:
	var stats := {}
	for key: String in ["str", "dex", "int", "luk"]:
		stats[key] = int(w.player_state.get(key, 0))
	return {"level": w.progression.level, "job_id": w.progression.job_id, "stats": stats, "mesos": w.mesos,
		"scrolls": w.scrolls.duplicate(), "equipment": w.equipment.duplicate(true)}


## What every Free Market NPC sells `w`'s job: Shop.stock entries of all NPCs in shops.json order, each with its `npc` id.
static func stock_of(w: RunWorld) -> Array:
	var out := []
	for npc: Dictionary in w.data.get("shops", {}).get("npcs", []):
		for entry: Dictionary in w.shop_stock(int(npc.id)):
			var annotated := entry.duplicate()
			annotated["npc"] = int(npc.id)
			out.append(annotated)
	return out


## The canonical facts plan() needs: {equipment_info, scroll_info (from the setup), weights (the job's stat weights)}.
static func facts_of(w: RunWorld) -> Dictionary:
	return {"equipment_info": w.setup.get("equipment_info", {}), "scroll_info": w.setup.get("scroll_info", {}),
		"weights": weights_for(w.balance, w.progression.job_id, w.jobs)}


## The shop plan for a visit: `{"sell": [Equip-tab indices, last first], "steps": [...]}` where steps run in order,
## `{"op": "buy", "npc": id, "scroll": id, "count": n}` and `{"op": "use", "scroll": id, "slot": equip slot}`. Pure: it reads
## `character` (see character_of), `stock` (stock_of), `facts` (facts_of) and, for the careless policy only, draws from `rng`.
## Applying it through RunWorld (visit) never spends more than the character's mesos plus what the sales bring in.
##
## Sensible (tier C): sell the equipment it will not wear (what auto_equip would not put on, unless it is a better item that
## only a higher level is missing); then, for each worn item with upgrade slots in SLOT_PRIORITY order, read the scroll of
## its item type (100% and 60% only) with the best expected stat score (success chance x weights), using the scrolls it
## already holds first and buying the rest while the mesos last, one scroll per upgrade slot.
## Careless (tier C): sells nothing; while some worn item has a slot left and an affordable scroll of its type exists (any
## rate, dark ones included), picks a random (item, scroll) pair from `rng`, buys it and reads it at once.
static func plan(character: Dictionary, stock: Array, facts: Dictionary, policy: String, rng: RandomNumberGenerator) -> Dictionary:
	return _plan_careless(character, stock, facts, rng) if policy == POLICY_CARELESS \
		else _plan_sensible(character, stock, facts)


static func _plan_sensible(character: Dictionary, stock: Array, facts: Dictionary) -> Dictionary:
	var weights: Dictionary = facts.get("weights", DEFAULT_WEIGHTS)
	var equipment_info: Dictionary = facts.get("equipment_info", {})
	var worn: Dictionary = character.equipment.worn
	var inventory: Array = character.equipment.inventory
	var sell := []
	var budget := int(character.get("mesos", 0))
	for index in inventory.size():
		if _keeps(inventory[index], character, equipment_info, weights):
			continue
		var price := Shop.sale_price(Equipment.info_of(equipment_info, int(inventory[index].id)))
		if price > 0:
			sell.push_front(index)
			budget += price
	var held: Dictionary = character.get("scrolls", {}).duplicate()
	var steps := []
	for slot: String in SLOT_PRIORITY:
		if not worn.has(slot) or int(worn[slot].slots) <= 0:
			continue
		var pick := _best_scroll(worn[slot], stock, facts, weights)
		if pick.is_empty():
			continue
		var id := int(pick.id)
		var left := int(worn[slot].slots)
		var from_hand := mini(left, int(held.get(str(id), 0)))
		var price := maxi(1, int(pick.price))
		var to_buy := mini(left - from_hand, budget / price)
		if to_buy > 0:
			steps.append({"op": "buy", "npc": int(pick.npc), "scroll": id, "count": to_buy})
			budget -= price * to_buy
		held[str(id)] = int(held.get(str(id), 0)) - from_hand
		for _i in from_hand + to_buy:
			steps.append({"op": "use", "scroll": id, "slot": slot})
	return {"sell": sell, "steps": steps}


static func _plan_careless(character: Dictionary, stock: Array, facts: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var scroll_info: Dictionary = facts.get("scroll_info", {})
	var worn: Dictionary = character.equipment.worn
	var budget := int(character.get("mesos", 0))
	var held: Dictionary = character.get("scrolls", {}).duplicate()
	var left := {}
	for slot: String in worn:
		left[slot] = int(worn[slot].slots)
	var steps := []
	for _guard in CARELESS_GUARD:
		var options := []
		for slot: String in Equipment.SLOTS:
			if not worn.has(slot) or int(left[slot]) <= 0:
				continue
			var category := Scrolls.category_of_item(int(worn[slot].id))
			for entry: Dictionary in stock:
				var id := int(entry.id)
				if Scrolls.category_of_scroll(id) == category and _scroll_info(scroll_info, id).has("success") \
						and (int(held.get(str(id), 0)) > 0 or int(entry.price) <= budget):
					options.append([slot, entry])
		if options.is_empty():
			break
		var pick: Array = options[rng.randi_range(0, options.size() - 1)]
		var id := int(pick[1].id)
		if int(held.get(str(id), 0)) > 0:
			held[str(id)] = int(held[str(id)]) - 1
		else:
			steps.append({"op": "buy", "npc": int(pick[1].npc), "scroll": id, "count": 1})
			budget -= int(pick[1].price)
		steps.append({"op": "use", "scroll": id, "slot": pick[0]})
		left[pick[0]] = int(left[pick[0]]) - 1
	return {"sell": [], "steps": steps}


## Whether a sensible bot keeps spare equipment `instance`: it would be an upgrade for its slot and its job class admits it.
static func _keeps(instance: Dictionary, character: Dictionary, equipment_info: Dictionary, weights: Dictionary) -> bool:
	var id := int(instance.id)
	var slot := Equipment.slot_of(id)
	if slot == "":
		return false
	if item_score(instance, weights) - _displaced_score(character.equipment.worn, id, weights) <= 1e-9:
		return false
	var who := {"job_id": int(character.get("job_id", 0))}
	return Equipment.requirement_error(Equipment.info_of(equipment_info, id), who) == ""


## The stock entry whose scroll fits `instance` and has the best expected score (success chance x its stats under
## `weights`); only the 100% and 60% rates; ties go to the higher success chance, then the lower id. {} when none scores.
static func _best_scroll(instance: Dictionary, stock: Array, facts: Dictionary, weights: Dictionary) -> Dictionary:
	var scroll_info: Dictionary = facts.get("scroll_info", {})
	var category := Scrolls.category_of_item(int(instance.id))
	var best := {}
	var best_score := 0.0
	var best_success := 0
	for entry: Dictionary in stock:
		var id := int(entry.id)
		if Scrolls.category_of_scroll(id) != category or not String(entry.rate) in SENSIBLE_RATES:
			continue
		var info := _scroll_info(scroll_info, id)
		if not info.has("success"):
			continue
		var success := int(info.success)
		var score := float(success) / 100.0 * stats_score(info, weights)
		if score > best_score + 1e-9 or (absf(score - best_score) <= 1e-9 and best_score > 0.0
				and (success > best_success or (success == best_success and id < int(best.id)))):
			best = entry
			best_score = score
			best_success = success
	return best


static func _scroll_info(infos: Dictionary, id: int) -> Dictionary:
	return infos.get(id, infos.get(str(id), {}))


## One Free Market visit of live character `w` (the hub's map-less RunWorld or the next round's world): wears the best
## items, then applies plan() through sell_item, buy_scroll and use_scroll, and plans again after a dark scroll destroys an
## item. `policy` is a balance card policy (policy_for); `rng` feeds the careless plan only. Returns the record:
## {equipped, sold, sale_mesos, bought, spent, used, succeeded, failed, destroyed, refused {reason: n}, mesos_before,
## mesos_after, scrolls_left, worn {slot: item id}}.
static func visit(w: RunWorld, policy: String, rng: RandomNumberGenerator) -> Dictionary:
	var record := {"equipped": auto_equip(w), "sold": 0, "sale_mesos": 0, "bought": 0, "spent": 0, "used": 0,
		"succeeded": 0, "failed": 0, "destroyed": 0, "refused": {}, "mesos_before": w.mesos}
	var shopping := policy_for(policy)
	for _pass in MAX_PASSES:
		var plan := plan(character_of(w), stock_of(w), facts_of(w), shopping, rng)
		if not _apply(w, plan, record):
			break
	var left := 0
	for count: Variant in w.scrolls.values():
		left += int(count)
	record["scrolls_left"] = left
	record["mesos_after"] = w.mesos
	var worn := {}
	for slot: String in w.equipment.worn:
		worn[slot] = int(w.equipment.worn[slot].id)
	record["worn"] = worn
	return record


## Runs `plan` on `w`, tallying into `record`; refused steps are counted and skipped. True when a scroll destroyed an item
## (the rest of the plan is dropped, the caller plans again).
static func _apply(w: RunWorld, plan: Dictionary, record: Dictionary) -> bool:
	for index: int in plan.sell:
		var before := w.mesos
		var reason := w.sell_item(index)
		if reason == "":
			record.sold += 1
			record.sale_mesos += w.mesos - before
		else:
			_refused(record, reason)
	for step: Dictionary in plan.steps:
		if step.op == "buy":
			var before := w.mesos
			var reason := w.buy_scroll(int(step.npc), int(step.scroll), int(step.count))
			if reason == "":
				record.bought += int(step.count)
				record.spent += before - w.mesos
			else:
				_refused(record, reason)
			continue
		var reason := w.use_scroll(int(step.scroll), String(step.slot))
		if reason != "":
			_refused(record, reason)
			continue
		record.used += 1
		var result := String(w.events.back().get("result", "")) if not w.events.is_empty() else ""
		match result:
			"success":
				record.succeeded += 1
			"failure":
				record.failed += 1
			"destroyed":
				record.destroyed += 1
				return true
	return false


static func _refused(record: Dictionary, reason: String) -> void:
	record.refused[reason] = int(record.refused.get(reason, 0)) + 1
