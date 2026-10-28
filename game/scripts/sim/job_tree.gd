class_name JobTree
extends RefCounted
## The canonical Explorer job tree (`data/canonical/jobs.json`: id, name, parent, tier, level, book) plus the survivor
## flags (`data/survivor/jobs.json`: playable, reason, skill_pool, starting_skill, mobility_skill). ADR 0006: a character is one job, fixed for its
## life; there is no advancement. The tree stays for the lineage lookups (per-job balance rows, accuracy and ammo rules) and for names.
##
## playable_jobs() are the jobs a character can be, default_job() the one a fresh character and the tools get, and
## job_error(id) why a tool cannot make a character of job `id` ("" when it can).

var _jobs := {}
var _order: Array[int] = []
var _survivor := {}
var _default_reason := "Not yet available"


## Builds the tree from the canonical jobs.json root ({"jobs": [...]}) and the survivor jobs.json root.
static func from_data(canonical: Dictionary, survivor: Dictionary) -> JobTree:
	var t := JobTree.new()
	for j: Dictionary in canonical.get("jobs", []):
		var id := int(j.get("id", 0))
		t._jobs[id] = {
			"id": id, "name": String(j.get("name", str(id))), "parent": int(j.get("parent", -1)),
			"tier": int(j.get("tier", 0)), "level": int(j.get("level", 1)), "book": String(j.get("book", "")),
		}
		t._order.append(id)
	var sj: Variant = survivor.get("jobs", {})
	if sj is Dictionary:
		for k: String in sj:
			t._survivor[int(k)] = sj[k]
	t._default_reason = String(survivor.get("default_reason", t._default_reason))
	return t


## Canonical record {id, name, parent, tier, level, book} with the survivor `playable`, `reason` and `start_skills`;
## {} when unknown. The source canonical record is never modified.
func job(id: int) -> Dictionary:
	if not _jobs.has(id):
		return {}
	var d: Dictionary = _jobs[id].duplicate()
	var s: Dictionary = _survivor.get(id, {})
	d["playable"] = bool(s.get("playable", false))
	d["reason"] = String(s.get("reason", _default_reason))
	d["skill_pool"] = skill_pool(id)
	d["starting_skill"] = starting_skill(id)
	d["mobility_skill"] = mobility_skill(id)
	return d


## The playable job ids in canonical data order.
func playable_jobs() -> Array[int]:
	var out: Array[int] = []
	for id in _order:
		if bool(_survivor.get(id, {}).get("playable", false)):
			out.append(id)
	return out


## The job of a fresh character (the first playable job); 0 when the data has none.
func default_job() -> int:
	var ids := playable_jobs()
	return ids[0] if not ids.is_empty() else 0


## Curated active skill keys for this exact job (not inherited).
func skill_pool(id: int) -> Array:
	return _survivor.get(id, {}).get("skill_pool", [])


## The skill occupying active slot one at the start of a round.
func starting_skill(id: int) -> String:
	return String(_survivor.get(id, {}).get("starting_skill", ""))


## Manual mobility outside both slot tracks.
func mobility_skill(id: int) -> String:
	return String(_survivor.get(id, {}).get("mobility_skill", ""))


## Initial learning order: starting active, then manual mobility.
func start_skills(id: int) -> PackedStringArray:
	var out := PackedStringArray()
	for key in [starting_skill(id), mobility_skill(id)]:
		if key != "":
			out.append(key)
	return out


## Display name of a job ("" when unknown).
func name_of(id: int) -> String:
	return String(_jobs[id].name) if _jobs.has(id) else ""


## True when `job_id` is `ancestor` or descends from it.
func is_descendant(job_id: int, ancestor: int) -> bool:
	return ancestor in lineage(job_id)


## `job_id` followed by its ancestors up to the root.
func lineage(job_id: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var j := job_id
	var guard := 0
	while guard < 16 and _jobs.has(j):
		out.append(j)
		j = int(_jobs[j].parent)
		guard += 1
	return out


## The survivor-data field `key` of `job_id`, else of its nearest ancestor that has it; `fallback` when no job in the
## line does.
func lineage_value(job_id: int, key: String, fallback: Variant = null) -> Variant:
	for j in lineage(job_id):
		var s: Dictionary = _survivor.get(j, {})
		if s.has(key):
			return s[key]
	return fallback


## Why the tools cannot make a character of job `job_id` ("" when they can): it must be in the canonical tree and
## playable in this build.
func job_error(job_id: int) -> String:
	if not _jobs.has(job_id):
		return "job %d is not in the canonical job tree" % job_id
	var rec := job(job_id)
	if not bool(rec.playable):
		return "job %d (%s) is not playable in this build (%s)" % [job_id, name_of(job_id), rec.reason]
	return ""


## The job id a tool's `--job=<id>` value names, -1 when it is not a whole number (`212`; the old `<id>:<path>` form is
## refused: weapon paths are gone).
static func parse_job(spec: String) -> int:
	var s := spec.strip_edges()
	return int(s) if s.is_valid_int() else -1


## Stores a tool's `--job=<id>` value in run `options` (`job`: parse_job's id; `job_text`: the raw value, for the error
## of a malformed one): the one parser the run flags (SceneFlow), the launcher and the balance tool share. Returns the id.
static func put_job(options: Dictionary, spec: String) -> int:
	options["job"] = parse_job(spec)
	options["job_text"] = spec
	return int(options.job)
