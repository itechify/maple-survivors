class_name SkillTemplate
extends RefCounted
## Skill templates (spec #319 I5, M19, GAME_DESIGN 7.63): a skill definition may carry `"extends": "<parent key>"` to say
## "I am that skill, in my book". The resolved child is a deep copy of the parent with the child's own keys on top, and
## the parent's art and sound paths rewritten to the child's book and skill id. Pure static data transforms; SkillBook
## resolves once, after every line fragment has merged, so nothing depends on DataRepo.lines() order. Tier C (mechanism):
## the three Big Bangs (2121001, 2221001, 2321001) are identical in the v83 data (tier A, `drift_problems` re-checks it).

const KEY := "extends"
## Keys a child must state itself (its identity); everything else it may inherit.
const REQUIRED: PackedStringArray = ["skill_id", "book", "job"]
## Levels compared by the drift guard: the eight survivor ranks of SkillBook.canonical_level.
const MAPPED_LEVELS := 8


## `skills` (the `skills` entries of the merged skills data) with every template resolved. A child that breaks a rule
## (listed in `errors`) is left out. Without a single `extends` the same dictionary comes back, so plain data is
## untouched; otherwise a new dictionary in the same key order, plain definitions shared with the input and children new.
static func resolve(skills: Dictionary, errors: PackedStringArray = PackedStringArray()) -> Dictionary:
	var templated := false
	for key: Variant in skills:
		var d: Variant = skills[key]
		if d is Dictionary and (d as Dictionary).has(KEY):
			templated = true
			break
	if not templated:
		return skills
	var out := {}
	for key: Variant in skills:
		var d: Variant = skills[key]
		if not (d is Dictionary and (d as Dictionary).has(KEY)):
			out[key] = d
			continue
		var child := _resolve_one(String(key), d, skills, errors)
		if not child.is_empty():
			out[key] = child
	return out


## The resolved definition of one child, or {} after reporting why it is refused.
static func _resolve_one(key: String, child: Dictionary, skills: Dictionary, errors: PackedStringArray) -> Dictionary:
	var parent_key: Variant = child[KEY]
	if not (parent_key is String) or String(parent_key) == "":
		errors.append("skill '%s': extends must be the key of another skill, not %s" % [key, JSON.stringify(parent_key)])
		return {}
	var missing := PackedStringArray()
	for field in REQUIRED:
		if not child.has(field):
			missing.append(field)
	if not missing.is_empty():
		errors.append("skill '%s': a template that extends '%s' must state its own %s (missing %s)"
				% [key, parent_key, ", ".join(REQUIRED), ", ".join(missing)])
		return {}
	var parent: Variant = skills.get(parent_key)
	if not (parent is Dictionary):
		errors.append("skill '%s': extends '%s', which is not a skill defined in the skills data" % [key, parent_key])
		return {}
	if (parent as Dictionary).has(KEY):
		errors.append("skill '%s': extends '%s', which itself extends '%s' (a template extends a plain skill, one level only)"
				% [key, parent_key, String((parent as Dictionary)[KEY])])
		return {}
	var inherited: Dictionary = _inherit(parent)
	var from_prefix := _wz_ids(parent)
	var to_prefix := _wz_ids(child)
	if from_prefix.is_empty() or to_prefix.is_empty():
		errors.append("skill '%s': skill_id and book of '%s' or of '%s' are not usable" % [key, key, parent_key])
		return {}
	inherited = rewrite_paths(inherited, from_prefix, to_prefix)
	return _merge(inherited, child)


## [book, "%07d" id] of a definition, or [] when it has neither a book nor a positive skill id.
static func _wz_ids(d: Dictionary) -> Array:
	var book := String(d.get("book", ""))
	var id := int(d.get("skill_id", 0))
	if book == "" or id <= 0:
		return []
	return [book, "%07d" % id]


## A deep copy of the parent without its `_`-prefixed documentation keys (at every depth).
static func _inherit(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for k: Variant in value:
			if not (k is String and String(k).begins_with("_")):
				out[k] = _inherit(value[k])
		return out
	if value is Array:
		var arr := []
		for v: Variant in value:
			arr.append(_inherit(v))
		return arr
	return value


## `base` with `over` on top: dictionaries merge key by key, arrays and scalars are replaced. Both are deep-copied.
static func _merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	for k: Variant in over:
		var v: Variant = over[k]
		if v is Dictionary and out.get(k) is Dictionary:
			out[k] = _merge(out[k], v)
		else:
			out[k] = v.duplicate(true) if (v is Dictionary or v is Array) else v
	return out


## `value` with every string's `Skill.wz/<from book>.img/skill/<from id>` and `Sound.wz/Skill.img/<from id>` replaced by
## the same path of `to` ([book, id7] pairs from `_wz_ids`). Matching is at a path boundary: the id must be followed by
## `/` or the end of the string, and the path must not continue a longer word at its start. Keys are not rewritten.
static func rewrite_paths(value: Variant, from: Array, to: Array) -> Variant:
	if value is String:
		var s := String(value)
		s = _swap(s, "Skill.wz/%s.img/skill/%s" % from, "Skill.wz/%s.img/skill/%s" % to)
		return _swap(s, "Sound.wz/Skill.img/%s" % from[1], "Sound.wz/Skill.img/%s" % to[1])
	if value is Dictionary:
		var out := {}
		for k: Variant in value:
			out[k] = rewrite_paths(value[k], from, to)
		return out
	if value is Array:
		var arr := []
		for v: Variant in value:
			arr.append(rewrite_paths(v, from, to))
		return arr
	return value


static func _swap(s: String, from: String, to: String) -> String:
	var out := ""
	var at := 0
	while true:
		var i := s.find(from, at)
		if i < 0:
			break
		var end := i + from.length()
		var before_ok := i == 0 or not _is_word(s[i - 1])
		var after_ok := end == s.length() or s[end] == "/"
		out += s.substr(at, i - at) + (to if before_ok and after_ok else from)
		at = end
	return out + s.substr(at)


static func _is_word(c: String) -> bool:
	return c == "_" or (c >= "0" and c <= "9") or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z")


## Every resolved template of `book` as [child key, parent key], in definition order.
static func pairs(book: SkillBook) -> Array:
	var out := []
	for key: String in book.defs:
		var parent: Variant = book.defs[key].get(KEY)
		if parent is String:
			out.append([key, parent])
	return out


## The drift guard (spec #319 M19): what differs between a template and its parent in the Skill.wz data `book` holds.
## Empty means they agree: the same canonical level node at each of the eight mapped levels (every number and vector),
## the same count of art nodes under every top-level key of the skill node (`level` aside), and every Skill.wz / Sound.wz
## path of the child resolves (`exists(path) -> bool`; `{level}` and `{cl}` take level 1 and 0). A book that ever
## differs must be overridden by the child, which is the point.
static func drift_problems(book: SkillBook, child: String, parent: String, exists: Callable) -> PackedStringArray:
	var out := PackedStringArray()
	var cn := book.skill_node(child)
	var pn := book.skill_node(parent)
	if cn.is_empty() or pn.is_empty():
		out.append("%s extends %s: no canonical node (%s: %s, %s: %s)" % [child, parent,
				child, book.wz_path(child), parent, book.wz_path(parent)])
		return out
	for rank in range(1, MAPPED_LEVELS + 1):
		var cl := book.canonical_level(child, rank)
		var pl := book.canonical_level(parent, rank)
		var cnode := book.level_node(child, cl)
		var pnode := book.level_node(parent, pl)
		for field: Variant in _union(cnode, pnode):
			if cnode.get(field) != pnode.get(field):
				out.append("%s extends %s: rank %d (level %d vs %d) %s is %s vs %s"
						% [child, parent, rank, cl, pl, field, cnode.get(field), pnode.get(field)])
	for field: Variant in _union(cn, pn):
		if field == "level":
			continue
		var c := _count_nodes(cn.get(field))
		var p := _count_nodes(pn.get(field))
		if c != p:
			out.append("%s extends %s: art node count of '%s' is %d vs %d" % [child, parent, field, c, p])
	var seen := {}
	for p: String in _wz_paths(book.def(child)):
		var path := SkillBook.fill_path(p, book.canonical_level(child, 1), 0)
		if not seen.has(path):
			seen[path] = true
			if not bool(exists.call(path)):
				out.append("%s: rewritten path %s does not resolve" % [child, path])
	return out


static func _union(a: Dictionary, b: Dictionary) -> Array:
	var keys := a.keys()
	for k: Variant in b:
		if not a.has(k):
			keys.append(k)
	return keys


## Nodes at and below `v`: a Dictionary counts itself and its children, anything else one.
static func _count_nodes(v: Variant) -> int:
	if v == null:
		return 0
	var n := 1
	if v is Dictionary:
		for k: Variant in v:
			n += _count_nodes(v[k])
	return n


## Every string of a definition that names a WZ node (Skill.wz/ or Sound.wz/).
static func _wz_paths(value: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if value is String:
		if String(value).begins_with("Skill.wz/") or String(value).begins_with("Sound.wz/"):
			out.append(value)
	elif value is Dictionary:
		for k: Variant in value:
			out.append_array(_wz_paths(value[k]))
	elif value is Array:
		for v: Variant in value:
			out.append_array(_wz_paths(v))
	return out
