extends SceneTree
## Reproduces a character fixture from an unmodified real-cache Henesys round (seed 1, bot; the spec #32 one was a
## forced-210 round before #284 removed job advancement).
## ISOLATE=t67 bash scripts/test.sh character_snapshot # prepares the isolated project, then:
## ISOLATE=t67 bash scripts/godot.sh --headless --path _scratch/godot_runs/t67/game
##   --script res://tools/character_fixture.gd -- --out=<absolute JSON path> --revision=<git SHA>
## `--label=<ticket>` (the _doc.branch provenance; default spec32/ticket-67, the Lv38 F/P fixture; lv11_warrior_1st.json says
## spec151/ticket-163), `--job=<id>` (the character's job; default JobTree.default_job(), 212; it must be playable),
## `--seed=<n>` (default 1) and `--seconds=<s>` pick the job, the seed and a time cap:
## with a cap the round stops there (a low-level fixture such as lv20_warrior_1st.json: `--job=100 --seconds=600`) and only
## has to be alive and warning-free; without one the round must clear.
## `--god` is a documented diagnostic
## aid (spec #165 #185 and spec #168 #195): RunWorld.god makes the character invulnerable, so the bot can reach a level its play does not
## survive to (Warrior, Pirate and Thief second-job fixtures). Use it with `--seconds`, and the
## fixture's _doc records it (`invulnerable` and `diagnostic`). `--exp-mult=<k>` is a second aid: it multiplies the round's EXP (balance
## `exp_mult`) for a line the bot cannot level at its natural pace (the knuckle Pirate: its damage cannot beat the second
## boss), and is recorded in the _doc as well.
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
	var job := -2 # -2: the default job
	var god := false
	var exp_mult := 1.0
	var seconds := 0.0
	var seed_value := 1
	var label := "spec32/ticket-67"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.substr(6)
		elif arg.begins_with("--revision="):
			revision = arg.substr(11)
		elif arg.begins_with("--migrate="):
			migrate = arg.substr(10)
		elif arg.begins_with("--job="):
			job = JobTree.parse_job(arg.substr(6))
		elif arg == "--god":
			god = true
		elif arg.begins_with("--exp-mult="):
			exp_mult = float(arg.substr(11))
		elif arg.begins_with("--seconds="):
			seconds = float(arg.substr(10))
		elif arg.begins_with("--label="):
			label = arg.substr(8)
		elif arg.begins_with("--seed="):
			seed_value = int(arg.substr(7))
	if output != "" and migrate != "":
		_migrate(migrate, output)
		return
	if output == "" or revision == "":
		print("character_fixture: --out and --revision are required")
		quit(2)
		return
	var data := DataRepo.load_all()
	var jobs := JobTree.from_data(data.jobs, data.jobs_survivor)
	if job == -2:
		job = jobs.default_job()
	var job_error := "not a job id" if job < 0 else jobs.job_error(job)
	if job_error != "":
		print("character_fixture: --job: " + job_error)
		quit(2)
		return
	var library := AssetLibrary.new()
	library.open()
	var missing := PackedStringArray()
	var setup := DataRepo.build_setup(data, "henesys", seed_value, Vector2(800, 600),
		func(path: String) -> Dictionary:
			var img := library.img(path)
			return img.root if img != null else {},
		func(id: int) -> Dictionary: return library.mob_root(id), missing)
	if not missing.is_empty():
		print("character_fixture: cache missing " + str(missing))
		library.free()
		quit(1)
		return
	setup["job"] = job
	var world := RunWorld.new(setup)
	world.god = god
	world.balance["exp_mult"] = float(world.balance.get("exp_mult", 1.0)) * exp_mult
	if seconds > 0.0:
		# A capped fixture (--seconds): the round stops at the cap, so the character is still low level.
		world.balance["run_time_cap"] = seconds
	var record := HARNESS.run_one(world, "bot", seed_value, -1.0, 60.0)
	print("FIXTURE_RUN " + JSON.stringify(record))
	var finished := world.state == RunWorld.CLEARED if seconds <= 0.0 else world.state != RunWorld.DEAD
	if not finished or not world.warnings.is_empty():
		print("character_fixture: expected a clean %s round" % ("completed" if seconds <= 0.0 else "capped, living"))
		library.free()
		quit(1)
		return
	var character := world.character_snapshot()
	character["_doc"] = {"source": "real headless Henesys bot round, all bosses/reward choices completed" if seconds <= 0.0
			else "real headless Henesys bot round, stopped at the %d s cap (a low-level fixture)" % int(seconds),
		"stage": "henesys", "seed": seed_value, "policy": "bot", "job": job,
		"branch": label, "revision": revision,
		"outcome": record.state, "round_seconds": record.time,
		"rounding": "floating character fields rounded to six decimal places"}
	if god:
		character._doc["invulnerable"] = true
		character._doc["source"] = "real headless Henesys bot round with the character invulnerable (RunWorld.god)" + (", stopped at the %d s cap" % int(seconds) if seconds > 0.0 else ", all bosses/reward choices completed")
		character._doc["diagnostic"] = "invulnerable (RunWorld.god = true; fixture tool --god): the bot plays with damage ignored to reach a level its play does not survive to, for diagnostic fixtures"
	if exp_mult != 1.0:
		character._doc["exp_mult"] = exp_mult
		character._doc["diagnostic_exp"] = "balance exp_mult x%s (fixture tool --exp-mult): diagnostic EXP aid to reach the requested job within the recorded time cap; not balance evidence" % str(exp_mult)
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
	var setup := DataRepo.build_setup(DataRepo.load_all(), "henesys", 1, Vector2(800, 600),
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
