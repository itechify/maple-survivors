class_name JobTree
extends RefCounted
## Data-driven job advancement (docs/GAME_DESIGN.md section 9): the canonical Explorer tree
## (`data/canonical/jobs.json`: id, name, parent, tier, level) plus the survivor flags (`data/survivor/jobs.json`:
## playable, reason, grants, optional level override).
##
## advancements(job, level) lists every child job of `job` as `{job_id, name, available, reason}`: available when it
## is playable and `level` reached its effective advancement level; otherwise `reason` says why ("Lv. 10" while the
## level is too low, else the survivor reason such as "Not in this build"). A first job with weapon `paths` (survivor
## jobs.json `paths`: [{id, label, item_id, family}], spec #151 #157) is listed once per path while it is playable (a locked one stays a single entry), each entry carrying its
## `path` id and the path label as its name; other entries have no `path` key. A second job may list the
## `weapon_families` it can use and one advancement weapon per family (`grant_items`): branch_grant() reads them. should_offer() decides whether a window
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


## Canonical record {id, name, parent, tier, level, book} with the survivor level override and
## `playable`, `reason`, `grants`; {} when unknown. The source canonical record is never modified.
func job(id: int) -> Dictionary:
	if not _jobs.has(id):
		return {}
	var d: Dictionary = _jobs[id].duplicate()
	var s: Dictionary = _survivor.get(id, {})
	d["level"] = int(s.get("level", d.level))
	d["playable"] = bool(s.get("playable", false))
	d["reason"] = String(s.get("reason", _default_reason))
	d["grants"] = s.get("grants", {})
	d["paths"] = paths_of(id)
	return d


## The weapon paths of first job `id` (survivor jobs.json `paths`): [{id, label, item_id, family}], [] when it has none.
func paths_of(id: int) -> Array:
	var raw: Variant = _survivor.get(id, {}).get("paths", [])
	var out: Array = []
	if raw is Array:
		for p: Variant in raw:
			if p is Dictionary and String(p.get("id", "")) != "":
				out.append({"id": String(p.id), "label": String(p.get("label", p.id)),
					"item_id": int(p.get("item_id", 0)), "family": String(p.get("family", ""))})
	return out


## The path `path_id` of `job_id` or of its first-job ancestor ({} when the line has no such path).
func path_of(job_id: int, path_id: String) -> Dictionary:
	for j in lineage(job_id):
		for p: Dictionary in paths_of(j):
			if p.id == path_id:
				return p
	return {}


## The weapon families a second job can use (survivor jobs.json `weapon_families`); [] when the row lists none.
func weapon_families(job_id: int) -> Array:
	var families: Variant = _survivor.get(job_id, {}).get("weapon_families", [])
	return families.map(func(f: Variant) -> String: return String(f)) if families is Array else []


## A second job's advancement weapons (survivor jobs.json `weapon_families` + `grant_items`, one item id per family in the
## same order): {weapons: [{family, item_id}]} in weapon_families order. A family without an item id (missing or <= 0) is
## skipped; {} when no family has one (nothing is granted then).
func branch_grant(job_id: int) -> Dictionary:
	var families := weapon_families(job_id)
	var raw: Variant = _survivor.get(job_id, {}).get("grant_items", [])
	var items: Array = raw if raw is Array else []
	var weapons: Array = []
	for i in mini(families.size(), items.size()):
		if int(items[i]) > 0:
			weapons.append({"family": families[i], "item_id": int(items[i])})
	return {} if weapons.is_empty() else {"weapons": weapons}


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
		if j.paths.is_empty() or not j.playable: # a locked job stays one entry
			out.append({"job_id": c, "name": j.name, "available": available, "reason": reason})
		else:
			for p: Dictionary in j.paths:
				out.append({"job_id": c, "path": p.id, "name": p.label, "available": available, "reason": reason})
	return out


## Lowest effective advancement level among the children of `job_id` (-1 when it has none).
func first_advance_level(job_id: int) -> int:
	var lo := -1
	for c: int in _children.get(job_id, []):
		var l := int(job(c).level)
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


## The survivor-data field `key` of `job_id`, else of its nearest ancestor that has it; `fallback` when no job in the
## line does (the same lineage walk as RunWorld's per-job balance tables).
func lineage_value(job_id: int, key: String, fallback: Variant = null) -> Variant:
	for j in lineage(job_id):
		var s: Dictionary = _survivor.get(j, {})
		if s.has(key):
			return s[key]
	return fallback


## The second job (tier 2) on `job_id`'s line, else 0: 210 -> 210, 230 -> 230, 200 and 0 -> 0.
func second_job(job_id: int) -> int:
	for j in lineage(job_id):
		if int(_jobs[j].tier) == 2:
			return j
	return 0


## Splits a `--job=<id>[:<path>]` value into {job: int, path: String} (`400:claw` -> 400 and "claw"; `210` -> 210 and "").
static func parse_forced(spec: String) -> Dictionary:
	var parts := spec.strip_edges().split(":", true, 1)
	return {"job": int(parts[0]), "path": parts[1].strip_edges() if parts.size() > 1 else ""}


## Parses a `--job=<id>[:<path>]` value into run `options` (`job`, and `job_path` when a path is named): the one parser
## the run flags (SceneFlow), the launcher and the balance tool share. Returns {job, path}.
static func put_forced(options: Dictionary, spec: String) -> Dictionary:
	var forced := parse_forced(spec)
	options["job"] = int(forced.job)
	if String(forced.path) != "":
		options["job_path"] = String(forced.path)
	return forced


## Why the tools cannot force `job_id` ("" when they can): it must be a first or second job of the canonical tree
## (tier 1 or 2) and every job on its line below the Beginner must be playable in this build. A forced `path` must be
## one of the line's first-job weapon paths.
func forced_job_error(job_id: int, path := "") -> String:
	if not _jobs.has(job_id):
		return "job %d is not in the canonical job tree" % job_id
	var tier := int(_jobs[job_id].tier)
	if tier < 1 or tier > 2:
		return "job %d (%s) is not a first or second job" % [job_id, name_of(job_id)]
	for j in lineage(job_id):
		var rec := job(j)
		if int(rec.tier) > 0 and not bool(rec.playable):
			return "job %d (%s) is not playable in this build (%s)" % [j, name_of(j), rec.reason]
	if path != "" and path_of(job_id, path).is_empty():
		return "job %d (%s) has no weapon path '%s'" % [job_id, name_of(job_id), path]
	return ""
