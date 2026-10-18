extends TestCase
## Every weapon family against the real asset cache (#154): stance, action set, afterimage, spark and sound all resolve.
## Needs an asset cache imported with asset_manifest.d/common.json; a SKIP proves nothing.

## One representative weapon per family and handedness (all imported by asset_manifest.d/common.json or the creation set).
const WEAPONS := [1302000, 1312004, 1322005, 1332000, 1372005, 1402001, 1412000, 1422000, 1432000, 1442000, 1452000,
	1462000, 1472000, 1482000, 1492000]
const BODY := "Character.wz/00002000.img"


func _item(lib: AssetLibrary, id: int) -> WzImg:
	return lib.img(AvatarRenderer.part_img_path(id))


func test_stances_resolve_in_the_item_and_the_body_for_every_family() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var body := lib.img(BODY)
	for id in WEAPONS:
		var item := _item(lib, id)
		assert_true(item != null, "weapon %d imported" % id)
		if item == null:
			continue
		var info: Dictionary = item.node("info")
		for stance in [WeaponInfo.stand_stance(info), WeaponInfo.walk_stance(info)]:
			assert_true(item.node(stance) != null, "%d draws in %s" % [id, stance])
			assert_true(body.node(stance) != null, "the body has %s" % stance)
	# Two-handed stand stances (2H sword, spear, polearm, crossbow) and one-handed ones.
	assert_eq(WeaponInfo.stand_stance(_item(lib, 1402001).node("info")), "stand2")
	assert_eq(WeaponInfo.walk_stance(_item(lib, 1402001).node("info")), "walk1", "2H swords walk with walk1")
	assert_eq(WeaponInfo.stand_stance(_item(lib, 1432000).node("info")), "stand2")
	assert_eq(WeaponInfo.walk_stance(_item(lib, 1432000).node("info")), "walk2")
	assert_eq(WeaponInfo.stand_stance(_item(lib, 1302000).node("info")), "stand1")
	assert_eq(WeaponInfo.stand_stance(_item(lib, 1452000).node("info")), "stand1")


func test_basic_actions_exist_in_the_weapon_the_body_and_the_afterimage() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var body := lib.img(BODY)
	for id in WEAPONS:
		var item := _item(lib, id)
		var info: Dictionary = item.node("info")
		var after := lib.img(WeaponInfo.afterimage_img_path(WeaponInfo.afterimage_name(info)))
		assert_true(after != null, "%d afterimage %s" % [id, WeaponInfo.afterimage_name(info)])
		for action in WeaponInfo.basic_actions(id):
			assert_true(item.node(action) != null, "%d has the %s stance" % [id, action])
			assert_true(body.node(action) != null, "the body has %s" % action)
			assert_true(WeaponInfo.basic_kind(id, action) in ["swing", "stab", "shoot"], "%d %s kind" % [id, action])
			if after == null:
				continue
			var node: Variant = after.node("%s/%s" % [WeaponInfo.AFTERIMAGE_VARIANT, action])
			if WeaponInfo.is_ranged(id):
				continue
			assert_true(node is Dictionary and node.has("lt") and node.has("rb"), "%d %s afterimage box" % [id, action])
		if WeaponInfo.family(id) == "bow":
			assert_true(after.node("0/shoot1") is Dictionary, "the Bow's draw frame")


func _avatar(weapon: int, cash := {}) -> AvatarRenderer:
	var a := AvatarRenderer.new()
	a.library = AssetLibrary.get_default()
	a.set_look({"equips": [1040002, 1060002, 1072001, weapon], "cash": cash})
	return a


func _owned(a: AvatarRenderer, id: int) -> int:
	var n := 0
	for p: Dictionary in a.current_parts():
		if int(p.get("owner", 0)) == id:
			n += 1
	return n


func test_the_avatar_draws_every_family_in_its_own_standing_and_walking_stance() -> void:
	if not require_cache():
		return
	for id in WEAPONS:
		var info: Dictionary = _item(AssetLibrary.get_default(), id).node("info")
		var a := _avatar(id)
		a.play("stand1")
		assert_eq(a.stance, WeaponInfo.stand_stance(info), "%d stands" % id)
		assert_true(_owned(a, id) > 0, "%d is drawn standing" % id)
		a.play("walk1")
		assert_eq(a.stance, WeaponInfo.walk_stance(info), "%d walks" % id)
		assert_true(_owned(a, id) > 0, "%d is drawn walking" % id)
		for action in WeaponInfo.basic_actions(id):
			a.play(action, true, false)
			assert_true(_owned(a, id) > 0, "%d is drawn in %s" % [id, action])
		a.free()
	var bare := _avatar(0)
	bare.play("stand1")
	assert_eq(bare.stance, "stand1", "no weapon, no variant")
	bare.free()


func test_a_cash_weapon_covers_a_two_handed_sword_and_a_claw() -> void:
	if not require_cache():
		return
	# 1702083 has art for every weapon type incl. 40 (two-handed sword) and 47 (claw).
	for pair: Array in [[1402001, "stand1"], [1402001, "walk1"], [1402001, "swingT1"], [1472000, "stand1"],
			[1472000, "swingO2"]]:
		var a := _avatar(int(pair[0]), {"weapon": 1702083})
		a.play(String(pair[1]), true)
		assert_true(_owned(a, 1702083) > 0, "the cover is drawn over %d in %s" % pair)
		assert_eq(_owned(a, int(pair[0])), 0, "and the real weapon is hidden")
		a.free()


func test_sparks_and_sounds_resolve_for_every_family() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var sounds := lib.img("Sound.wz/Weapon.img")
	var sparks := lib.img("Character.wz/Afterimage/hit.img")
	for id in WEAPONS:
		var info: Dictionary = _item(lib, id).node("info")
		var name := WeaponInfo.afterimage_name(info)
		for action in WeaponInfo.basic_actions(id):
			var spark := WeaponInfo.hit_spark_path(name, action).trim_prefix("Character.wz/Afterimage/hit.img/")
			assert_true(sparks.node(spark) != null, "%d spark %s" % [id, spark])
		var sound := WeaponInfo.sound_path(info).trim_prefix("Sound.wz/Weapon.img/")
		assert_true(sounds.node(sound) != null, "%d sound %s" % [id, sound])
	assert_true(sounds.node("barehands/Attack") != null, "bare hands")
