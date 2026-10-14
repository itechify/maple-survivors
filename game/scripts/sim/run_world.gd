class_name RunWorld
extends RefCounted
## One survivor run (docs/ARCHITECTURE.md 4.3, 4.4, 4.4.1-4.4.3): built from a setup Dictionary, advanced by fixed
## 1/60 s step() calls, reporting what happened through `events`. Pure: no nodes, input, time, files or autoloads.
##
## Per PLAYING tick: same-map portal activation or player movement (PlayerMotion) -> view rect -> timers -> mobs
## (MobSwarm, target = the player) -> BossDirector (warnings/arrivals) -> SpawnDirector (normal spawns) -> hash ->
## SkillRunner (casts, instant hits, new shots) -> ProjectileSystem (hits; kills become mob_died + an EXP drop) ->
## PickupSystem (magnet, collect -> EXP) -> touch damage -> EXP/level-ups. Then: death -> DEAD (player_died); the
## every scheduled boss dead (or duration reached in a stage without bosses) -> CLEARED; else queued level-ups open.
##
## Pause protocol (4.4.2): step() does nothing unless `state` is PLAYING. For each queued level the job tree is checked
## first (CHOOSING_JOB + job_advance_pending when JobTree.should_offer), then CHOOSING_UPGRADE + choice_pending with
## cards drawn when the window opens. apply_job(id) / decline_job() continue to that level's upgrade choice;
## apply_choice(id) applies the card and moves to the next queued level or back to PLAYING. They return false (and
## change nothing) when called in the wrong state or with an id that is not on offer.
##
## Events: every emitted Dictionary has `type` plus exactly the fields of EVENT_FIELDS[type]. `player_hit.damage` is the
## whole hit (the number shown), `mp_absorbed` the part Magic Guard paid with MP; `miss` hits spend neither and
## cause no knockback or invincibility. `choice_pending` card `rank` is the
## rank the card gives when taken. Swarm/projectile/pickup visuals are read from state (4.4.3).
##
## Player stats live in `player_state` (hp, mp, max_hp, max_mp, exp, level, job_id, str, dex, int, luk, pdd, mdd,
## avoid, invincible_t, action,
## action_t, dead, plus exp_next = EXP needed for the next level); `action` is the body stance to draw ("dead", the
## cast stance while standing, else PlayerMotion.stance()), `action_t` seconds since it started.
##
## Separate seeded RNG streams (combat rolls, spawning, card draws, drop pops) keep e.g. card draws independent of
## damage rolls.

const PLAYING := 0
const CHOOSING_JOB := 1
const CHOOSING_UPGRADE := 2
const DEAD := 3
const CLEARED := 4
const STATE_NAMES := ["PLAYING", "CHOOSING_JOB", "CHOOSING_UPGRADE", "DEAD", "CLEARED"]

## Event type -> its fields (besides `type`), docs/ARCHITECTURE.md 4.4.3.
const EVENT_FIELDS := {
	"cast": ["skill", "skill_id", "level", "pos", "facing", "action", "effect"],
	"mp_short": ["skill", "skill_id", "required_mp", "mp"],
	"boss_skill": ["mob", "mob_id", "skill_id", "level", "pos", "facing", "action", "duration", "effect", "player_effect", "targets", "summon_effect"],
	"basic_attack": ["phase", "weapon_id", "action", "facing", "pos", "afterimage", "sound", "hit_after", "interval"],
	"mob_spawned": ["mob", "mob_id", "pos", "elite", "relocated_from"],
	"mob_hit": ["mob", "mob_id", "damage", "crit", "pos", "hit_visual", "skill"],
	"mob_died": ["mob", "mob_id", "pos", "exp", "elite"],
	"player_hit": ["damage", "mp_absorbed", "miss", "dir", "pos", "mob", "mob_id", "boss", "max_hp", "source_kind"],
	"player_jump": ["pos"],
	"portal_used": ["portal", "target", "pos"],
	"player_died": ["pos"],
	"pickup_spawned": ["pickup", "item_id", "pos", "kind", "potion_kind", "count"],
	"pickup_collected": ["pickup", "item_id", "exp", "pos", "kind", "potion_kind", "count"],
	"potion_used": ["kind", "item_id", "restored", "count"],
	"potion_tier_up": ["kind", "from_item_id", "item_id", "count"],
	"level_up": ["level"],
	"job_advance_pending": ["options"],
	"job_changed": ["job_id", "name"],
	"choice_pending": ["cards", "bonus"],
	"upgrade_applied": ["id", "rank"],
	"skill_learned": ["skill", "skill_id"],
	"burst": ["count"],
	"stage_cleared": ["time"],
	"boss_warning": ["boss_index", "mob_id", "time"],
	"boss_spawned": ["boss_index", "mob", "mob_id", "pos", "time"],
	"boss_died": ["boss_index", "mob", "mob_id", "pos", "time"],
	"boss_attack": ["boss_index", "mob", "mob_id", "attack", "phase", "pos", "facing", "area", "time", "impact_time", "effect", "sound"],
	"boss_teleported": ["boss_index", "mob", "mob_id", "pos", "time"],

}

## tier C defaults used when balance.json lacks a value.
const DEFAULT_BODY := Rect2(-14, -58, 28, 58)
const DEFAULT_CAST_HEIGHT := 30.0
## Shots leave this far in front of the cast origin, toward their target (the hand, not the face). tier C: ours.
const DEFAULT_CAST_FORWARD := 22.0
const DEFAULT_VIEW := Vector2(800, 600)
## tier B: pre-Big-Bang avoidability formula, Exoot 2009 (refs/research/v83-mechanics/notes.md).
const AVOID_DEX_FACTOR := 0.25
const AVOID_LUK_FACTOR := 0.5
## tier B: v83 MP recovery cadence/base; tier C: owner-selected always-on HP recovery.
const DEFAULT_REGEN := {"interval": 10.0, "hp": 10.0, "mp": 3.0, "improved_mp_divisor": 10.0}

var setup: Dictionary
var data: Dictionary
var balance: Dictionary
var stage: Dictionary
var stage_key := ""
var seed_value := 0
var duration := 900.0
## Combat rolls (damage, touch damage).
var rng: RandomNumberGenerator
var spawn_rng: RandomNumberGenerator
var card_rng: RandomNumberGenerator
var drop_rng: RandomNumberGenerator
var potion_rng: RandomNumberGenerator
var reward_rng: RandomNumberGenerator
## Boss bonus picks have priority and never consume progression.queue.
var pending_bonus_choices := 0
var choice_bonus := false

var physics: PhysicsConstants
var fhm: FootholdMap
var bounds := Rect2()
var ladders: LadderSet
var portals: PortalSet
var nav: NavGraph
var nav_jump: NavGraph
var player: PlayerMotion
var player_state := {}
var swarm: MobSwarm
var mob_kinds: Array = []
## Original mob id -> index in mob_kinds.
var kind_of_id := {}
## Per mob slot: 1 when the mob in it spawned as an elite.
var mob_elite := PackedByteArray()
## Per slot: schedule index for a boss, -1 for ordinary mobs.
var mob_boss := PackedInt32Array()
## Summoning encounter index, -1 for ordinary spawns; preserved through relocation and reset on new slot use.
var mob_summon_owner := PackedInt32Array()
var _live_mdd := PackedFloat32Array()
var mob_grid: SpatialHash
var projectiles: ProjectileSystem
var pickups: PickupSystem
var potions: PotionInventory
var book: SkillBook
var loadout: Loadout
var runner: SkillRunner
var progression: RunProgression
var jobs: JobTree
var upgrades: UpgradePool
var director: SpawnDirector
var mob_skills: MobSkillRunner
var bosses: BossDirector
var boss_attacks := BossAttacks.new()

var events: Array = []
var time := 0.0
var kills := 0
var damage_dealt := 0
var state := PLAYING
var view_size := DEFAULT_VIEW
## Player-centred logical view clamped to the bounds (spawn logic keeps mobs outside it).
var view := Rect2()
## WZ paths referenced by ProjectileSystem.visual (and hit visuals); append-only.
var visual_paths: Array = []
## Options / cards of the open window.
var pending_jobs: Array = []
var pending_cards: Array = []
## The next card draw's guarantee ({kind, job}; {power: true} = a power card; {} = none), from the job just taken.
var guarantee := {}
## Card draws in a row that offered no power card (UpgradePool pity).
var power_dry := 0
## Setup problems the sim worked around (e.g. a pool mob without a mob img).
var warnings := PackedStringArray()
## Largest feet-to-body-box-corner distance over all mob kinds (pads feet-point hash queries).
var body_pad := 64.0
var magnet_r := 90.0
## Additional HP/MP per regeneration pulse (interim Recovery card contributes HP here).
var hp_regen := 0.0
var mp_regen := 0.0
var player_pdd := 0.0
var player_mdd := 0.0
var player_avoid := 0.0
var body := DEFAULT_BODY
var cast_height := DEFAULT_CAST_HEIGHT
var cast_forward := DEFAULT_CAST_FORWARD
## Tests and benchmarks only: the player takes no touch damage.
var god := false

var _hp := 0.0
var _mp := 0.0
var _max_hp := 1
var _max_mp := 0
var _base_hp := 50.0
var _base_mp := 5.0
var _job_mp := 0.0
## tier C: defaults match the survivor starter selection; balance.player.stats overrides each attribute.
var _base_stats := {"str": 12, "dex": 5, "int": 4, "luk": 4}
var _attributes := {}
var _earned_ap := 0
var _dead := false
var _invincible_t := 0.0
var _regen_elapsed := 0.0
var _cast_action := ""
var _action_airborne := false
var basic: BasicAttack
var basic_rng: RandomNumberGenerator
var _cast_left := 0.0
var _action := ""
var _action_t := 0.0
var _job_checked := false
var _instant_dealt := 0
var _ctx := {}
var _visual_ids := {}
var _touch_buf := PackedInt32Array()


func _init(p_setup: Dictionary = {}) -> void:
	setup = p_setup
	data = setup.get("data", {})
	balance = data.get("balance", {})
	stage_key = String(setup.get("stage", ""))
	stage = data.get("stages", {}).get("stages", {}).get(stage_key, {})
	duration = float(stage.get("duration", 900.0))
	seed_value = int(setup.get("seed", 0))
	rng = _stream(1)
	basic_rng = _stream(5)
	spawn_rng = _stream(2)
	card_rng = _stream(3)
	drop_rng = _stream(4)
	potion_rng = _stream(5)
	reward_rng = _stream(6)
	view_size = setup.get("view_size", DEFAULT_VIEW)
	var map_img: Dictionary = setup.get("map_img", {})
	physics = PhysicsConstants.from_wz(setup.get("physics_img", {}))
	fhm = FootholdMap.from_wz(map_img)
	bounds = MapBounds.from_map(map_img, fhm)
	ladders = LadderSet.from_wz(map_img)
	portals = PortalSet.from_wz(map_img, int(stage.get("map_id", 0)), balance.get("portals", {}))
	var nav_opts := {"gravity": physics.gravity_acc, "fall_speed": physics.fall_speed, "jump_speed": physics.jump_speed}
	nav = NavGraph.build(fhm, nav_opts.merged({"can_jump": false}))
	nav_jump = NavGraph.build(fhm, nav_opts.merged({"can_jump": true}))
	_build_mob_kinds()
	body_pad = ProjectileSystem.max_body_extent(mob_kinds)
	swarm = MobSwarm.new(256, mob_kinds, balance.get("mob_motion", {}))
	swarm.fhm = fhm
	mob_elite.resize(swarm.capacity())
	mob_boss.resize(swarm.capacity())
	mob_boss.fill(-1)
	mob_grid = SpatialHash.new(64.0, bounds.grow(64.0))
	projectiles = ProjectileSystem.new(64, rng)
	projectiles.paths = visual_paths
	projectiles.bounds = bounds
	projectiles.magic_defense_k = float(balance.get("magic_defense_k", CombatMath.MAGIC_DEFENSE_K))
	var pk: Dictionary = balance.get("pickup", {}).duplicate()
	pk["collect_radius"] = float(balance.get("collect_radius", PickupSystem.TUNING_DEFAULTS.collect_radius))
	pk["gravity"] = physics.gravity_acc
	pk["fall_speed"] = physics.fall_speed
	pickups = PickupSystem.new(128, pk, drop_rng)
	potions = PotionInventory.new(balance.get("potions", {}), setup.get("item_info", {}))
	book = SkillBook.from_data(data.get("skills", {}), setup.get("skill_imgs", {}))
	loadout = Loadout.new(book)
	var crit: Dictionary = balance.get("crit", {})
	loadout.crit_chance = float(crit.get("chance", 0.0))
	loadout.crit_mult = float(crit.get("mult", 1.5))
	runner = SkillRunner.new()
	basic = BasicAttack.new(setup.get("body_img", {}), setup.get("afterimage_imgs", {}))
	progression = RunProgression.new(ExpCurve.from_data(balance.get("exp_curve", {})),
		int(balance.get("max_level", 200)))
	jobs = JobTree.from_data(data.get("jobs", {}), data.get("jobs_survivor", {}))
	upgrades = UpgradePool.from_data(data.get("upgrades", {}))
	director = SpawnDirector.create(stage, kind_of_id, balance.get("spawn", {}))
	bosses = BossDirector.new(stage.get("bosses", []), balance.get("bosses", {}))
	mob_skills = MobSkillRunner.new(setup, balance.get("mob_skills", {}))
	var kb: Dictionary = balance.get("knockback", {})
	player = PlayerMotion.new(physics, {
		"knockback_speed": float(kb.get("speed", 187.5)), "knockback_hop": float(kb.get("hop", 200.0)),
		"knockback_lock": float(kb.get("lock", 0.3)),
	})
	_ctx = {"fhm": fhm, "nav": nav, "nav_jump": nav_jump, "bounds": bounds, "physics": physics,
		"target": Vector2.ZERO, "target_fh": -1, "speed_mult": 1.0}
	_init_player()
	update_view()
	_write_player_state(0.0)


## Name of the current state ("PLAYING", ...).
func state_name() -> String:
	return STATE_NAMES[state]


## Boss stages finish after every scheduled boss dies; unscheduled stages retain the duration clear.
## Reward/choice tickets may defer this decision until their pending rewards have been answered.
func can_clear() -> bool:
	if bosses.has_bosses():
		return bosses.all_dead() and pending_bonus_choices == 0 and not choice_bonus and not progression.has_pending()
	return time >= duration - 1e-6


## Drinks one HP or MP potion instantly while playing, including on ropes; false when stock or spec is unavailable.
func drink_potion(kind: String) -> bool:
	if state != PLAYING or _dead:
		return false
	var sip := potions.consume(kind)
	if sip.is_empty():
		return false
	var before := int(player_state[kind])
	if kind == "hp":
		_hp = minf(_max_hp, _hp + int(sip.amount))
	else:
		_mp = minf(_max_mp, _mp + int(sip.amount))
	_write_player_state(0.0)
	emit("potion_used", {"kind": kind, "item_id": int(sip.item_id),
		"restored": int(player_state[kind]) - before, "count": int(sip.count)})
	return true


## Upgrades a potion kind's current item, preserving stock and exposing the new icon/restoration immediately.
func upgrade_potion(kind: String, item_id: int) -> bool:
	var from_id := int(potions.stock.get(kind, {}).get("item_id", 0))
	if not potions.upgrade(kind, item_id):
		return false
	_write_player_state(0.0)
	emit("potion_tier_up", {"kind": kind, "from_item_id": from_id, "item_id": item_id,
		"count": int(potions.stock[kind].count)})
	return true


## Drops a bundle of the current HP/MP tier, including boss rewards; potion slots never consume the EXP drop cap.
func spawn_potion(kind: String, pos: Vector2, count: int = 1) -> int:
	if not potions.stock.has(kind):
		return -1
	var id := int(potions.stock[kind].item_id)
	var slot := pickups.spawn_potion(pos, count, id, kind)
	if slot >= 0:
		emit("pickup_spawned", {"pickup": slot, "item_id": id, "pos": pos,
			"kind": "potion", "potion_kind": kind, "count": count})
	return slot



## Returns the pending events and clears the list (what the presentation does every frame).
func drain_events() -> Array:
	var out := events
	events = []
	return out


## Appends an event of `type` with `fields` (exactly EVENT_FIELDS[type]).
func emit(type: String, fields: Dictionary) -> void:
	var e := {"type": type}
	e.merge(fields)
	events.append(e)


## Advances the run by dt seconds with the player's input (no-op unless PLAYING).
func step(dt: float, input: MoveInput) -> void:
	if state != PLAYING:
		return
	time += dt
	player.speed_stat = roundi(player_speed_stat())
	if input.drink_hp:
		drink_potion("hp")
	if input.drink_mp:
		drink_potion("mp")
	var warp := portals.step(dt, player.pos, input.up)
	var flags := 0
	if warp.is_empty():
		flags = player.step(dt, input, fhm, ladders, bounds)
	else:
		player.place(warp.pos, fhm)
		emit("portal_used", warp)
	if flags & PlayerMotion.EV_JUMP:
		emit("player_jump", {"pos": player.pos})
	update_view()
	_tick_timers(dt)
	_ctx.target = player.pos
	_ctx.target_fh = player.fh
	_ctx.speed_mult = director.value_at("speed", time)
	_ctx["boss_actions"] = bosses.prepare_actions(self)
	swarm.step(dt, _ctx)
	bosses.step(self, dt)
	mob_skills.step(self)
	boss_attacks.step(self)
	director.step(dt, self)
	_sync_slots()
	mob_grid.rebuild(swarm.x, swarm.y, swarm.active, swarm.capacity())
	runner.step(dt, self)
	basic.step(dt, self)
	_live_mdd.resize(swarm.capacity())
	for slot in swarm.capacity():
		if swarm.active[slot] != 0:
			_live_mdd[slot] = mob_defense(slot,true)
	projectiles.step(dt, swarm, mob_grid, events, _live_mdd)
	for m in projectiles.kills:
		_on_kill(m)
	damage_dealt = projectiles.dealt + _instant_dealt
	var got := pickups.step(dt, player.pos, magnet_r, fhm, events)
	for kind: String in pickups.collected_potions:
		potions.add(kind, int(pickups.collected_potions[kind]))
	_touch()
	if got > 0 and not _dead:
		_gain_exp(got)
	_write_player_state(dt)
	if _dead:
		return
	if pending_bonus_choices > 0:
		_advance_queue()
		if state != PLAYING:
			return
	if can_clear():
		state = CLEARED
		emit("stage_cleared", {"time": time})
		return
	if progression.has_pending():
		_advance_queue()


## Takes job `job_id` from the open advancement window; false when not on offer or not available.
func apply_job(job_id: int) -> bool:
	if state != CHOOSING_JOB:
		return false
	var ok := false
	for o: Dictionary in pending_jobs:
		if int(o.job_id) == job_id and bool(o.available):
			ok = true
	if not ok:
		return false
	pending_jobs = []
	change_job(job_id)
	state = PLAYING
	_advance_queue()
	return true


## "Not now": keeps the current job and continues to the level's upgrade choice.
func decline_job() -> bool:
	if state != CHOOSING_JOB:
		return false
	pending_jobs = []
	state = PLAYING
	_advance_queue()
	return true


## Applies card `card_id` from the open choice window and continues with the next queued level (or play).
func apply_choice(card_id: String) -> bool:
	if state != CHOOSING_UPGRADE:
		return false
	var ok := false
	for c: Dictionary in pending_cards:
		if String(c.id) == card_id:
			ok = true
	if not ok:
		return false
	pending_cards = []
	upgrades.apply(card_id, self)
	if choice_bonus:
		pending_bonus_choices -= 1
		choice_bonus = false
	else:
		progression.pop_front()
		_job_checked = false
	state = PLAYING
	_advance_queue()
	_write_player_state(0.0)
	return true


## Changes the job (stats, grants: max_mp, skills learned at once, the next draw's guarantee) and emits job_changed
## (then skill_learned for each granted skill).
func change_job(job_id: int) -> void:
	progression.job_id = job_id
	var j := jobs.job(job_id)
	var grants: Dictionary = j.get("grants", {})
	_job_mp += float(grants.get("max_mp", 0.0))
	var g: Variant = grants.get("guarantee")
	if g is Dictionary and not g.is_empty():
		guarantee = g.duplicate()
	refresh_player_stats()
	emit("job_changed", {"job_id": job_id, "name": jobs.name_of(job_id)})
	for key: Variant in grants.get("skills", []):
		learn_skill(String(key))


## Learns a skill (emits skill_learned); false when unknown or owned.
func learn_skill(key: String) -> bool:
	if not loadout.add_skill(key):
		return false
	emit("skill_learned", {"skill": key, "skill_id": book.skill_id(key)})
	refresh_player_stats()
	return true


## Restores `fraction` of max HP (stat "hp") or MP (stat "mp").
func heal_fraction(stat: String, fraction: float) -> void:
	if stat == "hp":
		_hp = minf(_max_hp, _hp + fraction * _max_hp)
	elif stat == "mp":
		_mp = minf(_max_mp, _mp + fraction * _max_mp)
	_write_player_state(0.0)


## Pays an action's MP cost; unaffordable actions leave the pool unchanged.
func spend_mp(amount: int) -> bool:
	var cost := maxi(0, amount)
	if _mp < cost:
		return false
	_mp -= cost
	_write_player_state(0.0)
	return true


## Recomputes max HP/MP, speed, magnet, regen, defence and the caster inputs from the base stats, job and upgrade
## modifiers. Explicit max-pool upgrades grant the difference; level growth passes grant_growth=false.
func refresh_player_stats(grant_growth: bool = true) -> void:
	var pb: Dictionary = balance.get("player", {})
	var primary := String(_job_value(pb.get("ap_stat", {"0": "str", "200": "int"}), "str"))
	for stat: String in _base_stats:
		_attributes[stat] = roundi(loadout.player_stat(stat, float(_base_stats[stat])
			+ (_earned_ap if stat == primary else 0)))
	var old_hp := _max_hp
	var old_mp := _max_mp
	_max_hp = maxi(1, roundi(loadout.player_stat("max_hp", _base_hp)))
	_max_mp = maxi(0, roundi(loadout.player_stat("max_mp", _base_mp + _job_mp)))
	if grant_growth and _max_hp > old_hp:
		_hp += _max_hp - old_hp
	if grant_growth and _max_mp > old_mp:
		_mp += _max_mp - old_mp
	_hp = minf(_hp, _max_hp)
	_mp = minf(_mp, _max_mp)
	player.speed_stat = roundi(player_speed_stat())
	magnet_r = loadout.player_stat("magnet", float(balance.get("magnet_radius", 90.0)))
	hp_regen = loadout.player_stat("hp_regen", float(balance.get("hp_regen", 0.0)))
	mp_regen = loadout.player_stat("mp_regen", float(balance.get("mp_regen", 0.0)))
	player_pdd = loadout.player_stat("pdd", _equipment_total("incPDD")) + loadout.passive_total("pdd")
	player_mdd = loadout.player_stat("mdd", _equipment_total("incMDD")) + loadout.passive_total("mdd")
	player_avoid = loadout.player_stat("avoid", float(_attributes.dex) * AVOID_DEX_FACTOR
		+ float(_attributes.luk) * AVOID_LUK_FACTOR + _equipment_total("incEVA"))
	loadout.set_caster(float(_attributes.int), _equipment_total("incMAD"), progression.level)
	_write_player_state(0.0)


## Upgraded movement speed composed with the current canonical-area slow.
func player_speed_stat() -> float:
	return loadout.player_stat("speed", 100.0) * mob_skills.speed_multiplier(time)


## Index of a WZ path in visual_paths (registered on first use); -1 for "".
func visual_index(path: String) -> int:
	if path == "":
		return -1
	if _visual_ids.has(path):
		return _visual_ids[path]
	var i := visual_paths.size()
	visual_paths.append(path)
	_visual_ids[path] = i
	return i


## Where targeting measures from: the player's body (feet - cast_height). Shots start shot_origin().
func cast_origin() -> Vector2:
	return player.pos - Vector2(0.0, cast_height)


## Where a shot flying toward `aim` starts: cast_forward px in front of the cast origin on the target's side (the
## throwing hand, so the shell does not cover the face), level with it.
func shot_origin(aim: Vector2) -> Vector2:
	var o := cast_origin()
	var side := signf(aim.x - o.x)
	if side == 0.0:
		side = float(player.facing)
	return o + Vector2(side * cast_forward, 0.0)


## Centre of mob m's body box (where shots aim).
func mob_center(m: int) -> Vector2:
	var mk: MobKind = mob_kinds[swarm.kind[m]]
	return mk.hitbox_at(swarm.x[m], swarm.y[m], swarm.facing[m]).get_center()


## Platform the player stands on or is above (-1 when none).
func player_platform() -> int:
	if player.fh >= 0:
		return fhm.platform_of(player.fh)
	return fhm.platform_of(fhm.find_below(player.pos.x, player.pos.y))


## The floor right below a player standing on a low step, which walkers also count as the player's
## (MobSwarm.low_platform, reach_y); -1 when there is none.
func player_low_platform() -> int:
	var tp := player_platform()
	if tp < 0:
		return -1
	return MobSwarm.low_platform(fhm, player.pos, tp, float(swarm.tuning.reach_y))


## Turns a standing player toward x (casting at a target); a walking player keeps facing its way.
func face_toward(tx: float) -> void:
	if player.state == PlayerMotion.ST_STAND and absf(tx - player.pos.x) > 0.5:
		player.facing = 1 if tx > player.pos.x else -1


## Starts a stance for its frame time; airborne opts basic swings into the same visual without changing motion.
func start_action(action: String, seconds: float, airborne: bool = false) -> void:
	if action == "" or seconds <= 0.0:
		return
	_cast_action = action
	_cast_left = seconds
	_action_airborne = airborne


## Canonical starter weapon selected by the current job's survivor-data rule.
func weapon_id() -> int:
	return int(_job_value(balance.get("player", {}).get("weapon_by_job", {}), 0))


## The current weapon's canonical info node (empty when absent).
func weapon_info() -> Dictionary:
	var infos: Dictionary = setup.get("equipment_info", {})
	return infos.get(weapon_id(), infos.get(str(weapon_id()), {}))


## Live defense at a mob slot; later timed boss buffs can override this shared hit seam.
func mob_defense(m: int, magic: bool) -> float:
	var kind: MobKind = mob_kinds[swarm.kind[m]]
	return float(kind.mdd if magic else kind.pdd) + mob_skills.defense_bonus(m,magic,time)


## Whether a physical hit may damage this slot; the weapon-immunity ticket supplies its timed state.
func physical_hit_allowed(_m: int) -> bool:
	return true


## Spawns a mob of kind index k on foothold fh at pos with max_hp x hp_mult; emits mob_spawned. Returns the slot.
func spawn_mob(k: int, pos: Vector2, fh: int, hp_mult: float, elite: bool) -> int:
	if k < 0 or k >= mob_kinds.size():
		return -1
	var mk: MobKind = mob_kinds[k]
	var i := swarm.spawn(k, pos.x, pos.y, fh, maxi(1, roundi(mk.max_hp * hp_mult)))
	_sync_slots()
	mob_elite[i] = 1 if elite else 0
	mob_boss[i] = -1
	mob_summon_owner[i] = -1
	mob_skills.reset_slot(i)
	emit("mob_spawned", {"mob": i, "mob_id": mk.id, "pos": Vector2(swarm.x[i], swarm.y[i]), "elite": elite,
		"relocated_from": -1})
	return i


## Moves live mob i to pos on foothold fh like a new spawn (SpawnDirector relocation): the slot is freed and the same
## kind spawned there with the mob's HP and max HP (and elite flag), fading in; emits mob_spawned with relocated_from =
## i (new spawns have -1). Returns the new slot (-1 when i is not a live mob).
func relocate_mob(i: int, pos: Vector2, fh: int) -> int:
	if i < 0 or i >= swarm.capacity() or swarm.active[i] == 0:
		return -1
	var k := swarm.kind[i]
	var hp := swarm.hp[i]
	var mhp := swarm.max_hp[i]
	var elite := mob_elite[i] != 0
	var boss_index := mob_boss[i]
	var summon_owner := mob_summon_owner[i]
	swarm.despawn(i)
	var j := swarm.spawn(k, pos.x, pos.y, fh, mhp)
	swarm.hp[j] = hp
	_sync_slots()
	mob_elite[j] = 1 if elite else 0
	mob_boss[j] = boss_index
	mob_summon_owner[j] = summon_owner
	mob_skills.move_slot(i,j)
	if boss_index >= 0:
		bosses.records[boss_index].slot = j
	emit("mob_spawned", {"mob": j, "mob_id": mob_kinds[k].id, "pos": Vector2(swarm.x[j], swarm.y[j]), "elite": elite,
		"relocated_from": i})
	return j


## One instant damage line of skill stats `st` on mob m (Magic Claw); hv = hit visual index. Kills drop EXP.
func hit_mob(m: int, st: Dictionary, hv: int) -> void:
	if swarm.active[m] == 0:
		return
	if not bool(st.magic) and not physical_hit_allowed(m):
		return
	var mk: MobKind = mob_kinds[swarm.kind[m]]
	var roll := ProjectileSystem.roll_damage(float(st.damage_min), float(st.damage_max), bool(st.magic),
		mob_defense(m, true), projectiles.magic_defense_k, float(st.crit), float(st.crit_mult), rng)
	var dir := 1 if swarm.x[m] >= player.pos.x else -1
	emit("mob_hit", {
		"mob": m, "mob_id": mk.id, "damage": roll.x, "crit": roll.y != 0,
		"pos": Vector2(swarm.x[m], swarm.y[m] + mk.hitbox.position.y),
		"hit_visual": String(visual_paths[hv]) if hv >= 0 else "", "skill": String(st.skill),
	})
	_instant_dealt += roll.x
	damage_dealt = projectiles.dealt + _instant_dealt
	if swarm.apply_hit(m, roll.x, dir):
		_on_kill(m)


func _stream(n: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value * 1000003 + n * 7919
	return r


func _build_mob_kinds() -> void:
	var imgs: Dictionary = setup.get("mob_imgs", {})
	var overrides: Dictionary = data.get("mobs", {}).get("mobs", {})
	var speed_mult := float(balance.get("mob_speed_factor", MobKind.SPEED_SCALE)) / MobKind.SPEED_SCALE
	var ids := PackedInt32Array()
	for kf: Dictionary in stage.get("keyframes", []):
		for key: Variant in kf.get("pool", {}):
			var id := int(key)
			if not (id in ids):
				ids.append(id)
	for boss: Dictionary in stage.get("bosses", []):
		var extra: Array = [int(boss.mob_id)] + boss.get("summon_ids", []) + boss.get("revive_ids", [])
		for id: Variant in extra:
			if not (int(id) in ids):
				ids.append(int(id))
	ids.sort()
	for id in ids:
		var img: Variant = imgs.get(id, imgs.get(str(id)))
		if not (img is Dictionary) or img.is_empty():
			warnings.append("no mob img for %d: dropped from the pools" % id)
			continue
		var ov: Dictionary = overrides.get(str(id), {}).duplicate()
		ov["speed_mult"] = float(ov.get("speed_mult", 1.0)) * speed_mult
		kind_of_id[id] = mob_kinds.size()
		mob_kinds.append(MobKind.from_wz(img, id, ov))


func _init_player() -> void:
	var pb: Dictionary = balance.get("player", {})
	_base_hp = float(pb.get("hp", 50.0))
	_base_mp = float(pb.get("mp", 5.0))
	var starting: Dictionary = pb.get("stats", {})
	for stat: String in _base_stats:
		_base_stats[stat] = int(starting.get(stat, _base_stats[stat]))
	var b: Variant = pb.get("body")
	if b is Array and b.size() == 4:
		body = Rect2(float(b[0]), float(b[1]), float(b[2]), float(b[3]))
	cast_height = float(pb.get("cast_height", DEFAULT_CAST_HEIGHT))
	cast_forward = float(pb.get("cast_forward", DEFAULT_CAST_FORWARD))
	player.place(_start_point(), fhm)
	refresh_player_stats()
	_hp = _max_hp
	_mp = _max_mp
	for key: Variant in pb.get("skills", []):
		learn_skill(String(key))
	_action = player.stance()


## A random spawn portal (pn "sp") dropped onto the floor below it; else the middle of the widest platform.
func _start_point() -> Vector2:
	var pts: Array = []
	var portals: Variant = setup.get("map_img", {}).get("portal", {})
	if portals is Dictionary:
		for k: String in portals:
			var p: Variant = portals[k]
			if p is Dictionary and String(p.get("pn", "")) == "sp":
				pts.append(Vector2(float(p.get("x", 0)), float(p.get("y", 0))))
	while not pts.is_empty():
		var i := spawn_rng.randi_range(0, pts.size() - 1)
		var p: Vector2 = pts[i]
		var f := fhm.find_below(p.x, p.y)
		if f >= 0:
			return Vector2(p.x, fhm.y_at(f, p.x))
		pts.remove_at(i)
	var best := -1
	for p in fhm.platform_count():
		var s := fhm.platform_span(p)
		if best < 0 or s.y - s.x > fhm.platform_span(best).y - fhm.platform_span(best).x:
			best = p
	if best < 0:
		return bounds.get_center()
	var mid := fhm.platform_span(best)
	var cx := (mid.x + mid.y) * 0.5
	var f := fhm.platform_fh_at(best, cx)
	return Vector2(cx, fhm.y_at(f, cx)) if f >= 0 else bounds.get_center()


## Recentres the view rect on the player, clamped to the bounds (step() does this every tick).
func update_view() -> void:
	var r := Rect2(player.pos - view_size * 0.5, view_size)
	if bounds.size.x > view_size.x:
		r.position.x = clampf(r.position.x, bounds.position.x, bounds.end.x - view_size.x)
	else:
		r.position.x = bounds.get_center().x - view_size.x * 0.5
	if bounds.size.y > view_size.y:
		r.position.y = clampf(r.position.y, bounds.position.y, bounds.end.y - view_size.y)
	else:
		r.position.y = bounds.get_center().y - view_size.y * 0.5
	view = r


func _tick_timers(dt: float) -> void:
	_invincible_t = maxf(0.0, _invincible_t - dt)
	_cast_left = maxf(0.0, _cast_left - dt)
	if not _dead:
		var regen: Dictionary = balance.get("regen", DEFAULT_REGEN)
		var interval := maxf(0.01, float(regen.get("interval", DEFAULT_REGEN.interval)))
		_regen_elapsed += dt
		while _regen_elapsed >= interval - 1e-9:
			_regen_elapsed = maxf(0.0, _regen_elapsed - interval)
			_hp = minf(_max_hp, _hp + float(regen.get("hp", DEFAULT_REGEN.hp)) + hp_regen)
			# tier B: pre-Big-Bang Improved MP Recovery rule, rounded to whole MP.
			var bonus := floorf(float(progression.level * loadout.level("improved_mp_recovery"))
				/ maxf(1.0, float(regen.get("improved_mp_divisor", DEFAULT_REGEN.improved_mp_divisor))))
			_mp = minf(_max_mp, _mp + float(regen.get("mp", DEFAULT_REGEN.mp)) + mp_regen + bonus)


func _sync_slots() -> void:
	if mob_skills != null:
		mob_skills.resize(swarm.capacity())
	if mob_summon_owner.size() < swarm.capacity():
		var old := mob_summon_owner.size()
		mob_summon_owner.resize(swarm.capacity())
		for slot in range(old,mob_summon_owner.size()):
			mob_summon_owner[slot] = -1
	if mob_elite.size() < swarm.capacity():
		mob_elite.resize(swarm.capacity())
	if mob_boss.size() < swarm.capacity():
		var old_size := mob_boss.size()
		mob_boss.resize(swarm.capacity())
		for index in range(old_size, mob_boss.size()):
			mob_boss[index] = -1


func _on_kill(m: int) -> void:
	kills += 1
	var mk: MobKind = mob_kinds[swarm.kind[m]]
	var elite := mob_elite[m] != 0
	var mult := float(balance.get("exp_mult", 1.0)) * float(stage.get("exp_mult", 1.0))
	if elite:
		mult *= float(stage.get("elites", {}).get("exp_mult", 5.0))
	var e := roundi(mk.exp * mult)
	var pos := Vector2(swarm.x[m], swarm.y[m])
	var boss_rewards := {}
	if mob_boss[m] >= 0:
		boss_rewards = bosses.reward_config(mob_boss[m])
		e = maxi(0, roundi(mk.exp * float(boss_rewards.get("exp_mult", 1.0))))
		bosses.mark_dead(mob_boss[m], m, pos, self)
	emit("mob_died", {"mob": m, "mob_id": mk.id, "pos": pos, "exp": e, "elite": elite})
	if mob_boss[m] >= 0:
		_drop_boss_rewards(pos, e, mk.exp_item, boss_rewards)
		return
	if e > 0:
		var p := pickups.spawn(pos, e, mk.exp_item, player.pos)
		emit("pickup_spawned", {"pickup": p, "item_id": mk.exp_item, "pos": pos,
			"kind": "exp", "potion_kind": "", "count": 0})
	var chances: Dictionary = balance.get("potions", {}).get("drops", {}).get("elite" if elite else "normal", {})
	for kind: String in ["hp", "mp"]:
		var chance := float(chances.get(kind, 0.0))
		if chance > 0.0 and potion_rng.randf() < chance:
			spawn_potion(kind, pos)


func _drop_boss_rewards(pos: Vector2, total: int, item_id: int, config: Dictionary) -> void:
	var count := mini(total, maxi(1, int(config.get("exp_drops", 1))))
	var spread := float(config.get("spread", 0.0))
	for i in count:
		var amount := total / count + (1 if i < total % count else 0)
		var point := pos + Vector2(reward_rng.randf_range(-spread, spread), 0)
		var slot := pickups.spawn(point, amount, item_id, player.pos)
		emit("pickup_spawned", {"pickup": slot, "item_id": item_id, "pos": point,
			"kind": "exp", "potion_kind": "", "count": 0})
	var bundles: Dictionary = config.get("potions", {})
	var potion_spread := float(config.get("potion_spread", 0.0))
	spawn_potion("hp", pos - Vector2(potion_spread, 0), int(bundles.get("hp", 0)))
	spawn_potion("mp", pos + Vector2(potion_spread, 0), int(bundles.get("mp", 0)))
	pending_bonus_choices += maxi(0, int(config.get("bonus_choices", 1)))


func _touch() -> void:
	if _dead or god or _invincible_t > 0.0:
		return
	var box := Rect2(player.pos + body.position, body.size)
	var c := box.get_center()
	var n := mob_grid.query_radius(c, body.size.length() * 0.5 + body_pad, _touch_buf)
	for j in n:
		var m := _touch_buf[j]
		if swarm.active[m] == 0 or swarm.alpha[m] < 1.0:
			continue
		var mk: MobKind = mob_kinds[swarm.kind[m]]
		if not mk.body_attack:
			continue
		if not mk.hitbox_at(swarm.x[m], swarm.y[m], swarm.facing[m]).intersects(box):
			continue
		_player_hit(m, mk)
		return


func _player_hit(m: int, mk: MobKind) -> void:
	var boss_index := mob_boss[m]
	var source := {"mob": m, "mob_id": mk.id, "accuracy": mk.acc,
		"elite": mob_elite[m] != 0, "boss": boss_index >= 0, "source_kind": "touch"}
	if boss_index >= 0:
		source["dmg_mult"] = bosses.damage_multiplier(boss_index)
	take_hit(float(mk.pad), false, "", Vector2(swarm.x[m], swarm.y[m]), source)


## Defense inputs for a monster hit; overridable by subsequent equipment and buff rules.
func hit_defense() -> Dictionary:
	return {"pdd": player_pdd, "mdd": player_mdd, "resistance": {}}


## Magic Guard's current percentage; overridable by the timed-buff rules.
func magic_guard_ratio() -> float:
	return loadout.passive_total("mp_guard")


## Only explicit source scaling: elites use stage.elites.damage_mult; boss sources may pass dmg_mult.
func hit_source_multiplier(source: Dictionary) -> float:
	var mult := float(source.get("dmg_mult", 1.0))
	if bool(source.get("elite", false)):
		mult *= float(stage.get("elites", {}).get("damage_mult", 1.0))
	return mult


## Applies one monster hit through avoid, defense, Magic Guard and hit reaction; returns whole damage (0 on miss).
## Source fields: accuracy (canonical acc), elite, dmg_mult, mob, mob_id, boss. Events snapshot max_hp at hit time.
func take_hit(attack: float, magic: bool, element: String, source_pos: Vector2, source: Dictionary = {}) -> int:
	if _dead or god or _invincible_t > 0.0:
		return 0
	var dir := 1 if player.pos.x >= source_pos.x else -1
	if CombatMath.roll_miss(player_avoid, float(source.get("accuracy", 0.0)), rng):
		_emit_player_hit(0, 0, true, dir, source)
		return 0
	var dmg := CombatMath.monster_hit(attack, magic, element, hit_defense(), rng,
		hit_source_multiplier(source))
	var split := CombatMath.magic_guard_split(dmg, magic_guard_ratio(), floori(_mp))
	_hp -= split.x
	_mp -= split.y
	_emit_player_hit(dmg, split.y, false, dir, source)
	_invincible_t = float(balance.get("invincible_time", 1.5))
	if _hp <= 0.0:
		_hp = 0.0
		_dead = true
		state = DEAD
		emit("player_died", {"pos": player.pos})
	else:
		player.knockback(dir)
	_write_player_state(0.0)
	return dmg


func _emit_player_hit(damage: int, mp_absorbed: int, miss: bool, dir: int, source: Dictionary) -> void:
	emit("player_hit", {"damage": damage, "mp_absorbed": mp_absorbed, "miss": miss, "dir": dir,
		"pos": player.pos, "mob": int(source.get("mob", -1)), "mob_id": int(source.get("mob_id", 0)),
		"boss": bool(source.get("boss", false)), "max_hp": _max_hp, "source_kind": String(source.get("source_kind", "other"))})


## Whether auto-actions may cast now: hanging on a rope/ladder blocks new casts, not their cooldowns or effects.
func can_cast() -> bool:
	return state == PLAYING and not _dead and player.state != PlayerMotion.ST_LADDER


func _gain_exp(n: int) -> void:
	var before := progression.level
	var gained := progression.add_exp(n)
	for k in gained:
		_on_level_up(before + k + 1)


func _on_level_up(level: int) -> void:
	var g: Dictionary = _job_value(balance.get("growth", {}), {})
	_base_hp += float(g.get("hp", 0.0))
	_base_mp += float(g.get("mp", 0.0))
	var divisor := float(g.get("int_mp_divisor", 0.0))
	if divisor > 0.0:
		_base_mp += floorf(float(_attributes.int) / divisor)
	_earned_ap += int(balance.get("player", {}).get("ap_per_level", 5))
	_level_ranks(level)
	refresh_player_stats(false)
	var refill := float(balance.get("level_up_refill", 0.0))
	_hp = minf(_max_hp, _hp + refill * _max_hp)
	_mp = minf(_max_mp, _mp + refill * _max_mp)
	emit("level_up", {"level": level})


## Skills with `level_ranks` ({character level: rank}, skills.json) reach at least that rank at that level (like the
## SP a v83 Beginner spends on Three Snails); cards may get there sooner.
func _level_ranks(level: int) -> void:
	for key: String in loadout.order:
		var lr: Variant = book.def(key).get("level_ranks")
		if not (lr is Dictionary):
			continue
		var want := 0
		for k: Variant in lr:
			if int(k) <= level:
				want = maxi(want, int(lr[k]))
		if want > loadout.rank(key):
			loadout.set_rank(key, want)


## The entry of a per-job table (keys = job ids as strings) for the current job, else its nearest ancestor's.
func _job_value(table: Variant, fallback: Variant) -> Variant:
	if not (table is Dictionary):
		return fallback
	for j in jobs.lineage(progression.job_id):
		if table.has(str(j)):
			return table[str(j)]
	return table.get("0", fallback)


func _equipment_total(field: String) -> float:
	var infos: Dictionary = setup.get("equipment_info", {})
	var pb: Dictionary = balance.get("player", {})
	var ids: Array = pb.get("equipment", []).duplicate()
	var weapon := int(_job_value(pb.get("weapon_by_job", {}), 0))
	if weapon > 0 and not (weapon in ids):
		ids.append(weapon)
	var total := 0.0
	for id: Variant in ids:
		var info: Dictionary = infos.get(int(id), infos.get(str(int(id)), {}))
		total += float(info.get(field, 0.0))
	return total


func _advance_queue() -> void:
	while pending_bonus_choices > 0:
		var bonus_cards := upgrades.roll_choices(self, card_rng, 3)
		if bonus_cards.is_empty():
			pending_bonus_choices -= 1
			continue
		choice_bonus = true
		pending_cards = bonus_cards
		state = CHOOSING_UPGRADE
		emit("choice_pending", {"cards": bonus_cards.duplicate(true), "bonus": true})
		return
	while progression.has_pending():
		var lvl := progression.front()
		if not _job_checked:
			_job_checked = true
			if jobs.should_offer(progression.job_id, lvl):
				pending_jobs = jobs.advancements(progression.job_id, lvl)
				state = CHOOSING_JOB
				emit("job_advance_pending", {"options": pending_jobs.duplicate(true)})
				return
		var cards := upgrades.roll_choices(self, card_rng, 3)
		if cards.is_empty():
			progression.pop_front()
			_job_checked = false
			continue
		pending_cards = cards
		state = CHOOSING_UPGRADE
		emit("choice_pending", {"cards": cards.duplicate(true), "bonus": false})
		return
	state = PLAYING


func _write_player_state(dt: float) -> void:
	var a := "dead" if _dead else player.stance()
	if not _dead and _cast_left > 0.0 and (player.state == PlayerMotion.ST_STAND
			or (_action_airborne and player.state == PlayerMotion.ST_AIR)):
		a = _cast_action
	if a != _action:
		_action = a
		_action_t = 0.0
	else:
		_action_t += dt
	player_state["hp"] = ceili(_hp) if _hp > 0.0 else 0
	player_state["mp"] = floori(_mp)
	player_state["mp_short"] = runner.waiting_mp
	player_state["max_hp"] = _max_hp
	player_state["max_mp"] = _max_mp
	player_state["exp"] = progression.exp
	player_state["exp_next"] = progression.exp_to_next()
	player_state["slow"] = mob_skills.slow_state(time)
	player_state["level"] = progression.level
	player_state["job_id"] = progression.job_id
	for stat: String in _attributes:
		player_state[stat] = _attributes[stat]
	player_state["pdd"] = player_pdd
	player_state["mdd"] = player_mdd
	player_state["avoid"] = player_avoid
	player_state["invincible_t"] = _invincible_t
	player_state["action"] = _action
	player_state["action_t"] = _action_t
	player_state["dead"] = _dead
	player_state["potions"] = potions.snapshot()
