extends SceneTree
## Headless per-system profile of RunWorld.step in a real round (issue #146): plays a stage with the sensible autoplay
## bot (BotInput.decide, BotInput.pick_card_for, BotShop.equip_after: the round RunScene's autoplay and balance_run
## play) untimed up to --from, then times every part of the tick separately until --to (or the end of the round) and
## prints each part's share of the step, with the alive mobs and the drop pool (by kind and state) per minute. Needs
## the asset cache (the real map and mob/skill imgs).
##
##   bash scripts/godot.sh --headless --path game --script res://tools/profile_run.gd -- --seed=5 --from=780 --to=900
##       [--stage=henesys] [--account=<abs AccountFile JSON>] [--job=<id>] [--mortal]
##
## The player is in god mode (RunWorld.god: no damage) so the bot reaches the late, crowded minutes; --mortal turns it
## off (the round then ends where the bot dies).
## The timed tick calls RunWorld.step with a stage observer: the same production code owns every subsystem call.
## The breakdown follows its coarse stages (monsters, player attacks, etc.), including all follow-up work.
## Timings are wall-clock on this machine (Time.get_ticks_usec around each part, which adds a little
## overhead per part); compare shares, and raw numbers only on a quiet machine.

const BR := preload("res://tools/balance_run.gd")
const DT := 1.0 / 60.0
const PARTS := RunWorld.STEP_PARTS


func _init() -> void:
	var stage := "henesys"
	var seed_value := 2026
	var from := 780.0
	var to := 1020.0
	var account_file := ""
	var forced_job := 0
	var god := true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stage="):
			stage = DataRepo.canonical_stage_key(a.substr(8))
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
		if w.transfer_pending:
			w.advance_map()
		if w.state != RunWorld.PLAYING:
			break
		var b0 := Time.get_ticks_usec()
		var input := BotInput.decide(w, memo)
		var b1 := Time.get_ticks_usec()
		if w.time < from:
			w.step(DT, input)
			if w.transfer_pending:
				w.advance_map()
			BotShop.equip_after(w, w.drain_events())
			continue
		bot_us += b1 - b0
		var s0 := Time.get_ticks_usec()
		var attacks0 := acc[2]
		_timed_step(w, DT, input, acc)
		if w.runner.waiting_mp:
			wait_ticks += 1
			wait_us += acc[2] - attacks0
		step_us += Time.get_ticks_usec() - s0
		BotShop.equip_after(w, w.drain_events())  # the bot wears its best drops, as RunScene and balance_run do
		ticks += 1
		var m := int(w.time / 60.0)
		var row: Dictionary = minute.get(m, {"n": 0, "alive": 0, "drops": 0, "exp": 0, "meso": 0, "equip": 0,
			"rest": 0, "magnet": 0, "air": 0, "hi": 0})
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
	print("minute  alive   drops (exp meso equip | rest air magnet)  slots walked")
	var keys := minute.keys()
	keys.sort()
	for m: int in keys:
		var r: Dictionary = minute[m]
		var n := float(r.n)
		print("%4d:00 %6.1f %7.1f (%5.1f %6.1f %4.1f | %6.1f %4.1f %4.1f) %7.1f" % [m, r.alive / n, r.drops / n,
			r.exp / n, r.meso / n, r.equip / n, r.rest / n, r.air / n, r.magnet / n, r.hi / n])
	print("job %d, level %d, skills %s; MP-short ticks %d of %d, player attacks %.1f us/tick in them, %.1f in the others" % [
		w.progression.job_id, w.progression.level, w.loadout.order, wait_ticks, ticks,
		float(wait_us) / maxf(1.0, wait_ticks),
		float(acc[2] - wait_us) / maxf(1.0, ticks - wait_ticks)])
	print("collected: exp %d, mesos %d, equips %d, kills %d" % [w.pickups.collected_exp, w.mesos, w.equips_collected,
		w.kills])
	quit()


## Times the actual production stages; no copied simulation order or arguments live in this tool.
static func _timed_step(w: RunWorld, dt: float, input: MoveInput, acc: PackedInt64Array) -> void:
	var timer := StageTimer.new(acc)
	w.step(dt, input, timer.lap)
	if w.transfer_pending:
		w.advance_map()


class StageTimer extends RefCounted:
	var _acc: PackedInt64Array
	var _last: int
	func _init(acc: PackedInt64Array) -> void:
		_acc = acc
		_last = Time.get_ticks_usec()
	func lap(part: String) -> void:
		var now := Time.get_ticks_usec()
		_acc[PARTS.find(part)] += now - _last
		_last = now
