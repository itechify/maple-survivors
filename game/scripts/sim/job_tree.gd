class_name JobTree
extends RefCounted
## Data-driven job advancement (docs/GAME_DESIGN.md section 9): the canonical Explorer tree
## (`data/canonical/jobs.json`: id, name, parent, tier, level) plus the survivor flags (`data/survivor/jobs.json`:
## playable, reason, grants).
##
## advancements(job, level) lists every child job of `job` as `{job_id, name, available, reason}`: available when it
## is playable and `level` reached its canonical advancement level; otherwise `reason` says why ("Lv. 10" while the
## level is too low, else the survivor reason such as "Not in this build"). should_offer() decides whether a window
## opens at a level: whenever an option is available (so "Not now" asks again next level), and once at exactly the
## tier's first advancement level even when nothing is available (the Lv 30 window of GAME_DESIGN 9).

var _jobs := {}
var _children := {}
var _survivor := {}
var _default_reason := "Not yet available"
var _level_reason := "Lv. {level}"


## Builds the tree from the canonical jobs.json root ({"jobs": [...]}) and the survivor jobs.json root.
static func from_data(canonical: Dictionary, survivor: Dictionary) -> JobTree:
	var t := JobTree.new()
	for j: Dictionary in canonical.get("jobs", []):
		var id := int(j.get("id", 0))
		var rec := {
			"id": id, "name": String(j.get("name", str(id))), "parent": int(j.get("parent", -1)),
			"tier": int(j.get("tier", 0)), "level": int(j.get("level", 1)), "book": String(j.get("book", "")),
		}
		t._jobs[id] = rec
	for id: int in t._jobs:
		var p: int = t._jobs[id].parent
		if not t._children.has(p):
			t._children[p] = []
		t._children[p].append(id)
	var sj: Variant = survivor.get("jobs", {})
	if sj is Dictionary:
		for k: String in sj:
			t._survivor[int(k)] = sj[k]
	t._default_reason = String(survivor.get("default_reason", t._default_reason))
	t._level_reason = String(survivor.get("level_reason", t._level_reason))
	return t


## Canonical record {id, name, parent, tier, level, book} plus the survivor `playable`, `reason`, `grants`; {} when
## unknown.
func job(id: int) -> Dictionary:
	if not _jobs.has(id):
		return {}
	var d: Dictionary = _jobs[id].duplicate()
	var s: Dictionary = _survivor.get(id, {})
	d["playable"] = bool(s.get("playable", false))
	d["reason"] = String(s.get("reason", _default_reason))
	d["grants"] = s.get("grants", {})
	return d


## Display name of a job ("" when unknown).
func name_of(id: int) -> String:
	return String(_jobs[id].name) if _jobs.has(id) else ""


## Child job ids of `id` in data order.
func children(id: int) -> Array:
	return _children.get(id, []).duplicate()


## The options of the advancement window for a player of `job_id` at `level`: [{job_id, name, available, reason}].
func advancements(job_id: int, level: int) -> Array:
	var out: Array = []
	for c: int in _children.get(job_id, []):
		var j := job(c)
		var available := false
		var reason := ""
		if level < int(j.level):
			reason = _level_reason.replace("{level}", str(j.level))
		elif not j.playable:
			reason = j.reason
		else:
			available = true
		out.append({"job_id": c, "name": j.name, "available": available, "reason": reason})
	return out


## Lowest canonical advancement level among the children of `job_id` (-1 when it has none).
func first_advance_level(job_id: int) -> int:
	var lo := -1
	for c: int in _children.get(job_id, []):
		var l := int(_jobs[c].level)
		if lo < 0 or l < lo:
			lo = l
	return lo


## Whether the advancement window opens for `job_id` at `level` (see the class comment).
func should_offer(job_id: int, level: int) -> bool:
	var first := first_advance_level(job_id)
	if first < 0 or level < first:
		return false
	if level == first:
		return true
	for o: Dictionary in advancements(job_id, level):
		if o.available:
			return true
	return false


## True when `job_id` is `ancestor` or descends from it.
func is_descendant(job_id: int, ancestor: int) -> bool:
	var j := job_id
	var guard := 0
	while guard < 16:
		if j == ancestor:
			return true
		if not _jobs.has(j):
			return false
		j = int(_jobs[j].parent)
		guard += 1
	return false


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
