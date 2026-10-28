class_name UpgradePool
extends RefCounted
## Data-driven upgrade cards (`data/survivor/upgrades.json`, docs/GAME_DESIGN.md section 8): eligibility, seeded
## weighted draws and applying a card to a run. `state` is the RunWorld (its loadout, progression, jobs and player).
## Pool membership replaces job-line card filtering. Only new/rank cards for pool actives and common passives
## are drawn. card_kind is the extension seam for rarity/Mastery and common passives (#288/#289).

## Canonical level fields a rank card previews as before -> after (mastery converted to percent), in display order.
const PREVIEW_FIELDS := ["mad", "mastery", "fixdamage", "time", "x", "pdd", "mdd", "acc", "eva", "mobCount", "cooltime", "speed", "range", "hp",
	"damage", "hpCon", "prop"]
## Preview keys of passive skills whose canonical number means something else than its field name (the Warrior
## passives, #163): Max HP per level-up for Improved MaxHP Increase (field x), HP per regeneration pulse for Improved HP
## Recovery (field hp, which is a percent for Heal).
const PASSIVE_MAX_HP := Loadout.MAX_HP_PER_LEVEL
const PASSIVE_REGEN_HP := "regen_hp"
const PASSIVE_PREVIEW_KEYS := [PASSIVE_MAX_HP, PASSIVE_REGEN_HP]
## Effective opt-in mechanic values; fall-off is displayed as percentage points per later target.
const MECHANIC_PREVIEW_KEYS := ["knockback_chance", "blast_targets", "pierce_falloff"]
## Skill modifier stats a skill_mod card previews. Each is its own skill_mod_changes key, except "count", which is
## SkillRunner.count_meaning of the skill's kind ("shots" or "targets").
const MOD_PREVIEW := ["count", "attack_count", "pierce", "cooldown", "speed", "range", "area", "damage", "crit", "blast_targets", "pierce_falloff"]
## tier C: survivor Potential ladder order; weights and Fortune scaling live in upgrades.json.
const TIERS := ["normal", "rare", "epic", "unique", "legendary"]

var cards: Array = []
## Draws in a row without a power card after which a power card is guaranteed (0 = no pity).
var pity_draws := 0
var _rarity := {}
var _magnitudes := {}
var _by_id := {}
var _draw_weights := {}
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
	p._draw_weights = root.get("draw_weights", {})
	p._magnitudes = root.get("magnitudes", {})
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


## Consumed rank/modifier steps of card `id`; a one-time learn card consumes one.
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
	var skill_key := String(c.get("skill", ""))
	var slot := lo.book.slot(skill_key)
	if String(c.get("kind", "")) != "filler":
		if not String(c.get("kind", "")) in ["skill_new", "skill_rank"]:
			return false
		if slot == "passive":
			if not bool(lo.book.def(skill_key).get("common_passive", false)):
				return false
		elif slot != "active" or not skill_key in state.jobs.skill_pool(state.job_id()):
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


## Draws up to n distinct eligible cards, adding one fallback alternative when short (see choice_card for fields).
func roll_choices(state: RunWorld, rng: RandomNumberGenerator, n: int = 3) -> Array:
	var pool := eligible(state)
	var picked: Array = []
	while picked.size() < n and not pool.is_empty():
		var id := _weighted_pick(pool, rng, state)
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


## Stable draw category, independent of the legacy card encoding. #288 can return mastery here at rank 8.
func card_kind(c: Dictionary, state: RunWorld) -> String:
	var skill := String(c.get("skill", ""))
	if String(c.get("kind", "")) == "filler":
		return "filler"
	if state.book.slot(skill) == "passive":
		return "passive_rank" if state.loadout.has(skill) else "new_passive"
	return "owned_active" if state.loadout.has(skill) else "new_active"


## Per-card sampling weight from survivor data; Fortune changes rarity only.
func draw_weight(c: Dictionary, state: RunWorld) -> float:
	return maxf(0.0, float(_draw_weights.get(card_kind(c, state), 1.0)))


## Add standard new/rank cards for newly implemented pool definitions; explicit data cards may override text.
func add_pool_skills(book: SkillBook, jobs: JobTree) -> void:
	if cards.is_empty():
		return # explicit empty card catalog (tools and synthetic worlds)
	for job in jobs.playable_jobs():
		for key: String in jobs.skill_pool(job):
			if not book.has(key):
				continue
			for kind: String in ["skill_new", "skill_rank"]:
				var id := key + ("_new" if kind == "skill_new" else "_rank")
				if _by_id.has(id):
					continue
				var d := book.def(key)
				var c := {"id": id, "kind": kind, "skill": key, "name": d.get("name", key),
					"icon": d.get("icon", book.wz_path(key) + "/icon"), "desc": "+1 rank", "max_rank": 0,
					"effects": [], "power": true}
				cards.append(c)
				_by_id[id] = c


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
## passive shows only its own stat in percent), skill_effect_stat (the skill's
## skills.json buff `stat`, e.g. "hp" for Recovery; "" for other skills),
## skill_mod_changes (skill_mod cards on an owned skill: effective value -> {before, after} once all the card's steps
## are taken, keys as MOD_PREVIEW names them: shots / targets / attack_count / pierce / speed / range (whole numbers), cooldown
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
		if effect_stat == "":
			# A Mastery's accuracy is its canonical `x` (#181): the card names that stat, not a buff's.
			for passive_effect: Variant in lo.book.def(skill).get("passive", {}).get("effects", []):
				if passive_effect is Dictionary and String(passive_effect.get("field", "")) == "x":
					effect_stat = String(passive_effect.get("stat", ""))
		if String(lo.book.def(skill).get("cast", {}).get("rule", "")) == "crowd":
			effect_stat = String(lo.book.def(skill).cast.get("status", "slow")) # the status the crowd cast inflicts
		var r := lo.rank(skill) if lo.has(skill) else 0
		level = lo.book.canonical_level(skill, r) if r > 0 else 0
		if kind == "skill_new":
			level_next = lo.book.canonical_level(skill, magnitude)
		elif kind == "skill_rank" and r > 0:
			level_next = lo.book.canonical_level(skill, r + magnitude)
			var before := lo.book.level_node(skill, level)
			var after := lo.book.level_node(skill, level_next)
			for field: String in PREVIEW_FIELDS:
				# `prop` is previewed for Final Attack only (#181): other skills' cards (Poison Breath) keep their events.
				if field == "prop" and not lo.book.def(skill).has("final_attack"):
					continue
				if before.has(field) and after.has(field):
					var a := int(lo.book.canonical(skill, level, field))
					var b := int(lo.book.canonical(skill, level_next, field))
					if field == "mastery":
						a = roundi(CombatMath.mastery_fraction(a) * 100.0)
						b = roundi(CombatMath.mastery_fraction(b) * 100.0)
					changes[field] = {"before": a, "after": b}
			var old_stats := lo.stats(skill, r)
			var new_stats := lo.stats(skill, r + magnitude)
			for field: String in MECHANIC_PREVIEW_KEYS:
				if old_stats[field] != new_stats[field]:
					changes[field] = {"before": _preview_value(field, old_stats, lo, skill),
						"after": _preview_value(field, new_stats, lo, skill)}
			var damage_field := String(lo.book.def(skill).get("impact_blast", {}).get("damage_field", "damage"))
			if damage_field != "damage" and changes.has(damage_field):
				changes["damage"] = changes[damage_field]
				changes.erase(damage_field)
			var renamed := _passive_preview(lo.book.def(skill))
			if not renamed.is_empty() and changes.has(renamed[0]):
				changes[renamed[1]] = changes[renamed[0]]
				changes.erase(renamed[0])
			var passive: Dictionary = lo.book.def(skill).get("passive", {})
			if passive.has("per_level"):
				# tier C: a survivor per-level passive previews its own fraction as a percent,
				# not the canonical fields it reinterprets.
				changes = {String(passive.stat): {"before": roundi(lo.passive_value(skill, level, passive) * 100.0),
					"after": roundi(lo.passive_value(skill, level_next, passive) * 100.0)}}
	return {
		"id": id,
		"tier": tier,
		"magnitude": magnitude,
		"kind": kind,
		"card_kind": card_kind(c, state),
		"slots": lo.slot_summary(),
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
	return []


## Card `id`'s desc for `magnitude` ranks / steps: {magnitude} filled in, {value} as the scaled or compounded value
## (shown on the level-up card).
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
		"pierce_falloff":
			return snappedf(float(st.pierce_falloff) * 100.0, 0.01)
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
	if String(c.get("kind", "")) in ["skill_new", "skill_rank"]:
		return 1
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
	var value := maxi(1, int(_tier_value(c, tier)))
	# tier C: owner #173 (2026-10-18): configured tiers clamp their fixed gain; -1 headroom means unlimited.
	var headroom := _headroom(c, state)
	return mini(value, headroom) if tier in _magnitudes.get("clamp", []) and headroom >= 0 else value


func _honest_tier(c: Dictionary, state: RunWorld, tier: String) -> String:
	if String(c.get("kind", "")) in ["skill_new", "skill_rank"]:
		return "normal" if state.book.slot(String(c.get("skill", ""))) == "passive" else tier
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
	return String(c.get("kind", "")) == "filler"


static func _is_stacking(c: Dictionary) -> bool:
	return String(c.get("kind", "")) in ["skill_mod", "stat", "passive"]


## A pick consumes its tier's ranks/modifier steps, while learn and filler cards consume one.
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


## Applies card `id` at its honest `tier` (default Normal) to the run (learn / rank / modifier steps / heal), emits
## upgrade_applied (and skill_learned for skill_new) and returns the card's new rank (0 when the card is unknown).
func apply(id: String, state: RunWorld, tier: String = "normal") -> int:
	var c := card(id)
	if c.is_empty():
		return 0
	tier = _honest_tier(c, state, tier)
	var kind := String(c.get("kind", ""))
	var lo: Loadout = state.loadout
	var magnitude := _magnitude(c, state, tier)
	if (kind == "skill_new" and (lo.has(String(c.skill)) or not lo.has_free_slot(lo.book.slot(String(c.skill))))) \
			or (kind == "skill_rank" and (not lo.has(String(c.skill)) or lo.rank(String(c.skill)) >= lo.book.max_rank(String(c.skill)))):
		return 0
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


func _weighted_pick(ids: Array, rng: RandomNumberGenerator, state: RunWorld) -> String:
	if ids.is_empty():
		return ""
	var total := 0.0
	for id: String in ids:
		total += draw_weight(card(id), state)
	if total <= 0.0:
		return ids[rng.randi_range(0, ids.size() - 1)]
	var r := rng.randf() * total
	for id: String in ids:
		r -= draw_weight(card(id), state)
		if r < 0.0:
			return id
	return ids[ids.size() - 1]


static func _fmt(v: Variant) -> String:
	var f := float(v)
	return str(int(f)) if f == floorf(f) else str(f)
