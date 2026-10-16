extends TestCase
## MP Eater's canonical monster pools, branch cards and seeded resolved-hit behaviour.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const KEYS := ["mp_eater_fp", "mp_eater_il", "mp_eater_cleric"]
const JOBS := [210, 220, 230]


func _setup() -> Dictionary:
	var setup := RF.setup()
	for job: int in JOBS:
		var levels := {}
		for level in range(1, 21):
			# Synthetic levels; canonical endpoints are independently checked against the real cache below.
			levels[str(level)] = {"prop": float(10 + level), "x": float(20 + level)}
		var book := str(job)
		if not setup.skill_imgs.has(book):
			setup.skill_imgs[book] = {"skill": {}}
		setup.skill_imgs[book].skill[str(job * 10000)] = {"level": levels}
	return setup


func test_monster_max_mp_is_canonical_and_defaults_to_zero() -> void:
	var kind := MobKind.from_wz({"info": {"maxHP": 50.0, "maxMP": 15.0}}, 210100, {"hp_mult": 3.0})
	assert_eq(kind.get("max_mp"), 15, "MP is independent of survivor HP scaling")
	assert_eq(MobKind.from_wz({}, 100100).get("max_mp"), 0, "absent maxMP means no MP")
	assert_eq(MobKind.from_wz({"info": {"maxMP": 0.0}}, 100100).get("max_mp"), 0)


func test_spawn_growth_and_reuse_reset_monster_mp() -> void:
	var kind := MobKind.from_wz({"info": {"maxMP": 15.0}}, 210100)
	var swarm := MobSwarm.new(1, [kind])
	var first := swarm.spawn(0, 0, 0, -1, 100)
	var mp: Variant = swarm.get("mp")
	assert_true(mp is PackedInt32Array, "per-slot MP is packed")
	if not (mp is PackedInt32Array):
		return
	assert_eq(mp[first], 15)
	swarm.mp[first] = 2
	var second := swarm.spawn(0, 0, 0, -1)
	assert_eq(swarm.mp[second], 15, "growing the pool initializes MP")
	assert_eq(swarm.mp[first], 2, "growth keeps depleted MP")
	swarm.despawn(first)
	assert_eq(swarm.mp[first], 0, "free slots hold no MP")
	var reused := swarm.spawn(0, 0, 0, -1)
	assert_eq(reused, first)
	assert_eq(swarm.mp[reused], 15, "a fresh monster has full MP")


func test_relocation_preserves_depleted_mp_and_fresh_spawn_refills_it() -> void:
	var w := RF.quiet_world()
	w.mob_kinds[0].max_mp = 200
	var slot := w.spawn_mob(0, w.player.pos + Vector2(100, 0), w.player.fh, 3, false)
	w.swarm.mp[slot] = 7
	var moved := w.relocate_mob(slot, w.player.pos + Vector2(200, 0), w.player.fh)
	assert_eq(w.swarm.mp[moved], 7, "relocation cannot refill a drained monster")
	w.swarm.mp[moved] = 0
	var drained := w.relocate_mob(moved, w.player.pos + Vector2(300, 0), w.player.fh)
	assert_eq(w.swarm.mp[drained], 0)
	w.swarm.despawn(drained)
	var fresh := w.spawn_mob(0, w.player.pos, w.player.fh, 1, false)
	assert_eq(w.swarm.mp[fresh], 200)


func test_branch_cards_learn_and_rank_passive_only_in_their_job() -> void:
	for branch in JOBS.size():
		var w := RunWorld.new(_setup())
		RF.change_job_bare(w, JOBS[branch])
		var key: String = KEYS[branch]
		assert_true(w.book.has(key), "branch has MP Eater")
		if not w.book.has(key):
			continue
		assert_eq(w.book.skill_id(key), JOBS[branch] * 10000)
		assert_eq(w.book.kind(key), "passive")
		assert_false(w.book.is_active(key), "MP Eater never auto-casts")
		assert_eq(w.book.max_rank(key), 20)
		assert_has(w.upgrades.eligible(w), key + "_new")
		for other in JOBS.size():
			if other != branch:
				assert_false(KEYS[other] + "_new" in w.upgrades.eligible(w))
		w.upgrades.apply(key + "_new", w)
		assert_eq(w.loadout.level(key), 1)
		assert_has(w.upgrades.eligible(w), key + "_rank")
		w.upgrades.apply(key + "_rank", w)
		assert_eq(w.loadout.level(key), 2)
		w.loadout.set_rank(key, 20)
		assert_false(key + "_rank" in w.upgrades.eligible(w), "maxed passive has no rank offer")
		for card: Dictionary in w.upgrades.cards:
			if String(card.get("skill", "")) == key:
				assert_true(String(card.kind) in ["skill_new", "skill_rank"], "no behaviour cards")


func test_bot_prefers_attack_then_mp_eater_over_general_magnet() -> void:
	var w := RunWorld.new(_setup())
	RF.change_job_bare(w, 210)
	var learn := {"id": "mp_eater_fp_new"}
	assert_true(BotInput.card_score(w, {"id": "fire_arrow_new"}) > BotInput.card_score(w, learn))
	assert_true(BotInput.card_score(w, learn) > BotInput.card_score(w, {"id": "magnet"}))
	assert_true(BotInput.card_score(w, {"id": "mp_eater_fp_rank"}) > BotInput.card_score(w, learn))


func test_real_cache_mp_eater_levels_effects_and_monster_pools() -> void:
	if not require_cache():
		return
	var library := AssetLibrary.new()
	var imgs := {}
	for job: int in JOBS:
		imgs[str(job)] = library.img("Skill.wz/%d.img" % job).root
	var book := SkillBook.from_data(DataRepo.load_all().skills, imgs)
	for key: String in KEYS:
		assert_eq(book.max_level(key), 20)
		assert_eq(book.canonical(key, 1, "prop"), 11.0)
		assert_eq(book.canonical(key, 1, "x"), 21.0)
		assert_eq(book.canonical(key, 20, "prop"), 30.0)
		assert_eq(book.canonical(key, 20, "x"), 40.0)
		assert_true(library.anim(book.visual(key, "effect", 1, 30)).duration() > 0.0)
	for id: int in [100100, 100101, 210100]:
		var img := library.img("Mob.wz/%07d.img" % id)
		var kind := MobKind.from_wz(img.root, id)
		assert_eq(kind.max_mp, {100100: 0, 100101: 15, 210100: 35}[id])
	assert_eq(library.missing, PackedStringArray(), "all required MP Eater assets are cached")
	library.free()
