class_name UpgradePool
extends RefCounted
## Data-driven upgrade cards (`data/survivor/upgrades.json`, docs/GAME_DESIGN.md section 8): eligibility, seeded
## weighted draws and applying a card to a run. `state` is the RunWorld (its loadout, progression, jobs and player).
##
## Eligible = requirements met and rank < max_rank (0 = unlimited): `requires.jobs` (exact current job id),
## `requires.skills` (owned), `requires.min_rank` ({skill: rank}), `requires.min_level`; skill_new also
## needs the skill unowned; skill_rank / skill_mod need the skill owned (skill_rank also below its max rank).
## Potion tiers require a current item and level from data. Draws pick distinct eligible cards with seeded weights.
## Cards of a skill (any kind with a `skill`) are eligible only while the weapon held when the draw rolls can use the
## skill (SkillBook.usable_with with RunWorld.held_weapon_family); the advancement draw goes through the same check.
## An accepted job opens a separate roll_advancement_choices draw before the normal level draw.
## Pity (upgrades.json `pity.draws` = N > 0): after N draws in a row that offered no
## "power" card (cards flagged `"power": true`: new attack skills, attack skill ranks, more shots / targets / damage),
## the next draw's first card is drawn among the eligible power cards, so a run's damage cannot stall on bad offers.
## RunWorld.power_dry counts those draws. A sparse draw adds one separate `fallback` card (Power Elixir, full HP/MP),
## never weighted; an exhausted pool offers it alone. Tier C: survivor reward rule, preserving earlier-job skills.
## Each scalable offer rolls a Potential tier with the same seeded RNG. Fortune shifts only tier odds; magnitude
## tables resolve the skill ranks / modifier steps. Headroom downgrades happen before preview and application.

## Canonical level fields a rank card previews as before -> after (mastery converted to percent), in display order.
const PREVIEW_FIELDS := ["mad", "mastery", "mpCon", "fixdamage", "time", "x", "pdd", "mdd", "acc", "eva", "mobCount", "cooltime", "speed", "range", "hp",
	"damage", "hpCon"]
## Preview keys of passive skills whose canonical number means something else than its field name (the Warrior
## passives, #163): Max HP per level-up for Improved MaxHP Increase (field x), HP per regeneration pulse for Improved HP
## Recovery (field hp, which is a percent for Heal), seconds between rope recoveries for Endure (field time).
const PASSIVE_MAX_HP := Loadout.MAX_HP_PER_LEVEL
const PASSIVE_REGEN_HP := "regen_hp"
const PASSIVE_CLIMB_INTERVAL := "climb_interval"
const PASSIVE_PREVIEW_KEYS := [Loadout.MAX_MP_PERCENT, PASSIVE_MAX_HP, PASSIVE_REGEN_HP, PASSIVE_CLIMB_INTERVAL]
## Skill modifier stats a skill_mod card previews. Each is its own skill_mod_changes key, except "count", which is
## SkillRunner.count_meaning of the skill's kind ("shots" or "targets").
const MOD_PREVIEW := ["count", "pierce", "cooldown", "speed", "range", "area", "damage", "crit"]
## tier C: survivor Potential ladder order; weights and Fortune scaling live in upgrades.json.
const TIERS := ["normal", "rare", "epic", "unique", "legendary"]

var cards: Array = []
## Draws in a row without a power card after which a power card is guaranteed (0 = no pity).
var pity_draws := 0
var _rarity := {}
var _magnitudes := {}
var _by_id := {}
var _fallback_id := ""


## Fresh zero counts for every Potential tier, in ladder order.
static func empty_tier_counts() -> Dictionary:
	var counts := {}
	for tier: String in TIERS:
		counts[tier] = 0
	return counts


## Builds the pool from the upgrades.json root ({cards: [...], fallback: card}). The fallback is never weighted.
static func from_data(root: Dictionary) -> UpgradePool:
	var p := UpgradePool.new()
	p._rarity = root.get("rarity", {})
	p._magnitudes = root.get("magnitudes", {})
	var pity: Variant = root.get("pity", {})
	if pity is Dictionary:
		p.pity_draws = maxi(0, int(pity.get("draws", 0)))
	for c: Dictionary in root.get("cards", []):
		var id := String(c.get("id", ""))
		if id == "" or p._by_id.has(id):
			continue
		p._by_id[id] = c
		p.cards.append(c)
	var fallback: Dictionary = root.get("fallback", {})
	var fallback_id := String(fallback.get("id", ""))
	if fallback_id != "" and not p._by_id.has(fallback_id):
		p._fallback_id = fallback_id
		p._by_id[fallback_id] = fallback
	return p


## The card definition ({} when unknown).
func card(id: String) -> Dictionary:
	return _by_id.get(id, {})


## Consumed rank/modifier steps of card `id`; a one-time learn or potion card consumes one.
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
	# Spec #34: a pet with VAC pulls every drop, so the Magnet card (any card raising the magnet stat) is never offered.
	if state.pet_has("vac") and _raises_stat(c, "magnet"):
		return false
	var req: Dictionary = c.get("requires", {}) if c.get("requires") is Dictionary else {}
	var jobs: Array = req.get("jobs", [])
	if not jobs.is_empty():
		var ok := false
		for j: Variant in jobs:
			if state.progression.job_id == int(j):
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
	# Spec #151 (#156): a skill's cards are offered only while the held weapon can use the skill.
	if skill != "" and not lo.book.usable_with(skill, state.held_weapon_family()):
		return false
	match String(c.get("kind", "")):
		"skill_new":
			if not lo.book.has(skill) or lo.has(skill):
				return false
		"skill_rank":
			if not lo.has(skill) or lo.rank(skill) >= lo.book.max_rank(skill):
				return false
		"skill_mod":
			if not lo.has(skill):
				return false
	return true


## Draws up to n distinct eligible cards, adding one fallback alternative when short (see choice_card for fields).
func roll_choices(state: RunWorld, rng: RandomNumberGenerator, n: int = 3) -> Array:
	var pool := eligible(state)
	if state.choice_bonus:
		# tier C: an almost-maxed rank card that cannot sustain Rare is omitted from boss rewards. Potion and
		# Elixir are explicitly Normal exceptions to the boss floor, so an exhausted reward still opens a window.
		pool = pool.filter(func(id: String) -> bool:
			return _always_normal(card(id)) or _honest_tier(card(id), state, "rare") != "normal")
	var picked: Array = []
	if pity_draws > 0 and state.power_dry >= pity_draws:
		var gpool: Array = []
		for id: String in pool:
			var c := card(id)
			if is_power(c):
				gpool.append(id)
		var gid := _weighted_pick(gpool, rng)
		if gid != "":
			picked.append(gid)
			pool.erase(gid)
	while picked.size() < n and not pool.is_empty():
		var id := _weighted_pick(pool, rng)
		picked.append(id)
		pool.erase(id)
	if picked.size() < n and _fallback_id != "":
		picked.append(_fallback_id)
	var out: Array = []
	var power := false
	for id: String in picked:
		var offered := choice_card(id, state, "normal" if _always_normal(card(id)) else _roll_tier(state, rng))
		out.append(offered)
		state.card_tiers_offered[String(offered.tier)] += 1
		power = power or is_power(card(id))
	state.power_dry = 0 if power else state.power_dry + 1
	return out


## Extra job draw: every eligible new power skill, then seeded new-skill choices of that exact job up to n.
## Tier C: no slot caps or prerequisites; a sparse draw includes the usual Elixir alternative.
func roll_advancement_choices(state: RunWorld, rng: RandomNumberGenerator, n: int = 3) -> Array:
	var picked: Array = []
	var other: Array = []
	for id: String in eligible(state):
		var c := card(id)
		if String(c.get("kind", "")) != "skill_new" or not _lists_job(c, state.progression.job_id):
			continue
		if is_power(c):
			picked.append(id)
		else:
			other.append(id)
	while picked.size() < n and not other.is_empty():
		var id := _weighted_pick(other, rng)
		picked.append(id)
		other.erase(id)
	if picked.size() < n and _fallback_id != "":
		picked.append(_fallback_id)
	var out: Array = []
	var power := false
	for id: String in picked:
		var offered := choice_card(id, state, "normal" if _always_normal(card(id)) else _roll_tier(state, rng))
		out.append(offered)
		state.card_tiers_offered[String(offered.tier)] += 1
		power = power or is_power(card(id))
	state.power_dry = 0 if power else state.power_dry + 1
	return out


## Whether card `c` has an effect on player stat `stat`.
static func _raises_stat(c: Dictionary, stat: String) -> bool:
	for effect: Variant in c.get("effects", []):
		if effect is Dictionary and String(effect.get("stat", "")) == stat:
			return true
	return false


## True for a card flagged `"power": true` (it raises an attack skill's damage output).
static func is_power(c: Dictionary) -> bool:
	return bool(c.get("power", false))


## The choice_pending entry of card `id` for the current run: {id, kind, name, desc, icon, tier (honest lowercase
## Potential tier), magnitude (ranks/steps/starting rank), rank_before, rank (consumed steps after taking it),
## max_rank, skill, skill_name (the skill's name, "" for cards without a skill), skill_level (the skill's
## canonical level now, 0 when not owned), skill_level_next (its canonical level once the card is taken; 0 when the card
## does not change the level: skill_new and skill_rank cards only), skill_level_max (the skill's canonical level cap, 0
## for cards without a skill), skill_changes (rank cards: canonical field ->
## {before, after} for PREVIEW_FIELDS; mastery is a percent, other values are original WZ numbers; a survivor per-level
## passive shows only its own stat in percent, e.g. Loadout.MAX_MP_PERCENT), skill_effect_stat (the skill's
## skills.json buff `stat`, e.g. "hp" for Recovery, "mp_guard" for Magic Guard; "" for other skills),
## skill_mod_changes (skill_mod cards on an owned skill: effective value -> {before, after} once all the card's steps
## are taken, keys as MOD_PREVIEW names them: shots / targets / pierce / speed / range (whole numbers), cooldown
## (seconds between casts as SkillRunner.restart_cooldown counts them, two decimals), area / damage / crit (percent);
## {} otherwise)}.
func choice_card(id: String, state: RunWorld, tier: String = "normal") -> Dictionary:
	var c := card(id)
	tier = _honest_tier(c, state, tier)
	var magnitude := _magnitude(c, state, tier)
	var desc := describe(id, magnitude)
	var kind := String(c.get("kind", ""))
	var skill := String(c.get("skill", ""))
	var skill_name := ""
	var level := 0
	var level_next := 0
	var level_max := 0
	var changes := {}
	var effect_stat := ""
	var lo: Loadout = state.loadout
	if skill != "" and lo.book.has(skill):
		skill_name = String(lo.book.def(skill).get("name", skill))
		level_max = lo.book.canonical_level(skill, lo.book.max_rank(skill))
		effect_stat = String(lo.book.def(skill).get("buff", {}).get("stat", ""))
		var buff_effects: Array = lo.book.def(skill).get("buff", {}).get("effects", [])
		if effect_stat == "" and not buff_effects.is_empty():
			effect_stat = String(buff_effects[0].stat)
		if String(lo.book.def(skill).get("cast", {}).get("rule", "")) == "crowd":
			effect_stat = "slow"
		var r := lo.rank(skill) if lo.has(skill) else 0
		level = lo.book.canonical_level(skill, r) if r > 0 else 0
		if kind == "skill_new":
			level_next = lo.book.canonical_level(skill, magnitude)
		elif kind == "skill_rank" and r > 0:
			level_next = lo.book.canonical_level(skill, r + magnitude)
			var before := lo.book.level_node(skill, level)
			var after := lo.book.level_node(skill, level_next)
			for field: String in PREVIEW_FIELDS:
				if before.has(field) and after.has(field):
					var a := int(lo.book.canonical(skill, level, field))
					var b := int(lo.book.canonical(skill, level_next, field))
					if field == "mastery":
						a = roundi(CombatMath.mastery_fraction(a) * 100.0)
						b = roundi(CombatMath.mastery_fraction(b) * 100.0)
					changes[field] = {"before": a, "after": b}
			var renamed := _passive_preview(lo.book.def(skill))
			if not renamed.is_empty() and changes.has(renamed[0]):
				changes[renamed[1]] = changes[renamed[0]]
				changes.erase(renamed[0])
			var passive: Dictionary = lo.book.def(skill).get("passive", {})
			if passive.has("per_level"):
				# tier C: a survivor per-level passive (Improved MaxMP Increase) previews its own fraction as a percent,
				# not the canonical fields it reinterprets.
				changes = {String(passive.stat): {"before": roundi(lo.passive_value(skill, level, passive) * 100.0),
					"after": roundi(lo.passive_value(skill, level_next, passive) * 100.0)}}
	return {
		"id": id,
		"tier": tier,
		"magnitude": magnitude,
		"kind": kind,
		"name": String(c.get("name", id)),
		"desc": desc,
		"icon": String(c.get("icon", "")),
		"rank": rank(id, state) + _consumed_steps(c, magnitude),
		"rank_before": rank(id, state),
		"max_rank": int(c.get("max_rank", 1)),
		"skill": skill,
		"skill_name": skill_name,
		"skill_level": level,
		"skill_level_next": level_next,
		"skill_level_max": level_max,
		"skill_changes": changes,
		"skill_effect_stat": effect_stat,
		"skill_mod_changes": _mod_changes(c, lo, magnitude) if kind == "skill_mod" and lo.has(skill) else {},
	}


## [canonical field, preview key] for a Warrior passive whose number a rank card shows under another name (see
## PASSIVE_MAX_HP), else [].
static func _passive_preview(d: Dictionary) -> Array:
	var regen: Variant = d.get("regen")
	if regen is Dictionary and regen.has("field") and String(regen.get("pool", "")) == "hp":
		return [String(regen.field), PASSIVE_REGEN_HP]
	var passive: Dictionary = d.get("passive", {})
	if String(passive.get("stat", "")) == PASSIVE_MAX_HP and passive.has("field"):
		return [String(passive.field), PASSIVE_MAX_HP]
	var climb: Variant = d.get("climb_regen")
	if climb is Dictionary:
		return [String(climb.get("interval_field", "time")), PASSIVE_CLIMB_INTERVAL]
	return []


## Card `id`'s desc for `magnitude` ranks / steps: {magnitude} filled in, {value} as the scaled or compounded value
## (the level-up card and the Skill window's star tab both show it).
func describe(id: String, magnitude: int) -> String:
	var c := card(id)
	var desc := String(c.get("desc", "")).replace("{magnitude}", str(magnitude))
	if c.has("value"):
		desc = desc.replace("{value}", _fmt(_description_value(c, magnitude)))
	return desc


## The effective values a skill_mod card's `magnitude` steps change, measured on a scratch copy of the loadout with
## the steps stacked exactly as apply() stacks them.
static func _mod_changes(c: Dictionary, lo: Loadout, magnitude: int) -> Dictionary:
	var skill := String(c.get("skill", ""))
	var preview := lo.clone()
	var touched := []
	for e: Dictionary in c.get("effects", []):
		var stat := String(e.get("stat", ""))
		var op := String(e.get("op", "add"))
		if not stat in MOD_PREVIEW:
			continue
		var value := float(e.get("value", 0.0))
		preview.add_skill_mod(skill, stat, op, pow(value, magnitude) if op == "mul" else value * magnitude)
		touched.append(stat)
	var before := lo.stats(skill)
	var after := preview.stats(skill)
	var out := {}
	for stat: String in touched:
		if stat == "count":
			out[SkillRunner.count_meaning(String(before.kind))] = {"before": SkillRunner.strike_count(before),
				"after": SkillRunner.strike_count(after)}
		else:
			out[stat] = {"before": _preview_value(stat, before, lo, skill),
				"after": _preview_value(stat, after, preview, skill)}
	return out


static func _preview_value(stat: String, st: Dictionary, lo: Loadout, skill: String) -> Variant:
	match stat:
		"cooldown":
			return snappedf(SkillRunner.restart_cooldown(st), 0.01)
		"area":
			return roundi(float(st.area) * 100.0)
		"damage":
			return roundi(lo.skill_stat(skill, "damage", 1.0) * 100.0)
		"crit":
			return roundi(float(st.crit) * 100.0)
	return roundi(float(st[stat]))


## Survivor ranks a skill_rank card adds (the sum of its "rank" effects, at least 1).
static func _rank_step(c: Dictionary) -> int:
	var n := 0
	for e: Dictionary in c.get("effects", []):
		if String(e.get("stat", "")) == "rank":
			n += int(e.get("value", 0))
	return maxi(1, n)


func _magnitude(c: Dictionary, state: RunWorld, tier: String) -> int:
	if _always_normal(c):
		return 1
	var headroom := _headroom(c, state)
	var value := _requested_magnitude(c, state, tier)
	return mini(headroom, value) if headroom >= 0 else value


func _tier_value(c: Dictionary, tier: String) -> Variant:
	var kind := String(c.get("kind", ""))
	var defaults: Dictionary = _magnitudes.get("stacking" if _is_stacking(c) else kind, {})
	var table: Dictionary = c.get("magnitudes", {})
	return table.get(tier, defaults.get(tier, _rank_step(c) if kind == "skill_rank" else 1))


func _headroom(c: Dictionary, state: RunWorld) -> int:
	var kind := String(c.get("kind", ""))
	var max_rank := int(c.get("max_rank", 0))
	var card_left := maxi(0, max_rank - rank(String(c.get("id", "")), state)) if max_rank > 0 else -1
	if kind == "skill_rank":
		var skill_left := state.book.max_rank(String(c.get("skill", ""))) - state.loadout.rank(String(c.get("skill", "")))
		return mini(skill_left, card_left) if card_left >= 0 else skill_left
	if kind == "skill_new":
		return state.book.max_rank(String(c.get("skill", "")))
	return card_left


func _requested_magnitude(c: Dictionary, state: RunWorld, tier: String) -> int:
	var value: Variant = _tier_value(c, tier)
	return _headroom(c, state) if str(value) == "max" else maxi(1, int(value))


func _honest_tier(c: Dictionary, state: RunWorld, tier: String) -> String:
	if _always_normal(c):
		return "normal"
	var headroom := _headroom(c, state)
	var index := maxi(0, TIERS.find(tier))
	while index > 0:
		var requested := _requested_magnitude(c, state, TIERS[index])
		if requested < 1 or (headroom >= 0 and requested > headroom):
			index -= 1
			continue
		# tier C: a tier that merely equals a lower one (a jackpot spending the last few steps, or an equal per-card
		# table entry) wears the lowest tier giving the same gain, so a label never overstates the card.
		var label := index
		for lower in range(index - 1, -1, -1):
			if _requested_magnitude(c, state, TIERS[lower]) == requested:
				label = lower
		return TIERS[label]
	return "normal"


static func _always_normal(c: Dictionary) -> bool:
	return String(c.get("kind", "")) in ["potion_tier", "filler"]


static func _is_stacking(c: Dictionary) -> bool:
	return String(c.get("kind", "")) in ["skill_mod", "stat", "passive"]


## A pick consumes its tier's ranks/modifier steps, while learn, potion and filler cards consume one.
static func _consumed_steps(c: Dictionary, magnitude: int) -> int:
	return magnitude if String(c.get("kind", "")) == "skill_rank" or _is_stacking(c) else 1


static func _description_value(c: Dictionary, magnitude: int) -> float:
	if _is_stacking(c):
		for effect: Dictionary in c.get("effects", []):
			if String(effect.get("op", "add")) == "mul":
				# tier C: show the compounded percentage to two decimals; application keeps full precision.
				return snappedf(absf(pow(float(effect.value), magnitude) - 1.0) * 100.0, 0.01)
	return float(c.value) * magnitude


func _roll_tier(state: RunWorld, rng: RandomNumberGenerator) -> String:
	var weights: Dictionary = _rarity.get("weights", {"normal": 1.0})
	var shift := 1.0 + maxf(0.0, float(state.player_state.get("fortune", 0.0))) * float(_rarity.get("fortune_scale", 0.0))
	var total := 0.0
	for tier: String in TIERS:
		total += maxf(0.0, float(weights.get(tier, 0.0))) * (1.0 if tier == "normal" else shift)
	var value := rng.randf() * total
	for tier: String in TIERS:
		value -= maxf(0.0, float(weights.get(tier, 0.0))) * (1.0 if tier == "normal" else shift)
		if value < 0.0:
			return "rare" if state.choice_bonus and tier == "normal" else tier
	return "rare" if state.choice_bonus else "normal"


## Applies card `id` at its honest `tier` (default Normal) to the run (learn / rank / modifier steps / potion / heal), emits
## upgrade_applied (and skill_learned for skill_new) and returns the card's new rank (0 when the card is unknown).
func apply(id: String, state: RunWorld, tier: String = "normal") -> int:
	var c := card(id)
	if c.is_empty():
		return 0
	tier = _honest_tier(c, state, tier)
	var kind := String(c.get("kind", ""))
	if kind == "potion_tier":
		if not is_eligible(c, state) or not state.upgrade_potion(String(c.get("potion_kind", "")), int(c.get("item_id", 0))):
			return 0
	var lo: Loadout = state.loadout
	var magnitude := _magnitude(c, state, tier)
	if magnitude <= 0:
		return 0
	var r := rank(id, state) + _consumed_steps(c, magnitude)
	lo.card_ranks[id] = r
	var skill := String(c.get("skill", ""))
	if kind == "skill_new":
		state.learn_skill(skill)
		lo.set_rank(skill, magnitude)
	elif kind == "skill_rank":
		lo.set_rank(skill, lo.rank(skill) + magnitude)
	for e: Dictionary in c.get("effects", []):
		var stat := String(e.get("stat", ""))
		var op := String(e.get("op", "add"))
		var value := float(e.get("value", 0.0))
		if _is_stacking(c):
			value = pow(value, magnitude) if op == "mul" else value * magnitude
		if kind == "filler" and op == "heal":
			state.heal_fraction(stat, value)
		elif kind in ["skill_new", "skill_rank", "skill_mod"] and skill != "":
			if stat == "rank" and kind != "skill_rank":
				lo.set_rank(skill, lo.rank(skill) + int(value))
			elif stat != "rank":
				lo.add_skill_mod(skill, stat, op, value)
		else:
			lo.add_player_mod(stat, op, value)
	state.refresh_player_stats()
	state.emit("upgrade_applied", {"id": id, "rank": r, "tier": tier, "magnitude": magnitude})
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
