class_name Loadout
extends RefCounted
## The skills a run owns, their survivor ranks and the modifiers upgrade cards stacked on them, plus the player-wide
## modifiers of general cards (docs/ARCHITECTURE.md 4.4, docs/GAME_DESIGN.md sections 7, 8). Skill ids are the survivor
## keys of skills.json.
##
## Modifiers are kept as (add, mul) per stat: the resolved value is (base + add) x mul, where `add` sums every "add"
## effect and `mul` multiplies every "mul" effect (so Faster Snails x0.88 compounds per rank). stats(key) resolves a
## skill completely: its canonical level from the rank, the canonical numbers of that level from Skill.wz, the survivor
## base numbers with the modifiers, the damage range for the current INT / magic attack, and the visual paths.
## `version` increments on every change so callers can cache stats().

## Passive stats of the shared physical passives (docs/GAME_DESIGN.md 7.6). mastery: the canonical Mastery skill value N
## (the mastery fraction is (10 + 5N)%); acc: skill ACC; crit_chance: percent chance (Skill.wz `prop`); crit_damage: the
## critical hit's total percent (Skill.wz `damage`; the bonus is that minus 100); max_hp_per_level: Max HP gained at each
## level-up after learning.
const MASTERY := "mastery"
const ACC := "acc"
const CRIT_CHANCE := "crit_chance"
const CRIT_DAMAGE := "crit_damage"
const MAX_HP_PER_LEVEL := "max_hp_per_level"
## tier C (#199): additive pixels of reach for ranged weapon stances and weapon-gated ranged attack skills.
const RANGE := "range"
## tier B: untrained physical mastery is 10% (SouthPerry/HS.net).
const BASE_MASTERY := 0.10
## Passive stats of the nine common passives (skills/common.json, spec #282 ticket #289); every value is per rank in the
## unit its name gives (tier C, docs/GAME_DESIGN.md 8). damage_pct, cast_speed_pct and area_pct feed stats(); max_hp_pct,
## speed_pct, regen_pct, exp_pct and armor_flat feed RunWorld.
const DAMAGE_PCT := "damage_pct"
const MAX_HP_PCT := "max_hp_pct"
const SPEED_PCT := "speed_pct"
const REGEN_PCT := "regen_pct"
const CAST_SPEED_PCT := "cast_speed_pct"
const AREA_PCT := "area_pct"
const EXP_PCT := "exp_pct"
const ARMOR_FLAT := "armor_flat"
## tier C: the cooldown factor (cast speed passives, cooldown cards and every other cooldown source together) never goes
## below this share of the skill's own cooldown. The reference's x0.35 floor.
const COOLDOWN_FLOOR := 0.35
## tier C (#376): the most a Heal threshold card can raise the "heals below" fraction to; full HP never counts as injured.
const HEAL_THRESHOLD_CAP := 0.95

var book: SkillBook
## Owned skill key -> survivor rank (>= 1).
var ranks := {}
## Owned skill keys in the order they were learned.
var order: Array = []
## skill key -> {stat: Vector2(add, mul)}.
var skill_mods := {}
## The status-bonus catalogue of all job lines; the SkillBook owns it (the Skill window text reads it there too).
var status_bonuses: Dictionary:
	get:
		return book.status_bonuses
	set(value):
		book.status_bonuses = value
## Skill key -> ordered catalogue ids of the status grants taken (separate from the numeric mods).
var grants := {}
## Skill key -> {catalogue id: additive repeat chance points} (StatusBonus.repeat_points).
var grant_chances := {}
## stat -> Vector2(add, mul) for player-wide stats (max_hp, speed, magnet, hp_regen, pdd, damage, crit).
var player_mods := {}
## Upgrade card id -> consumed rank/modifier steps (one per learned skill card), respecting its maximum.
var card_ranks := {}
## Inputs of the damage formula and the CharLevel visuals, kept current by RunWorld.
var int_stat := 4.0
var matk := 0.0
var char_level := 1
## Max HP, kept current by RunWorld: a percentage HP cost (HpRisk) resolves against it.
var max_hp := 1:
	set(value):
		if value != max_hp:
			max_hp = value
			version += 1
## tier C: display/preview input matching ProjectileSystem, supplied from balance.combat.pierce_floor at setup.
var pierce_floor := 0.0
## Physical caster inputs; RunWorld._refresh_caster assembles these. Setters invalidate cached stats on change.
var str_stat := 4.0:
	set(value):
		if value != str_stat:
			str_stat = value
			version += 1
var dex_stat := 4.0:
	set(value):
		if value != dex_stat:
			dex_stat = value
			version += 1
var luk_stat := 4.0:
	set(value):
		if value != luk_stat:
			luk_stat = value
			version += 1
var watk := 0.0:
	set(value):
		if value != watk:
			watk = value
			version += 1
var acc := 0.0:
	set(value):
		if value != acc:
			acc = value
			version += 1
var weapon_id := 0:
	set(value):
		if value != weapon_id:
			weapon_id = value
			version += 1
var weapon_family := "":
	set(value):
		if value != weapon_family:
			weapon_family = value
			version += 1
var job_id := 0:
	set(value):
		if value != job_id:
			job_id = value
			version += 1
var mastery := BASE_MASTERY:
	set(value):
		if value != mastery:
			mastery = value
			version += 1
var crit_bonus := 0.0:
	set(value):
		if value != crit_bonus:
			crit_bonus = value
			version += 1
## Passive bonus in skill-percentage points (100 adds 1.0 to the skill multiplier on a critical hit).
var crit_damage_bonus := 0.0:
	set(value):
		if value != crit_damage_bonus:
			crit_damage_bonus = value
			version += 1
## Attack speed (spec #151, #160): the held weapon's step (Item.wz attackSpeed; WeaponInfo.NORMAL_SPEED bare-handed) and
## the Booster steps in effect (positive = faster, only while the Booster's weapon family is held).
var weapon_speed := WeaponInfo.NORMAL_SPEED:
	set(value):
		if value != weapon_speed:
			weapon_speed = value
			version += 1
var speed_steps := 0:
	set(value):
		if value != speed_steps:
			speed_steps = value
			version += 1
## Survivor balance.crit.per_acc; accuracy converts to crit chance for every damage type.
var crit_per_acc := 0.0:
	set(value):
		if value != crit_per_acc:
			crit_per_acc = value
			version += 1
## Base crit chance and multiplier (balance.json `crit`).
var crit_chance := 0.0
var crit_mult := 1.5
var version := 0


func _init(p_book: SkillBook = null) -> void:
	book = p_book if p_book != null else SkillBook.new()


## An independent copy of every field (the same SkillBook): changing the copy never changes this loadout. Previews
## stack a card's steps on a clone.
func clone() -> Loadout:
	var c := Loadout.new(book)
	c.ranks = ranks.duplicate()
	c.order = order.duplicate()
	c.skill_mods = skill_mods.duplicate(true)
	c.grants = grants.duplicate(true)
	c.grant_chances = grant_chances.duplicate(true)
	c.player_mods = player_mods.duplicate(true)
	c.card_ranks = card_ranks.duplicate()
	c.int_stat = int_stat
	c.matk = matk
	c.char_level = char_level
	c.max_hp = max_hp
	c.pierce_floor = pierce_floor
	for field: String in ["str_stat", "dex_stat", "luk_stat", "watk", "acc", "weapon_id", "weapon_family",
			"job_id", "mastery", "crit_bonus", "crit_damage_bonus", "crit_per_acc", "weapon_speed", "speed_steps"]:
		c.set(field, get(field))
	c.crit_chance = crit_chance
	c.crit_mult = crit_mult
	c.version = version
	return c


## Learns `key` at rank 1. False when unknown or already owned.
func add_skill(key: String) -> bool:
	if not book.has(key) or ranks.has(key) or book.slot(key) in ["summon_sub", "form_sub"] or not has_free_slot(book.slot(key)):
		return false
	ranks[key] = 1
	order.append(key)
	version += 1
	return true


## True when the skill is owned.
func has(key: String) -> bool:
	return ranks.has(key)


## Survivor rank of `key` (0 when not owned).
func rank(key: String) -> int:
	return int(ranks.get(key, 0))


## Sets the rank (clamped to 1..max rank); false when not owned.
func set_rank(key: String, r: int) -> bool:
	if not ranks.has(key):
		return false
	ranks[key] = clampi(r, 1, book.max_rank(key))
	version += 1
	return true


## Canonical skill level of an owned skill (0 when not owned).
func level(key: String) -> int:
	return book.canonical_level(key, rank(key)) if ranks.has(key) else 0


## Owned skills that occupy slot `slot_name` ("active" / "passive").
func slot_count(slot_name: String) -> int:
	var n := 0
	for k: String in order:
		if book.slot(k) == slot_name:
			n += 1
	return n


## Maximum slots of a kind, supplied by survivor data. Untracked kinds (mobility) have no limit.
func slot_limit(slot_name: String) -> int:
	return int(book.slot_limits.get(slot_name, 0))


## Whether another skill of this kind fits; mobility consumes neither track.
func has_free_slot(slot_name: String) -> bool:
	return slot_limit(slot_name) <= 0 or slot_count(slot_name) < slot_limit(slot_name)


## The common passives held, in learning order, for the Stat window: [{key, name, icon, rank, max_rank}].
func held_common_passives() -> Array:
	var out: Array = []
	for k: String in order:
		var d := book.def(k)
		if bool(d.get("common_passive", false)):
			out.append({"key": k, "name": String(d.get("name", k)), "icon": String(d.get("icon", "")), "rank": rank(k),
				"max_rank": book.max_rank(k)})
	return out


## Shared display of both slot tracks for the HUD windows.
func slot_summary() -> String:
	return "Active %d/%d   Passive %d/%d" % [slot_count("active"), slot_limit("active"),
		slot_count("passive"), slot_limit("passive")]


## Stacks one effect on skill `key` (op "add" or "mul").
func add_skill_mod(key: String, stat: String, op: String, value: float) -> void:
	if not skill_mods.has(key):
		skill_mods[key] = {}
	skill_mods[key][stat] = _stack(skill_mods[key].get(stat, Vector2(0.0, 1.0)), op, value)
	version += 1


## Stacks one effect on a player-wide stat (op "add" or "mul").
func add_player_mod(stat: String, op: String, value: float) -> void:
	player_mods[stat] = _stack(player_mods.get(stat, Vector2(0.0, 1.0)), op, value)
	version += 1


## (base + add) x mul of a player-wide stat.
func player_stat(stat: String, base: float) -> float:
	var m: Vector2 = player_mods.get(stat, Vector2(0.0, 1.0))
	return (base + m.x) * m.y


## (base + add) x mul of a skill stat.
func skill_stat(key: String, stat: String, base: float) -> float:
	var m: Vector2 = skill_mods.get(key, {}).get(stat, Vector2(0.0, 1.0))
	return (base + m.x) * m.y


## Sets the formula inputs (bumps `version` only when something changed).
func set_caster(p_int: float, p_matk: float, p_char_level: int) -> void:
	if p_int == int_stat and p_matk == matk and p_char_level == char_level:
		return
	int_stat = p_int
	matk = p_matk
	char_level = p_char_level
	version += 1


## The extra cast art of a definition's `cast_visuals`: [{path, x, follow}] (`follow` anchors it to the caster and mirrors it
## with the facing). An entry with `min_attack_count` K only plays when the cast has at least K damage lines (Spear
## Crusher's K-th dragon thrust, tier B reading of the D1 contact sheet); paths take the held weapon's art twin.
func _cast_visuals(d: Dictionary, attack_count: int, key: String) -> Array:
	var out: Array = []
	for v: Dictionary in d.get("cast_visuals", []):
		if v.has("across") or v.has("fall"):
			continue # CastVisualPlan expands spread/falling art at presentation time.
		if attack_count >= int(v.get("min_attack_count", 0)):
			out.append({"path": book.art_path(key, String(v.get("path_by_family", {}).get(weapon_family, v.path)), weapon_family), "x": float(v.get("x", 0.0)),
				"follow": bool(v.get("follow", false)), "facing": bool(v.get("facing", false))})
			if v.has("delay"):
				out.back()["delay"] = maxf(0.0, float(v.delay))
	return out


## The knock-back distance of a `knockback` block at survivor rank `rank_value`: the block's `distance_by_rank` list (one
## value per rank, the last one past its end, rank 1 for an unowned skill) when it has one, else its scalar `distance`
## (0 for a block with neither). tier C: ours (spec #383 NL8, GAME_DESIGN 7.94.8); every other field of the block is unchanged.
static func knockback_distance_at(block: Dictionary, rank_value: int) -> float:
	var by_rank: Variant = block.get("distance_by_rank")
	if by_rank is Array and not (by_rank as Array).is_empty():
		return float(by_rank[clampi(rank_value - 1, 0, (by_rank as Array).size() - 1)])
	return float(block.get("distance", 0.0))


## Fully resolved numbers of skill `key` at its owned rank, or at `at_rank` when > 0 (a preview of another rank with
## the same modifiers; an unowned skill resolves at rank 1):
## skill, skill_id, kind, slot, rank, level, damage_type (fixed/magic/physical/none), attack_kind (swing/stab/shoot/""),
## defense (pdd/mdd/none), damage_pct (physical skill% / 100, otherwise 1; a `damage_basis` skill reads `canonical(field) x scale / 100`
## and also reports damage_percent, the same number x 100), damage_min/max (before mob defence,
## after survivor multipliers; physical bounds are also before skill%), magic (bool), element, attack_count (canonical
## attackCount plus skill modifiers, damage lines per target),
## crit, crit_mult, speed_factor (attack speed: the fraction of the data's cooldown and action time left), cooldown, range, cast_rule (empty means legacy), cast_params (the cast block),
## has_box, box (canonical left-facing feet offsets scaled by area), area, mob_count (canonical plus count mods),
## hp_cost (canonical hpCon, 0 for most skills; Slash Blast; there is no MP cost, ADR 0006),
## speed, count, pierce, radius, ball, hit, effect
## (WZ paths), cast_visuals (the extra cast art, `_cast_visuals`), action, action_time, rotate, passive_stat,
## passive_value, icon, displacement ({} or the moving-attack block, _displacement), duration (canonical time), legacy buff_stat/buff_value, buff_effects (stat -> canonical value),
## impact_blast ({} or a cast-time box/count/visual), blast_targets, knockback_chance/distance, pull_chance (percent)/pull_gap (px; docs/GAME_DESIGN.md 7.35) and pierce_falloff,
## burn_pulse / burn_time / burn_share (only a skill whose on_hit status is burn; docs/GAME_DESIGN.md 7.43),
## `support` (SupportSummons.resolve pulses), flash_distance (px of a `flash_jump` skill at this rank; FlashJump.distance),
## heal_power (Heal's recovery multiplier, 1.0 without the card; docs/GAME_DESIGN.md 7.83) and heal_threshold (the resolved
## fraction of max HP below which Heal restores: the data's `hp_threshold` plus the card, capped at HEAL_THRESHOLD_CAP; 0 for
## a skill without a `heal` block),
## revive ({hp: share of max HP, guard: s, push: px} of a skill with a `revive` block, modifiers applied; PlayerRevive.resolve),
## and for a Hidden buff (docs/GAME_DESIGN.md 7.18): hidden, morph (Morph.wz id from the `morph_field` level number, 0 = none),
## fail_chance (0..1, the `fail_field` level number as a percentage), end_hp_above (HP fraction that ends it early) and
## cooldown_from_cast (the cooldown is exactly buff_cooldown from the cast, however long or short the buff lasts).
func stats(key: String, at_rank: int = 0) -> Dictionary:
	var d := book.def(key)
	var r := clampi(at_rank, 1, book.max_rank(key)) if at_rank > 0 else maxi(1, rank(key))
	var lv := book.canonical_level(key, r)
	var dtype := String(d.get("damage", "none"))
	var action := String(d.get("action", ""))
	if d.has("action_field"):
		# tier A: the WZ level names its own body stance (Spear Crusher: burster1 for two hits, burster2 for three).
		action = String(book.level_node(key, lv).get(String(d.action_field), action))
	if action == "weapon":
		# tier C: the stance (and so the swing/stab multiplier) of the held weapon's first basic-attack action.
		action = WeaponInfo.skill_action(weapon_id)
	# tier C: one body action and matching effect by handedness (Brandish, #301 ruling).
	var handedness := "two" if WeaponInfo.is_two_handed(weapon_id) else "one"
	action = String(d.get("action_by_handedness", {}).get(handedness, action))
	var effect := String(d.get("effect_by_handedness", {}).get(handedness, book.visual(key, "effect", lv, char_level)))
	effect = book.art_path(key, effect, weapon_family) # tier C: art_by_family twin, art only (Panic/Coma : Axe)
	var attack_kind := WeaponInfo.attack_kind(action)
	var dmg_mult := skill_stat(key, "damage", 1.0) * player_stat("damage", 1.0) * (1.0 + passive_total(DAMAGE_PCT) / 100.0)
	var lo := 0.0
	var hi := 0.0
	if dtype == "fixed":
		lo = book.canonical(key, lv, "fixdamage", 0.0) * dmg_mult
		hi = lo
	elif dtype == "magic":
		var mad := book.canonical(key, lv, "mad", 0.0)
		var mastery := CombatMath.mastery_fraction(int(book.canonical(key, lv, "mastery", 0.0)))
		var rng := CombatMath.magic_damage_range(int_stat, matk, mad, mastery)
		lo = rng.x * dmg_mult
		hi = rng.y * dmg_mult
	elif dtype == "physical":
		var bounds := CombatMath.physical_damage_range(str_stat, dex_stat, luk_stat, _summon_watk(key, lv, d), weapon_id,
			attack_kind, job_id, mastery, d.get("physical_formula", {}))
		lo = bounds.x * dmg_mult
		hi = bounds.y * dmg_mult
	# Attack speed (#160): an attack skill's action time and cooldown shrink with the Booster steps in effect, relative
	# to the held weapon's own speed (1.0 without a Booster, so existing timing is untouched). Buffs, passives and
	# non-damaging casts keep their data.
	var attacks := book.is_active(key) and book.kind(key) != "buff" and dtype != "none"
	var speed_factor := WeaponInfo.speed_factor(weapon_speed, speed_steps) if attacks else 1.0
	var passive: Dictionary = d.get("passive", {})
	var buff: Dictionary = d.get("buff", {})
	var heal: Dictionary = d.get("heal", {})
	var blast: Dictionary = d.get("impact_blast", {})
	var cast: Dictionary = d.get("cast", {})
	var node := book.level_node(key, lv)
	# tier C: survivor fallback box for skills without canonical lt/rb (Disorder); WZ boxes always take precedence.
	var box_node: Dictionary = node if node.get("lt") is Dictionary and node.get("rb") is Dictionary \
		else cast.get("box", {})
	var has_box := box_node.get("lt") is Dictionary and box_node.get("rb") is Dictionary
	var area := skill_stat(key, "area", 1.0) * (1.0 + passive_total(AREA_PCT) / 100.0)
	var box := Rect2()
	if has_box:
		var lt: Array = box_node.lt.get("$v", [0.0, 0.0])
		var rb: Array = box_node.rb.get("$v", [0.0, 0.0])
		var start := Vector2(float(lt[0]), float(lt[1])) * area
		box = Rect2(start, Vector2(float(rb[0]), float(rb[1])) * area - start)
		if bool(cast.get("around", false)):
			# tier C: surround attacks retain canonical reach/height on both sides of the player (Pirate kick).
			var extent := maxf(absf(box.position.x), absf(box.end.x))
			box = Rect2(-extent, box.position.y, extent * 2.0, box.size.y)
	var resolved := {
		"skill": key,
		"skill_id": book.skill_id(key),
		"kind": book.kind(key),
		"slot": book.slot(key),
		"rank": r,
		"level": lv,
		"cast_rule": String(cast.get("rule", "")),
		"cast_params": cast.duplicate(true),
		"has_box": has_box,
		"area": area,
		"box": box,
		"mob_count": maxi(1, roundi(skill_stat(key, "count", book.canonical(key, lv, "mobCount", float(cast.get("mob_count", 1.0)))))),
		"hp_cost": HpRisk.cost(self, key, lv),
		"teleport_range": book.canonical(key, lv, "range", 0.0) if d.has("teleport") else 0.0,
		"repeat_delay": float(d.get("teleport", {}).get("repeat_delay", 0.0)),
		"damage_type": dtype,
		"attack_kind": attack_kind,
		"defense": "pdd" if dtype == "physical" else "mdd" if dtype == "magic" else "none",
		"damage_pct": _damage_pct(key, d, lv, dtype, blast),
		"status_damage_mult": dmg_mult,
		"damage_min": lo,
		"damage_max": hi,
		"magic": dtype == "magic",
		"element": String(d.get("element", book.skill_node(key).get("elemAttr", ""))),
		"attack_count": maxi(1, roundi(skill_stat(key, "attack_count", book.canonical(key, lv, "attackCount", 1.0)))),
		"crit": skill_stat(key, "crit", 0.0) + player_stat("crit", crit_chance + acc * crit_per_acc + crit_bonus),
		"crit_mult": crit_mult,
		"crit_damage_bonus": crit_damage_bonus,
		"speed_factor": speed_factor,
		"cooldown": _cooldown(key, d, heal, lv, r, speed_factor),
		"range": skill_stat(key, "range", float(d.get("range", book.canonical(key, lv, "range",
			ChainCast.base_range(cast)))))
			* (area if String(cast.get("rule", "")) == "range_around" else 1.0)
			+ (passive_total(RANGE) if attacks and weapon_family in WeaponInfo.RANGED_FAMILIES
				and weapon_family in book.weapon_families(key) else 0.0),
		"speed": skill_stat(key, "speed", float(d.get("speed", 0.0))),
		"count": maxi(1, roundi(skill_stat(key, "count", float(d.get("count", book.canonical(key, lv, "bulletCount", 1.0)))))),
		"pierce": maxi(0, roundi(skill_stat(key, "pierce", float(d.get("pierce", 0))))),
		"pierce_falloff": maxf(0.0, skill_stat(key, "pierce_falloff", float(d.get("pierce_falloff", 0.0)))),
		"pierce_floor": pierce_floor,
		# No chance field = the knock-back always applies (Rush, tier C #302).
		"knockback_chance": (book.canonical(key, lv, String(d.knockback.chance_field)) if d.knockback.has("chance_field") else 100.0)
			if d.has("knockback") else 0.0,
		"knockback_distance": knockback_distance_at(d.get("knockback", {}), r),
		"pull_chance": book.canonical(key, lv, String(d.pull.get("chance_field", "")), 100.0) if d.has("pull") else 0.0,
		"pull_gap": float(d.pull.get("min_gap", 0.0)) if d.has("pull") else 0.0,
		"blast_targets": maxi(1, roundi(skill_stat(key, "blast_targets", book.canonical(key, lv, "mobCount", 1.0))))
			if d.has("impact_blast") and has_box else 0,
		"impact_blast": {"box": box, "count": maxi(1, roundi(skill_stat(key, "blast_targets",
			book.canonical(key, lv, "mobCount", 1.0)))),
			"visual": book.visual(key, String(blast.get("visual", "hit")), lv, char_level)}
			if d.has("impact_blast") and has_box else {},
		"radius": float(d.get("radius", 10.0)),
		"ball": book.visual(key, "ball", lv, char_level),
		"hit": book.art_path(key, book.visual(key, "hit", lv, char_level), weapon_family),
		"effect": effect,
		"cast_visuals": _cast_visuals(d, roundi(skill_stat(key, "attack_count", book.canonical(key, lv, "attackCount", 1.0))), key),
		"action": action,
		"action_time": float(d.get("action_times", {}).get(action, d.get("action_time", 0.0))) * speed_factor,
		"rotate": bool(d.get("rotate", false)),
		"passive_stat": String(passive.get("stat", "")),
		"passive_value": passive_value(key, lv, passive),
		"icon": String(d.get("icon", "")),
		# A literal survivor duration (the Beholder's 60 s life, tier C) overrides the canonical field, whose WZ time is
		# session-scale; every other buff and summon keeps reading its `duration_field` (default `time`).
		"duration": float(buff.duration) if buff.has("duration") \
			else book.canonical(key, lv, String(buff.get("duration_field", "time")), 0.0),
		"buff_stat": String(buff.get("stat", "")),
		"buff_value": book.canonical(key, lv, String(buff.get("field", "")), 0.0) if not buff.is_empty() else 0.0,
		"buff_effects": _buff_effects(key, lv, buff),
		# A literal survivor cooldown (Dark Sight) overrides the canonical cooldown field; other buffs keep their WZ value.
		"buff_cooldown": float(buff.cooldown) if buff.has("cooldown") \
			else book.canonical(key, lv, String(buff.get("cooldown_field", "time")), 0.0),
		"pulse_interval": float(buff.get("pulse_interval", 0.0)),
		"hp_threshold": float(buff.get("hp_threshold", 0.0)),
		"heal_power": maxf(0.0, skill_stat(key, "heal_power", 1.0)) if d.has("heal") else 1.0,
		"heal_threshold": _heal_threshold(key, heal),
		"hidden": bool(buff.get("hidden", false)),
		"morph": int(book.canonical(key, lv, String(buff.morph_field), 0.0)) if buff.has("morph_field") else 0,
		# The roll draws the Pirate stream 16 (RunWorld.start_buff): a future non-Pirate failure chance needs its own stream.
		"fail_chance": clampf(book.canonical(key, lv, String(buff.fail_field), 0.0) / 100.0, 0.0, 1.0)
			if buff.has("fail_field") else 0.0,
		"end_hp_above": float(buff.get("end_hp_above", 0.0)),
		"cooldown_from_cast": bool(buff.get("cooldown_from_cast", false)),
		"displacement": _displacement(key, d, r, lv),
	}
	if d.get("summon", {}).has("support"):
		resolved["support"] = SupportSummons.resolve(self, key, r)
	resolved.merge(HpRisk.resolve(self, key, lv))
	if d.has("meter"):
		resolved["meter"] = d.meter
		resolved["meter_keep"] = maxi(0, roundi(skill_stat(key, "meter_keep", 0.0)))
	_add_burn(resolved, key, d, lv)
	_add_pierce_field(resolved, key, d, lv)
	if d.has("damage_basis"):
		resolved["damage_percent"] = roundf(float(resolved.damage_pct) * 100.0 * 100.0) / 100.0

	if d.has("form"):
		resolved["duration"] = float(d.form.duration) * skill_stat(key, "form_time", 1.0)
		resolved["form_sub_damage"] = skill_stat(key, "damage", 1.0)
		resolved["form_sub_area"] = skill_stat(key, "area", 1.0)
		resolved["form_time"] = skill_stat(key, "form_time", 1.0)
		resolved["form_power"] = skill_stat(key, "form_power", 0.0)

	if d.has("revive"):
		resolved["revive"] = _revive(key, d.revive)
	if d.has("flash_jump"):
		# tier C (#405): the flash's reach at this rank, for the Skill window (RunWorld.flash_jump_distance reads the same).
		resolved["flash_distance"] = FlashJump.distance(d.flash_jump.distance, r, book.max_rank(key))
	_add_status_grants(resolved, key, r)
	return resolved


## Adds the burn numbers of a skill whose `on_hit.status` is "burn" to its resolved stats: burn_pulse (whole damage per
## second, BurnStatus.pulse of the cast's resolved bounds, the `pulse_field` share ("x") and the `burn_damage` modifier),
## burn_time (the `duration_field` seconds, "time") and burn_share (the percent of base damage per second, burn_damage
## included; the Skill window and cards show it). Other skills gain no key, so their stats are unchanged.
func _add_burn(resolved: Dictionary, key: String, d: Dictionary, lv: int) -> void:
	var on_hit: Dictionary = d.get("on_hit", {})
	if String(on_hit.get("status", "")) != "burn":
		return
	var share := book.canonical(key, lv, String(on_hit.pulse_field), 0.0) if on_hit.has("pulse_field") \
		else float(on_hit.get("pulse", 0.0)) # tier C: literal percent for skills without a WZ burn field
	var mult := skill_stat(key, "burn_damage", 1.0)
	resolved["burn_pulse"] = BurnStatus.pulse(float(resolved.damage_min), float(resolved.damage_max), share, mult)
	resolved["burn_time"] = book.canonical(key, lv, String(on_hit.get("duration_field", "time")), 0.0)
	resolved["burn_share"] = share * maxf(0.0, mult)


## The skill percent of a physical hit as a multiplier (1.0 = 100%; 1 for any other damage type): the level's `damage` field (or
## the blast's `damage_field`), 100 when the level has none. A definition with `damage_basis {field, scale}` and no such field on
## its level takes `canonical(field) x scale / 100` instead (Shadow Meso's `moneyCon` x 0.6, tier C, spec #383 NL9); a level that
## does carry the damage field keeps it, so the key never overrides a WZ number.
func _damage_pct(key: String, d: Dictionary, lv: int, dtype: String, blast: Dictionary) -> float:
	if dtype != "physical":
		return 1.0
	var field := String(blast.get("damage_field", "damage"))
	var basis: Variant = d.get("damage_basis")
	if basis is Dictionary and not book.level_node(key, lv).has(field):
		return book.canonical(key, lv, String(basis.field)) * float(basis.get("scale", 1.0)) / 100.0
	return book.canonical(key, lv, field, 100.0) / 100.0


## A definition with `pierce_field` (a level field, Dragon's Breath "mobCount") pierces one monster fewer than the field says:
## the arrow strikes `field` monsters in all, so `pierce` is the field minus one, plus the definition's literal `pierce` and any
## `pierce` card (spec #332 B8, tier C reading of the WZ monster count). Other skills keep their `pierce` unchanged.
func _add_pierce_field(resolved: Dictionary, key: String, d: Dictionary, lv: int) -> void:
	var field := String(d.get("pierce_field", ""))
	if field == "":
		return
	var base := float(d.get("pierce", 0)) + maxf(0.0, book.canonical(key, lv, field, 1.0) - 1.0)
	resolved["pierce"] = maxi(0, roundi(skill_stat(key, "pierce", base)))


## The W.Att a physical hit of `key` resolves with: the level field named by the definition's `summon.watk_field` (a
## physical follower's `pad`, spec #332 M8) in place of the worn weapon plus ammo, else the character's `watk`.
func _summon_watk(key: String, lv: int, d: Dictionary) -> float:
	var field := String(d.get("summon", {}).get("watk_field", ""))
	return book.canonical(key, lv, field, 0.0) if field != "" else watk


## Heal's resolved HP threshold (a fraction of max HP): the data's `hp_threshold` plus the `heal_threshold` modifier, capped at
## HEAL_THRESHOLD_CAP and rounded to 1e-4 (modifier values are stored as float32, so 0.5 + 0.15 would read 0.65000001). 0 for a
## skill without a `heal` block.
func _heal_threshold(key: String, heal: Dictionary) -> float:
	if heal.is_empty():
		return 0.0
	return roundi(clampf(skill_stat(key, "heal_threshold", float(heal.get("hp_threshold", 0.0))), 0.0, HEAL_THRESHOLD_CAP) * 10000.0) / 10000.0


## Seconds between casts: the skill's own cooldown with its cards, then the cast speed passives (an active skill's cooldown
## x (1 - cast speed)), the product of every factor floored at COOLDOWN_FLOOR of the base, then attack speed.
func _cooldown(key: String, d: Dictionary, heal: Dictionary, lv: int, rank: int, speed_factor: float) -> float:
	var base := _base_cooldown(key, d, heal, lv, rank)
	var cooldown := skill_stat(key, "cooldown", base)
	if book.slot(key) == "active" and base > 0.0:
		cooldown = maxf(cooldown * (1.0 - passive_total(CAST_SPEED_PCT) / 100.0), base * COOLDOWN_FLOOR)
	return maxf(0.05, cooldown * speed_factor)


## The seconds between casts before cards and attack speed: the definition's `cooldown_by_rank` (survivor seconds per
## rank, indexed by rank - 1, the last value repeating) when it has one, else its `cooldown_field` (a canonical level
## number, e.g. `cooltime`) when it names one, else the Heal `recast_delay`, else the survivor `cooldown`, else 1.
func _base_cooldown(key: String, d: Dictionary, heal: Dictionary, lv: int, rank: int) -> float:
	var by_rank: Variant = d.get("cooldown_by_rank")
	if by_rank is Array and not (by_rank as Array).is_empty():
		return float(by_rank[clampi(rank - 1, 0, by_rank.size() - 1)])
	var fallback := float(heal.get("recast_delay", d.get("cooldown", 1.0)))
	if d.has("cooldown_field"):
		return book.canonical(key, lv, String(d.cooldown_field), fallback)
	return fallback


## The resolved moving-attack block of `key` ({} for a skill that does not move): {direction "away" | "toward" | "input",
## when "before" | "after" | "during", distance px >= 0}. The definition's `displacement` gives the distance as `field` (a
## canonical level field of this rank's level; `lt.x` is the reach of its box, Rush), `distances` (survivor values per
## rank, the last one repeating) or a plain `distance`, in that order (docs/GAME_DESIGN.md 7.13). `input` (a manual
## dash, 7.33) is the pressed arrow key or the facing, chosen by the caster.
func _displacement(key: String, d: Dictionary, rank: int, lv: int) -> Dictionary:
	var block: Variant = d.get("displacement", {})
	if not (block is Dictionary) or (block as Dictionary).is_empty():
		return {}
	var distance := 0.0
	if block.has("field"):
		var field := String(block.field)
		if field.ends_with(".x") and book.level_node(key, lv).get(field.trim_suffix(".x")) is Dictionary:
			var corner: Array = book.level_node(key, lv)[field.trim_suffix(".x")].get("$v", [0.0, 0.0])
			distance = absf(float(corner[0]))
		else:
			distance = book.canonical(key, lv, field, 0.0)
	elif block.has("distances") and not (block.distances as Array).is_empty():
		var list: Array = block.distances
		distance = float(list[clampi(rank - 1, 0, list.size() - 1)])
	else:
		distance = float(block.get("distance", 0.0))
	return {"direction": String(block.get("direction", "away")), "when": String(block.get("when", "after")),
		"distance": maxf(0.0, distance)}


## The second-life plan inputs of `key` (PlayerRevive reads them; nothing else does): see PlayerRevive.resolve.
func _revive(key: String, block: Dictionary) -> Dictionary:
	return PlayerRevive.resolve(block, skill_stat(key, "revive_hp", PlayerRevive.hp_base(block)),
		skill_stat(key, "revive_guard", PlayerRevive.guard_base(block)))


func _buff_effects(key: String, lv: int, buff: Dictionary) -> Dictionary:
	var effects := {}
	if buff.has("stat"):
		effects[String(buff.stat)] = book.canonical(key, lv, String(buff.get("field", "")), 0.0)
	for effect: Dictionary in buff.get("effects", []):
		var stat := String(effect.stat)
		# `scale` (optional, default 1) flips a WZ sign (the Boosters' negative speed steps use -1; Rage's pdd is already negative in the WZ and takes no scale).
		effects[stat] = float(effects.get(stat, 0.0)) \
			+ book.canonical(key, lv, String(effect.field), 0.0) * float(effect.get("scale", 1.0))
	return effects


## Every effect of owned skill `key`'s `passive`: the legacy single `stat` (with `field` or `per_level`) first, then the
## optional `effects` list of {stat, field | per_level} entries (a Mastery skill adds mastery and ACC, Critical Shot adds
## chance and damage).
func passive_effects(key: String) -> Array:
	var p: Dictionary = book.def(key).get("passive", {})
	var out: Array = []
	if p.has("stat"):
		out.append(p)
	out.append_array(p.get("effects", []))
	return out


## Sum of owned passive effects of `passive_stat`: canonical fields or survivor per-level values from skills.json.
func passive_total(passive_stat: String) -> float:
	var t := 0.0
	for k: String in order:
		for effect: Dictionary in passive_effects(k):
			if String(effect.get("stat", "")) == passive_stat:
				t += passive_value(k, level(k), effect)
	return t


## The largest single owned effect of `passive_stat`; 0 when none. For stats that do not stack across skills (mastery,
## crit damage).
func passive_best(passive_stat: String) -> float:
	var best := 0.0
	for k: String in order:
		for effect: Dictionary in passive_effects(k):
			if String(effect.get("stat", "")) == passive_stat:
				best = maxf(best, passive_value(k, level(k), effect))
	return best


## Extra HP that the owned skills with a `regen` field add to one regeneration pulse. A skill declares
## `"regen": {"pool": "hp", "field": "hp"}` (Improved HP Recovery) and adds that canonical level number as it is
## (tier A: +3 to +50).
func regen_bonus() -> float:
	var t := 0.0
	for k: String in order:
		var r: Variant = book.def(k).get("regen")
		if r is Dictionary and String(r.get("pool", "hp")) == "hp" and r.has("field"):
			t += book.canonical(k, level(k), String(r.field))
	return t


## Effect of skill `key`'s `passive` at canonical `skill_level`: its survivor `per_level` value times the level, else
## the canonical `field` of that level (0 without a passive).
func passive_value(key: String, skill_level: int, passive: Dictionary) -> float:
	if passive.has("per_level"):
		return float(passive.per_level) * skill_level
	return book.canonical(key, skill_level, String(passive.get("field", "")), 0.0) if not passive.is_empty() else 0.0


static func _stack(m: Vector2, op: String, value: float) -> Vector2:
	if op == "mul":
		return Vector2(m.x, m.y * value)
	return Vector2(m.x + value, m.y)

## Resolves a sub at the parent's rank with only its damage and area inheritance.
func sub_stats(sub: String, parent: Dictionary, rank: int) -> Dictionary:
	var lo := clone()
	lo.add_skill_mod(sub, "damage", "mul", float(parent.get("form_sub_damage", 1.0)))
	lo.add_skill_mod(sub, "area", "mul", float(parent.get("form_sub_area", 1.0)))
	return lo.stats(sub, rank)


## Awards a status once in learning order; later awards add scaled chance points without numeric skill modifiers.
func add_status_grant(key: String, id: String, scale: float = 1.0) -> void:
	if not status_bonuses.has(id):
		return
	if not grants.has(key):
		grants[key] = []
		grant_chances[key] = {}
	if id in grants[key]:
		grant_chances[key][id] = float(grant_chances[key].get(id, 0.0)) + StatusBonus.repeat_points(status_bonuses[id], scale)
	else:
		grants[key].append(id)
	version += 1


func _add_status_grants(resolved: Dictionary, key: String, r: int) -> void:
	if grants.get(key, []).is_empty():
		return
	resolved["status_grants"] = StatusBonus.resolve(status_bonuses, grants[key], r, grant_chances[key])
