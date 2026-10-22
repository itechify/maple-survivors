extends TestCase
## Automation evidence must stay bounded when a life-list pool contains many projectile-firing ordinary mobs.


## Repeated volleys keep their first-ball evidence without scheduling a PNG for every projectile.
func test_projectile_swarm_requests_one_first_ball_capture_for_the_round() -> void:
	var scene := RunScene.new()
	scene._shots_dir = test_dir("shots")
	var volley: Array = []
	for i in 64:
		volley.append({"type": "mob_projectile_spawned"})
	scene.handle_events(volley)
	assert_eq(scene._timed_shots.size(), 1, "a volley must not encode the same PNG once per projectile")
	if not scene._timed_shots.is_empty():
		assert_eq(scene._timed_shots[0][1], "mob_projectile.png")
		assert_near(float(scene._timed_shots[0][0]), 0.55, 1e-6, "keep the ball's separation delay")
	# Once the pending evidence has been consumed, later volleys must not keep overwriting the same file.
	scene._timed_shots.clear()
	scene.handle_events(volley)
	assert_true(scene._timed_shots.is_empty(), "only the first projectile needs the evidence shot")
	scene.free()
