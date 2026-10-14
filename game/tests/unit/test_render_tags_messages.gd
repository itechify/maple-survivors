extends TestCase
## Elite name tags (GAME_DESIGN section 4) and the HUD's "+N EXP" system messages (section 5).

const AF := preload("res://tests/fixtures/asset_fixtures.gd")


func _swarm(n: int) -> DebugSoA:
	return DebugSoA.make(n, {"kind": TYPE_PACKED_INT32_ARRAY, "x": TYPE_PACKED_FLOAT32_ARRAY,
		"y": TYPE_PACKED_FLOAT32_ARRAY, "state": TYPE_PACKED_INT32_ARRAY})


func test_name_tags_only_for_live_elites() -> void:
	assert_eq(NameTags.FIRST_LIVE, MobSwarm.STAND)
	assert_eq(NameTags.LAST_LIVE, MobSwarm.HIT)
	var s := _swarm(4)
	s.fields.state = PackedInt32Array([MobSwarm.MOVE, MobSwarm.MOVE, MobSwarm.DIE, MobSwarm.HIT])
	s.fields.kind = PackedInt32Array([0, 1, 0, 1])
	s.fields.x = PackedFloat32Array([10.4, 20, 30, 40])
	s.fields.y = PackedFloat32Array([5, 5, 5, 6.6])
	var tags := NameTags.new()
	tags.update_from(s, PackedByteArray([1, 0, 1, 1]), PackedStringArray(["Snail", "Slime"]))
	assert_eq(tags.tag_count(), 2, "slot 1 is not elite, slot 2 is dying")
	assert_eq(tags.tag(0), {"text": "Snail", "feet": Vector2(10, 5)})
	assert_eq(tags.tag(1), {"text": "Slime", "feet": Vector2(40, 7)}, "whole pixels")
	tags.update_from(s, PackedByteArray([0, 0]), PackedStringArray(["Snail", "Slime"]))
	assert_eq(tags.tag_count(), 0, "a short elite array covers only its slots")
	tags.free()


func test_name_tag_box_under_the_feet() -> void:
	var r := NameTags.box_rect(Vector2(100, 50), 29.5)
	assert_eq(r.size, Vector2(30 + 2 * NameTags.PAD_X, NameTags.BOX_H))
	assert_eq(r.position, Vector2(100 - 18, 50 + NameTags.GAP_Y), "centred on x, just below the feet")
	assert_eq(r.position, r.position.floor())


func test_names_for_kinds_fall_back_to_string_wz() -> void:
	var lib := AssetLibrary.new()
	lib.open(AF.write_cache())
	var named := MobKind.new()
	named.id = 100100
	named.name = "Custom"
	var unnamed := MobKind.new()
	unnamed.id = 210100
	assert_eq(NameTags.names_for([named, unnamed, 100100], lib), PackedStringArray(["Custom", "Slime", "Snail"]))
	lib.free()


func test_hud_exp_messages_stack_fade_and_expire() -> void:
	var hud := Hud.new()
	hud.show_exp(15)
	hud.show_exp(0)
	hud.push_message("Level up!", Color(1, 1, 1))
	var m := hud.messages()
	assert_eq(m.size(), 2, "+0 EXP is not shown")
	assert_eq(m[0].text, "+15 EXP")
	assert_eq(m[0].color, Hud.SYSTEM_YELLOW, "yellow system message")
	assert_eq(m[1].alpha, 1.0)
	hud.advance_messages(Hud.MSG_LIFE - Hud.MSG_FADE * 0.5)
	assert_near(hud.messages()[0].alpha, 0.5, 1e-4, "half way through the fade")
	hud.advance_messages(Hud.MSG_FADE)
	assert_eq(hud.messages().size(), 0, "expired")
	for i in Hud.MSG_MAX + 3:
		hud.show_exp(i + 1)
	m = hud.messages()
	assert_eq(m.size(), Hud.MSG_MAX, "at most MSG_MAX lines")
	assert_eq(m[0].text, "+4 EXP", "the oldest dropped off")
	assert_eq(m[m.size() - 1].text, "+%d EXP" % (Hud.MSG_MAX + 3), "newest last (drawn at the bottom)")
	hud.free()
