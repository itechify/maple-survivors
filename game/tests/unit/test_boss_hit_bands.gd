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
	4090000: {"touch": 95.0},
	5090000: {"touch": 165.0},
	# #452: the Ellinia and Perion swaps. King Clang's shell 5220001 stands and never attacks; the form 5220000 does.
	3300008: {"touch": 130.0, "attack1": 150.0},
	3300005: {"touch": 125.0, "attack1": 125.0},
	5220002: {"touch": 165.0, "attack1": 190.0},
	5220001: {"touch": 165.0},
	5220000: {"touch": 165.0, "attack1": 180.0},
}


## The mob whose img holds `source`'s PADamage for a scheduled entry: attacks belong to the final form when it has one.
func _pad(entry: Dictionary, source: String) -> float:
	var id := int(entry.mob_id)
	if source != "touch" and entry.has("final_form"):
		id = int(entry.final_form)
	return float(CANONICAL_PAD.get(id, {}).get(source, -1.0))


## Every (stage, boss, source) case: {name, pad, mult, hp, pdd}.
func _cases() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var stages: Dictionary = DataRepo.load_all().stages.stages
	for key: String in ["henesys", "ellinia", "perion", "kerning"]:
		for entry: Dictionary in DataRepo.stage_bosses(stages[key]):
			var id := int(entry.mob_id)
			var sources: Array = ["touch"] + Array(entry.get("attacks", []))
			for source: String in sources:
				out.append({"name": "%s %d %s" % [key, id, source], "id": id, "source": source,
					"pad": _pad(entry, source),
					"mult": float(entry.dmg_mult if source == "touch" else entry.attack_dmg_mult),
					"hp": float(entry.typical_hp), "pdd": float(entry.typical_pdd)})
	return out


func test_every_boss_hit_roll_range_lies_in_the_40_to_50_percent_band() -> void:
	var cases := _cases()
	assert_eq(cases.size(), 21, "Henesys/Ellinia: six contact hits plus five selected attacks (two mushroom slams, "
		+ "Prime Minister's, Grey Yeti's and Faust's attack1; #452); Perion/Kerning (#253): six more contact hits plus "
		+ "Stumpy's two attacks, King Clang's attack1 and King Slime's slam")
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


## v83 Mob.wz info/maxHP of the scheduled tier-1 bosses (checked against the cache below).
const CANONICAL_HP := {2220000: 2000.0, 6130101: 20000.0, 9400205: 200000.0, 3220000: 7000.0, 9300003: 8000.0,
	6220000: 31000.0, 4090000: 2200.0, 5090000: 4800.0, 3300008: 12500.0, 3300005: 120000.0, 5220002: 9800.0,
	5220001: 4000.0, 5220000: 25000.0}


## An entry's survivor HP to defeat: a final form's encounter is the shell's HP plus the form's (#456).
func _survivor_hp(entry: Dictionary) -> int:
	var hp := roundi(CANONICAL_HP[int(entry.mob_id)] * float(entry.hp_mult))
	if entry.has("final_form"):
		hp += roundi(CANONICAL_HP[int(entry.final_form)] * float(entry.get("final_form_hp_mult", entry.hp_mult)))
	return hp
## Roll endpoints may differ from the Henesys slot's by this many HP: the 0.01 multiplier steps and the different
## canonical PAD values cannot always hit both endpoints exactly.
const SLOT_ROLL_TOLERANCE := 1


## Spec #253: each Perion and Kerning City boss matches the Henesys boss of its map slot (Mano, Mushmom, Blue Mushmom)
## at that slot's typical_hp/typical_pdd: the same survivor HP and touch/attack roll ranges within one HP. Mano has no
## attack, so a map-1 attack matches Mano's touch.
func test_new_region_bosses_match_the_henesys_boss_of_their_map_slot() -> void:
	var stages: Dictionary = DataRepo.load_all().stages.stages
	var slots: Array = DataRepo.stage_bosses(stages.henesys)
	for key: String in ["perion", "kerning"]:
		var entries: Array = DataRepo.stage_bosses(stages[key])
		assert_eq(entries.size(), 3, "%s schedules three bosses" % key)
		for i in mini(entries.size(), 3):
			var e: Dictionary = entries[i]
			var s: Dictionary = slots[i]
			var name := "%s map %d boss %d" % [key, i + 1, int(e.mob_id)]
			assert_eq(float(e.typical_hp), float(s.typical_hp), "%s: the slot's typical HP" % name)
			assert_eq(float(e.typical_pdd), float(s.typical_pdd), "%s: the slot's typical W.DEF" % name)
			assert_eq(_survivor_hp(e), _survivor_hp(s), "%s: the slot's survivor HP" % name)
			var slot_touch := _roll(_pad(s, "touch"), s, float(s.dmg_mult))
			_assert_roll_near(_roll(_pad(e, "touch"), e, float(e.dmg_mult)), slot_touch,
				name + " touch")
			var slot_attack := slot_touch
			if not s.get("attacks", []).is_empty():
				slot_attack = _roll(_pad(s, s.attacks[0]), s, float(s.attack_dmg_mult))
			for attack: String in e.get("attacks", []):
				_assert_roll_near(_roll(_pad(e, attack), e, float(e.attack_dmg_mult)),
					slot_attack, "%s %s" % [name, attack])


## What each Ellinia boss replaced (#452, #254 method), from the former shipped entries: survivor HP, touch and attack
## roll ranges at the slot's typical HP/W.DEF. Stumpy 7000 x 0.45, touch 125 x 0.83, slam 135 x 0.77; King Slime
## 8000 x 1.1, touch 130 x 1.36, slam 165 x 1.06; Dyle 31000 x 0.26, touch 190 x 1.14 (no attack: its touch stands in).
const ELLINIA_REPLACED := [
	{"hp": 3150, "touch": Vector2i(84, 100), "attack": Vector2i(85, 100)},
	{"hp": 8800, "touch": Vector2i(143, 170), "attack": Vector2i(143, 170)},
	{"hp": 8060, "touch": Vector2i(178, 211), "attack": Vector2i(178, 211)},
]


## #452: Prime Minister, Grey Yeti and King Pepe and Faust match the boss of their slot (survivor HP exactly, roll
## endpoints within one HP) at the replaced boss's typical HP and W.DEF.
func test_ellinia_bosses_match_the_boss_they_replaced() -> void:
	var entries: Array = DataRepo.stage_bosses(DataRepo.load_all().stages.stages.ellinia)
	assert_eq(entries.size(), 3)
	assert_eq(entries.map(func(e: Dictionary) -> int: return int(e.mob_id)), [3300008, 3300005, 5220002])
	for i in mini(entries.size(), 3):
		var e: Dictionary = entries[i]
		var want: Dictionary = ELLINIA_REPLACED[i]
		var name := "ellinia map %d boss %d" % [i + 1, int(e.mob_id)]
		assert_eq(_survivor_hp(e), int(want.hp), name + ": the replaced boss's survivor HP")
		_assert_roll_near(_roll(_pad(e, "touch"), e, float(e.dmg_mult)), want.touch, name + " touch")
		assert_eq(e.get("attacks", []), ["attack1"], name + ": its one canonical attack")
		_assert_roll_near(_roll(_pad(e, "attack1"), e, float(e.attack_dmg_mult)), want.attack, name + " attack1")


func _roll(pad: float, entry: Dictionary, mult: float) -> Vector2i:
	return Vector2i(CombatMath.monster_damage(pad, 0.0, float(entry.typical_pdd), 0.0, mult),
		CombatMath.monster_damage(pad, 1.0, float(entry.typical_pdd), 0.0, mult))


func _assert_roll_near(got: Vector2i, want: Vector2i, label: String) -> void:
	assert_true(absi(got.x - want.x) <= SLOT_ROLL_TOLERANCE and absi(got.y - want.y) <= SLOT_ROLL_TOLERANCE,
		"%s: %d..%d matches the slot's %d..%d" % [label, got.x, got.y, want.x, want.y])


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
	for id: int in CANONICAL_HP:
		assert_eq(float(lib.mob_root(id).get("info", {}).get("maxHP", -1.0)), CANONICAL_HP[id], "%d maxHP" % id)
	lib.free()
