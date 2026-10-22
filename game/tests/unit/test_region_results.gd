extends TestCase
## Results identify the ending map independently of the selected region's first map (#247).

const RESULTS := preload("res://scenes/ui/results_screen.gd")


func test_results_name_the_region_and_ending_map_with_its_own_mark() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	for example: Array in [[false, 104010001, "The Pig Beach"], [true, 100030001, "The Blue Mushroom Forest"]]:
		if lib.img(AssetLibrary.map_img_path(example[1])) == null:
			skip("ending map absent from cache: %d" % example[1])
			return
		var summary := {"stage": "henesys", "region": "Henesys", "continent": "Victoria Island",
			"cleared": example[0], "map_id": example[1], "map_name": example[2]}
		var screen := RESULTS.new()
		assert_true(screen.has_method("location"), "results expose the location they display")
		if screen.has_method("location"):
			var location: Dictionary = screen.call("location", summary)
			assert_eq(location.region, "Henesys")
			assert_eq(location.map_name, example[2])
			assert_eq(location.mark, lib.find(AssetLibrary.map_img_path(example[1]) + "/info/mapMark"))
		screen.free()
