extends RefCounted
## Checks every region test shares (spec #449 C14, ticket #476): the progression neighbours of a region and the EXP its
## ordinary monsters pay against the level curve. Region tests call these so a rule added here covers all of them.

## tier C (#500 review, #476): an ordinary pool mob's EXP stays within this band of level_curve.json exp at its own level.
## It catches `hideName` instance and PQ copies whose canonical EXP sits far below the curve (Leafre's cave Skelegons paid 0.30).
const EXP_RATIO_MIN := 0.7
const EXP_RATIO_MAX := 1.3
## The first progression step the pool-EXP rule covers: the regions whose pools come from the Lv40-160 rosters of Ossyria
## and beyond (the original five were hand-tuned to their own curves).
const EXP_CHECK_FROM_STEP := 6


## [previous key, next key] of `key` in `progression` ("" at either end); [] when `key` is not listed.
static func neighbours(progression: Array, key: String) -> Array:
	var i := progression.find(key)
	if i < 0:
		return []
	return [String(progression[i - 1]) if i > 0 else "", String(progression[i + 1]) if i + 1 < progression.size() else ""]


## The ordinary monsters of `stage_key` (the pool mobs of its three maps and the monsters its bosses summon; the bosses and
## final forms left out), ascending, from the cache's map life lists. Empty when a map img is not imported (callers SKIP).
static func ordinary_mob_ids(data: Dictionary, lib: AssetLibrary, stage_key: String) -> PackedInt32Array:
	var stage: Dictionary = data.stages.stages.get(stage_key, {})
	var map_imgs: Array = []
	for map: Dictionary in stage.get("maps", []):
		var img := lib.img(DataRepo.map_img_path(int(map.map_id)))
		if img == null:
			return PackedInt32Array()
		map_imgs.append(img.root)
	var bosses := {}
	var mob_imgs := {}
	for boss: Dictionary in DataRepo.stage_bosses(stage):
		for id: int in [int(boss.mob_id), int(boss.get("final_form", 0))]:
			var img := lib.img("Mob.wz/%07d.img" % id) if id > 0 else null
			if img != null:
				bosses[id] = true
				mob_imgs[id] = img.root
	var skill_img := lib.img(DataRepo.MOB_SKILL_IMG)
	var skills: Dictionary = skill_img.root if skill_img != null else {}
	var out := PackedInt32Array()
	for id: int in DataRepo.stage_mob_ids(data, stage_key, mob_imgs, skills, map_imgs):
		if not bosses.has(id):
			out.append(id)
	return out


## One message per ordinary mob of `stage_key` whose canonical EXP is outside EXP_RATIO_MIN..MAX of the level curve's EXP at the
## mob's own `info.level`, or whose img is missing. A mob whose canonical EXP is 0 (a summoned decoy) is exempt.
static func exp_ratio_errors(data: Dictionary, lib: AssetLibrary, stage_key: String) -> PackedStringArray:
	var errors := PackedStringArray()
	var curve: Array = DataRepo.load_json("res://data/survivor/level_curve.json").exp
	for id: int in ordinary_mob_ids(data, lib, stage_key):
		var img := lib.img("Mob.wz/%07d.img" % id)
		if img == null:
			errors.append("%s: mob %d is not imported" % [stage_key, id])
			continue
		var info: Dictionary = img.root.info
		if int(info.get("exp", 0)) == 0:
			continue # a summoned decoy that pays nothing by design (the Clocktower's Low and High Darkstar)
		var level := clampi(int(info.level), 1, curve.size())
		var ratio := float(info.exp) / float(curve[level - 1])
		if ratio < EXP_RATIO_MIN or ratio > EXP_RATIO_MAX:
			errors.append("%s: mob %d (Lv%d) pays %.2fx the level curve's EXP, outside %.1f-%.1f" % [
				stage_key, id, level, ratio, EXP_RATIO_MIN, EXP_RATIO_MAX])
	return errors

