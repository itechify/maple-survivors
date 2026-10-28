class_name HpRisk
extends RefCounted
## HP-risk skills (roster M17, spec #348): a percentage HP cost, an HP gate, recoil as a share of the damage a cast dealt
## and a low-HP damage bonus. Stateless static helpers like CombatMath: no node, no clock, no RNG draw. The seam is
## data-driven and job-blind: any skill definition may carry the blocks below, and a skill without them is untouched.
##
##   "hp_cost":     {"field": "hpCon", "of": "flat" | "max_hp"}   flat (default) pays the canonical field as it is;
##                  max_hp pays floor(field / 100 x max HP). Resolved into the `hp_cost` stat, the same number every
##                  consumer (admission, RunWorld.can_pay_hp, the bot, the Skill window) already reads.
##   "hp_gate":     {"above": 0.5}      the cast waits while current HP is not strictly above 50% of max HP.
##   "self_damage": {"field": "x", "of": "damage_dealt", "cap_max_hp": 0.10}
##                  after the cast the caster loses floor(field / 100 x damage applied), at most cap_max_hp x max HP,
##                  never the last HP.
##
## Rarity-bonus / card modifier stats (Loadout skill mods): `hp_cost` (mul), `self_damage` (mul), `low_hp_damage` (add,
## a fraction of damage, applied while HP is at or below BERSERK_BELOW of max HP at the moment of the cast).
## RunWorld.can_pay_hp / spend_hp stay the one place HP is paid (it never pays the last HP); this file only decides how
## much, whether the cast is admitted and what the recoil is. Events: `hp_spent` (see RunWorld.EVENT_FIELDS).

## HP fraction at or below which `low_hp_damage` applies. tier A: Berserk (1320006) level 30 `x` is 50 (% of HP).
const BERSERK_BELOW := 0.5
## Card-text names of the modifier stats (UpgradePool.rarity_bonus labels).
const LABELS := {"hp_cost": "HP cost", "self_damage": "Recoil", "low_hp_damage": "Low-HP damage"}
## `hp_spent.kind` values.
const KIND_COST := "cost"
const KIND_RECOIL := "recoil"


## The HP cost of skill `key` at canonical level `lv`, with the skill's `hp_cost` modifiers: the canonical field (`hpCon`
## unless the definition's `hp_cost.field` names another) as it is for `of: flat`, floor(field / 100 x max HP) for
## `of: max_hp`. Scaled by the `hp_cost` modifier, floored, never negative. A skill with no block and no `hpCon` is 0.
static func cost(lo: Loadout, key: String, lv: int) -> int:
	var block: Dictionary = lo.book.def(key).get("hp_cost", {})
	var amount := lo.book.canonical(key, lv, String(block.get("field", "hpCon")), 0.0)
	if String(block.get("of", "flat")) == "max_hp":
		amount = amount * lo.max_hp / 100.0
	return maxi(0, floori(lo.skill_stat(key, "hp_cost", amount)))


## The HP-risk numbers of skill `key` at canonical level `lv`, merged into Loadout.stats: `hp_gate` (fraction of max HP,
## 0 = none), `self_damage` (percent of the damage dealt lost as recoil, after the `self_damage` modifier; 0 = none) and
## `self_damage_cap` (fraction of max HP one cast's recoil may take) and `low_hp_damage` (the Berserk bonus, a fraction of
## damage added while HP is at or below BERSERK_BELOW; 0 = none).
static func resolve(lo: Loadout, key: String, lv: int) -> Dictionary:
	var d := lo.book.def(key)
	var gate: Dictionary = d.get("hp_gate", {})
	var recoil: Dictionary = d.get("self_damage", {})
	var percent := 0.0
	if not recoil.is_empty():
		percent = maxf(0.0, lo.skill_stat(key, "self_damage", lo.book.canonical(key, lv, String(recoil.get("field", "x")), 0.0)))
	return {"hp_gate": float(gate.get("above", 0.0)), "self_damage": percent,
		"self_damage_cap": float(recoil.get("cap_max_hp", 1.0)), "low_hp_damage": lo.skill_stat(key, "low_hp_damage", 0.0)}


## The Skill window / tooltip lines of resolved stats `st` (empty for a skill with no HP-risk block): the gate, the recoil
## and the low-HP bonus. The cost itself shows as the ordinary `hp_cost` fact.
static func mechanic_lines(st: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	if float(st.get("hp_gate", 0.0)) > 0.0:
		lines.append("Needs more than %s%% HP" % _percent(float(st.hp_gate) * 100.0))
	if float(st.get("self_damage", 0.0)) > 0.0:
		lines.append("Recoil: %s%% of damage dealt (at most %s%% of max HP)" % [_percent(float(st.self_damage)),
			_percent(float(st.get("self_damage_cap", 1.0)) * 100.0)])
	if float(st.get("low_hp_damage", 0.0)) > 0.0:
		lines.append("+%s%% damage at %s%% HP or less" % [_percent(float(st.low_hp_damage) * 100.0), _percent(BERSERK_BELOW * 100.0)])
	return lines


static func _percent(value: float) -> String:
	return str(snappedf(value, 0.1)).trim_suffix(".0")


## Whether the `hp_gate` of resolved stats `st` is open at `hp` of `max_hp`: no gate, or HP strictly above the gate's
## share of max HP.
static func gate_open(st: Dictionary, hp: float, max_hp: float) -> bool:
	var above := float(st.get("hp_gate", 0.0))
	return above <= 0.0 or hp > above * max_hp


## Whether the cast of resolved stats `st` is admitted on its HP terms: the gate is open and paying the cost would leave
## the caster alive (RunWorld.can_pay_hp). A refused cast waits: nothing is spent and no cooldown starts.
static func admits(world: RunWorld, st: Dictionary) -> bool:
	return world.can_pay_hp(int(st.hp_cost)) and gate_open(st, world.hp_exact(), float(world.player_state.max_hp))


## Pays the HP cost of the cast of `st` through RunWorld.spend_hp and reports it (`hp_spent`, kind cost; nothing at zero).
static func pay_cost(world: RunWorld, st: Dictionary) -> void:
	var amount := int(st.hp_cost)
	if amount > 0 and world.spend_hp(amount):
		_report(world, st, amount, KIND_COST)


## The cast-local stats of a cast that starts now: a copy whose damage carries the `low_hp_damage` bonus (x(1 + bonus), the
## fields PlayerMeter.begin_cast also scales) while HP is at or below BERSERK_BELOW of max HP, read before the cost is
## paid. Any other cast gets `st` itself (never mutated: stats are cached).
static func begin_cast(world: RunWorld, st: Dictionary) -> Dictionary:
	var bonus := float(st.get("low_hp_damage", 0.0))
	if bonus == 0.0 or world.hp_exact() > BERSERK_BELOW * float(world.player_state.max_hp):
		return st
	var out := st.duplicate()
	for field: String in ["damage_min", "damage_max", "status_damage_mult"]:
		out[field] = float(out.get(field, 0.0)) * (1.0 + bonus)
	return out


## The recoil of a cast of resolved stats `st` that applied `dealt` damage, for a caster at `hp` of `max_hp`:
## floor(self_damage / 100 x dealt), at most floor(self_damage_cap x max HP), and never the last HP. 0 for a skill with no
## `self_damage` and for a cast that dealt nothing.
static func recoil(st: Dictionary, dealt: int, hp: float, max_hp: float) -> int:
	var percent := float(st.get("self_damage", 0.0))
	if percent <= 0.0 or dealt <= 0:
		return 0
	var share := floori(percent * dealt / 100.0)
	var cap := floori(float(st.get("self_damage_cap", 1.0)) * max_hp)
	return maxi(0, mini(mini(share, cap), floori(hp - 1.0)))


## Charges the recoil of the cast that just resolved: `dealt_before` is RunWorld.damage_dealt taken before the cast, so the
## damage applied is what its instant lines added (shots still in flight are not counted; tier C). The cast already
## happened, so there is no admission: RunWorld.spend_hp pays it (hp_spent, kind recoil; nothing at zero).
static func settle(world: RunWorld, st: Dictionary, dealt_before: int) -> void:
	if float(st.get("self_damage", 0.0)) <= 0.0:
		return
	var amount := recoil(st, world.damage_dealt - dealt_before, world.hp_exact(), float(world.player_state.max_hp))
	if amount > 0 and world.spend_hp(amount):
		_report(world, st, amount, KIND_RECOIL)


static func _report(world: RunWorld, st: Dictionary, amount: int, kind: String) -> void:
	world.emit("hp_spent", {"skill": String(st.skill), "skill_id": int(st.skill_id), "amount": amount, "kind": kind})
