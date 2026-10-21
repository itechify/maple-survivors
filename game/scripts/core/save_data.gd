class_name SaveData
extends RefCounted
## Local save file (user://save.json): best results, round counts, character slots and ended-run history. Nothing leaves
## machine (docs/ARCHITECTURE.md section 7).
##
## File: {format: 2, best: {stage_key: record}, runs: {stage_key: int}, slots: [null | run snapshot], history: [],
## account?: {nx: int, owned: [int]}}. The optional `account` (spec #34; see Account) is NX plus owned cash item ids:
## a save without it is an empty account, and the format number stays 2 so older files need no migration step.
## A best record is
## {time, duration, cleared, level, job_id, job_name, kills, damage_dealt, seed}. Missing files start empty;
## format 1 converts on load, keeping playable-stage bests/counts. Writes replace the file via a sibling temporary.
## Run snapshot: {name, created, character: CharacterSnapshot, tier, phase, rounds_played, tiers_cleared,
## stage?, round_seed?}; tier indexes the next tier (0-based). phase is free_market/map_select/round;
## round requires stage and round_seed. Keep the last stage outside a round for deletion history.
## History: {name, job_id, job_name, level, tiers_cleared, rounds_played, ending, stage, date}; ending is
## died/victory/deleted. Dates are nonempty caller-supplied strings; SaveData never reads the clock or picks seeds.
## A round summary's `nx_awarded` is added to the account inside the same write as update_slot (clear boundary) or
## end_run (death/victory); deletion never credits. set_account replaces the whole block (Cash Shop spending).
## Corrupt/unsupported files are copied to .bad[.N]; valid .bak recovers a missing or rejected primary.
## Web imports are staged at .import and fully validated here before promotion; rejection leaves committed files alone.
##
## Best result rule (tier C, ours): a clear beats a death; then the longer survival; then the higher level, more kills,
## more damage.

const PATH := "user://save.json"
const FORMAT := 2 # tier C: spec #32 save schema.
const SLOT_COUNT := 3 # tier C: spec #32 owner choice.
## Summary keys kept in a best record.
const RECORD_KEYS := ["time", "duration", "cleared", "level", "job_id", "job_name", "kills", "damage_dealt", "seed"]

var path := PATH
## stage key -> best record.
var best: Dictionary = {}
## stage key -> runs finished.
var runs: Dictionary = {}
## Detached views; mutate characters through create_slot/update_slot/end_run.
var slots: Array:
	get:
		return _slots.duplicate(true)
var history: Array:
	get:
		return _history.duplicate(true)
## The account ({nx, owned}), a detached view; change it through set_account or a round summary's nx_awarded.
var account: Dictionary:
	get:
		return _account.duplicate(true)
## Most recent persistence error; creation returns -1 on failure and other mutators return Error.
var last_error: Error = OK
var _preserve_error: Error = OK
var _primary_valid := false
var _slots: Array = [null, null, null]
var _history: Array = []
var _account: Dictionary = Account.empty()
var _writer: WriterLock
var _writer_required := false
## Lock acquisition error; tool paths opt out, while the default persistent save always opts in on desktop.
var writer_error: Error = OK


func _init(p_path: String = PATH, persistent: bool = false) -> void:
	path = p_path
	_writer_required = (persistent or path == PATH) and not OS.has_feature("web")
	if _writer_required:
		_writer = WriterLock.new()
		writer_error = _writer.acquire(ProjectSettings.globalize_path(path + ".lock"))
	load_file()


## Re-reads/converts the file, recovers a valid backup, then validates any shell-staged import before promotion.
func load_file() -> void:
	if _writer_required and not _writer.owns():
		last_error = writer_error if writer_error != OK else ERR_ALREADY_IN_USE
		return
	best = {}
	runs = {}
	_slots = [null, null, null]
	_history = []
	_account = Account.empty()
	last_error = OK
	_preserve_error = OK
	_primary_valid = false
	for source: String in [path, path + ".bak"]:
		if not FileAccess.file_exists(source):
			continue
		var parsed := _read_valid_file(source)
		if _preserve_error != OK:
			return
		if parsed.is_empty():
			continue
		_primary_valid = source == path
		_apply_file(parsed)
		last_error = OK
		if source != path or int(parsed.format) == 1:
			last_error = save_file()
		break
	_load_import()


func _read_valid_file(source: String) -> Dictionary:
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null:
		_preserve_error = FileAccess.get_open_error()
		last_error = _preserve_error
		return {}
	var text := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK and read_error != ERR_FILE_EOF:
		_preserve_error = read_error
		last_error = read_error
		return {}
	var json := JSON.new()
	if json.parse(text) != OK or not _valid_file(json.data):
		_preserve_bad_file(source)
		return {}
	return json.data


func _apply_file(parsed: Dictionary) -> void:
	best = {}
	runs = {}
	var stage_data: Variant = DataRepo.load_json(DataRepo.DATA_ROOT.path_join(DataRepo.FILES.stages))
	var stages: Dictionary = stage_data.get("stages", {}) if stage_data is Dictionary else {}
	for k: String in parsed.best:
		if stages.has(k) and parsed.best[k] is Dictionary:
			best[k] = parsed.best[k]
	for k: String in parsed.runs:
		if stages.has(k):
			runs[k] = int(parsed.runs[k])
	_slots = parsed.get("slots", [null, null, null])
	_history = parsed.get("history", [])
	_account = Account.normalized(parsed.get("account", Account.empty()))


func _load_import() -> void:
	var source := path + ".import"
	if not FileAccess.file_exists(source):
		return
	var parsed := _read_valid_file(source)
	if _preserve_error != OK:
		return
	if parsed.is_empty():
		# The rejected candidate is retained as .import.bad; do not retry it on every launch.
		var error := DirAccess.remove_absolute(source)
		if error != OK:
			_preserve_error = error
			last_error = error
		return
	var previous := _state()
	_apply_file(parsed)
	last_error = save_file()
	if last_error == OK:
		last_error = DirAccess.remove_absolute(source)
	else:
		_apply_file(previous)
	if last_error != OK:
		# Do not allow later mutations while an unconsumed candidate could replay over them on restart.
		_preserve_error = last_error


## Writes through .tmp with a .bak recovery copy (creating its folder); returns any persistence error.
func save_file() -> Error:
	last_error = _write(_state())
	return last_error


## The run snapshot in a slot, detached from the save; {} for an empty or out-of-range slot.
func slot(index: int) -> Dictionary:
	if index < 0 or index >= SLOT_COUNT or _slots[index] == null:
		return {}
	return (_slots[index] as Dictionary).duplicate(true)


## Saves a character in the first free slot; returns its index, or -1 (see last_error).
func create_slot(snapshot: Dictionary) -> int:
	if not validation_error(snapshot).is_empty() or not _name_available(String(snapshot.name)):
		last_error = ERR_INVALID_DATA
		return -1
	for index in SLOT_COUNT:
		if _slots[index] == null:
			var data := _state()
			data.slots[index] = snapshot.duplicate(true)
			return index if _commit(data) == OK else -1
	last_error = ERR_OUT_OF_MEMORY
	return -1


## Saves an occupied slot's boundary; an optional finished-round summary counts toward bests in the same write.
func update_slot(index: int, snapshot: Dictionary, round_summary: Dictionary = {}) -> Error:
	if slot(index).is_empty():
		last_error = ERR_INVALID_PARAMETER
		return last_error
	if not validation_error(snapshot).is_empty() or not _name_available(String(snapshot.name), index):
		last_error = ERR_INVALID_DATA
		return last_error
	var data := _state()
	data.slots[index] = snapshot.duplicate(true)
	if not round_summary.is_empty():
		_record_into(data, round_summary)
		_credit(data, round_summary)
	return _commit(data)


## Replaces the account (NX balance and owned cash items) in one write; ERR_INVALID_DATA for a malformed block.
func set_account(value: Variant) -> Error:
	if not Account.validation_error(value).is_empty():
		last_error = ERR_INVALID_DATA
		return last_error
	var data := _state()
	data.account = Account.normalized(value)
	return _commit(data)


## Frees a slot and appends history in one save. Optional final snapshot/round summary capture terminal progress.
## Date comes from the caller. Omit the final snapshot when deleting a character at its saved boundary.
func end_run(index: int, ending: String, date: String, final_snapshot: Dictionary = {},
		round_summary: Dictionary = {}) -> Error:
	if slot(index).is_empty() or ending not in ["died", "victory", "deleted"] or date.is_empty():
		last_error = ERR_INVALID_PARAMETER
		return last_error
	var snapshot := slot(index) if final_snapshot.is_empty() else final_snapshot
	if not validation_error(snapshot).is_empty() or not _name_available(String(snapshot.name), index):
		last_error = ERR_INVALID_DATA
		return last_error
	var character: Dictionary = snapshot.character
	var job_id := int(character.job_id)
	var jobs: Dictionary = DataRepo.load_json(DataRepo.DATA_ROOT.path_join(DataRepo.FILES.jobs))
	var job_name := str(job_id)
	for job: Dictionary in jobs.get("jobs", []):
		if int(job.id) == job_id:
			job_name = String(job.name)
			break
	var data := _state()
	data.slots[index] = null
	data.history.append({"name": snapshot.name, "job_id": job_id, "job_name": job_name,
		"level": int(character.level), "tiers_cleared": int(snapshot.tiers_cleared),
		"rounds_played": int(snapshot.rounds_played), "ending": ending,
		"stage": snapshot.get("stage", ""), "date": date})
	if not round_summary.is_empty():
		_record_into(data, round_summary)
		if ending != "deleted":
			_credit(data, round_summary)
	return _commit(data)


## Validates the binding spec #32 run wrapper and delegates character validation to CharacterSnapshot.
static func validation_error(value: Variant) -> String:
	if not value is Dictionary or not _json_safe(value):
		return "expected a JSON-safe run snapshot"
	if not value.get("name") is String or not _valid_name(value.name):
		return "name must be 4-12 letters or digits"
	# Legacy format-2 wrappers may carry a duplicate look. Only character.look is consumed (#70/#71).
	if value.has("look") and not value.look is Dictionary:
		return "invalid look"
	if not value.get("created") is String or value.created.is_empty():
		return "invalid created date"
	var character: Variant = value.get("character")
	if not character is Dictionary or not _whole(character.get("format")):
		return "invalid CharacterSnapshot format"
	var character_error := CharacterSnapshot.validation_error(character)
	if not character_error.is_empty():
		return character_error
	for key: String in ["tier", "rounds_played", "tiers_cleared"]:
		if not _whole(value.get(key)):
			return "invalid " + key
	if value.get("phase") not in ["free_market", "map_select", "round"]:
		return "invalid phase"
	if value.has("stage") and not value.stage is String:
		return "invalid stage"
	if value.has("round_seed") and not _whole(value.round_seed):
		return "invalid round_seed"
	if value.phase == "round" and (String(value.get("stage", "")).is_empty() or not value.has("round_seed")):
		return "a round needs a stage and round_seed"
	return ""


func _name_available(name: String, except: int = -1) -> bool:
	for index in SLOT_COUNT:
		if index != except and _slots[index] != null and String(_slots[index].name).nocasecmp_to(name) == 0:
			return false
	return true


## Creation validation with a recoverable message, shared by the screen and flow action.
func name_error(character_name: String) -> String:
	# tier C: owner #32 name rule (4-12 ASCII letters/digits, unique among living characters).
	if character_name.length() < 4 or character_name.length() > 12:
		return "Use 4-12 letters and digits for your name."
	if not _valid_name(character_name):
		return "Use only letters A-Z and digits 0-9."
	if not _name_available(character_name):
		return "A living character already has that name. Choose another."
	return ""


static func _valid_name(value: String) -> bool:
	# tier C: owner #32 creation rule, shared with the plain slot API before #70's screens.
	if value.length() < 4 or value.length() > 12:
		return false
	for i in value.length():
		var code := value.unicode_at(i)
		if not (code >= 48 and code <= 57 or code >= 65 and code <= 90 or code >= 97 and code <= 122):
			return false
	return true


static func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and float(value) >= 0.0 and float(value) == floorf(float(value))


static func _json_safe(value: Variant) -> bool:
	if value == null or value is bool or value is String or value is StringName or value is int:
		return true
	if value is float:
		return is_finite(value)
	if value is Array:
		for entry: Variant in value:
			if not _json_safe(entry):
				return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not (key is String or key is StringName) or not _json_safe(value[key]):
				return false
		return true
	return false


static func _valid_file(value: Variant) -> bool:
	if not value is Dictionary or not _json_safe(value) or not _whole(value.get("format")):
		return false
	if int(value.format) not in [1, FORMAT] or not value.get("best") is Dictionary or not value.get("runs") is Dictionary:
		return false
	for count: Variant in value.runs.values():
		if not _whole(count):
			return false
	if int(value.format) == 1:
		return true
	if not value.get("slots") is Array or value.slots.size() != SLOT_COUNT or not value.get("history") is Array:
		return false
	if value.has("account") and not Account.validation_error(value.account).is_empty():
		return false
	var names := {}
	for snapshot: Variant in value.slots:
		if snapshot == null:
			continue
		if not validation_error(snapshot).is_empty():
			return false
		var name: String = snapshot.name.to_lower()
		if names.has(name):
			return false
		names[name] = true
	for entry: Variant in value.history:
		if not entry is Dictionary:
			return false
		for key: String in ["name", "job_name", "stage", "date"]:
			if not entry.get(key) is String:
				return false
		for key: String in ["job_id", "level", "tiers_cleared", "rounds_played"]:
			if not _whole(entry.get(key)):
				return false
		if int(entry.level) < 1 or entry.get("ending") not in ["died", "victory", "deleted"]:
			return false
	return true


func _state() -> Dictionary:
	return {"format": FORMAT, "best": best.duplicate(true), "runs": runs.duplicate(true),
		"slots": _slots.duplicate(true), "history": _history.duplicate(true), "account": _account.duplicate(true)}


## Adds a finished round's NX to the account being written (a missing or negative nx_awarded adds nothing).
static func _credit(data: Dictionary, round_summary: Dictionary) -> void:
	data.account.nx = int(data.account.nx) + maxi(0, int(round_summary.get("nx_awarded", 0)))


func _commit(data: Dictionary) -> Error:
	last_error = _write(data)
	if last_error == OK:
		_account = data.account
		best = data.best
		runs = data.runs
		_slots = data.slots
		_history = data.history
	return last_error


func _preserve_bad_file(source: String) -> void:
	var backup := source + ".bad"
	var suffix := 0
	while FileAccess.file_exists(backup) or DirAccess.dir_exists_absolute(backup):
		suffix += 1
		backup = source + ".bad." + str(suffix)
	_preserve_error = DirAccess.copy_absolute(source, backup)
	last_error = _preserve_error if _preserve_error != OK else ERR_FILE_CORRUPT


func _write(data: Dictionary) -> Error:
	if _writer_required and not _writer.owns():
		return writer_error if writer_error != OK else ERR_ALREADY_IN_USE
	if not _valid_file(data):
		return ERR_INVALID_DATA
	# Never overwrite a save whose bytes could not be read or preserved.
	if _preserve_error != OK:
		return _preserve_error
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		var error := DirAccess.make_dir_recursive_absolute(dir)
		if error != OK:
			return error
	var text := JSON.stringify(data, "\t", true, true)
	if _primary_valid and JSON.parse_string(FileAccess.get_file_as_string(path)) == JSON.parse_string(text):
		return OK # No state change: retain both committed byte sequences, including the older backup.
	var temporary := path + ".tmp"
	var f := FileAccess.open(temporary, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.flush()
	var error := f.get_error()
	f.close()
	# Windows DirAccess.rename removes the destination before moving. Keep a complete previous save so
	# load_file can recover if the process stops in that gap. Never move the only complete copy aside.
	if error == OK and _primary_valid and FileAccess.file_exists(path):
		error = DirAccess.copy_absolute(path, path + ".bak")
	if error == OK:
		error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
	else:
		_primary_valid = true
	return error


## Atomic directory creation is the exclusive lock; its owner file records a PID for crash recovery.
## Only the real save uses it. No simulation, test/tool save, or web engine needs a desktop session lock.
class WriterLock extends RefCounted:
	# tier C: allow an interrupted mkdir/owner-file pair five seconds before recovering an empty lock.
	const EMPTY_GRACE_SECONDS := 5
	var directory := ""
	var owner := ""

	## Claims the sibling lock directory, or recovers it only when its prior process is gone.
	func acquire(lock_path: String) -> Error:
		directory = lock_path
		var error := DirAccess.make_dir_recursive_absolute(directory.get_base_dir())
		if error != OK:
			return error
		error = DirAccess.make_dir_absolute(directory)
		if error != OK:
			if not DirAccess.dir_exists_absolute(directory):
				return error
			var removed := false
			for name: String in DirAccess.get_files_at(directory):
				if not name.ends_with(".owner") or not name.get_slice(".", 0).is_valid_int():
					continue # Unknown debris fails closed rather than stealing a possibly live lock.
				var pid := int(name.get_slice(".", 0))
				if pid > 0 and not _process_alive(pid):
					removed = DirAccess.remove_absolute(directory.path_join(name)) == OK or removed
			var empty := DirAccess.get_files_at(directory).is_empty() and DirAccess.get_directories_at(directory).is_empty()
			var expired := Time.get_unix_time_from_system() - FileAccess.get_modified_time(directory) >= EMPTY_GRACE_SECONDS
			if empty and (removed or expired):
				DirAccess.remove_absolute(directory)
			error = DirAccess.make_dir_absolute(directory)
			if error != OK:
				return ERR_ALREADY_IN_USE
		# Unique filenames make even a race with recovery of an empty lock fail closed: two markers never authorize a write.
		owner = "%d.%d.owner" % [OS.get_process_id(), get_instance_id()]
		var file := FileAccess.open(directory.path_join(owner), FileAccess.WRITE)
		if file == null:
			return FileAccess.get_open_error()
		file.store_string(owner)
		file.flush()
		error = file.get_error()
		file.close()
		if error != OK:
			return error
		return OK if owns() else ERR_ALREADY_IN_USE

	## True only while this marker is the sole owner; ambiguous initialization/recovery races refuse writes.
	func owns() -> bool:
		return not owner.is_empty() and DirAccess.get_files_at(directory) == PackedStringArray([owner])

	static func _process_alive(pid: int) -> bool:
		if pid == OS.get_process_id():
			return true
		if OS.get_name() != "Windows":
			var processes: Array = []
			var result := OS.execute("ps", PackedStringArray(["-p", str(pid), "-o", "pid="]), processes, true)
			if result != 0 and result != 1:
				return true
			return "".join(processes).strip_edges() == str(pid)
		# Godot 4.7.2 on Windows only checks its own child-process map. A different game instance is not a child.
		# tasklist is an offline Windows system utility; query the numeric PID only, with no shell interpolation.
		var output: Array = []
		if OS.execute("tasklist", PackedStringArray(["/FI", "PID eq %d" % pid, "/FO", "CSV", "/NH"]), output, true) != 0:
			return true # Liveness could not be established: do not steal a possibly live save.
		for chunk: String in output:
			for line: String in chunk.split("\n"):
				if line.contains('\",\"%d\",' % pid):
					return true
		return false

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and not owner.is_empty():
			DirAccess.remove_absolute(directory.path_join(owner))
			DirAccess.remove_absolute(directory) # Only an empty directory is removed; another owner's marker survives.


## The best record of a stage ({} when none).
func best_for(stage_key: String) -> Dictionary:
	return best.get(stage_key, {})


## Runs finished on a stage.
func runs_for(stage_key: String) -> int:
	return int(runs.get(stage_key, 0))


## Records a finished round (legacy Flow summary); returns true when a new best was saved.
## Tool-only one-off rounds must skip persistence in their caller (#69).
func record(summary: Dictionary) -> bool:
	var data := _state()
	var is_new := _record_into(data, summary)
	if String(summary.get("stage", "")).is_empty():
		return false
	return is_new if _commit(data) == OK else false


static func _record_into(data: Dictionary, summary: Dictionary) -> bool:
	var stage := String(summary.get("stage", ""))
	if stage == "":
		return false
	data.runs[stage] = int(data.runs.get(stage, 0)) + 1
	var rec := record_from(summary)
	var is_new := is_better(rec, data.best.get(stage, {}))
	if is_new:
		data.best[stage] = rec.duplicate(true)
	return is_new


## The subset of a summary kept as a best record.
static func record_from(summary: Dictionary) -> Dictionary:
	var out := {}
	for k: String in RECORD_KEYS:
		if summary.has(k):
			out[k] = summary[k]
	return out


## One line describing a record: "Cleared, Lv. 31, 3,120 kills" or "Survived 08:32, Lv. 17, 1,342 kills" ("" when empty).
static func describe(rec: Dictionary) -> String:
	if rec.is_empty():
		return ""
	var t := int(float(rec.get("time", 0.0)))
	@warning_ignore("integer_division")
	var what := "Cleared" if bool(rec.get("cleared", false)) else "Survived %02d:%02d" % [t / 60, t % 60]
	return "%s, Lv. %d, %s kills" % [what, int(rec.get("level", 0)), _group(int(rec.get("kills", 0)))]


static func _group(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## True when record `a` beats record `b` (an empty `b` is beaten by anything).
static func is_better(a: Dictionary, b: Dictionary) -> bool:
	if b.is_empty():
		return true
	var ca := bool(a.get("cleared", false))
	var cb := bool(b.get("cleared", false))
	if ca != cb:
		return ca
	for k: String in ["time", "level", "kills", "damage_dealt"]:
		var va := float(a.get(k, 0))
		var vb := float(b.get(k, 0))
		if va != vb:
			return va > vb
	return false
