class_name Ammo
extends RefCounted
## Endless ammo of the ranged weapon stance (spec #151 #155; docs/GAME_DESIGN.md "Ranged basic attack and endless ammo").
## Pure lookups over survivor/ammo.json (`data.ammo`): which ammo item a ranged weapon family uses for an exact job and the
## round's level, the shot's numbers, and the upgrade notice. The ammo is never consumed and never an inventory item;
## RunWorld.ammo_id() derives it, so a saved character needs no ammo field. Item facts (incPAD, names) are canonical
## Item.wz / String.wz data the setup carries as `ammo_info` (DataRepo.ammo_info).


## The ammo item a `family` weapon uses for a character of exactly `job_id` at the round's `level`; 0 for a family without
## ammo (melee, bare hands). A schedule applies when its family matches and its `job` is `job_id` (no lineage walk: ADR
## 0006 has no branches, ruling D9); the highest step whose level is reached wins, else the family's starting ammo.
static func item_for(ammo: Dictionary, family: String, job_id: int, level: int) -> int:
	var start := int(ammo.get("families", {}).get(family, {}).get("start", 0))
	if start == 0:
		return 0
	var best := start
	var best_level := -1
	for schedule: Dictionary in ammo.get("schedules", []):
		if String(schedule.family) != family or int(schedule.get("job", 0)) != job_id:
			continue
		for step: Dictionary in schedule.steps:
			if int(step.level) <= level and int(step.level) > best_level:
				best = int(step.item)
				best_level = int(step.level)
	return best


## What is wrong with `ammo`'s schedules (format 2): one message per schedule that carries the removed `branch` key or
## names no `job`. Empty when the data is fine.
static func schedule_errors(ammo: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for i in ammo.get("schedules", []).size():
		var schedule: Dictionary = ammo.schedules[i]
		if schedule.has("branch"):
			errors.append("ammo schedule %d carries `branch` (format 1): key it by the exact `job`" % i)
		if int(schedule.get("job", 0)) <= 0:
			errors.append("ammo schedule %d has no `job`" % i)
	return errors


## The shot of `family`'s weapon shot: {speed, radius, rotate, overshoot}; empty for a family without ammo.
static func projectile(ammo: Dictionary, family: String) -> Dictionary:
	return ammo.get("families", {}).get(family, {}).get("projectile", {})


## What the upgrade notice calls the family's ammo ("throwing stars", "arrows", "bullets").
static func noun(ammo: Dictionary, family: String) -> String:
	return String(ammo.get("families", {}).get(family, {}).get("noun", "ammo"))


## The one-line upgrade notice, in the style of the other system notices (`item_name` is the v83 String.wz name).
static func notice(p_noun: String, item_name: String) -> String:
	return "Your %s are now %s" % [p_noun, item_name]


## Every ammo item id the data names (starting and scheduled), ascending: the Item.wz entries a setup loads.
static func item_ids(ammo: Dictionary) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for family: Dictionary in ammo.get("families", {}).values():
		_add(ids, int(family.get("start", 0)))
	for schedule: Dictionary in ammo.get("schedules", []):
		for step: Dictionary in schedule.steps:
			_add(ids, int(step.item))
	ids.sort()
	return ids


## Cache path of the Item.wz img an ammo item lives in: "Item.wz/Consume/0207.img" (arrows 0206, stars 0207, bullets 0233).
@warning_ignore("integer_division")
static func img_path(item_id: int) -> String:
	return "Item.wz/Consume/%04d.img" % (item_id / 10000)


## Cache path of an ammo item's flight animation: "Item.wz/Consume/0207.img/02070001/bullet".
static func bullet_path(item_id: int) -> String:
	return "%s/%08d/bullet" % [img_path(item_id), item_id]


static func _add(ids: PackedInt32Array, id: int) -> void:
	if id > 0 and not (id in ids):
		ids.append(id)
