extends RefCounted
## Synthetic support-summon world for the sim tests (no Nexon data, no Dark Knight data): a made-up job 999 whose
## Beholder-like summon (skill 9990001) pulses a heal (sub 9990002) and a buff (sub 9990003). See test_support_summons.gd.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const PARENT := "synth_beholder"
const AURA := "synth_aura"
const HEX := "synth_hex"


## Animation node of `frames` frames of `ms` milliseconds (the sim reads only the delays).
static func anim(frames: int, ms: float = 100.0) -> Dictionary:
	var out := {}
	for i in frames:
		out[str(i)] = {"delay": ms}
	return out


## Sub-skill level tables. Parent levels 1..8 (explicit ranks [1..8]); sub levels 1..16 reached through the sub's OWN
## table [2, 4, ..., 16], so a test that wrongly used the parent's rank as a level reads different numbers.
static func skill_imgs() -> Dictionary:
	var parent_levels := {}
	for lv in range(1, 9):
		parent_levels[str(lv)] = {"time": 60.0}
	var aura_levels := {}
	var hex_levels := {}
	for lv in range(1, 17):
		aura_levels[str(lv)] = {"hp": 10.0 * lv, "x": 20.0 - lv}
		var hex := {"x": 24.0 - lv, "time": 10.0 + lv, "pdd": 5.0 * lv}
		if lv >= 6:
			hex["mdd"] = 3.0 * lv
		if lv >= 11:
			hex["acc"] = float(lv)
		if lv >= 14:
			hex["pad"] = float(lv)
		if lv >= 16:
			hex["eva"] = 2.0 * lv
		hex_levels[str(lv)] = hex
	var summon := {"summoned": anim(3), "stand": anim(4), "move": anim(2), "die": anim(2)}
	for n in range(1, 7):
		summon["skill%d" % n] = anim(4 if n > 1 else 6)
	return {"999": {"skill": {
		"9990001": {"level": parent_levels, "summon": summon},
		"9990002": {"level": aura_levels},
		"9990003": {"level": hex_levels},
	}}}


static func definitions() -> Dictionary:
	var ranks := [2, 4, 6, 8, 10, 12, 14, 16]
	return {
		PARENT: {"skill_id": 9990001, "book": "999", "job": 999, "name": "Synth Beholder", "kind": "summon",
			"slot": "active", "cast": {"rule": "summon"}, "cooldown": 45.0, "damage": "none",
			"ranks": [1, 2, 3, 4, 5, 6, 7, 8],
			"summon": {"path": "Skill.wz/999.img/skill/9990001/summon", "attack": "", "follow_speed": 180.0,
				"follow_distance": 60.0, "teleport_distance": 600.0,
				"support": {"pulses": [
					{"skill": AURA, "kind": "heal", "first_after": "interval", "anim": "skill1"},
					{"skill": HEX, "kind": "buff", "first_after": 3.0, "anim": "skill2"},
				]}}},
		AURA: {"skill_id": 9990002, "book": "999", "job": 999, "name": "Synth Aura", "kind": "support",
			"slot": "summon_sub", "summon_sub_of": PARENT, "ranks": ranks},
		HEX: {"skill_id": 9990003, "book": "999", "job": 999, "name": "Synth Hex", "kind": "support",
			"slot": "summon_sub", "summon_sub_of": PARENT, "ranks": ranks,
			"buff": {"effects": [{"stat": "pdd", "field": "pdd"}, {"stat": "mdd", "field": "mdd"},
				{"stat": "acc", "field": "acc"}, {"stat": "avoid", "field": "eva"},
				{"stat": "watk", "field": "pad"}]}},
	}


## A quiet world holding the synthetic Beholder as its only owned skill.
static func world(seed_value := 352) -> RunWorld:
	var setup := RF.setup("quiet", seed_value, RF.quiet_data())
	setup.skill_imgs.merge(skill_imgs())
	setup.data.skills.skills.merge(definitions())
	setup.data.balance["regen"] = {"interval": 10, "hp": 0} # natural regeneration off: only pulses move HP
	setup.data.stages.stages.quiet.maps.append(setup.data.stages.stages.quiet.maps[0].duplicate(true))
	var w := RunWorld.new(setup)
	RF.place_player(w, 200)
	w.loadout.order.clear()
	w.learn_skill(PARENT)
	w.loadout.set_caster(100.0, 0.0, 30)
	w.loadout.add_player_mod("max_hp", "add", 1000.0) # room for a flat heal to show exactly
	w.refresh_player_stats()
	return w
