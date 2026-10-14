class_name RunWorld
extends RefCounted
## One survivor run (docs/ARCHITECTURE.md 4.3, 4.4, 4.4.1-4.4.3): built from a setup Dictionary, advanced by fixed
## 1/60 s step() calls, reporting what happened through `events`. Pure: no nodes, input, time, files or autoloads.
##
## Per PLAYING tick: player movement (PlayerMotion) -> view rect -> invincibility/regen/cast-stance timers -> mobs
## (MobSwarm, target = the player) -> SpawnDirector (recycling, spawns, bursts, elites) -> SpatialHash rebuild ->
## SkillRunner (casts, instant hits, new shots) -> ProjectileSystem (hits; kills become mob_died + an EXP drop) ->
## PickupSystem (magnet, collect -> EXP) -> touch damage -> EXP/level-ups. Then: death -> DEAD (player_died); the
## stage duration reached -> CLEARED (stage_cleared); else queued level-ups open their windows.
##
## Pause protocol (4.4.2): step() does nothing unless `state` is PLAYING. For each queued level the job tree is checked
## first (CHOOSING_JOB + job_advance_pending when JobTree.should_offer), then CHOOSING_UPGRADE + choice_pending with
## cards drawn when the window opens. apply_job(id) / decline_job() continue to that level's upgrade choice;
## apply_choice(id) applies the card and moves to the next queued level or back to PLAYING. They return false (and
## change nothing) when called in the wrong state or with an id that is not on offer.
##
## Events: every emitted Dictionary has `type` plus exactly the fields of EVENT_FIELDS[type]. `player_hit.damage` is the
## whole hit (the number shown), `mp_absorbed` the part Magic Guard paid with MP. `choice_pending` card `rank` is the
## rank the card gives when taken. Swarm/projectile/pickup visuals are read from state (4.4.3).
##
## Player stats live in `player_state` (hp, mp, max_hp, max_mp, exp, level, job_id, int, invincible_t, action,
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
	"mob_spawned": ["mob", "mob_id", "pos", "elite"],
	"mob_hit": ["mob", "mob_id", "damage", "crit", "pos", "hit_visual", "skill"],
	"mob_died": ["mob", "mob_id", "pos", "exp", "elite"],
	"player_hit": ["damage", "mp_absorbed", "dir", "pos"],
	"player_jump": ["pos"],
	"player_died": ["pos"],
	"pickup_spawned": ["pickup", "item_id", "pos"],
	"pickup_collected": ["pickup", "item_id", "exp", "pos"],
	"level_up": ["level"],
	"job_advance_pending": ["options"],
	"job_changed": ["job_id", "name"],
	"choice_pending": ["cards"],
	"upgrade_applied": ["id", "rank"],
	"skill_learned": ["skill", "skill_id"],
	"burst": ["count"],
	"stage_cleared": ["time"],
}

## tier C defaults used when balance.json lacks a value.
const DEFAULT_BODY := Rect2(-14, -58, 28, 58)
const DEFAULT_CAST_HEIGHT := 30.0
const DEFAULT_VIEW := Vector2(800, 600)

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

var physics: PhysicsConstants
var fhm: FootholdMap
var bounds := Rect2()
var ladders: LadderSet
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
var mob_grid: SpatialHash
var projectiles: ProjectileSystem
var pickups: PickupSystem
var book: SkillBook
var loadout: Loadout
var runner: SkillRunner
var progression: RunProgression
var jobs: JobTree
var upgrades: UpgradePool
var director: SpawnDirector

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
## The next card draw's guarantee ({kind, job}; {} = none), from the job just taken.
var guarantee := {}
## Setup problems the sim worked around (e.g. a pool mob without a mob img).
var warnings := PackedStringArray()
## Largest feet-to-body-box-corner distance over all mob kinds (pads feet-point hash queries).
var body_pad := 64.0
var magnet_r := 90.0
var hp_regen := 0.0
var mp_regen := 2.0
var player_pdd := 0.0
var body := DEFAULT_BODY
var cast_height := DEFAULT_CAST_HEIGHT
## Tests and benchmarks only: the player takes no touch damage.
var god := false

var _hp := 0.0
var _mp := 0.0
var _max_hp := 1
var _max_mp := 0
var _base_hp := 50.0
var _base_mp := 5.0
var _job_mp := 0.0
var _int := 4.0
var _dead := false
var _invincible_t := 0.0
var _cast_action := ""
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
	spawn_rng = _stream(2)
	card_rng = _stream(3)
	drop_rng = _stream(4)
	view_size = setup.get("view_size", DEFAULT_VIEW)
	var map_img: Dictionary = setup.get("map_img", {})
	physics = PhysicsConstants.from_wz(setup.get("physics_img", {}))
	fhm = FootholdMap.from_wz(map_img)
	bounds = MapBounds.from_map(map_img, fhm)
	ladders = LadderSet.from_wz(map_img)
	var nav_opts := {"gravity": physics.gravity_acc, "fall_speed": physics.fall_speed, "jump_speed": physics.jump_speed}
	nav = NavGraph.build(fhm, nav_opts.merged({"can_jump": false}))
	nav_jump = NavGraph.build(fhm, nav_opts.merged({"can_jump": true}))
	_build_mob_kinds()
	body_pad = ProjectileSystem.max_body_extent(mob_kinds)
	swarm = MobSwarm.new(256, mob_kinds)
	swarm.fhm = fhm
	mob_elite.resize(swarm.capacity())
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
	book = SkillBook.from_data(data.get("skills", {}), setup.get("skill_imgs", {}))
	loadout = Loadout.new(book)
	var crit: Dictionary = balance.get("crit", {})
	loadout.crit_chance = float(crit.get("chance", 0.0))
	loadout.crit_mult = float(crit.get("mult", 1.5))
	runner = SkillRunner.new()
	progression = RunProgression.new(ExpCurve.from_data(balance.get("exp_curve", {})),
		int(balance.get("max_level", 200)))
	jobs = JobTree.from_data(data.get("jobs", {}), data.get("jobs_survivor", {}))
	upgrades = UpgradePool.from_data(data.get("upgrades", {}))
	director = SpawnDirector.create(stage, kind_of_id, balance.get("spawn", {}))
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
	var flags := player.step(dt, input, fhm, ladders, bounds)
	if flags & PlayerMotion.EV_JUMP:
		emit("player_jump", {"pos": player.pos})
	update_view()
	_tick_timers(dt)
	_ctx.target = player.pos
	_ctx.target_fh = player.fh
	_ctx.speed_mult = director.value_at("speed", time)
	swarm.step(dt, _ctx)
	director.step(dt, self)
	_sync_slots()
	mob_grid.rebuild(swarm.x, swarm.y, swarm.active, swarm.capacity())
	runner.step(dt, self)
	projectiles.step(dt, swarm, mob_grid, events)
	for m in projectiles.kills:
		_on_kill(m)
	damage_dealt = projectiles.dealt + _instant_dealt
	var got := pickups.step(dt, player.pos, magnet_r, fhm, events)
	_touch()
	if got > 0 and not _dead:
		_gain_exp(got)
	_write_player_state(dt)
	if _dead:
		return
	if time >= duration - 1e-6:
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
	progression.pop_front()
	_job_checked = false
	state = PLAYING
	_advance_queue()
	_write_player_state(0.0)
	return true


## Changes the job (stats, grants) and emits job_changed.
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


## Recomputes max HP/MP, speed, magnet, regen, defence and the caster inputs from the base stats, job and upgrade
## modifiers. A higher max also raises the current value by the difference.
func refresh_player_stats() -> void:
	var old_hp := _max_hp
	var old_mp := _max_mp
	_max_hp = maxi(1, roundi(loadout.player_stat("max_hp", _base_hp)))
	_max_mp = maxi(0, roundi(loadout.player_stat("max_mp", _base_mp + _job_mp)))
	if _max_hp > old_hp:
		_hp += _max_hp - old_hp
	if _max_mp > old_mp:
		_mp += _max_mp - old_mp
	_hp = minf(_hp, _max_hp)
	_mp = minf(_mp, _max_mp)
	player.speed_stat = roundi(loadout.player_stat("speed", 100.0))
	magnet_r = loadout.player_stat("magnet", float(balance.get("magnet_radius", 90.0)))
	hp_regen = loadout.player_stat("hp_regen", float(balance.get("hp_regen", 0.0)))
	mp_regen = loadout.player_stat("mp_regen", float(balance.get("mp_regen", 2.0)))
	var pb: Dictionary = balance.get("player", {})
	player_pdd = loadout.player_stat("pdd", float(pb.get("pdd", 0.0))) + loadout.passive_total("pdd")
	loadout.set_caster(_int, _job_value(pb.get("magic_attack", {}), 0.0), progression.level)
	_write_player_state(0.0)


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


## Where shots start and targeting measures from: the player's body (feet - cast_height).
func cast_origin() -> Vector2:
	return player.pos - Vector2(0.0, cast_height)


## Centre of mob m's body box (where shots aim).
func mob_center(m: int) -> Vector2:
	var mk: MobKind = mob_kinds[swarm.kind[m]]
	return mk.hitbox_at(swarm.x[m], swarm.y[m], swarm.facing[m]).get_center()


## Platform the player stands on or is above (-1 when none).
func player_platform() -> int:
	if player.fh >= 0:
		return fhm.platform_of(player.fh)
	return fhm.platform_of(fhm.find_below(player.pos.x, player.pos.y))


## Turns a standing player toward x (casting at a target); a walking player keeps facing its way.
func face_toward(tx: float) -> void:
	if player.state == PlayerMotion.ST_STAND and absf(tx - player.pos.x) > 0.5:
		player.facing = 1 if tx > player.pos.x else -1


## Starts the cast stance `action` for `seconds` (shown while the player stands still).
func start_action(action: String, seconds: float) -> void:
	if action == "" or seconds <= 0.0:
		return
	_cast_action = action
	_cast_left = seconds


## Spawns a mob of kind index k on foothold fh at pos with max_hp x hp_mult; emits mob_spawned. Returns the slot.
func spawn_mob(k: int, pos: Vector2, fh: int, hp_mult: float, elite: bool) -> int:
	if k < 0 or k >= mob_kinds.size():
		return -1
	var mk: MobKind = mob_kinds[k]
	var i := swarm.spawn(k, pos.x, pos.y, fh, maxi(1, roundi(mk.max_hp * hp_mult)))
	_sync_slots()
	mob_elite[i] = 1 if elite else 0
	emit("mob_spawned", {"mob": i, "mob_id": mk.id, "pos": Vector2(swarm.x[i], swarm.y[i]), "elite": elite})
	return i


## One instant damage line of skill stats `st` on mob m (Magic Claw); hv = hit visual index. Kills drop EXP.
func hit_mob(m: int, st: Dictionary, hv: int) -> void:
	if swarm.active[m] == 0:
		return
	var mk: MobKind = mob_kinds[swarm.kind[m]]
	var roll := ProjectileSystem.roll_damage(float(st.damage_min), float(st.damage_max), bool(st.magic),
		float(mk.mdd), projectiles.magic_defense_k, float(st.crit), float(st.crit_mult), rng)
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
	_int = float(pb.get("int", 4.0))
	var b: Variant = pb.get("body")
	if b is Array and b.size() == 4:
		body = Rect2(float(b[0]), float(b[1]), float(b[2]), float(b[3]))
	cast_height = float(pb.get("cast_height", DEFAULT_CAST_HEIGHT))
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
		_hp = minf(_max_hp, _hp + hp_regen * dt)
		_mp = minf(_max_mp, _mp + mp_regen * dt)


func _sync_slots() -> void:
	if mob_elite.size() < swarm.capacity():
		mob_elite.resize(swarm.capacity())


func _on_kill(m: int) -> void:
	kills += 1
	var mk: MobKind = mob_kinds[swarm.kind[m]]
	var elite := mob_elite[m] != 0
	var mult := float(balance.get("exp_mult", 1.0))
	if elite:
		mult *= float(stage.get("elites", {}).get("exp_mult", 5.0))
	var e := roundi(mk.exp * mult)
	var pos := Vector2(swarm.x[m], swarm.y[m])
	emit("mob_died", {"mob": m, "mob_id": mk.id, "pos": pos, "exp": e, "elite": elite})
	if e <= 0:
		return
	var p := pickups.spawn(pos, e, mk.exp_item)
	if not pickups.merged:
		emit("pickup_spawned", {"pickup": p, "item_id": mk.exp_item, "pos": pos})


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
	var td: Dictionary = balance.get("touch_damage", {})
	var dmg := CombatMath.touch_damage(float(mk.pad), rng.randf(), director.value_at("damage", time), player_pdd,
		float(td.get("scale", CombatMath.TOUCH_SCALE)), float(td.get("roll_min", CombatMath.TOUCH_ROLL_MIN)),
		float(td.get("roll_max", CombatMath.TOUCH_ROLL_MAX)), float(td.get("pdd_factor", CombatMath.TOUCH_PDD_FACTOR)))
	var split := CombatMath.magic_guard_split(dmg, loadout.passive_total("mp_guard"), floori(_mp))
	_hp -= split.x
	_mp -= split.y
	var dir := 1 if player.pos.x >= swarm.x[m] else -1
	emit("player_hit", {"damage": dmg, "mp_absorbed": split.y, "dir": dir, "pos": player.pos})
	_invincible_t = float(balance.get("invincible_time", 1.5))
	if _hp <= 0.0:
		_hp = 0.0
		_dead = true
		state = DEAD
		emit("player_died", {"pos": player.pos})
	else:
		player.knockback(dir)


func _gain_exp(n: int) -> void:
	var before := progression.level
	var gained := progression.add_exp(n)
	for k in gained:
		_on_level_up(before + k + 1)


func _on_level_up(level: int) -> void:
	var g: Dictionary = _job_value(balance.get("growth", {}), {})
	_base_hp += float(g.get("hp", 0.0))
	_base_mp += float(g.get("mp", 0.0))
	_int += float(g.get("int", 0.0))
	refresh_player_stats()
	var refill := float(balance.get("level_up_refill", 0.25))
	_hp = minf(_max_hp, _hp + refill * _max_hp)
	_mp = minf(_max_mp, _mp + refill * _max_mp)
	emit("level_up", {"level": level})


## The entry of a per-job table (keys = job ids as strings) for the current job, else its nearest ancestor's.
func _job_value(table: Variant, fallback: Variant) -> Variant:
	if not (table is Dictionary):
		return fallback
	for j in jobs.lineage(progression.job_id):
		if table.has(str(j)):
			return table[str(j)]
	return table.get("0", fallback)


func _advance_queue() -> void:
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
		emit("choice_pending", {"cards": cards.duplicate(true)})
		return
	state = PLAYING


func _write_player_state(dt: float) -> void:
	var a := "dead" if _dead else player.stance()
	if not _dead and _cast_left > 0.0 and player.state == PlayerMotion.ST_STAND:
		a = _cast_action
	if a != _action:
		_action = a
		_action_t = 0.0
	else:
		_action_t += dt
	player_state["hp"] = ceili(_hp) if _hp > 0.0 else 0
	player_state["mp"] = floori(_mp)
	player_state["max_hp"] = _max_hp
	player_state["max_mp"] = _max_mp
	player_state["exp"] = progression.exp
	player_state["exp_next"] = progression.exp_to_next()
	player_state["level"] = progression.level
	player_state["job_id"] = progression.job_id
	player_state["int"] = roundi(_int)
	player_state["invincible_t"] = _invincible_t
	player_state["action"] = _action
	player_state["action_t"] = _action_t
	player_state["dead"] = _dead
