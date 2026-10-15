class_name StageRoster
extends RefCounted
## Which mob kinds a stage needs (docs/ARCHITECTURE.md 4.4.1): the ids its keyframe pools and boss schedule name,
## plus the mobs its scheduled bosses bring in through their canonical data: every MobSkill 200 (summon) level a
## boss lists in `info/skill` (the integer keys of `MobSkill.img/200/level/<level>`) and its `info/revive` list.
## Summon and revive lists are v83 facts, so stages.json never repeats them. Pure: plain Dictionaries in, ids out.
## Used by RunWorld (mob kinds) and DataRepo (which mob imgs to load).

const SUMMON_SKILL := 200


## Pool ids of every keyframe plus every scheduled boss id, ascending.
static func named_ids(stage: Dictionary) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for kf: Dictionary in stage.get("keyframes", []):
		for key: Variant in kf.get("pool", {}):
			_add(ids, int(key))
	for boss: Dictionary in stage.get("bosses", []):
		_add(ids, int(boss.get("mob_id", 0)))
	ids.sort()
	return ids


## Mob ids one boss img brings in: its summon lists (MobSkill 200 at each level it lists) and its revive list,
## ascending without duplicates. `mob_skill_img` is the Skill.wz/MobSkill.img root.
static func boss_extra_ids(boss_img: Dictionary, mob_skill_img: Dictionary) -> PackedInt32Array:
	var ids := PackedInt32Array()
	var info: Variant = boss_img.get("info", {})
	if not (info is Dictionary):
		return ids
	var skills: Variant = info.get("skill", {})
	if skills is Dictionary:
		var levels: Dictionary = mob_skill_img.get(str(SUMMON_SKILL), {}).get("level", {})
		for entry: Variant in skills.values():
			if not (entry is Dictionary) or int(entry.get("skill", 0)) != SUMMON_SKILL:
				continue
			var spec: Variant = levels.get(str(int(entry.get("level", 0))), {})
			if spec is Dictionary:
				_add_list(ids, spec)
	var revive: Variant = info.get("revive", {})
	if revive is Dictionary:
		_add_list(ids, revive)
	ids.sort()
	return ids


## Every mob id the stage needs: named_ids plus each scheduled boss's boss_extra_ids, read from `mob_imgs`
## ({id: img root}; int or String keys); a boss without an img adds nothing. Ascending.
static func mob_ids(stage: Dictionary, mob_imgs: Dictionary, mob_skill_img: Dictionary) -> PackedInt32Array:
	var ids := named_ids(stage)
	for boss: Dictionary in stage.get("bosses", []):
		var id := int(boss.get("mob_id", 0))
		var img: Variant = mob_imgs.get(id, mob_imgs.get(str(id), {}))
		if img is Dictionary:
			for extra in boss_extra_ids(img, mob_skill_img):
				_add(ids, extra)
	ids.sort()
	return ids


## The ids of a WZ list node ({"0": id, "1": id, ...}: a MobSkill 200 level or an info/revive list) in key order,
## duplicates and zeros kept; other keys (interval, hp, limit, ...) are skipped.
static func list_ids(node: Dictionary) -> PackedInt32Array:
	var keys := PackedInt32Array()
	for key: Variant in node:
		if String(key).is_valid_int():
			keys.append(int(key))
	keys.sort()
	var ids := PackedInt32Array()
	for k in keys:
		ids.append(int(node[str(k)]))
	return ids


## Integer-keyed entries of a WZ list node ({"0": id, "1": id, ...}); other keys (interval, hp, ...) are skipped.
static func _add_list(ids: PackedInt32Array, node: Dictionary) -> void:
	for key: Variant in node:
		if String(key).is_valid_int():
			var id := int(node[key])
			if id > 0:
				_add(ids, id)


static func _add(ids: PackedInt32Array, id: int) -> void:
	if id > 0 and not (id in ids):
		ids.append(id)
