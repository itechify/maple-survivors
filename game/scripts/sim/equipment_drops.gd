class_name EquipmentDrops
extends RefCounted
## Which equipment a kill drops (spec #33, #109, #159), pure functions over the survivor list (equipment_drops.json
## "items"), the canonical item info ({id: Character.wz info}, as in setup.equipment_info) and one seeded RNG. Only items
## the character's current job can wear and whose reqLevel is near the character's level are eligible; items without
## info never drop. A weapon is eligible only when its family (WeaponInfo.family) is the family of the weapon held at the
## roll (`held_family`; "" = bare hands, so no weapon): one- and two-handed swords share "sword", and the families listed
## together in `rules.shared_families` (wand and staff: a Magician wields either) drop for each other's holder. Armour
## does not depend on the held weapon; shields are eligible for the jobs their reqJob admits, with Thief shields
## restricted to a held dagger (#207). `rules` is
## equipment_drops.json (below, above, falloff, boss_top, shared_families); the random stats of the chosen item come from
## Equipment.create_drop.


## Whether item `id` may drop for a character holding a weapon of `held_family`: any non-weapon, a weapon of that family
## or of a family it shares a drop group with (rules.shared_families, e.g. [["wand", "staff"]]). Bare hands ("") get no
## weapon.
static func family_allows(id: int, held_family: String, rules: Dictionary) -> bool:
	if Equipment.slot_of(id) != "weapon":
		return true
	var family := WeaponInfo.family(id)
	if family == "" or held_family == "":
		return false
	if family == held_family:
		return true
	for group: Variant in rules.get("shared_families", []):
		if family in group and held_family in group:
			return true
	return false


## Eligible item ids, in list order: job admitted (Equipment.job_allows), weapon family admitted (family_allows for
## `held_family`) and reqLevel in [level - rules.below, level + rules.above].
static func eligible(items: Array, infos: Dictionary, job_id: int, level: int, rules: Dictionary,
		held_family: String) -> Array:
	var lo := level - int(rules.get("below", 10))
	var hi := level + int(rules.get("above", 5))
	var out := []
	for raw: Variant in items:
		var id := int(raw)
		var info := Equipment.info_of(infos, id)
		if info.is_empty() or not _allows(id, info, job_id, held_family, rules):
			continue
		var req := int(info.get("reqLevel", 0))
		if req >= lo and req <= hi:
			out.append(id)
	return out


## One ordinary drop: an eligible item, nearer reqLevels likelier (weight 1 / (1 + falloff x distance), tier C). 0 when
## nothing is eligible.
static func pick(items: Array, infos: Dictionary, job_id: int, level: int, rules: Dictionary,
		rng: RandomNumberGenerator, held_family: String) -> int:
	var ids := eligible(items, infos, job_id, level, rules, held_family)
	if ids.is_empty():
		return 0
	var falloff := float(rules.get("falloff", 0.25))
	var weights := PackedFloat32Array()
	var total := 0.0
	for id: int in ids:
		var w := 1.0 / (1.0 + falloff * absf(float(int(Equipment.info_of(infos, id).get("reqLevel", 0)) - level)))
		weights.append(w)
		total += w
	var roll := rng.randf() * total
	for i in ids.size():
		roll -= weights[i]
		if roll < 0.0:
			return ids[i]
	return ids[ids.size() - 1]


## One boss drop: uniformly from the top of the window, reqLevel in [level + above - boss_top, level + above]; with
## nothing there the highest reqLevel in the window; with an empty window the job- and family-eligible item whose
## reqLevel is nearest the character's level (tier C). 0 only when the job can wear nothing admitted in the list.
static func pick_boss(items: Array, infos: Dictionary, job_id: int, level: int, rules: Dictionary,
		rng: RandomNumberGenerator, held_family: String) -> int:
	var ids := eligible(items, infos, job_id, level, rules, held_family)
	if ids.is_empty():
		var best := 0
		var best_d := 1 << 30
		for raw: Variant in items:
			var info := Equipment.info_of(infos, int(raw))
			if info.is_empty() or not _allows(int(raw), info, job_id, held_family, rules):
				continue
			var d := absi(int(info.get("reqLevel", 0)) - level)
			if d < best_d:
				best_d = d
				best = int(raw)
		return best
	var top := level + int(rules.get("above", 5)) - int(rules.get("boss_top", 5))
	var pool := ids.filter(func(id: int) -> bool: return int(Equipment.info_of(infos, id).get("reqLevel", 0)) >= top)
	if pool.is_empty():
		var highest := -1
		for id: int in ids:
			highest = maxi(highest, int(Equipment.info_of(infos, id).get("reqLevel", 0)))
		pool = ids.filter(func(id: int) -> bool: return int(Equipment.info_of(infos, id).get("reqLevel", 0)) == highest)
	return pool[rng.randi_range(0, pool.size() - 1)]


static func _allows(id: int, info: Dictionary, job_id: int, held_family: String, rules: Dictionary) -> bool:
	# tier C (#207): Thief shields belong to the one-handed dagger path; a claw occupies both hands.
	if Equipment.slot_of(id) == "shield" and floori(float(job_id) / 100.0) == 4 and held_family != "dagger":
		return false
	return Equipment.job_allows(info, job_id) and family_allows(id, held_family, rules)
