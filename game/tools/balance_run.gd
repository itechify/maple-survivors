extends SceneTree
## Headless pacing report for balance tuning (docs/GAME_DESIGN.md 4.1, 4.2, 5): plays whole runs of a stage on the real
## map with the kiting autoplay bot (BotInput.decide: kiting, walking and climbing to drops) and a card policy, and
## prints when the run reached each level milestone, the alive mobs, levels and hits taken per minute (alive = the mean
## over the minute, so burst spikes do not dominate), the mean number of mobs near the player (within NEAR_X px
## horizontally and NEAR_Y px vertically), the swarm engagement (below), the mean EXP drops lying on the map, mobs
## recycled and relocated per minute, the lowest HP fraction per minute, EXP lost to expired drops, and how it ended.
## Needs the asset cache (the real map and mob/skill imgs).
##
## Engagement (docs/GAME_DESIGN.md 4.2): `eng_by_min[m-1]` is the share of the live mobs within ENG_X px horizontally
## and ENG_Y px vertically of the player's feet over the minute centred on m:00 (sum of engaged mobs / sum of live mobs
## over every tick of [m:00 - 30 s, m:00 + 30 s), the last window cut at the run's end); `stale_by_min` is the share,
## over the same windows, of live mobs that have been outside that box for STALE_S s or more in a row (since their
## spawn or their last time inside it; a relocated mob keeps its time, mob_spawned.relocated_from): the idle queues,
## including mobs that idle off-screen until SpawnDirector relocates them.
##
##   bash scripts/balance.sh                       # henesys_hg1, the held-out seeds, in parallel
##   bash scripts/balance.sh 7 11 --stage=tree_that_grew_1
##   godot --headless --path game --script res://tools/balance_run.gd -- --seed=7 [--stage=henesys_hg1]
##       [--patch=<abs path of a JSON patch>] [--policy=bot|random|first] [--idle-after=<s>]
##
## Card policies (jobs: always the first available job, as BotInput.pick_job):
##   bot     BotInput.pick_card_for: the card a sensible player takes (the policy RunScene's autopick uses).
##   random  a careless player: a seeded random card of the three offered (its own RNG, so the sim's streams are the
##           same as with any other policy until the choices differ). This is the "careless player" of the tuning
##           record; it does not favour the first slot, where UpgradePool puts a guaranteed card.
##   first   always the first card offered (--first-card is the same). Not a random player: guaranteed cards (the
##           Magician's Energy Bolt, pity cards) are always drawn first, so this policy always takes them.
##
## --idle-after=S: from S seconds of run time on the player stops moving (hands off the keys; cards are still chosen).
## --patch: a JSON object deep-merged into the loaded data before the run (keys as in setup.data: "balance",
## "stages", "skills", ...; see deep_merge), to try tuning variants without editing game/data.
## One "BALANCE {json}" line per run (scripts/balance.sh tabulates them) plus a readable summary.

const DT := 1.0 / 60.0
const MILESTONES := [8, 10, 20, 30, 40, 50]
## "Near the player" box for the engagement metric (px from the player's feet).
const NEAR_X := 300.0
const NEAR_Y := 150.0
## Engagement box and the "stale" age (see the class doc).
const ENG_X := 400.0
const ENG_Y := 200.0
const STALE_S := 20.0
const POLICIES := ["bot", "random", "first"]


func _init() -> void:
	var stage := "henesys_hg1"
	var seeds: Array[int] = []
	var patch_file := ""
	var policy := "bot"
	var idle_after := -1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stage="):
			stage = a.substr(8)
		elif a.begins_with("--patch="):
			patch_file = a.substr(8)
		elif a == "--first-card":
			policy = "first"
		elif a.begins_with("--policy="):
			policy = a.substr(9)
		elif a.begins_with("--idle-after="):
			idle_after = float(a.substr(13))
		elif a.begins_with("--seed="):
			seeds.append(int(a.substr(7)))
		elif a.is_valid_int():
			seeds.append(int(a))
	if not (policy in POLICIES):
		print("balance_run: unknown --policy=%s (%s)" % [policy, POLICIES])
		quit(2)
		return
	if seeds.is_empty():
		seeds = [101]
	var data := DataRepo.load_all()
	if patch_file != "":
		var patch: Variant = JSON.parse_string(FileAccess.get_file_as_string(patch_file))
		if not (patch is Dictionary):
			print("balance_run: cannot read the patch %s" % patch_file)
			quit(1)
			return
		deep_merge(data, patch)
	var missing := PackedStringArray()
	var root := AssetCachePaths.resolve_cache_root()
	var setup_base := DataRepo.build_setup(data, stage, 0, Vector2(800, 600),
		func(p: String) -> Dictionary: return _json(root, p),
		func(id: int) -> Dictionary: return _json(root, "Mob.wz/%07d.img" % id),
		missing)
	if not missing.is_empty() or setup_base.get("map_img", {}).is_empty():
		print("balance_run: the asset cache lacks %s (root %s)" % [missing, root])
		quit(1)
		return
	for s in seeds:
		var setup := setup_base.duplicate()
		setup.seed = s
		var r := run_one(RunWorld.new(setup), policy, s, idle_after)
		r["seed"] = s
		r["stage"] = stage
		r["policy"] = policy
		print("BALANCE " + JSON.stringify(r))
		print(describe(r))
	quit()


## Answers an open job / card window of `w` with `policy` (see the class doc); `rng` drives the random policy.
static func choose(w: RunWorld, policy: String, rng: RandomNumberGenerator, cards_taken: Array) -> void:
	var guard := 0
	while guard < 64 and (w.state == RunWorld.CHOOSING_JOB or w.state == RunWorld.CHOOSING_UPGRADE):
		guard += 1
		if w.state == RunWorld.CHOOSING_JOB:
			var job := BotInput.pick_job(w.pending_jobs)
			if job < 0 or not w.apply_job(job):
				w.decline_job()
			continue
		var id := ""
		match policy:
			"random":
				id = String(w.pending_cards[rng.randi_range(0, w.pending_cards.size() - 1)].get("id", ""))
			"first":
				id = BotInput.pick_card(w.pending_cards)
			_:
				id = BotInput.pick_card_for(w, w.pending_cards)
		cards_taken.append("%d:%s" % [w.progression.front(), id])
		w.apply_choice(id)


## Plays `w` to its end with the kiting bot and card policy `policy` and returns the pacing record.
static func run_one(w: RunWorld, policy := "bot", seed_value := 0, idle_after := -1.0) -> Dictionary:
	var memo := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("careless-%d" % seed_value)
	var cards_taken: Array = []
	var reach := {}
	var alive_min: Array = []
	var level_min: Array = []
	var hits_min: Array = []
	var taken_min: Array = []
	var exp_min: Array = []
	var kills_min: Array = []
	var near_min: Array = []
	var drops_min: Array = []
	var exp_total := 0
	var recycled_min: Array = []
	var hp_min: Array = []
	# Engagement: 30 s buckets of engaged / stale / live mob-ticks, and per slot the last time inside the box.
	var eng_b := PackedInt64Array()
	var stale_b := PackedInt64Array()
	var live_b := PackedInt64Array()
	var nb := int(ceil(w.duration / 30.0)) + 2
	eng_b.resize(nb)
	stale_b.resize(nb)
	live_b.resize(nb)
	var seen := PackedFloat32Array()
	var relocated0 := 0
	var relocated_min: Array = []
	var alive_sum := 0
	var near_sum := 0
	var drops_sum := 0
	var alive_n := 0
	var recycled0 := 0
	var hp_low := 1.0
	var hits := 0
	var taken := 0
	var max_alive := 0
	var max_alive_t := 0.0
	var job_t := -1.0
	var ticks := int(round(w.duration / DT)) + 1
	var next_min := 60.0
	var low_hp := 1.0
	for t in ticks:
		choose(w, policy, rng, cards_taken)
		if w.state != RunWorld.PLAYING:
			break
		var idle := idle_after >= 0.0 and w.time >= idle_after
		w.step(DT, MoveInput.new() if idle else BotInput.decide(w, memo))
		var a := w.swarm.alive_count()
		alive_sum += a
		near_sum += _near(w)
		var bk := mini(int(w.time / 30.0), nb - 1)
		var ec := _engaged(w, seen)
		eng_b[bk] += ec.x
		stale_b[bk] += ec.y
		live_b[bk] += a
		drops_sum += w.pickups.exp_count()
		alive_n += 1
		hp_low = minf(hp_low, float(w.player_state.hp) / maxf(1.0, float(w.player_state.max_hp)))
		if a > max_alive:
			max_alive = a
			max_alive_t = w.time
		if w.time > 60.0:
			low_hp = minf(low_hp, float(w.player_state.hp) / maxf(1.0, float(w.player_state.max_hp)))
		for e: Dictionary in w.drain_events():
			match String(e.type):
				"mob_spawned":
					# A relocated mob is the same mob: it keeps the time it was last inside the box.
					var ms := int(e.mob)
					var from := int(e.get("relocated_from", -1))
					if seen.size() <= maxi(ms, from):
						seen.resize(w.swarm.capacity())
					seen[ms] = seen[from] if from >= 0 else w.time
				"player_hit":
					hits += 1
					taken += int(e.damage)
				"pickup_collected":
					exp_total += int(e.exp)
				"level_up":
					var lv := int(e.level)
					if lv in MILESTONES and not reach.has(str(lv)):
						reach[str(lv)] = snappedf(w.time, 0.1)
				"job_changed":
					job_t = snappedf(w.time, 0.1)
		if w.time >= next_min - 1e-6:
			next_min += 60.0
			var n := maxi(1, alive_n)
			alive_min.append(roundi(float(alive_sum) / n))
			near_min.append(snappedf(float(near_sum) / n, 0.1))
			drops_min.append(roundi(float(drops_sum) / n))
			alive_sum = 0
			near_sum = 0
			drops_sum = 0
			alive_n = 0
			recycled_min.append(w.director.recycled - recycled0)
			recycled0 = w.director.recycled
			relocated_min.append(w.director.relocated - relocated0)
			relocated0 = w.director.relocated
			hp_min.append(snappedf(hp_low, 0.01))
			hp_low = 1.0
			level_min.append(int(w.player_state.level))
			hits_min.append(hits)
			taken_min.append(taken)
			exp_min.append(exp_total)
			kills_min.append(w.kills)
			hits = 0
			taken = 0
	choose(w, policy, rng, cards_taken)
	var eng_min: Array = []
	var stale_min: Array = []
	for m in range(1, int(w.duration / 60.0) + 1):
		var lv := live_b[2 * m - 1] + live_b[2 * m]
		eng_min.append(snappedf(float(eng_b[2 * m - 1] + eng_b[2 * m]) / lv, 0.01) if lv > 0 else -1.0)
		stale_min.append(snappedf(float(stale_b[2 * m - 1] + stale_b[2 * m]) / lv, 0.01) if lv > 0 else -1.0)
	var skills := {}
	for key: String in w.loadout.order:
		skills[key] = w.loadout.rank(key)
	return {
		"state": w.state_name(), "time": snappedf(w.time, 0.1), "level": int(w.player_state.level),
		"job": int(w.player_state.job_id), "job_t": job_t, "kills": w.kills, "reach": reach,
		"alive_by_min": alive_min, "level_by_min": level_min, "hits_by_min": hits_min, "taken_by_min": taken_min,
		"exp_by_min": exp_min, "kills_by_min": kills_min, "recycled_by_min": recycled_min, "low_hp_by_min": hp_min,
		"near_by_min": near_min, "drops_by_min": drops_min, "expired_exp": w.pickups.expired_exp,
		"expired_drops": w.pickups.expired, "exp_collected": w.pickups.collected_exp,
		"potions_collected": w.potions.collected.duplicate(), "potions_used": w.potions.used.duplicate(),
		"spawned": w.director.spawned, "recycled": w.director.recycled, "relocated": w.director.relocated,
		"relocated_by_min": relocated_min, "eng_by_min": eng_min, "stale_by_min": stale_min,
		"max_alive": max_alive, "max_alive_t": snappedf(max_alive_t, 1.0), "low_hp_after_1min": snappedf(low_hp, 0.01),
		"skills": skills, "cards": w.loadout.card_ranks.duplicate(), "cards_taken": cards_taken,
	}


## Live mobs within NEAR_X px horizontally and NEAR_Y px vertically of the player's feet.
static func _near(w: RunWorld) -> int:
	var s := w.swarm
	var p := w.player.pos
	var n := 0
	for i in s.capacity():
		if s.active[i] != 0 and absf(s.x[i] - p.x) <= NEAR_X and absf(s.y[i] - p.y) <= NEAR_Y:
			n += 1
	return n


## Vector2i(engaged, stale): live mobs inside the ENG_X x ENG_Y box around the player's feet, and live mobs outside it
## for STALE_S s or more (seen[slot] = the last time the mob in that slot was inside the box or spawned; updated here).
static func _engaged(w: RunWorld, seen: PackedFloat32Array) -> Vector2i:
	var s := w.swarm
	var p := w.player.pos
	if seen.size() < s.capacity():
		seen.resize(s.capacity())
	var eng := 0
	var stale := 0
	for i in s.capacity():
		if s.active[i] == 0:
			continue
		if absf(s.x[i] - p.x) <= ENG_X and absf(s.y[i] - p.y) <= ENG_Y:
			eng += 1
			seen[i] = w.time
		elif w.time - seen[i] >= STALE_S:
			stale += 1
	return Vector2i(eng, stale)


## Merges `patch` into `into`: Dictionaries key by key (recursively); an Array of Dictionaries onto an Array of the
## same length element by element (null elements keep the original), so a keyframe patch may list only the fields it
## changes; any other value replaces.
static func deep_merge(into: Dictionary, patch: Dictionary) -> void:
	for k: Variant in patch:
		var pv: Variant = patch[k]
		var iv: Variant = into.get(k)
		if pv is Dictionary and iv is Dictionary:
			deep_merge(iv, pv)
		elif pv is Array and iv is Array and (pv as Array).size() == (iv as Array).size():
			for i in (pv as Array).size():
				if pv[i] is Dictionary and iv[i] is Dictionary:
					deep_merge(iv[i], pv[i])
				elif pv[i] != null:
					iv[i] = pv[i]
		else:
			into[k] = pv


## A readable multi-line summary of one record.
static func describe(r: Dictionary) -> String:
	var reach: Dictionary = r.reach
	var parts := PackedStringArray()
	for lv: int in MILESTONES:
		parts.append("Lv%d %s" % [lv, _mmss(float(reach.get(str(lv), -1.0)))])
	var head := "seed %d (%s): %s at %s, Lv %d, job %d (at %s), kills %d, max alive %d at %s, lowest HP %d%%" % [
		int(r.seed), String(r.get("policy", "bot")), r.state, _mmss(float(r.time)), int(r.level), int(r.job),
		_mmss(float(r.job_t)), int(r.kills), int(r.max_alive), _mmss(float(r.max_alive_t)),
		roundi(float(r.low_hp_after_1min) * 100.0)]
	var lines := PackedStringArray([head, "  " + "  ".join(parts),
		"  EXP collected %d, expired %d (%d drops)" % [int(r.exp_collected), int(r.expired_exp), int(r.expired_drops)]])
	for k: String in ["alive_by_min", "near_by_min", "eng_by_min", "stale_by_min", "drops_by_min", "level_by_min",
			"hits_by_min", "low_hp_by_min",
			"exp_by_min", "kills_by_min", "recycled_by_min", "relocated_by_min"]:
		lines.append("  %-16s %s" % [k, r.get(k, [])])
	lines.append("  cards %s" % [r.get("cards_taken", [])])
	return "\n".join(lines)


static func _mmss(t: float) -> String:
	if t < 0.0:
		return "--:--"
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


static func _json(root: String, path: String) -> Dictionary:
	var file := root.path_join(path + ".json")
	if not FileAccess.file_exists(file):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	return d if d is Dictionary else {}
