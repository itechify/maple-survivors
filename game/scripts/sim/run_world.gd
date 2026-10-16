class_name RunWorld
extends RefCounted
## One survivor run (docs/ARCHITECTURE.md 4.3, 4.4, 4.4.1-4.4.3): built from a setup Dictionary, advanced by fixed
## 1/60 s step() calls, reporting what happened through `events`. Pure: no nodes, input, time, files or autoloads.
##
## Per PLAYING tick: drinks -> portals/movement -> view/timers (regen/buffs) -> swarm -> boss lifecycle,
## skills/attacks/monster balls -> ordinary spawns/hash -> SkillRunner/BasicAttack -> player shots/kills/rewards ->
## pickups -> touch -> collected EXP/level-ups -> state snapshot. Death takes priority; bonus choices precede clear,
## and can_clear requires all bosses dead and all bonus/level choices resolved. Normal queued levels open last.
##
## Pause protocol (4.4.2): step() does nothing unless `state` is PLAYING. For each queued level the job tree is checked
## first (CHOOSING_JOB + job_advance_pending when JobTree.should_offer), then CHOOSING_UPGRADE + choice_pending with
## cards drawn when the window opens. apply_job(id) adds an advancement draw; decline_job() skips it;
## apply_choice(id) applies the card and moves to the next queued level or back to PLAYING. They return false (and
## change nothing) when called in the wrong state or with an id that is not on offer.
##
## Events: every emitted Dictionary has `type` plus exactly the fields of EVENT_FIELDS[type]. `player_hit.damage` is the
## whole hit (the number shown), `mp_absorbed` the part Magic Guard paid with MP; `miss` hits spend neither and
## cause no knockback or invincibility. `choice_pending` card `rank` is the
## rank the card gives when taken. Swarm/projectile/pickup visuals are read from state (4.4.3).
##
## Player stats live in `player_state` (hp, mp, max_hp, max_mp, exp, level, job_id, str, dex, int, luk, pdd, mdd,
## avoid, fortune (survivor card-tier stat, separate from LUK), invincible_t, action,
## action_t, dead, plus exp_next = EXP needed for the next level); `action` is the body stance to draw ("dead", the
## cast stance while standing, else PlayerMotion.stance()), `action_t` seconds since it started.
##
## Separate seeded RNG streams keep e.g. card draws independent of damage rolls: 1 combat rolls, 2 spawning, 3 card
## draws, 4 drop pops, 5 basic-attack stances, 6 boss reward scatter, 7 potion drop rolls, 8 bot branch choices.
## Each stream has exactly one owner.

const PLAYING := 0
const CHOOSING_JOB := 1
const CHOOSING_UPGRADE := 2
const DEAD := 3
const CLEARED := 4
const STATE_NAMES := ["PLAYING", "CHOOSING_JOB", "CHOOSING_UPGRADE", "DEAD", "CLEARED"]

## Event type -> its fields (besides `type`), docs/ARCHITECTURE.md 4.4.3.
const EVENT_FIELDS := {
	"teleport": ["skill", "skill_id", "level", "phase", "pos", "facing", "effect"],
	"cast": ["skill", "skill_id", "level", "pos", "facing", "action", "effect"],
	"mp_short": ["skill", "skill_id", "required_mp", "mp"],
	"player_restored": ["stat", "amount", "skill", "pos"],
	"mp_eater_absorbed": ["mob", "amount", "skill", "pos"],
	"boss_skill": ["mob", "mob_id", "skill_id", "level", "pos", "facing", "action", "duration", "effect", "player_effect", "targets", "summon_effect", "recipient_effect"],
	"buff_cast": ["skill", "skill_id", "level", "duration"],
	"buff_expired": ["skill", "skill_id"],
	"buff_pulse": ["skill", "skill_id", "amount"],
	"basic_attack": ["phase", "weapon_id", "action", "facing", "pos", "afterimage", "sound", "hit_after", "interval"],
	"mob_spawned": ["mob", "mob_id", "pos", "elite", "relocated_from"],
	"mob_hit": ["mob", "mob_id", "damage", "crit", "pos", "hit_visual", "skill"],
	"mob_status_applied": ["mob", "mob_id", "status", "duration"],
	"mob_status_expired": ["mob", "mob_id", "status"],
	"mob_died": ["mob", "mob_id", "pos", "exp", "elite"],
	"mob_revives_spawned": ["boss_index", "mob", "mob_id", "pos", "revives", "time"],
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
	"choice_pending": ["cards", "bonus", "advancement"],
	"upgrade_applied": ["id", "rank", "tier", "magnitude"],
	"skill_learned": ["skill", "skill_id"],
	"burst": ["count"],
	"stage_cleared": ["time"],
	"boss_warning": ["boss_index", "mob_id", "time"],
	"boss_spawned": ["boss_index", "mob", "mob_id", "pos", "time"],
	"boss_died": ["boss_index", "mob", "mob_id", "pos", "time"],
	"boss_attack": ["boss_index", "mob", "mob_id", "attack", "phase", "pos", "facing", "area", "time", "impact_time", "effect", "sound"],
	"mob_projectile_spawned": ["proj", "mob", "mob_id", "pos", "velocity", "range", "speed", "ball", "hit", "time"],
	"mob_projectile_hit": ["proj", "mob", "mob_id", "pos", "hit", "facing", "time"],
	"mob_healed": ["mob", "mob_id", "skill_id", "level", "amount", "pos", "time"],
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
## balance.regen fallback (PlayerUpkeep owns the pulse clock).
const DEFAULT_REGEN := PlayerUpkeep.DEFAULT_REGEN
## tier C: the survivor starter attributes; balance.player.stats overrides each one.
const DEFAULT_STATS := {"str": 12, "dex": 5, "int": 4, "luk": 4}
## balance.level_up_refill fallback: fraction of the new maximum restored per level-up. MP tier B (v83 servers refill
## it: Cosmic Character.levelUp calls changeHpMp(maxhp, maxmp)); HP tier C (owner choice: no heal on level-up).
const DEFAULT_LEVEL_UP_REFILL := {"hp": 0.0, "mp": 1.0}
## tier C: px between MobSkill 200 summons and revive offspring when balance.mob_skills has no summon_spacing.
const DEFAULT_SUMMON_SPACING := 24.0

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
## Independent seeded branch choices do not perturb card, combat or careless-card streams.
var job_rng: RandomNumberGenerator
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
var _live_physical_allowed := PackedByteArray()
var mob_grid: SpatialHash
var projectiles: ProjectileSystem
var pickups: PickupSystem
var potions: PotionInventory
var buffs := PlayerBuffs.new()
## Buff, invincibility, cast-hold and regeneration timers.
var upkeep: PlayerUpkeep
var book: SkillBook
var loadout: Loadout
var runner: SkillRunner
var _teleport_left := 0.0
var _teleport_total := 0.0
var progression: RunProgression
var jobs: JobTree
var upgrades: UpgradePool
var director: SpawnDirector
var mob_skills: MobSkillRunner
var bosses: BossDirector
var boss_attacks := BossAttacks.new()
var mob_projectiles := MobProjectileSystem.new()

var events: Array = []
var time := 0.0
var kills := 0
## Total damage the player dealt: shots, instant skill hits and nonlethal poison (read-only).
var damage_dealt: int:
	get:
		return projectiles.dealt + _instant_dealt + swarm.poison_dealt
var state := PLAYING
var view_size := DEFAULT_VIEW
## Player-centred logical view clamped to the bounds (spawn logic keeps mobs outside it).
var view := Rect2()
## WZ paths referenced by ProjectileSystem.visual (and hit visuals); append-only.
var visual_paths: Array = []
## Options / cards of the open window.
var pending_jobs: Array = []
var pending_cards: Array = []
## True while the extra new-job skill draw is open; it does not consume a queued level or boss reward.
var choice_advancement := false
## Card draws in a row that offered no power card (UpgradePool pity).
var power_dry := 0
## Offered cards / selected cards per displayed tier, counting cards once rather than the steps they grant.
var card_tiers_offered := UpgradePool.empty_tier_counts()
var card_tiers_picked := UpgradePool.empty_tier_counts()
## Setup problems the sim worked around (e.g. a pool mob without a mob img).
var warnings := PackedStringArray()
## Largest feet-to-body-box-corner distance over all mob kinds (pads feet-point hash queries).
var body_pad := 64.0
var magnet_r := 90.0
## Additional HP/MP per regeneration pulse; Recovery's separate PlayerBuffs timeline heals independently.
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
var _hit_listeners: Array[Callable] = []
var _mp := 0.0
var _max_hp := 1
var _max_mp := 0
var _base_hp := 50.0
var _base_mp := 5.0
var _job_mp := 0.0
var _base_stats := DEFAULT_STATS.duplicate()
var _attributes := {}
var _earned_ap := 0
var _dead := false
var basic: BasicAttack
var basic_rng: RandomNumberGenerator
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
	view_size = setup.get("view_size", DEFAULT_VIEW)
	_init_rng_streams()
	_init_map()
	_init_mobs()
	_init_drops_and_shots()
	_init_skills_and_progression()
	_init_directors()
	_init_player_motion()
	_init_player()
	add_hit_listener(_mp_eater_hit)
	update_view()
	_write_player_state(0.0)


## One seeded stream per owner (see the header).
func _init_rng_streams() -> void:
	rng = _stream(1)
	basic_rng = _stream(5)
	spawn_rng = _stream(2)
	card_rng = _stream(3)
	drop_rng = _stream(4)
	potion_rng = _stream(7)
	reward_rng = _stream(6)
	job_rng = _stream(8) # tier C: independent bot branch stream, #53.


## Physics, footholds, bounds, ropes, portals and the two mob navigation graphs from the map img.
func _init_map() -> void:
	var map_img: Dictionary = setup.get("map_img", {})
	physics = PhysicsConstants.from_wz(setup.get("physics_img", {}))
	fhm = FootholdMap.from_wz(map_img)
	bounds = MapBounds.from_map(map_img, fhm)
	ladders = LadderSet.from_wz(map_img)
	portals = PortalSet.from_wz(map_img, int(stage.get("map_id", 0)), balance.get("portals", {}))
	var nav_opts := {"gravity": physics.gravity_acc, "fall_speed": physics.fall_speed, "jump_speed": physics.jump_speed}
	nav = NavGraph.build(fhm, nav_opts.merged({"can_jump": false}))
	nav_jump = NavGraph.build(fhm, nav_opts.merged({"can_jump": true}))


## Mob kinds, the swarm with its per-slot arrays, its spatial hash and its step context.
func _init_mobs() -> void:
	_build_mob_kinds()
	body_pad = ProjectileSystem.max_body_extent(mob_kinds)
	swarm = MobSwarm.new(256, mob_kinds, balance.get("mob_motion", {}))
	swarm.fhm = fhm
	mob_elite.resize(swarm.capacity())
	mob_boss.resize(swarm.capacity())
	mob_boss.fill(-1)
	mob_grid = SpatialHash.new(64.0, bounds.grow(64.0))
	_ctx = {"fhm": fhm, "nav": nav, "nav_jump": nav_jump, "bounds": bounds, "physics": physics,
		"target": Vector2.ZERO, "target_fh": -1, "speed_mult": 1.0}


## Player shots, EXP/potion drops and the potion stock.
func _init_drops_and_shots() -> void:
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


## Skill book, loadout, casters, EXP curve, job tree and upgrade cards.
func _init_skills_and_progression() -> void:
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


## Ordinary spawning, the boss schedule and the bosses' canonical skills.
func _init_directors() -> void:
	director = SpawnDirector.create(stage, kind_of_id, balance.get("spawn", {}))
	bosses = BossDirector.new(stage.get("bosses", []), balance.get("bosses", {}))
	mob_skills = MobSkillRunner.new(setup, balance.get("mob_skills", {}))


## The player's movement model (with the survivor knockback) and per-tick timers.
func _init_player_motion() -> void:
	var kb: Dictionary = balance.get("knockback", {})
	player = PlayerMotion.new(physics, {
		"knockback_speed": float(kb.get("speed", 187.5)), "knockback_hop": float(kb.get("hop", 200.0)),
		"knockback_lock": float(kb.get("lock", 0.3)),
	})
	upkeep = PlayerUpkeep.new(buffs, balance.get("regen", DEFAULT_REGEN))


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



## Whether an inactive buff meets its optional survivor HP threshold; casting/cooldown gates remain in SkillRunner.
func can_start_buff(skill: String, stats: Dictionary) -> bool:
	var threshold := float(stats.hp_threshold)
	return not buffs.has(skill) and (threshold <= 0 or _hp < float(_max_hp) * threshold)


## Starts a resolved timed buff; SkillRunner pays MP and applies the shared casting gate before this call.
func start_buff(skill: String, stats: Dictionary) -> void:
	buffs.start(skill, stats)
	_refresh_caster()
	refresh_player_speed()
	emit("buff_cast", {"skill": skill, "skill_id": int(stats.skill_id), "level": int(stats.level),
		"duration": float(stats.duration)})
	_write_player_state(0.0)


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
	refresh_player_speed()
	_step_player(dt, input)
	_step_monsters(dt)
	_step_player_attacks(dt)
	var got := _step_pickups(dt)
	_touch()
	if got > 0 and not _dead:
		_gain_exp(got)
	_write_player_state(dt)
	_end_tick()


## Drinks, then a same-map portal warp or ordinary movement, the view, and the player's timers.
func _step_player(dt: float, input: MoveInput) -> void:
	_teleport_left = maxf(0.0, _teleport_left - dt)
	if input.drink_hp:
		drink_potion("hp")
	if input.drink_mp:
		drink_potion("mp")
	if not _try_teleport(input) and not _take_portal(dt, input):
		var flags := player.step(dt, input, fhm, ladders, bounds)
		if flags & PlayerMotion.EV_JUMP:
			emit("player_jump", {"pos": player.pos})
	update_view()
	_tick_timers(dt)


## Owned branch Teleport key, or empty before learning it.
func teleport_skill() -> String:
	for key: String in loadout.order:
		if book.def(key).has("teleport"):
			return key
	return ""


## Whether an owned Teleport can currently be paid for (also used by the HUD and autoplay).
func teleport_affordable() -> bool:
	var key := teleport_skill()
	return key != "" and _mp >= int(runner.stats_of(self, key).mp_cost)


## HUD readiness of an owned skill: `left` seconds until ready (>= 0), the cooldown `total` set at its last cast
## (0 before any) and `mp_short` (ready and would cast, but MP is below its cost). Teleport reports its repeat timer.
func skill_readiness(key: String) -> Dictionary:
	if book.def(key).has("teleport"):
		return {"left": _teleport_left, "total": _teleport_total,
			"mp_short": _teleport_left <= 1e-6 and key == teleport_skill() and not teleport_affordable()}
	var left := maxf(0.0, float(runner.cooldowns.get(key, 0.0)))
	return {"left": left, "total": float(runner.cooldown_totals.get(key, 0.0)),
		"mp_short": left <= 1e-6 and runner.is_waiting_mp(key) and _mp < float(runner.stats_of(self, key).mp_cost)}


func _try_teleport(input: MoveInput) -> bool:
	if not (input.teleport_pressed or input.teleport_held) or _teleport_left > 1e-6 or not can_cast():
		return false
	var key := teleport_skill()
	if key == "":
		return false
	var stats := runner.stats_of(self, key)
	# tier C: vertical intent wins a diagonal; opposing keys cancel, then fall back to facing.
	var vertical := int(input.down) - int(input.up)
	var direction := Vector2(0, vertical) if vertical != 0 else Vector2(input.dir(), 0)
	if direction == Vector2.ZERO:
		direction.x = player.facing
	var dest := player.teleport_destination(direction, float(stats.teleport_range), fhm, bounds)
	if dest.is_empty() or not spend_mp(int(stats.mp_cost)):
		return false
	var departure := player.pos
	player.place(dest.pos, fhm)
	if direction.x != 0:
		player.facing = int(direction.x)
	_teleport_left = float(stats.repeat_delay)
	_teleport_total = _teleport_left
	for phase: String in ["departure", "arrival"]:
		emit("teleport", {"skill": key, "skill_id": int(stats.skill_id), "level": int(stats.level),
			"phase": phase, "pos": departure if phase == "departure" else player.pos,
			"facing": player.facing, "effect": String(stats.effect)})
	return true


## Holding Up in a same-map portal's box places the player at its destination (emits portal_used); true when warped.
func _take_portal(dt: float, input: MoveInput) -> bool:
	var warp := portals.step(dt, player.pos, input.up)
	if warp.is_empty():
		return false
	player.place(warp.pos, fhm)
	emit("portal_used", warp)
	return true


## Swarm movement, the boss lifecycle, boss skills/attacks, monster balls, ordinary spawns and the mob hash.
func _step_monsters(dt: float) -> void:
	_ctx.target = player.pos
	_ctx.target_fh = player.fh
	_ctx.speed_mult = director.value_at("speed", time)
	_ctx["boss_actions"] = bosses.prepare_actions(self)
	_ctx["events"] = events
	swarm.step(dt, _ctx)
	bosses.step(self, dt)
	mob_skills.step(self)
	boss_attacks.step(self)
	mob_projectiles.step(dt, self)
	director.step(dt, self)
	_sync_slots()
	mob_grid.rebuild(swarm.x, swarm.y, swarm.active, swarm.capacity())


## Auto-casts, the basic swing, then the player's shots against live defense/immunity; kills drop their rewards.
func _step_player_attacks(dt: float) -> void:
	runner.step(dt, self)
	basic.step(dt, self)
	_live_mdd.resize(swarm.capacity())
	_live_physical_allowed.resize(swarm.capacity())
	for slot in swarm.capacity():
		if swarm.active[slot] != 0:
			_live_mdd[slot] = mob_defense(slot,true)
			_live_physical_allowed[slot] = 1 if physical_hit_allowed(slot) else 0
	projectiles.step(dt, swarm, mob_grid, events, _live_mdd, _live_physical_allowed, _on_player_hit)
	for m in projectiles.kills:
		_on_kill(m)


## Moves and collects drops; collected potions join the stock. Returns the EXP collected this tick.
func _step_pickups(dt: float) -> int:
	var got := pickups.step(dt, player.pos, magnet_r, fhm, events)
	for kind: String in pickups.collected_potions:
		potions.add(kind, int(pickups.collected_potions[kind]))
	return got


## After a living tick: boss bonus choices first, then the clear, then queued level-ups.
func _end_tick() -> void:
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
	choice_bonus = false
	choice_advancement = true
	pending_cards = upgrades.roll_advancement_choices(self, card_rng)
	state = CHOOSING_UPGRADE
	emit("choice_pending", {"cards": pending_cards.duplicate(true), "bonus": false, "advancement": true})
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
	var selected := {}
	for c: Dictionary in pending_cards:
		if String(c.id) == card_id:
			selected = c
	if selected.is_empty():
		return false
	if upgrades.apply(card_id, self, String(selected.get("tier", "normal"))) == 0:
		return false
	var tier := String(selected.get("tier", "normal"))
	card_tiers_picked[tier] += 1
	pending_cards = []
	if choice_advancement:
		choice_advancement = false
	elif choice_bonus:
		pending_bonus_choices -= 1
		choice_bonus = false
	else:
		progression.pop_front()
		_job_checked = false
	state = PLAYING
	_advance_queue()
	_write_player_state(0.0)
	return true


## Changes the job and its Max MP grant, without learning skills; emits job_changed.
func change_job(job_id: int) -> void:
	progression.job_id = job_id
	var j := jobs.job(job_id)
	var grants: Dictionary = j.get("grants", {})
	_job_mp += float(grants.get("max_mp", 0.0))
	refresh_player_stats()
	emit("job_changed", {"job_id": job_id, "name": jobs.name_of(job_id)})


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


## Restores HP or MP, clamped to its maximum; returns and emits the actual integer pool gain (no event at zero).
func restore_player(stat: String, amount: int, skill: String) -> int:
	if stat not in ["hp", "mp"] or amount <= 0:
		return 0
	var before := ceili(_hp) if stat == "hp" else floori(_mp)
	if stat == "hp":
		_hp = minf(_max_hp, _hp + amount)
	else:
		_mp = minf(_max_mp, _mp + amount)
	_write_player_state(0.0)
	var gain := int(player_state[stat]) - before
	if gain > 0:
		emit("player_restored", {"stat": stat, "amount": gain, "skill": skill, "pos": player.pos})
	return gain


## Recomputes max HP/MP, speed, magnet, regen, defence and the caster inputs from the base stats, job and upgrade
## modifiers. The MaxMP passive preserves the MP ratio on growth; other explicit pool modifiers grant the
## difference, while ordinary level growth passes grant_growth=false and grants nothing.
func refresh_player_stats(grant_growth: bool = true) -> void:
	var pb: Dictionary = balance.get("player", {})
	var primary := String(_job_value(pb.get("ap_stat", {"0": "str", "200": "int"}), "str"))
	for stat: String in _base_stats:
		_attributes[stat] = roundi(loadout.player_stat(stat, float(_base_stats[stat])
			+ (_earned_ap if stat == primary else 0)))
	var old_hp := _max_hp
	var old_mp := _max_mp
	_max_hp = maxi(1, roundi(loadout.player_stat("max_hp", _base_hp)))
	var mp_percent := loadout.passive_total(Loadout.MAX_MP_PERCENT)
	_max_mp = maxi(0, roundi(loadout.player_stat("max_mp", _base_mp + _job_mp) * (1.0 + mp_percent)))
	if grant_growth and _max_hp > old_hp:
		_hp += _max_hp - old_hp
	if mp_percent > 0.0 and old_mp > 0 and _max_mp > old_mp:
		_mp = (_mp / old_mp) * _max_mp
	elif grant_growth and _max_mp > old_mp:
		_mp += _max_mp - old_mp
	_hp = minf(_hp, _max_hp)
	_mp = minf(_mp, _max_mp)
	refresh_player_speed()
	magnet_r = loadout.player_stat("magnet", float(balance.get("magnet_radius", 90.0)))
	hp_regen = loadout.player_stat("hp_regen", float(balance.get("hp_regen", 0.0)))
	mp_regen = loadout.player_stat("mp_regen", float(balance.get("mp_regen", 0.0)))
	player_pdd = loadout.player_stat("pdd", _equipment_total("incPDD")) + loadout.passive_total("pdd")
	player_mdd = loadout.player_stat("mdd", _equipment_total("incMDD")) + loadout.passive_total("mdd")
	player_avoid = loadout.player_stat("avoid", float(_attributes.dex) * AVOID_DEX_FACTOR
		+ float(_attributes.luk) * AVOID_LUK_FACTOR + _equipment_total("incEVA"))
	_refresh_caster()
	_write_player_state(0.0)


## Upgraded movement speed plus active canonical buff points, composed with the canonical-area slow.
func player_speed_stat() -> float:
	return (loadout.player_stat("speed", 100.0) + buffs.effect_total("speed")) * mob_skills.speed_multiplier(time)


func _refresh_caster() -> void:
	loadout.set_caster(float(_attributes.int), _equipment_total("incMAD") + buffs.effect_total("matk"), progression.level)


## Applies player_speed_stat() to the movement model (whole speed points).
func refresh_player_speed() -> void:
	player.speed_stat = roundi(player_speed_stat())


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


## True when slot m holds a scheduled boss (a BossDirector encounter); elites and boss offspring are not.
func is_scheduled_boss(m: int) -> bool:
	return m >= 0 and m < mob_boss.size() and mob_boss[m] >= 0


## Target order shared by every player targeting rule: scheduled bosses first, then nearer `d2`, then lower slot.
## tier C: ours (#83), so attacks reach a boss in range ahead of the swarm around it.
func targets_before(a: int, da: float, b: int, db: float) -> bool:
	var boss_a := is_scheduled_boss(a)
	if boss_a != is_scheduled_boss(b):
		return boss_a
	return da < db if da != db else a < b


## All live bodies intersecting a canonical feet-relative, left-facing skill box; scheduled bosses first, then nearest
## centre, then slot (targets_before).
## Minimum edges include touching bodies; maximum edges exclude them, matching SpatialHash.query_rect.
func skill_box_targets(box: Rect2, filter: Callable = Callable()) -> PackedInt32Array:
	if not box.has_area():
		return PackedInt32Array()
	if player.facing > 0:
		box.position.x = -box.end.x
	box.position += player.pos
	var candidates := PackedInt32Array()
	var n := mob_grid.query_rect(box.grow(body_pad), candidates)
	var matches: Array[int] = []
	for i in n:
		var m := candidates[i]
		if not swarm.is_live(m):
			continue
		var mk: MobKind = mob_kinds[swarm.kind[m]]
		var body_box := mk.hitbox_at(swarm.x[m], swarm.y[m], swarm.facing[m])
		if body_box.end.x < box.position.x or body_box.position.x >= box.end.x \
				or body_box.end.y < box.position.y or body_box.position.y >= box.end.y:
			continue
		if filter.is_valid() and not bool(filter.call(m)):
			continue
		matches.append(m)
	var origin := cast_origin()
	matches.sort_custom(func(a: int, b: int) -> bool:
		return targets_before(a, mob_center(a).distance_squared_to(origin), b, mob_center(b).distance_squared_to(origin)))
	return PackedInt32Array(matches)


## The setup's Mob.wz img root of mob `id` (int or String keys); {} when absent.
func mob_img(id: int) -> Dictionary:
	var imgs: Dictionary = setup.get("mob_imgs", {})
	return imgs.get(id, imgs.get(str(id), {}))


## The player's world-space body box (feet + `body`): what monster touches, attacks and balls test.
func player_box() -> Rect2:
	return Rect2(player.pos + body.position, body.size)


## Centre of the player's body box (where monster balls aim).
func player_body_center() -> Vector2:
	return player.pos + body.get_center()


## Number of living slots owned by summoning encounter `owner` (MobSkill 200 summons and revive offspring).
func summoned_alive(owner: int) -> int:
	var count := 0
	for slot in swarm.capacity():
		if swarm.active[slot] != 0 and mob_summon_owner[slot] == owner:
			count += 1
	return count


## Spawns `ids` (in list order) as ordinary mobs owned by encounter `owner` on mob `source`'s platform, spread
## `balance.mob_skills.summon_spacing` px apart around `center_x` and centred on the whole list even when `max_count`
## (-1 = all) spawns only its first entries. Ids without a mob kind and points without a foothold are skipped (their
## place in the spread stays empty). Returns the new slots; none when the source has no platform.
func spawn_offspring(source: int, center_x: float, ids: PackedInt32Array, owner: int,
		max_count: int = -1) -> PackedInt32Array:
	var slots := PackedInt32Array()
	var platform := swarm.platform[source]
	if platform < 0:
		return slots
	var span := fhm.platform_span(platform)
	# tier C: symmetric survivor spawn spacing; canonical list/limit/stats remain unchanged.
	var spacing := float(balance.get("mob_skills", {}).get("summon_spacing", DEFAULT_SUMMON_SPACING))
	for i in (ids.size() if max_count < 0 else mini(ids.size(), max_count)):
		var id := ids[i]
		if not kind_of_id.has(id):
			continue
		var x := clampf(center_x + (i - (ids.size() - 1) * 0.5) * spacing, span.x, span.y)
		var fh := fhm.platform_fh_at(platform, x)
		if fh < 0:
			continue
		var slot := spawn_mob(int(kind_of_id[id]), Vector2(x, fhm.y_at(fh, x)), fh, 1.0, false)
		mob_summon_owner[slot] = owner
		slots.append(slot)
	return slots


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
	upkeep.start_action(action, seconds, airborne)


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


## Whether a physical impact may damage this slot at the current simulation time.
func physical_hit_allowed(m: int) -> bool:
	return mob_skills.physical_hit_allowed(m, time)


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
## kind spawned there with its logical identity, HP, max HP, remaining MP and elite flag, fading in; emits mob_spawned with relocated_from =
## i (new spawns have -1). Returns the new slot (-1 when i is not a live mob).
func relocate_mob(i: int, pos: Vector2, fh: int) -> int:
	if i < 0 or i >= swarm.capacity() or swarm.active[i] == 0:
		return -1
	var k := swarm.kind[i]
	var elite := mob_elite[i] != 0
	var boss_index := mob_boss[i]
	var summon_owner := mob_summon_owner[i]
	var j := swarm.relocate(i, pos, fh)
	_sync_slots()
	mob_elite[j] = 1 if elite else 0
	mob_boss[j] = boss_index
	swarm.steady[j] = 1 if boss_index >= 0 else 0
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
		mob_defense(m, true), projectiles.magic_defense_k, float(st.crit), float(st.crit_mult), rng,
		mk.element_multiplier(String(st.get("element", ""))))
	var dir := 1 if swarm.x[m] >= player.pos.x else -1
	emit("mob_hit", {
		"mob": m, "mob_id": mk.id, "damage": roll.x, "crit": roll.y != 0,
		"pos": Vector2(swarm.x[m], swarm.y[m] + mk.hitbox.position.y),
		"hit_visual": String(visual_paths[hv]) if hv >= 0 else "", "skill": String(st.skill),
	})
	_instant_dealt += roll.x
	if roll.x > 0:
		_on_player_hit(m, {"skill": String(st.skill), "level": int(st.get("level", 0)), "magic": bool(st.magic),
			"damage": roll.x, "element": String(st.get("element", ""))})
	if swarm.apply_hit(m, roll.x, dir):
		_on_kill(m)


## Registers a listener(slot, hit) after on-hit statuses and before damage/kill resolution, once per damaging line.
func add_hit_listener(listener: Callable) -> void:
	_hit_listeners.append(listener)


func _mp_eater_hit(slot: int, hit: Dictionary) -> void:
	if not bool(hit.magic) or int(hit.damage) <= 0 or swarm.mp[slot] <= 0:
		return
	# Branch-exclusive learn cards allow only one MP Eater per normal run, preserving the old proc order.
	for key: String in loadout.order:
		var absorb: Dictionary = book.def(key).get("absorb_mp", {})
		if absorb.is_empty():
			continue
		var level := loadout.level(key)
		if level <= 0:
			continue
		var chance := book.canonical(key, level, String(absorb.chance_field))
		var percent := book.canonical(key, level, String(absorb.percent_field))
		# tier C: truncate fractional MP to whole points (integer interpretation).
		var amount := mini(swarm.mp[slot], int(swarm.mob_kind(slot).max_mp * percent / 100.0))
		if chance <= 0.0 or amount <= 0:
			continue
		if chance < 100.0 and rng.randf() * 100.0 >= chance:
			continue
		swarm.mp[slot] -= amount
		restore_player("mp", amount, key)
		# tier C: absorb art also plays at full player MP; gain numbers use player_restored's actual capped gain.
		emit("mp_eater_absorbed", {"mob": slot, "amount": amount, "skill": key, "pos": player.pos})


func _on_player_hit(slot: int, hit: Dictionary) -> void:
	var key := String(hit.skill)
	var level := int(hit.level)
	var status: Dictionary = book.def(key).get("on_hit", {})
	if not status.is_empty():
		var chance_field := String(status.get("chance_field", ""))
		var chance := book.canonical(key, level, chance_field) if chance_field != "" else 100.0
		if chance > 0.0 and (chance >= 100.0 or rng.randf() * 100.0 < chance):
			var params := {"time": book.canonical(key, level, String(status.get("duration_field", "time"))),
				"level": level, "skill": key, "x": book.canonical(key, level, "x")}
			if String(hit.element) != "":
				params["element"] = String(hit.element)
			swarm.apply_status(slot, String(status.get("status", "")), params, events)
	for listener: Callable in _hit_listeners:
		listener.call(slot, hit)


func _stream(n: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value * 1000003 + n * 7919
	return r


func _build_mob_kinds() -> void:
	var imgs: Dictionary = setup.get("mob_imgs", {})
	var overrides: Dictionary = data.get("mobs", {}).get("mobs", {})
	var speed_mult := float(balance.get("mob_speed_factor", MobKind.SPEED_SCALE)) / MobKind.SPEED_SCALE
	for id in StageRoster.mob_ids(stage, imgs, setup.get("mob_skill_img", {})):
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
	player.place(PortalSet.start_point(setup.get("map_img", {}), fhm, bounds, spawn_rng), fhm)
	refresh_player_stats()
	_hp = _max_hp
	_mp = _max_mp
	for key: Variant in pb.get("skills", []):
		learn_skill(String(key))
	_action = player.stance()


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
	var matk_before := buffs.effect_total("matk")
	_hp = minf(_max_hp, _hp + upkeep.tick(dt, events))
	if buffs.effect_total("matk") != matk_before:
		_refresh_caster()
	refresh_player_speed()
	if _dead:
		return
	for _pulse in upkeep.regen_pulses(dt):
		_hp = minf(_max_hp, _hp + upkeep.pulse_hp() + hp_regen)
		_mp = minf(_max_mp, _mp + upkeep.pulse_mp() + mp_regen
			+ upkeep.improved_mp_bonus(progression.level, loadout.level("improved_mp_recovery")))


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
	var mk := swarm.mob_kind(m)
	var elite := mob_elite[m] != 0
	var pos := swarm.pos(m)
	if mob_boss[m] >= 0:
		_on_boss_kill(m, mk, pos, elite)
		return
	var mult := float(balance.get("exp_mult", 1.0)) * float(stage.get("exp_mult", 1.0))
	if elite:
		mult *= float(stage.get("elites", {}).get("exp_mult", 5.0))
	var e := roundi(mk.exp * mult)
	emit("mob_died", {"mob": m, "mob_id": mk.id, "pos": pos, "exp": e, "elite": elite})
	if e > 0:
		var p := pickups.spawn(pos, e, mk.exp_item, player.pos)
		emit("pickup_spawned", {"pickup": p, "item_id": mk.exp_item, "pos": pos,
			"kind": "exp", "potion_kind": "", "count": 0})
	var chances: Dictionary = balance.get("potions", {}).get("drops", {}).get("elite" if elite else "normal", {})
	for kind: String in ["hp", "mp"]:
		var chance := float(chances.get(kind, 0.0))
		# Only HP has a stage curve; normal MP is one flat chance everywhere (owner, 2026-10-16, #80).
		if kind == "hp" and not elite:
			chance = director.normal_hp_drop_chance_at(time, chance)
		if chance > 0.0 and potion_rng.randf() < chance:
			spawn_potion(kind, pos)


## A scheduled boss died: boss_died, mob_died with the boss reward EXP (canonical EXP x rewards.exp_mult; no ordinary
## EXP or random potion rolls), its canonical revive list, then the reward shower and bonus choices.
func _on_boss_kill(m: int, mk: MobKind, pos: Vector2, elite: bool) -> void:
	var rewards := bosses.reward_config(mob_boss[m])
	var e := maxi(0, roundi(mk.exp * float(rewards.get("exp_mult", 1.0))))
	bosses.mark_dead(mob_boss[m], m, pos, self)
	emit("mob_died", {"mob": m, "mob_id": mk.id, "pos": pos, "exp": e, "elite": elite})
	_spawn_revives(m, pos)
	_drop_boss_rewards(pos, e, mk.exp_item, rewards)


func _spawn_revives(source: int, pos: Vector2) -> void:
	var id: int = mob_kinds[swarm.kind[source]].id
	var list: Dictionary = mob_img(id).get("info", {}).get("revive", {})
	if list.is_empty() or swarm.platform[source] < 0:
		return
	# Every canonical revive entry is spawned once (Skill200's living limit applies to casts, not to this list).
	var children: Array[Dictionary] = []
	for slot in spawn_offspring(source, pos.x, StageRoster.list_ids(list), mob_boss[source]):
		children.append({"mob": slot, "mob_id": swarm.mob_kind(slot).id})
	emit("mob_revives_spawned", {"boss_index": mob_boss[source], "mob": source, "mob_id": id,
		"pos": pos, "revives": children, "time": time})


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
	if _dead or god or upkeep.invincible_t > 0.0:
		return
	var box := player_box()
	var c := box.get_center()
	var n := mob_grid.query_radius(c, body.size.length() * 0.5 + body_pad, _touch_buf)
	for j in n:
		var m := _touch_buf[j]
		# tier C (owner): a frozen monster deals no touch damage.
		if not swarm.can_act(m):
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
	return {"pdd": player_pdd + buffs.effect_total("pdd"), "mdd": player_mdd + buffs.effect_total("mdd"), "resistance": {}}


## Magic Guard's current percentage; overridable by the timed-buff rules.
func magic_guard_ratio() -> float:
	return buffs.effect_total("mp_guard")


## Only explicit source scaling: elites use stage.elites.damage_mult; boss sources may pass dmg_mult.
func hit_source_multiplier(source: Dictionary) -> float:
	var mult := float(source.get("dmg_mult", 1.0))
	if bool(source.get("elite", false)):
		mult *= float(stage.get("elites", {}).get("damage_mult", 1.0))
	return mult


## Applies one monster hit through avoid, defense, Magic Guard and hit reaction; returns whole damage (0 on miss).
## Source fields: accuracy (canonical acc), elite, dmg_mult, mob, mob_id, boss. Events snapshot max_hp at hit time.
func take_hit(attack: float, magic: bool, element: String, source_pos: Vector2, source: Dictionary = {}) -> int:
	if _dead or god or upkeep.invincible_t > 0.0:
		return 0
	var dir := 1 if player.pos.x >= source_pos.x else -1
	if CombatMath.roll_miss(player_avoid + buffs.effect_total("avoid"), float(source.get("accuracy", 0.0)), rng):
		_emit_player_hit(0, 0, true, dir, source)
		return 0
	var dmg := CombatMath.monster_hit(attack, magic, element, hit_defense(), rng,
		hit_source_multiplier(source))
	if not magic:
		# tier C: apply canonical Invincible percent to the whole weapon hit, before Magic Guard; minimum 1.
		dmg = maxi(1, roundi(dmg * (1.0 - clampf(buffs.effect_total("weapon_damage_reduction"), 0.0, 100.0) / 100.0)))
	var split := CombatMath.magic_guard_split(dmg, magic_guard_ratio(), floori(_mp))
	_hp -= split.x
	_mp -= split.y
	_emit_player_hit(dmg, split.y, false, dir, source)
	upkeep.invincible_t = float(balance.get("invincible_time", 1.5))
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
	var refill: Dictionary = balance.get("level_up_refill", DEFAULT_LEVEL_UP_REFILL)
	_hp = minf(_max_hp, _hp + float(refill.get("hp", DEFAULT_LEVEL_UP_REFILL.hp)) * _max_hp)
	_mp = minf(_max_mp, _mp + float(refill.get("mp", DEFAULT_LEVEL_UP_REFILL.mp)) * _max_mp)
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
		choice_bonus = true
		var bonus_cards := upgrades.roll_choices(self, card_rng, 3)
		pending_cards = bonus_cards
		state = CHOOSING_UPGRADE
		emit("choice_pending", {"cards": bonus_cards.duplicate(true), "bonus": true, "advancement": false})
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
		choice_bonus = false
		var cards := upgrades.roll_choices(self, card_rng, 3)
		pending_cards = cards
		state = CHOOSING_UPGRADE
		emit("choice_pending", {"cards": cards.duplicate(true), "bonus": false, "advancement": false})
		return
	state = PLAYING


func _write_player_state(dt: float) -> void:
	var a := "dead" if _dead else player.stance()
	if not _dead and upkeep.cast_left > 0.0 and (player.state == PlayerMotion.ST_STAND
			or (upkeep.action_airborne and player.state == PlayerMotion.ST_AIR)):
		a = upkeep.cast_action
	if a != _action:
		_action = a
		_action_t = 0.0
	else:
		_action_t += dt
	player_state["hp"] = ceili(_hp) if _hp > 0.0 else 0
	player_state["mp"] = floori(_mp)
	player_state["mp_short"] = runner.waiting_mp
	player_state["buffs"] = buffs.snapshot()
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
	player_state["avoid"] = player_avoid + buffs.effect_total("avoid")
	# Canonical Bless accuracy is stored; outgoing attacks currently have no player-accuracy rule.
	player_state["acc"] = buffs.effect_total("acc")
	player_state["fortune"] = maxf(0.0, loadout.player_stat("fortune", float(balance.get("player", {}).get("fortune", 0.0))))
	player_state["invincible_t"] = upkeep.invincible_t
	player_state["action"] = _action
	player_state["action_t"] = _action_t
	player_state["dead"] = _dead
	player_state["potions"] = potions.snapshot()
