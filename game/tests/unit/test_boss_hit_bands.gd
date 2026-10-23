extends TestCase
## Frozen #77 C24 survivor boss HP and hit-roll endpoints, with canonical PAD/HP verified against WZ.
## Numerical survivor expectations are independent of the runtime formula; canonical checks remain unchanged.

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
}


## Tier C: #77 frozen C24 training-data endpoints; the former 40-50% / shared-slot starting targets are superseded.
const FROZEN_ROLLS := {
	"henesys": {
		2220000: {"touch": Vector2i(29, 34)},
		6130101: {"touch": Vector2i(38, 45), "attack1": Vector2i(38, 44)},
		9400205: {"touch": Vector2i(151, 178), "attack1": Vector2i(150, 177)},
	},
	"ellinia": {
		3220000: {"touch": Vector2i(25, 30), "attack1": Vector2i(25, 30), "attack2": Vector2i(25, 30)},
		9300003: {"touch": Vector2i(14, 17), "attack1": Vector2i(14, 17)},
		6220000: {"touch": Vector2i(36, 42)},
	},
	"perion": {
		2220000: {"touch": Vector2i(25, 29)},
		3220000: {"touch": Vector2i(192, 228), "attack1": Vector2i(209, 247), "attack2": Vector2i(209, 247)},
		4090000: {"touch": Vector2i(14, 16)},
	},
	"kerning": {
		9300003: {"touch": Vector2i(8, 10), "attack1": Vector2i(8, 10)},
		5090000: {"touch": Vector2i(162, 192)},
		6220000: {"touch": Vector2i(78, 93)},
	},
}

## Tier C: #77 C24 survivor HP expectations.
const FROZEN_HP := {
	"henesys": {
		2220000: 5760,
		6130101: 14400,
		9400205: 21000,
	},
	"ellinia": {
		3220000: 4095,
		9300003: 17600,
		6220000: 20150,
	},
	"perion": {
		2220000: 5760,
		3220000: 24500,
		4090000: 23100,
	},
	"kerning": {
		9300003: 5220,
		5090000: 14400,
		6220000: 17500,
	},
}

## Every (stage, boss, source) case with its canonical inputs and frozen survivor multiplier.
func _cases() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var stages: Dictionary = DataRepo.load_all().stages.stages
	for key: String in ["henesys", "ellinia", "perion", "kerning"]:
		for entry: Dictionary in DataRepo.stage_bosses(stages[key]):
			var id := int(entry.mob_id)
			var sources: Array = ["touch"] + Array(entry.get("attacks", []))
			for source: String in sources:
				out.append({"stage": key, "name": "%s %d %s" % [key, id, source], "id": id, "source": source,
					"pad": float(CANONICAL_PAD.get(id, {}).get(source, -1.0)),
					"mult": float(entry.dmg_mult if source == "touch" else entry.attack_dmg_mult),
					"hp": float(entry.typical_hp), "pdd": float(entry.typical_pdd)})
	return out


## Verifies the frozen survivor endpoints without changing canonical attack inputs.
func test_frozen_boss_hit_roll_ranges() -> void:
	var cases := _cases()
	assert_eq(cases.size(), 20, "all scheduled tier-1 touch hits and selected attacks")
	for c: Dictionary in cases:
		assert_true(float(c.pad) > 0.0, "%s: canonical PAD is listed" % c.name)
		var low := CombatMath.monster_damage(float(c.pad), 0.0, float(c.pdd), 0.0, float(c.mult))
		var high := CombatMath.monster_damage(float(c.pad), 1.0, float(c.pdd), 0.0, float(c.mult))
		assert_eq(Vector2i(low, high), FROZEN_ROLLS[c.stage][int(c.id)][c.source],
			"%s: frozen C24 roll endpoints" % c.name)


## v83 Mob.wz info/maxHP of the scheduled tier-1 bosses (checked against the cache below).
const CANONICAL_HP := {2220000: 2000.0, 6130101: 20000.0, 9400205: 200000.0, 3220000: 7000.0, 9300003: 8000.0,
	6220000: 31000.0, 4090000: 2200.0, 5090000: 4800.0}
## Tier C: unchanged 1 HP helper tolerance from the old slot comparison; the endpoint test above remains exact.
const SLOT_ROLL_TOLERANCE := 1


## Tier C: #77 C24 replaces equal-slot starting multipliers with per-region HP and hit-roll expectations.
## The slot's illustrative typical HP/defence remains unchanged, as do the WZ inputs checked below.
func test_new_region_frozen_boss_hp_and_rolls() -> void:
	var stages: Dictionary = DataRepo.load_all().stages.stages
	var slots: Array = DataRepo.stage_bosses(stages.henesys)
	for key: String in ["perion", "kerning"]:
		var entries: Array = DataRepo.stage_bosses(stages[key])
		assert_eq(entries.size(), 3, "%s schedules three bosses" % key)
		for i in mini(entries.size(), 3):
			var e: Dictionary = entries[i]
			var slot: Dictionary = slots[i]
			var id := int(e.mob_id)
			var name := "%s map %d boss %d" % [key, i + 1, id]
			assert_eq(float(e.typical_hp), float(slot.typical_hp), "%s: illustrative typical HP" % name)
			assert_eq(float(e.typical_pdd), float(slot.typical_pdd), "%s: illustrative W.DEF" % name)
			assert_eq(roundi(CANONICAL_HP[id] * float(e.hp_mult)), FROZEN_HP[key][id], name + " frozen HP")
			_assert_roll_near(_roll(CANONICAL_PAD[id].touch, e, float(e.dmg_mult)),
				FROZEN_ROLLS[key][id].touch, name + " touch")
			for attack: String in e.get("attacks", []):
				_assert_roll_near(_roll(CANONICAL_PAD[id][attack], e, float(e.attack_dmg_mult)),
					FROZEN_ROLLS[key][id][attack], "%s %s" % [name, attack])


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
