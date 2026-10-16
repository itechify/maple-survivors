extends TestCase
## The v83 Skill window (#86): SkillWindowModel's tabs (one per job on the character's path plus the star tab),
## rows (every implemented skill of the job with its level / max, unlearned ones at 0), the tooltips (SkillText lines,
## cooldown, MP cost, the Upgrades list of behaviour cards) and the star tab's job-neutral cards; then SkillWindow's
## keyboard navigation. All data is synthetic (no cache): a two-branch job tree, a few skills, a few cards.

## Synthetic String.wz/Skill.img: book names and skill lines.
const STRINGS := {
	"000": {"bookName": "Beginner's Basics"},
	"200": {"bookName": "Intro. to Magic"},
	"220": {"bookName": "Ice & Lightning Basics"},
	"0001000": {"name": "Three Snails", "desc": "Throws snail shells.", "h1": "MP -3, damage 10",
		"h2": "MP -3, damage 25"},
	"2001005": {"name": "Magic Claw", "desc": "Use MP to attack an enemy twice.", "h1": "MP -10, basic attack 11",
		"h2": "MP -10, basic attack 12"},
	"2001004": {"name": "Energy Bolt", "desc": "Use MP to attack one enemy.", "h1": "MP -6, basic attack 20"},
	"2000001": {"name": "Improved MP Recovery", "desc": "Recovers more MP.", "h1": "MP recovery +3"},
}


func _jobs() -> JobTree:
	return JobTree.from_data({"jobs": [
		{"id": 0, "name": "Beginner", "parent": -1, "tier": 0, "level": 1, "book": "000"},
		{"id": 200, "name": "Magician", "parent": 0, "tier": 1, "level": 8, "book": "200"},
		{"id": 210, "name": "Wizard (Fire, Poison)", "parent": 200, "tier": 2, "level": 30, "book": "210"},
		{"id": 220, "name": "Wizard (Ice, Lightning)", "parent": 200, "tier": 2, "level": 30, "book": "220"},
	]}, {})


func _book() -> SkillBook:
	var skills := {
		"three_snails": {"skill_id": 1000, "book": "000", "job": 0, "kind": "projectile", "damage": "fixed",
			"name": "Three Snails", "icon": "Skill.wz/000.img/skill/0001000/icon", "cooldown": 1.1, "count": 1,
			"ranks": [1, 2]},
		"magic_claw": {"skill_id": 2001005, "book": "200", "job": 200, "kind": "instant", "damage": "magic",
			"name": "Magic Claw", "icon": "Skill.wz/200.img/skill/2001005/icon", "cooldown": 1.25, "count": 1,
			"ranks": [1, 2]},
		"energy_bolt": {"skill_id": 2001004, "book": "200", "job": 200, "kind": "projectile", "damage": "magic",
			"name": "Energy Bolt", "icon": "Skill.wz/200.img/skill/2001004/icon", "cooldown": 0.9, "count": 1,
			"ranks": [1]},
		"improved_mp_recovery": {"skill_id": 2000001, "book": "200", "job": 200, "kind": "passive",
			"damage": "none", "name": "Improved MP Recovery", "icon": "Skill.wz/200.img/skill/2000001/icon",
			"ranks": [1]},
		"thunder_bolt": {"skill_id": 2201005, "book": "220", "job": 220, "kind": "instant", "damage": "magic",
			"name": "Thunder Bolt", "icon": "Skill.wz/220.img/skill/2201005/icon", "ranks": [1]},
		"fire_arrow": {"skill_id": 2101004, "book": "210", "job": 210, "kind": "projectile", "damage": "magic",
			"name": "Fire Arrow", "icon": "Skill.wz/210.img/skill/2101004/icon", "ranks": [1]},
		"unused_skill": {"skill_id": 2001009, "book": "200", "job": 200, "kind": "instant", "damage": "magic",
			"name": "No Card", "ranks": [1]},
	}
	var imgs := {
		"000": {"skill": {"0001000": {"level": {"1": {"hs": "h1", "mpCon": 3.0, "fixdamage": 10.0},
			"2": {"hs": "h2", "mpCon": 3.0, "fixdamage": 25.0}}}}},
		"200": {"skill": {
			"2001005": {"level": {"1": {"hs": "h1", "mpCon": 10.0, "mad": 11.0, "mastery": 1.0},
				"2": {"hs": "h2", "mpCon": 10.0, "mad": 12.0, "mastery": 1.0}}},
			"2001004": {"level": {"1": {"hs": "h1", "mpCon": 6.0, "mad": 20.0, "mastery": 1.0}}},
			"2000001": {"level": {"1": {"hs": "h1", "x": 3.0}}}}},
	}
	return SkillBook.from_data({"skills": skills}, imgs)


func _pool() -> UpgradePool:
	return UpgradePool.from_data({
		"cards": [
			{"id": "three_snails_count", "kind": "skill_mod", "skill": "three_snails", "name": "Additional Shell",
				"desc": "Three Snails throws +{value} shell.", "value": 1, "max_rank": 4,
				"effects": [{"stat": "count", "op": "add", "value": 1}]},
			{"id": "energy_bolt_new", "kind": "skill_new", "skill": "energy_bolt", "name": "Energy Bolt",
				"max_rank": 1, "effects": []},
			{"id": "magic_claw_new", "kind": "skill_new", "skill": "magic_claw", "name": "Magic Claw",
				"max_rank": 1, "effects": []},
			{"id": "magic_claw_rank", "kind": "skill_rank", "skill": "magic_claw", "name": "Magic Claw",
				"max_rank": 20, "effects": [{"stat": "rank", "op": "add", "value": 1}]},
			{"id": "magic_claw_targets", "kind": "skill_mod", "skill": "magic_claw", "name": "Twin Claw",
				"desc": "Magic Claw strikes +{value} more monster.", "value": 1, "max_rank": 2,
				"effects": [{"stat": "count", "op": "add", "value": 1}]},
			{"id": "magic_claw_cooldown", "kind": "skill_mod", "skill": "magic_claw", "name": "Quick Claw",
				"desc": "Magic Claw cooldown -{value}%.", "max_rank": 3,
				"effects": [{"stat": "cooldown", "op": "mul", "value": 0.88}]},
			{"id": "improved_mp_recovery", "kind": "skill_new", "skill": "improved_mp_recovery",
				"name": "Improved MP Recovery", "max_rank": 1, "effects": []},
			{"id": "thunder_bolt_new", "kind": "skill_new", "skill": "thunder_bolt", "name": "Thunder Bolt",
				"max_rank": 1, "effects": []},
			{"id": "fire_arrow_new", "kind": "skill_new", "skill": "fire_arrow", "name": "Fire Arrow",
				"max_rank": 1, "effects": []},
			{"id": "magnet", "kind": "stat", "skill": "", "name": "Magnet", "desc": "Pick-up radius +{value}%.", "value": 25,
				"icon": "Character.wz/PetEquip/01812000.img/info/icon", "max_rank": 4,
				"effects": [{"stat": "magnet", "op": "mul", "value": 1.25}]},
			{"id": "orange_potion", "kind": "potion_tier", "skill": "", "name": "Orange Potions",
				"desc": "Upgrade all HP stock to Orange Potions.", "icon": "Item.wz/Consume/0200.img/02000001/info/icon",
				"max_rank": 1, "effects": []},
			{"id": "mana_elixir", "kind": "potion_tier", "skill": "", "name": "Mana Elixirs",
				"desc": "Upgrade all MP stock to Mana Elixirs.", "max_rank": 1, "effects": []},
		],
		"fallback": {"id": "elixir", "kind": "filler", "skill": "", "name": "Power Elixir",
			"desc": "Fully restores HP and MP.", "max_rank": 0, "effects": []},
	})


## A Magician (200) who has Three Snails rank 2 with one Additional Shell, Magic Claw rank 1 with Twin Claw x2 and
## Quick Claw x1, and took Magnet x2, Orange Potions and the Elixir fallback.
func _magician_loadout(book: SkillBook) -> Loadout:
	var lo := Loadout.new(book)
	lo.add_skill("three_snails")
	lo.set_rank("three_snails", 2)
	lo.add_skill_mod("three_snails", "count", "add", 1.0)
	lo.add_skill("magic_claw")
	lo.add_skill_mod("magic_claw", "count", "add", 2.0)
	lo.add_skill_mod("magic_claw", "cooldown", "mul", 0.88)
	lo.card_ranks = {"three_snails_count": 1, "magic_claw_new": 1, "magic_claw_targets": 2,
		"magic_claw_cooldown": 1, "magnet": 2, "orange_potion": 1, "elixir": 1}
	return lo


func _model(job_id: int, lo: Loadout = null) -> SkillWindowModel:
	var book := lo.book if lo != null else _book()
	if lo == null:
		lo = Loadout.new(book)
	return SkillWindowModel.new(book, _pool(), lo, _jobs(), job_id, SkillText.new(book, STRINGS))


static func _tab_names(m: SkillWindowModel) -> Array:
	var out := []
	for t: Dictionary in m.tabs:
		out.append(String(t.name))
	return out


func test_tabs_follow_the_job_path_and_end_with_the_star_tab() -> void:
	assert_eq(_tab_names(_model(0)), ["Beginner", "Star"], "a Beginner has the Beginner tab and the star tab")
	assert_eq(_tab_names(_model(200)), ["Beginner", "Magician", "Star"], "1st job adds its tab")
	var m := _model(220)
	assert_eq(_tab_names(m), ["Beginner", "Magician", "Wizard (Ice, Lightning)", "Star"],
		"the 2nd-job branch reached, not the other branch")
	assert_eq(m.tabs[0].tier, 0, "the Beginner tab uses the Beginner tab glyph")
	assert_eq(m.tabs[2].tier, 2, "the 2nd job tab uses glyph II")
	assert_eq(m.tabs[1].book_name, "Intro. to Magic", "the job's v83 book name")
	assert_eq(m.tabs[1].book_icon, "Skill.wz/200.img/info/icon")
	assert_eq(String(m.tabs[3].kind), "star")


static func _row_keys(tab: Dictionary) -> Array:
	var out := []
	for r: Dictionary in tab.rows:
		out.append(String(r.get("key", r.get("id", ""))))
	return out


func test_each_job_tab_lists_the_jobs_implemented_skills_with_learned_ranks_and_greyed_unlearned_ones() -> void:
	var m := _model(200, _magician_loadout(_book()))
	assert_eq(_row_keys(m.tabs[0]), ["three_snails"], "the Beginner tab")
	assert_eq(_row_keys(m.tabs[1]), ["improved_mp_recovery", "energy_bolt", "magic_claw"],
		"every Magician skill a card can offer, in v83 skill id order; a skill no card offers is not listed")
	var snails: Dictionary = m.tabs[0].rows[0]
	assert_eq([snails.name, snails.level, snails.max_level, snails.learned], ["Three Snails", 2, 2, true],
		"a learned skill shows its level / max")
	assert_eq(snails.icon, "Skill.wz/000.img/skill/0001000/icon")
	var claw: Dictionary = m.tabs[1].rows[2]
	assert_eq([claw.level, claw.max_level, claw.learned], [1, 2, true])
	var bolt: Dictionary = m.tabs[1].rows[1]
	assert_eq([bolt.level, bolt.max_level, bolt.learned], [0, 1, false], "an unlearned skill is greyed at 0 / max")
	assert_eq(bolt.icon_disabled, "Skill.wz/200.img/skill/2001004/iconDisabled", "drawn with its v83 disabled icon")
	assert_eq(_row_keys(_model(220).tabs[2]), ["thunder_bolt"], "the 2nd-job tab lists that branch's skills")


func test_the_star_tab_lists_the_job_neutral_cards_taken_but_not_the_elixir() -> void:
	var m := _model(200, _magician_loadout(_book()))
	var star: Dictionary = m.tabs[m.tabs.size() - 1]
	assert_eq(_row_keys(star), ["magnet", "orange_potion"],
		"Magnet and the potion tier taken, in card order; Mana Elixirs not taken; the Elixir fallback never")
	var magnet: Dictionary = star.rows[0]
	assert_eq([magnet.name, magnet.rank, magnet.max_rank], ["Magnet", 2, 4], "with its rank")
	assert_eq(magnet.icon, "Character.wz/PetEquip/01812000.img/info/icon")
	assert_eq(_row_keys(_model(0).tabs[1]), [], "nothing taken: an empty star tab")


func test_the_skill_tooltip_lists_each_behaviour_card_taken_with_its_steps() -> void:
	var m := _model(200, _magician_loadout(_book()))
	var tip := m.skill_tooltip("magic_claw")
	assert_eq(tip.upgrades.size(), 2, "the two Magic Claw behaviour cards taken; rank and learn cards are not listed")
	assert_eq([tip.upgrades[0].name, tip.upgrades[0].steps, tip.upgrades[0].effect], ["Twin Claw", 2, "+2 targets"])
	assert_eq(tip.upgrades[0].text, "Twin Claw ×2: +2 targets")
	assert_eq(tip.upgrades[1].text, "Quick Claw ×1: -12% cooldown", "a multiplier shows as its percentage")
	assert_eq(m.skill_tooltip("three_snails").upgrades[0].text, "Additional Shell ×1: +1 shot",
		"a projectile skill's count is shots")
	assert_eq(m.skill_tooltip("energy_bolt").upgrades, [], "no cards taken, no Upgrades")


func test_the_skill_tooltip_has_the_skill_text_cooldown_and_mp_cost() -> void:
	var m := _model(200, _magician_loadout(_book()))
	var tip := m.skill_tooltip("magic_claw")
	assert_eq([tip.name, tip.icon], ["Magic Claw", "Skill.wz/200.img/skill/2001005/icon"])
	assert_eq(tip.desc, "Use MP to attack an enemy twice.")
	assert_eq([tip.level, tip.current], [1, "MP -10, basic attack 11"], "the owned level's line")
	assert_eq([tip.next_level, tip.next], [2, "MP -10, basic attack 12"], "the next level's line")
	assert_near(tip.cooldown, 1.1, 1e-6, "the effective cooldown: 1.25 s with one Quick Claw step (x0.88)")
	assert_eq(tip.mp_cost, 10)
	var maxed := m.skill_tooltip("three_snails")
	assert_eq([maxed.level, maxed.current, maxed.next_level, maxed.next], [2, "MP -3, damage 25", 0, ""],
		"no next level at the cap")
	var unlearned := m.skill_tooltip("energy_bolt")
	assert_eq([unlearned.level, unlearned.current, unlearned.next_level, unlearned.next],
		[0, "", 1, "MP -6, basic attack 20"], "an unlearned skill shows what level 1 does")
	var passive := m.skill_tooltip("improved_mp_recovery")
	assert_eq([passive.cooldown, passive.mp_cost], [-1.0, -1], "a passive has neither")


func test_a_star_card_tooltip_describes_every_step_taken() -> void:
	var m := _model(200, _magician_loadout(_book()))
	var tip := m.card_tooltip("magnet")
	assert_eq([tip.name, tip.rank, tip.max_rank], ["Magnet", 2, 4])
	assert_eq(tip.desc, "Pick-up radius +56.25%.", "two x1.25 steps compound to +56.25%")
	assert_eq(m.card_tooltip("orange_potion").desc, "Upgrade all HP stock to Orange Potions.")
