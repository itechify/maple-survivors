extends TestCase
## Spec #225 / #228: no job-neutral cards but the Power Elixir filler, and potions that upgrade by character level from
## the balance.potions.schedule through RunWorld's level-up and snapshot-load seams (seeded RNG, fixed dt).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const REMOVED := ["magnet", "orange_potion", "white_potion", "mana_elixir"]


## Earns exactly one level at a time through a real EXP pickup and answers every window (Magician line).
func _level_up_once(w: RunWorld) -> void:
	w.pickups.spawn(w.player.pos - Vector2(0, 25), w.progression.exp_to_next(), 4000019)
	w.step(DT, MoveInput.new())
	BotInput.auto_choose(w, false, 210)


func _tier_events(w: RunWorld) -> Array:
	return w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "potion_tier_up")


func _loaded(character: Dictionary, p_seed := 5) -> RunWorld:
	var setup := RF.setup("quiet", p_seed, RF.quiet_data())
	setup.character = character
	return RunWorld.new(setup)


func _snapshot_at(level: int) -> Dictionary:
	var w := RF.quiet_world(400.0, 3)
	var s := w.character_snapshot()
	s.level = level
	s.exp = 0
	return s


## The researched schedule (docs/research/v83-potion-progression.md section 6): the three old card gates, then Unagi and
## Pure Water at Lv 40 and Ice Cream Pop and Red Bean Sundae at Lv 60 (spec #225 / #229).
const STEPS := [{"level": 10, "kind": "hp", "item": 2000001}, {"level": 20, "kind": "mp", "item": 2000006},
	{"level": 25, "kind": "hp", "item": 2000002}, {"level": 40, "kind": "hp", "item": 2022003},
	{"level": 40, "kind": "mp", "item": 2022000}, {"level": 60, "kind": "hp", "item": 2001001},
	{"level": 60, "kind": "mp", "item": 2001002}]


func test_schedule_data_ships_the_researched_steps() -> void:
	var balance: Dictionary = DataRepo.load_all().balance
	var potions: Dictionary = balance.potions
	assert_eq((potions.schedule as Array).size(), 7, "three card gates and four researched steps")
	assert_eq(PotionSchedule.steps(balance), STEPS)
	assert_has(potions, "_schedule")
	assert_true(String(potions._schedule).contains("docs/research/v83-potion-progression.md"), "tier C pointer to the doc")
	assert_true(String(potions._schedule).contains("Tier C"))


func test_schedule_fires_at_exactly_its_levels_keeping_the_stock() -> void:
	var w := RF.quiet_world(400.0, 111)
	w.potions.add("mp", 4)
	w.drain_events()
	var expected := {
		10: [["hp", 2000000, 2000001, 5]], 20: [["mp", 2000003, 2000006, 4]], 25: [["hp", 2000001, 2000002, 5]],
		40: [["hp", 2000002, 2022003, 5], ["mp", 2000006, 2022000, 4]],
		60: [["hp", 2022003, 2001001, 5], ["mp", 2022000, 2001002, 4]]}
	var hp_items := {0: 2000000, 10: 2000001, 25: 2000002, 40: 2022003, 60: 2001001}
	var mp_items := {0: 2000003, 20: 2000006, 40: 2022000, 60: 2001002}
	while w.progression.level < 62:
		_level_up_once(w)
		var level := w.progression.level
		var events := _tier_events(w)
		var wanted: Array = expected.get(level, [])
		assert_eq(events.size(), wanted.size(), "notice events at Lv %d" % level)
		if events.size() == wanted.size():
			for i in wanted.size():
				var want: Array = wanted[i]
				assert_eq(events[i], {"type": "potion_tier_up", "kind": want[0], "from_item_id": want[1],
					"item_id": want[2], "count": want[3]}, "step %d at Lv %d" % [i, level])
		var hp_item := 0
		for from_level: int in hp_items:
			if level >= from_level:
				hp_item = hp_items[from_level]
		var mp_item := 0
		for from_level: int in mp_items:
			if level >= from_level:
				mp_item = mp_items[from_level]
		assert_eq(w.player_state.potions.hp.item_id, hp_item, "HP item at Lv %d" % level)
		assert_eq(w.player_state.potions.mp.item_id, mp_item, "MP item at Lv %d" % level)
		assert_eq(w.player_state.potions.hp.count, 5)
		assert_eq(w.player_state.potions.mp.count, 4)


func test_the_schedule_is_monotonic_per_kind_in_the_real_item_data() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	var last := {"hp": 50, "mp": 100} # the starters: Red Potion and Blue Potion
	var data := DataRepo.load_all()
	for kind: String in ["hp", "mp"]:
		assert_eq(_spec_of(lib, int(data.balance.potions[kind].item_id), kind), last[kind], "starter %s restore" % kind)
	for step: Dictionary in PotionSchedule.steps(data.balance):
		var kind := String(step.kind)
		var restore := _spec_of(lib, int(step.item), kind)
		assert_true(restore > int(last[kind]), "%s step %d at Lv %d restores %d > %d" % [kind, step.item, step.level,
			restore, last[kind]])
		last[kind] = restore
	assert_eq(last, {"hp": 2000, "mp": 2000})


func test_every_scheduled_item_resolves_in_the_cache_with_icon_name_and_sound() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	var data := DataRepo.load_all()
	var setup := DataRepo.build_setup(data, "henesys_hg1", 1, Vector2(800, 600),
		func(p: String) -> Dictionary:
			var img := lib.img(p)
			return img.root if img != null else {},
		func(id: int) -> Dictionary: return lib.mob_root(id))
	for id in DataRepo.potion_item_ids(data):
		assert_true(setup.item_info.has(id), "item_info resolves %d (Consume/%04d.img)" % [id, id / 10000])
		assert_true(lib.has_img(DataRepo.potion_img_path(id)))
		assert_true(lib.frame(AssetLibrary.item_icon_path(id, false)) != null, "icon of %d" % id)
		assert_ne(String(lib.find(InventoryModel.name_path(id))), "", "String.wz name of %d" % id)
		assert_true(lib.sound("Sound.wz/Item.img/%08d/Use" % id) != null, "Use sound of %d" % id)
	assert_eq((setup.item_info[2022000] as Dictionary).spec.mp, 800.0, "Pure Water: its sound links to ../02012002/Use")
	assert_eq(String(lib.find(InventoryModel.name_path(2022003))), "Unagi")


func _spec_of(lib: AssetLibrary, id: int, kind: String) -> int:
	var img := lib.img(DataRepo.potion_img_path(id))
	if img == null:
		return -1
	var node: Variant = img.root.get("%08d" % id)
	return int(node.get("spec", {}).get(kind, -1)) if node is Dictionary else -1


func test_an_old_cache_without_the_new_items_stops_at_the_last_resolvable_tier() -> void:
	var old_items := {2000000: {"spec": {"hp": 50}}, 2000001: {"spec": {"hp": 150}}, 2000002: {"spec": {"hp": 300}},
		2000003: {"spec": {"mp": 100}}, 2000006: {"spec": {"mp": 300}}}
	var setup := RF.setup("quiet", 14, RF.quiet_data())
	setup.item_info = old_items
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	w.drain_events()
	while w.progression.level < 62:
		_level_up_once(w)
	assert_eq(w.player_state.potions.hp.item_id, 2000002, "HP stays White: Unagi and Ice Cream Pop do not resolve")
	assert_eq(w.player_state.potions.mp.item_id, 2000006, "MP stays Mana Elixir: Pure Water and Red Bean Sundae do not resolve")
	assert_eq(w.player_state.potions.hp.count, 5)
	var snapshot := _snapshot_at(60)
	var setup2 := RF.setup("quiet", 15, RF.quiet_data())
	setup2.item_info = old_items
	setup2.character = snapshot
	var loaded := RunWorld.new(setup2)
	assert_eq(loaded.player_state.potions.hp.item_id, 2000002, "a Lv 60 load on an old cache catches up to White")
	assert_eq(loaded.player_state.potions.mp.item_id, 2000006)
	# A partly newer cache (Unagi but no Ice Cream Pop) reaches exactly the tiers it holds.
	old_items[2022003] = {"spec": {"hp": 1000}}
	var setup3 := RF.setup("quiet", 16, RF.quiet_data())
	setup3.item_info = old_items
	setup3.character = snapshot
	assert_eq(RunWorld.new(setup3).player_state.potions.hp.item_id, 2022003)


func test_several_levels_in_one_tick_apply_every_due_step_in_level_order() -> void:
	var w := RF.quiet_world(400.0, 12)
	w.drain_events()
	w.pickups.spawn(w.player.pos - Vector2(0, 25), w.progression.curve.total_to(26) + 1, 4000019)
	w.step(DT, MoveInput.new())
	var events := _tier_events(w)
	assert_eq(events.map(func(e: Dictionary) -> int: return int(e.item_id)), [2000001, 2000006, 2000002])
	assert_eq(w.player_state.potions.hp.item_id, 2000002)
	assert_eq(w.player_state.potions.mp.item_id, 2000006)


func test_new_potion_item_is_what_drops_afterwards() -> void:
	var w := RF.quiet_world(400.0, 13)
	while w.progression.level < 25:
		_level_up_once(w)
	w.drain_events()
	w.balance.potions.drops.normal = {"hp": 1.0, "mp": 1.0}
	var slot := RF.put_mob(w, 100100, 800)
	w.hit_mob(slot, {"damage_min": 1000.0, "damage_max": 1000.0, "magic": false, "crit": 0.0,
		"crit_mult": 1.5, "skill": "three_snails"}, -1)
	var ids := w.drain_events().filter(func(e: Dictionary) -> bool:
		return e.type == "pickup_spawned" and e.get("kind") == "potion").map(func(e: Dictionary) -> int: return int(e.item_id))
	ids.sort()
	assert_eq(ids, [2000002, 2000006])


func test_lv38_fixture_loads_with_white_and_mana_elixir_without_notices() -> void:
	var text := FileAccess.get_file_as_string("res://tests/fixtures/characters/lv35_magician_2nd.json")
	var character: Dictionary = JSON.parse_string(text)
	assert_eq(int(character.level), 38)
	character.potions.hp.item_id = 2000000
	character.potions.mp.item_id = 2000003
	var w := _loaded(character)
	assert_eq(w.player_state.potions.hp, {"item_id": 2000002, "count": int(character.potions.hp.count)})
	assert_eq(w.player_state.potions.mp, {"item_id": 2000006, "count": int(character.potions.mp.count)})
	assert_eq(_tier_events(w).size(), 0, "a load catches up silently")
	var untouched: Dictionary = JSON.parse_string(text)
	var v := _loaded(untouched)
	assert_eq(v.player_state.potions.hp.item_id, 2000002)
	assert_eq(v.player_state.potions.mp.item_id, 2000006)


func test_snapshot_catch_up_applies_only_steps_up_to_its_level_and_never_downgrades() -> void:
	for example: Array in [[9, 2000000, 2000003], [10, 2000001, 2000003], [19, 2000001, 2000003],
			[20, 2000001, 2000006], [24, 2000001, 2000006], [25, 2000002, 2000006], [39, 2000002, 2000006], [40, 2022003, 2022000],
			[59, 2022003, 2022000], [60, 2001001, 2001002], [70, 2001001, 2001002]]:
		var w := _loaded(_snapshot_at(example[0]))
		assert_eq(w.player_state.potions.hp.item_id, example[1], "HP at Lv %d" % example[0])
		assert_eq(w.player_state.potions.mp.item_id, example[2], "MP at Lv %d" % example[0])
	var white := _snapshot_at(12)
	white.potions.hp.item_id = 2000002
	assert_eq(_loaded(white).player_state.potions.hp.item_id, 2000002, "White at Lv 12 is never downgraded to Orange")
	var counted := _snapshot_at(30)
	counted.potions.hp.count = 17
	assert_eq(_loaded(counted).player_state.potions.hp.count, 17, "catch-up keeps the stock")


func test_no_draw_contains_a_removed_card() -> void:
	var data := DataRepo.load_all()
	for c: Dictionary in data.upgrades.cards:
		assert_false(String(c.id) in REMOVED, "%s is gone from the data" % c.id)
		assert_ne(String(c.kind), "potion_tier")
	for job in [0, 200, 210]:
		for seed_value in range(1, 9):
			var w := RF.quiet_world(400.0, seed_value)
			RF.change_job_bare(w, job)
			w.progression.level = 30
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			var draws: Array = []
			draws.append_array(w.upgrades.roll_choices(w, rng, 3))
			w.choice_bonus = true
			draws.append_array(w.upgrades.roll_choices(w, rng, 3))
			w.choice_bonus = false
			draws.append_array(w.upgrades.roll_advancement_choices(w, rng, 3))
			for offered: Dictionary in draws:
				assert_false(String(offered.id) in REMOVED, "job %d seed %d offered %s" % [job, seed_value, offered.id])
			assert_false(w.upgrades.eligible(w).any(func(id: String) -> bool: return id in REMOVED))


func test_exhausted_job_pool_offers_the_power_elixir_alone_and_the_run_continues() -> void:
	var data := RF.quiet_data()
	data.upgrades.cards = []
	var w := RunWorld.new(RF.setup("quiet", 21, data))
	RF.place_player(w, 400)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	assert_eq(w.upgrades.roll_choices(w, rng, 3).map(func(c: Dictionary) -> String: return c.id), ["elixir"])
	w.choice_bonus = true
	assert_eq(w.upgrades.roll_choices(w, rng, 3).map(func(c: Dictionary) -> String: return c.id), ["elixir"], "boss reward")
	w.choice_bonus = false
	assert_eq(w.upgrades.roll_advancement_choices(w, rng, 3).map(func(c: Dictionary) -> String: return c.id), ["elixir"])
	w.drain_events()
	w.pickups.spawn(w.player.pos - Vector2(0, 25), w.progression.exp_to_next(), 4000019)
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE)
	assert_eq(w.pending_cards.map(func(c: Dictionary) -> String: return c.id), ["elixir"])
	assert_true(w.apply_choice("elixir"))
	assert_eq(w.state, RunWorld.PLAYING)
	assert_false(w.progression.has_pending())
	w.pickups.spawn(w.player.pos - Vector2(0, 25), w.progression.exp_to_next(), 4000019)
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "the next level-up opens again")


func test_a_pool_without_any_card_never_opens_an_unanswerable_window() -> void:
	var data := RF.quiet_data()
	data.upgrades.cards = []
	data.upgrades.erase("fallback")
	var w := RunWorld.new(RF.setup("quiet", 22, data))
	RF.place_player(w, 400)
	w.pickups.spawn(w.player.pos - Vector2(0, 25), w.progression.exp_to_next(), 4000019)
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.PLAYING, "nothing to offer: the level-up is consumed instead of soft-locking")
	assert_false(w.progression.has_pending())


func test_snapshot_with_magnet_ranks_loads_with_the_base_radius() -> void:
	var character := _snapshot_at(20)
	character.card_ranks["magnet"] = 3
	character.card_ranks["improved_max_mp"] = 2
	character.player_mods["magnet"] = [0.0, 1.953125]
	var w := _loaded(character)
	assert_eq(w.magnet_r, float(w.balance.magnet_radius))
	assert_false(w.loadout.card_ranks.has("magnet"))
	assert_false(w.loadout.player_mods.has("magnet"))
	assert_eq(int(w.loadout.card_ranks.get("improved_max_mp", 0)), 2, "other ranks are kept")
	assert_false(w.character_snapshot().card_ranks.has("magnet"))
	var migrated := CharacterSnapshot.migrate(character, w.jobs, {})
	assert_false(migrated.card_ranks.has("magnet"))
	assert_false(migrated.player_mods.has("magnet"))
	assert_true(character.card_ranks.has("magnet"), "the source is not mutated")


func test_notice_text_reads_right_for_every_scheduled_item() -> void:
	var data := DataRepo.load_all()
	var names := {2000000: "Red Potion", 2000003: "Blue Potion", 2000001: "Orange Potion", 2000006: "Mana Elixir",
		2000002: "White Potion", 2022003: "Unagi", 2022000: "Pure Water", 2001001: "Ice Cream Pop",
		2001002: "Red Bean Sundae"}
	var plurals: Dictionary = data.balance.potions.get("plural_names", {})
	for item: Variant in PotionSchedule.items(data.balance):
		assert_true(names.has(int(item)), "synthetic name for %s" % item)
		var line := PotionSchedule.notice_text(2000000, "Red Potion", int(item), String(names[int(item)]), plurals)
		assert_false("Unagis" in line or "Pure Waters" in line, line)
		assert_true(line.begins_with("Your Red Potions are now ") and line.ends_with("."), line)
	assert_eq(PotionSchedule.notice_text(2000000, "Red Potion", 2022003, "Unagi", plurals),
		"Your Red Potions are now Unagi.")
	assert_eq(PotionSchedule.notice_text(2022003, "Unagi", 2001001, "Ice Cream Pop", plurals),
		"Your Unagi are now Ice Cream Pops.")
	assert_eq(PotionSchedule.notice_text(2000003, "Blue Potion", 2000006, "Mana Elixir", plurals),
		"Your Blue Potions are now Mana Elixirs.")


func test_notice_text_default_plural_is_name_plus_s_and_an_override_wins() -> void:
	assert_eq(PotionSchedule.notice_text(1, "A", 2, "B", {}), "Your As are now Bs.")
	assert_eq(PotionSchedule.notice_text(1, "A", 2, "B", {"2": "Bee"}), "Your As are now Bee.")
	assert_eq(PotionSchedule.notice_text(1, "A", 2, "B", {"1": "Aye", "2": "Bee"}), "Your Aye are now Bee.")
