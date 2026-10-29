extends TestCase
## The Bishop's core bolts (spec #372, ticket BS5 #377): Holy Arrow and Teleport (moved out of magician.json into the bishop
## line), Shining Ray and Angel Ray (new). Seeded RNG, fixed 1/60 s ticks. Level tables are synthetic (bishop_bolt_fixtures.gd:
## the recorded v83 values at the eight ranks); the real-cache tests (require_cache(), SKIP without it) read Skill.wz itself.
## That every rarity entry changes the resolved cast is audited with the other lines in test_rarity_bonus_effects.

const BF := preload("res://tests/fixtures/bishop_bolt_fixtures.gd")
const IL := preload("res://tests/fixtures/il_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const KEYS := ["holy_arrow", "shining_ray", "angel_ray"]
const TIERS := ["rare", "epic", "unique", "legendary"]


# --- fixtures ---------------------------------------------------------------------------------------------------------


## The same round with only `key` learned, at `rank`, for a cast test.
func _alone(key: String, rank := 1) -> RunWorld:
	var w := BF.round_world()
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	w.learn_skill(key)
	w.loadout.set_rank(key, rank)
	w.loadout.set_caster(100.0, 0.0, 30)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
	w.drain_events()
	return w


func _cast(w: RunWorld) -> Array:
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()
	w.runner.step(DT, w)
	return w.drain_events()


## Casts, then flies the projectiles for a second and returns every event.
func _fly(w: RunWorld) -> Array:
	var events := _cast(w)
	for tick in 60:
		w.projectiles.step(DT, w.swarm, w.mob_grid, w.events)
	events.append_array(w.drain_events())
	return events


func _hits(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")


func _hit_mobs(events: Array) -> Dictionary:
	var out := {}
	for e: Dictionary in _hits(events):
		out[int(e.mob)] = true
	return out


func _mob_at(w: RunWorld, dx: float, dy := 0.0) -> int:
	return w.spawn_mob(int(w.kind_of_id[MOB]), w.player.pos + Vector2(dx, dy), w.player.fh, 100000.0, false)


# --- the line ---------------------------------------------------------------------------------------------------------


func test_the_four_skills_live_in_the_bishop_line_and_not_in_magician_json() -> void:
	var bishop := IL.skill_file("bishop")
	var magician := IL.skill_file("magician")
	for key: String in KEYS + ["teleport_cleric"]:
		assert_true(bishop.has(key), "%s is in skills/bishop.json" % key)
		assert_false(magician.has(key), "%s left skills/magician.json (a key in two files is a load error)" % key)
	for key: String in ["energy_bolt", "magic_claw", "heal", "bless", "invincible"]:
		assert_true(magician.has(key), "%s stays in magician.json (Heal is BS4's)" % key)
	var skills: Dictionary = DataRepo.load_all().skills.skills
	assert_eq([int(skills.holy_arrow.skill_id), int(skills.shining_ray.skill_id), int(skills.angel_ray.skill_id),
		int(skills.teleport_cleric.skill_id)], [2301005, 2311004, 2321007, 2301001])
	assert_eq([skills.holy_arrow.book, skills.shining_ray.book, skills.angel_ray.book], ["230", "231", "232"])
	assert_eq([int(skills.holy_arrow.job), int(skills.shining_ray.job), int(skills.angel_ray.job)], [230, 231, 232])


func test_definitions_follow_the_pool_rules() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	var want := {"holy_arrow": 0.4, "shining_ray": 1.2, "angel_ray": 1.0}
	for key: String in want:
		var d: Dictionary = skills[key]
		assert_eq(String(d.slot), "active", "%s: an explicit active slot" % key)
		assert_near(float(d.cooldown), want[key], 1e-9, "%s: first-pass cooldown (base x0.4)" % key)
		assert_false(d.has("ranks"), "%s: the default 30-level table" % key)
		assert_false(d.has("weapon_families"), key)
		assert_eq(String(d.damage), "magic", key)
		assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/%d/Use" % int(d.skill_id), "%s: its own Use sound" % key)
	for key: String in ["holy_arrow", "angel_ray"]:
		var d: Dictionary = skills[key]
		assert_eq(String(d.kind), "projectile", key)
		assert_eq([int(d.range), int(d.speed), int(d.count), int(d.pierce)], [480, 520, 1, 0], "%s: the Fire Arrow flight" % key)
		assert_eq(d.action, "shoot1", key)
		assert_true(bool(d.rotate), key)
	assert_eq(skills.holy_arrow.radius, 12)
	assert_eq(skills.angel_ray.radius, 14)
	assert_eq(skills.holy_arrow.ball, "Skill.wz/230.img/skill/2301005/ball")
	assert_eq(skills.angel_ray.ball, "Skill.wz/232.img/skill/2321007/ball/0", "its own single-frame ball")
	assert_eq(skills.holy_arrow.hit, "Skill.wz/230.img/skill/2301005/hit/0")
	assert_eq(skills.angel_ray.effect, "Skill.wz/232.img/skill/2321007/effect")
	assert_eq(skills.shining_ray.kind, "instant")
	assert_eq(skills.shining_ray.cast.rule, "box")
	assert_eq(int(skills.shining_ray.cast.get("min_targets", 1)), 1)
	assert_eq(skills.shining_ray.action, "magic2")
	assert_eq(skills.shining_ray.ball, "", "no ball")
	assert_eq(skills.shining_ray.hit, "Skill.wz/231.img/skill/2311004/hit/0")
	assert_eq(skills.shining_ray.effect, "Skill.wz/231.img/skill/2311004/effect")


func test_the_legacy_holy_arrow_cards_are_gone_and_new_and_rank_cards_are_generated() -> void:
	for c: Dictionary in DataRepo.load_all().upgrades.cards:
		for prefix: String in ["holy_arrow_", "shining_ray_", "angel_ray_"]:
			assert_false(String(c.id).begins_with(prefix) and String(c.get("kind", "")) == "skill_mod",
				"%s: ported skills carry no standalone mod cards" % c.id)
	var ids: Array = DataRepo.load_all().upgrades.cards.map(func(c: Dictionary) -> String: return String(c.id))
	for id: String in ["holy_arrow_new", "holy_arrow_rank", "holy_arrow_count", "holy_arrow_pierce", "holy_arrow_cooldown"]:
		assert_false(id in ids, "%s is not a data card any more" % id)
	var w := BF.round_world()
	assert_eq(w.upgrades.card("shining_ray_new").get("kind"), "skill_new", "new and rank cards are generated from the pool")
	assert_eq(w.upgrades.card("angel_ray_rank").get("kind"), "skill_rank")
	assert_eq(w.upgrades.card("holy_arrow_rank").get("kind"), "skill_rank")


# --- Holy Arrow -------------------------------------------------------------------------------------------------------


func test_holy_arrow_casts_every_0_4_seconds_with_the_mapped_damage_and_the_holy_element() -> void:
	var w := _alone("holy_arrow", 8)
	var st := w.loadout.stats("holy_arrow")
	assert_eq([st.level, st.element, st.kind, st.count, st.pierce, st.range, st.speed], [30, "h", "projectile", 1, 0, 480.0, 520.0])
	assert_near(st.cooldown, 0.4, 1e-9)
	var low := _alone("holy_arrow", 1).loadout.stats("holy_arrow")
	assert_eq(low.level, 4, "rank 1 is WZ level 4")
	# mad 80 against 28: the damage ranges follow the mapped mad.
	assert_true(st.damage_max > low.damage_max * 2.0, "mad 28 -> 80: %s -> %s" % [low.damage_max, st.damage_max])
	var m := _mob_at(w, 300)
	w.swarm.hp[m] = 1.0e9
	w.swarm.max_hp[m] = 1.0e9
	var casts := 0
	for tick in 150: # 2.5 s
		w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
		w.step(DT, MoveInput.new())
		casts = w.runner.casts
		w.drain_events()
	# Cast at t = 0, 0.4, 0.8, 1.2, 1.6, 2.0, 2.4 (the first tick is the first cast).
	assert_true(casts >= 6 and casts <= 7, "one cast every 0.4 s over 2.5 s: %d" % casts)


func test_holy_arrow_range_is_480_px_and_count_and_pierce_come_from_the_bonuses() -> void:
	var w := _alone("holy_arrow")
	_mob_at(w, 500)
	assert_eq(_hits(_fly(w)).size(), 0, "beyond 480 px nothing is cast")
	var one := _alone("holy_arrow")
	_mob_at(one, 100)
	_mob_at(one, 200)
	_mob_at(one, 300)
	assert_eq(_hit_mobs(_fly(one)).size(), 1, "one arrow, no pierce: one monster")
	var piercing := _alone("holy_arrow")
	for mk: MobKind in piercing.mob_kinds:
		mk.hitbox = Rect2(-20, -80, 40, 80) # tall enough that the arrow's slanted line crosses all three
	piercing.loadout.add_skill_mod("holy_arrow", "pierce", "add", 1.0)
	_mob_at(piercing, 100)
	_mob_at(piercing, 200)
	_mob_at(piercing, 300)
	assert_eq(_hit_mobs(_fly(piercing)).size(), 2, "pierce +1: two monsters on the line")
	var twin := _alone("holy_arrow")
	twin.loadout.add_skill_mod("holy_arrow", "count", "add", 1.0)
	_mob_at(twin, 100)
	_mob_at(twin, -150)
	assert_eq(_hit_mobs(_fly(twin)).size(), 2, "count +1: a second arrow at the next target")


# --- Shining Ray ------------------------------------------------------------------------------------------------------


func test_shining_ray_box_steps_up_at_rank_3_and_admits_only_box_targets() -> void:
	for rank in range(1, 9):
		var st := _alone("shining_ray", rank).loadout.stats("shining_ray")
		var half: float = BF.RAY_HALF_WIDTH[rank - 1]
		assert_eq(st.level, BF.RANK_LEVELS[rank - 1])
		assert_true((st.box as Rect2).is_equal_approx(Rect2(-half, -50, 2.0 * half, 100)), "rank %d box %s" % [rank, st.box])
		assert_eq([st.cast_rule, st.mob_count, st.element], ["box", 6, "h"])
		assert_near(st.cooldown, 1.2, 1e-9)
	var narrow := _alone("shining_ray", 2) # WZ level 8: half-width 150
	_mob_at(narrow, 155)
	assert_eq(_hits(_cast(narrow)).size(), 0, "155 px is outside the level-8 box")
	var wide := _alone("shining_ray", 3) # WZ level 12: half-width 160
	_mob_at(wide, 155)
	assert_eq(_hits(_cast(wide)).size(), 1, "and inside the level-12 one")


func test_shining_ray_is_centred_on_the_caster_and_hits_at_most_six_with_count_adding_targets() -> void:
	for extra: int in [0, 2]:
		var w := _alone("shining_ray", 8)
		w.loadout.add_skill_mod("shining_ray", "count", "add", float(extra))
		for i in 12:
			_mob_at(w, (i + 1) * 10 * (1 if i % 2 == 0 else -1))
		assert_eq(_hit_mobs(_cast(w)).size(), 6 + extra, "mobCount 6 + count %d" % extra)
	var left := _alone("shining_ray")
	_mob_at(left, -140)
	assert_eq(_hits(_cast(left)).size(), 1, "the box reaches behind the caster as far as in front")


# --- Angel Ray --------------------------------------------------------------------------------------------------------


func test_angel_ray_fires_one_ball_at_the_nearest_target_with_its_own_art() -> void:
	var w := _alone("angel_ray", 8)
	var st := w.loadout.stats("angel_ray")
	assert_eq([st.level, st.element, st.kind, st.count, st.pierce, st.range, st.speed, st.radius],
		[30, "h", "projectile", 1, 0, 480.0, 520.0, 14.0])
	assert_near(st.cooldown, 1.0, 1e-9)
	var near := _mob_at(w, 150)
	_mob_at(w, 250)
	_mob_at(w, -300)
	var events := _cast(w)
	assert_eq(w.projectiles.active_count(), 1, "one ball")
	for tick in 40:
		w.projectiles.step(DT, w.swarm, w.mob_grid, w.events)
	events.append_array(w.drain_events())
	assert_eq(_hit_mobs(events).keys(), [near], "the nearest alone")
	assert_eq(String(w.book.def("angel_ray").ball), "Skill.wz/232.img/skill/2321007/ball/0")
	var heavy := _alone("angel_ray", 8).loadout.stats("angel_ray")
	var light := _alone("holy_arrow", 8).loadout.stats("holy_arrow")
	assert_true(heavy.damage_max > light.damage_max * 2.5, "mad 240 against 80 at the top rank")


func test_angel_ray_range_is_480_px_and_count_adds_a_shot() -> void:
	var w := _alone("angel_ray")
	_mob_at(w, 500)
	assert_eq(_hits(_fly(w)).size(), 0)
	var twin := _alone("angel_ray")
	twin.loadout.add_skill_mod("angel_ray", "count", "add", 1.0)
	_mob_at(twin, 100)
	_mob_at(twin, -150)
	_cast(twin)
	assert_eq(twin.projectiles.active_count(), 2, "two shots")


# --- Teleport ---------------------------------------------------------------------------------------------------------


func test_teleport_cleric_is_the_mobility_skill_outside_both_slot_tracks() -> void:
	var skills: Dictionary = SkillBook.from_data(DataRepo.load_all().skills, {}).defs
	assert_eq(skills.teleport_cleric.slot, "mobility")
	assert_eq(skills.teleport_cleric.skill_key, "teleport")
	assert_eq(skills.teleport_cleric.cast.rule, "manual")
	assert_eq(skills.teleport_cleric.skill_id, 2301001)
	assert_eq(skills.teleport_cleric.sounds.use, "Sound.wz/Skill.img/2301001/Use")
	assert_eq(skills.teleport_cleric.teleport, skills.teleport_fp.teleport, "the same 0.3 s repeat and bot threat distance")
	assert_eq(skills.teleport_cleric.ranks, skills.teleport_fp.ranks, "the same 20 ranks")
	assert_eq(skills.teleport_cleric.effect, "Effect.wz/BasicEff.img/Teleport")
	var w := BF.round_world()
	assert_eq(w.jobs.mobility_skill(232), "teleport_cleric")
	assert_true(w.loadout.has("teleport_cleric"), "learned at round start")
	assert_eq(w.loadout.rank("teleport_cleric"), 1)
	assert_eq(w.teleport_skill(), "teleport_cleric", "Key Config's Teleport action and the HUD cell find it")
	assert_false("teleport_cleric" in w.jobs.skill_pool(232), "not a pool entry")
	for c: Dictionary in w.upgrades.cards:
		assert_ne(String(c.get("skill", "")), "teleport_cleric", "%s: Teleport is never offered as a card" % c.id)
	assert_false("teleport_cleric_new" in w.upgrades.eligible(w) or "teleport_cleric_rank" in w.upgrades.eligible(w))
	assert_eq(w.loadout.slot_count("active"), 1, "Holy Arrow alone occupies a slot; Teleport consumes none")
	assert_eq(float(w.skill_readiness("teleport_cleric").left), 0.0, "the HUD cell reads its readiness")


func test_teleport_cleric_blinks_exactly_like_the_fp_one() -> void:
	var landed := {}
	for job: int in [212, 232]:
		var data := RF.quiet_data()
		var setup := BF.setup(data) if job == 232 else RF.setup("quiet", 60, data)
		setup.job = job
		setup.map_img = RF.map_from_segments([{"x1": 0, "y1": 0, "x2": 1000, "y2": 0}])
		var w := RunWorld.new(setup)
		w.player.place(Vector2(400, 0), w.fhm)
		w.loadout.set_rank(w.jobs.mobility_skill(job), 20)
		var input := MoveInput.new()
		input.press_skill("teleport")
		w.step(DT, input)
		landed[job] = w.player.pos
	assert_eq(landed[232], landed[212], "the same distance")
	assert_ne(landed[232], Vector2(400, 0))


func test_teleport_cleric_rank_follows_mobility_rank_levels() -> void:
	var w := BF.round_world()
	assert_eq(w.loadout.rank("teleport_cleric"), 1)
	var table: Dictionary = w.balance.mobility_rank_levels
	assert_eq(table["20"], 10, "the shared rule: rank N at character level 2N")
	for step in range(2, 41):
		w.pickups.spawn(w.player.pos, w.progression.exp_to_next(), 4000019)
		w.step(DT, MoveInput.new())
		while w.state == RunWorld.CHOOSING_UPGRADE:
			w.apply_choice(String(w.pending_cards[0].id))
		var level := w.progression.level
		assert_eq(w.loadout.rank("teleport_cleric"), clampi(level / 2, 1, 20), "level %d" % level)
	assert_true(w.progression.level >= 40, "the loop reached the cap level")
	assert_eq(w.loadout.rank("teleport_cleric"), 20)
	assert_false("teleport_cleric_rank" in w.upgrades.eligible(w))


# --- rarity: every entry changes the cast (see also test_rarity_bonus_effects) -----------------------------------------------

## [id, stat] per tier (Legendary repeats the Unique's id and effect, plus damage x1.2).
const BONUSES := {
	"holy_arrow": {"rare": ["power", "damage"], "epic": ["pierce", "pierce"], "unique": ["twin", "count"],
		"legendary": ["twin", "count"]},
	"shining_ray": {"rare": ["power", "damage"], "epic": ["radiance", "area"], "unique": ["fork", "count"],
		"legendary": ["fork", "count"]},
	"angel_ray": {"rare": ["power", "damage"], "epic": ["booster", "cooldown"], "unique": ["twin", "count"],
		"legendary": ["twin", "count"]},
}


func test_the_four_rarity_lists_name_the_spec_entries() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	for key: String in BONUSES:
		for tier: String in TIERS:
			var entries: Array = skills[key].rarity_bonuses[tier]
			assert_eq(entries.size(), 1, "%s %s" % [key, tier])
			assert_eq(entries[0].id, BONUSES[key][tier][0], "%s %s id" % [key, tier])
			assert_eq(entries[0].effects[0].stat, BONUSES[key][tier][1], "%s %s stat" % [key, tier])
		var unique: Dictionary = skills[key].rarity_bonuses.unique[0]
		var legendary: Dictionary = skills[key].rarity_bonuses.legendary[0]
		assert_eq(legendary.id, unique.id, "%s: Legendary shares the Unique's counter" % key)
		assert_eq(legendary.effects.size(), 2)
		assert_eq(legendary.effects[0], unique.effects[0], "%s: Legendary = Unique plus damage" % key)
		assert_eq(legendary.effects[1], {"stat": "damage", "op": "mul", "value": 1.2})
		assert_eq(skills[key].rarity_bonuses.rare[0].effects[0].value, 1.2)
	assert_eq(skills.holy_arrow.rarity_bonuses.epic[0].effects[0].value, 1, "Piercing Light: +1 pierce")
	assert_eq(skills.holy_arrow.rarity_bonuses.unique[0].text, "Twin Arrow")
	assert_eq(skills.shining_ray.rarity_bonuses.epic[0].effects[0].value, 1.2, "Wider Ray: area x1.2")
	assert_eq(skills.shining_ray.rarity_bonuses.unique[0].effects[0].value, 2, "Splitting Ray: +2 targets")
	assert_eq(skills.angel_ray.rarity_bonuses.epic[0].effects[0].value, 0.88, "Spell Booster: cooldown x0.88")
	assert_eq(skills.angel_ray.rarity_bonuses.unique[0].effects[0].value, 1, "Twin Angel: +1 shot")


func test_each_bonus_changes_the_stats_the_cast_reads() -> void:
	# Direct reading of the resolved stats; the audit in test_rarity_bonus_effects shows the same through whole casts.
	var skills: Dictionary = DataRepo.load_all().skills.skills
	for key: String in KEYS:
		var base := _alone(key, 8).loadout.stats(key)
		for tier: String in TIERS:
			var w := _alone(key, 8)
			for effect: Dictionary in skills[key].rarity_bonuses[tier][0].effects:
				w.loadout.add_skill_mod(key, String(effect.stat), String(effect.op), float(effect.value))
			var st := w.loadout.stats(key)
			match String(BONUSES[key][tier][1]):
				"damage":
					assert_true(st.damage_max > base.damage_max, "%s %s: damage" % [key, tier])
				"pierce":
					assert_eq(st.pierce, base.pierce + 1, "%s %s: pierce" % [key, tier])
				"cooldown":
					assert_near(st.cooldown, base.cooldown * 0.88, 1e-6, "%s %s: cooldown" % [key, tier])
				"area":
					assert_true((st.box as Rect2).size.x > (base.box as Rect2).size.x, "%s %s: area" % [key, tier])
				"count":
					var added := 2 if key == "shining_ray" else 1
					assert_eq(st.mob_count if key == "shining_ray" else st.count, (base.mob_count if key == "shining_ray" else base.count) + added,
						"%s %s: count" % [key, tier])


func test_a_rare_plus_card_adds_one_rank_plus_its_bonus_and_legendary_shares_the_unique_counter() -> void:
	for key: String in KEYS:
		for tier: String in TIERS:
			var w := BF.round_world()
			var id := key + ("_rank" if w.loadout.has(key) else "_new")
			var offered := w.upgrades.choice_card(id, w, tier)
			assert_false(offered.get("rarity_bonus", {}).is_empty(), "%s %s offers a bonus" % [key, tier])
			assert_false(offered.skill_mod_changes.is_empty(), "%s %s previews the change" % [key, tier])
			w.upgrades.apply(id, w, tier)
			assert_true(w.loadout.has(key))
			assert_false(w.loadout.skill_mods.get(key, {}).is_empty(), "%s %s applied the bonus" % [key, tier])
		var w := BF.round_world()
		w.upgrades.apply(key + ("_rank" if w.loadout.has(key) else "_new"), w, "unique")
		w.upgrades.apply(key + "_rank", w, "legendary")
		var unique_id: String = BONUSES[key].unique[0]
		assert_eq(int(w.loadout.card_ranks["bonus:%s:%s" % [key, unique_id]]), 2, "%s: one counter for Unique and Legendary" % key)
		assert_eq(w.loadout.rank(key), 3 if key == "holy_arrow" else 2, "%s: each card added exactly one rank" % key)


func test_mastery_repeats_shrink_by_0_8_on_every_bolt() -> void:
	for key: String in KEYS:
		var w := BF.round_world()
		w.learn_skill(key)
		w.loadout.set_rank(key, 8)
		var mastery := w.upgrades.choice_card(key + "_rank", w, "rare")
		assert_eq(mastery.card_kind, "mastery", key)
		var first := w.loadout.skill_stat(key, "damage", 1.0)
		w.upgrades.apply(key + "_rank", w, "rare")
		var after_one := w.loadout.skill_stat(key, "damage", 1.0)
		w.upgrades.apply(key + "_rank", w, "rare")
		var after_two := w.loadout.skill_stat(key, "damage", 1.0)
		assert_near(after_one / first, 1.2, 1e-6, "%s: first Rare Mastery x1.2" % key)
		assert_near(after_two / after_one, 1.0 + 0.2 * 0.8, 1e-6, "%s: the repeat is x(1 + 0.2 x 0.8)" % key)
		assert_eq(w.loadout.rank(key), 8)


# --- real cache -------------------------------------------------------------------------------------------------------


func test_real_cache_the_eight_ranks_map_to_the_wz_levels_and_teleport_has_its_twenty() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	if lib.img("Skill.wz/232.img") == null:
		skip("the cache predates the Bishop manifest fragment (no Skill.wz/232.img)")
		lib.free()
		return
	var imgs := {}
	for b: String in ["230", "231", "232"]:
		imgs[b] = lib.img("Skill.wz/%s.img" % b).root
	var book := SkillBook.from_data(DataRepo.load_all().skills, imgs)
	for key: String in KEYS:
		assert_eq(book.max_level(key), 30, key)
		assert_eq(book.max_rank(key), 8, key)
		for rank in range(1, 9):
			assert_eq(book.canonical_level(key, rank), BF.RANK_LEVELS[rank - 1], "%s rank %d" % [key, rank])
	# Independent literals: the recorded WZ values for ranks 1..8 (BS1-373.md).
	var mad := {"holy_arrow": BF.ARROW_MAD, "shining_ray": BF.RAY_MAD, "angel_ray": BF.ANGEL_MAD}
	for key: String in mad:
		for rank in range(1, 9):
			var level := book.canonical_level(key, rank)
			assert_eq(int(book.canonical(key, level, "mad")), mad[key][rank - 1], "%s rank %d mad" % [key, rank])
			assert_eq(int(book.canonical(key, level, "mastery")), BF.MASTERY[rank - 1], "%s rank %d mastery" % [key, rank])
	for rank in range(1, 9):
		var node := book.level_node("shining_ray", book.canonical_level("shining_ray", rank))
		assert_eq(int(node.mobCount), 6, "Shining Ray rank %d mobCount" % rank)
		assert_eq([int(node.lt["$v"][0]), int(node.lt["$v"][1]), int(node.rb["$v"][0]), int(node.rb["$v"][1])],
			[-BF.RAY_HALF_WIDTH[rank - 1], -50, BF.RAY_HALF_WIDTH[rank - 1], 50], "Shining Ray rank %d box" % rank)
	# Teleport: 20 levels, one rank per level; 130 up to level 10, then +2 per level to 150.
	assert_eq(book.max_level("teleport_cleric"), 20)
	assert_eq(book.max_rank("teleport_cleric"), 20)
	for level in range(1, 21):
		assert_eq(int(book.canonical("teleport_cleric", level, "range")), 130 if level <= 10 else 130 + 2 * (level - 10),
			"Teleport level %d range" % level)
		assert_eq(book.canonical_level("teleport_cleric", level), level)
	for key: String in KEYS + ["teleport_cleric"]:
		assert_true(lib.frame(String(book.def(key).icon)) != null, "%s icon" % key)
		assert_true(lib.sound(String(book.def(key).sounds.use)) != null, "%s Use sound" % key)
	for key: String in KEYS:
		for field: String in ["hit", "effect"]:
			assert_true(lib.anim(book.visual(key, field, 30, 30)) != null, "%s %s art" % [key, field])
	assert_true(lib.anim(String(book.def("holy_arrow").ball)) != null, "Holy Arrow ball")
	assert_true(lib.frame(String(book.def("angel_ray").ball)) != null, "Angel Ray's single-frame ball")
	assert_true(lib.missing.is_empty(), str(lib.missing))
	lib.free()


# --- text -------------------------------------------------------------------------------------------------------------


func test_skill_text_fills_every_placeholder_of_the_three_overrides() -> void:
	var w := BF.round_world()
	var text := SkillText.new(w.book, {})
	var want := {
		"holy_arrow": "Basic attack 28, mastery 20%, 1 arrow per cast",
		"shining_ray": "Basic attack 66, mastery 20%, up to 6 monsters",
		"angel_ray": "Basic attack 132, mastery 20%, 1 shot per cast",
	}
	for key: String in want:
		w.learn_skill(key)
		assert_eq(text.level_line(key, 4, w.loadout.stats(key, 1)), want[key], key)
		assert_ne(text.desc(key), "", "%s has a description" % key)
