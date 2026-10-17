extends TestCase
## Presentation against the real imported v83 cache (SKIP without it): Snail animation timing, map 104040000 builds
## with zero missing lookups, the composited beginner in every stance, damage digits, HUD art, names and sounds.

const STANCES := ["stand1", "walk1", "jump", "alert", "prone", "ladder", "rope", "swingO1", "shoot1", "dead"]

var lib: AssetLibrary


func before_each() -> void:
	lib = AssetLibrary.new()
	lib.open()


func after_each() -> void:
	lib.free()


func test_snail_animations() -> void:
	if not require_cache():
		return
	var move := lib.anim("Mob.wz/0100100.img/move")
	assert_eq(move.frame_count(), 5)
	for f in move.frames:
		assert_near(f.delay_s, 0.18, 1e-6, "move delay 180 ms (WZ)")
	assert_near(move.total, 0.9, 1e-5)
	assert_eq(move.frames[0].origin, Vector2(18, 26))
	assert_eq(move.frames[0].region.size, Vector2(37, 26))
	assert_eq(move.frames[0].vec("head"), Vector2(-13, -24))
	var stand := lib.anim("Mob.wz/0100100.img/stand")
	assert_eq(stand.frame_count(), 1)
	assert_near(stand.frames[0].delay_s, 0.1, 1e-6, "no delay key -> 100 ms (tier C)")
	var die := lib.anim("Mob.wz/0100100.img/die1")
	assert_eq(die.frame_count(), 9)
	assert_near(die.total, 8 * 0.12 + 0.3, 1e-5)
	var hit := lib.anim("Mob.wz/0100100.img/hit1")
	assert_near(hit.frames[0].delay_s, 0.6, 1e-6)
	var om_die := lib.anim("Mob.wz/1210102.img/die1")
	assert_near(om_die.frames[2].a0, 1.0, 1e-6, "Orange Mushroom die1/2 a0 255")
	assert_near(om_die.frames[2].a1, 0.0, 1e-6, "a1 0: fades out")
	assert_true(move.frames[0].page != null, "page loaded")
	assert_eq(lib.missing.size(), 0, "%s" % [lib.missing])


func test_map_104040000_builds_without_missing() -> void:
	if not require_cache():
		return
	var map := MapRenderer.new()
	map.library = lib
	assert_true(map.load_map(104040000))
	assert_eq(map.missing.size(), 0, "missing lookups: %s" % [map.missing])
	assert_eq(map.stats.objs, 135)
	assert_eq(map.stats.tiles, 288)
	assert_eq(map.stats.backs, 5)
	assert_eq(map.stats.portals, 2, "west00/east00 (pt 2)")
	assert_true(map.stats.animated >= 5, "animated objs + portals")
	assert_eq(map.bounds, Rect2(-530, -1278, 2317, 1832), "miniMap rule (no VR in this map)")
	# Every sprite of every run has its atlas page.
	for layer in 8:
		for run in map.get_node("Layer%d" % layer).get_children():
			if run is MapDrawList:
				for it: Dictionary in run.items:
					assert_true(it.anim.frames[0].page != null, "texture for %s" % it.get("path", "?"))
	assert_eq(lib.missing.size(), 0, "library misses: %s" % [lib.missing])
	map.free()


func test_other_maps_build_without_missing() -> void:
	if not require_cache():
		return
	for id in [101010100]:
		var map := MapRenderer.new()
		map.library = lib
		assert_true(map.load_map(id), "map %d" % id)
		assert_eq(map.missing.size(), 0, "map %d missing: %s" % [id, map.missing])
		map.free()


func test_beginner_every_stance() -> void:
	if not require_cache():
		return
	var a := AvatarRenderer.new()
	a.library = lib
	a.set_look({})
	assert_eq(a.missing.size(), 0, "part imgs: %s" % [a.missing])
	for s: String in STANCES:
		assert_true(a.has_stance(s), "stance %s" % s)
		var parts := a.compose(s, 0)
		assert_true(parts.size() >= 3, "%s has parts" % s)
		var names: PackedStringArray = []
		for p: Dictionary in parts:
			names.append(p.name)
			assert_true((p.frame as SpriteFrame).page != null, "%s/%s texture" % [s, p.name])
		var facing_back := s == "ladder" or s == "rope"
		assert_eq("face" in names, not facing_back, "%s: face shown unless climbing (%s)" % [s, names])
		assert_true("head" in names, "%s head (%s)" % [s, names])
	# stand1/0 anchors by hand: body origin at the feet, head at body.neck (-4,-32) - head.neck (0,15).
	var parts := a.compose("stand1", 0)
	for p: Dictionary in parts:
		match p.name:
			"body":
				assert_eq(p.pos, Vector2(0, 0))
			"head":
				assert_eq(p.pos, Vector2(-4, -47))
			"arm":
				assert_eq(p.pos, Vector2(5, -20), "body.navel (-8,-21) - arm.navel (-13,-1)")
	# Draw order (back to front by zmap): the arm over the body, the face over the head.
	var idx := {}
	for i in parts.size():
		idx[parts[i].name] = i
	assert_true(idx.body < idx.arm, "arm over body")
	assert_true(idx.head < idx.face, "face over head")
	assert_eq(a.stance_delays("walk1"), PackedFloat32Array([0.18, 0.18, 0.18, 0.18]))
	assert_eq(a.stance_delays("swingO1"), PackedFloat32Array([0.3, 0.15, 0.35]))
	a.free()


func test_magician_wand_look() -> void:
	if not require_cache():
		return
	var a := AvatarRenderer.new()
	a.library = lib
	a.set_look({"equips": [1040002, 1060002, 1072001, 1372005]})
	assert_eq(a.missing.size(), 0, "part imgs: %s" % [a.missing])
	for s: String in STANCES:
		var names: PackedStringArray = []
		for p: Dictionary in a.compose(s, 0):
			names.append(p.name)
		# 1372005 has stand1/walk1/alert/swingO1/shoot1/prone/jump but no ladder/rope/dead: skipped silently.
		var has_weapon := lib.find("Character.wz/Weapon/01372005.img/" + s) != null
		assert_eq("weapon" in names, has_weapon, "%s weapon part (%s)" % [s, names])
	assert_eq(a.missing.size(), 0, "stances the wand lacks are not recorded as missing")
	a.free()


func test_damage_digits_and_hud_art() -> void:
	if not require_cache():
		return
	for set_name in ["NoRed0", "NoRed1", "NoCri0", "NoCri1", "NoViolet0", "NoViolet1"]:
		for d in 10:
			assert_true(lib.frame("Effect.wz/BasicEff.img/%s/%d" % [set_name, d]) != null, "%s/%d" % [set_name, d])
	assert_true(lib.frame("Effect.wz/BasicEff.img/NoCri1/effect") != null)
	assert_true(lib.frame("Effect.wz/BasicEff.img/NoRed0/Miss") != null)
	assert_eq(lib.frame("UI.wz/StatusBar.img/base/backgrnd").region.size, Vector2(800, 71))
	for p in ["base/backgrnd2", "gauge/bar", "gauge/graduation", "gauge/gray", "number/0", "number/slash",
			"number/Lbracket", "number/percent", "BtShop/normal/0", "EquipKey/normal/0"]:
		assert_true(lib.frame("UI.wz/StatusBar.img/" + p) != null, p)
	for d in 10:
		assert_true(lib.frame("UI.wz/Basic.img/LevelNo/%d" % d) != null, "LevelNo %d" % d)
		assert_true(lib.frame("UI.wz/Basic.img/ItemNo/%d" % d) != null, "ItemNo %d" % d)
	assert_eq(lib.anim("Effect.wz/Tomb.img/fall").frame_count(), 20)
	assert_eq(lib.anim("Effect.wz/BasicEff.img/LevelUp").frame_count(), 21)
	assert_eq(lib.anim("Effect.wz/BasicEff.img/JobChanged").frame_count(), 13)
	assert_eq(lib.anim("Effect.wz/BasicEff.img/JobChanged").z, -1, "drawn behind the character")
	assert_eq(lib.anim("Skill.wz/000.img/skill/0001000/level/1/ball").frame_count(), 3, "Three Snails shell")
	assert_eq(lib.anim("Skill.wz/000.img/skill/0001000/level/1/hit/0").frame_count(), 6)
	assert_true(lib.anim("Map.wz/MapHelper.img/portal/game/pv").frame_count() > 1, "portal animation")
	assert_true(lib.frame(AssetLibrary.item_icon_path(4000019)) != null, "Snail Shell iconRaw")
	for coin in [9000000, 9000001, 9000002, 9000003]:
		for frame in 4:
			assert_true(lib.frame(AssetLibrary.meso_frame_path(coin, frame)) != null, "meso %d frame %d" % [coin, frame])
	assert_eq(lib.missing.size(), 0, "%s" % [lib.missing])


func test_names_and_sounds() -> void:
	if not require_cache():
		return
	assert_eq(lib.string_name("Mob", 100100), "Snail")
	assert_eq(lib.string_name("Mob", 1210102), "Orange Mushroom")
	assert_eq(lib.string_name("Map", 104040000), "Henesys Hunting Ground I")
	assert_eq(lib.string_name("Skill", 1000), "Three Snails")
	assert_eq(lib.string_name("Etc", 4000019), "Snail Shell")
	var bgm := lib.sound(AssetLibrary.bgm_path(str(lib.node("Map.wz/Map/Map1/104040000.img/info/bgm"))))
	assert_true(bgm is AudioStreamMP3, "CavaBien MP3")
	if bgm != null:
		assert_between(bgm.get_length(), 126.0, 130.0, "about 128 s ($ms 128000)")
	assert_true(lib.sound("Sound.wz/Mob.img/0100100/Die") != null)
	assert_true(lib.sound("Sound.wz/Game.img/PickUpItem") != null)
