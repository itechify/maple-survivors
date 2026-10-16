extends TestCase
## Restoration-number kinds render from the player's cached v83 BasicEff art and expire through the shared pool.


func test_hp_and_mp_gain_numbers_render_and_expire() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	var numbers := DamageNumbers.new()
	numbers.library = lib
	assert_true(numbers.spawn(123, Vector2(100, 200), DamageNumbers.HP_GAIN) >= 0)
	assert_true(numbers.spawn(45, Vector2(200, 200), DamageNumbers.MP_GAIN) >= 0)
	assert_eq(numbers.active_count(), 2)
	numbers.advance(0.7)
	assert_eq(numbers.active_count(), 2)
	numbers.advance(0.4)
	assert_eq(numbers.active_count(), 0)
	assert_true(lib.missing.is_empty())
	numbers.free()
	lib.free()
