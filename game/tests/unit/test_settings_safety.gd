extends TestCase
## Settings durability tests use only process-private files; failed writes must remain visible to setter callers.

var cfg_path := test_dir("settings_safety/settings.cfg")


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cfg_path.get_base_dir()))


func after_each() -> void:
	TestCase.remove_tree(cfg_path.get_base_dir())


func test_failed_setter_preserves_preferences_and_emits_a_persistence_error() -> void:
	var settings := GameSettings.new(cfg_path)
	settings.set_volume("bgm", 0.25)
	settings.set_window_scale(3)
	var original := FileAccess.get_file_as_string(cfg_path)
	var backup := FileAccess.get_file_as_string(cfg_path + ".bak")
	assert_true(settings.has_signal("save_failed"))
	var seen := {"errors": []}
	if settings.has_signal("save_failed"):
		settings.connect("save_failed", func(error: Error) -> void: seen.errors.append(error))
	assert_eq(DirAccess.make_dir_absolute(ProjectSettings.globalize_path(cfg_path + ".tmp")), OK)
	settings.set_volume("bgm", 0.5)
	assert_true(settings.get("last_error") is int)
	assert_ne(settings.get("last_error"), OK)
	assert_eq(seen.errors.size(), 1, "setters report persistence failures even when their return is ignored")
	assert_eq(FileAccess.get_file_as_string(cfg_path), original)
	assert_eq(FileAccess.get_file_as_string(cfg_path + ".bak"), backup)
	assert_eq(DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path + ".tmp")), OK)
	assert_eq(settings.save_settings(), OK)
	assert_eq(settings.get("last_error"), OK)
	settings.free()


func test_corrupt_primary_recovers_preferences_and_keeps_the_valid_backup() -> void:
	var settings := GameSettings.new(cfg_path)
	settings.set_volume("bgm", 0.25)
	settings.set_window_scale(3)
	settings.free()
	var backup := FileAccess.get_file_as_string(cfg_path + ".bak")
	assert_false(backup.is_empty(), "a prior complete config survives replacement")
	var file := FileAccess.open(cfg_path, FileAccess.WRITE)
	file.store_string("[audio\nbgm=\"")
	file.close()
	var recovered := GameSettings.new(cfg_path)
	assert_eq(recovered.bgm_volume, 0.25)
	assert_eq(recovered.window_scale, 0, "the backup precedes the scale change")
	assert_eq(FileAccess.get_file_as_string(cfg_path), "[audio\nbgm=\"", "loading never writes")
	assert_eq(recovered.save_settings(), OK)
	assert_eq(FileAccess.get_file_as_string(cfg_path + ".bak"), backup, "rejected bytes never rotate over a good backup")
	recovered.free()
	var reloaded := GameSettings.new(cfg_path)
	assert_eq(reloaded.bgm_volume, 0.25)
	reloaded.free()
