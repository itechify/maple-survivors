extends TestCase
## Avatar rendering of cash equipment on synthetic layer data (spec #34, ticket #117): expression-keyed face
## accessories, weapon cover type selection and fallback (UOL aliases included), vslot hiding through smap.img, and a
## cash overall replacing the top and bottom. Every canvas carries a marker in its atlas x so a test can tell which
## frame was chosen; nothing here needs the asset cache.

const BODY := 2000
const HEAD := 12000
const FACE := 20000
const HAIR := 30030
const COAT := 1040002
const PANTS := 1060002
const SHOES := 1072001
const SWORD := 1302000
const WAND := 1372005
const COVER := 1702134
const SHIELD_COVER := 1702004 # two-handed: stored under weapon and shield
const FACE_ACC := 1012000
const EYE_ACC := 1022000
const CAP := 1002279
const FULL_HEAD_CAP := 1002544
const CASH_COAT := 1042000
const CASH_OVERALL := 1052001
const CASH_PANTS := 1062003
const CASH_SHIELD := 1092031

const SMAP := {"body": "Bd", "head": "Hd", "face": "Fc", "hair": "H2", "hairOverHead": "H1", "backHair": "H1",
	"hairShade": "Hs", "cap": "CpHdH1H2H3H4H5H6HsHfHbAfAyAsAe", "mailChest": "MaGw", "mailArm": "MaGw",
	"pants": "PnSo", "shoes": "So", "weapon": "Wp", "shield": "Si", "accessoryFace": "Af", "accessoryEye": "Ay",
	"mobEquipFront": null}
const ZMAP := ["shield", "weapon", "hairOverHead", "cap", "hair", "accessoryFace", "accessoryEye", "face", "head",
	"mailArm", "mailChest", "shoes", "pants", "body"]


class FakeLibrary:
	extends AssetLibrary
	var images := {}

	func img(path: String) -> WzImg:
		return images.get(path)


var lib: FakeLibrary
var avatar: AvatarRenderer


func before_each() -> void:
	lib = FakeLibrary.new()
	var zmap := {}
	for z in ZMAP:
		zmap[z] = null
	lib.images["Base.wz/zmap.img"] = _wz(zmap)
	lib.images["Base.wz/smap.img"] = _wz(SMAP)
	lib.images[_path(BODY)] = _wz({"stand1": {"0": {"body": _c("body", 1)}}, "walk1": {"0": {"body": _c("body", 1)}},
		"ladder": {"0": {"body": _c("body", 1), "face": 0}}})
	lib.images[_path(HEAD)] = _wz({"front": {"head": _c("head", 2)}, "back": {"head": _c("head", 2)}})
	lib.images[_path(FACE)] = _wz({"default": {"face": _c("face", 3)}, "blink": {"0": {"face": _c("face", 4)}}})
	lib.images[_path(HAIR)] = _wz({"default": {"hair": _c("hair", 5), "hairOverHead": _c("hairOverHead", 6)}})
	lib.images[_path(COAT)] = _wz({"stand1": {"0": {"mailChest": _c("mailChest", 7)}}}, "Ma")
	lib.images[_path(PANTS)] = _wz({"stand1": {"0": {"pants": _c("pants", 8)}}}, "Pn")
	lib.images[_path(SHOES)] = _wz({"stand1": {"0": {"shoes": _c("shoes", 9)}}}, "So")
	lib.images[_path(SWORD)] = _wz({"stand1": {"0": {"weapon": _c("weapon", 10)}}}, "Wp")
	lib.images[_path(WAND)] = _wz({"stand1": {"0": {"weapon": _c("weapon", 11)}}}, "Wp")
	avatar = AvatarRenderer.new()
	avatar.library = lib


func after_each() -> void:
	avatar.free()
	lib.free()


func _path(id: int) -> String:
	return AvatarRenderer.part_img_path(id)


func _c(z: String, marker: int) -> Dictionary:
	return {"$canvas": [0, marker, 0, 4, 4], "origin": {"$v": [0, 0]}, "z": z}


func _wz(root: Dictionary, vslot: String = "") -> WzImg:
	var tree := root.duplicate(true)
	if vslot != "":
		tree["info"] = {"vslot": vslot}
	return WzImg.new("synthetic", tree)


func _look(equips: Array, cash: Dictionary = {}) -> Dictionary:
	return {"skin": 0, "face": FACE, "hair": HAIR, "equips": equips, "cash": cash}


func _compose(look: Dictionary, stance: String = "stand1", expression: String = "default",
		expr_t: float = 0.0) -> Array:
	avatar.set_look(look)
	return avatar.compose(stance, 0, expression, expr_t)


func _markers(parts: Array) -> Array:
	var out: Array = []
	for p: Dictionary in parts:
		out.append(int(p.frame.region.position.x))
	out.sort()
	return out


func _owned_by(parts: Array, id: int) -> Array:
	return parts.filter(func(p: Dictionary) -> bool: return int(p.get("owner", 0)) == id)


# ---------------------------------------------------------------------------------------------------------------------
# Pure helpers

func test_weapon_type_is_the_item_category_minus_100() -> void:
	assert_eq(AvatarLayers.weapon_type(SWORD), 30)
	assert_eq(AvatarLayers.weapon_type(WAND), 37)
	assert_eq(AvatarLayers.weapon_type(1382000), 38, "staff")
	assert_eq(AvatarLayers.weapon_type(1402000), 40, "two-handed sword")
	assert_eq(AvatarLayers.weapon_type(COVER), 0, "a cash cover is not a weapon type")
	assert_eq(AvatarLayers.weapon_type(COAT), 0)


func test_codes_split_into_two_letter_slots() -> void:
	assert_eq(AvatarLayers.codes("CpH1H5"), PackedStringArray(["Cp", "H1", "H5"]))
	assert_eq(AvatarLayers.codes(""), PackedStringArray())
	assert_eq(AvatarLayers.codes("Wp"), PackedStringArray(["Wp"]))


func test_a_layer_is_hidden_only_when_every_code_is_covered() -> void:
	var hiding := {"Ma": true, "Pn": true}
	assert_true(AvatarLayers.is_hidden("Ma", hiding))
	assert_false(AvatarLayers.is_hidden("MaGw", hiding), "the sleeves also hold Gw: only an item taking both hides them")
	assert_false(AvatarLayers.is_hidden("PnSo", hiding), "pants share the shoes code")
	assert_false(AvatarLayers.is_hidden("", hiding), "a layer with no slot code is never hidden")


# ---------------------------------------------------------------------------------------------------------------------
# Face accessories follow the face expression

func _face_acc_img() -> WzImg:
	return _wz({"default": {"accessoryFace": _c("accessoryFace", 20)},
		"blink": {"0": {"accessoryFace": _c("accessoryFace", 21)}, "1": {"accessoryFace": _c("accessoryFace", 22)}}}, "Af")


func test_face_accessory_follows_the_expression_and_its_frame() -> void:
	lib.images[_path(1012000)] = _face_acc_img()
	lib.images[_path(FACE)] = _wz({"default": {"face": _c("face", 3)},
		"blink": {"0": {"face": _c("face", 4), "delay": 50}, "1": {"face": _c("face", 4), "delay": 50}}})
	var look := _look([], {"face": 1012000})
	assert_true(20 in _markers(_compose(look)), "default expression: the accessory's default")
	assert_true(21 in _markers(_compose(look, "stand1", "blink", 0.0)), "blink frame 0")
	assert_true(22 in _markers(_compose(look, "stand1", "blink", 0.07)), "blink frame 1 at 70 ms")
	assert_false(20 in _markers(_compose(look, "stand1", "blink", 0.0)), "not the default art while blinking")


func test_face_accessory_falls_back_to_default_for_an_expression_it_lacks() -> void:
	lib.images[_path(1012000)] = _face_acc_img()
	lib.images[_path(FACE)] = _wz({"default": {"face": _c("face", 3)}, "smile": {"0": {"face": _c("face", 4)}}})
	assert_true(20 in _markers(_compose(_look([], {"face": 1012000}), "stand1", "smile")))


func test_face_accessory_is_hidden_with_the_face_on_a_ladder() -> void:
	lib.images[_path(1012000)] = _face_acc_img()
	var parts := _compose(_look([], {"face": 1012000}), "ladder")
	assert_eq(_owned_by(parts, 1012000).size(), 0, "frames with face = 0 hide the face and its accessory")


func test_eye_accessory_uses_default_when_the_stance_is_missing() -> void:
	lib.images[_path(EYE_ACC)] = _wz({"default": {"accessoryEye": _c("accessoryEye", 30)},
		"stand1": {"0": {"accessoryEye": _c("accessoryEye", 31)}}}, "Ay")
	var look := _look([], {"eye": EYE_ACC})
	assert_true(31 in _markers(_compose(look)), "the stance's own art")
	assert_true(30 in _markers(_compose(look, "walk1")), "no walk1: the default frame")
	assert_eq(_owned_by(_compose(look, "ladder"), EYE_ACC).size(), 0, "back stances use backDefault, which it lacks")


# ---------------------------------------------------------------------------------------------------------------------
# Weapon covers

func _cover_img(types: Array, aliased: Array = []) -> WzImg:
	var root := {}
	for t: int in types:
		root[str(t)] = {"stand1": {"0": {"weapon": _c("weapon", 40 + t)}}}
	for t: int in aliased:
		root[str(t)] = {"stand1": {"$uol": "../%d/stand1" % types[0]}}
	return _wz(root, "Wp")


func test_cover_draws_the_stance_set_of_the_weapon_type() -> void:
	lib.images[_path(COVER)] = _cover_img([30, 37])
	var sword := _compose(_look([COAT, SWORD], {"weapon": COVER}))
	assert_true(70 in _markers(sword) and not 77 in _markers(sword), "a sword wearer gets the 30 art")
	assert_false(10 in _markers(sword), "the real sword is replaced")
	var wand := _compose(_look([COAT, WAND], {"weapon": COVER}))
	assert_true(77 in _markers(wand) and not 70 in _markers(wand), "a wand wearer gets the 37 art")
	assert_false(11 in _markers(wand), "the real wand is replaced")


func test_cover_without_art_for_the_type_leaves_the_real_weapon() -> void:
	lib.images[_path(COVER)] = _cover_img([37, 38])
	var parts := _compose(_look([COAT, SWORD], {"weapon": COVER}))
	assert_true(10 in _markers(parts), "no 30 art: the real sword is drawn")
	assert_eq(_owned_by(parts, COVER).size(), 0, "nothing of the cover")


func test_cover_without_art_for_the_stance_leaves_the_real_weapon() -> void:
	lib.images[_path(COVER)] = _cover_img([37])
	lib.images[_path(WAND)] = _wz({"stand1": {"0": {"weapon": _c("weapon", 11)}},
		"walk1": {"0": {"weapon": _c("weapon", 12)}}}, "Wp")
	var parts := _compose(_look([WAND], {"weapon": COVER}), "walk1")
	assert_true(12 in _markers(parts), "the cover has no walk1: the real wand")
	assert_eq(_owned_by(parts, COVER).size(), 0)


func test_cover_follows_uol_aliases_between_types() -> void:
	lib.images[_path(COVER)] = _cover_img([30], [37])
	var parts := _compose(_look([WAND], {"weapon": COVER}))
	assert_true(70 in _markers(parts), "37/stand1 is a link to ../30/stand1 and resolves to its art")
	assert_false(11 in _markers(parts))


func test_cover_draws_nothing_without_a_real_weapon() -> void:
	lib.images[_path(COVER)] = _cover_img([30, 37])
	assert_eq(_owned_by(_compose(_look([COAT], {"weapon": COVER})), COVER).size(), 0, "there is nothing to cover")


func test_two_handed_cover_is_drawn_once_and_replaces_a_shield() -> void:
	lib.images[_path(SHIELD_COVER)] = _cover_img([30])
	lib.images[_path(1092000)] = _wz({"stand1": {"0": {"shield": _c("shield", 50)}}}, "Si")
	var parts := _compose(_look([SWORD, 1092000], {"weapon": SHIELD_COVER, "shield": SHIELD_COVER}))
	assert_eq(_owned_by(parts, SHIELD_COVER).size(), 1, "stored under weapon and shield, drawn once")
	assert_false(50 in _markers(parts), "the regular shield slot is taken by the cash entry")


func test_a_worn_regular_shield_is_drawn_beside_a_one_handed_weapon_and_a_cash_shield_replaces_it() -> void:
	# #158: the shield equip slot's item reaches the avatar through the look's `equips` (Equipment.worn_ids).
	lib.images[_path(1092000)] = _wz({"stand1": {"0": {"shield": _c("shield", 50)}}}, "Si")
	lib.images[_path(CASH_SHIELD)] = _wz({"stand1": {"0": {"shield": _c("shield", 51)}}}, "Si")
	var worn := Equipment.worn_ids({"top": {"id": COAT}, "weapon": {"id": SWORD}, "shield": {"id": 1092000}})
	assert_eq(worn, [COAT, SWORD, 1092000], "the shield is listed after the weapon")
	var parts := _compose(_look(worn))
	assert_true(50 in _markers(parts), "the shield layer is drawn")
	assert_true(10 in _markers(parts), "and the sword with it")
	var cash := _markers(_compose(_look(worn, {"shield": CASH_SHIELD})))
	assert_false(50 in cash, "a worn cash shield takes the regular shield's place")
	assert_true(51 in cash)


func test_cash_shield_is_drawn() -> void:
	lib.images[_path(CASH_SHIELD)] = _wz({"stand1": {"0": {"shield": _c("shield", 51)}}}, "Si")
	assert_true(51 in _markers(_compose(_look([COAT, SWORD], {"shield": CASH_SHIELD}))))


# ---------------------------------------------------------------------------------------------------------------------
# vslot hiding through smap.img

func _cap_img(vslot: String) -> WzImg:
	return _wz({"default": {"default": _c("cap", 60)}, "backDefault": {"default": _c("backCap", 61)}}, vslot)


func test_hat_hides_the_hair_layers_its_vslot_names() -> void:
	lib.images[_path(CAP)] = _cap_img("CpH1H5")
	var parts := _compose(_look([COAT], {"hat": CAP}))
	assert_true(60 in _markers(parts), "the hat")
	assert_false(6 in _markers(parts), "hairOverHead is H1: hidden")
	assert_true(5 in _markers(parts), "hair is H2: still drawn")
	assert_true(2 in _markers(parts), "the head stays")


func test_full_head_hat_hides_head_hair_and_accessories() -> void:
	lib.images[_path(FULL_HEAD_CAP)] = _cap_img("CpHdH1H2H3H4H5H6HsHfHbAfAyAsAe")
	lib.images[_path(1012000)] = _face_acc_img()
	var parts := _compose(_look([], {"hat": FULL_HEAD_CAP, "face": 1012000}))
	assert_true(60 in _markers(parts), "the cap itself is not hidden by its own vslot")
	assert_false(2 in _markers(parts), "head (Hd)")
	assert_false(5 in _markers(parts) or 6 in _markers(parts), "hair (H1, H2)")
	assert_false(20 in _markers(parts), "the face accessory (Af)")
	assert_true(3 in _markers(parts), "the face has no code in the hat's vslot")


func test_a_glove_vslot_does_not_hide_sleeves() -> void:
	lib.images[_path(1082040)] = _wz({"stand1": {"0": {"glove": _c("glove", 70)}}}, "GlGw")
	lib.images[_path(COAT)] = _wz({"stand1": {"0": {"mailChest": _c("mailChest", 7), "mailArm": _c("mailArm", 71)}}}, "Ma")
	var parts := _compose(_look([COAT], {"gloves": 1082040}))
	assert_true(71 in _markers(parts), "mailArm holds Ma and Gw: it needs both to be hidden")


func test_hair_below_cap_layers_still_need_a_hat() -> void:
	lib.images[_path(HAIR)] = _wz({"default": {"hair": _c("hair", 5), "hairBelowCap": _c("backHairBelowCap", 8)}})
	assert_false(8 in _markers(_compose(_look([]))), "no hat: the BelowCap layers are skipped")
	lib.images[_path(CAP)] = _cap_img("CpH1H5")
	assert_true(8 in _markers(_compose(_look([], {"hat": CAP}))), "a cash hat counts as a hat")


# ---------------------------------------------------------------------------------------------------------------------
# Cash replaces the regular equipment of its slot; an overall replaces top and bottom

func test_cash_top_replaces_the_regular_top_but_keeps_the_rest() -> void:
	lib.images[_path(CASH_COAT)] = _wz({"stand1": {"0": {"mailChest": _c("mailChest", 80)}}}, "Ma")
	var parts := _compose(_look([COAT, PANTS, SHOES], {"top": CASH_COAT}))
	assert_true(80 in _markers(parts))
	assert_false(7 in _markers(parts), "the regular coat is replaced")
	assert_true(8 in _markers(parts) and 9 in _markers(parts), "pants and shoes stay")


func test_cash_overall_replaces_the_top_and_the_bottom() -> void:
	lib.images[_path(CASH_OVERALL)] = _wz({"stand1": {"0": {"mailChest": _c("mailChest", 81)}}}, "MaPn")
	var parts := _compose(_look([COAT, PANTS, SHOES], {"top": CASH_OVERALL, "bottom": CASH_OVERALL}))
	assert_eq(_owned_by(parts, CASH_OVERALL).size(), 1, "stored under top and bottom, drawn once")
	assert_false(7 in _markers(parts), "the regular coat is replaced")
	assert_false(8 in _markers(parts), "the regular pants are replaced")
	assert_true(9 in _markers(parts), "shoes stay")


func test_a_cash_top_whose_vslot_includes_pn_replaces_the_pants_too() -> void:
	lib.images[_path(1042186)] = _wz({"stand1": {"0": {"mailChest": _c("mailChest", 83)}}}, "MaPn")
	var parts := _compose(_look([COAT, PANTS, SHOES], {"top": 1042186}))
	assert_true(83 in _markers(parts))
	assert_false(7 in _markers(parts) or 8 in _markers(parts), "the vest takes the coat and the pants slots")
	assert_true(9 in _markers(parts), "shoes (So) are not inside MaPn")
	assert_true(AvatarLayers.replaced_by_vslot(PANTS, {"Pn": true}, {"Ma": true, "Pn": true}))
	assert_false(AvatarLayers.replaced_by_vslot(SWORD, {"Wp": true}, {"Wp": true}), "weapons follow the cover rule")
	assert_false(AvatarLayers.replaced_by_vslot(SHOES, {}, {"So": true}), "an item without a vslot is never replaced")


func test_items_do_not_pool_their_vslot_codes_to_hide_a_layer() -> void:
	# A hat holding Pn (artificial) and the shoes holding So are two items: neither alone covers the pants PnSo.
	lib.images[_path(CAP)] = _cap_img("CpPn")
	lib.images[_path(PANTS)] = _wz({"stand1": {"0": {"pants": _c("pants", 8)}}}) # no vslot of its own
	var parts := _compose(_look([PANTS, SHOES], {"hat": CAP}))
	assert_true(8 in _markers(parts), "pants layer PnSo needs Pn and So from a single item")


func test_cash_bottom_replaces_regular_pants() -> void:
	lib.images[_path(CASH_PANTS)] = _wz({"stand1": {"0": {"pants": _c("pants", 82)}}}, "Pn")
	var parts := _compose(_look([COAT, PANTS], {"bottom": CASH_PANTS}))
	assert_true(82 in _markers(parts) and not 8 in _markers(parts))
	assert_true(7 in _markers(parts))


func test_cash_over_the_regular_slot_by_category() -> void:
	assert_true(AvatarLayers.suppressed_by_cash(COAT, {"top": CASH_OVERALL, "bottom": CASH_OVERALL}))
	assert_true(AvatarLayers.suppressed_by_cash(PANTS, {"bottom": CASH_PANTS}))
	assert_true(AvatarLayers.suppressed_by_cash(1050001, {"top": CASH_COAT}), "a regular overall sits in the coat slot")
	assert_false(AvatarLayers.suppressed_by_cash(SHOES, {"top": CASH_COAT}))
	assert_false(AvatarLayers.suppressed_by_cash(SWORD, {"weapon": COVER}), "weapons are decided per stance")
	assert_false(AvatarLayers.suppressed_by_cash(COAT, {}))


func test_no_cash_draws_exactly_what_the_look_always_drew() -> void:
	var plain := _compose({"skin": 0, "face": FACE, "hair": HAIR, "equips": [COAT, PANTS, SHOES, SWORD]})
	assert_eq(_markers(plain), [1, 2, 3, 5, 6, 7, 8, 9, 10], "body, head, face, hair (no BelowCap), coat, pants, shoes, sword")


# ---------------------------------------------------------------------------------------------------------------------
# The look a screen draws carries only the cash equipment the account owns

func test_character_look_carries_worn_cash_only_when_given() -> void:
	var data := DataRepo.load_all()
	var character := {"job_id": 0, "look": {}, "cash": {"hat": CAP}}
	assert_false(DataRepo.character_look(character, data).has("cash"), "no worn cash given: the look is what it always was")
	var look := DataRepo.character_look(character, data, {"hat": CAP})
	assert_eq(look.cash, {"hat": CAP})


func test_worn_cash_filters_the_snapshot_by_account_ownership() -> void:
	var data := DataRepo.load_all()
	var character := {"cash": {"hat": 1002279, "top": 1052001, "bottom": 1052001, "shoes": 1072010}}
	var worn := DataRepo.worn_cash(character, data, [1002279, 1052001])
	assert_eq(worn, {"hat": 1002279, "top": 1052001, "bottom": 1052001}, "the unowned shoes are not drawn")
	assert_eq(DataRepo.worn_cash({}, data, [1002279]), {}, "a character without cash wears none")
