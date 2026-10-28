class_name SaveData
extends RefCounted
## Local save file (user://save.json): best results, round counts, character slots and the round history. Nothing leaves
## machine (docs/ARCHITECTURE.md section 7).
##
## File: {format: 3, best: {stage_key: record}, runs: {stage_key: int}, slots: [null | slot], history: [],
## account?: {nx: int, owned: [int]}}. The optional `account` (spec #34; see Account) is NX plus owned cash item ids:
## a save without it is an empty account.
## A best record is
## {time, duration, cleared, level, job_id, job_name, kills, damage_dealt, seed}. Missing files start empty;
## format 1 converts on load, keeping playable-stage bests/counts. Writes replace the file via a sibling temporary.
## Legacy stage keys migrate through DataRepo.STAGE_ALIASES on load and write, without changing the save format.
## Slot: {name, created, rounds_played, character: CharacterSnapshot (format 3)}. The character is saved at the hub
## (Free Market) and after every round; there is no saved round, tier cursor or seed to resume (ADR 0006, #286).
## History: one entry per round, {name, job_id, job_name, stage, level, ending, date} (level = reached in that round),
## plus one when a character is deleted (stage "", level 1) or retired. ending is
## cleared/died/quit (a round, finish_round), deleted (delete_slot) or retired (a character of a format-2 file, moved here
## on load unmigrated: level and stage are the ones it had). Format 2 history entries (died/victory/deleted, with
## tiers_cleared and rounds_played) are kept as they are. Dates are nonempty caller-supplied strings; persistence never
## generates gameplay dates or seeds.
## A round summary's `nx_awarded` is added to the account inside the same write as finish_round (every round ending);
## deletion never credits. set_account replaces the whole block (Cash Shop spending).
## Corrupt/unsupported files are copied to .bad[.N]; valid .bak recovers a missing or rejected primary.
## Web imports are staged at .import and fully validated here before promotion; rejection leaves committed files alone.
##
## Best result rule (tier C, ours): a clear beats a death; then the longer survival; then the higher level, more kills,
## more damage.

const PATH := "user://save.json"
const FORMAT := 3 # tier C: spec #282 / #286 (ADR 0006): characters without a saved round or build.
## History endings: a round (finish_round), a deleted or retired character, and format 2's "victory".
const ROUND_ENDINGS := ["cleared", "died", "quit"]
const HISTORY_ENDINGS := ["cleared", "died", "quit", "victory", "deleted", "retired"]
const SLOT_COUNT := 3 # tier C: spec #32 owner choice.
## Summary keys kept in a best record.
const RECORD_KEYS := ["time", "duration", "cleared", "level", "job_id", "job_name", "kills", "damage_dealt", "seed"]

var path := PATH
## stage key -> best record.
var best: Dictionary = {}
## stage key -> runs finished.
var runs: Dictionary = {}
## Detached views; mutate characters through create_slot/update_slot/finish_round/delete_slot.
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
var _writer_clock: Callable
## Lock acquisition error; tool paths opt out, while the default persistent save always opts in on desktop.
var writer_error: Error = OK


func _init(p_path: String = PATH, persistent: bool = false, clock: Callable = Callable()) -> void:
	path = p_path
	_writer_clock = clock
	_writer_required = (persistent or path == PATH) and not OS.has_feature("web")
	if _writer_required:
		_writer = WriterLock.new(clock)
		writer_error = _writer.acquire(ProjectSettings.globalize_path(path + ".lock"))
	load_file()


## Re-reads/converts the file, recovers a valid backup, then validates any shell-staged import before promotion.
func load_file() -> void:
	if renew_writer() != OK:
		last_error = writer_error
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
		var migrated := _apply_file(parsed)
		last_error = OK
		if source != path or int(parsed.format) < FORMAT or migrated:
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


func _apply_file(parsed: Dictionary) -> bool:
	var normalized := _canonical_stages(parsed)
	var migrated := normalized != parsed
	parsed = normalized
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
	# Format 1 validates only bests/counts: later fields must be ignored, not adopted without validation.
	var format := int(parsed.format)
	_slots = parsed.slots if format == FORMAT else [null, null, null]
	_history = parsed.get("history", []) if format >= 2 else []
	_account = Account.normalized(parsed.get("account", Account.empty())) if format >= 2 else Account.empty()
	if format == 2:
		# Format 3 has no saved build or round: a living character of an older file goes to the history, unmigrated.
		for old: Variant in parsed.slots:
			if old is Dictionary:
				_history.append(_retired_entry(old))
	return migrated


## The history entry of a format-2 character that this version cannot continue.
static func _retired_entry(old: Dictionary) -> Dictionary:
	var character: Dictionary = old.get("character", {})
	return {"name": old.name, "job_id": int(character.get("job_id", 0)),
		"job_name": job_name_of(int(character.get("job_id", 0))), "level": maxi(1, int(character.get("level", 1))),
		"stage": String(old.get("stage", "")), "ending": "retired", "date": String(old.get("created", "unknown"))}


static func _canonical_stages(source: Dictionary) -> Dictionary:
	var out := source.duplicate(true)
	out.best = {}
	out.runs = {}
	for old: String in source.best:
		var key := DataRepo.canonical_stage_key(old)
		var record: Variant = source.best[old]
		if record is Dictionary:
			record = record.duplicate(true)
			_canonical_stage_field(record)
			if is_better(record, out.best.get(key, {})):
				out.best[key] = record
	for old: String in source.runs:
		var key := DataRepo.canonical_stage_key(old)
		out.runs[key] = int(out.runs.get(key, 0)) + int(source.runs[old])
	# Format 1's extra fields have never been validated and must remain ignored.
	if int(source.format) >= 2:
		for snapshot: Variant in out.slots:
			if snapshot is Dictionary:
				_canonical_stage_field(snapshot)
		for entry: Dictionary in out.history:
			_canonical_stage_field(entry)
	return out


static func _canonical_stage_field(value: Dictionary) -> void:
	if value.has("stage"):
		value.stage = DataRepo.canonical_stage_key(String(value.stage))


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


## Renews desktop ownership; a lost lease permanently refuses writes until a fresh SaveData reloads committed state.
func renew_writer() -> Error:
	if _writer_required and writer_error == OK:
		writer_error = _writer.renew()
	return writer_error


## A retry always reloads committed state in a fresh session, retaining an injected clock for deterministic tools.
func reopen() -> SaveData:
	return SaveData.new(path, _writer_required, _writer_clock)


## Releases only this desktop lease on clean exit; tools and browser-owned stores have no desktop lease.
func release_writer() -> void:
	if _writer_required:
		_writer.release()
		writer_error = ERR_ALREADY_IN_USE


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


## Saves an occupied slot (the hub: equipment, scrolls and mesos changes) in one write.
func update_slot(index: int, snapshot: Dictionary) -> Error:
	if slot(index).is_empty():
		last_error = ERR_INVALID_PARAMETER
		return last_error
	if not validation_error(snapshot).is_empty() or not _name_available(String(snapshot.name), index):
		last_error = ERR_INVALID_DATA
		return last_error
	var data := _state()
	data.slots[index] = snapshot.duplicate(true)
	return _commit(data)


## Replaces the account (NX balance and owned cash items) in one write; ERR_INVALID_DATA for a malformed block.
func set_account(value: Variant) -> Error:
	if not Account.validation_error(value).is_empty():
		last_error = ERR_INVALID_DATA
		return last_error
	var data := _state()
	data.account = Account.normalized(value)
	return _commit(data)


## Ends a round for the character in slot `index`, in one write: the slot takes `snapshot` (its character as the round
## left it, pickups included), the summary counts toward the stage's best and run count and credits its NX, and the
## history gains the round (`ending` is one of ROUND_ENDINGS). The character is never removed: a death or a quit ends
## the round only. The date comes from the caller.
func finish_round(index: int, snapshot: Dictionary, ending: String, date: String, round_summary: Dictionary) -> Error:
	if slot(index).is_empty() or ending not in ROUND_ENDINGS or date.is_empty():
		last_error = ERR_INVALID_PARAMETER
		return last_error
	if not validation_error(snapshot).is_empty() or not _name_available(String(snapshot.name), index):
		last_error = ERR_INVALID_DATA
		return last_error
	var data := _state()
	data.slots[index] = snapshot.duplicate(true)
	var job_id := int(snapshot.character.job_id)
	data.history.append({"name": snapshot.name, "job_id": job_id, "job_name": job_name_of(job_id),
		"stage": DataRepo.canonical_stage_key(String(round_summary.get("stage", ""))),
		"level": maxi(1, int(round_summary.get("level", 1))), "ending": ending, "date": date})
	_record_into(data, round_summary)
	_credit(data, round_summary)
	return _commit(data)


## Frees slot `index` and appends a "deleted" history entry (no stage, level 1) in one save. The date comes from the caller.
func delete_slot(index: int, date: String) -> Error:
	if slot(index).is_empty() or date.is_empty():
		last_error = ERR_INVALID_PARAMETER
		return last_error
	var snapshot := slot(index)
	var job_id := int(snapshot.character.job_id)
	var data := _state()
	data.slots[index] = null
	data.history.append({"name": snapshot.name, "job_id": job_id, "job_name": job_name_of(job_id), "stage": "",
		"level": 1, "ending": "deleted", "date": date})
	return _commit(data)


## Immutable canonical names, loaded once per process.
static var _job_names: Dictionary = {}


## The canonical name of a job id, or the id as text when unknown.
static func job_name_of(job_id: int) -> String:
	if _job_names.is_empty():
		for job: Dictionary in DataRepo.load_all().jobs.get("jobs", []):
			_job_names[int(job.id)] = String(job.name)
	return String(_job_names.get(job_id, str(job_id)))


## Validates a slot (the run wrapper of specs #32 and #70, trimmed by #286) and delegates the character to CharacterSnapshot.
## Only a format-3 character is a living one; an older one is a history entry (see _apply_file).
static func validation_error(value: Variant) -> String:
	if not value is Dictionary or not _json_safe(value):
		return "expected a JSON-safe slot"
	if not value.get("name") is String or not _valid_name(value.name):
		return "name must be 4-12 letters or digits"
	if not value.get("created") is String or value.created.is_empty():
		return "invalid created date"
	var character: Variant = value.get("character")
	if not character is Dictionary or not _whole(character.get("format")) or int(character.format) != CharacterSnapshot.FORMAT:
		return "invalid CharacterSnapshot format"
	var character_error := CharacterSnapshot.validation_error(character)
	if not character_error.is_empty():
		return character_error
	if not _whole(value.get("rounds_played")):
		return "invalid rounds_played"
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
	if int(value.format) not in [1, 2, FORMAT] or not value.get("best") is Dictionary or not value.get("runs") is Dictionary:
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
		# A format-2 character is only read for its history entry: its name, job and level, not its build.
		if int(value.format) == 2:
			if not _valid_retiring_slot(snapshot):
				return false
		elif not validation_error(snapshot).is_empty():
			return false
		var name: String = snapshot.name.to_lower()
		if names.has(name):
			return false
		names[name] = true
	for entry: Variant in value.history:
		if not _valid_history_entry(entry):
			return false
	return true


static func _valid_retiring_slot(value: Variant) -> bool:
	if not value is Dictionary or not value.get("name") is String or not _valid_name(value.name) \
			or not value.get("character") is Dictionary:
		return false
	var character: Dictionary = value.character
	return _whole(character.get("job_id")) and (not character.has("level") or _whole(character.level)) \
		and (not value.has("stage") or value.stage is String) and (not value.has("created") or value.created is String)


static func _valid_history_entry(entry: Variant) -> bool:
	if not entry is Dictionary:
		return false
	for key: String in ["name", "job_name", "stage", "date"]:
		if not entry.get(key) is String:
			return false
	for key: String in ["job_id", "level"]:
		if not _whole(entry.get(key)):
			return false
	for key: String in ["tiers_cleared", "rounds_played"]: # format 2 entries only
		if entry.has(key) and not _whole(entry[key]):
			return false
	return int(entry.level) >= 1 and entry.get("ending") in HISTORY_ENDINGS


func _state() -> Dictionary:
	return {"format": FORMAT, "best": best.duplicate(true), "runs": runs.duplicate(true),
		"slots": _slots.duplicate(true), "history": _history.duplicate(true), "account": _account.duplicate(true)}


## Adds a finished round's NX to the account being written (a missing or negative nx_awarded adds nothing).
static func _credit(data: Dictionary, round_summary: Dictionary) -> void:
	data.account.nx = int(data.account.nx) + maxi(0, int(round_summary.get("nx_awarded", 0)))


func _commit(data: Dictionary) -> Error:
	data = _canonical_stages(data)
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
	if renew_writer() != OK:
		return writer_error
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
	if _primary_valid and FileAccess.file_exists(path):
		var previous := JSON.new()
		if previous.parse(FileAccess.get_file_as_string(path)) == OK and previous.data == JSON.parse_string(text):
			return OK # No state change: retain both committed byte sequences, including the older backup.
	# An old owner waking mid-write must not truncate or remove its replacement's staging file.
	var temporary := path + ".tmp" + ("." + _writer._session if _writer_required else "")
	var f := FileAccess.open(temporary, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.flush()
	var error := f.get_error()
	f.close()
	# A session may have slept while preparing the file. Check ownership again before touching committed bytes.
	if error == OK:
		error = renew_writer()
	# Windows DirAccess.rename removes the destination before moving. Keep a complete previous save so
	# load_file can recover if the process stops in that gap. Never move the only complete copy aside.
	if error == OK and _primary_valid and FileAccess.file_exists(path):
		error = DirAccess.copy_absolute(path, path + ".bak")
	if error == OK:
		error = renew_writer()
	if error == OK:
		error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
	else:
		_primary_valid = true
		# Refresh after successful writes as well as before them (unchanged saves already renewed on entry).
		# The bytes are already committed: keep the successful result even if renewal now fails; writer_error
		# makes all later writes read-only and the flow shows the notice on its next heartbeat.
		renew_writer()
	return error


## Atomic directory creation grants a renewable wall-clock lease without launching another process.
## Only the real save uses it. No simulation, test/tool save, or web engine needs a desktop session lock.
class WriterLock extends RefCounted:
	# tier C: renew every five real seconds; thirty seconds without renewal permits crash/sleep takeover.
	const RENEW_SECONDS := 5.0
	const STALE_SECONDS := 30.0
	var directory := ""
	var owner := ""
	# tier C: a random 128-bit session id keeps owner generations distinct across independent game processes.
	var _session := Crypto.new().generate_random_bytes(16).hex_encode()
	var _generation := 0
	var _lost := false
	var _clock: Callable

	func _init(clock: Callable = Callable()) -> void:
		_clock = clock if clock.is_valid() else func() -> float: return Time.get_unix_time_from_system()

	## Claims an empty directory, or removes only expired owner generations before retrying exclusive mkdir.
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
				if name.ends_with(".owner") and _now() - _renewed_at(name) >= STALE_SECONDS:
					# Renewal always uses a new filename, so this never deletes a concurrently renewed generation.
					removed = DirAccess.remove_absolute(directory.path_join(name)) == OK or removed
			var empty := DirAccess.get_files_at(directory).is_empty() and DirAccess.get_directories_at(directory).is_empty()
			var expired := _now() - FileAccess.get_modified_time(directory) >= STALE_SECONDS
			if empty and (removed or expired):
				DirAccess.remove_absolute(directory)
			error = DirAccess.make_dir_absolute(directory)
			if error != OK:
				return ERR_ALREADY_IN_USE
		owner = _next_owner()
		error = _publish(owner)
		if error != OK:
			return error
		return OK if owns() else ERR_ALREADY_IN_USE

	## True only while this marker is the sole owner; ambiguous initialization/recovery races refuse writes.
	func owns() -> bool:
		if _lost or owner.is_empty():
			return false
		if DirAccess.get_files_at(directory) != PackedStringArray([owner]) \
				or not DirAccess.get_directories_at(directory).is_empty():
			_lost = true
		return not _lost

	## Publishes a unique generation before retiring the old one; races fail closed instead of reviving a stale lease.
	func renew() -> Error:
		if not owns():
			return ERR_ALREADY_IN_USE
		var next := _next_owner()
		var error := _publish(next)
		if error == OK:
			error = DirAccess.remove_absolute(directory.path_join(owner))
		if error != OK:
			DirAccess.remove_absolute(directory.path_join(next))
			_lost = true
			return error
		owner = next
		return OK if owns() else ERR_ALREADY_IN_USE

	## Removes only this generation; an old session can never release its replacement's lease.
	func release() -> void:
		if not owner.is_empty():
			DirAccess.remove_absolute(directory.path_join(owner))
			DirAccess.remove_absolute(directory) # Removal succeeds only when empty.
		owner = ""
		_lost = true

	func _next_owner() -> String:
		_generation += 1
		return "%s.%d.owner" % [_session, _generation]

	func _publish(name: String) -> Error:
		var file := FileAccess.open(directory.path_join(name), FileAccess.WRITE)
		if file == null:
			return FileAccess.get_open_error()
		file.store_string(JSON.stringify({"owner": _session, "renewed_at": _now()}))
		file.flush()
		var error := file.get_error()
		file.close()
		return error

	func _renewed_at(name: String) -> float:
		var marker := directory.path_join(name)
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(marker)) == OK and json.data is Dictionary:
			var value: Variant = json.data.get("renewed_at")
			if json.data.get("owner") is String and (value is float or value is int) and is_finite(float(value)):
				return float(value)
		# Interrupted/legacy marker creation is recoverable too; malformed bytes never count as a fresh renewal.
		return float(FileAccess.get_modified_time(marker))

	func _now() -> float:
		return float(_clock.call())

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and not owner.is_empty():
			# RefCounted is already at zero here; calling another instance method cannot retain self.
			DirAccess.remove_absolute(directory.path_join(owner))
			DirAccess.remove_absolute(directory)


## The best record of a stage ({} when none).
func best_for(stage_key: String) -> Dictionary:
	return best.get(DataRepo.canonical_stage_key(stage_key), {})


## Runs finished on a stage.
func runs_for(stage_key: String) -> int:
	return int(runs.get(DataRepo.canonical_stage_key(stage_key), 0))


## Records a finished round (legacy Flow summary); returns true when a new best was saved.
## Tool-only one-off rounds must skip persistence in their caller (#69).
func record(summary: Dictionary) -> bool:
	var data := _state()
	var is_new := _record_into(data, summary)
	if String(summary.get("stage", "")).is_empty():
		return false
	return is_new if _commit(data) == OK else false


static func _record_into(data: Dictionary, summary: Dictionary) -> bool:
	var stage := DataRepo.canonical_stage_key(String(summary.get("stage", "")))
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
