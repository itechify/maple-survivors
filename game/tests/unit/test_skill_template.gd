extends TestCase
## Skill templates (spec #319 I5, M19, GAME_DESIGN 7.63): `"extends": "<key>"` in a skill definition inherits another
## definition and rewrites its art and sound paths to the child's own book and skill id (SkillTemplate, resolved in
## SkillBook). Merge, rewrite and validation are tested on synthetic data; the drift guard on the shipped data and a
## synthetic pair, against the real cache when it is imported.

const WORK := "skill_template"


func after_each() -> void:
	remove_tree(test_dir(WORK))


## A parent shaped like F/P's big_bang: every string kind the rewrite meets.
func _parent() -> Dictionary:
	return {
		"skill_id": 2121001, "book": "212", "job": 212, "kind": "instant", "name": "Big Bang",
		"_provenance": "parent note", "_rarity": "parent rarity note",
		"icon": "Skill.wz/212.img/skill/2121001/icon",
		"effect": "Skill.wz/212.img/skill/2121001/keydown",
		"release_visuals": ["Skill.wz/212.img/skill/2121001/special/0"],
		"desc": "Mentions 2121001 and Skill.wz/212.img/skill/21210010/x without being a path to it.",
		"sounds": {"use": "Sound.wz/Skill.img/2121001/Use", "loop": "Sound.wz/Skill.img/2121001/Loop"},
		"pending": {"delay": 1.08, "effect": "Skill.wz/212.img/skill/2121001/effect", "follow_player": true},
		"ranks": [1, 2, 3, 4, 5, 6, 7, 8],
		"rarity_bonuses": {"rare": [{"id": "power", "text": "Damage", "effects": [{"stat": "damage", "op": "mul", "value": 1.2}]}]},
		"cast": {"rule": "box", "box": {"lt": {"$v": [-250, -180]}, "rb": {"$v": [250, 100]}}},
	}


func _child() -> Dictionary:
	return {"extends": "big_bang", "skill_id": 2221001, "book": "222", "job": 222}


func _resolve(skills: Dictionary, errors: PackedStringArray = PackedStringArray()) -> Dictionary:
	return SkillTemplate.resolve(skills, errors)


func test_three_line_child_inherits_everything_with_its_own_identity() -> void:
	var errors := PackedStringArray()
	var out := _resolve({"big_bang": _parent(), "big_bang_il": _child()}, errors)
	assert_true(errors.is_empty(), "%s" % [errors])
	var il: Dictionary = out.big_bang_il
	assert_eq(il.skill_id, 2221001)
	assert_eq(il.book, "222")
	assert_eq(il.job, 222)
	assert_eq(il["extends"], "big_bang")
	assert_eq(il.name, "Big Bang")
	assert_eq(il.kind, "instant")
	assert_eq(il.ranks, [1, 2, 3, 4, 5, 6, 7, 8])
	assert_eq(il.rarity_bonuses, _parent().rarity_bonuses, "rarity bonuses inherit untouched")
	assert_eq(il.cast, _parent().cast)
	assert_eq(il.pending.delay, 1.08)


func test_child_keys_win_dictionaries_merge_arrays_and_scalars_replace() -> void:
	var child := _child()
	child["name"] = "Big Bang (I/L)"
	child["ranks"] = [2, 4]
	child["cast"] = {"box": {"lt": {"$v": [-100, -100]}}}
	child["pending"] = {"delay": 0.5}
	var il: Dictionary = _resolve({"big_bang": _parent(), "big_bang_il": child}).big_bang_il
	assert_eq(il.name, "Big Bang (I/L)")
	assert_eq(il.ranks, [2, 4], "an array replaces, never concatenates")
	assert_eq(il.cast.rule, "box", "a dictionary merges key by key: the parent's rule stays")
	assert_eq(il.cast.box.lt, {"$v": [-100, -100]}, "the child's own value wins inside a merged dictionary")
	assert_eq(il.cast.box.rb, {"$v": [250, 100]}, "and the parent's sibling key survives")
	assert_eq(il.pending.delay, 0.5)
	assert_true(il.pending.follow_player, "inherited sibling of an overridden key")
	assert_eq(il.pending.effect, "Skill.wz/222.img/skill/2221001/effect", "an inherited sibling is still rewritten")


func test_underscore_keys_are_not_inherited_but_the_childs_own_are_kept() -> void:
	var child := _child()
	child["_note"] = "child note"
	var il: Dictionary = _resolve({"big_bang": _parent(), "big_bang_il": child}).big_bang_il
	assert_false(il.has("_provenance"))
	assert_false(il.has("_rarity"))
	assert_eq(il._note, "child note")


func test_inherited_paths_are_rewritten_to_the_childs_book_and_id() -> void:
	var il: Dictionary = _resolve({"big_bang": _parent(), "big_bang_il": _child()}).big_bang_il
	assert_eq(il.icon, "Skill.wz/222.img/skill/2221001/icon")
	assert_eq(il.effect, "Skill.wz/222.img/skill/2221001/keydown")
	assert_eq(il.release_visuals, ["Skill.wz/222.img/skill/2221001/special/0"])
	assert_eq(il.pending.effect, "Skill.wz/222.img/skill/2221001/effect")
	assert_eq(il.sounds.use, "Sound.wz/Skill.img/2221001/Use")
	assert_eq(il.sounds.loop, "Sound.wz/Skill.img/2221001/Loop")


func test_rewrite_matches_only_at_a_path_boundary() -> void:
	var parent := _parent()
	parent["end"] = "Skill.wz/212.img/skill/2121001"
	var il: Dictionary = _resolve({"big_bang": parent, "big_bang_il": _child()}).big_bang_il
	assert_eq(il.end, "Skill.wz/222.img/skill/2221001", "a path may end at the id")
	assert_eq(il.desc, parent.desc, "an id inside prose, or a longer id that begins with it, is left alone")


func test_child_strings_are_never_rewritten() -> void:
	var child := _child()
	child["icon"] = "Skill.wz/212.img/skill/2121001/icon"
	child["sounds"] = {"use": "Sound.wz/Skill.img/2121001/Use"}
	var il: Dictionary = _resolve({"big_bang": _parent(), "big_bang_il": child}).big_bang_il
	assert_eq(il.icon, "Skill.wz/212.img/skill/2121001/icon", "the child names the parent's art on purpose")
	assert_eq(il.sounds.use, "Sound.wz/Skill.img/2121001/Use")
	assert_eq(il.sounds.loop, "Sound.wz/Skill.img/2221001/Loop", "the inherited sibling is rewritten")


func test_the_parent_and_the_inputs_are_not_modified() -> void:
	var skills := {"big_bang": _parent(), "big_bang_il": _child()}
	var out := _resolve(skills)
	assert_eq(skills, {"big_bang": _parent(), "big_bang_il": _child()}, "resolve never edits its input")
	assert_eq(out.big_bang, _parent(), "the parent resolves to its raw data, _ keys included")
	out.big_bang_il.cast.box.lt = {"$v": [0, 0]}
	assert_eq(out.big_bang.cast, _parent().cast, "the child is a deep copy")


func test_data_without_extends_resolves_to_itself() -> void:
	var skills := {"big_bang": _parent(), "other": {"skill_id": 1, "book": "000"}}
	var out := _resolve(skills)
	assert_eq(out, skills)
	assert_true(is_same(out, skills), "no template means the same dictionary, so nothing else changes")


func test_resolution_does_not_depend_on_key_order() -> void:
	var a := _resolve({"big_bang": _parent(), "big_bang_il": _child()})
	var b := _resolve({"big_bang_il": _child(), "big_bang": _parent()})
	assert_eq(a.big_bang_il, b.big_bang_il)
	assert_eq(a.big_bang, b.big_bang)
	assert_eq(a.keys().size(), 2)
	assert_eq(b.keys(), ["big_bang_il", "big_bang"], "the order of the keys is kept, not sorted")


func test_a_child_missing_skill_id_book_or_job_is_reported_and_dropped() -> void:
	for missing: String in ["skill_id", "book", "job"]:
		var child := _child()
		child.erase(missing)
		var errors := PackedStringArray()
		var out := _resolve({"big_bang": _parent(), "big_bang_il": child}, errors)
		assert_eq(errors.size(), 1, "%s: %s" % [missing, errors])
		assert_true("big_bang_il" in errors[0] and missing in errors[0], errors[0])
		assert_false(out.has("big_bang_il"), "the child is refused")
		assert_true(out.has("big_bang"))


func test_a_missing_parent_is_reported_and_the_child_dropped() -> void:
	var errors := PackedStringArray()
	var out := _resolve({"big_bang_il": _child()}, errors)
	assert_eq(errors.size(), 1, "%s" % [errors])
	assert_true("big_bang_il" in errors[0] and "big_bang" in errors[0], errors[0])
	assert_true(out.is_empty())


func test_a_chained_parent_and_a_self_parent_are_errors() -> void:
	var errors := PackedStringArray()
	var mid := {"extends": "big_bang", "skill_id": 2221001, "book": "222", "job": 222}
	var leaf := {"extends": "big_bang_il", "skill_id": 2321001, "book": "232", "job": 232}
	var out := _resolve({"big_bang": _parent(), "big_bang_il": mid, "big_bang_bishop": leaf}, errors)
	assert_eq(errors.size(), 1, "only the grandchild is refused: %s" % [errors])
	assert_true("big_bang_bishop" in errors[0] and "big_bang_il" in errors[0], errors[0])
	assert_true(out.has("big_bang_il"), "the first level resolves")
	assert_false(out.has("big_bang_bishop"))
	errors = PackedStringArray()
	out = _resolve({"loop": {"extends": "loop", "skill_id": 1, "book": "000", "job": 0}}, errors)
	assert_eq(errors.size(), 1, "%s" % [errors])
	assert_true(out.is_empty(), "a self-parent is a chain of one, and a cycle of two refuses both")
	errors = PackedStringArray()
	out = _resolve({"a": {"extends": "b", "skill_id": 1, "book": "000", "job": 0},
		"b": {"extends": "a", "skill_id": 2, "book": "000", "job": 0}}, errors)
	assert_eq(errors.size(), 2, "%s" % [errors])
	assert_true(out.is_empty())


func test_an_extends_that_is_not_a_key_name_is_an_error() -> void:
	var errors := PackedStringArray()
	var child := _child()
	child["extends"] = 5
	var out := _resolve({"big_bang": _parent(), "big_bang_il": child}, errors)
	assert_eq(errors.size(), 1, "%s" % [errors])
	assert_false(out.has("big_bang_il"))


func test_big_bang_resolves_to_its_raw_data_in_the_shipped_files() -> void:
	var data := DataRepo.load_all()
	var raw: Dictionary = data.skills.skills
	assert_false(raw.big_bang.has("extends"), "F/P's definition is not a template")
	var book := SkillBook.from_data(data.skills, {})
	assert_eq(book.def("big_bang"), raw.big_bang, "F/P resolves byte-identical")
	assert_eq(book.defs.keys(), raw.keys(), "no shipped skill extends yet, so the book holds the raw definitions")


func test_skill_book_returns_only_resolved_definitions() -> void:
	var root := {"skills": {"big_bang": _parent(), "big_bang_il": _child(), "bad": {"extends": "nope"}}}
	var book := SkillBook.from_data(root, {})
	assert_eq(book.def("big_bang_il").icon, "Skill.wz/222.img/skill/2221001/icon")
	assert_eq(book.skill_id("big_bang_il"), 2221001)
	assert_eq(book.key_for_id(2221001), "big_bang_il")
	assert_eq(book.key_for_id(2121001), "big_bang")
	assert_eq(book.wz_path("big_bang_il"), "Skill.wz/222.img/skill/2221001")
	assert_false(book.has("bad"), "a refused template is not a definition")
	assert_eq(root.skills.big_bang_il, _child(), "the raw root is untouched")


func test_load_all_lists_template_errors_and_keeps_the_raw_data() -> void:
	var root := test_dir(WORK)
	_put("survivor/skills.json", {"_doc": "base", "skills": {}})
	_put("survivor/skills/magician.json", {"skills": {"big_bang": _parent()}})
	_put("survivor/skills/il_arch_mage.json", {"skills": {"big_bang_il": {"extends": "big_bang", "skill_id": 2221001, "job": 222}}})
	var errors := PackedStringArray()
	var d := DataRepo.load_all(root, errors)
	var template_errors := Array(errors).filter(func(e: String) -> bool: return "big_bang_il" in e)
	assert_eq(template_errors.size(), 1, "%s" % [errors])
	assert_true("book" in template_errors[0], template_errors[0])
	assert_eq(d.skills.skills.big_bang_il, {"extends": "big_bang", "skill_id": 2221001.0, "job": 222.0},
		"load_all hands out the raw data: only SkillBook resolves")


func test_the_same_template_resolves_the_same_whichever_line_file_holds_the_parent() -> void:
	var root := test_dir(WORK)
	_put("survivor/skills.json", {"skills": {}})
	_put("survivor/skills/magician.json", {"skills": {"big_bang": _parent()}})
	_put("survivor/skills/il_arch_mage.json", {"skills": {"big_bang_il": _child()}})
	var errors := PackedStringArray()
	var d1 := DataRepo.load_all(root, errors)
	assert_eq(Array(errors).filter(func(e: String) -> bool: return "big_bang" in e), [], "child after parent: %s" % [errors])
	var first := SkillBook.from_data(d1.skills, {}).def("big_bang_il")
	_put("survivor/skills/beginner.json", {"skills": {"big_bang_il": _child()}})
	_put("survivor/skills/il_arch_mage.json", {"skills": {}})
	var d2 := DataRepo.load_all(root, PackedStringArray())
	assert_eq(d2.skills.skills.keys(), ["big_bang_il", "big_bang"], "now the child's file merges before the parent's")
	assert_eq(SkillBook.from_data(d2.skills, {}).def("big_bang_il"), first, "child before parent: same result")


func test_a_child_key_defined_by_two_files_is_the_existing_duplicate_error() -> void:
	var root := test_dir(WORK)
	_put("survivor/skills.json", {"skills": {}})
	_put("survivor/skills/magician.json", {"skills": {"big_bang": _parent()}})
	_put("survivor/skills/beginner.json", {"skills": {"big_bang_il": _child()}})
	_put("survivor/skills/il_arch_mage.json", {"skills": {"big_bang_il": _child()}})
	var errors := PackedStringArray()
	DataRepo.load_all(root, errors)
	var dup := Array(errors).filter(func(e: String) -> bool: return "duplicate" in e and "big_bang_il" in e)
	assert_eq(dup.size(), 1, "%s" % [errors])


func _put(rel: String, value: Dictionary) -> void:
	var path := test_dir(WORK).path_join(rel)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "", false))
	file.close()


# ---- drift guard -------------------------------------------------------------------------------------------------

## A Skill.wz-shaped img for one book with skill `id`: eight-plus levels of numbers and the art nodes of a Big Bang.
func _img(id: int, mad_top: float = 450.0, with_prepare: bool = true) -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"mad": 160.0 + (mad_top - 160.0) * (lv - 1) / 29.0, "mastery": 50.0, "mobCount": 6.0,
			"time": 2.0, "lt": {"$v": [-250.0, -180.0]}, "rb": {"$v": [250.0, 100.0]}}
	var node := {"icon": {"$canvas": 1}, "keydown": {"0": {"$canvas": 1}, "1": {"$canvas": 2}},
		"effect": {"0": {"$canvas": 3}}, "special": {"0": {"$canvas": 4}}, "level": levels}
	if with_prepare:
		node["prepare"] = {"0": {"$canvas": 5}}
	return {"skill": {"%07d" % id: node}}


func _template_book(child_img: Dictionary) -> SkillBook:
	var root := {"skills": {"big_bang": _parent(), "big_bang_il": _child()}}
	return SkillBook.from_data(root, {"212": _img(2121001), "222": child_img})


## Every path the synthetic imgs hold, as the resolve callable the guard uses.
func _exists_in(imgs: Dictionary) -> Callable:
	return func(path: String) -> bool:
		var parts := path.split("/")
		if parts.size() < 2 or not parts[0].ends_with(".wz"):
			return false
		var book := String(parts[1]).trim_suffix(".img")
		if parts[0] == "Sound.wz":
			return true
		var n: Variant = imgs.get(book)
		for i in range(2, parts.size()):
			if not (n is Dictionary) or not n.has(parts[i]):
				return false
			n = n[parts[i]]
		return true


func test_drift_guard_passes_when_the_books_agree() -> void:
	var book := _template_book(_img(2221001))
	var imgs := {"212": _img(2121001), "222": _img(2221001)}
	assert_eq(SkillTemplate.pairs(book), [["big_bang_il", "big_bang"]])
	assert_eq(SkillTemplate.drift_problems(book, "big_bang_il", "big_bang", _exists_in(imgs)), PackedStringArray())


func test_drift_guard_names_a_number_that_differs_at_a_mapped_level() -> void:
	var book := _template_book(_img(2221001, 449.0))
	var problems := SkillTemplate.drift_problems(book, "big_bang_il", "big_bang",
		_exists_in({"212": _img(2121001), "222": _img(2221001, 449.0)}))
	assert_false(problems.is_empty(), "a book that differs must fail the guard")
	assert_true("mad" in problems[0] and "level" in problems[0], problems[0])


func test_drift_guard_names_an_art_node_count_that_differs() -> void:
	var book := _template_book(_img(2221001, 450.0, false))
	var problems := SkillTemplate.drift_problems(book, "big_bang_il", "big_bang",
		_exists_in({"212": _img(2121001), "222": _img(2221001, 450.0, false)}))
	assert_eq(problems.size(), 1, "%s" % [problems])
	assert_true("art" in problems[0], problems[0])


func test_drift_guard_names_a_rewritten_path_that_does_not_resolve() -> void:
	var book := _template_book(_img(2221001))
	var broken := _img(2221001)
	broken.skill["2221001"].erase("keydown")
	broken.skill["2221001"]["keydown_old"] = {"0": {"$canvas": 1}, "1": {"$canvas": 2}}
	var problems := SkillTemplate.drift_problems(book, "big_bang_il", "big_bang", _exists_in({"212": _img(2121001), "222": broken}))
	assert_true(Array(problems).any(func(p: String) -> bool: return "2221001/keydown" in p), "%s" % [problems])


func test_drift_guard_reports_a_child_without_a_canonical_node() -> void:
	var book := SkillBook.from_data({"skills": {"big_bang": _parent(), "big_bang_il": _child()}}, {"212": _img(2121001)})
	var problems := SkillTemplate.drift_problems(book, "big_bang_il", "big_bang", _exists_in({"212": _img(2121001)}))
	assert_false(problems.is_empty(), "an img that is missing is a failure, not a pass")


func test_shipped_templates_agree_with_their_parents_in_the_real_cache() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var data := DataRepo.load_all()
	var imgs := {}
	for b: String in DataRepo.skill_books(data):
		var w := lib.img(DataRepo.skill_img_path(b))
		if w != null:
			imgs[b] = w.root
	var book := SkillBook.from_data(data.skills, imgs)
	var exists := func(path: String) -> bool: return lib.find(path) != null or lib.sound(path) != null
	var pairs := SkillTemplate.pairs(book)
	# No shipped pair exists until I10; once one does, every one of them is held to the guard.
	for pair: Array in pairs:
		var problems := SkillTemplate.drift_problems(book, pair[0], pair[1], exists)
		assert_eq(problems, PackedStringArray(), "%s extends %s: %s" % [pair[0], pair[1], problems])
	# The guard on the real cache with a synthetic pair so it is not vacuous: F/P's Big Bang extended by an identical
	# twin that names the same book and id, which must agree in every number, node and path.
	var twin := {"skills": {"big_bang": data.skills.skills.big_bang, "big_bang_twin": {"extends": "big_bang",
		"skill_id": 2121001, "book": "212", "job": 212}}}
	var twin_book := SkillBook.from_data(twin, imgs)
	assert_eq(SkillTemplate.pairs(twin_book), [["big_bang_twin", "big_bang"]])
	assert_eq(twin_book.def("big_bang_twin").icon, twin_book.def("big_bang").icon)
	assert_eq(SkillTemplate.drift_problems(twin_book, "big_bang_twin", "big_bang", exists), PackedStringArray())
	# ...and a twin in the real cache that does differ (F/P's Big Bang read as Meteor Shower's book entry) is caught.
	var wrong := {"skills": {"big_bang": data.skills.skills.big_bang, "big_bang_twin": {"extends": "big_bang",
		"skill_id": 2121005, "book": "212", "job": 212}}}
	var wrong_book := SkillBook.from_data(wrong, imgs)
	assert_false(SkillTemplate.drift_problems(wrong_book, "big_bang_twin", "big_bang", exists).is_empty())
