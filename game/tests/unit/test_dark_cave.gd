extends TestCase
## Dark Cave's public stage data and deterministic round contract (spec #32, ticket #72).

const RF := preload("res://tests/fixtures/run_fixtures.gd")


## The owner's ordinary roster and tier list are available through the normal data boundary.
func test_dark_cave_roster_and_run_tiers() -> void:
	var data := DataRepo.load_all()
	var stage: Dictionary = data.stages.stages.get("dark_cave", {})
	assert_eq(int(stage.get("map_id", 0)), 105050400, "v83 Dark Cave")
	assert_eq(int(stage.get("duration", 0)), 900, "standard fifteen-minute round")
	var ordinary_stage := stage.duplicate()
	ordinary_stage["bosses"] = []
	assert_eq(StageRoster.named_ids(ordinary_stage),
		PackedInt32Array([2110200, 2230100, 2230101, 2300100, 3230100, 3230300, 7130100, 7130101]),
		"owner's tier-2 ordinary roster; bosses belong to #73")
	assert_eq(data.stages.get("tiers", []), [["henesys_hg1", "tree_that_grew_1"], ["dark_cave"]],
		"tier indices start at zero")


## Pacing introduces each phase in order and spans the standard round.
func test_keyframes_introduce_the_roster_in_owner_order() -> void:
	var stage: Dictionary = DataRepo.load_all().stages.stages.get("dark_cave", {})
	var frames: Array = stage.get("keyframes", [])
	assert_false(frames.is_empty(), "a paced round")
	var first_seen := {}
	var previous := -1.0
	for frame: Dictionary in frames:
		var t := float(frame.t)
		assert_true(t > previous, "strictly increasing keyframe times")
		previous = t
		assert_true(float(frame.rate) > 0.0 and int(frame.max_alive) > 0, "spawning remains active")
		assert_true(int(frame.max_alive) <= int(stage.hard_cap), "ordinary cap fits the hard cap")
		for id: String in frame.pool:
			assert_true(float(frame.pool[id]) > 0.0, "every listed mob can spawn")
			if not first_seen.has(id):
				first_seen[id] = t
	assert_eq(first_seen, {"2110200": 0.0, "2230101": 0.0, "2300100": 0.0,
		"2230100": 120.0, "3230100": 300.0, "3230300": 300.0, "7130100": 600.0, "7130101": 780.0},
		"opening, Eyes/Boogie, late Tauromacis and last-minutes Taurospear")
	assert_near(previous, 900.0, 1e-6, "pacing reaches the round duration")


## Every ordinary mob has its signature pickup and import selections.
func test_signature_exp_items_and_manifest_cover_the_stage() -> void:
	# Tier A: names/IDs verified in original v83 String.wz/Etc.img; tier C: signature EXP icon association.
	var expected := {2110200: 4000015, 2230101: 4000008, 2300100: 4000042, 2230100: 4000007,
		3230100: 4000013, 3230300: 4000067, 7130100: 4000028, 7130101: 4000046}
	var data := DataRepo.load_all()
	var manifest: Dictionary = AssetManifest.load_merged("res://data/asset_manifest.json")
	assert_true(105050400 in PackedInt32Array(manifest.maps), "import the canonical map and its dependencies")
	for id: int in expected:
		assert_eq(int(data.mobs.mobs.get(str(id), {}).get("exp_item", 0)), expected[id], "signature item for %d" % id)
		assert_true(id in PackedInt32Array(manifest.mobs), "mob animation and sounds for %d" % id)
		assert_true(int(expected[id]) in PackedInt32Array(manifest.items), "pickup art for %d" % id)
	var npc_imgs: Array = manifest.imgs.filter(func(row: Dictionary) -> bool: return row.img == "Npc.wz/9201133.img")
	assert_eq(npc_imgs.size(), 1, "draw Dark Cave's inert NPC with the existing renderer")


## A deterministic bossless round crosses the duration boundary exactly once.
func test_bossless_round_clears_at_fifteen_minutes() -> void:
	# Synthetic mob art/stats, real stage data; seed and fixed ticks make the duration boundary reproducible.
	var setup := RF.setup("dark_cave", 72)
	# Keep exercising the bossless fallback after #73 supplies the live stage's boss schedule.
	setup.data.stages.stages.dark_cave.bosses = []
	for id in DataRepo.stage_mob_ids(setup.data, "dark_cave"):
		setup.mob_imgs[id] = {"info": {"maxHP": 10, "exp": 1, "bodyAttack": 1},
			"stand": {"0": {"delay": 100}}}
	var w := RunWorld.new(setup)
	w.god = true
	assert_true(w.warnings.is_empty(), "every roster member loads")
	assert_false(w.bosses.has_bosses(), "#73 owns the future boss schedule")
	w.time = 900.0 - 2.0 / 60.0
	w.step(1.0 / 60.0, MoveInput.new())
	assert_eq(w.state, RunWorld.PLAYING, "cannot clear before duration")
	w.step(1.0 / 60.0, MoveInput.new())
	assert_eq(w.state, RunWorld.CLEARED, "no absent final boss can leave this round hanging")
	var clears := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "stage_cleared")
	assert_eq(clears.size(), 1, "one clear event")
	w.step(1.0 / 60.0, MoveInput.new())
	assert_true(w.drain_events().is_empty(), "finished round stays finished")


## The real cache preserves canonical stats, geometry and existing cross-map exit handling.
func test_real_map_roster_stats_and_inert_cross_map_portals() -> void:
	if not require_cache():
		return
	var data := DataRepo.load_all()
	var setup := DataRepo.build_setup(data, "dark_cave", 72, Vector2(800, 600), _img, _mob)
	var w := RunWorld.new(setup)
	assert_true(w.warnings.is_empty(), "private cache contains the entire stage: %s" % w.warnings)
	assert_eq(w.ladders.x.size(), 14, "original Dark Cave ladders")
	assert_eq(w.portals.links.size(), 0, "west00/east00 leave this map, so stay inert as in Henesys")
	assert_eq(int(setup.map_img.portal["1"].tm), 105050300, "west00 to Ant Tunnel IV")
	assert_eq(int(setup.map_img.portal["2"].tm), 105060000, "east00 to Dangerous Steam")
	assert_true(w.mob_kinds[int(w.kind_of_id[2300100])].flies, "Stirge flies")
	for id in DataRepo.stage_mob_ids(data, "dark_cave"):
		var kind: MobKind = w.mob_kinds[int(w.kind_of_id[id])]
		var info: Dictionary = setup.mob_imgs[id].info
		assert_eq(kind.max_hp, int(info.maxHP), "canonical HP for %d" % id)
		assert_eq(kind.exp, int(info.exp), "canonical EXP for %d" % id)
		assert_eq(kind.level, int(info.level), "canonical level for %d" % id)
		assert_eq(kind.pdd, int(info.get("PDDamage", 0)), "canonical defence for %d" % id)
		assert_eq(kind.elem_attr, String(info.get("elemAttr", "")), "canonical elements for %d" % id)


func _img(path: String) -> Dictionary:
	var parsed: Variant = DataRepo.load_json(AssetCachePaths.resolve_cache_root().path_join(path + ".json"))
	return parsed if parsed is Dictionary else {}


func _mob(id: int) -> Dictionary:
	return _img("Mob.wz/%07d.img" % id)
