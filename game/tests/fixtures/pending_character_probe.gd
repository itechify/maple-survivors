extends SceneTree
## Child-process probe: the expected debug assertion must not abort the parent test runner.


func _init() -> void:
	var w := preload("res://tests/fixtures/run_fixtures.gd").quiet_world()
	var mode := OS.get_cmdline_user_args()[0]
	match mode:
		"card": w.state = RunWorld.CHOOSING_UPGRADE
		"queue": w.progression.queue.append(2)
		"reward": w.pending_bonus_choices = 1
	var character := w.character_snapshot()
	print("PENDING_SNAPSHOT_EMPTY=" + str(character.is_empty()))
	quit()
