extends SceneTree
## Headless per-system profile of RunWorld.step in a real round (issue #146): plays a stage with the sensible autoplay
## bot (BotInput.decide, BotInput.pick_card_for, BotShop.equip_after: the round RunScene's autoplay and balance_run
## play) untimed up to --from, then times every part of the tick separately until --to (or the end of the round) and
## prints each part's share of the step, with the alive mobs and the drop pool (by kind and state) per minute. Needs
## the asset cache (the real map and mob/skill imgs).
##
##   bash scripts/godot.sh --headless --path game --script res://tools/profile_run.gd -- --seed=5 --from=780 --to=900
##       [--stage=henesys_hg1] [--account=<abs AccountFile JSON>] [--job=<id>] [--mortal]
##
## The player is in god mode (RunWorld.god: no damage) so the bot reaches the late, crowded minutes; --mortal turns it
## off (the round then ends where the bot dies).
## The timed tick replays RunWorld.step part by part (keep _timed_step in step with RunWorld.step / _step_monsters /
## _step_player_attacks); it calls the same functions in the same order, so the round is the same one RunWorld.step
## would play. Timings are wall-clock on this machine (Time.get_ticks_usec around each part, which adds a little
## overhead per part); compare shares, and raw numbers only on a quiet machine.

const BR := preload("res://tools/balance_run.gd")
const DT := 1.0 / 60.0
const PARTS := ["player", "swarm.step", "bosses", "mob_skills", "boss_attacks", "mob_attacks", "mob_projectiles",
	"director", "sync_slots", "mob_grid", "runner", "basic", "live_mdd", "projectiles", "kills", "pet", "pickups",
	"touch", "gain_exp", "player_state", "end_tick"]


func _init() -> void:
	var stage := "henesys_hg1"
	var seed_value := 2026
	var from := 780.0
	var to := 1020.0
	var account_file := ""
	var forced_job := 0
	var god := true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stage="):
			stage = a.substr(8)
		elif a.begins_with("--seed="):
			seed_value = int(a.substr(7))
		elif a.begins_with("--from="):
			from = float(a.substr(7))
		elif a.begins_with("--to="):
			to = float(a.substr(5))
		elif a.begins_with("--account="):
			account_file = a.substr(10)
		elif a.begins_with("--job="):
			forced_job = int(a.substr(6))
		elif a == "--mortal":
			god = false
	var data := DataRepo.load_all()
	var root := AssetCachePaths.resolve_cache_root()
	var missing := PackedStringArray()
	var setup := DataRepo.build_setup(data, stage, seed_value, Vector2(800, 600),
		func(p: String) -> Dictionary: return BR._json(root, p),
		func(id: int) -> Dictionary: return BR._json(root, "Mob.wz/%07d.img" % id), missing, {})
	if not missing.is_empty() or setup.get("map_img", {}).is_empty():
		print("profile_run: the asset cache lacks %s for %s (root %s)" % [missing, stage, root])
		quit(1)
		return
	if account_file != "":
		var errors := PackedStringArray()
		var account := AccountFile.load_file(account_file, errors)
		if not errors.is_empty():
			print("profile_run: " + "; ".join(errors))
			quit(1)
			return
		BR.apply_account([setup], account)
	setup.seed = seed_value
	var w := RunWorld.new(setup)
	w.god = god
	var memo := {}
	var rng := RandomNumberGenerator.new()
	var cards: Array = []
	var acc := PackedInt64Array()
	acc.resize(PARTS.size())
	var bot_us := 0
	var step_us := 0
	var wait_ticks := 0
	var wait_us := 0
	var ticks := 0
	var minute := {}
	var t_start := Time.get_ticks_msec()
	while w.time < to:
		BR.choose(w, "bot", rng, cards, forced_job)
		if w.state != RunWorld.PLAYING:
			break
		var b0 := Time.get_ticks_usec()
		var input := BotInput.decide(w, memo)
		var b1 := Time.get_ticks_usec()
		if w.time < from:
			w.step(DT, input)
			BotShop.equip_after(w, w.drain_events())
			continue
		bot_us += b1 - b0
		var s0 := Time.get_ticks_usec()
		var runner0 := acc[10]
		_timed_step(w, DT, input, acc)
		if w.runner.waiting_mp:
			wait_ticks += 1
			wait_us += acc[10] - runner0
		step_us += Time.get_ticks_usec() - s0
		BotShop.equip_after(w, w.drain_events())  # the bot wears its best drops, as RunScene and balance_run do
		ticks += 1
		var m := int(w.time / 60.0)
		var row: Dictionary = minute.get(m, {"n": 0, "alive": 0, "drops": 0, "exp": 0, "meso": 0, "equip": 0,
			"potion": 0, "rest": 0, "magnet": 0, "air": 0, "hi": 0})
		row.n += 1
		row.alive += w.swarm.alive_count()
		var pk := w.pickups
		row.drops += pk.active_count()
		row.hi += pk._hi
		for i in pk.capacity():
			if pk.active[i] == 0:
				continue
			match int(pk.kind[i]):
				PickupSystem.EXP: row.exp += 1
				PickupSystem.MESO: row.meso += 1
				PickupSystem.EQUIP: row.equip += 1
				_: row.potion += 1
			match int(pk.state[i]):
				PickupSystem.REST: row.rest += 1
				PickupSystem.MAGNET: row.magnet += 1
				_: row.air += 1
		minute[m] = row
	print("profile_run: %s seed %d, %s, %d timed ticks from %.0f s to %.0f s (state %s, wall %.1f s)" % [stage,
		seed_value, "pet " + str(w.pet) if w.pet_system != null else "no pet", ticks, from, w.time, w.state_name(),
		(Time.get_ticks_msec() - t_start) / 1000.0])
	if ticks == 0:
		quit(1)
		return
	var parts_sum := 0
	for v in acc:
		parts_sum += v
	print("step %.1f us/tick (parts %.1f, timer overhead %.1f); bot decide %.1f us/tick (outside the step)" % [
		float(step_us) / ticks, float(parts_sum) / ticks, float(step_us - parts_sum) / ticks, float(bot_us) / ticks])
	var order := range(PARTS.size())
	order.sort_custom(func(a: int, b: int) -> bool: return acc[a] > acc[b])
	for k: int in order:
		print("  %-16s %8.1f us/tick  %5.1f%%" % [PARTS[k], float(acc[k]) / ticks, 100.0 * acc[k] / maxf(1.0, parts_sum)])
	print("minute  alive   drops (exp meso equip potion | rest air magnet)  slots walked")
	var keys := minute.keys()
	keys.sort()
	for m: int in keys:
		var r: Dictionary = minute[m]
		var n := float(r.n)
		print("%4d:00 %6.1f %7.1f (%5.1f %6.1f %4.1f %4.1f | %6.1f %4.1f %4.1f) %7.1f" % [m, r.alive / n, r.drops / n,
			r.exp / n, r.meso / n, r.equip / n, r.potion / n, r.rest / n, r.air / n, r.magnet / n, r.hi / n])
	print("job %d, level %d, skills %s; MP-short ticks %d of %d, runner %.1f us/tick in them, %.1f in the others" % [
		w.progression.job_id, w.progression.level, w.loadout.order, wait_ticks, ticks,
		float(wait_us) / maxf(1.0, wait_ticks),
		float(acc[10] - wait_us) / maxf(1.0, ticks - wait_ticks)])
	print("collected: exp %d, mesos %d, equips %d, kills %d" % [w.pickups.collected_exp, w.mesos, w.equips_collected,
		w.kills])
	quit()


## RunWorld.step, part by part, adding each part's microseconds to acc (indexed like PARTS).
static func _timed_step(w: RunWorld, dt: float, input: MoveInput, acc: PackedInt64Array) -> void:
	if w.state != RunWorld.PLAYING:
		return
	w.time += dt
	w.refresh_player_speed()
	var t := Time.get_ticks_usec()
	w._step_player(dt, input)
	t = _lap(acc, 0, t)
	w._ctx.target = w.player.pos
	w._ctx.target_fh = w.player.fh
	w._ctx.speed_mult = w.director.value_at("speed", w.time)
	w._ctx["boss_actions"] = w.mob_actions.view(w.bosses.prepare_actions(w), w.bosses, w.swarm, w.time)
	w._ctx["events"] = w.events
	w.swarm.step(dt, w._ctx)
	t = _lap(acc, 1, t)
	w.bosses.step(w, dt)
	t = _lap(acc, 2, t)
	w.mob_skills.step(w)
	t = _lap(acc, 3, t)
	w.boss_attacks.step(w)
	t = _lap(acc, 4, t)
	w.mob_attacks.step(w, dt)
	t = _lap(acc, 5, t)
	w.mob_projectiles.step(dt, w)
	t = _lap(acc, 6, t)
	w.director.step(dt, w)
	t = _lap(acc, 7, t)
	w._sync_slots()
	t = _lap(acc, 8, t)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active, w.swarm.capacity())
	t = _lap(acc, 9, t)
	w.runner.step(dt, w)
	t = _lap(acc, 10, t)
	w.basic.step(dt, w)
	t = _lap(acc, 11, t)
	w._fill_live_defense()
	t = _lap(acc, 12, t)
	w.projectiles.step(dt, w.swarm, w.mob_grid, w.events, w._live_mdd, w._live_physical_allowed, w._on_player_hit)
	t = _lap(acc, 13, t)
	for m in w.projectiles.kills:
		w._on_kill(m)
	t = _lap(acc, 14, t)
	if w.pet_system != null:
		w._step_pet(dt)
	t = _lap(acc, 15, t)
	var got := w._step_pickups(dt)
	t = _lap(acc, 16, t)
	w._touch()
	t = _lap(acc, 17, t)
	if got > 0 and not w._dead:
		w._gain_exp(got)
	t = _lap(acc, 18, t)
	w._write_player_state(dt)
	t = _lap(acc, 19, t)
	w._end_tick()
	_lap(acc, 20, t)


static func _lap(acc: PackedInt64Array, part: int, t0: int) -> int:
	var t1 := Time.get_ticks_usec()
	acc[part] += t1 - t0
	return t1
