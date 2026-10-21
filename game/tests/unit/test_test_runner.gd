extends TestCase
## Runner discovery counts declared instance tests and excludes utility methods.


class ThreeTests extends TestCase:
	func test_a() -> void:
		assert_true(true)

	func test_b() -> void:
		assert_true(true)

	func test_c() -> void:
		assert_true(true)

	static func test_static_helper() -> void:
		pass


func test_discovers_only_declared_instance_tests() -> void:
	assert_eq(TestRunner._discover_methods(ThreeTests), ["test_a", "test_b", "test_c"])
