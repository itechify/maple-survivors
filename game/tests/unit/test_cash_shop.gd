extends TestCase
## Buying in the Cash Shop (#118): CashShop.buy deducts the price, adds the item to the account and saves at once;
## unaffordable, already-owned, locked and unlisted items are refused and change nothing. Listings put every unowned item
## on the v83 tab and sub-tab it is filed under (Etc.wz/Category.img via the Commodity SN) and say why a pet upgrade is locked.

const HAT := 1002279 # 3700 NX, SN 20000051: EQUIP. / Hat
const KITTY := 5000000 # 4900 NX pet
const AUTO_HP := 1812002 # 1800 NX, needs a pet
const WING_BOOTS := 1812004
const BINOCULAR := 1812005
const VAC := 9990000 # 20000 NX, needs Wing Boots + Binocular + a pet

var save_path := TestCase.test_dir("cash_shop/save.json")
var _catalog: CashCatalog


func before_each() -> void:
	_catalog = CashCatalog.from_data(DataRepo.load_all())


func after_each() -> void:
	TestCase.remove_tree(save_path.get_base_dir())


func _save(nx: int, owned: Array = []) -> SaveData:
	var save := SaveData.new(save_path)
	assert_eq(save.set_account({"nx": nx, "owned": owned}), OK)
	return save


func test_buying_deducts_the_price_adds_the_item_and_saves_at_once() -> void:
	var save := _save(10000)
	assert_eq(CashShop.buy(save, _catalog, HAT), "")
	assert_eq(save.account.nx, 6300)
	assert_eq(save.account.owned, [HAT])
	var reloaded := SaveData.new(save_path)
	assert_eq(reloaded.account.nx, 6300, "written before buy returns")
	assert_eq(reloaded.account.owned, [HAT])


func test_an_unaffordable_item_is_refused_and_changes_nothing() -> void:
	var save := _save(3699)
	assert_eq(CashShop.buy(save, _catalog, HAT), "nx")
	assert_eq(SaveData.new(save_path).account, {"nx": 3699, "owned": []})
	assert_eq(save.account, {"nx": 3699, "owned": []})


func test_an_exact_balance_buys_and_leaves_zero() -> void:
	var save := _save(3700)
	assert_eq(CashShop.buy(save, _catalog, HAT), "")
	assert_eq(save.account.nx, 0)


func test_an_owned_item_cannot_be_bought_twice() -> void:
	var save := _save(99999, [HAT])
	assert_eq(CashShop.buy(save, _catalog, HAT), "owned")
	assert_eq(SaveData.new(save_path).account, {"nx": 99999, "owned": [HAT]})


func test_a_pet_upgrade_is_locked_until_a_pet_is_owned() -> void:
	var save := _save(99999)
	assert_eq(CashShop.buy(save, _catalog, AUTO_HP), "locked")
	assert_eq(save.account, {"nx": 99999, "owned": []})
	assert_eq(CashShop.buy(save, _catalog, KITTY), "")
	assert_eq(CashShop.buy(save, _catalog, AUTO_HP), "")
	assert_eq(save.account, {"nx": 99999 - 4900 - 1800, "owned": [KITTY, AUTO_HP]})


func test_vac_needs_wing_boots_and_binocular_as_well_as_a_pet() -> void:
	var save := _save(99999, [KITTY, WING_BOOTS])
	assert_eq(CashShop.buy(save, _catalog, VAC), "locked", "Binocular missing")
	save = _save(99999, [KITTY, WING_BOOTS, BINOCULAR])
	assert_eq(CashShop.buy(save, _catalog, VAC), "")


func test_an_unlisted_item_is_refused() -> void:
	var save := _save(99999)
	assert_eq(CashShop.buy(save, _catalog, 1302000), "unlisted", "a Beginner sword is not for sale")
	assert_eq(save.account, {"nx": 99999, "owned": []})


func test_a_failed_save_leaves_the_account_unchanged() -> void:
	var save := _save(10000)
	var blocker := FileAccess.open(save_path.get_base_dir().path_join("blocker"), FileAccess.WRITE)
	blocker.close()
	save.path = save_path.get_base_dir().path_join("blocker/save.json") # a file where the folder must be, so the write fails
	assert_ne(CashShop.buy(save, _catalog, HAT), "")
	assert_eq(save.account, {"nx": 10000, "owned": []})


func test_every_message_is_v83_notice_text() -> void:
	assert_eq(CashShop.message("nx"), "You don't have enough NX.")
	for reason: String in ["owned", "locked", "unlisted", "save"]:
		assert_ne(CashShop.message(reason), "", reason)


func test_listing_files_items_under_their_v83_tab_and_sub_tab_and_drops_owned_ones() -> void:
	var hats := CashShop.listing(_catalog, [], "equip", "Hat")
	assert_eq(hats.size(), 10)
	assert_true(hats.has(HAT))
	assert_false(CashShop.listing(_catalog, [HAT], "equip", "Hat").has(HAT), "bought items leave the list")
	assert_true(CashShop.listing(_catalog, [], "equip", "Face").has(1032029), "earrings are filed under Face (SN 2/1)")
	assert_true(CashShop.listing(_catalog, [], "equip", "Weapon").has(1092031), "shields are filed under Weapon (SN 2/8)")
	assert_eq(CashShop.listing(_catalog, [], "pet", "Pet"), [5000000, 5000001, 5000002])
	var upgrades := CashShop.listing(_catalog, [], "pet", "Pet Equip.")
	assert_eq(upgrades, [1812002, 1812004, 1812005, VAC], "VAC has no SN and goes last (no Auto MP Pouch, #285)")


func test_every_equipment_item_is_on_a_listed_sub_tab() -> void:
	var seen := 0
	for tab: Dictionary in CashShop.tabs():
		for sub: String in tab.subs:
			seen += CashShop.listing(_catalog, [], tab.key, sub).size()
	assert_eq(seen, _catalog.ids().size())


func test_lock_reasons_explain_what_is_missing() -> void:
	var name_of := func(id: int) -> String: return {WING_BOOTS: "Wing Boots", BINOCULAR: "Binocular"}.get(id, str(id))
	assert_eq(CashShop.lock_reasons(_catalog, [], AUTO_HP, name_of), PackedStringArray(["Needs a pet."]))
	assert_eq(CashShop.lock_reasons(_catalog, [KITTY], AUTO_HP, name_of), PackedStringArray())
	assert_eq(CashShop.lock_reasons(_catalog, [], VAC, name_of),
		PackedStringArray(["Needs Wing Boots.", "Needs Binocular.", "Needs a pet."]))
	assert_eq(CashShop.lock_reasons(_catalog, [KITTY, BINOCULAR], VAC, name_of), PackedStringArray(["Needs Wing Boots."]))
	assert_eq(CashShop.lock_reasons(_catalog, [], HAT, name_of), PackedStringArray())


func test_trying_on_replaces_what_the_new_item_covers() -> void:
	var overall := 1052013
	var cash := CashShop.try_on(_catalog, {}, HAT)
	assert_eq(cash, {"hat": HAT})
	cash = CashShop.try_on(_catalog, cash, overall)
	assert_eq(cash, {"hat": HAT, "top": overall, "bottom": overall}, "an overall fills top and bottom")
	var top: int = CashShop.listing(_catalog, [], "equip", "Top")[0]
	cash = CashShop.try_on(_catalog, cash, top)
	assert_eq(cash, {"hat": HAT, "top": top}, "a top replaces the overall, which also leaves the bottom slot")
	cash = CashShop.try_on(_catalog, cash, HAT)
	assert_eq(cash, {"hat": HAT, "top": top}, "the same item again changes nothing")
	assert_eq(CashShop.try_on(_catalog, cash, KITTY), cash, "a pet is not worn on the avatar")


func test_icon_paths_follow_the_item_type() -> void:
	assert_eq(CashShop.icon_path(_catalog, HAT), "Character.wz/Cap/01002279.img/info/icon")
	assert_eq(CashShop.icon_path(_catalog, 1032029), "Character.wz/Accessory/01032029.img/info/icon")
	assert_eq(CashShop.icon_path(_catalog, 1052013), "Character.wz/Longcoat/01052013.img/info/icon")
	assert_eq(CashShop.icon_path(_catalog, KITTY), "Item.wz/Pet/5000000.img/info/icon")
	assert_eq(CashShop.icon_path(_catalog, AUTO_HP), "Character.wz/PetEquip/01812002.img/info/icon")
	assert_eq(CashShop.icon_path(_catalog, VAC), "Character.wz/PetEquip/01812000.img/info/icon", "VAC shares the Magnet art")


func test_names_and_descriptions_come_from_the_string_files_or_the_survivor_entry() -> void:
	assert_eq(CashShop.item_name(null, _catalog, VAC), "VAC")
	assert_true(CashShop.item_desc(null, _catalog, VAC).begins_with("Your pet pulls every drop"))
	assert_eq(CashShop.item_name(null, _catalog, HAT), "", "no cache, no String.wz name")
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	assert_eq(CashShop.item_name(lib, _catalog, KITTY), "Brown Kitty")
	assert_ne(CashShop.item_name(lib, _catalog, HAT), "")
	assert_ne(CashShop.item_name(lib, _catalog, AUTO_HP), "")
	assert_ne(CashShop.item_desc(lib, _catalog, AUTO_HP), "")
