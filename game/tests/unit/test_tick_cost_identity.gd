extends TestCase
## Issue #146: the per-tick cost work leaves the simulation bit-identical. A fixed-seed, fixed-tick round on the
## synthetic map (no WZ data) that is busy in the places the work touches: 160 mobs refilled around a god-mode player
## whose MP runs dry (every cast rule waiting for MP between refills), a Magician loadout with every auto-cast rule
## (nearest, box, crowd, hp_or_undead, buffs), a drop pool of several hundred meso, equipment, EXP and potion drops
## lying on every floor, an Equip tab that fills up (pickup_blocked), and a pet with VAC brought out, dismissed with
## drops in flight and brought back. The digest covers every drained event, the player state after every tick and the
## drop pool every second, all as var_to_bytes (exact float bits; JSON/str() round floats, #142), plus the totals.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const PF := preload("res://tests/fixtures/pet_fixtures.gd")
const MF := preload("res://tests/fixtures/mano_fixtures.gd")
const TF := preload("res://tests/fixtures/tree_boss_fixtures.gd")
const DT := 1.0 / 60.0
const TICKS := 3600
## Ticks at which the pet with VAC comes out, is dismissed (its drops in flight) and comes back.
const PET_ON := 2400
const PET_OFF := 2415
const PET_BACK := 2700
## Every MP_CYCLE ticks a fifth of the MP pool is refilled and MP_DRAIN ticks later it is spent to 0, so casts come in
## bursts between long MP-short stretches (level-ups refill it too).
const MP_CYCLE := 300
const MP_DRAIN := 60
## Re-captured on Windows on the unoptimised spec #151 tip (19ca0a8), then matched against the #177 merge.
## Spec #151 changes crit RNG, physical combat and player-state fields (including attack speed and accuracy), so
## its events and totals legitimately differ from main's 4e51522e... baseline. The #146 optimisation changes neither.
## Re-captured for #194 (spec #168): player_state gains `hidden` and `morph` and every buff snapshot `hidden`, `morph` and
## `end_hp_above`; the events and TOTALS are unchanged, only those bytes differ (previous digest cb554e31...).
const GOLDEN := "ad5c2bc1c6db7cb8ffd92a8d5909296941900219b6873e57de5ddd7aebbe48db"
const TOTALS := {"exp": 5133, "mesos": 97368, "pickup_mesos": 97368, "equips_collected": 24,
	"equips_dropped": 30, "inventory": 24, "hp_potions": 15, "mp_potions": 0, "kills": 276, "casts": 249, "level": 14,
	"pool": 6, "time": 59.999999999997875}
const SKILLS: Array[String] = ["energy_bolt", "magic_claw", "magic_guard", "cold_beam", "thunder_bolt", "slow_il",
	"heal", "fire_arrow", "poison_breath", "holy_arrow"]


func test_busy_round_with_a_big_drop_pool_and_mp_short_casts_is_unchanged() -> void:
	var r := _replay(TICKS)
	var c: Dictionary = r.coverage
	# The scenario must exercise what it guards; a quiet replay would prove nothing.
	assert_true(int(c.max_pool) >= 400, "a big drop pool (max %d)" % int(c.max_pool))
	assert_true(int(c.max_meso) >= 300, "hundreds of meso drops lying at once (max %d)" % int(c.max_meso))
	assert_true(int(c.blocked) > 0, "an equipment drop is blocked by the full Equip tab")
	assert_true(int(c.pet_pickups) >= 200, "the VAC pet collects hundreds of drops (%d)" % int(c.pet_pickups))
	assert_true(int(c.mp_short_ticks) >= 1000, "long MP-short stretches (%d ticks)" % int(c.mp_short_ticks))
	for rule: String in ["nearest", "box", "crowd", "buff"]:
		assert_true(int(c.casts.get(rule, 0)) > 0, "a %s skill casts (%s)" % [rule, c.casts])
	assert_true(int(c.kills) >= 200, "kills keep adding drops (%d)" % int(c.kills))
	assert_eq(r.totals, TOTALS, "collected totals, seed 146")
	assert_eq(r.digest, GOLDEN, "event, player-state and drop-pool bytes, seed 146")


func test_mp_short_target_check_agrees_with_full_admission_for_every_cast_rule() -> void:
	# cast_ready asks has_target instead of building the target list while a skill is short of MP; on every platform
	# it must give admission's own answer, for every skill, with and without targets.
	var w := _world()
	# Half the mob kinds undead, so hp_or_undead is admitted through its undead targets at full HP (god mode), not
	# only through the HP threshold.
	var undead := 0
	for k in w.mob_kinds.size():
		if k % 2 == 0:
			(w.mob_kinds[k] as MobKind).undead = true
			undead += 1
	assert_true(undead > 0 and undead < w.mob_kinds.size(), "some kinds undead, some not (%d)" % undead)
	var seen := {}
	for tick in 1500:
		if tick % MP_CYCLE == 0:
			w.heal_fraction("mp", 0.2)
		elif tick % MP_CYCLE == MP_DRAIN:
			w.spend_mp(int(w.player_state.mp))
		BotInput.auto_choose(w)
		if tick % 3 == 0 and w.state == RunWorld.PLAYING:
			var origin := w.cast_origin()
			for key: String in w.loadout.order:
				if not w.loadout.book.is_active(key):
					continue
				var st := w.runner.stats_of(w, key)
				var admitted := not w.runner._admit_cast(w, key, st, origin).is_empty()
				var answer := w.runner.has_target(w, key, st, origin)
				if answer != admitted:
					fail("%s at %.2f s: has_target %s, admission %s" % [key, w.time, answer, admitted])
					return
				var rule := "buff" if String(st.kind) == "buff" else String(st.cast_rule)
				seen["%s:%s" % [rule if rule != "" else "nearest", admitted]] = true
				if rule == "hp_or_undead" and w.player_state.hp >= w.player_state.max_hp * 0.5:
					# Above Heal's threshold only undead in its box admit it. The synthetic skill data has no WZ
					# lt/rb box, so the same stats with a box around the character exercise the undead path.
					var boxed := st.duplicate()
					boxed.has_box = true
					boxed.box = Rect2(-300.0, -200.0, 600.0, 260.0)
					var undead_admitted := not w.runner._admit_cast(w, key, boxed, origin).is_empty()
					if w.runner.has_target(w, key, boxed, origin) != undead_admitted:
						fail("%s with a box at %.2f s: has_target disagrees with admission (%s)" % [key, w.time,
							undead_admitted])
						return
					seen["hp_or_undead_undead_box:%s" % undead_admitted] = true
		w.step(DT, _input(tick))
		w.drain_events()
	for rule: String in ["nearest", "box", "crowd", "hp_or_undead", "hp_or_undead_undead_box", "buff"]:
		assert_true(seen.has(rule + ":true"), "%s admitted at least once (%s)" % [rule, seen.keys()])
		assert_true(seen.has(rule + ":false"), "%s refused at least once (%s)" % [rule, seen.keys()])


func test_bulk_live_defense_equals_the_per_slot_defense_and_immunity() -> void:
	# _fill_live_defense (one pass over the swarm) must write both mob_defense cases and physical_hit_allowed(slot) for
	# every live slot, while defense buffs (MobSkill 112/113) and weapon immunity (140) are on and after they expire.
	var buffed := 0
	var pdd_buffed := 0
	var immune := 0
	var checked := 0
	var defense := MF.world([112, 113])
	var immunity := RunWorld.new(TF.setup(6220000, [140], []))
	immunity.god = true
	for w: RunWorld in [defense, immunity]:
		for tick in 2400:
			w.step(DT, MoveInput.new())
			w.drain_events()
			if w.state != RunWorld.PLAYING:
				break
			if tick == 60 and w == immunity:
				var boss := int(w.bosses.records[0].slot)
				w.hit_mob(boss, {"damage_min": 12000.0, "damage_max": 12000.0, "magic": false, "crit": 0.0,
					"crit_mult": 1.5, "skill": "three_snails"}, -1)  # under the HP gate of skill 140 (from 30 s)
			if tick % 4 != 0:
				continue
			w._fill_live_defense()
			for slot in w.swarm.capacity():
				if w.swarm.active[slot] == 0:
					continue
				var expected := PackedFloat32Array([w.mob_defense(slot, true)])[0]
				var expected_pdd := PackedFloat32Array([w.mob_defense(slot, false)])[0]
				assert_eq(w._live_pdd[slot], expected_pdd, "bulk physical defense matches per-slot PDD")
				if w._live_mdd[slot] != expected or (w._live_physical_allowed[slot] == 1) != w.physical_hit_allowed(slot):
					fail("slot %d at %.2f s: %s / %d, per slot %s / %s" % [slot, w.time, w._live_mdd[slot],
						w._live_physical_allowed[slot], expected, w.physical_hit_allowed(slot)])
					return
				checked += 1
				if w.mob_skills.defense_bonus(slot, true, w.time) > 0.0:
					buffed += 1
				if w.mob_skills.defense_bonus(slot, false, w.time) > 0.0:
					pdd_buffed += 1
				if not w.physical_hit_allowed(slot):
					immune += 1
	assert_true(checked > 1000, "live slots compared (%d)" % checked)
	assert_true(buffed > 0, "some slots compared under a magic defense buff (%d)" % buffed)
	assert_true(pdd_buffed > 0, "some slots compared under a physical defense buff (%d)" % pdd_buffed)
	assert_true(immune > 0, "some slots compared under weapon immunity (%d)" % immune)


## Data: the real files plus a stage that keeps 160 mobs alive, more equipment drops, no MP potions and little MP.
static func _data() -> Dictionary:
	var data := DataRepo.load_all()
	var pool := {}
	for id in DataRepo.stage_mob_ids(data, "henesys_hg1"):
		pool[str(id)] = 1.0
	data.stages.stages["pool_146"] = {
		"map_id": 0, "name": "pool_146", "duration": 1.0e9, "hard_cap": 160,
		"keyframes": [{"t": 0.0, "rate": 60.0, "max_alive": 160.0, "hp": 0.02, "speed": 1.0, "damage": 1.0,
			"pool": pool}],
		"bursts": {}, "elites": {},
	}
	data.equipment_drops.chance = 0.05
	data.balance.potions.mp.start = 0
	data.balance.potions.drops = {"normal": {"hp": 0.05, "mp": 0.0}, "elite": {"hp": 0.0, "mp": 0.0}}
	data.balance.regen.mp = 0
	return data


static func _world() -> RunWorld:
	var s := RF.with_basic_attack(RF.setup("pool_146", 146, _data()))
	s.account = {"owned": PF.EVERYTHING}
	var w := RunWorld.new(s)
	w.god = true
	w.change_job(220)
	for key: String in SKILLS:
		w.learn_skill(key)
	# Several hundred drops lying on every floor of the map from the start: mesos, equipment, EXP.
	var rng := RandomNumberGenerator.new()
	rng.seed = 146
	var info := Equipment.info_of(s.equipment_info, 1302000)
	for k in 420:
		var pos := Vector2(-950.0 + k * 9.4, 60.0 - float(k % 4) * 140.0)
		if k % 14 == 0:
			w.spawn_equipment(pos, Equipment.create_drop(1302000, info, rng))
		elif k % 5 == 0:
			var slot := w.pickups.spawn(pos, 3 + k % 7, 4000019, w.player.pos)
			w.emit("pickup_spawned", {"pickup": slot, "item_id": 4000019, "pos": pos, "kind": "exp",
				"potion_kind": "", "count": 0})
		else:
			w.spawn_meso(pos, 10 + k)
	return w


## The scripted walk: right, stand, left, stand (8 s cycle), a jump now and then.
static func _input(tick: int) -> MoveInput:
	var phase := tick % 480
	var input := MoveInput.new()
	input.right = phase < 180
	input.left = phase >= 240 and phase < 420
	input.jump_pressed = tick % 97 == 0
	input.jump_held = input.jump_pressed
	return input


## Plays the scenario for `ticks` and returns {digest, totals, coverage}.
static func _replay(ticks: int) -> Dictionary:
	var w := _world()
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	var coverage := {"max_pool": 0, "max_meso": 0, "blocked": 0, "pet_pickups": 0, "mp_short_ticks": 0, "casts": {},
		"kills": 0}
	for tick in ticks:
		if tick == PET_ON or tick == PET_BACK:
			w.set_pet(PF.KITTY)
		elif tick == PET_OFF:
			w.set_pet(0)
		if tick % MP_CYCLE == 0:
			w.heal_fraction("mp", 0.2)
		elif tick % MP_CYCLE == MP_DRAIN:
			w.spend_mp(int(w.player_state.mp))
		BotInput.auto_choose(w)
		w.step(DT, _input(tick))
		var events := w.drain_events()
		digest.update(var_to_bytes(events))
		digest.update(var_to_bytes(w.player_state))
		if tick % 60 == 0:
			digest.update(_pool_bytes(w.pickups))
		for e: Dictionary in events:
			match String(e.type):
				"pickup_blocked":
					coverage.blocked += 1
				"pickup_collected":
					if String(e.get("collector", "")) == "pet":
						coverage.pet_pickups += 1
				"cast":
					var st := w.runner.stats_of(w, String(e.skill))
					var rule := "buff" if String(st.kind) == "buff" else String(st.cast_rule)
					rule = "nearest" if rule == "" else rule
					coverage.casts[rule] = int(coverage.casts.get(rule, 0)) + 1
		if w.runner.waiting_mp:
			coverage.mp_short_ticks += 1
		coverage.max_pool = maxi(coverage.max_pool, w.pickups.active_count())
		var mesos := 0
		for i in w.pickups.capacity():
			if w.pickups.active[i] != 0 and w.pickups.kind[i] == PickupSystem.MESO:
				mesos += 1
		coverage.max_meso = maxi(coverage.max_meso, mesos)
	coverage.kills = w.kills
	var totals := {"exp": w.pickups.collected_exp, "mesos": w.mesos, "pickup_mesos": w.pickups.collected_mesos,
		"equips_collected": w.equips_collected, "equips_dropped": w.equips_dropped,
		"inventory": w.equipment.inventory.size(), "hp_potions": int(w.potions.collected.hp),
		"mp_potions": int(w.potions.collected.mp), "kills": w.kills, "casts": w.runner.casts,
		"level": w.progression.level, "pool": w.pickups.active_count(), "time": w.time}
	digest.update(var_to_bytes(totals))
	return {"digest": digest.finish().hex_encode(), "totals": totals, "coverage": coverage}


static func _pool_bytes(p: PickupSystem) -> PackedByteArray:
	return var_to_bytes([p.active, p.x, p.y, p.vx, p.vy, p.state, p.to_pet, p.kind, p.full_noted, p.exp, p.meso,
		p.item_id, p.potion_count, p.age])
