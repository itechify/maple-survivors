class_name UpgradePool
extends RefCounted
## Data-driven upgrade cards (`data/survivor/upgrades.json`, docs/GAME_DESIGN.md section 8): eligibility, seeded
## weighted draws and applying a card to a run. `state` is the RunWorld (its loadout, progression, jobs and player).
##
## Eligible = requirements met and rank < max_rank (0 = unlimited): `requires.jobs` (the job is one of them or a
## descendant), `requires.skills` (owned), `requires.min_rank` ({skill: rank}), `requires.min_level`; skill_new also
## needs the skill unowned and a free slot of its kind; skill_rank / skill_mod need the skill owned (skill_rank also
## below the skill's max rank). Potion tiers require a current item and level from data. A draw picks up to the
## requested number of distinct eligible cards by weight with the given RNG; when the run has a pending `guarantee`
## ({kind, job}) the first card is drawn among the eligible cards of that kind whose requires.jobs lists that job,
## and the guarantee is consumed. Pity (upgrades.json `pity.draws` = N > 0): after N draws in a row that offered no
## "power" card (cards flagged `"power": true`: new attack skills, attack skill ranks, more shots / targets / damage),
## the next draw's first card is drawn among the eligible power cards, so a run's damage cannot stall on bad offers.
## RunWorld.power_dry counts those draws.

var cards: Array = []
## Draws in a row without a power card after which a power card is guaranteed (0 = no pity).
var pity_draws := 0
var _by_id := {}


## Builds the pool from the upgrades.json root ({"cards": [...]}).
static func from_data(root: Dictionary) -> UpgradePool:
	var p := UpgradePool.new()
	var pity: Variant = root.get("pity", {})
	if pity is Dictionary:
		p.pity_draws = maxi(0, int(pity.get("draws", 0)))
	for c: Dictionary in root.get("cards", []):
		var id := String(c.get("id", ""))
		if id == "" or p._by_id.has(id):
			continue
		p._by_id[id] = c
		p.cards.append(c)
	return p


## The card definition ({} when unknown).
func card(id: String) -> Dictionary:
	return _by_id.get(id, {})


## Times card `id` was taken in this run.
func rank(id: String, state: RunWorld) -> int:
	return int(state.loadout.card_ranks.get(id, 0))


## Ids of the cards eligible now, in data order.
func eligible(state: RunWorld) -> Array:
	var out: Array = []
	for c: Dictionary in cards:
		if is_eligible(c, state):
			out.append(String(c.id))
	return out


## Whether card `c` may be offered now.
func is_eligible(c: Dictionary, state: RunWorld) -> bool:
	var lo: Loadout = state.loadout
	var id := String(c.get("id", ""))
	var max_rank := int(c.get("max_rank", 1))
	if max_rank > 0 and rank(id, state) >= max_rank:
		return false
	var req: Dictionary = c.get("requires", {}) if c.get("requires") is Dictionary else {}
	var jobs: Array = req.get("jobs", [])
	if not jobs.is_empty():
		var ok := false
		for j: Variant in jobs:
			if state.jobs.is_descendant(state.progression.job_id, int(j)):
				ok = true
				break
		if not ok:
			return false
	for s: Variant in req.get("skills", []):
		if not lo.has(String(s)):
			return false
	var min_rank: Dictionary = req.get("min_rank", {}) if req.get("min_rank") is Dictionary else {}
	for s: String in min_rank:
		if lo.rank(s) < int(min_rank[s]):
			return false
	if state.progression.level < int(req.get("min_level", 0)):
		return false
	for potion_kind: String in req.get("potions", {}):
		if int(state.potions.stock.get(potion_kind, {}).get("item_id", 0)) != int(req.potions[potion_kind]):
			return false
	var skill := String(c.get("skill", ""))
	match String(c.get("kind", "")):
		"skill_new":
			if not lo.book.has(skill) or lo.has(skill) or not lo.has_free_slot(lo.book.slot(skill)):
				return false
		"skill_rank":
			if not lo.has(skill) or lo.rank(skill) >= lo.book.max_rank(skill):
				return false
		"skill_mod":
			if not lo.has(skill):
				return false
	return true


## Draws up to n distinct eligible cards and returns them as choice_pending cards (see
## choice_card for the fields).
func roll_choices(state: RunWorld, rng: RandomNumberGenerator, n: int = 3) -> Array:
	var pool := eligible(state)
	var picked: Array = []
	var g: Dictionary = state.guarantee
	if g.is_empty() and pity_draws > 0 and state.power_dry >= pity_draws:
		g = {"power": true}
	if not g.is_empty():
		state.guarantee = {}
		var gpool: Array = []
		for id: String in pool:
			var c := card(id)
			if bool(g.get("power", false)):
				if is_power(c):
					gpool.append(id)
			elif String(c.get("kind", "")) == String(g.get("kind", "")) and _lists_job(c, int(g.get("job", -1))):
				gpool.append(id)
		var gid := _weighted_pick(gpool, rng)
		if gid != "":
			picked.append(gid)
			pool.erase(gid)
	while picked.size() < n and not pool.is_empty():
		var id := _weighted_pick(pool, rng)
		picked.append(id)
		pool.erase(id)
	var out: Array = []
	var power := false
	for id: String in picked:
		out.append(choice_card(id, state))
		power = power or is_power(card(id))
	state.power_dry = 0 if power else state.power_dry + 1
	return out


## True for a card flagged `"power": true` (it raises an attack skill's damage output).
static func is_power(c: Dictionary) -> bool:
	return bool(c.get("power", false))


## The choice_pending entry of card `id` for the current run: {id, kind, name, desc, icon, rank (the card's rank once
## taken), max_rank, skill, skill_name (the skill's name, "" for cards without a skill), skill_level (the skill's
## canonical level now, 0 when not owned), skill_level_next (its canonical level once the card is taken; 0 when the card
## does not change the level: skill_new and skill_rank cards only), skill_changes (rank cards: canonical field ->
## {before, after}; mastery is a percent, all other values are the original WZ numbers)}.
func choice_card(id: String, state: RunWorld) -> Dictionary:
	var c := card(id)
	var desc := String(c.get("desc", ""))
	if c.has("value"):
		desc = desc.replace("{value}", _fmt(c.value))
	var kind := String(c.get("kind", ""))
	var skill := String(c.get("skill", ""))
	var skill_name := ""
	var level := 0
	var level_next := 0
	var changes := {}
	var lo: Loadout = state.loadout
	if skill != "" and lo.book.has(skill):
		skill_name = String(lo.book.def(skill).get("name", skill))
		var r := lo.rank(skill) if lo.has(skill) else 0
		level = lo.book.canonical_level(skill, r) if r > 0 else 0
		if kind == "skill_new":
			level_next = lo.book.canonical_level(skill, 1)
		elif kind == "skill_rank" and r > 0:
			level_next = lo.book.canonical_level(skill, r + _rank_step(c))
			var before := lo.book.level_node(skill, level)
			var after := lo.book.level_node(skill, level_next)
			for field: String in ["mad", "mastery", "mpCon", "fixdamage", "time", "x", "pdd"]:
				if before.has(field) and after.has(field):
					var a := int(lo.book.canonical(skill, level, field))
					var b := int(lo.book.canonical(skill, level_next, field))
					if field == "mastery":
						a = roundi(CombatMath.mastery_fraction(a) * 100.0)
						b = roundi(CombatMath.mastery_fraction(b) * 100.0)
					changes[field] = {"before": a, "after": b}
	return {
		"id": id,
		"kind": kind,
		"name": String(c.get("name", id)),
		"desc": desc,
		"icon": String(c.get("icon", "")),
		"rank": rank(id, state) + 1,
		"max_rank": int(c.get("max_rank", 1)),
		"skill": skill,
		"skill_name": skill_name,
		"skill_level": level,
		"skill_level_next": level_next,
		"skill_changes": changes,
	}


## Survivor ranks a skill_rank card adds (the sum of its "rank" effects, at least 1).
static func _rank_step(c: Dictionary) -> int:
	var n := 0
	for e: Dictionary in c.get("effects", []):
		if String(e.get("stat", "")) == "rank":
			n += int(e.get("value", 0))
	return maxi(1, n)


## Applies card `id` to the run (learn / rank up / modifiers / potion tier), emits upgrade_applied (and skill_learned for
## skill_new) and returns the card's new rank (0 when the card is unknown).
func apply(id: String, state: RunWorld) -> int:
	var c := card(id)
	if c.is_empty():
		return 0
	var kind := String(c.get("kind", ""))
	if kind == "potion_tier":
		if not is_eligible(c, state) or not state.upgrade_potion(String(c.get("potion_kind", "")), int(c.get("item_id", 0))):
			return 0
	var lo: Loadout = state.loadout
	var r := rank(id, state) + 1
	lo.card_ranks[id] = r
	var skill := String(c.get("skill", ""))
	if kind == "skill_new":
		state.learn_skill(skill)
	for e: Dictionary in c.get("effects", []):
		var stat := String(e.get("stat", ""))
		var op := String(e.get("op", "add"))
		var value := float(e.get("value", 0.0))
		if kind in ["skill_new", "skill_rank", "skill_mod"] and skill != "":
			if stat == "rank":
				lo.set_rank(skill, lo.rank(skill) + int(value))
			else:
				lo.add_skill_mod(skill, stat, op, value)
		else:
			lo.add_player_mod(stat, op, value)
	state.refresh_player_stats()
	state.emit("upgrade_applied", {"id": id, "rank": r})
	return r


func _lists_job(c: Dictionary, job: int) -> bool:
	var req: Variant = c.get("requires", {})
	if not (req is Dictionary):
		return false
	for j: Variant in req.get("jobs", []):
		if int(j) == job:
			return true
	return false


func _weighted_pick(ids: Array, rng: RandomNumberGenerator) -> String:
	if ids.is_empty():
		return ""
	var total := 0.0
	for id: String in ids:
		total += maxf(0.0, float(card(id).get("weight", 1.0)))
	if total <= 0.0:
		return ids[rng.randi_range(0, ids.size() - 1)]
	var r := rng.randf() * total
	for id: String in ids:
		r -= maxf(0.0, float(card(id).get("weight", 1.0)))
		if r < 0.0:
			return id
	return ids[ids.size() - 1]


static func _fmt(v: Variant) -> String:
	var f := float(v)
	return str(int(f)) if f == floorf(f) else str(f)
