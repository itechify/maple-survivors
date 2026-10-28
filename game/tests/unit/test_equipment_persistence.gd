extends TestCase
## Mesos and equipment stay with the character (spec #282, #292, ADR 0006): worn gear, the Equip tab, scrolls and mesos
## survive a death and a clear through the format-3 snapshot and the save file, and a Lv1 round wears gear whose
## reqLevel and stat requirements it could never meet. Seam: RunWorld.character_snapshot() out, SaveData between rounds,
## RunWorld.new({character}) back in.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const HAT_LV100 := 1002579 # a Magician hat, reqLevel 100 in this synthetic table
const WAND_LV70 := 1382039
const SWORD_WARRIOR := 1302008
const INFO := {
	HAT_LV100: {"reqLevel": 100, "reqJob": 2, "reqINT": 200, "incMDD": 30, "tuc": 5},
	WAND_LV70: {"reqLevel": 70, "reqJob": 2, "reqINT": 180, "incMAD": 70, "attackSpeed": 6, "tuc": 7},
	1372005: {"reqLevel": 8, "reqJob": 0, "incPAD": 15, "incMAD": 23, "attackSpeed": 6, "tuc": 7},
	1002001: {"reqLevel": 0, "reqJob": 0, "incPDD": 4, "tuc": 7},
	SWORD_WARRIOR: {"reqLevel": 30, "reqJob": 1, "incPAD": 47, "attackSpeed": 5, "tuc": 7},
}

var save_path := test_dir("equipment_persistence/save.json")


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_path.get_base_dir()))


func after_each() -> void:
	TestCase.remove_tree(save_path.get_base_dir())


func _setup(character: Dictionary) -> Dictionary:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	data.equipment_drops.chance = 0.0
	RF.set_bosses(data.stages.stages.quiet, [
		{"time": 0.1, "mob_id": 2220000, "hp_mult": 1.0, "rewards": {"exp_mult": 1, "bonus_choices": 0}}])
	var setup := RF.setup("quiet", 20, data)
	for id: int in INFO:
		var merged: Dictionary = setup.equipment_info.get(id, {}).duplicate()
		merged.merge(INFO[id], true)
		setup.equipment_info[id] = merged
	setup.character = character
	return setup


## A format-3 Magician who owns a Lv100 hat (worn), a Lv70 staff and a Warrior's sword (spare), 12,345 mesos, two scrolls.
func _character() -> Dictionary:
	var equipment := Equipment.empty_state()
	equipment.worn = Equipment.worn_from_ids([HAT_LV100, 1372005], INFO)
	equipment.inventory = [Equipment.create(WAND_LV70, INFO[WAND_LV70]), Equipment.create(SWORD_WARRIOR, INFO[SWORD_WARRIOR])]
	equipment.worn.hat.stats.incMDD = 33 # a scrolled / rolled instance, not the canonical one
	equipment.worn.hat.scrolls = 1
	return {"format": 3, "job_id": 212, "look": {"skin": 0, "face": 20000, "hair": 30030}, "equipment": equipment,
		"scrolls": {"2043700": 2}, "mesos": 12345, "tiers_unlocked": 1}


func _round(character: Dictionary) -> RunWorld:
	var w := RunWorld.new(_setup(character))
	RF.place_player(w, 400)
	for i in 20:
		w.step(DT, MoveInput.new())
	return w


func _json(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))


func _die(w: RunWorld) -> void:
	w.god = false
	w.upkeep.invincible_t = 0.0
	w.take_hit(1000000.0, false, "", w.player.pos + Vector2(20, 0), {"accuracy": 100000.0})
	assert_eq(w.state, RunWorld.DEAD)


func _clear(w: RunWorld) -> void:
	w.hit_mob(int(w.bosses.records[0].slot), {"damage_min": 1000000.0, "damage_max": 1000000.0,
		"magic": false, "crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
	for i in 3:
		w.step(DT, MoveInput.new())
	RF.auto_choose(w)
	assert_eq(w.state, RunWorld.CLEARED)


## Saves `snapshot` with the real save file as a finished round ("died" / "cleared") and reads the slot back from disk.
func _through_the_save_file(snapshot: Dictionary, ending: String) -> Dictionary:
	var save := SaveData.new(save_path)
	var index := save.create_slot({"name": "Maple292", "created": "2026-10-28T12:00:00Z", "rounds_played": 0,
		"character": _character()})
	assert_eq(index, 0)
	var slot: Dictionary = save.slot(index)
	slot.character = _json(snapshot)
	slot.rounds_played = 1
	assert_eq(save.finish_round(index, slot, ending, "2026-10-28", {"stage": "henesys", "level": 5}), OK)
	return SaveData.new(save_path).slot(index).character


func test_a_level_one_round_wears_gear_it_could_never_meet_the_requirements_of() -> void:
	var w := _round(_character())
	assert_eq(w.progression.level, 1)
	assert_eq(w.equipment.worn.hat.id, HAT_LV100, "the reqLevel 100 / reqINT 200 hat stays on")
	assert_eq(w.equip_item(0), "", "the reqLevel 70 / reqINT 180 staff can be worn at Lv1")
	assert_eq(w.equipment.worn.weapon.id, WAND_LV70)
	assert_eq(w.equip_item(w.equipment.inventory.size() - 1), "reqJob", "a Warrior's sword stays off a Magician")


func test_a_death_keeps_equipment_mesos_and_scrolls_through_the_save_file() -> void:
	var w := _round(_character())
	w.spawn_meso(w.player.pos, 55)
	w.spawn_equipment(w.player.pos, {"id": 1002001, "stats": {"incPDD": 4}, "slots": 7, "scrolls": 0})
	for i in 60:
		w.step(DT, MoveInput.new())
	_die(w)
	var snapshot := w.character_snapshot()
	assert_eq(snapshot.mesos, 12400)
	assert_eq(CharacterSnapshot.validation_error(snapshot), "")
	var loaded := _through_the_save_file(snapshot, "died")
	assert_eq(loaded.mesos, 12400, "mesos survive the death and the save file")
	assert_eq(int(loaded.scrolls["2043700"]), 2)
	assert_eq(Equipment.worn_ids(loaded.equipment.worn), Equipment.worn_ids(snapshot.equipment.worn))
	assert_eq(loaded.equipment.worn.hat.stats.incMDD, 33, "the rolled stats and scroll count of the instance")
	assert_eq(loaded.equipment.worn.hat.scrolls, 1)
	assert_eq(Equipment.normalized(loaded.equipment), snapshot.equipment, "worn and spare, instance by instance")
	assert_true(1002001 in Equipment.held_ids(loaded.equipment), "what the round picked up is kept")
	var next := _round(loaded)
	assert_eq(next.progression.level, 1, "the next round starts again at Lv1")
	assert_eq(next.mesos, 12400)
	assert_eq(next.scrolls, {"2043700": 2})
	assert_eq(next.equipment, snapshot.equipment, "the same gear, worn and spare")
	assert_eq(next.equipment.worn.hat.id, HAT_LV100)


func test_a_clear_keeps_equipment_mesos_and_scrolls_through_the_save_file() -> void:
	var w := _round(_character())
	w.spawn_meso(w.player.pos, 700)
	for i in 60:
		w.step(DT, MoveInput.new())
	_clear(w)
	var snapshot := w.character_snapshot()
	assert_true(snapshot.mesos >= 13045, "the pickup and the boss's meso bundles on top of 12,345")
	var spares: Array = snapshot.equipment.inventory.map(func(i: Dictionary) -> int: return int(i.id))
	assert_eq(spares.slice(0, 2), [WAND_LV70, SWORD_WARRIOR], "the spare gear is still there, the boss drops follow")
	var loaded := _through_the_save_file(snapshot, "cleared")
	assert_eq(loaded.mesos, snapshot.mesos)
	assert_eq(int(loaded.scrolls["2043700"]), 2)
	assert_eq(Equipment.normalized(loaded.equipment), snapshot.equipment)
	var next := _round(loaded)
	assert_eq(next.mesos, snapshot.mesos)
	assert_eq(next.equipment.worn.hat.id, HAT_LV100)
	assert_eq(next.equipment, snapshot.equipment)


func test_a_quit_round_keeps_them_like_a_death() -> void:
	var w := _round(_character())
	var snapshot := w.character_snapshot()
	var loaded := _through_the_save_file(snapshot, "quit")
	assert_eq(Equipment.normalized(loaded.equipment), snapshot.equipment)
	assert_eq(loaded.mesos, 12345)
