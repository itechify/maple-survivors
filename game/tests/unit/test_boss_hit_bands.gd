extends TestCase
## Spec: a boss hit takes 40-50% of the documented typical HP pool at the boss's spawn time. Deterministic: the whole
## roll range (85% and 100% of PAD, after floor(0.75 x typical W.DEF), times the shipped multiplier, rounded) of every
## scheduled boss's contact hit and selected attacks must lie inside the band. Multipliers, typical_hp/typical_pdd and
## the attack selection come from the shipped stages.json; canonical PAD values are the v83 Mob.wz numbers below,
## checked against the real asset cache when it is present.

const BAND_MIN := 0.4
const BAND_MAX := 0.5
## v83 Mob.wz PADamage: "touch" = info/PADamage, attackN = attackN/info/PADamage (docs/GAME_DESIGN.md 4.3).
const CANONICAL_PAD := {
	2220000: {"touch": 90.0},
	6130101: {"touch": 200.0, "attack1": 300.0},
	9400205: {"touch": 450.0, "attack1": 300.0},
	3220000: {"touch": 125.0, "attack1": 135.0, "attack2": 135.0},
	9300003: {"touch": 130.0, "attack1": 165.0},
	6220000: {"touch": 190.0},
}


## Every (stage, boss, source) case: {name, pad, mult, hp, pdd}.
func _cases() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var stages: Dictionary = DataRepo.load_all().stages.stages
	for key: String in ["henesys", "ellinia"]:
		for entry: Dictionary in DataRepo.stage_bosses(stages[key]):
			var id := int(entry.mob_id)
			var sources: Array = ["touch"] + Array(entry.get("attacks", []))
			for source: String in sources:
				out.append({"name": "%s %d %s" % [key, id, source], "id": id, "source": source,
					"pad": float(CANONICAL_PAD.get(id, {}).get(source, -1.0)),
					"mult": float(entry.dmg_mult if source == "touch" else entry.attack_dmg_mult),
					"hp": float(entry.typical_hp), "pdd": float(entry.typical_pdd)})
	return out


func test_every_boss_hit_roll_range_lies_in_the_40_to_50_percent_band() -> void:
	var cases := _cases()
	assert_eq(cases.size(), 11,
		"six contact hits plus five selected attacks (two mushroom slams, Stumpy's slam and ball, King Slime's slam)")
	for c: Dictionary in cases:
		assert_true(float(c.pad) > 0.0, "%s: canonical PAD is listed" % c.name)
		var low := CombatMath.monster_damage(float(c.pad), 0.0, float(c.pdd), 0.0, float(c.mult))
		var high := CombatMath.monster_damage(float(c.pad), 1.0, float(c.pdd), 0.0, float(c.mult))
		var lo_f := float(low) / float(c.hp)
		var hi_f := float(high) / float(c.hp)
		var inside := lo_f >= BAND_MIN - 1e-9 and hi_f <= BAND_MAX + 1e-9
		print("  %s: x%.2f -> %d..%d of %d HP = %.2f%%..%.2f%%" % [c.name, float(c.mult), low, high,
			int(c.hp), lo_f * 100.0, hi_f * 100.0])
		assert_true(inside, "%s: %d..%d of %d HP (%.2f%%..%.2f%%) must lie in 40-50%%" % [c.name, low, high,
			int(c.hp), lo_f * 100.0, hi_f * 100.0])


func test_canonical_pad_table_matches_the_real_mob_imgs() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	for id: int in CANONICAL_PAD:
		var img := lib.mob_root(id)
		for source: String in CANONICAL_PAD[id]:
			var info: Dictionary = img.get("info", {}) if source == "touch" else img.get(source, {}).get("info", {})
			assert_eq(float(info.get("PADamage", -1.0)), float(CANONICAL_PAD[id][source]),
				"%d %s PADamage" % [id, source])
			assert_eq(float(info.get("MADamage", 0.0)) if source != "touch" else 0.0, 0.0,
				"%d %s is a physical hit" % [id, source])
	lib.free()
