class_name SaveData
extends RefCounted
## Local save file (user://save.json): the best result per stage and run counts. Local only; nothing leaves the
## machine (docs/ARCHITECTURE.md section 7).
##
## File: {"format": 1, "best": {stage_key: record}, "runs": {stage_key: int}} where a record is
## {time, duration, cleared, level, job_id, job_name, kills, damage_dealt, seed}. Loading a missing or broken file
## gives an empty save (never an error); the file is written by record() / save_file() only.
##
## Best result rule (tier C, ours): a clear beats a death; then the longer survival; then the higher level, more kills,
## more damage.

const PATH := "user://save.json"
const FORMAT := 1
## Summary keys kept in a best record.
const RECORD_KEYS := ["time", "duration", "cleared", "level", "job_id", "job_name", "kills", "damage_dealt", "seed"]

var path := PATH
## stage key -> best record.
var best: Dictionary = {}
## stage key -> runs finished.
var runs: Dictionary = {}


func _init(p_path: String = PATH) -> void:
	path = p_path
	load_file()


## Re-reads the file (an absent or invalid file leaves an empty save).
func load_file() -> void:
	best = {}
	runs = {}
	if not FileAccess.file_exists(path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return
	var parsed: Variant = json.data
	if not (parsed is Dictionary) or int((parsed as Dictionary).get("format", 0)) != FORMAT:
		return
	var b: Variant = parsed.get("best", {})
	if b is Dictionary:
		for k: Variant in b:
			if b[k] is Dictionary:
				best[String(k)] = b[k]
	var r: Variant = parsed.get("runs", {})
	if r is Dictionary:
		for k: Variant in r:
			runs[String(k)] = int(r[k])


## Writes the file (creating its folder).
func save_file() -> Error:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"format": FORMAT, "best": best, "runs": runs}, "\t"))
	f.close()
	return OK


## The best record of a stage ({} when none).
func best_for(stage_key: String) -> Dictionary:
	return best.get(stage_key, {})


## Runs finished on a stage.
func runs_for(stage_key: String) -> int:
	return int(runs.get(stage_key, 0))


## Records a finished run (a Flow summary): counts it, keeps it as the stage's best when better, saves.
## Returns true when it is a new best.
func record(summary: Dictionary) -> bool:
	var stage := String(summary.get("stage", ""))
	if stage == "":
		return false
	runs[stage] = runs_for(stage) + 1
	var rec := record_from(summary)
	var is_new := is_better(rec, best_for(stage))
	if is_new:
		best[stage] = rec
	save_file()
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
