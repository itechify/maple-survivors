extends SceneTree
## Writes the character fixtures (format 3, ADR 0006: job, look, worn equipment, inventory, scrolls, mesos, cleared regions,
## cash and pet; no level or build). Three modes:
##
##  * a real round: an unmodified real-cache Henesys round (default seed 1, the kiting bot) whose character is written as
##    the round leaves it, with its pickups and the region its clear adds to its cleared set.
##  * `--kit=<id,id,...>`: a synthetic kit, no round: a fresh Lv1 character of `--job` wearing those equipment ids with
##    their canonical stats (what they displace is dropped), `--cleared=<n>` the first n progression regions cleared (default 0;
##    `--tiers=<n>` is the old spelling: 2 = `--cleared=4`, 1 = 0). This is how the committed `fp_arch_mage.json` is made
##    (the tier-1 kit of the Sleepywood checks, Sleepywood unlocked).
##  * `--migrate=<absolute JSON path>`: converts an existing format-1 or format-2 file to format 3 with real-cache item
##    info (CharacterSnapshot.migrate), keeping its job, look and belongings and its `_doc`.
##
## ISOLATE=<name> bash scripts/test.sh character_snapshot # prepares the isolated project, then:
## ISOLATE=<name> bash scripts/godot.sh --headless --path _scratch/godot_runs/<name>/game
##   --script res://tools/character_fixture.gd -- --out=<absolute JSON path> --revision=<git SHA> [mode flags]
## The committed kit fixture is `--kit=1382002,1002013,1072019,1082019,1040002,1060002 --cleared=4 --label=spec282/ticket-294`.
## Flags: `--label=<ticket>` (the _doc.branch provenance), `--job=<id>` (the character's job; default
## JobTree.default_job(), 212; it must be playable), `--seed=<n>` (a round's seed, default 1) and `--seconds=<s>` (a round's
## time cap: the round stops there and only has to be alive and warning-free; without it the round must clear).
## `--extra-cleared=<key,key,...>` (kit mode) adds stage keys to the cleared set that `progression` does not hold yet (planned
## regions: a fixture made before they exist, e.g. `late_progression.json` with `--cleared=15` while only five regions ship; once
## they ship, `--cleared=<n>` alone writes the same set); `--note=<text>` replaces the generated `_doc.note` of a kit fixture.
## `--god` is a documented diagnostic aid: RunWorld.god makes the character invulnerable, so the bot can reach a clear its
## play does not survive to; use it with a round, and the fixture's _doc records it (`invulnerable` and `diagnostic`).
## `--patch=<absolute JSON path>` deep-merges a JSON patch into loaded data first, as balance_run does; `_doc.patch`
## records its file name. Both Hero (112) and F/P (212, default) ship playable; generating either needs no patch.
## `--exp-mult=<k>` multiplies the round's EXP (balance `exp_mult`); recorded in the _doc as well.
## Only numeric character state/IDs and provenance are written; never cache trees or decoded assets.

const DEFAULT_JOB := -2
const HARNESS := preload("res://tools/balance_run.gd")


func _init() -> void:
	var output := ""
	var revision := ""
	var migrate := ""
	var job := DEFAULT_JOB
	var god := false
	var exp_mult := 1.0
	var seconds := 0.0
	var seed_value := 1
	var label := "spec32/ticket-67"
	var kit := ""
	var cleared := 0
	var patch_file := ""
	var extra_cleared := ""
	var note := ""
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
		elif arg.begins_with("--kit="):
			kit = arg.substr(6)
		elif arg.begins_with("--cleared="):
			cleared = maxi(0, int(arg.substr(10)))
		elif arg.begins_with("--tiers="): # compatibility alias: tier 2 open = the four tier-1 regions cleared
			cleared = CharacterSnapshot.LEGACY_TIER1_REGIONS if int(arg.substr(8)) >= 2 else 0
		elif arg.begins_with("--patch="):
			patch_file = arg.substr(8)
		elif arg.begins_with("--extra-cleared="):
			extra_cleared = arg.substr(16)
		elif arg.begins_with("--note="):
			note = arg.substr(7)
	if output != "" and migrate != "":
		_migrate(migrate, output)
		return
	if output == "" or revision == "":
		print("character_fixture: --out and --revision are required")
		quit(2)
		return
	var data := DataRepo.load_all()
	if patch_file != "":
		var patch: Variant = JSON.parse_string(FileAccess.get_file_as_string(patch_file))
		if not (patch is Dictionary):
			print("character_fixture: cannot read the patch %s" % patch_file)
			quit(1)
			return
		HARNESS.deep_merge(data, patch)
	var jobs := DataRepo.jobs(data)
	if job == DEFAULT_JOB:
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
	if kit != "":
		_kit({"kit": kit, "cleared": cleared, "job": job, "output": output, "revision": revision, "label": label,
				"patch": patch_file, "extra_cleared": extra_cleared, "note": note}, setup, library)
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
	if patch_file != "":
		character._doc["patch"] = patch_file.get_file()
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
	print("FIXTURE_WRITTEN %s job%d reached Lv%d missing=%s" % [output, character.job_id, int(record.level), missing])
	library.free()
	quit()


## A fresh Lv1 character of `job` wearing the equipment ids in `kit` (a comma list), the first `cleared` progression regions
## cleared, written to `output`.
func _kit(options: Dictionary, setup: Dictionary, library: AssetLibrary) -> void:
	var kit := String(options.kit)
	var cleared := int(options.cleared)
	var job := int(options.job)
	var output := String(options.output)
	var revision := String(options.revision)
	var label := String(options.label)
	setup["job"] = job
	var world := RunWorld.new(setup)
	var ids: Array[int] = []
	for part: String in kit.split(","):
		var id := int(part)
		var error := world.wear_new_item(id)
		if error != "" or Equipment.slot_of(id) == "":
			print("character_fixture: cannot wear %s: %s" % [part, error])
			library.free()
			quit(1)
			return
		ids.append(id)
	var character := world.character_snapshot()
	character.equipment.inventory = [] # the kit is what is worn: the pieces it displaced are dropped
	var progression: Array = world.data.stages.get("progression", [])
	var cleared_keys: Array = progression.slice(0, cleared)
	for key: String in String(options.get("extra_cleared", "")).split(",", false):
		if key not in cleared_keys:
			cleared_keys.append(key)
	character.cleared_regions = CharacterSnapshot.cleared_of({"cleared_regions": cleared_keys}, progression)
	character["_doc"] = {"by": label, "revision": revision, "job": job, "kit": ids,
		"note": String(options.get("note", "")) if String(options.get("note", "")) != "" else
			"Synthetic format-3 kit (tools/character_fixture.gd --kit): unscrolled canonical equipment of the Lv0-30 tier-1 "
			+ "drop band and %d regions cleared, no cash, pet or carried build; a Lv1 character for the Sleepywood checks." % cleared}
	if String(options.get("extra_cleared", "")) != "":
		character._doc["extra_cleared"] = String(options.extra_cleared).split(",", false)
	if String(options.get("patch", "")) != "":
		character._doc["patch"] = String(options.patch).get_file()
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		print("character_fixture: cannot write " + output)
		library.free()
		quit(1)
		return
	file.store_string(JSON.stringify(_rounded(character), "\t") + "\n")
	file.close()
	print("FIXTURE_WRITTEN %s kit %s cleared %d" % [output, ids, cleared])
	library.free()
	quit()


func _migrate(input: String, output: String) -> void:
	var errors := PackedStringArray()
	var old := DataRepo.load_character(input, errors)
	if not errors.is_empty() or int(old.get("format", 0)) not in [1, 2]:
		print("character_fixture: --migrate needs a valid format-1 or format-2 character: %s" % "; ".join(errors))
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
		if character._doc.has(key):
			character._doc[key] = int(character._doc[key])
	character._doc["migration"] = {"from_format": int(old.format), "to_format": CharacterSnapshot.FORMAT,
		"by": "spec282/ticket-286", "how": "tools/character_fixture.gd --migrate (CharacterSnapshot.migrate)"}
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
