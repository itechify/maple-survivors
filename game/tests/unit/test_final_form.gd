extends TestCase
## A boss's final form (stages.json `final_form`, #456) on synthetic data: the shell's death continues the same
## encounter, the form's death ends it.
const TF := preload("res://tests/fixtures/tree_boss_fixtures.gd")
const BR := preload("res://tools/balance_run.gd")
const DT := 1.0 / 60.0
const KILL := {"damage_min": 1000000, "damage_max": 1000000, "magic": true, "crit": 0.0, "crit_mult": 1.5,
	"skill": "energy_bolt"}


## King Clang's shape: shell 5220001 (4000 HP, revives into) form 5220000 (25000 HP, casts a summon), entry hp_mult 1.5.
func _setup(entry: Dictionary = {}) -> Dictionary:
	var setup: Dictionary = TF.setup(5220001, [], ["attack1"])
	var boss: Dictionary = setup.data.stages.stages.quiet.maps[0].boss
	boss.final_form = 5220000
	boss.merge(entry, true)
	setup.mob_imgs[5220001].info.maxHP = 4000
	setup.mob_imgs[5220001].info.revive = {"0": 5220000}
	setup.mob_imgs[5220000] = setup.mob_imgs[5220001].duplicate(true)
	setup.mob_imgs[5220000].info.erase("revive")
	setup.mob_imgs[5220000].info.maxHP = 25000
	setup.mob_imgs[5220000].info.exp = 1234
	setup.data.balance.mob_skills.enabled_ids = [5220001, 5220000]
	setup.mob_imgs[5220000].info.skill = {"0": {"skill": 200, "level": 82, "action": 1, "effectAfter": 0}}
	setup.mob_skill_img["200"].level["82"] = {"hp": 100, "interval": 1, "limit": 2, "0": 210100}
	return setup


func _world(entry: Dictionary = {}) -> RunWorld:
	var w := RunWorld.new(_setup(entry))
	w.god = true
	for i in 60:
		w.step(DT, MoveInput.new())
	w.drain_events()
	return w


func _types(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


## The shell's death spawns the form where it died, in the same encounter, and pays nothing.
func test_shell_death_spawns_the_form_in_place_without_reward() -> void:
	var w := _world()
	var shell := int(w.bosses.records[0].slot)
	var at := w.swarm.pos(shell)
	var spawned := float(w.bosses.records[0].spawn_time)
	w.hit_mob(shell, KILL, -1)
	var events := w.drain_events()
	assert_false(w.bosses.all_dead(), "the shell's death does not end the encounter")
	assert_true(_types(events, "boss_died").is_empty(), "the shell is not marked dead")
	assert_true(_types(events, "pickup_spawned").is_empty(), "no EXP, meso or equipment from the shell")
	assert_eq(_types(events, "mob_died").size(), 1)
	assert_eq(int(_types(events, "mob_died")[0].exp), 0, "the shell pays no EXP")
	assert_eq(w.pending_bonus_choices, 0, "and opens no bonus choice")
	var revives := _types(events, "mob_revives_spawned")
	assert_eq(revives.size(), 1)
	var form := int(w.bosses.records[0].slot)
	assert_ne(form, shell)
	assert_eq(int(w.bosses.records[0].mob_id), 5220000)
	assert_eq(int(revives[0].revives[0].mob_id), 5220000)
	assert_eq(w.mob_boss[form], 0, "the form carries the encounter's boss_index")
	assert_eq(w.swarm.steady[form], 1, "and the steady flag")
	assert_eq(w.swarm.pos(form), at, "at the shell's death position")
	assert_near(float(w.bosses.records[0].spawn_time), spawned, 1e-9, "one encounter clock")
	assert_false(bool(w.bosses.records[0].dead))
	assert_eq(w.bosses.live_count(), 1)


## Only the form's death ends the encounter and pays the boss rewards, once.
func test_encounter_is_won_only_on_the_form() -> void:
	var w := _world()
	w.hit_mob(int(w.bosses.records[0].slot), KILL, -1)
	w.drain_events()
	for i in 60:
		w.step(DT, MoveInput.new())
	w.drain_events()
	w.hit_mob(int(w.bosses.records[0].slot), KILL, -1)
	assert_true(w.bosses.all_dead(), "the form's death ends the encounter")
	var events := w.drain_events()
	assert_eq(_types(events, "boss_died").size(), 1)
	assert_eq(int(_types(events, "boss_died")[0].mob_id), 5220000)
	assert_eq(int(_types(events, "mob_died")[0].mob_id), 5220000)
	assert_false(_types(events, "pickup_spawned").is_empty(), "the form's death pays the reward")


## hp_mult applies to each form; final_form_hp_mult weights the form alone.
func test_hp_split() -> void:
	for case: Array in [[{}, 37500], [{"final_form_hp_mult": 0.5}, 12500]]:
		var w := _world(case[0])
		var shell := int(w.bosses.records[0].slot)
		assert_eq(w.swarm.max_hp[shell], 6000, "the shell takes the entry's hp_mult")
		w.hit_mob(shell, KILL, -1)
		assert_eq(w.swarm.max_hp[int(w.bosses.records[0].slot)], case[1], str(case[0]))


## The entry's attacks and the form's own skills run on the form.
func test_form_uses_the_entry_attacks_and_its_own_skills() -> void:
	var w := _world()
	w.hit_mob(int(w.bosses.records[0].slot), KILL, -1)
	w.drain_events()
	var attacked := false
	var summoned := false
	for i in 20 * 60:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			attacked = attacked or (e.type == "boss_attack" and int(e.mob_id) == 5220000)
			summoned = summoned or (e.type == "boss_skill" and int(e.mob_id) == 5220000 and int(e.skill_id) == 200)
	assert_true(attacked, "entry.attacks applies to the final form")
	assert_true(summoned, "the final form casts its own canonical kit")


## A final_form that its shell does not list in info/revive is refused by validation and dies as an ordinary boss.
func test_final_form_missing_from_revive_is_invalid() -> void:
	var setup := _setup()
	setup.mob_imgs[5220001].info.revive = {"0": 210100}
	var stage: Dictionary = setup.data.stages.stages.quiet
	var errors := DataRepo.final_form_errors(stage, setup.mob_imgs)
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("5220000"), errors[0])
	assert_eq(DataRepo.final_form_errors(_setup().data.stages.stages.quiet, _setup().mob_imgs), PackedStringArray(),
		"a listed form is valid")
	var w := RunWorld.new(setup)
	w.god = true
	for i in 60:
		w.step(DT, MoveInput.new())
	w.drain_events()
	w.hit_mob(int(w.bosses.records[0].slot), KILL, -1)
	assert_true(w.bosses.all_dead(), "an unlisted form is not continued: the shell's death ends the encounter")


## build_setup reports the same violation through its missing list.
func test_build_setup_reports_an_unlisted_final_form() -> void:
	var data := DataRepo.load_all()
	var stage: Dictionary = data.stages.stages.henesys
	stage.maps[0].boss.final_form = 5220000
	var shell := int(stage.maps[0].boss.mob_id)
	var missing := PackedStringArray()
	DataRepo.build_setup(data, "henesys", 1, Vector2(800, 600), func(_p: String) -> Dictionary: return {},
		func(id: int) -> Dictionary:
			return {"info": {"revive": {"0": 210100}}} if id == shell else {"info": {}}, missing)
	assert_true(" ".join(missing).contains("final_form 5220000"), str(missing))


## stages.json schema: a final form is another mob, and its HP weight is positive.
func test_stage_schema_checks_final_form_fields() -> void:
	var file := {"stages": {"x": {"maps": [{"map_id": 1, "boss": {"mob_id": 5, "final_form": 5}}]}}}
	assert_eq(DataRepo.stage_map_errors(file).size(), 1, "the form cannot be the boss itself")
	file.stages.x.maps[0].boss = {"mob_id": 5, "final_form": 6, "final_form_hp_mult": 0.0}
	assert_eq(DataRepo.stage_map_errors(file).size(), 1, "the weight must be positive")
	file.stages.x.maps[0].boss = {"mob_id": 5, "final_form": 6, "final_form_hp_mult": 0.5}
	assert_eq(DataRepo.stage_map_errors(file), PackedStringArray())


## The roster loads the form and the summons of its skills along with the shell.
func test_roster_includes_the_form_and_its_summons() -> void:
	var setup := _setup()
	var stage: Dictionary = setup.data.stages.stages.quiet
	assert_has(StageRoster.named_ids(stage), 5220000)
	var ids := StageRoster.mob_ids(stage, setup.mob_imgs, setup.mob_skill_img)
	assert_has(ids, 5220001)
	assert_has(ids, 5220000)
	assert_has(ids, 210100, "the form's MobSkill 200 summon")


## An ordinary info/revive boss (King Slime) keeps ending its encounter on death and spawning its revives as offspring.
func test_ordinary_revive_still_finishes_the_encounter() -> void:
	var w := RunWorld.new(TF.setup(9300003, []))
	w.god = true
	for i in 60:
		w.step(DT, MoveInput.new())
	w.drain_events()
	w.hit_mob(int(w.bosses.records[0].slot), KILL, -1)
	assert_true(w.bosses.all_dead(), "no final_form: the boss's death ends the encounter despite living offspring")
	var events := w.drain_events()
	assert_eq(_types(events, "boss_died").size(), 1)
	assert_eq(_types(events, "mob_revives_spawned").size(), 1)


## The form's skills are ready one interval after the swap, never on its first tick and never from the shell's schedule,
## even for a skill both forms share (the Summon 200 of this fixture: its shell cast at 1 s, 2 s, ...).
func test_form_skills_first_cast_one_interval_after_the_swap() -> void:
	var setup := _setup()
	setup.mob_imgs[5220001].info.skill = {"0": {"skill": 200, "level": 82, "action": 1, "effectAfter": 0}}
	setup.mob_skill_img["200"].level["82"].interval = 10
	var w := RunWorld.new(setup)
	w.god = true
	for i in 60 + 10 * 60 + 30:
		w.step(DT, MoveInput.new())
	var shell_casts := _types(w.drain_events(), "boss_skill").filter(func(e: Dictionary) -> bool:
		return int(e.mob_id) == 5220001)
	assert_false(shell_casts.is_empty(), "control: the shell cast its summon before dying")
	w.hit_mob(int(w.bosses.records[0].slot), KILL, -1)
	var swapped := w.time
	assert_near(float(w.bosses.records[0].form_time), swapped, 1e-9, "the record carries the swap time")
	var first := -1.0
	for i in 12 * 60:
		w.step(DT, MoveInput.new())
		for e: Dictionary in _types(w.drain_events(), "boss_skill"):
			if int(e.mob_id) == 5220000 and first < 0.0:
				first = w.time
	assert_near(first - swapped, 10.0, 1.0 / 60.0 + 1e-6, "the form's first cast lands one interval after the swap")
	assert_true(first - swapped >= 10.0 - 1e-6, "and never earlier")


## The kill counter skips a shell that continues into its form, and counts the form's death.
func test_shell_death_is_not_a_kill() -> void:
	var w := _world()
	var before := w.kills
	w.hit_mob(int(w.bosses.records[0].slot), KILL, -1)
	assert_eq(w.kills, before, "the shell's death is not counted")
	for i in 60:
		w.step(DT, MoveInput.new())
	w.hit_mob(int(w.bosses.records[0].slot), KILL, -1)
	assert_eq(w.kills, before + 1, "the form's death is the boss kill")
	var plain := RunWorld.new(TF.setup(9300003, []))
	plain.god = true
	for i in 60:
		plain.step(DT, MoveInput.new())
	var kills := plain.kills
	plain.hit_mob(int(plain.bosses.records[0].slot), KILL, -1)
	assert_eq(plain.kills, kills + 1, "an ordinary revive boss still counts")


## boss_fights stays keyed on the scheduled entry across the swap, with the form and its swap time added.
func test_boss_fight_records_are_keyed_on_the_entry() -> void:
	var w := _world()
	var before := BR.fight_records(w)
	assert_eq(before.size(), 1)
	assert_eq(int(before[0].mob_id), 5220001)
	assert_eq(int(before[0].final_form), 5220000)
	assert_eq(float(before[0].form_time), -1.0, "no swap yet")
	w.hit_mob(int(w.bosses.records[0].slot), KILL, -1)
	var mid: Dictionary = BR.fight_records(w)[0]
	assert_eq(int(mid.mob_id), 5220001, "still the entry's id after the swap")
	assert_near(float(mid.form_time), w.time, 1e-9)
	assert_eq(mid.status, "alive")
	for key: String in before[0]:
		assert_true(mid.has(key), "existing field %s kept" % key)
	for i in 60:
		w.step(DT, MoveInput.new())
	w.hit_mob(int(w.bosses.records[0].slot), KILL, -1)
	var done: Dictionary = BR.fight_records(w)[0]
	assert_eq(int(done.mob_id), 5220001)
	assert_eq(done.status, "dead")
	assert_near(float(done.duration), float(done.death_time) - float(done.spawn_time), 1e-9, "one fight from arrival")
	var plain: Dictionary = BR.fight_records(RunWorld.new(TF.setup(9300003, [])))[0]
	assert_false(plain.has("final_form"), "encounters without a form keep the old record shape")
	assert_false(plain.has("form_time"))


## A form missing from enabled_ids while its shell is listed is flagged.
func test_final_form_missing_from_enabled_ids_is_flagged() -> void:
	var setup := _setup()
	var stage: Dictionary = setup.data.stages.stages.quiet
	assert_eq(DataRepo.final_form_errors(stage, setup.mob_imgs, [5220001.0, 5220000.0]), PackedStringArray())
	assert_eq(DataRepo.final_form_errors(stage, setup.mob_imgs, []), PackedStringArray(), "no list: nothing to compare")
	var errors := DataRepo.final_form_errors(stage, setup.mob_imgs, [5220001.0])
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("enabled_ids"), errors[0])
	assert_eq(DataRepo.final_form_errors(stage, setup.mob_imgs, [9999]), PackedStringArray(), "an unlisted shell is not flagged")
