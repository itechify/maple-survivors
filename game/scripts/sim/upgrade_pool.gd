class_name UpgradePool
extends RefCounted
## Data-driven upgrade cards (`data/survivor/upgrades.json`, docs/GAME_DESIGN.md section 8): eligibility, seeded
## weighted draws and applying a card to a run. `state` is the RunWorld (its loadout, progression, jobs and player).
## Pool membership replaces job-line card filtering. Only new/rank cards for pool actives and common passives
## are drawn, with their rarity bonuses; capped pool actives keep offering Mastery (#288).

const SKILL_NEW := "skill_new"
const SKILL_RANK := "skill_rank"
const FILLER := "filler"
const MASTERY := "mastery"
const NEW_ACTIVE := "new_active"
const OWNED_ACTIVE := "owned_active"
const NEW_PASSIVE := "new_passive"
const PASSIVE_RANK := "passive_rank"

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
## `fixed_share` previews the rank's share of max HP in percent (Snipe, #368).
const MECHANIC_PREVIEW_KEYS := ["knockback_chance", "blast_targets", "pierce_falloff", "meter_keep", "form_time", "form_power",
	"fixed_share"]
## How a bonus effect on a healing or revive stat reads on its card: [name, scale of an added value, unit of an added
## value]. tier C: wording from spec #372 story 11 ("Greater Heal: recovery x1.2", "Holy Shield: guard +1.5 s").
const CARD_STAT_TEXT := {"heal_power": ["recovery", 1.0, ""], "heal_threshold": ["heals below", 100.0, "% HP"],
	"revive_hp": ["revive HP", 100.0, "%"], "revive_guard": ["guard", 1.0, " s"]}
const MOD_PREVIEW := ["count", "attack_count", "pierce", "cooldown", "speed", "range", "area", "damage", "crit", "blast_targets", "pierce_falloff", "meter_keep", "hp_cost", "self_damage", "low_hp_damage", "support_heal", "support_rate", "form_time", "form_power", "heal_power", "heal_threshold", "revive_hp", "revive_guard"]
## Modifier previews: label, unit and base multiplier. Add another multiplier here only (tier C: UI wording).
const MODIFIER_PREVIEW := {"burn_damage": ["Burn", "%", 1.0]}
## tier C: survivor Potential ladder order; weights and Fortune scaling live in upgrades.json.
const STAT_LABELS := {"form_time": "Form duration", "form_power": "Form power", "attack_count": "Hits"}
const TIERS := ["normal", "rare", "epic", "unique", "legendary"]

var cards: Array = []
var _rarity := {}
var _mastery_bonus := {}
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
	p._mastery_bonus = root.get("mastery_bonus", {})
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


## Number of picks consumed by card `id`, including repeat Mastery picks.
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
	if String(c.get("kind", "")) != FILLER:
		if not String(c.get("kind", "")) in [SKILL_NEW, SKILL_RANK]:
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
		SKILL_NEW:
			if not lo.book.has(skill) or lo.has(skill) or not lo.has_free_slot(lo.book.slot(skill)):
				return false
		SKILL_RANK:
			if not lo.has(skill) or (lo.rank(skill) >= lo.book.max_rank(skill) and slot != "active"):
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
	for id: String in picked:
		var offered := choice_card(id, state, "normal" if state.book.slot(String(card(id).get("skill", ""))) != "active" else _roll_tier(state, rng))
		out.append(offered)
		state.card_tiers_offered[String(offered.tier)] += 1
	return out


## Stable draw category, independent of card encoding; capped pool actives become Mastery.
func card_kind(c: Dictionary, state: RunWorld) -> String:
	var skill := String(c.get("skill", ""))
	if String(c.get("kind", "")) == FILLER:
		return FILLER
	if state.book.slot(skill) == "passive":
		return PASSIVE_RANK if state.loadout.has(skill) else NEW_PASSIVE
	if String(c.get("kind", "")) == SKILL_RANK and state.book.slot(skill) == "active" and skill in state.jobs.skill_pool(state.job_id()) and state.loadout.has(skill) and state.loadout.rank(skill) >= state.book.max_rank(skill):
		return MASTERY
	return OWNED_ACTIVE if state.loadout.has(skill) else NEW_ACTIVE


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
			for kind: String in [SKILL_NEW, SKILL_RANK]:
				var id := key + ("_new" if kind == SKILL_NEW else "_rank")
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
## skill_mod_changes (rarity bonuses: effective value -> {before, after} once the bonus effects
## are taken, keys as MOD_PREVIEW names them: shots / targets / attack_count / pierce / speed / range (whole numbers), cooldown
## (seconds between casts as SkillRunner.restart_cooldown counts them, two decimals), area / damage / crit / revive_hp (percent),
## revive_guard (seconds, two decimals);
## {} otherwise)}.
func choice_card(id: String, state: RunWorld, tier: String = "normal") -> Dictionary:
	var c := card(id)
	var category := card_kind(c, state)
	tier = _honest_tier(c, state, tier)
	var magnitude := 0 if category == MASTERY else 1
	var bonus := rarity_bonus(c, state, tier, category)
	var desc := describe(id, magnitude)
	if state.book.def(String(c.get("skill", ""))).has("rarity_bonuses"):
		desc = "Learn at rank 1." if String(c.get("kind", "")) == SKILL_NEW else "+1 rank."
	if category == MASTERY:
		desc = "Mastery: no rank gained."
	if not bonus.is_empty():
		desc += " " + String(bonus.text) + "."
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
		if kind == SKILL_NEW:
			level_next = lo.book.canonical_level(skill, magnitude)
		elif kind == SKILL_RANK and r > 0:
			level_next = lo.book.canonical_level(skill, r + magnitude)
			var before := lo.book.level_node(skill, level)
			var after := lo.book.level_node(skill, level_next)
			for field: String in PREVIEW_FIELDS:
				# `prop` is previewed for Final Attack only (#181): other skills' cards (Poison Breath) keep their events.
				if field == "prop" and not lo.book.def(skill).has("final_attack"):
					continue
				# A fixed-share skill (Snipe, #368) never reads its WZ cooltime (a session value): the card must not show it.
				if field == "cooltime" and lo.book.def(skill).has("fixed_share"):
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
				if old_stats.get(field, 0) != new_stats.get(field, 0):
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
			if passive.has("per_level") and not bool(lo.book.def(skill).get("common_passive", false)):
				# tier C: a survivor per-level passive previews its own fraction as a percent,
				# not the canonical fields it reinterprets. A common passive (#289) has no canonical fields and states
				# its per-rank value in its own unit: its card text (SkillText) shows it.
				changes = {String(passive.stat): {"before": roundi(lo.passive_value(skill, level, passive) * 100.0),
					"after": roundi(lo.passive_value(skill, level_next, passive) * 100.0)}}
	return {
		"id": id,
		"tier": tier,
		"magnitude": magnitude,
		"kind": kind,
		"card_kind": category,
		"slots": lo.slot_summary(),
		"skill_rank_before": lo.rank(skill),
		"skill_rank_max": lo.book.max_rank(skill),
		"name": String(c.get("name", id)) + (" Mastery" if category == MASTERY else ""),
		"rarity_bonus": bonus,
		"desc": desc,
		"icon": String(c.get("icon", "")),
		"rank": rank(id, state) + maxi(1, _consumed_steps(c, magnitude)),
		"rank_before": rank(id, state),
		"max_rank": int(c.get("max_rank", 1)),
		"skill": skill,
		"skill_name": skill_name,
		"skill_level": level,
		"skill_level_next": level_next,
		"skill_level_max": level_max,
		"skill_changes": changes,
		"skill_effect_stat": effect_stat,
		"skill_mod_changes": _bonus_changes({"skill": skill, "effects": bonus.get("effects", [])}, lo, 1) if not bonus.is_empty() else {},
	}


## Resolves the next data-only bonus without consuming RNG; preview and application use the same entry.
## Lists cycle in data order. A shared id across rarities shares its repeat count.
func rarity_bonus(c: Dictionary, state: RunWorld, tier: String, category: String = "") -> Dictionary:
	if category == "":
		category = card_kind(c, state)
	var skill := String(c.get("skill", ""))
	if state.book.slot(skill) != "active" or not String(c.get("kind", "")) in [SKILL_NEW, SKILL_RANK]:
		return {}
	if tier == "normal" and category != MASTERY:
		return {}
	var entries: Array = state.book.def(skill).get("rarity_bonuses", {}).get(tier, [])
	# tier C (#346): Normal Mastery gives damage, or cooldown x0.95 for damage:none skills.
	if tier == "normal" and category == MASTERY and not _mastery_bonus.is_empty():
		var normal := _mastery_bonus.duplicate(true)
		if String(state.book.def(skill).get("damage", "")) == "none":
			normal.effects = [{"stat": "cooldown", "op": "mul", "value": 0.95}]
		entries = [normal]
	if entries.is_empty():
		return {}
	var count := 0
	for entry: Dictionary in entries:
		count += int(state.loadout.card_ranks.get("bonus:" + skill + ":" + String(entry.id), 0))
	var bonus: Dictionary = entries[count % entries.size()].duplicate(true)
	var counter := "bonus:" + skill + ":" + String(bonus.id)
	# tier C: repeated bonuses shrink x0.8, including awards received before Mastery.
	var scale := pow(0.8, int(state.loadout.card_ranks.get(counter, 0)))
	var labels: Array[String] = []
	for effect: Dictionary in bonus.effects:
		var op := String(effect.get("op", "add"))
		var value := float(effect.value)
		effect.value = 1.0 + (value - 1.0) * scale if op == "mul" else value * scale
		if String(effect.stat) == "meter_keep":
			var before := state.loadout.skill_stat(skill, "meter_keep", 0.0)
			var kept := before * float(effect.value) if op == "mul" else before + float(effect.value)
			labels.append("Keeps %d %s" % [maxi(0, roundi(kept)), state.book.meter_unit(skill)])
			continue
		if HpRisk.LABELS.has(String(effect.stat)):
			labels.append(String(HpRisk.LABELS[String(effect.stat)]) + (" x" if op == "mul" else " +") + _fmt(snappedf(float(effect.value), 0.001)))
			continue
		labels.append(effect_label(String(effect.stat), op, float(effect.value)))
	# tier C (spec #360, MS5): an optional `text_by_family` renames the bonus for the held weapon family (Arrow Blow's
	# "Crossbow Mastery"); the text only, never a number.
	var by_family: Dictionary = bonus.get("text_by_family", {})
	var shown := String(by_family.get(state.loadout.weapon_family, bonus.get("text", bonus.id)))
	bonus.erase("text_by_family") # resolved: the card dictionary (and the event stream that carries it) holds the one name only
	bonus.text = shown + ": " + ", ".join(labels)
	bonus.counter = counter
	return bonus


## A bonus effect's card text, "<stat> x1.2" for a multiplier and "<stat> +3" for an addition. The healing and revive stats
## read in the player's words (CARD_STAT_TEXT: "recovery x1.2", "guard +1.5 s"); the others are their capitalized key.
static func effect_label(stat: String, op: String, value: float) -> String:
	var text: Array = CARD_STAT_TEXT.get(stat, [])
	if text.is_empty():
		return String(STAT_LABELS.get(stat, stat)).capitalize() + (" x" if op == "mul" else " +") + _fmt(snappedf(value, 0.001))
	# A modifier stored as a share of a bar (0.15 of max HP) reads as percent when it adds; a multiplier reads as a factor.
	var shown := value * float(text[1]) if op == "add" else value
	return "%s%s%s%s" % [text[0], " x" if op == "mul" else " +", _fmt(snappedf(shown, 0.001)), "" if op == "mul" else text[2]]


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
		desc = desc.replace("{value}", _fmt(float(c.value) * magnitude))
	return desc


## Preview an active rarity bonus on an independent loadout copy.
static func _bonus_changes(c: Dictionary, lo: Loadout, magnitude: int) -> Dictionary:
	var skill := String(c.get("skill", ""))
	var preview := lo.clone()
	var touched := []
	for e: Dictionary in c.get("effects", []):
		var stat := String(e.get("stat", ""))
		var op := String(e.get("op", "add"))
		if not stat in MOD_PREVIEW and not stat in MODIFIER_PREVIEW:
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
	if MODIFIER_PREVIEW.has(stat):
		return roundi(lo.skill_stat(skill, stat, float(MODIFIER_PREVIEW[stat][2])) * 100.0)
	match stat:
		"support_heal", "support_rate":
			return SupportSummons.preview(st, stat)
		"form_time":
			return snappedf(float(st.get("duration", 0.0)), 0.01)
		"form_power":
			return snappedf(lo.skill_stat(skill, "form_power", 0.0) * 100.0, 0.01)
		"meter_keep":
			return maxi(0, roundi(lo.skill_stat(skill, "meter_keep", 0.0)))
		"pierce_falloff":
			return snappedf(float(st.pierce_falloff) * 100.0, 0.01)
		"fixed_share":
			return roundi(float(st.fixed_share.share) * 100.0)
		"self_damage":
			return snappedf(float(st.self_damage), 0.01) # percent of the damage dealt
		"low_hp_damage":
			return roundi(float(st.low_hp_damage) * 100.0)
		"cooldown":
			return snappedf(SkillRunner.restart_cooldown(st), 0.01)
		"revive_hp":
			return roundi(float(st.revive.hp) * 100.0)
		"revive_guard":
			return snappedf(float(st.revive.guard), 0.01)
		"area":
			return roundi(float(st.area) * 100.0)
		"heal_power", "heal_threshold":
			return roundi(float(st[stat]) * 100.0)
		"damage":
			return roundi(lo.skill_stat(skill, "damage", 1.0) * 100.0)
		"crit":
			return roundi(float(st.crit) * 100.0)
	return roundi(float(st[stat]))


func _honest_tier(c: Dictionary, state: RunWorld, tier: String) -> String:
	return tier if String(c.get("kind", "")) in [SKILL_NEW, SKILL_RANK] and state.book.slot(String(c.get("skill", ""))) == "active" else "normal"


## New, rank and filler cards each consume one pick, including Mastery.
static func _consumed_steps(_c: Dictionary, _magnitude: int) -> int:
	return 1


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
	if c.is_empty() or not String(c.get("kind", "")) in [SKILL_NEW, SKILL_RANK, FILLER]:
		return 0
	var category := card_kind(c, state)
	tier = _honest_tier(c, state, tier)
	var kind := String(c.get("kind", ""))
	var lo: Loadout = state.loadout
	var magnitude := 0 if category == MASTERY else 1
	var bonus := rarity_bonus(c, state, tier, category)
	if (kind == SKILL_NEW and (lo.has(String(c.skill)) or not lo.has_free_slot(lo.book.slot(String(c.skill))))) \
			or (kind == SKILL_RANK and (not lo.has(String(c.skill)) or (lo.rank(String(c.skill)) >= lo.book.max_rank(String(c.skill)) and category != MASTERY))):
		return 0
	if magnitude <= 0 and category != MASTERY:
		return 0
	var r := rank(id, state) + maxi(1, _consumed_steps(c, magnitude))
	lo.card_ranks[id] = r
	var skill := String(c.get("skill", ""))
	if kind == SKILL_NEW:
		state.learn_skill(skill)
		lo.set_rank(skill, magnitude)
	elif kind == SKILL_RANK:
		lo.set_rank(skill, lo.rank(skill) + magnitude)
	for e: Dictionary in c.get("effects", []):
		var stat := String(e.get("stat", ""))
		var op := String(e.get("op", "add"))
		var value := float(e.get("value", 0.0))
		if kind == FILLER and op == "heal":
			state.heal_fraction(stat, value)
		elif kind in [SKILL_NEW, SKILL_RANK] and skill != "":
			if stat == "rank" and kind != SKILL_RANK:
				lo.set_rank(skill, lo.rank(skill) + int(value))
			elif stat != "rank":
				lo.add_skill_mod(skill, stat, op, value)
	if not bonus.is_empty():
		for effect: Dictionary in bonus.effects:
			lo.add_skill_mod(skill, String(effect.stat), String(effect.op), float(effect.value))
		lo.card_ranks[String(bonus.counter)] = int(lo.card_ranks.get(String(bonus.counter), 0)) + 1
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
