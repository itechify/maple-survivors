extends TestCase
## The sixteen-region progression as one list (spec #447, #449, ADR 0007; C14 #476): its exact order, its neighbours and the
## monotone drop bands. The region tests pin their own neighbours; this pins the whole list, so a region inserted anywhere fails here.

const RC := preload("res://tests/region_checks.gd")
const ORDER := ["henesys", "ellinia", "perion", "kerning", "sleepywood", "ludibrium", "omega_sector", "korean_folk_town",
	"mu_lung", "el_nath", "magatia", "zipangu", "leafre", "phantom_forest", "clocktower", "temple_of_time"]


func test_the_progression_is_the_sixteen_regions_in_order() -> void:
	var data := DataRepo.load_all()
	assert_eq(data.stages.progression, ORDER)
	assert_eq(DataRepo.progression_errors(data.stages), PackedStringArray())


func test_every_region_has_exactly_its_neighbours() -> void:
	var progression: Array = DataRepo.load_all().stages.progression
	for i in ORDER.size():
		assert_eq(RC.neighbours(progression, ORDER[i]), [ORDER[i - 1] if i > 0 else "", ORDER[i + 1] if i + 1 < ORDER.size() else ""],
			"%s is step %d" % [ORDER[i], i + 1])


func test_drop_bands_never_fall_along_the_progression() -> void:
	var stages: Dictionary = DataRepo.load_all().stages.stages
	var previous := [-1.0, -1.0]
	for key: String in ORDER:
		var band: Array = stages[key].drop_band
		assert_true(float(band[0]) >= float(previous[0]) and float(band[1]) >= float(previous[1]), "%s %s does not fall below %s" % [key, band, previous])
		assert_true(float(band[0]) < float(band[1]), "%s has an ordered band" % key)
		previous = band
