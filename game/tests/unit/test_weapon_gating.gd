extends TestCase
## Weapon-gated skills and cards (spec #151 ticket #156, docs/GAME_DESIGN.md 7.5 and 8): SkillBook reads a skill's weapon
## requirement (Skill.wz `weapon` and the `"weapon "` typo key, overridden by survivor `weapon_families`), the runner only
## casts a skill the held weapon allows, UpgradePool only offers its cards, and the Skill window greys it. All data is
## synthetic (no cache); weapons are swapped through RunWorld.equip_item like the Equip window does.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
## Synthetic item nodes shaped like Character.wz `info`: no requirements, so any of them can be worn.
const INFO := {
	1302000: {"incPAD": 17, "attackSpeed": 4, "tuc": 7},
	1332063: {"incPAD": 20, "attackSpeed": 4, "tuc": 7},
	1472061: {"incPAD": 20, "attackSpeed": 4, "tuc": 7},
	1482000: {"incPAD": 20, "attackSpeed": 4, "tuc": 7},
}


# --- SkillBook: where the requirement comes from -------------------------------------------------------------------

func _book(skills: Dictionary, imgs: Dictionary) -> SkillBook:
	return SkillBook.from_data({"skills": skills}, imgs)


func test_the_canonical_weapon_field_is_the_requirement() -> void:
	var b := _book({"drain": {"skill_id": 4101005, "book": "410"}, "plain": {"skill_id": 4101004, "book": "410"}},
		{"410": {"skill": {"4101005": {"weapon": 47}, "4101004": {"level": {"1": {}}}}}})
	assert_eq(b.weapon_families("drain"), PackedStringArray(["claw"]), "Skill.wz weapon 47 = type 147 = claw")
	assert_eq(b.weapon_families("plain"), PackedStringArray(), "no weapon field: any weapon")
	assert_eq(b.weapon_families("unknown_key"), PackedStringArray())
	assert_true(b.usable_with("drain", "claw"))
	assert_false(b.usable_with("drain", "dagger"))
	assert_false(b.usable_with("drain", ""), "bare hands are not a claw")
	assert_true(b.usable_with("plain", ""), "an untagged skill works bare-handed")
	assert_true(b.usable_with("plain", "claw"))


func test_the_weapon_key_with_a_trailing_space_is_read_too() -> void:
	# The real shape of 5001003 Pirate Double Shot: the key is "weapon " (trailing space), value 49 = gun.
	var b := _book({"double_shot": {"skill_id": 5001003, "book": "500"}},
		{"500": {"skill": {"5001003": {"weapon ": 49, "level": {"1": {}}}}}})
	assert_eq(b.weapon_families("double_shot"), PackedStringArray(["gun"]))
	assert_true(b.usable_with("double_shot", "gun"))
	assert_false(b.usable_with("double_shot", "knuckle"))
	var parsed := _book({"double_shot": {"skill_id": 5001003, "book": "500"}},
		{"500": {"skill": {"5001003": JSON.parse_string('{"weapon ": 49.0}')}}})
	assert_eq(parsed.weapon_families("double_shot"), PackedStringArray(["gun"]), "a JSON float code works")
	var text := _book({"double_shot": {"skill_id": 5001003, "book": "500"}},
		{"500": {"skill": {"5001003": {"weapon ": "49"}}}})
	assert_eq(text.weapon_families("double_shot"), PackedStringArray(["gun"]), "a string code works")


func test_a_one_and_a_two_handed_code_share_the_family() -> void:
	var b := _book({"a": {"skill_id": 1, "book": "1"}, "b": {"skill_id": 2, "book": "1"}},
		{"1": {"skill": {"0000001": {"weapon": 30}, "0000002": {"weapon": 40}}}})
	assert_eq(b.weapon_families("a"), PackedStringArray(["sword"]))
	assert_eq(b.weapon_families("b"), PackedStringArray(["sword"]))


func test_survivor_weapon_families_override_the_canonical_requirement() -> void:
	var skills := {
		"retag": {"skill_id": 1, "book": "1", "weapon_families": ["knuckle", "gun"]},
		"any_weapon": {"skill_id": 2, "book": "1", "weapon_families": ["any"]},
		"untagged_gets_one": {"skill_id": 3, "book": "1", "weapon_families": ["knuckle"]},
	}
	var b := _book(skills, {"1": {"skill": {"0000001": {"weapon": 47}, "0000002": {"weapon": 47}, "0000003": {}}}})
	assert_eq(b.weapon_families("retag"), PackedStringArray(["knuckle", "gun"]), "the override wins over weapon 47")
	assert_true(b.usable_with("retag", "gun"))
	assert_false(b.usable_with("retag", "claw"), "the canonical claw no longer applies")
	assert_eq(b.weapon_families("any_weapon"), PackedStringArray(), "[\"any\"] means explicitly any weapon")
	assert_true(b.usable_with("any_weapon", "dagger"))
	assert_true(b.usable_with("any_weapon", ""), "even bare-handed")
	assert_eq(b.weapon_families("untagged_gets_one"), PackedStringArray(["knuckle"]), "a tag on an untagged skill")


func test_an_unknown_weapon_code_or_missing_img_means_no_requirement() -> void:
	var b := _book({"odd": {"skill_id": 1, "book": "1"}, "noimg": {"skill_id": 2, "book": "9"}},
		{"1": {"skill": {"0000001": {"weapon": 3}}}})
	assert_eq(b.weapon_families("odd"), PackedStringArray(), "code 3 names no weapon type")
	assert_eq(b.weapon_families("noimg"), PackedStringArray(), "no Skill.wz img: untagged")


func test_shipping_survivor_data_names_only_real_families() -> void:
	var data := DataRepo.load_all()
	var names := {"any": true}
	for family: Variant in WeaponInfo.FAMILIES.values():
		names[String(family)] = true
	for key: String in data.skills.skills:
		var fams: Variant = data.skills.skills[key].get("weapon_families", [])
		assert_true(fams is Array, key + " weapon_families is an array")
		for f: Variant in fams:
			assert_true(names.has(String(f)), "%s names a known weapon family: %s" % [key, f])


func test_every_family_has_a_display_name() -> void:
	for family: Variant in WeaponInfo.FAMILIES.values():
		assert_true(WeaponInfo.family_label(String(family)) != "", String(family))
	assert_eq(WeaponInfo.family_label("claw"), "Claw")
	assert_eq(WeaponInfo.family_label("polearm"), "Pole Arm")
	assert_eq(WeaponInfo.family_label(""), "Bare hands")


# --- A world with a swappable weapon -------------------------------------------------------------------------------

## A world whose inventory holds a dagger, a claw and a knuckle beside the worn creation sword, with a synthetic
## claw-only skill "claw_skill" (canonical weapon 47) and an any-weapon "free_skill" (survivor ["any"]) owned.
func _world(cards: Array = [], learn: bool = true) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.mp = 100
	data.upgrades.cards = cards
	for key: String in ["claw_skill", "free_skill"]:
		data.skills.skills[key] = {"skill_id": 9991000 if key == "claw_skill" else 9991001, "book": "999",
			"kind": "instant", "damage": "fixed", "ranks": [1, 2], "cooldown": 1.0, "range": 400.0,
			"name": key.capitalize(),
			"icon": "Skill.wz/999.img/skill/%d/icon" % (9991000 if key == "claw_skill" else 9991001)}
	data.skills.skills.free_skill.weapon_families = ["any"]
	var setup := RF.setup("quiet", 156, data)
	setup.equipment_info = INFO.duplicate(true)
	setup.skill_imgs["999"] = {"skill": {
		"9991000": {"weapon": 47, "level": {"1": {"fixdamage": 10.0, "mpCon": 5.0}, "2": {"fixdamage": 20.0}}},
		"9991001": {"level": {"1": {"fixdamage": 10.0, "mpCon": 5.0}, "2": {"fixdamage": 20.0}}}}}
	var character := RunWorld.new(setup).character_snapshot()
	for id: int in [1332063, 1472061, 1482000]:
		character.equipment.inventory.append(Equipment.create(id, INFO[id]))
	setup.character = character
	var w := RunWorld.new(setup)
	RF.place_player(w, 200)
	w.loadout.order.clear()
	if learn:
		w.learn_skill("claw_skill")
		w.learn_skill("free_skill")
	w.drain_events()
	return w


## Wears the inventory item `id` (the Equip window's double click); the old weapon goes back to the inventory.
func _wear(w: RunWorld, id: int) -> void:
	for i in w.equipment.inventory.size():
		if int(w.equipment.inventory[i].id) == id:
			assert_eq(w.equip_item(i), "", "wearing %d" % id)
			return
	assert_true(false, "item %d is in the inventory" % id)


func _casts(w: RunWorld) -> Array:
	return w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "cast").map(
		func(e: Dictionary) -> String: return String(e.skill))


# --- Casting ---------------------------------------------------------------------------------------------------------

func test_a_claw_skill_stops_casting_with_the_wrong_weapon_and_resumes_when_it_is_back() -> void:
	var w := _world()
	w.loadout.order.erase("free_skill") # one skill at a time
	RF.put_mob(w, 1110100, 250)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	assert_eq(w.held_weapon_family(), "sword")
	for tick in 90:
		w.runner.step(DT, w)
	assert_eq(_casts(w), [], "a sword is not a claw")
	assert_eq(w.player_state.mp, 100, "and nothing was paid")
	_wear(w, 1472061)
	assert_eq(w.held_weapon_family(), "claw")
	w.runner.step(DT, w)
	assert_eq(_casts(w), ["claw_skill"], "it casts the moment a claw is held (its cooldown ran out meanwhile)")
	assert_eq(w.player_state.mp, 95)
	for tick in 80:
		w.runner.step(DT, w)
	assert_eq(_casts(w), ["claw_skill"], "a second cast once its cooldown (1 s) ran out")
	_wear(w, 1332063) # a dagger replaces the claw
	assert_eq(w.held_weapon_family(), "dagger")
	for tick in 120:
		w.runner.step(DT, w)
	assert_eq(_casts(w), [], "swapped to a dagger: no cast, although the cooldown is over")
	_wear(w, 1472061) # swap back
	w.runner.step(DT, w)
	assert_eq(_casts(w), ["claw_skill"], "swapped back: it resumes")


func test_an_any_weapon_skill_casts_with_every_weapon_and_bare_hands() -> void:
	var w := _world()
	w.loadout.order.erase("claw_skill")
	RF.put_mob(w, 1110100, 250)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	for id: int in [0, 1332063, 1482000]:
		if id > 0:
			_wear(w, id)
		else:
			assert_eq(w.unequip_item("weapon"), "")
			assert_eq(w.held_weapon_family(), "")
		for tick in 50:
			w.runner.step(DT, w)
		assert_eq(_casts(w).size(), 1, "weapon %d" % id)


func test_a_skill_the_weapon_blocks_does_not_hold_back_the_others() -> void:
	var w := _world()
	RF.put_mob(w, 1110100, 250)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	for tick in 5:
		w.runner.step(DT, w)
	assert_eq(_casts(w), ["free_skill"], "the sword casts the any-weapon skill; the claw skill is skipped")


func test_a_blocked_skill_that_was_waiting_for_mp_stops_waiting() -> void:
	var w := _world()
	w.loadout.order.erase("free_skill")
	_wear(w, 1472061)
	RF.put_mob(w, 1110100, 250)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.spend_mp(98)
	w.runner.step(DT, w)
	assert_true(w.runner.is_waiting_mp("claw_skill"), "claw held, 2 MP left: short of the 5 MP cost")
	_wear(w, 1302000)
	w.runner.step(DT, w)
	assert_false(w.runner.is_waiting_mp("claw_skill"), "a sword again: the skill is not even considered")
	assert_false(w.runner.waiting_mp)


# --- Cards -------------------------------------------------------------------------------------------------------------

func _claw_cards() -> Array:
	return [
		{"id": "claw_new", "kind": "skill_new", "skill": "claw_skill", "name": "Claw Skill", "max_rank": 1, "weight": 1.0,
			"effects": []},
		{"id": "claw_rank", "kind": "skill_rank", "skill": "claw_skill", "name": "Claw Rank", "max_rank": 0, "weight": 1.0,
			"effects": [{"stat": "rank", "op": "add", "value": 1}]},
		{"id": "claw_count", "kind": "skill_mod", "skill": "claw_skill", "name": "Claw Count", "max_rank": 3,
			"weight": 1.0, "value": 1, "desc": "+{value}", "effects": [{"stat": "count", "op": "add", "value": 1}]},
		{"id": "free_count", "kind": "skill_mod", "skill": "free_skill", "name": "Free Count", "max_rank": 3,
			"weight": 1.0, "value": 1, "desc": "+{value}", "effects": [{"stat": "count", "op": "add", "value": 1}]},
	]


func _ids(choices: Array) -> Array:
	return choices.map(func(c: Dictionary) -> String: return String(c.id))


func test_claw_cards_are_never_offered_with_a_dagger_and_are_with_a_claw() -> void:
	var w := _world(_claw_cards())
	_wear(w, 1332063)
	assert_eq(w.upgrades.eligible(w), ["free_count"], "only the any-weapon skill's card is eligible")
	for seed_value in 40:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var ids := _ids(w.upgrades.roll_choices(w, rng))
		for id in ["claw_rank", "claw_count"]:
			assert_false(id in ids, "dagger, seed %d: %s" % [seed_value, id])
	_wear(w, 1472061)
	assert_eq(w.upgrades.eligible(w), ["claw_rank", "claw_count", "free_count"], "swapped to a claw before the roll")
	var offered := {}
	for seed_value in 40:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		for id in _ids(w.upgrades.roll_choices(w, rng)):
			offered[id] = true
	assert_true(offered.has("claw_rank") and offered.has("claw_count"), "claw cards are offered with a claw: %s" % offered)


func test_a_skill_new_card_for_a_claw_skill_follows_the_held_weapon_too() -> void:
	var w := _world(_claw_cards(), false)
	_wear(w, 1332063)
	assert_false("claw_new" in w.upgrades.eligible(w), "dagger: the learn card is not offered")
	_wear(w, 1472061)
	assert_true("claw_new" in w.upgrades.eligible(w), "claw: it is")
	_wear(w, 1482000)
	assert_false("claw_new" in w.upgrades.eligible(w), "knuckle: it is not")
	w.unequip_item("weapon")
	assert_false("claw_new" in w.upgrades.eligible(w), "bare hands: it is not")


func test_the_advancement_draw_follows_the_held_weapon() -> void:
	var cards := [
		{"id": "claw_job_new", "kind": "skill_new", "skill": "claw_skill", "name": "Claw Skill", "max_rank": 1,
			"power": true, "weight": 1.0, "requires": {"jobs": [200]}, "effects": []},
		{"id": "free_job_new", "kind": "skill_new", "skill": "free_skill", "name": "Free Skill", "max_rank": 1,
			"power": true, "weight": 1.0, "requires": {"jobs": [200]}, "effects": []},
	]
	var w := _world(cards, false)
	w.change_job(200)
	_wear(w, 1332063)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	assert_eq(_ids(w.upgrades.roll_advancement_choices(w, rng)), ["free_job_new", "elixir"],
		"a dagger: the claw skill is left out of the job draw")
	_wear(w, 1472061)
	rng.seed = 5
	assert_eq(_ids(w.upgrades.roll_advancement_choices(w, rng)), ["claw_job_new", "free_job_new", "elixir"],
		"a claw: both are offered")


# --- The Skill window --------------------------------------------------------------------------------------------------

func _model(w: RunWorld, family: Array) -> SkillWindowModel:
	var jobs := JobTree.from_data({"jobs": [
		{"id": 0, "name": "Beginner", "parent": -1, "tier": 0, "level": 1, "book": "000"},
	]}, {})
	w.book.defs.claw_skill.job = 0
	w.book.defs.free_skill.job = 0
	var pool := UpgradePool.from_data({"cards": [
		{"id": "claw_new", "kind": "skill_new", "skill": "claw_skill", "name": "Claw Skill", "max_rank": 1, "effects": []},
		{"id": "free_new", "kind": "skill_new", "skill": "free_skill", "name": "Free Skill", "max_rank": 1, "effects": []},
	]})
	var text := SkillText.new(w.book, {"9991000": {"name": "Claw Skill", "desc": "Needs a claw."},
		"9991001": {"name": "Free Skill", "desc": "Any weapon."}})
	return SkillWindowModel.new(w.book, pool, w.loadout, jobs, 0, text, func() -> String: return String(family[0]))


func test_the_skill_window_greys_the_skill_the_held_weapon_cannot_use() -> void:
	var w := _world()
	var held := ["sword"]
	var m := _model(w, held)
	assert_false(m.usable("claw_skill"), "a sword cannot use the claw skill")
	assert_true(m.usable("free_skill"))
	held[0] = "claw"
	assert_true(m.usable("claw_skill"), "the window follows the held weapon live")
	var tip := m.skill_tooltip("claw_skill")
	assert_true(tip.usable)
	assert_eq(tip.needs, "Claw", "the tooltip names the weapon it needs")
	held[0] = ""
	tip = m.skill_tooltip("claw_skill")
	assert_false(tip.usable)
	assert_eq(tip.needs, "Claw")
	assert_eq(m.skill_tooltip("free_skill").needs, "", "no requirement, nothing to name")
	var rows: Array = m.tabs[0].rows
	var claw_row: Dictionary = rows.filter(func(r: Dictionary) -> bool: return r.key == "claw_skill")[0]
	assert_eq(claw_row.icon_disabled, "Skill.wz/999.img/skill/9991000/iconDisabled",
		"the row carries the v83 disabled icon the greyed look draws")


func test_the_skill_tooltip_prints_the_needed_weapon_line() -> void:
	var usable := SkillTooltip.layout({"name": "Claw Skill", "desc": "x", "level": 1, "needs": "Claw", "usable": true})
	var blocked := SkillTooltip.layout({"name": "Claw Skill", "desc": "x", "level": 1, "needs": "Claw", "usable": false})
	var none := SkillTooltip.layout({"name": "Free Skill", "desc": "x", "level": 1, "needs": "", "usable": true})
	var texts := func(lines: Array) -> Array:
		return lines.map(func(l: Array) -> String: return String(l[1]))
	assert_true("Weapon : Claw" in texts.call(usable), "the requirement is always shown")
	assert_true("Weapon : Claw (not held)" in texts.call(blocked), "and flagged when the held weapon cannot use it")
	assert_false(texts.call(none).any(func(t: String) -> bool: return t.begins_with("Weapon")))
