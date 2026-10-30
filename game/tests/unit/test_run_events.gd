extends TestCase
## Event schema conformance (docs/ARCHITECTURE.md 4.4.3): every event RunWorld emits in a real run has `type` plus
## exactly the documented fields, with the documented value types; every type shows up. Also checks seeded replays
## are identical.

const SSF := preload("res://tests/fixtures/support_summon_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const EchoTest := preload("res://tests/unit/test_echo_cast.gd")
const PF := preload("res://tests/fixtures/pet_fixtures.gd")
const RV := preload("res://tests/fixtures/revive_fixtures.gd")
const CF := preload("res://tests/fixtures/combat_mechanics_fixtures.gd")
const SF := preload("res://tests/fixtures/shade_fixtures.gd")
const DT := 1.0 / 60.0

const INT_FIELDS := ["mob", "pickup", "mob_id", "item_id", "job_id", "skill_id", "level", "damage",
	"dir", "exp", "count", "rank", "magnitude", "facing", "relocated_from", "boss_index", "max_hp", "restored", "from_item_id", "weapon_id", "proj", "amount", "map_index", "map_id", "hp", "pushed"]

const BOOL_FIELDS := ["crit", "elite", "miss", "boss", "bonus", "rotate"]
const STRING_FIELDS := ["element", "reason", "skill", "hit_visual", "action", "effect", "name", "id", "tier", "portal", "target", "kind", "potion_kind", "phase", "afterimage", "sound", "attack", "source_kind", "player_effect", "summon_effect", "recipient_effect", "ball", "hit", "status", "stat", "family", "message"]





func _check(e: Dictionary, seen: Dictionary) -> void:
	var type := String(e.get("type", ""))
	if not RunWorld.EVENT_FIELDS.has(type):
		fail("unknown event type %s" % type)
		return
	seen[type] = int(seen.get(type, 0)) + 1
	var want: Array = ["type"] + RunWorld.EVENT_FIELDS[type]
	if type == "summon_spawn" and e.has("sound"):
		want.append("sound")
	want.sort()
	var got: Array = e.keys()
	got.sort()
	if got != want:
		fail("%s fields %s, documented %s" % [type, got, want])
		return
	for k: String in e:
		var v: Variant = e[k]
		if k == "pos" and not (v is Vector2):
			fail("%s.pos is %s" % [type, type_string(typeof(v))])
		elif k == "velocity" and not (v is Vector2):
			fail("%s.velocity is not Vector2" % type)
		elif k == "area" and not (v is Rect2):
			fail("%s.area is not Rect2" % type)
		elif (k == "slot" and type.begins_with("summon_")) and typeof(v) != TYPE_INT:
			fail("%s.slot is not int" % type)
		elif k in INT_FIELDS and typeof(v) != TYPE_INT:
			fail("%s.%s is %s, not int" % [type, k, type_string(typeof(v))])
		elif k in BOOL_FIELDS and typeof(v) != TYPE_BOOL:
			fail("%s.%s is %s, not bool" % [type, k, type_string(typeof(v))])
		elif k in STRING_FIELDS and typeof(v) != TYPE_STRING:
			fail("%s.%s is %s, not String" % [type, k, type_string(typeof(v))])
		elif k in ["time", "cast_time", "hit_after", "interval", "impact_time", "duration", "range", "speed", "guard", "recharge"] and typeof(v) != TYPE_FLOAT:


			fail("%s.time is not float" % type)
	if type == "boss_skill":
		assert_true(e.targets is Array,"boss skill targets are sim slot indices")
		for slot: Variant in e.targets:
			assert_true(slot is int,"boss skill target slot type")
	match type:
		"mob_revives_spawned":
			assert_true(e.revives is Array)
			for child: Dictionary in e.revives:
				assert_eq(child.keys(), ["mob", "mob_id"])
				assert_true(child.mob is int and child.mob_id is int)
		"job_advance_pending":
			for o: Dictionary in e.options:
				var ok: Array = o.keys()
				ok.sort()
				var fields := ["available", "job_id", "name", "paths", "reason"]
				if ok != fields:
					fail("job option fields %s" % [ok])
				elif typeof(o.job_id) != TYPE_INT or typeof(o.available) != TYPE_BOOL \
						or not (o.paths is Array):
					fail("job option types %s" % [o])
				else:
					for p: Dictionary in o.paths:
						var path_fields: Array = p.keys()
						path_fields.sort()
						assert_eq(path_fields, ["family", "id", "item_id", "label"])
						assert_true(p.id is String and p.family is String and p.label is String and p.item_id is int)
		"choice_pending":
			for c: Dictionary in e.cards:
				var ck: Array = c.keys()
				ck.sort()
				if ck != ["card_kind", "desc", "icon", "id", "kind", "magnitude", "max_rank", "name", "rank", "rank_before", "rarity_bonus", "skill", "skill_changes", "skill_effect_stat",
						"skill_level", "skill_level_max", "skill_level_next", "skill_mod_changes", "skill_name", "skill_rank_before", "skill_rank_max", "slots", "tier"]:
					fail("card fields %s" % [ck])
				elif typeof(c.rank) != TYPE_INT or typeof(c.max_rank) != TYPE_INT or typeof(c.skill_level) != TYPE_INT 						or typeof(c.skill_level_next) != TYPE_INT:
					fail("card rank types %s" % [c])
				elif not (c.skill_changes is Dictionary):
					fail("card skill_changes is not a Dictionary")
				elif not (c.tier is String) or not c.tier in UpgradePool.TIERS or not (c.magnitude is int) or not (c.rank_before is int):
					fail("card rarity schema %s" % [c])
				else:
					for field: String in c.skill_changes:
						var change: Dictionary = c.skill_changes[field]
						if not field in ["mad", "mastery", "fixdamage", "time", "x", "pdd", "cooltime", "speed", "range", "hp", "mobCount", "damage", "hpCon", "max_hp_per_level", "regen_hp"] or change.size() != 2 \
								or typeof(change.get("before")) != TYPE_INT or typeof(change.get("after")) != TYPE_INT:
							fail("card skill change schema %s: %s" % [field, change])
		"mob_hit":
			if int(e.damage) < 1:
				fail("damage below 1")
		"player_hit":
			if bool(e.miss) and int(e.damage) != 0:
				fail("a missed hit cannot spend HP")
			elif not bool(e.miss) and int(e.damage) < 1:
				fail("a landed hit must deal at least 1")
		"cast":
			if not (int(e.facing) in [-1, 1]):
				fail("facing %s" % e.facing)


func test_every_event_matches_the_schema() -> void:
	var w := RunWorld.new(RF.setup("henesys", 4242))
	w.god = true # Schema coverage uses a living run; separate seeded full runs test actual survival.
	var seen := {}
	var memo := {}
	for t in 60 * 360:
		var guard := 0
		while w.state != RunWorld.PLAYING and w.state != RunWorld.DEAD and w.state != RunWorld.CLEARED and guard < 64:
			guard += 1
			RF.auto_choose(w)
		if w.state != RunWorld.PLAYING:
			break
		w.step(DT, RF.bot_input(w, memo))
		for e: Dictionary in w.drain_events():
			_check(e, seen)
	RF.auto_choose(w)
	if w.state == RunWorld.PLAYING:
		w.duration = w.time
		w.bosses = BossDirector.new() # The clear event's schema is independent of the boss clear gate.
		w.step(DT, MoveInput.new())
		RF.auto_choose(w) # settle swept EXP choices before expecting stage_cleared
	for e: Dictionary in w.drain_events():
		_check(e, seen)
	# A death for player_died.
	var d := RF.quiet_world(400.0)
	d.take_hit(1000.0, false, "", d.player.pos + Vector2(20, 0)) # Guaranteed lethal schema probe.
	for e: Dictionary in d.drain_events():
		_check(e, seen)
	# A second life for player_revived: a test-only reaction skill (no Bishop data) catches a lethal hit beside a monster.
	var revived := RV.world(375)
	RF.put_mob(revived, 100100, 900.0)
	revived.mob_grid.rebuild(revived.swarm.x, revived.swarm.y, revived.swarm.active)
	RV.hit(revived, {"boss": false, "source_kind": "touch"})
	for e: Dictionary in revived.drain_events():
		_check(e, seen)
	# Both player-hit variants obey the same documented event schema.
	var m := RF.quiet_world(400.0, 617)
	m.loadout.add_player_mod("avoid", "add", 1000.0)
	m.refresh_player_stats()
	m.drain_events()
	m.take_hit(82.0, false, "", m.player.pos, {"accuracy": 42})
	for e: Dictionary in m.drain_events():
		_check(e, seen)
	# A short scheduled boss encounter covers warning/spawn/death and a boss hit's source fields.
	var boss_setup := RF.setup("quiet", 19, RF.quiet_data())
	boss_setup.data.jobs_survivor.jobs["212"]["starting_skill"] = ""; boss_setup.data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	RF.set_bosses(boss_setup.data.stages.stages.quiet, [{"time": 0.5, "mob_id": 100100}])
	var b := RunWorld.new(boss_setup)
	b.god = true
	for tick in 35:
		b.step(DT, MoveInput.new())
	var slot := int(b.bosses.records[0].slot)
	b.mob_kinds[b.swarm.kind[slot]].move_speed = 0
	for tick in 360:
		b.step(DT, MoveInput.new())
	slot = int(b.bosses.records[0].slot)
	b.god = false
	b.take_hit(12.0, false, "", b.player.pos, {"mob": slot, "mob_id": 100100, "boss": true})
	b.hit_mob(slot, {"damage_min": 999.0, "damage_max": 999.0, "magic": false,
		"crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
	b.step(DT, MoveInput.new())
	for e: Dictionary in b.drain_events():
		_check(e, seen)
	var slam := RunWorld.new(preload("res://tests/fixtures/boss_attack_fixtures.gd").setup())
	slam.god = true
	for tick in 180:
		slam.step(DT, MoveInput.new())
	for event: Dictionary in slam.drain_events():
		_check(event, seen)
	# #76: an ordinary Tauro attack (mob_attack); Jr. Boogie beside it deals contact damage only.
	var ordinary := preload("res://tests/fixtures/mob_attack_fixtures.gd").world()
	ordinary.god = true
	RF.put_mob(ordinary, 7130100, 600)
	RF.put_mob(ordinary, 3230300, 620)
	for tick in 15 * 60:
		ordinary.step(DT, MoveInput.new())
	for event: Dictionary in ordinary.drain_events():
		_check(event, seen)
	var stumpy := RunWorld.new(preload("res://tests/fixtures/stumpy_fixtures.gd").setup())
	stumpy.god = true
	for tick in 600:
		stumpy.step(DT, MoveInput.new())
	for event: Dictionary in stumpy.drain_events():
		_check(event, seen)
	var heal := RunWorld.new(preload("res://tests/fixtures/stumpy_fixtures.gd").heal_setup())
	heal.god = true
	for tick in 60:
		heal.step(DT, MoveInput.new())
	heal.hit_mob(int(heal.bosses.records[0].slot), {"damage_min": 1500.0, "damage_max": 1500.0,
		"magic": false, "crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
	for tick in 32 * 60:
		heal.step(DT, MoveInput.new())
	for event: Dictionary in heal.drain_events():
		_check(event, seen)
	# A same-map warp for portal_used (the synthetic hunting ground otherwise has only spawn points).
	var king := RunWorld.new(preload("res://tests/fixtures/tree_boss_fixtures.gd").setup(9300003, []))
	king.god = true
	for tick in 60:
		king.step(DT, MoveInput.new())
	king.hit_mob(int(king.bosses.records[0].slot), {"damage_min": 100000.0, "damage_max": 100000.0,
		"magic": true, "crit": 0.0, "crit_mult": 1.5, "skill": "energy_bolt"}, -1)
	for event: Dictionary in king.drain_events():
		_check(event, seen)
	var p_setup := RF.setup("quiet", 17, RF.quiet_data())
	p_setup.map_img.portal = {
		"0": {"pn": "source", "pt": 1, "x": 400, "y": 200, "tm": 999999999, "tn": "destination"},
		"1": {"pn": "destination", "pt": 1, "x": 800, "y": 80, "tm": 999999999, "tn": ""},
	}
	var p := RunWorld.new(p_setup)
	p.player.place(Vector2(400, 200), p.fhm)
	p.step(DT, MoveInput.make(false, false, true))
	for e: Dictionary in p.drain_events():
		_check(e, seen)
	var mano := preload("res://tests/fixtures/mano_fixtures.gd").world([126,112,113])
	for tick in 60*17:
		mano.step(DT,MoveInput.new())
	for event: Dictionary in mano.drain_events():
		_check(event,seen)
	# Guaranteed unlimited potion use exercises the consumable schema.
	var potion := RF.quiet_world()
	potion.step(DT, MoveInput.new())
	potion.drink_potion("hp")
	potion.progression.level = 10
	potion.apply_potion_schedule(10, true)
	for e: Dictionary in potion.drain_events():
		_check(e, seen)
	var buff_setup := RF.setup("quiet", 12, RF.quiet_data())
	buff_setup.data.jobs_survivor.jobs["212"]["starting_skill"] = ""; buff_setup.data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	var buff_world := RunWorld.new(buff_setup)
	RF.as_job(buff_world, 200)
	buff_world.loadout.ranks.erase("energy_bolt")
	buff_world.loadout.order.erase("energy_bolt")
	buff_world.learn_skill("magic_armor")
	for tick in 2:
		buff_world.step(DT, MoveInput.new())
	for tick in 60 * 112:
		buff_world.step(DT, MoveInput.new())
	for e: Dictionary in buff_world.drain_events():
		_check(e, seen)
	var recovery := RF.quiet_world(400, 13)
	recovery.learn_skill("recovery")
	recovery.take_hit(40, false, "", recovery.player.pos + Vector2(10, 0))
	for tick in 60 * 30 + 1:
		recovery.step(DT, MoveInput.new())
	for e: Dictionary in recovery.drain_events():
		_check(e, seen)
	var statuses := RF.quiet_world()
	var affected := RF.put_mob(statuses, 1110100, 700)
	for status: String in MobSwarm.STATUS_NAMES:
		statuses.swarm.apply_status(affected, status, {"x": -40, "level": 30, "time": 1}, statuses.events)
	for tick in 60:
		statuses.step(DT, MoveInput.new())
	for event: Dictionary in statuses.drain_events():
		_check(event, seen)
	var teleporter := RF.quiet_world(400, 60)
	RF.as_job(teleporter, 210)
	teleporter.learn_skill("teleport_fp")
	var blink := MoveInput.new()
	blink.press_skill("teleport")
	teleporter.step(DT, blink)
	for event: Dictionary in teleporter.drain_events():
		_check(event, seen)
	# Flash Jump (#405): a Night Lord's airborne flash announces itself with `flash_jump {skill, from, to}`.
	var flash_data := RF.quiet_data()
	flash_data.jobs_survivor.jobs["412"]["playable"] = true
	var flash_setup := RF.setup("quiet", 405, flash_data)
	flash_setup["job"] = 412
	var flasher := RunWorld.new(flash_setup)
	flasher.player.place(Vector2(400, -200), flasher.fhm)
	var flash_press := MoveInput.new()
	flash_press.press_skill("flash_jump")
	flash_press.right = true
	flasher.step(DT, flash_press)
	var flashed := 0
	for event: Dictionary in flasher.drain_events():
		_check(event, seen)
		flashed += int(event.type == "flash_jump")
	assert_eq(flashed, 1, "the flash announced itself once")
	# Shared restoration has no live skill consumer until the second-job tickets land.
	var restored := RF.quiet_world()
	restored.take_hit(10, false, "", restored.player.pos + Vector2(10, 0))
	restored.restore_player("hp", 2, "synthetic")
	for event: Dictionary in restored.drain_events():
		_check(event, seen)
	# A synthetic Final Attack (#161) follows a physical line of the held sword with its own event.
	var final_data := RF.quiet_data()
	final_data.skills.skills["final_fixture"] = {"skill_id": 9991005, "book": "999", "kind": "passive", "slot": "passive",
		"name": "Final", "damage": "physical", "ranks": [1], "action": "swingO1", "action_time": 0.0,
		"final_attack": {"chance_field": "prop"}, "effect": "", "icon": ""}
	var final_setup := RF.setup("quiet", 161, final_data)
	final_setup.skill_imgs["999"] = {"skill": {"9991005": {"level": {"1": {"prop": 100, "damage": 200}}}}}
	var finisher := RunWorld.new(final_setup)
	RF.place_player(finisher, 400)
	finisher.learn_skill("final_fixture")
	var target := RF.put_mob(finisher, 100100, 450, 190, 1000)
	finisher.hit_mob(target, {"skill": "fixture", "damage_type": "physical", "magic": false, "damage_min": 5.0,
		"damage_max": 5.0, "crit": 0.0, "crit_mult": 1.5}, -1)
	finisher.step(DT, MoveInput.new())
	for event: Dictionary in finisher.drain_events():
		_check(event, seen)
	# An equipment drop beside the player with a full Equip tab: spawn, then the inventory-full notice.
	var full := RF.quiet_world(400, 61)
	while full.equipment.inventory.size() < full.inventory_slots():
		full.equipment.inventory.append({"id": 1002001, "stats": {}, "slots": 7, "scrolls": 0})
	full.spawn_equipment(full.player.pos + Vector2(20, 0), {"id": 1372005, "stats": {"incMAD": 23}, "slots": 7, "scrolls": 0})
	for tick in 90:
		full.step(DT, MoveInput.new())
	for event: Dictionary in full.drain_events():
		_check(event, seen)
	# A scroll read on the worn top reports its result (#110).
	var scroller := RF.quiet_world()
	scroller.setup.scroll_info = {2040400: {"incPDD": 1, "success": 100}}
	scroller.equipment.worn.top.slots = 1
	scroller.grant_scrolls(2040400, 1)
	assert_eq(scroller.use_scroll(2040400, "top"), "")
	for event: Dictionary in scroller.drain_events():
		_check(event, seen)
	# A Night Lord's throwing stars reach the next tier (#155, exact job 412): ammo_upgraded, schema-checked like every event.
	var thrower := RF.quiet_world()
	thrower.setup.equipment_info[1472000] = {"incPAD": 10.0, "attackSpeed": 6.0}
	thrower.equipment.inventory.append(Equipment.create(1472000, {"incPAD": 10.0, "attackSpeed": 6.0}))
	assert_eq(thrower.equip_item(thrower.equipment.inventory.size() - 1), "")
	thrower.progression.level = 37
	RF.as_job(thrower, 412)
	for event: Dictionary in thrower.drain_events():
		_check(event, seen)
	# An echo clone repeats a star cast (spec #383 M11): echo_cast, schema-checked like every event. The skills are synthetic.
	var echoer := EchoTest.world()
	echoer.step(DT, MoveInput.new())
	EchoTest.mob(echoer, 500)
	for tick in 40:
		echoer.step(DT, MoveInput.new())
	for event: Dictionary in echoer.drain_events():
		_check(event, seen)
	# A Gunslinger's Grenade is thrown (#192): skill_thrown, schema-checked like every event.
	var grenadier := RF.quiet_world()
	RF.as_job(grenadier, 520)
	grenadier.loadout.order.clear()
	assert_true(grenadier.learn_skill("grenade"))
	RF.put_mob(grenadier, 1110100, grenadier.player.pos.x + 200, 190, 1000)
	for tick in 90:
		grenadier.step(DT, MoveInput.new())
	for event: Dictionary in grenadier.drain_events():
		_check(event, seen)
	# A chain cast (#323): skill_chain, schema-checked like every event. The skill is synthetic.
	var chain_setup := RF.setup("quiet", 323, RF.quiet_data())
	var chain_levels := {}
	for lv in range(1, 31):
		chain_levels[str(lv)] = {"mad": 100.0, "mastery": 10.0, "mobCount": 3.0}
	chain_setup.skill_imgs["212"] = {"skill": {"9992000": {"level": chain_levels}}}
	var chainer := RunWorld.new(chain_setup)
	RF.place_player(chainer, 200)
	chainer.loadout.order.clear()
	chainer.book.defs["chain_test"] = {"skill_id": 9992000, "book": "212", "job": 212, "kind": "instant",
		"slot": "active", "damage": "magic", "cooldown": 1.6, "ranks": [1], "action": "swingO1", "action_time": 0.5,
		"ball": "", "hit": "", "effect": "", "cast": {"rule": "chain", "acquire": 450, "hop": 200, "min_targets": 1}}
	assert_true(chainer.learn_skill("chain_test"))
	RF.put_mob(chainer, 1110100, 260, 195, 1000)
	RF.put_mob(chainer, 1110100, 330, 195, 1000)
	chainer.mob_grid.rebuild(chainer.swarm.x, chainer.swarm.y, chainer.swarm.active)
	chainer.runner.step(DT, chainer)
	for event: Dictionary in chainer.drain_events():
		_check(event, seen)
	# Spec #34 pet events: the pet's own drink and its teleport to a player who left it behind.
	var pet_world := PF.world([PF.KITTY, PF.AUTO_HP], {"hp": 0.5})
	pet_world._hp = 1.0
	PF.put_pet(pet_world, Vector2(30.0, 0.0))
	PF.put_player(pet_world, 1100.0, 0.0)
	for event: Dictionary in PF.run(pet_world, 3):
		_check(event, seen)
	# #194: a buff cast whose failure chance rolls true (Oak Barrel) emits buff_failed and starts nothing.
	var failing := RF.quiet_world()
	assert_false(failing.start_buff("failing", {"skill_id": 5101007, "level": 1, "icon": "", "duration": 4.0,
		"fail_chance": 1.0}))
	for event: Dictionary in failing.drain_events():
		_check(event, seen)
	# #210: Disorder's recipient art is a status effect, never a fake damaging mob_hit.
	var disorder := RF.quiet_world()
	RF.as_job(disorder, 400, "dagger")
	disorder.loadout.order.clear()
	disorder.learn_skill("disorder")
	for dx in [40.0, 80.0, 120.0]:
		RF.put_mob(disorder, 1110100, disorder.player.pos.x + dx, disorder.player.pos.y)
	disorder.mob_grid.rebuild(disorder.swarm.x, disorder.swarm.y, disorder.swarm.active)
	disorder.runner.step(DT, disorder)
	for event: Dictionary in disorder.drain_events():
		_check(event, seen)
	var transfer := RunWorld.new(preload("res://tests/fixtures/map_transfer_fixtures.gd").setup(0.1))
	transfer.god = true
	for tick in 60:
		transfer.step(DT, MoveInput.new())
	transfer.hit_mob(int(transfer.bosses.records[0].slot), {"damage_min": 1e9, "damage_max": 1e9,
		"magic": false, "crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
	transfer.step(DT, MoveInput.new())
	transfer.advance_map()
	for event: Dictionary in transfer.drain_events():
		_check(event, seen)
	# P3: no playable job owns a form yet. Exercise the new events with synthetic stance data.
	var former := RunWorld.new(RF.setup("quiet", 311, RF.quiet_data()))
	former.progression.job_id = 999
	former.book.defs["fixture_form"] = {"skill_id": 9991001, "book": "999", "kind": "form", "slot": "active", "damage": "none",
		"ranks": [1], "cooldown": 3.0, "cast": {"rule": "form", "mob_within": 400},
		"form": {"duration": 1.0, "exclusive_group": "fixture", "effects": {"element": "f"}, "subs": []}}
	former.drain_events()
	former.runner.forms.start(former, "fixture_form", former.loadout.stats("fixture_form"))
	former.runner.forms.step(1.0, former)
	for event: Dictionary in former.drain_events():
		_check(event, seen)
	# H3: the no-meter F/P probe cannot emit this job-specific event. Exercise the generic counter.
	var meter := PlayerMeter.new({"id": "fixture", "max": 10, "gain": {"event": "cast_landed", "amount": 1}})
	var meter_events: Array = []
	meter.gain("cast_landed", meter_events)
	for event: Dictionary in meter_events:
		_check(event, seen)
	# D3 (#351): no shipped skill pays HP in this probe's runs. Exercise both kinds of hp_spent through HpRisk.
	var risk := RF.quiet_world(400.0, 351)
	risk.god = false
	risk.drain_events()
	var risk_stats := {"skill": "synthetic", "skill_id": 9991000, "hp_cost": 5, "self_damage": 50.0, "self_damage_cap": 1.0}
	HpRisk.pay_cost(risk, risk_stats)
	HpRisk.settle(risk, risk_stats, risk.damage_dealt - 40)
	var spent := risk.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "hp_spent")
	assert_eq(spent.map(func(e: Dictionary) -> String: return e.kind), ["cost", "recoil"])
	for event: Dictionary in spent:
		assert_eq(event.size(), 5)
		_check(event, seen)
	var pull := CF.world({"pull": {"min_gap": 60}, "range": 600.0})
	RF.put_mob(pull, 1110100, pull.player.pos.x + 300)
	pull.mob_grid.rebuild(pull.swarm.x, pull.swarm.y, pull.swarm.active)
	pull.runner.apply_pull(pull, "synthetic", pull.loadout.stats("synthetic"), pull.cast_origin())
	var pulls := pull.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_pulled")
	assert_eq(pulls.size(), 1)
	for event: Dictionary in pulls:
		assert_eq(event.size(), 4)
		_check(event, seen)
	# Real follower events, including the optional summon sound and per-target strike effect.
	var followers := preload("res://tests/unit/test_bowmaster_followers.gd").new()
	var hawk: RunWorld = followers._world("silver_hawk")
	followers._mob(hawk, 1110100, 300)
	hawk.book.skill_imgs["311"].skill["3111005"].summon.attack1.info["effect"] = {"0": {"delay": 100.0}}
	for tick in 240:
		hawk.step(DT, MoveInput.new())
	for event: Dictionary in hawk.drain_events():
		_check(event, seen)
	for type: String in RunWorld.EVENT_FIELDS:
		if type == "meso_picked":
			var data := RF.quiet_data()
			data.jobs_survivor.jobs["212"]["meter"] = {"id": "meso_charge", "max": 10,
				"gain": {"event": "meso_picked", "amount": 1, "per_mesos": 1000}, "per_unit": {"stat": "damage", "value": 0.03}}
			var looter := RunWorld.new(RF.setup("quiet", 403, data))
			RF.place_player(looter, 200)
			var drop := looter.pickups.spawn_meso(looter.player.pos, 1200)
			looter.pickups.state[drop] = PickupSystem.REST
			looter.step(DT, MoveInput.new())
			for event: Dictionary in looter.drain_events():
				_check(event, seen)
		if type == "ammo_shot":
			var archer := CF.ranged_final(1452000, 312)
			var dummy := RF.put_mob(archer, 1110100, 350, 190, 100)
			archer.hit_mob(dummy, {"skill": "fixture", "damage_type": "physical", "damage_min": 1,
				"damage_max": 1, "crit": 0, "crit_mult": 1.5}, -1)
			archer.step(DT, MoveInput.new())
			for event: Dictionary in archer.drain_events():
				_check(event, seen)
		if type == "skill_impact":
			var blaster := CF.world({"kind": "projectile", "impact_blast": {}})
			RF.put_mob(blaster, 1110100, 350, 190, 100)
			for tick in 30:
				blaster.step(DT, MoveInput.new())
			for event: Dictionary in blaster.drain_events():
				_check(event, seen)
		if type == "burst_start" or type == "burst_end":
			var archer := CF.world({"kind": "projectile", "cast": {"rule": "burst"},
				"burst": {"interval": 0.1, "wind_up": 0.1, "retarget": true}, "count": 3})
			RF.put_mob(archer, 1110100, 350, 190, 100000)
			for tick in 40:
				archer.step(DT, MoveInput.new())
			for event: Dictionary in archer.drain_events():
				_check(event, seen)

		if type == "support_pulse":
			var beholder := SSF.world()
			for tick in 200: # the synthetic Hex pulse lands at 3 s
				beholder.step(DT, MoveInput.new())
			# summon_spawn / summon_attack (T9) were never registered in EVENT_FIELDS: check only this ticket's event.
			for event: Dictionary in beholder.drain_events():
				if event.type in ["support_pulse", "buff_cast", "player_restored"]:
					_check(event, seen)
		if type == "player_banished":
			var shaded := SF.world()
			for tick in 15 * 60:
				shaded.step(DT, MoveInput.new())
			for event: Dictionary in shaded.drain_events():
				_check(event, seen)
		assert_true(seen.has(type), "%s was emitted (seen %s)" % [type, seen])


func _digest(p_seed: int, seconds: float) -> String:
	var w := RunWorld.new(RF.setup("henesys", p_seed))
	var memo := {}
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for t in roundi(seconds * 60.0):
		RF.auto_choose(w)
		if w.state != RunWorld.PLAYING:
			break
		w.step(DT, RF.bot_input(w, memo))
		for e: Dictionary in w.drain_events():
			ctx.update(var_to_str(e).to_utf8_buffer())
	ctx.update(var_to_str(w.player_state).to_utf8_buffer())
	return ctx.finish().hex_encode()


func test_seeded_runs_replay_identically() -> void:
	var a := _digest(31, 90.0)
	var b := _digest(31, 90.0)
	var c := _digest(32, 90.0)
	assert_eq(a, b, "same seed, same events")
	assert_ne(a, c, "another seed differs")
