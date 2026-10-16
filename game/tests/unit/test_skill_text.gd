extends TestCase
## SkillText: the one source of player-visible skill text (v83 String.wz desc / hN lines, survivor overrides filled
## from effective stats) and the MapleText markup it is drawn with. String.wz data here is synthetic.

## Synthetic String.wz/Skill.img entries, written the way the cache stores them: literal "\n" / "\r\n" escapes.
const STRINGS := {
	"2001004": {"name": "Energy Bolt", "desc": "[Master Level : 20]\\nUse MP to attack one enemy.",
		"h1": "MP -6, basic attack 20, mastery 15%", "h2": "MP -6, basic attack 21, mastery 15%"},
	"2201005": {"name": "Thunder Bolt",
		"desc": "[Master Level : 30]\\nAttacks surrounding monsters.  All monsters in the range receive damage.",
		"h1": "MP -20; Basic attack 2, mastery 15%"},
	"2001003": {"name": "Magic Armor", "desc": "[Master Level : 20]\\nBoosts the weapon def.\\nRequired Skill : #cAt least Level 3 on Magic Guard#",
		"h1": "MP -8; weapon def. +2,\\r\\nfor 54 sec."},
	"0001001": {"name": "Recovery", "desc": "Recovers HP. \\n#cTerms between skills : 10 min.#", "h1": "MP -10"},
}


func _book(text_overrides: Dictionary = {}) -> SkillBook:
	var skills := {
		"energy_bolt": {"skill_id": 2001004, "book": "200", "kind": "projectile", "damage": "magic", "count": 1,
			"ranks": [1, 2]},
		"thunder_bolt": {"skill_id": 2201005, "book": "220", "kind": "instant", "damage": "magic",
			"cast": {"rule": "box"}, "ranks": [1]},
		"magic_armor": {"skill_id": 2001003, "book": "200", "kind": "buff", "damage": "none", "ranks": [1]},
		"recovery": {"skill_id": 1001, "book": "000", "kind": "buff", "damage": "none", "ranks": [1]},
	}
	for key: String in text_overrides:
		skills[key]["text"] = text_overrides[key]
	var imgs := {
		"200": {"skill": {
			"2001004": {"level": {"1": {"hs": "h1", "mpCon": 6.0, "mad": 20.0, "mastery": 1.0},
				"2": {"hs": "h2", "mpCon": 6.0, "mad": 21.0, "mastery": 1.0}}},
			"2001003": {"level": {"1": {"hs": "h1", "mpCon": 8.0, "pdd": 2.0, "time": 54.0}}}}},
		"220": {"skill": {"2201005": {"level": {"1": {"hs": "h1", "mpCon": 20.0, "mad": 2.0, "mastery": 1.0,
			"mobCount": 6.0, "lt": {"$v": [-150.0, -50.0]}, "rb": {"$v": [150.0, 50.0]}}}}}},
		"000": {"skill": {"0001001": {"level": {"1": {"hs": "h1", "mpCon": 5.0, "x": 4.0, "time": 30.0,
			"cooltime": 120.0}}}}},
	}
	return SkillBook.from_data({"skills": skills}, imgs)


func test_wz_text_is_used_without_an_override() -> void:
	var book := _book()
	var text := SkillText.new(book, STRINGS)
	var lo := Loadout.new(book)
	assert_eq(text.desc("energy_bolt"), "Use MP to attack one enemy.",
		"the WZ desc, without the [Master Level] line the level text already shows")
	assert_eq(text.level_line("energy_bolt", 2, lo.stats("energy_bolt", 2)), "MP -6, basic attack 21, mastery 15%",
		"the WZ line named by the level node's hs")
	assert_eq(text.desc("magic_armor"), "Boosts the weapon def.",
		"Required Skill lines go: WZ prerequisites are ignored in this game")
	assert_eq(text.level_line("magic_armor", 1, lo.stats("magic_armor")), "MP -8; weapon def. +2,\nfor 54 sec.",
		"literal \\r\\n escapes become one line break")
	assert_eq(text.desc("recovery"), "Recovers HP.\n#cTerms between skills : 10 min.#",
		"markup stays for the renderer; the space before a break goes")
	assert_eq(text.desc("unknown"), "", "no text for an unknown skill")
	assert_eq(SkillText.new(book, {}).level_line("energy_bolt", 1, lo.stats("energy_bolt")), "",
		"no text without strings or an override")


func test_an_override_replaces_the_wz_text_and_fills_effective_stats() -> void:
	var book := _book({"thunder_bolt": {"desc": "Strikes nearby monsters with a thunder bolt.",
		"h": "MP -{mp_cost}; Basic attack {mad}, mastery {mastery_pct}%, up to {mob_count|monster|monsters}"}})
	var text := SkillText.new(book, STRINGS)
	var lo := Loadout.new(book)
	lo.add_skill("thunder_bolt")
	assert_eq(text.desc("thunder_bolt"), "Strikes nearby monsters with a thunder bolt.", "the override desc wins")
	assert_eq(text.level_line("thunder_bolt", 1, lo.stats("thunder_bolt")),
		"MP -20; Basic attack 2, mastery 15%, up to 6 monsters", "canonical mobCount 6 before any card")
	lo.add_skill_mod("thunder_bolt", "count", "add", 2.0)
	assert_eq(text.level_line("thunder_bolt", 1, lo.stats("thunder_bolt")),
		"MP -20; Basic attack 2, mastery 15%, up to 8 monsters", "a +2 targets card shows as 8")
	assert_eq(text.desc("energy_bolt"), "Use MP to attack one enemy.", "skills without an override keep WZ text")


func test_templates_pick_the_singular_and_leave_unknown_names() -> void:
	assert_eq(SkillText.fill("{count|bolt|bolts}, {count|bolt|bolts}", {"count": 1.0}), "1 bolt, 1 bolt")
	assert_eq(SkillText.fill("{count|bolt|bolts}", {"count": 3.0}), "3 bolts")
	assert_eq(SkillText.fill("cooldown {cooldown} sec.", {"cooldown": 0.968}), "cooldown 0.97 sec.")
	assert_eq(SkillText.fill("{nope} stays", {}), "{nope} stays", "an unknown name is left for the tests to find")
