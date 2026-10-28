extends TestCase
## SkillText: the one source of player-visible skill text (v83 String.wz desc / hN lines, survivor overrides filled
## from effective stats), the level-up cards dressed with it, and the MapleText markup it is drawn with. String.wz data
## here is synthetic, except the require_cache() pass over the real v83 strings.

const RF := preload("res://tests/fixtures/run_fixtures.gd")

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
	assert_eq(text.level_line("energy_bolt", 2, lo.stats("energy_bolt", 2)), "Basic attack 21, mastery 15%",
		"the WZ line named by the level node's hs, without its MP cost (no MP, #285)")
	assert_eq(text.desc("magic_armor"), "Boosts the weapon def.",
		"Required Skill lines go: WZ prerequisites are ignored in this game")
	assert_eq(text.level_line("magic_armor", 1, lo.stats("magic_armor")), "Weapon def. +2,\nfor 54 sec.",
		"literal \\r\\n escapes become one line break")
	assert_eq(text.desc("recovery"), "Recovers HP.\n#cTerms between skills : 10 min.#",
		"markup stays for the renderer; the space before a break goes")
	assert_eq(text.desc("unknown"), "", "no text for an unknown skill")
	assert_eq(SkillText.new(book, {}).level_line("energy_bolt", 1, lo.stats("energy_bolt")), "",
		"no text without strings or an override")


func test_an_override_replaces_the_wz_text_and_fills_effective_stats() -> void:
	var book := _book({"thunder_bolt": {"desc": "Strikes nearby monsters with a thunder bolt.",
		"h": "Basic attack {mad}, mastery {mastery_pct}%, up to {mob_count|monster|monsters}"}})
	var text := SkillText.new(book, STRINGS)
	var lo := Loadout.new(book)
	lo.add_skill("thunder_bolt")
	assert_eq(text.desc("thunder_bolt"), "Strikes nearby monsters with a thunder bolt.", "the override desc wins")
	assert_eq(text.level_line("thunder_bolt", 1, lo.stats("thunder_bolt")),
		"Basic attack 2, mastery 15%, up to 6 monsters", "canonical mobCount 6 before any card")
	lo.add_skill_mod("thunder_bolt", "count", "add", 2.0)
	assert_eq(text.level_line("thunder_bolt", 1, lo.stats("thunder_bolt")),
		"Basic attack 2, mastery 15%, up to 8 monsters", "a +2 targets card shows as 8")
	assert_eq(text.desc("energy_bolt"), "Use MP to attack one enemy.", "skills without an override keep WZ text")


func test_level_up_cards_show_the_skill_text_at_the_offered_level() -> void:
	var w := RF.quiet_world()
	RF.change_job_bare(w, 200)
	var text := SkillText.new(w.book, {"2001003": {"desc": "[Master Level : 20]\\nBoosts the weapon def.",
		"h1": "MP -8; weapon def. +2", "h2": "MP -8; weapon def. +4"}})
	var learn := w.upgrades.choice_card("magic_armor_new", w)
	var mod := w.upgrades.choice_card("energy_bolt_rank", w, "unique") # the 212 start skill (#284; the Beginner cards are gone)
	var magnet := w.upgrades.choice_card("elixir", w)
	var cards := text.dress([learn, mod, magnet], w.loadout)
	assert_eq([cards[0].desc, cards[0].detail], ["Boosts the weapon def.", "Weapon def. +2"],
		"a learn card: the skill's desc and its level-1 line")
	assert_eq(text.dress([w.upgrades.choice_card("magic_armor_new", w, "rare")], w.loadout)[0].detail,
		"Weapon def. +2", "a Rare learn gives rank 1 too (#287)")
	assert_eq(cards[1].desc, mod.desc, "a rarity card keeps its rank and bonus text")
	assert_has(LevelUpWindow.change_lines(cards[1]), "Shots: 1 → 2", "with the number it changes")
	assert_eq(cards[2], magnet, "cards without a skill are left alone")
	w.upgrades.apply("magic_armor_new", w)
	var rank: Dictionary = text.dress([w.upgrades.choice_card("magic_armor_rank", w)], w.loadout)[0]
	assert_eq(rank.desc, "Weapon def. +4", "a rank card: the next level's line")
	assert_false(LevelUpWindow.change_lines(rank).is_empty(), "above its before -> after values")
	var bare: Dictionary = SkillText.new(w.book, {}).dress([learn], w.loadout)[0]
	assert_eq([bare.desc, String(bare.get("detail", ""))], [learn.desc, ""], "without strings the card data text stays")


func test_strip_mp_cost_drops_the_v83_mp_cost_wordings() -> void:
	assert_eq(SkillText.strip_mp_cost("MP -10, Damage 120%"), "Damage 120%")
	assert_eq(SkillText.strip_mp_cost("MP - 10 , damage 120%"), "Damage 120%", "spaced wording, first letter capitalised")
	assert_eq(SkillText.strip_mp_cost("HP -12, MP -8; increase"), "HP -12; increase", "the HP cost stays")
	assert_eq(SkillText.strip_mp_cost("Use 20 MP, Damage 150%"), "Damage 150%")
	assert_eq(SkillText.strip_mp_cost("Max HP +10%, Max MP +10%"), "Max HP +10%, Max MP +10%", "not a cost: unchanged")
	assert_eq(SkillText.strip_mp_cost("Damage 120%"), "Damage 120%", "no cost: unchanged")


func test_markup_draws_orange_runs_and_never_a_raw_hash() -> void:
	assert_eq(MapleText.runs("Lasts #c10 min.# more"), [["Lasts ", false], ["10 min.", true], [" more", false]])
	assert_eq(MapleText.runs("#bblue#k and a stray #"), [["blue and a stray ", false]],
		"other v83 colour codes and stray #s are dropped, never drawn")
	assert_eq(MapleText.plain("A #cB# C"), "A B C")
	var lines := MapleText.wrap_markup("Recovers HP.\n#cTerms between skills : 10 min.#", 80.0, MapleText.SMALL)
	assert_true(lines.size() >= 3, "the break is kept and the long orange run wraps: %s" % [lines])
	assert_eq(lines[0], "Recovers HP.")
	for line: String in lines.slice(1):
		assert_true(line.begins_with("#c") and line.ends_with("#"), "each wrapped line reopens the orange: %s" % line)
		for run: Array in MapleText.runs(line):
			assert_false("#" in String(run[0]), "no # reaches the screen")


func test_templates_pick_the_singular_and_leave_unknown_names() -> void:
	assert_eq(SkillText.fill("{count|bolt|bolts}, {count|bolt|bolts}", {"count": 1.0}), "1 bolt, 1 bolt")
	assert_eq(SkillText.fill("{count|bolt|bolts}", {"count": 3.0}), "3 bolts")
	assert_eq(SkillText.fill("cooldown {cooldown} sec.", {"cooldown": 0.968}), "cooldown 0.97 sec.")
	assert_eq(SkillText.fill("{nope} stays", {}), "{nope} stays", "an unknown name is left for the tests to find")


func test_bless_text_explains_the_accuracy_bonus_that_raises_critical_chance() -> void:
	var world := RF.quiet_world(400.0, 1)
	RF.as_job(world, 230)
	world.learn_skill("energy_bolt")
	world.learn_skill("bless")
	var before := float(world.loadout.stats("energy_bolt").crit)
	world.start_buff("bless", world.loadout.stats("bless"))
	assert_true(float(world.loadout.stats("energy_bolt").crit) > before, "ADR 0005: Bless ACC contributes to crit")
	var text := SkillText.new(world.book, {})
	var card := world.upgrades.choice_card("bless_new", world)
	var descriptions := [String(world.book.def("bless").desc), text.desc("bless"), String(card.desc),
		String(text.dress([card], world.loadout)[0].desc)]
	for description: String in descriptions:
		assert_true("accuracy" in description.to_lower(), "the accuracy bonus stays visible")
		assert_true("critical" in description.to_lower(), "the tooltip and card explain its combat benefit")
		assert_false("no effect" in description.to_lower() or "no combat effect" in description.to_lower())
		assert_false("canonical" in description.to_lower(), "plain player-visible wording")


# --- every player-visible skill and card text ----------------------------------------------------------------------

## Fields a v83 skill level node can carry, so every override template can resolve without the cache.
const LEVEL_FIELDS := ["mpCon", "mad", "mastery", "attackCount", "fixdamage", "x", "y", "time", "prop", "pdd", "mdd",
	"acc", "eva", "mobCount", "range", "speed", "cooltime", "hp", "mp", "jump", "damage", "hpCon"]


func test_no_skill_or_card_text_says_canonical_or_leaves_markup_or_placeholders() -> void:
	var data := DataRepo.load_all()
	var imgs := {}
	var strings := {}
	var resolved: Dictionary = SkillTemplate.resolve(data.skills.skills)
	for key: String in resolved:
		var d: Dictionary = resolved[key]
		var id := "%07d" % int(d.skill_id)
		var levels := {}
		var s := {"name": String(d.name), "desc": "[Master Level : 20]\\nSynthetic %s. \\n#cTerms between skills : 1 min.#\\nRequired Skill : #cAt least Level 1 on X#" % key}
		for lv in range(1, (d.get("ranks", [4,8,12,15,19,23,27,30]) as Array).max() + 1):
			var node := {"hs": "h%d" % lv, "lt": {"$v": [-100.0, -50.0]}, "rb": {"$v": [100.0, 50.0]}}
			for f: String in LEVEL_FIELDS:
				node[f] = float(lv)
			levels[str(lv)] = node
			s["h%d" % lv] = "MP -%d;\\r\\nsynthetic line" % lv
		if not imgs.has(String(d.book)):
			imgs[String(d.book)] = {"skill": {}}
		imgs[String(d.book)].skill[id] = {"level": levels}
		strings[id] = s
	_check_all_text(imgs, strings, "synthetic")


func test_real_v83_skill_and_card_text_is_clean() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	var data := DataRepo.load_all()
	var imgs := {}
	for book: String in DataRepo.skill_books(data):
		var img := lib.img(DataRepo.skill_img_path(book))
		if img != null:
			imgs[book] = img.root
	_check_all_text(imgs, lib.find("String.wz/Skill.img"), "v83")


## Every skill at every level (desc and level line) and every card of upgrades.json at every tier, dressed for the
## level-up window: present, no "canonical", only well-formed #c...# markup, no unfilled {placeholder}.
func _check_all_text(imgs: Dictionary, strings: Variant, label: String) -> void:
	var setup := RF.setup("quiet", 7, RF.quiet_data())
	setup.skill_imgs = imgs
	var w := RunWorld.new(setup)
	var text := SkillText.new(w.book, strings)
	for key: String in w.book.defs:
		_check_text(text.desc(key), "%s %s desc" % [label, key], true)
		for r in range(1, w.book.max_rank(key) + 1):
			var line := text.level_line(key, w.book.canonical_level(key, r), w.loadout.stats(key, r))
			_check_text(line, "%s %s level %d" % [label, key, r], true)
	var root: Dictionary = DataRepo.load_all().upgrades
	var all_cards: Array = root.cards.duplicate()
	all_cards.append(root.fallback)
	for c: Dictionary in all_cards:
		_check_text(String(c.name), "%s card %s name" % [label, c.id], true)
	for c: Dictionary in root.cards:
		var skill := String(c.get("skill", ""))
		var kind := String(c.kind)
		if skill != "" and kind != "skill_new" and not w.loadout.has(skill):
			w.loadout.add_skill(skill)
		if skill != "" and kind == "skill_new" and w.loadout.has(skill):
			w.loadout.ranks.erase(skill)
			w.loadout.order.erase(skill)
		for tier: String in UpgradePool.TIERS:
			var offered := w.upgrades.choice_card(String(c.id), w, tier)
			var where := "%s card %s (%s)" % [label, c.id, tier]
			_check_text(String(offered.desc), where + " data desc (shown without String.wz)", true)
			var card: Dictionary = text.dress([offered], w.loadout)[0]
			_check_text(String(card.desc), where + " desc", true)
			_check_text(String(card.get("detail", "")), where + " detail", kind == "skill_new")
			for line: String in LevelUpWindow.change_lines(card):
				_check_text(line, where + " change", true)
			_check_text(LevelUpWindow.rank_text(card), where + " rank", false)
		if kind == "skill_rank":
			for r in range(1, w.book.max_rank(skill)):
				w.loadout.set_rank(skill, r)
				var card: Dictionary = text.dress([w.upgrades.choice_card(String(c.id), w)], w.loadout)[0]
				_check_text(String(card.desc), "%s card %s at rank %d" % [label, c.id, r], true)


func _check_text(s: String, where: String, required: bool) -> void:
	if required:
		assert_ne(s.strip_edges(), "", "%s: has text" % where)
	assert_false("canonical" in s.to_lower(), "%s says canonical: %s" % [where, s])
	var unmarked := RegEx.create_from_string("#c[^#\\n]*#").sub(s, "", true)
	assert_false("#" in unmarked, "%s: raw # markup: %s" % [where, s])
	assert_true(RegEx.create_from_string("\\{[^}]*\\}").search(s) == null, "%s: unfilled placeholder: %s" % [where, s])
