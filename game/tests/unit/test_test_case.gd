extends TestCase
## Numeric assertion helpers must reject invalid numbers without weakening finite boundary checks.


func test_near_rejects_non_finite_values() -> void:
	for value: float in [NAN, INF, -INF]:
		var tc := TestCase.new()
		tc.assert_near(value, 1.0)
		tc.assert_near(1.0, value)
		tc.assert_near(value, value)
		assert_eq(tc.failures.size(), 3, "non-finite operand %s" % value)


func test_near_rejects_invalid_tolerance() -> void:
	for eps: float in [NAN, INF, -INF, -0.01]:
		var tc := TestCase.new()
		tc.assert_near(1.0, 1.0, eps)
		assert_eq(tc.failures.size(), 1, "invalid tolerance %s" % eps)


func test_near_preserves_finite_boundaries() -> void:
	var tc := TestCase.new()
	tc.assert_near(1.0, 1.0, 0.0)
	tc.assert_near(0.75, 1.0, 0.25)
	tc.assert_near(1.25, 1.0, 0.25)
	assert_true(tc.failures.is_empty(), "zero tolerance and inclusive endpoints")
	tc.assert_near(1.5, 1.0, 0.25)
	assert_eq(tc.failures.size(), 1, "finite value outside tolerance")


func test_between_rejects_non_finite_values_and_bounds() -> void:
	for value: float in [NAN, INF, -INF]:
		var tc := TestCase.new()
		tc.assert_between(value, 0.0, 1.0)
		tc.assert_between(0.5, value, 1.0)
		tc.assert_between(0.5, 0.0, value)
		assert_eq(tc.failures.size(), 3, "non-finite operand/bound %s" % value)


func test_between_rejects_reversed_bounds() -> void:
	var tc := TestCase.new()
	tc.assert_between(0.5, 1.0, 0.0)
	assert_eq(tc.failures.size(), 1)


func test_between_preserves_finite_boundaries() -> void:
	var tc := TestCase.new()
	for value: float in [0.0, 0.5, 1.0]:
		tc.assert_between(value, 0.0, 1.0)
	tc.assert_between(1.0, 1.0, 1.0)
	assert_true(tc.failures.is_empty(), "inclusive and equal bounds")
	tc.assert_between(-0.5, 0.0, 1.0)
	tc.assert_between(1.5, 0.0, 1.0)
	assert_eq(tc.failures.size(), 2, "finite values outside the interval")
