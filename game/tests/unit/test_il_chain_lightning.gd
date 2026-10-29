extends TestCase
## Chain Lightning (2221006) as data on the chain cast rule (spec #319, ticket I8 #327): the definition, the link count by
## rank, the hop distance, the boss-first head, the bolt event, one hit per link, its rarity bonuses, and (real cache) the
## mapped WZ levels, the art and the staff that has no stabO2. The rule itself is tested in test_chain_cast.gd. Seeded RNG,
## fixed 1/60 s ticks. Level tables are synthetic: the recorded v83 values at levels 1/4/8/12/15/19/23/27/30.

const IL := preload("res://tests/fixtures/il_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BOLTS := preload("res://tests/unit/test_il_bolts.gd")
const DT := 1.0 / 60.0
const KEY := "chain_lightning"
const MOB := 1110100
const TIERS := ["rare", "epic", "unique", "legendary"]
## mobCount and mad at the mapped WZ levels 4 / 8 / 12 / 15 / 19 / 23 / 27 / 30 (ranks 1..8): recorded from Skill.wz.
const LINKS := [2, 3, 3, 4, 5, 5, 6, 6]
const MAD := [112, 124, 136, 145, 157, 166, 174, 180]


# --- fixtures ---------------------------------------------------------------------------------------------------------

## A fresh I/L round (Cold Beam and Teleport learned) with the synthetic 222 book.
func _round() -> RunWorld:
	var setup := RF.setup("quiet", 327, IL.data())
	setup.job = 222
	setup.skill_imgs["222"] = {"skill": {"2221006": IL.chain_node()}}
	var w := RunWorld.new(setup)
	RF.place_player(w, 200)
	w.drain_events()
	return w


## The round with only Chain Lightning learned, at `rank`.
func _world(rank := 8) -> RunWorld:
	var w := _round()
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	w.learn_skill(KEY)
	w.loadout.set_rank(KEY, rank)
	w.loadout.set_caster(100.0, 0.0, 30)
	w.god = true
	w.drain_events()
	return w


func _mob(w: RunWorld, px: float) -> int:
	var m := RF.put_mob(w, MOB, px, 195, 100000.0)
	w.swarm.hp[m] = 100000
	w.swarm.max_hp[m] = 100000
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m


func _cast(w: RunWorld) -> Array:
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()
	w.runner.step(DT, w)
	return w.drain_events()


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


## A row of `n` monsters 80 px apart starting 150 px in front of the caster.
func _row(w: RunWorld, n: int, gap := 80.0) -> Array:
	var out := []
	for i in n:
		out.append(_mob(w, 350.0 + gap * i))
	return out


# --- the definition ---------------------------------------------------------------------------------------------------

func test_chain_lightning_lives_in_the_il_line_and_follows_the_pool_rules() -> void:
	assert_true(IL.skill_file("il_arch_mage").has(KEY), "skills/il_arch_mage.json")
	assert_false(IL.skill_file("magician").has(KEY))
	var d: Dictionary = DataRepo.load_all().skills.skills[KEY]
	assert_eq([int(d.skill_id), d.book, int(d.job), d.kind, d.slot], [2221006, "222", 222, "instant", "active"])
	assert_eq(d.damage, "magic")
	assert_eq(String(d.cast.rule), "chain")
	assert_eq([float(d.cast.acquire), float(d.cast.hop), int(d.cast.min_targets)], [450.0, 200.0, 1])
	assert_near(float(d.cooldown), 1.6, 1e-9, "4 s x0.4 (spec: slightly slower than Paralyze for six targets)")
	assert_eq(d.action, "chainlightning")
	assert_near(float(d.action_time), 0.8, 1e-9)
	assert_false(d.has("ranks"), "the default 30-level table")
	assert_false(d.has("weapon_families"))
	assert_false(d.has("range"), "acquire is the range (Loadout falls back to cast.acquire)")
	assert_false(d.has("on_hit"), "Chain Lightning has no status")
	assert_eq(d.chain.ball, ["Skill.wz/222.img/skill/2221006/ball/0", "Skill.wz/222.img/skill/2221006/ball/1",
		"Skill.wz/222.img/skill/2221006/ball/2"])
	assert_eq(d.hit, "Skill.wz/222.img/skill/2221006/hit/0")
	assert_eq(d.effect, "Skill.wz/222.img/skill/2221006/effect")
	assert_eq(d.icon, "Skill.wz/222.img/skill/2221006/icon")
	assert_eq(d.sounds, {"use": "Sound.wz/Skill.img/2221006/Use", "hit": "Sound.wz/Skill.img/2221006/Hit"})
	var job: Dictionary = DataRepo.load_all().jobs_survivor.jobs["222"]
	assert_true(KEY in job.skill_pool, "in the 222 pool")


func test_no_standalone_card_exists_for_chain_lightning() -> void:
	for c: Dictionary in DataRepo.load_all().upgrades.cards:
		assert_false(String(c.id).begins_with("chain_lightning_") and String(c.get("kind", "")) == "skill_mod", String(c.id))


# --- the cast ---------------------------------------------------------------------------------------------------------

func test_the_chain_is_two_three_three_four_five_five_six_six_links_by_rank() -> void:
	for rank in range(1, 9):
		var w := _world(rank)
		var row := _row(w, 8)
		var events := _cast(w)
		var struck := _of(events, "mob_hit").map(func(e: Dictionary) -> int: return int(e.mob))
		assert_eq(struck, row.slice(0, LINKS[rank - 1]), "rank %d strikes the first %d of the row, in order" % [rank, LINKS[rank - 1]])
		assert_eq((_of(events, "skill_chain")[0].points as PackedVector2Array).size(), LINKS[rank - 1] + 1, "hand + links")


func test_one_hit_per_link_with_the_rank_s_damage_unchanged_along_the_chain() -> void:
	var w := _world(1)
	_row(w, 4)
	var hits := _of(_cast(w), "mob_hit")
	assert_eq(hits.size(), 2, "one resolved hit per link, one line each")
	var floor_damage := 0.0
	for h: Dictionary in hits:
		assert_eq(String(h.skill), KEY)
		assert_eq(String(h.hit_visual), "Skill.wz/222.img/skill/2221006/hit/0", "the hit burst on every link")
		floor_damage = maxf(floor_damage, float(h.damage))
	var strong := _world(8)
	_row(strong, 4)
	var strong_hits := _of(_cast(strong), "mob_hit")
	assert_true(float(strong_hits[0].damage) > floor_damage, "rank 8 (mad 180) hits harder than rank 1 (mad 112)")
	assert_true(float(strong_hits[3].damage) <= float(strong_hits[0].damage) * 2.0, "no falloff to the last link")


func test_the_hop_is_200_px_between_body_centres() -> void:
	var w := _world()
	var a := _mob(w, 350)
	var b := _mob(w, 350 + 190)
	_mob(w, 350 + 190 + 215)
	assert_eq(_of(_cast(w), "mob_hit").map(func(e: Dictionary) -> int: return int(e.mob)), [a, b], "190 px hops, 215 px does not")


func test_the_head_is_acquired_within_450_px_and_a_scheduled_boss_comes_first() -> void:
	var w := _world()
	_mob(w, 200 + 480)
	assert_true(_of(_cast(w), "mob_hit").is_empty(), "480 px is outside acquire")
	var near := _mob(w, 200 + 290)
	var boss := _mob(w, 200 + 440)
	w.mob_boss[boss] = 0
	var struck := _of(_cast(w), "mob_hit").map(func(e: Dictionary) -> int: return int(e.mob))
	assert_eq(struck[0], boss, "a scheduled boss in acquire is the head")
	assert_true(near in struck, "and the chain continues to the nearest unhit monster")


func test_the_bolt_event_lists_the_hand_then_each_link_centre_after_the_cast_event() -> void:
	var w := _world(8)
	var row := _row(w, 3)
	var events := _cast(w)
	var chain := _of(events, "skill_chain")
	assert_eq(chain.size(), 1)
	var points: PackedVector2Array = chain[0].points
	assert_eq(points.size(), 4)
	assert_eq(points[0], w.shot_origin(w.mob_center(row[0])))
	for i in 3:
		assert_eq(points[i + 1], w.mob_center(row[i]))
	assert_eq(int(chain[0].skill_id), 2221006)
	var types := events.map(func(e: Dictionary) -> String: return e.type)
	assert_true(types.find("cast") < types.find("skill_chain") and types.find("skill_chain") < types.find("mob_hit"))
	var cast: Dictionary = _of(events, "cast")[0]
	assert_eq(String(cast.action), "chainlightning")
	assert_eq(String(cast.effect), "Skill.wz/222.img/skill/2221006/effect", "the 12-frame effect at the caster")


func test_the_cooldown_is_1_6_seconds() -> void:
	var w := _world(8)
	_row(w, 3)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	var casts := 0
	for t in int(5.0 / DT):
		w.step(DT, MoveInput.new())
		for s in w.swarm.x.size():
			if w.swarm.active[s] != 0:
				w.swarm.hp[s] = w.swarm.max_hp[s]
		casts = w.runner.casts
	assert_true(casts >= 3 and casts <= 4, "about 5 s / 1.6 s casts: %d" % casts)


# --- rarity bonuses ---------------------------------------------------------------------------------------------------

const BONUSES := {
	"rare": ["amplify", "damage", "mul", 1.2],
	"epic": ["conduct", "area", "mul", 1.2],
	"unique": ["fork", "count", "add", 1.0],
	"legendary": ["fork", "count", "add", 1.0],
}


func test_the_four_rarity_lists_name_the_spec_entries() -> void:
	var b: Dictionary = DataRepo.load_all().skills.skills[KEY].rarity_bonuses
	for tier: String in TIERS:
		assert_eq(b[tier].size(), 1, tier)
		assert_eq(b[tier][0].id, BONUSES[tier][0], "%s id" % tier)
		assert_eq(b[tier][0].effects[0], {"stat": BONUSES[tier][1], "op": BONUSES[tier][2], "value": BONUSES[tier][3]}, tier)
	assert_eq(b.rare[0].text, "Element Amplification")
	assert_eq(b.epic[0].text, "Conductor")
	assert_eq(b.unique[0].text, "Longer Chain")
	assert_eq(b.legendary[0].effects.size(), 2)
	assert_eq(b.legendary[0].effects[1], {"stat": "damage", "op": "mul", "value": 1.2}, "Legendary = Unique plus damage")


func test_conductor_widens_the_hop_and_longer_chain_adds_a_link() -> void:
	var gap := 230.0 # beyond the base hop of 200, inside 200 x 1.2
	var base := _world()
	_row(base, 2, gap)
	assert_eq(_of(_cast(base), "mob_hit").size(), 1, "the second monster is out of hop")
	var wide := _world()
	wide.loadout.add_skill_mod(KEY, "area", "mul", 1.2)
	_row(wide, 2, gap)
	assert_eq(_of(_cast(wide), "mob_hit").size(), 2, "area x1.2 makes the hop 240 px")
	var longer := _world(8)
	longer.loadout.add_skill_mod(KEY, "count", "add", 1.0)
	_row(longer, 9)
	assert_eq(_of(_cast(longer), "mob_hit").size(), 7, "rank 8 chain of 6 plus one")


func test_a_rare_plus_card_adds_one_rank_plus_its_bonus_and_legendary_shares_the_unique_counter() -> void:
	for tier: String in TIERS:
		var w := _round()
		var offered := w.upgrades.choice_card(KEY + "_new", w, tier)
		assert_false(offered.get("rarity_bonus", {}).is_empty(), "%s offers a bonus" % tier)
		assert_false(offered.skill_mod_changes.is_empty(), "%s previews the change" % tier)
		w.upgrades.apply(KEY + "_new", w, tier)
		assert_true(w.loadout.has(KEY))
		assert_false(w.loadout.skill_mods.get(KEY, {}).is_empty(), "%s applied the bonus" % tier)
	var w := _round()
	w.upgrades.apply(KEY + "_new", w, "unique")
	w.upgrades.apply(KEY + "_rank", w, "legendary")
	assert_eq(int(w.loadout.card_ranks["bonus:%s:fork" % KEY]), 2, "one counter for Unique and Legendary")
	assert_eq(w.loadout.rank(KEY), 2, "each card added exactly one rank")


func test_mastery_repeats_shrink_by_0_8() -> void:
	var w := _round()
	w.learn_skill(KEY)
	w.loadout.set_rank(KEY, 8)
	var mastery := w.upgrades.choice_card(KEY + "_rank", w, "rare")
	assert_eq(mastery.card_kind, "mastery")
	var first := w.loadout.skill_stat(KEY, "damage", 1.0)
	w.upgrades.apply(KEY + "_rank", w, "rare")
	var after_one := w.loadout.skill_stat(KEY, "damage", 1.0)
	w.upgrades.apply(KEY + "_rank", w, "rare")
	var after_two := w.loadout.skill_stat(KEY, "damage", 1.0)
	assert_near(after_one / first, 1.2, 1e-6)
	assert_near(after_two / after_one, 1.0 + 0.2 * 0.8, 1e-6)


func test_the_card_text_states_the_chain() -> void:
	var w := _world(1)
	var text := SkillText.new(w.book, {})
	assert_eq(text.level_line(KEY, 4, w.loadout.stats(KEY, 1)),
		"Basic attack 112, mastery 20%, up to 2 monsters\nJumps to up to 2 monsters within 200 px")
	assert_ne(text.desc(KEY), "")


# --- real cache -------------------------------------------------------------------------------------------------------

func _real_book(lib: AssetLibrary) -> SkillBook:
	var imgs := {}
	for b: String in ["220", "221", "222"]:
		imgs[b] = lib.img("Skill.wz/%s.img" % b).root
	return SkillBook.from_data(DataRepo.load_all().skills, imgs)


func test_real_cache_the_eight_ranks_map_to_the_wz_levels_and_the_art_resolves() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	if lib.img("Skill.wz/222.img") == null:
		skip("the cache predates the I/L manifest fragment (no Skill.wz/222.img)")
		lib.free()
		return
	var book := _real_book(lib)
	assert_eq(book.max_level(KEY), 30)
	assert_eq(book.max_rank(KEY), 8)
	for rank in range(1, 9):
		var level := book.canonical_level(KEY, rank)
		assert_eq(level, BOLTS.RANK_LEVELS[rank - 1], "rank %d level" % rank)
		assert_eq(int(book.canonical(KEY, level, "mad")), MAD[rank - 1], "rank %d mad" % rank)
		assert_eq(int(book.canonical(KEY, level, "mobCount")), LINKS[rank - 1], "rank %d links" % rank)
		var node := book.level_node(KEY, level)
		assert_false(node.has("lt") or node.has("range") or node.has("prop"), "the WZ node has no box, range or prop")
	assert_eq([int(book.canonical(KEY, 4, "mastery")), int(book.canonical(KEY, 30, "mastery"))], [2, 10])
	for variant in 3:
		var ball := lib.anim("Skill.wz/222.img/skill/2221006/ball/%d" % variant)
		assert_true(ball != null and not ball.is_empty(), "ball/%d" % variant)
	for path: String in book.def(KEY).chain.ball:
		assert_true(lib.anim(path) != null, path)
	assert_true(lib.frame(String(book.def(KEY).icon)) != null, "icon")
	for field: String in ["hit", "effect"]:
		assert_true(lib.anim(book.visual(KEY, field, 30, 30)) != null, "%s art" % field)
	for snd: String in ["use", "hit"]:
		assert_true(lib.sound(String(book.def(KEY).sounds[snd])) != null, "%s sound" % snd)
	assert_true(lib.missing.is_empty(), str(lib.missing))
	lib.free()


func test_real_cache_a_staff_without_stabO2_keeps_its_weapon_in_both_chainlightning_frames() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	if lib.img("Character.wz/Weapon/01382000.img") == null:
		skip("no staff 1382000 in the cache")
		return
	assert_false(AvatarLayers.has_art(lib.img("Character.wz/Weapon/01382000.img"), "stabO2"), "premise: staff 1382000 has no stabO2")
	var avatar := AvatarRenderer.new()
	avatar.library = lib
	for weapon: int in [1382000, 1372005]:
		avatar.set_look({"equips": [1040002, 1060002, 1072001, weapon]})
		for index in 2:
			var owned := avatar.compose("chainlightning", index).filter(
				func(p: Dictionary) -> bool: return int(p.get("owner", 0)) == weapon)
			assert_false(owned.is_empty(), "%d is drawn at chainlightning frame %d" % [weapon, index])
	avatar.free()
