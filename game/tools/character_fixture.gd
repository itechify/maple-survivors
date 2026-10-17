extends SceneTree
## Reproduces the spec #32 fixture from an unmodified real-cache Henesys round, seed 1, bot, forced branch 210.
## ISOLATE=t67 bash scripts/test.sh character_snapshot # prepares the isolated project, then:
## ISOLATE=t67 bash scripts/godot.sh --headless --path _scratch/godot_runs/t67/game
##   --script res://tools/character_fixture.gd -- --out=<absolute JSON path> --revision=<git SHA>
## Only numeric character state/IDs/skill keys and provenance are written; never cache trees or decoded assets.
## The snapshot written is the current CharacterSnapshot format (2: worn equipment, inventory, scrolls, mesos).
##
## `--migrate=<absolute JSON path> --out=<absolute JSON path>` instead converts an existing format-1 fixture to format 2
## with real-cache item info (CharacterSnapshot.migrate), keeping its character and _doc provenance and recording the
## migration in _doc.migration. The committed fixture was migrated this way by spec #33 (#105), not regenerated, so its
## Dark Cave records stay comparable.

const HARNESS := preload("res://tools/balance_run.gd")


func _init() -> void:
	var output := ""
	var revision := ""
	var migrate := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.substr(6)
		elif arg.begins_with("--revision="):
			revision = arg.substr(11)
		elif arg.begins_with("--migrate="):
			migrate = arg.substr(10)
	if output != "" and migrate != "":
		_migrate(migrate, output)
		return
	if output == "" or revision == "":
		print("character_fixture: --out and --revision are required")
		quit(2)
		return
	var library := AssetLibrary.new()
	library.open()
	var missing := PackedStringArray()
	var setup := DataRepo.build_setup(DataRepo.load_all(), "henesys_hg1", 1, Vector2(800, 600),
		func(path: String) -> Dictionary:
			var img := library.img(path)
			return img.root if img != null else {},
		func(id: int) -> Dictionary: return library.mob_root(id), missing)
	if not missing.is_empty():
		print("character_fixture: cache missing " + str(missing))
		library.free()
		quit(1)
		return
	var world := RunWorld.new(setup)
	var record := HARNESS.run_one(world, "bot", 1, -1.0, 60.0, 210)
	print("FIXTURE_RUN " + JSON.stringify(record))
	if world.state != RunWorld.CLEARED or not world.warnings.is_empty():
		print("character_fixture: expected a clean completed round")
		library.free()
		quit(1)
		return
	var character := world.character_snapshot()
	character["_doc"] = {"source": "real headless Henesys bot round, all bosses/reward choices completed",
		"stage": "henesys_hg1", "seed": 1, "policy": "bot", "forced_branch": 210,
		"branch": "spec32/ticket-67", "revision": revision, "outcome": record.state,
		"round_seconds": record.time, "rounding": "floating character fields rounded to six decimal places"}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		print("character_fixture: cannot write " + output)
		library.free()
		quit(1)
		return
	file.store_string(JSON.stringify(_rounded(character), "\t") + "\n")
	file.close()
	print("FIXTURE_WRITTEN %s Lv%d job%d missing=%s" % [output, character.level, character.job_id, missing])
	library.free()
	quit()


func _migrate(input: String, output: String) -> void:
	var errors := PackedStringArray()
	var old := DataRepo.load_character(input, errors)
	if not errors.is_empty() or int(old.get("format", 0)) != 1:
		print("character_fixture: --migrate needs a valid format-1 character: %s" % "; ".join(errors))
		quit(1)
		return
	var library := AssetLibrary.new()
	library.open()
	var missing := PackedStringArray()
	# Restoring into a real-cache world migrates it (RunWorld._restore_character) and writes the sim's own types back.
	var setup := DataRepo.build_setup(DataRepo.load_all(), "henesys_hg1", 1, Vector2(800, 600),
		func(path: String) -> Dictionary:
			var img := library.img(path)
			return img.root if img != null else {},
		func(id: int) -> Dictionary: return library.mob_root(id), missing, old)
	library.free()
	if not missing.is_empty():
		print("character_fixture: cache missing " + str(missing))
		quit(1)
		return
	var character := RunWorld.new(setup).character_snapshot()
	character["_doc"] = old._doc.duplicate(true)
	for key: String in ["forced_branch", "seed"]:
		character._doc[key] = int(character._doc[key])
	character._doc["migration"] = {"from_format": 1, "to_format": CharacterSnapshot.FORMAT,
		"by": "spec33/ticket-105", "how": "tools/character_fixture.gd --migrate (CharacterSnapshot.migrate)"}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		print("character_fixture: cannot write " + output)
		quit(1)
		return
	file.store_string(JSON.stringify(_rounded(character), "\t") + "\n")
	file.close()
	print("FIXTURE_MIGRATED %s worn=%s" % [output, Equipment.worn_ids(character.equipment.worn)])
	quit()


func _rounded(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[key] = _rounded(value[key])
		return out
	if value is Array:
		return value.map(_rounded)
	if value is float:
		return snappedf(value, 0.000001) # tier C: fixture readability, never balance tuning.
	return value
