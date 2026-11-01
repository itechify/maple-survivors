class_name EquipmentDrops
extends RefCounted
## Which equipment a kill drops (spec #33, #109, #159, #292), pure functions over the survivor list (equipment_drops.json
## "items"), the canonical item info ({id: Character.wz info}, as in setup.equipment_info) and one seeded RNG. A drop does
## not follow the character's level (ADR 0006): the stage's `drop_band` fixes a reqLevel `band` [min, max] (stages.json
## stage entry, see band_of; per region since ADR 0007) and an ordinary drop is any eligible item whose reqLevel lies in it, equally likely. A boss drop
## comes from the top third of the band. Eligible means the job class wears it (Equipment.job_allows) and, for a weapon, that
## it belongs to one of the job's weapon `families` (JobTree.weapon_families, WeaponInfo.family: one- and two-handed swords
## share "sword"); armour and shields depend on the job class alone. Items without info never drop. `rules` is
## equipment_drops.json (boss_top_parts); random stats come from Equipment.create_drop.


## The reqLevel band [min, max] of a stage dictionary (a stages.json `stages` entry): its `drop_band`. A stage without
## one (a tool stage outside the progression, synthetic test data) has no limit, [0, 999].
static func band_of(stage: Dictionary) -> Array:
	var band: Variant = stage.get("drop_band")
	if not band is Array or band.size() != 2:
		return [0, 999]
	return [int(band[0]), int(band[1])]


## The lowest reqLevel of a boss drop: the top 1/`rules.boss_top_parts` (3: a third) of the band, rounded down. Henesys
## [0, 15] gives 10, Sleepywood [30, 40] gives 37.
static func boss_floor(band: Array, rules: Dictionary) -> int:
	return int(band[1]) - (int(band[1]) - int(band[0])) / maxi(1, int(rules.get("boss_top_parts", 3)))


## Whether weapon item `id` may drop for a job whose weapon families are `families`: any non-weapon, a weapon of one of them.
static func family_allows(id: int, families: Array) -> bool:
	if Equipment.slot_of(id) != "weapon":
		return true
	return WeaponInfo.family(id) in families


## Eligible item ids, in list order: job admitted (Equipment.job_allows), weapon family admitted (family_allows) and
## reqLevel in [band[0], band[1]].
static func eligible(items: Array, infos: Dictionary, job_id: int, band: Array,
		families: Array) -> Array:
	var out := []
	for raw: Variant in items:
		var id := int(raw)
		var info := Equipment.info_of(infos, id)
		if info.is_empty() or not _allows(id, info, job_id, families):
			continue
		var req := int(info.get("reqLevel", 0))
		if req >= int(band[0]) and req <= int(band[1]):
			out.append(id)
	return out


## One ordinary drop: an eligible item, uniformly (tier C: owner call, #292). 0 when nothing is eligible.
static func pick(items: Array, infos: Dictionary, job_id: int, band: Array, rules: Dictionary,
		rng: RandomNumberGenerator, families: Array) -> int:
	var ids := eligible(items, infos, job_id, band, families)
	if ids.is_empty():
		return 0
	return ids[rng.randi_range(0, ids.size() - 1)]


## One boss drop: uniformly from the eligible items in the top of the band (reqLevel >= boss_floor); with nothing there
## the highest reqLevel in the band; with an empty band the job- and family-eligible item whose reqLevel is nearest to the
## band (tier C). 0 only when the job can wear nothing admitted in the list.
static func pick_boss(items: Array, infos: Dictionary, job_id: int, band: Array, rules: Dictionary,
		rng: RandomNumberGenerator, families: Array) -> int:
	var ids := eligible(items, infos, job_id, band, families)
	if ids.is_empty():
		var best := 0
		var best_d := 1 << 30
		for raw: Variant in items:
			var info := Equipment.info_of(infos, int(raw))
			if info.is_empty() or not _allows(int(raw), info, job_id, families):
				continue
			var req := int(info.get("reqLevel", 0))
			var d := maxi(int(band[0]) - req, req - int(band[1]))
			if d < best_d:
				best_d = d
				best = int(raw)
		return best
	var top := boss_floor(band, rules)
	var pool := ids.filter(func(id: int) -> bool: return int(Equipment.info_of(infos, id).get("reqLevel", 0)) >= top)
	if pool.is_empty():
		var highest := -1
		for id: int in ids:
			highest = maxi(highest, int(Equipment.info_of(infos, id).get("reqLevel", 0)))
		pool = ids.filter(func(id: int) -> bool: return int(Equipment.info_of(infos, id).get("reqLevel", 0)) == highest)
	return pool[rng.randi_range(0, pool.size() - 1)]


static func _allows(id: int, info: Dictionary, job_id: int, families: Array) -> bool:
	return Equipment.job_allows(info, job_id) and family_allows(id, families)
