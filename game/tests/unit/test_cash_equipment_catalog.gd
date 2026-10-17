extends TestCase
## The curated cash equipment catalog (spec #34, ticket #117): 6-10 unisex v83 items per slot at their real
## Commodity.img prices and serial numbers, all exported by the asset manifest. The Commodity/Character checks need the
## asset cache and SKIP without it.

## Catalog groups by id / 10000 (an overall is a group of its own: it fills top and bottom).
const GROUPS := {100: "hat", 101: "face", 102: "eye", 103: "earrings", 104: "top", 105: "overall", 106: "bottom",
	107: "shoes", 108: "gloves", 109: "shield", 110: "cape", 170: "weapon cover"}


func _equip_items() -> Array:
	var out: Array = []
	for item: Dictionary in DataRepo.load_all().cash_items.items:
		if String(item.kind) == "equip":
			out.append(item)
	return out


func _manifest_ids() -> Array:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/asset_manifest.json"))
	return manifest.character.map(func(id: Variant) -> int: return int(id))


func test_every_slot_has_six_to_ten_items() -> void:
	var counts := {}
	for item: Dictionary in _equip_items():
		@warning_ignore("integer_division")
		var group := int(item.id) / 10000
		counts[group] = int(counts.get(group, 0)) + 1
	for group: int in GROUPS:
		var n := int(counts.get(group, 0))
		assert_between(n, 6, 10, "%s items" % GROUPS[group])
	assert_eq(counts.size(), GROUPS.size(), "no item outside the twelve groups (rings are not cash slots)")


func test_items_are_unisex_priced_and_have_a_serial_number() -> void:
	var seen := {}
	for item: Dictionary in _equip_items():
		var id := int(item.id)
		assert_false(seen.has(id), "%d listed once" % id)
		seen[id] = true
		@warning_ignore("integer_division")
		assert_true((id / 1000) % 10 >= 2, "%d: unisex id (thousands digit >= 2, tier C)" % id)
		assert_true(int(item.price) > 0 and int(item.sn) > 0, "%d has a price and a Commodity SN" % id)
		assert_false(item.has("requires") or item.has("requires_any"), "%d has no prerequisites" % id)
		if bool(item.get("two_handed", false)):
			@warning_ignore("integer_division")
			assert_eq(id / 10000, 170, "%d: two_handed is for weapon covers" % id)


func test_two_handed_covers_are_flagged_from_their_vslot() -> void:
	var flagged: Array = []
	for item: Dictionary in _equip_items():
		if bool(item.get("two_handed", false)):
			flagged.append(int(item.id))
	flagged.sort()
	assert_eq(flagged, [1702004, 1702042, 1702078], "vslot WpSi covers (tier C inference)")


func test_every_curated_item_is_in_the_asset_manifest() -> void:
	var ids := _manifest_ids()
	for item: Dictionary in _equip_items():
		assert_true(int(item.id) in ids, "%d exported by the manifest" % int(item.id))


func test_prices_and_serial_numbers_match_commodity_img() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	var commodity := lib.img("Etc.wz/Commodity.img")
	if commodity == null:
		skip("Etc.wz/Commodity.img is not in this asset cache (re-import with the current manifest)")
		return
	var by_sn := {}
	for key: Variant in commodity.root.keys():
		var row: Variant = commodity.root[key]
		if row is Dictionary and (row as Dictionary).has("SN"):
			by_sn[int(row.SN)] = row
	for item: Dictionary in _equip_items():
		var row: Variant = by_sn.get(int(item.sn))
		assert_true(row != null, "%d: SN %d is in Commodity.img" % [int(item.id), int(item.sn)])
		if row == null:
			continue
		assert_eq(int(row.ItemId), int(item.id), "%d: Commodity ItemId of SN %d" % [int(item.id), int(item.sn)])
		assert_eq(int(row.Price), int(item.price), "%d: Commodity Price (tier A)" % int(item.id))
		assert_eq(int(row.OnSale), 1, "%d: on sale" % int(item.id))


func test_every_curated_item_draws_standing_and_walking_in_the_cache() -> void:
	if not require_cache():
		return
	var catalog := CashCatalog.from_data(DataRepo.load_all())
	for item: Dictionary in _equip_items():
		var id := int(item.id)
		var cash := {}
		for slot in catalog.slots_for(id):
			cash[slot] = id
		var avatar := AvatarRenderer.new()
		# A Magician's wand: every curated cover has 37 art (the sword's type 30 is only in some).
		avatar.set_look({"equips": [1040002, 1060002, 1072001, 1372005], "cash": cash})
		for stance in ["stand1", "walk1"]:
			var drawn := avatar.compose(stance, 0).filter(func(p: Dictionary) -> bool: return int(p.owner) == id)
			assert_false(drawn.is_empty(), "%d draws in %s" % [id, stance])
		assert_eq(avatar.missing, PackedStringArray(), "%d: nothing missing from the cache" % id)
		avatar.free()


func test_items_have_sprites_names_and_no_requirements_in_the_cache() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	for item: Dictionary in _equip_items():
		var id := int(item.id)
		var w := lib.img(AvatarRenderer.part_img_path(id))
		assert_true(w != null, "%d: img in the cache" % id)
		if w == null:
			continue
		var info: Dictionary = w.root.get("info", {})
		assert_eq(int(info.get("cash", 0)), 1, "%d: a cash item" % id)
		assert_eq(int(info.get("reqLevel", 0)), 0, "%d: no level requirement" % id)
		assert_true(info.get("vslot", "") is String and String(info.vslot) != "", "%d has a vslot" % id)
		assert_true(w.root.size() > 3, "%d has art besides info" % id)
		assert_ne(lib.string_name("Eqp", id), "", "%d has a String.wz name" % id)
