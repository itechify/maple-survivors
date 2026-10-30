extends SceneTree
## Headless pacing report for balance tuning (docs/GAME_DESIGN.md 4.1, 4.2, 5): plays whole rounds across a stage's real
## maps with the kiting autoplay bot (BotInput.decide: kiting, walking and climbing to drops) and a card policy, and
## prints when the run reached each level milestone, the alive mobs, levels and hits taken per minute (alive = the mean
## over the minute, so burst spikes do not dominate), the mean number of mobs near the player (within NEAR_X px
## horizontally and NEAR_Y px vertically), the swarm engagement (below), the mean EXP drops lying on the map, mobs
## recycled and relocated per minute, the lowest HP fraction per minute, EXP lost to expired drops, and how it ended.
## Also records per-boss fight duration and whole boss-hit fractions. Potion metrics are player-only
## potions_used {hp} and potion_uses [{time, level, kind, item_id, restored, capacity_waste}]; a pet adds its own
## pet.potions_used {hp}. There is no MP (ADR 0006), so no MP-short or MP-absorbed fields. SYSTEMS sums player
## drinks only. Unlimited potions have no collection/stock metrics.
## Second life (#375, docs/GAME_DESIGN.md 7.81): `revives` [{t, level, rank, source_kind, hp}] lists each time a lethal hit
## was turned into a survived one and `revive_count` is its length; the report prints the count per run and SUMMARY
## `revived n/runs` (runs with at least one). A world without a reaction skill records `[]` / 0.
## Three-map schema: map_times = reached-map entry seconds from round start, starting [0.0]; ended_map =
## {index: zero-based map index, id: original v83 map id}. boss_fights[] retains map_index/map_id even for unspawned
## bosses. SUMMARY deaths_by_map uses one-based string keys; map_entry_seconds["2"/"3"] has count/min/median/max/mean
## over reached maps only (null stats when unobserved). Legacy records contribute no invented map observations.
## Stage keys: henesys/ellinia/sleepywood; henesys_hg1/tree_that_grew_1/dark_cave remain aliases, including --tier
## chains and --character one-offs. Camper activation/arrival/portals refer only to its own map 1; later maps use bot.
## Needs the asset cache (the real map and mob/skill imgs).
##
## Engagement (docs/GAME_DESIGN.md 4.2): `eng_by_min[m-1]` is the share of the live mobs within ENG_X px horizontally
## and ENG_Y px vertically of the player's feet over the minute centred on m:00 (sum of engaged mobs / sum of live mobs
## over every tick of [m:00 - 30 s, m:00 + 30 s), the last window cut at the run's end); `stale_by_min` is the share,
## over the same windows, of live mobs that have been outside that box for STALE_S s or more in a row (since their
## spawn or their last time inside it; a relocated mob keeps its time, mob_spawned.relocated_from): the idle queues,
## including mobs that idle off-screen until SpawnDirector relocates them.
##
##   bash scripts/balance.sh                       # henesys, training seeds 1..6, in parallel
##   bash scripts/balance.sh 7 11 --stage=ellinia
##   godot --headless --path game --script res://tools/balance_run.gd -- --seed=7 [--stage=henesys]
##       [--patch=<abs path of a JSON patch>] [--policy=bot|random|first] [--idle-after=<s>] [--job=<id>]
##
## --job=<id> names a fresh character's job (#284; the default is JobTree.default_job(), 212). A job this build cannot
## play, or one that differs from a --character's own job, fails at startup; --branch=<id> is the deprecated alias.
## Card policies:
##   bot     BotInput.pick_card_for: the card a sensible player takes (the policy RunScene's autopick uses).
##   random  a careless player: a seeded random card of the three offered (its own RNG, so the sim's streams are the
##           same as with any other policy until the choices differ). This is the "careless player" of the tuning
##           record; it does not favour the first slot, where UpgradePool puts a guaranteed card.
##   first   always the first card offered (--first-card is the same). Not a random player: guaranteed cards (pity
##           cards) are always drawn first, so this policy always takes them.
##
## Camper movement policies: camper_henesys_top, camper_henesys_rope, camper_tree_top (sensible cards/potions).
## --camp-after=S: begin parking after S seconds (default 60); Tree reaches its top branch through portals.
## --cap=S: report TIMEOUT at S seconds if still playing; only boss completion reports a clear.
## --idle-after=S: from S seconds of run time on the player stops moving (hands off the keys; cards are still chosen).
## --patch: a JSON object deep-merged into the loaded data before the run (keys as in setup.data: "balance",
## "stages", "skills", ...; see deep_merge), to try tuning variants without editing game/data.
## One "BALANCE {json}" line per run (scripts/balance.sh tabulates them) plus a readable summary.
## --character=<abs JSON path>: start this one-off round from a CharacterSnapshot; never writes a save.
## --account=<abs JSON path>: give the round an account (AccountFile: owned cash items, worn cash equipment, pet, ALERT
## levels; applied to the first round's character and carried through --tier chains). The record gets "account": <file
## name>. Without the flag the round has an empty account and the record is byte-identical to before; NX is never credited.
## --tier=N (N >= 2): chain from tier 1 through N using stages.json tiers; --stage selects tier 1 (default first).
## Later tiers take their first listed stage; --character and camper policies cannot be combined with --tier.
## Tier-1 round seed equals the run seed; later seeds are hash("balance-round-<run seed>-<zero-based tier>").
## Chain BALANCE records contain rounds[]; only CLEARED (including all rewards) feeds the next tier.

const DT := 1.0 / 60.0
const MILESTONES := [8, 10, 20, 30, 40, 50]
## "Near the player" box for the engagement metric (px from the player's feet).
const NEAR_X := 300.0
const NEAR_Y := 150.0
## Engagement box and the "stale" age (see the class doc).
const ENG_X := 400.0
const ENG_Y := 200.0
const STALE_S := 20.0
const CAMPER := preload("res://tools/camper_input.gd")
const POLICIES := ["bot", "random", "first", "camper_henesys_top", "camper_henesys_rope", "camper_tree_top"]
## tier C: harness timeout fallback; balance.run_time_cap and --cap override it.
const DEFAULT_RUN_CAP := 1800.0
## tier C measurement: ordinary hits per kill are reported for the first this-many run minutes.
const EARLY_MINUTES := 5
## The numeric fields of a round record's `shop` (the Free Market visit at its end) that aggregate() summarises.
const SHOP_FIELDS := ["sold", "sale_mesos", "spent", "bought", "used", "succeeded", "failed", "destroyed", "equipped",
	"scrolls_left", "mesos_after"]
const LEVEL_TARGET := 70 # tier C: spec #32 requested reach metric; no success/clear rule or tuning target.


## tier C measurement: landed lifetime hits per ordinary (non-elite, non-boss) kill, bucketed by the minute of the
## kill over the first EARLY_MINUTES. Lifetimes replay in event order, since swarm slots can already have been reused.
class KillHits:
	## One {hits, kills, mean} per early minute.
	var buckets: Array = empty_buckets()
	var _lifetimes := {}

	## One empty {hits, kills, mean} bucket per early minute (also the aggregate's starting point).
	static func empty_buckets() -> Array:
		var out: Array = []
		for minute in EARLY_MINUTES:
			out.append({"hits": 0, "kills": 0, "mean": null})
		return out

	## Updates lifetimes and buckets from one drained run event at run time `now`.
	func observe(e: Dictionary, w: RunWorld, now: float) -> void:
		var mob := int(e.get("mob", -1))
		match String(e.type):
			"mob_spawned":
				var from := int(e.get("relocated_from", -1))
				var lifetime: Dictionary = _lifetimes.get(from, {}).duplicate() if from >= 0 else {}
				_lifetimes.erase(from)
				if lifetime.is_empty():
					var kind: MobKind = w.mob_kinds[int(w.kind_of_id[int(e.mob_id)])]
					lifetime = {"hits": 0, "ordinary": not bool(e.elite) and not kind.boss}
				_lifetimes[mob] = lifetime
			"boss_spawned":
				if _lifetimes.has(mob):
					_lifetimes[mob].ordinary = false
			"mob_hit":
				if _lifetimes.has(mob):
					_lifetimes[mob].hits += 1
			"mob_died":
				var lifetime: Dictionary = _lifetimes.get(mob, {})
				var minute := maxi(0, floori((now - 1e-6) / 60.0))
				if minute < EARLY_MINUTES and bool(lifetime.get("ordinary", false)):
					buckets[minute].hits += int(lifetime.hits)
					buckets[minute].kills += 1
					buckets[minute].mean = float(buckets[minute].hits) / int(buckets[minute].kills)
				_lifetimes.erase(mob)


func _init() -> void:
	var stage := "henesys"
	var seeds: Array[int] = []
	var patch_file := ""
	var policy := "bot"
	var idle_after := -1.0
	var cap := -1.0
	var camp_after := 60.0
	var stage_explicit := false
	var forced_job := -2 # -2: no --job; -1: a malformed one
	var character_file := ""
	var has_character := false
	var account_file := ""
	var has_account := false
	var chain := false
	var target_tier := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stage="):
			stage = DataRepo.canonical_stage_key(a.substr(8))
			stage_explicit = true
		elif a.begins_with("--job="):
			forced_job = JobTree.parse_job(a.substr(6))
		elif a.begins_with("--branch="):
			printerr("balance_run: --branch is deprecated: use --job=<id>")
			forced_job = JobTree.parse_job(a.substr(9))
		elif a.begins_with("--patch="):
			patch_file = a.substr(8)
		elif a.begins_with("--character="):
			character_file = a.substr(12)
			has_character = true
		elif a.begins_with("--account="):
			account_file = a.substr(10)
			has_account = true
		elif a.begins_with("--tier="):
			chain = true
			target_tier = int(a.substr(7)) if a.substr(7).is_valid_int() else -1
		elif a == "--first-card":
			policy = "first"
		elif a.begins_with("--policy="):
			policy = a.substr(9)
		elif a.begins_with("--idle-after="):
			idle_after = float(a.substr(13))
		elif a.begins_with("--camp-after="):
			camp_after = float(a.substr(13))
		elif a.begins_with("--cap="):
			cap = float(a.substr(6))
		elif a.begins_with("--seed="):
			seeds.append(int(a.substr(7)))
		elif a.is_valid_int():
			seeds.append(int(a))
	if not (policy in POLICIES):
		print("balance_run: unknown --policy=%s (%s)" % [policy, POLICIES])
		quit(2)
		return
	if CAMPER.STAGES.has(policy):
		if stage_explicit and stage != CAMPER.STAGES[policy]:
			print("balance_run: policy %s requires stage %s" % [policy,CAMPER.STAGES[policy]])
			quit(2)
			return
		stage = CAMPER.STAGES[policy]
	if seeds.is_empty():
		seeds = [1] # tier C: training default; held-out runs are explicit after candidate freeze.
	var data := DataRepo.load_all()
	if patch_file != "":
		var patch: Variant = JSON.parse_string(FileAccess.get_file_as_string(patch_file))
		if not (patch is Dictionary):
			print("balance_run: cannot read the patch %s" % patch_file)
			quit(1)
			return
		deep_merge(data, patch)
	if forced_job != -2:
		var job_error := "not a job id" if forced_job < 0 \
			else DataRepo.jobs(data).job_error(forced_job)
		if job_error != "":
			print("balance_run: --job: " + job_error)
			quit(2)
			return
	if cap > 0.0:
		data.balance["run_time_cap"] = cap
	var tiers: Array = data.stages.get("tiers", [])
	if chain and (target_tier < 2 or target_tier > tiers.size() or has_character or CAMPER.STAGES.has(policy)):
		print("balance_run: --tier must be 2..%d; cannot combine with --character or camper policies" % tiers.size())
		quit(2)
		return
	if chain and not stage_explicit:
		stage = String(tiers[0][0])
	if not data.stages.stages.has(stage) or (chain and stage not in tiers[0]):
		print("balance_run: unknown stage or --tier requires a tier-1 --stage: " + stage)
		quit(2)
		return
	var stages: Array = [stage]
	if chain:
		for tier_index in range(1, target_tier):
			stages.append(String(tiers[tier_index][0]))
	var character := {}
	if has_character:
		var errors := PackedStringArray()
		character = DataRepo.load_character(character_file, errors)
		if not errors.is_empty():
			print("balance_run: " + "; ".join(errors))
			quit(1)
			return
		if forced_job >= 0 and int(character.get("job_id", -1)) != forced_job:
			print("balance_run: --job=%d does not match the character's job %d" % [forced_job, int(character.get("job_id", -1))])
			quit(2)
			return
	var account := {}
	if has_account:
		var account_errors := PackedStringArray()
		account = AccountFile.load_file(account_file, account_errors)
		if not account_errors.is_empty():
			print("balance_run: " + "; ".join(account_errors))
			quit(1)
			return
	var root := AssetCachePaths.resolve_cache_root()
	var setups: Array = []
	for stage_key: String in stages:
		var missing := PackedStringArray()
		var setup := DataRepo.build_setup(data, stage_key, 0, Vector2(800, 600),
			func(p: String) -> Dictionary: return _json(root, p),
			func(id: int) -> Dictionary: return _json(root, "Mob.wz/%07d.img" % id), missing, character)
		if not missing.is_empty() or setup.get("map_img", {}).is_empty():
			print("balance_run: the asset cache lacks %s for %s (root %s)" % [missing, stage_key, root])
			quit(1)
			return
		if has_character:
			setup.character = character
		elif forced_job >= 0:
			setup["job"] = forced_job
		setups.append(setup)
	if has_account:
		apply_account(setups, account)
	for s in seeds:
		var r: Dictionary
		if chain:
			r = run_chain(setups, policy, s, idle_after, camp_after)
		else:
			var setup: Dictionary = setups[0].duplicate()
			setup.seed = s
			var world := RunWorld.new(setup)
			var start_character := world.character_snapshot()
			r = run_one(world, policy, s, idle_after, camp_after)
			r.merge({"seed": s, "stage": stage, "policy": policy, "start_character": start_character, "missing": []})
			for tier_index in tiers.size():
				if stage in tiers[tier_index]:
					r["tier"] = tier_index + 1
		if has_account:
			r["account"] = account_file.get_file() # spec #34: the record names the account file; absent without the flag.
		print("BALANCE " + JSON.stringify(r))
		print(describe(r))
	quit()


## Puts a normalised tool account (AccountFile) on every prepared round setup. The worn cash equipment and pet go on
## the first round's character only; later tiers carry the character from the clear, which keeps them.
static func apply_account(setups: Array, account: Dictionary) -> void:
	var later := account.duplicate()
	later.erase("cash")
	later.erase("pet")
	for index in setups.size():
		AccountFile.apply(setups[index], account if index == 0 else later)


## Stable round stream by run seed and zero-based tier; tier 1 preserves existing regression seeds.
static func round_seed(run_seed: int, tier_index: int) -> int:
	# tier C: harness stream namespace, independent of card/job/combat RNG consumption in earlier rounds.
	return run_seed if tier_index == 0 else hash("balance-round-%d-%d" % [run_seed, tier_index])


## Plays prepared tier setups in order, carrying a boundary snapshot only after CLEARED; no menu/save dependency.
static func run_chain(setups: Array, policy: String, run_seed: int, idle_after := -1.0,
		camp_after := 60.0) -> Dictionary:
	var rounds: Array = []
	var carried: RunWorld = null
	for tier_index in setups.size():
		var setup: Dictionary = setups[tier_index].duplicate()
		setup.seed = round_seed(run_seed, tier_index)
		var world := carried if carried != null else RunWorld.new(setup)
		var start_character := world.character_snapshot()
		var record := run_one(world, policy, int(setup.seed), idle_after, camp_after)
		record["start_character"] = start_character
		record.merge({"seed": setup.seed, "stage": setup.stage, "policy": policy, "tier": tier_index + 1, "missing": []})
		rounds.append(record)
		if record.state != "CLEARED":
			break
		carried = null
		if tier_index + 1 < setups.size():
			# The Free Market between the tiers (spec #33, #112): the next round's world, built from the boundary snapshot,
			# visits the shops before it plays. Its scroll rolls follow that round's seed; the careless plan draws from
			# its own stream.
			var next_setup: Dictionary = setups[tier_index + 1].duplicate()
			next_setup.seed = round_seed(run_seed, tier_index + 1)
			next_setup.character = record.character
			carried = RunWorld.new(next_setup)
			var shop_rng := RandomNumberGenerator.new()
			shop_rng.seed = hash("careless-shop-%d-%d" % [run_seed, tier_index])
			record["shop"] = BotShop.visit(carried, policy, shop_rng)
			carried.drain_events()
	return {"mode": "chain", "seed": run_seed, "stage": setups[0].stage, "policy": policy,
		"target_tier": setups.size(), "rounds": rounds}


## Answers an open card window of `w` with `policy` (see the class doc); `rng` drives the random policy.
static func choose(w: RunWorld, policy: String, rng: RandomNumberGenerator, cards_taken: Array) -> void:
	var guard := 0
	while guard < 64 and w.state == RunWorld.CHOOSING_UPGRADE:
		guard += 1
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


## Plays `w` to its end/cap with movement/card policy `policy` and returns the pacing record.
static func run_one(w: RunWorld, policy := "bot", seed_value := 0, idle_after := -1.0, camp_after := 60.0) -> Dictionary:
	var memo := {}
	var portal_names: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("careless-%d" % seed_value)
	var cards_taken: Array = []
	var six_actives_at := -1.0
	var boss_hits: Array = []
	# #76: landed ordinary mob attack hits (recorded only when nonzero).
	var mob_attack_hits := 0
	var buff_casts: Array = []
	var potion_uses: Array = []
	var reach := {}
	var alive_min: Array = []
	var level_min: Array = []
	var hits_min: Array = []
	var taken_min: Array = []
	var exp_min: Array = []
	var kills_min: Array = []
	var kill_hits := KillHits.new()
	var near_min: Array = []
	var drops_min: Array = []
	var exp_total := 0
	var recycled_min: Array = []
	var hp_min: Array = []
	# Engagement: 30 s buckets of engaged / stale / live mob-ticks, and per slot the last time inside the box.
	var eng_b := PackedInt64Array()
	var stale_b := PackedInt64Array()
	var live_b := PackedInt64Array()
	var cap := maxf(DT, float(w.balance.get("run_time_cap", DEFAULT_RUN_CAP)))
	var nb := int(ceil(cap / 30.0)) + 2
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
	var equips_worn := 0
	var teleports := 0
	var taken := 0
	var max_alive := 0
	var max_alive_t := 0.0
	var ticks := maxi(0, ceili((cap - w.time) / DT - 1e-6))
	var next_min := 60.0
	var low_hp := 1.0
	for t in ticks + 1: # drain the final choice-only settlement too, without adding a combat/measurement tick
		choose(w, policy, rng, cards_taken)
		if six_actives_at < 0.0 and w.loadout.slot_count("active") == 6:
			six_actives_at = w.time
		if w.transfer_pending:
			w.advance_map()
		var ticked := w.state == RunWorld.PLAYING and t < ticks
		if ticked:
			var idle := idle_after >= 0.0 and w.time >= idle_after
			w.step(DT, MoveInput.new() if idle else movement(w, policy, memo, camp_after))
			if w.transfer_pending:
				w.advance_map()
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
		var events := w.drain_events()
		# Mid-round equipping (spec #33, #112): not a decision point, no RNG; changes stats before the next tick.
		equips_worn += BotShop.equip_after(w, events)
		for e: Dictionary in events:
			kill_hits.observe(e, w, w.time)
			match String(e.type):
				"teleport":
					if String(e.phase) == "arrival":
						teleports += 1
				"mob_spawned":
					# A relocated mob is the same mob: it keeps the time it was last inside the box.
					var ms := int(e.mob)
					var from := int(e.get("relocated_from", -1))
					if seen.size() <= maxi(ms, from):
						seen.resize(w.swarm.capacity())
					seen[ms] = seen[from] if from >= 0 else w.time
				"buff_cast":
					# Tier C measurement: event-observation tick; normal runs drain each step.
					var cast := {"time": w.time, "skill": String(e.skill), "skill_id": int(e.skill_id),
						"level": int(e.level), "duration": float(e.duration), "effect_stat": "", "value": 0.0}
					for buff: Dictionary in w.player_state.get("buffs", []):
						if String(buff.skill) == String(e.skill):
							cast.effect_stat = String(buff.effect_stat)
							cast.value = float(buff.value)
							break
					buff_casts.append(cast)
				"player_hit":
					if not bool(e.miss):
						hits += 1
						taken += int(e.damage)
						if String(e.get("source_kind", "")) == "mob_attack":
							mob_attack_hits += 1
						if bool(e.boss):
							boss_hits.append({"mob_id": int(e.mob_id), "time": w.time, "damage": int(e.damage),
								"max_hp": int(e.max_hp), "fraction": float(e.damage) / maxi(1, int(e.max_hp)),
								"source_kind": String(e.get("source_kind","other"))})
				"pickup_collected":
					exp_total += int(e.exp)
				"equipment_changed":
					if String(e.action) == "auto_equip": # worn by the sim at pickup (#222), counted with the bot's own wears
						equips_worn += 1
				"potion_used":
					var id := int(e.item_id)
					var item: Dictionary = w.potions.item_info.get(id, w.potions.item_info.get(str(id), {}))
					var amount := int(item.get("spec", {}).get(String(e.kind), 0))
					potion_uses.append({"time": w.time, "level": int(w.player_state.level), "kind": String(e.kind),
						"item_id": id, "restored": int(e.restored), "capacity_waste": maxi(0, amount - int(e.restored))})
				"portal_used":
					if w.map_index == 0:
						portal_names.append(String(e.portal))
				"level_up":
					var lv := int(e.level)
					if lv in MILESTONES and not reach.has(str(lv)):
						reach[str(lv)] = snappedf(w.time, 0.1)
		if not ticked:
			break
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
	var eng_min: Array = []
	var stale_min: Array = []
	for m in range(1, int(w.time / 60.0) + 1):
		var lv := live_b[2 * m - 1] + live_b[2 * m]
		eng_min.append(snappedf(float(eng_b[2 * m - 1] + eng_b[2 * m]) / lv, 0.01) if lv > 0 else -1.0)
		stale_min.append(snappedf(float(stale_b[2 * m - 1] + stale_b[2 * m]) / lv, 0.01) if lv > 0 else -1.0)
	var skills := {}
	for key: String in w.loadout.order:
		skills[key] = w.loadout.rank(key)
	var record := {
		"map_times": w.map_times.duplicate(), "ended_map": {"index": w.map_index, "id": w.current_map_id()},
		"lv70_reached": int(w.player_state.level) >= LEVEL_TARGET,
		"character": w.character_snapshot() if w.state == RunWorld.CLEARED else {},
		"state": "TIMEOUT" if w.state == RunWorld.PLAYING else w.state_name(),
		"timeout": w.state == RunWorld.PLAYING, "run_time_cap": cap,
		"bosses": _boss_snapshots(w), "boss_hits": boss_hits, "buff_casts": buff_casts,
		"boss_fights": fight_records(w), "boss_hit_fraction": statistics(boss_hits.map(func(hit: Dictionary) -> float: return float(hit.fraction))),
		"teleports": teleports,
		"camper": {"policy":policy if CAMPER.STAGES.has(policy) else "", "started_time":float(memo.get("started_time",-1.0)),
			"reached":bool(memo.get("reached",false)),"reached_time":float(memo.get("reached_time",-1.0)),"portals":portal_names},
		"time": snappedf(w.time, 0.1), "level": int(w.player_state.level),
		"job": int(w.player_state.job_id), "kills": w.kills, "reach": reach,
		"alive_by_min": alive_min, "level_by_min": level_min, "hits_by_min": hits_min, "taken_by_min": taken_min,
		"exp_by_min": exp_min, "kills_by_min": kills_min, "recycled_by_min": recycled_min, "low_hp_by_min": hp_min,
		"ordinary_kill_hits_by_min": kill_hits.buckets,
		"near_by_min": near_min, "drops_by_min": drops_min, "expired_exp": w.pickups.expired_exp,
		"expired_drops": w.pickups.expired, "exp_collected": w.pickups.collected_exp,
		"mesos_earned": w.pickups.collected_mesos, "mesos_total": w.mesos,
		"equips_dropped": w.equips_dropped, "equips_collected": w.equips_collected,
		"equips_worn": equips_worn, "equipment_worn": _worn_ids(w), "scrolls_on_worn": _scrolls_on_worn(w),
		"potions_used": w.potions.used.duplicate(),
		"potion_uses": potion_uses,
		"revives": w.revives.duplicate(true), "revive_count": w.revives.size(),
		"warnings": Array(w.warnings),
		"spawned": w.director.spawned, "recycled": w.director.recycled, "relocated": w.director.relocated,
		"relocated_by_min": relocated_min, "eng_by_min": eng_min, "stale_by_min": stale_min,
		"max_alive": max_alive, "max_alive_t": snappedf(max_alive_t, 1.0), "low_hp_after_1min": snappedf(low_hp, 0.01),
		"six_actives_at": six_actives_at, "picks": cards_taken.size(),
		"skills": skills, "cards": w.loadout.card_ranks.duplicate(), "cards_taken": cards_taken,
		# #115: what the round would pay (tier C placeholders); tools record it and never credit it or write a save.
		"nx_awarded": w.nx_awarded(), "bosses_killed": w.bosses_killed(), "levels_gained": w.levels_gained(),
		"card_tiers_offered": w.card_tiers_offered.duplicate(), "card_tiers_picked": w.card_tiers_picked.duplicate(),
	}
	if mob_attack_hits > 0:
		# #76: only rounds where an ordinary mob's attack landed record this, so other rounds keep their exact bytes.
		record["mob_attack_hits"] = mob_attack_hits
	if w.level_scale != null:
		# #453: only a stage with a level_scale records this, so other stages keep their exact bytes. The effective level at
		# each scheduled boss's arrival, in schedule order (bosses that never arrived are absent).
		record["level_scale_at"] = level_scale_arrivals(w)
	if w.pet_system != null:
		# #119: only a round with a pet out records one, so rounds without keep their exact bytes. Its drinks and pickups
		# are counted apart from the player's (potions_used stays the player's).
		record["pet"] = {"species": w.pet_system.species, "abilities": w.pet_system.abilities.duplicate(),
			"pickups": w.pet_system.pickups, "potions_used": w.potions.pet_used.duplicate(),
			"alert": w.alert.duplicate()}
	return record


## The worn equipment at this moment, {slot: item id}.
static func _worn_ids(w: RunWorld) -> Dictionary:
	var out := {}
	for slot: String in w.equipment.worn:
		out[slot] = int(w.equipment.worn[slot].id)
	return out


## Successful scrolls read onto the worn items, in total.
static func _scrolls_on_worn(w: RunWorld) -> int:
	var n := 0
	for instance: Dictionary in w.equipment.worn.values():
		n += int(instance.scrolls)
	return n


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
	DataRepo.merge_patch(into, patch, true)


## A readable multi-line summary of one record.
static func describe(r: Dictionary) -> String:
	if r.get("mode", "") == "chain":
		var lines := PackedStringArray(["CHAIN seed %d (%s): %d/%d rounds started" % [
			int(r.seed), String(r.policy), r.rounds.size(), int(r.target_tier)]])
		for record: Dictionary in r.rounds:
			lines.append("ROUND tier %d stage %s" % [int(record.tier), String(record.stage)])
			lines.append(describe(record))
		return "\n".join(lines)
	var reach: Dictionary = r.reach
	var parts := PackedStringArray()
	for lv: int in MILESTONES:
		parts.append("Lv%d %s" % [lv, _mmss(float(reach.get(str(lv), -1.0)))])
	var head := "seed %d (%s): %s at %s, Lv %d, job %d, kills %d, max alive %d at %s, lowest HP %d%%" % [
		int(r.seed), String(r.get("policy", "bot")), r.state, _mmss(float(r.time)), int(r.level), int(r.job),
		int(r.kills), int(r.max_alive), _mmss(float(r.max_alive_t)),
		roundi(float(r.low_hp_after_1min) * 100.0)]
	var lines := PackedStringArray([head, "  " + "  ".join(parts),
		"  EXP collected %d, expired %d (%d drops); mesos earned %d; equipment %d dropped, %d picked up" % [int(r.exp_collected), int(r.expired_exp),
			int(r.expired_drops), int(r.get("mesos_earned", 0)), int(r.get("equips_dropped", 0)), int(r.get("equips_collected", 0))]])
	lines.append("  equipment worn %s (%d put on mid-round, %d scrolls succeeded on it)" % [
		JSON.stringify(r.get("equipment_worn", {})), int(r.get("equips_worn", 0)), int(r.get("scrolls_on_worn", 0))])
	if r.has("shop"):
		var shop: Dictionary = r.shop
		lines.append(("  shop: mesos %d -> %d (earned this round %d; sold %d for %d, spent %d); scrolls bought %d, used %d "
			+ "(%d succeeded, %d failed, %d items destroyed), %d left; refused %s") % [
			int(shop.mesos_before), int(shop.mesos_after), int(r.get("mesos_earned", 0)), int(shop.sold),
			int(shop.sale_mesos), int(shop.spent), int(shop.bought), int(shop.used), int(shop.succeeded),
			int(shop.failed), int(shop.destroyed), int(shop.scrolls_left), shop.refused])
	for k: String in ["alive_by_min", "near_by_min", "eng_by_min", "stale_by_min", "drops_by_min", "level_by_min",
			"hits_by_min", "low_hp_by_min",
			"exp_by_min", "kills_by_min", "recycled_by_min", "relocated_by_min"]:
		lines.append("  %-16s %s" % [k, r.get(k, [])])
	lines.append("  NX awarded %d (bosses killed %d, levels gained %d)" % [int(r.get("nx_awarded", 0)),
		int(r.get("bosses_killed", 0)), int(r.get("levels_gained", 0))])
	lines.append("  boss fights %s" % [r.get("boss_fights",[])])
	lines.append("  potions used %s; boss-hit fractions %s" % [r.get("potions_used",{}),r.get("boss_hit_fraction",{})])
	lines.append("  second lives %d %s" % [int(r.get("revive_count", 0)), r.get("revives", [])])
	if r.has("pet"):
		lines.append("  pet %s" % [r.pet])
	lines.append("  camper %s" % [r.get("camper",{})])
	lines.append("  cards %s" % [r.get("cards_taken", [])])
	lines.append("  card tiers offered %s; picked %s" % [r.get("card_tiers_offered", {}), r.get("card_tiers_picked", {})])
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


static func _boss_snapshots(world: RunWorld) -> Array:
	var snapshots: Array = world.bosses.records.duplicate(true)
	for record: Dictionary in snapshots:
		# No route observation yet: preserve null in JSON without changing the live infinity sentinel.
		if not is_finite(float(record.get("best_distance", 0.0))):
			record.best_distance = null
	return snapshots


## [{boss_index, mob_id, level}] of the bosses that arrived, `level` being the level scale's effective level then.
static func level_scale_arrivals(world: RunWorld) -> Array:
	var arrivals: Array = []
	for record: Dictionary in world.bosses.records:
		if record.has("level_scale_at"):
			arrivals.append({"boss_index": int(record.boss_index), "mob_id": int(record.mob_id),
				"level": float(record.level_scale_at)})
	return arrivals


## Completed spawn-to-death durations; unfinished fights keep duration -1 and report elapsed/censor status.
static func fight_records(world: RunWorld) -> Array:
	var fights: Array = []
	for record: Dictionary in world.bosses.records:
		var spawn := float(record.spawn_time)
		var death := float(record.death_time)
		fights.append({"boss_index": int(record.boss_index), "mob_id": int(record.mob_id), "spawn_time": spawn, "death_time": death,
			"map_index": int(record.get("map_index", 0)), "map_id": int(record.get("map_id", world.current_map_id())),
			"duration": death-spawn if bool(record.dead) and spawn>=0.0 else -1.0,
			"elapsed": maxf(0.0, (death if bool(record.dead) else world.time)-spawn) if spawn>=0.0 else 0.0,
			"status": "dead" if bool(record.dead) else "alive" if spawn>=0.0 else "skipped" if bool(record.get("skipped", false)) else "not_spawned"})
		if record.has("level_scale_at"):
			fights[fights.size() - 1]["level_scale_at"] = float(record.level_scale_at)
	return fights


## Unweighted sample summary; null values distinguish no observations from observed zero.
static func statistics(values: Array) -> Dictionary:
	if values.is_empty():
		return {"count": 0, "min": null, "median": null, "max": null, "mean": null}
	var sorted := values.duplicate()
	sorted.sort()
	var count := sorted.size()
	var sum := 0.0
	for value: Variant in sorted:
		sum += float(value)
	var median := float(sorted[count/2]) if count%2 else (float(sorted[count/2-1])+float(sorted[count/2]))*0.5
	return {"count": count, "min": float(sorted[0]), "median": median, "max": float(sorted[count-1]), "mean": sum/count}


## Harness movement policy; camper policies use the sensible card and potion policy with their own movement goals.
static func movement(world: RunWorld, policy: String, memo: Dictionary, camp_after: float = 60.0) -> MoveInput:
	return CAMPER.decide(world, policy, memo, camp_after) if CAMPER.STAGES.has(policy) else BotInput.decide(world, memo)


## Aggregates observed run records: per boss the completed fight statistics, the completed/spawned count and a
## censored median (censored_median), whole-hit fractions per boss/source, player potion-use totals and camper arrivals
## (counted over camper-policy runs only).
static func aggregate(records: Array) -> Dictionary:
	if not records.is_empty() and records[0].get("mode", "") == "chain":
		return aggregate_chain(records)
	var result := {"runs": records.size(), "potions_used": {"hp": 0},
		"boss_fights": {}, "boss_hits": {}, "camper_runs": 0, "camper_started": 0, "camper_reached": 0,
		"ordinary_kill_hits_by_min": KillHits.empty_buckets()}
	result["jobs"] = {}
	result["revived_runs"] = 0
	result["card_tier_runs"] = 0
	result["card_tiers_offered"] = UpgradePool.empty_tier_counts()
	result["card_tiers_picked"] = result.card_tiers_offered.duplicate()
	var deaths: Array = []
	result["deaths_by_map"] = {"1": 0, "2": 0, "3": 0}
	var map_entries := {"2": [], "3": []}
	result["outcomes"] = {"CLEARED": 0, "DEAD": 0, "TIMEOUT": 0}
	var mesos_earned: Array = []
	var equips_dropped: Array = []
	var equips_collected: Array = []
	var equips_worn: Array = []
	var shop_samples := {}
	for field: String in SHOP_FIELDS:
		shop_samples[field] = []
	var fractions: Array = []
	var fight_samples := {}
	var censored_samples := {}
	var hit_samples := {}
	var end_levels: Array = []
	var nx_samples: Array = []
	result["lv70_reached"] = 0
	result["tier"] = int(records[0].get("tier", 0)) if not records.is_empty() else 0
	for record: Dictionary in records:
		if record.has("level"):
			end_levels.append(int(record.level))
		if record.has("nx_awarded"):
			nx_samples.append(int(record.nx_awarded))
		result.lv70_reached += 1 if bool(record.get("lv70_reached", int(record.get("level", 0)) >= LEVEL_TARGET)) else 0
		var job_key := str(int(record.get("job", 0))) if record.has("job") else "unobserved"
		if not result.jobs.has(job_key):
			result.jobs[job_key] = {"runs": 0, "CLEARED": 0, "DEAD": 0, "TIMEOUT": 0}
		var group: Dictionary = result.jobs[job_key]
		group.runs += 1
		var outcome := String(record.get("state", ""))
		if group.has(outcome):
			group[outcome] += 1
		if record.has("card_tiers_offered") and record.has("card_tiers_picked"):
			result.card_tier_runs += 1
			for key: String in ["card_tiers_offered", "card_tiers_picked"]:
				for tier: String in UpgradePool.TIERS:
					result[key][tier] += int(record[key].get(tier, 0))
		var state := String(record.get("state", ""))
		if result.outcomes.has(state):
			result.outcomes[state] += 1
		if state == "DEAD":
			deaths.append(float(record.time))
			if record.has("ended_map"):
				var map_number := str(int(record.ended_map.index) + 1)
				result.deaths_by_map[map_number] = int(result.deaths_by_map.get(map_number, 0)) + 1
		var map_times: Array = record.get("map_times", [])
		for number: String in map_entries:
			var index := int(number) - 1
			if map_times.size() > index:
				map_entries[number].append(float(map_times[index]))
		var kill_hits: Array = record.get("ordinary_kill_hits_by_min", [])
		for minute in mini(EARLY_MINUTES, kill_hits.size()):
			result.ordinary_kill_hits_by_min[minute].hits += int(kill_hits[minute].hits)
			result.ordinary_kill_hits_by_min[minute].kills += int(kill_hits[minute].kills)
		if record.has("equips_dropped"):
			equips_dropped.append(int(record.equips_dropped))
			equips_collected.append(int(record.get("equips_collected", 0)))
		if record.has("equips_worn"):
			equips_worn.append(int(record.equips_worn))
		if record.has("shop"):
			for field: String in SHOP_FIELDS:
				shop_samples[field].append(int(record.shop.get(field, 0)))
		if record.has("mesos_earned"):
			mesos_earned.append(int(record.mesos_earned))
		result.potions_used.hp += int(record.get("potions_used", {}).get("hp", 0))
		if int(record.get("revive_count", 0)) > 0:
			result.revived_runs += 1
		var camper: Dictionary = record.get("camper", {})
		if String(camper.get("policy", "")) != "":
			result.camper_runs += 1
			result.camper_started += 1 if float(camper.get("started_time", -1.0))>=0 else 0
			result.camper_reached += 1 if bool(camper.get("reached", false)) else 0
		for fight: Dictionary in record.get("boss_fights", []):
			var id := str(int(fight.mob_id))
			if not result.boss_fights.has(id):
				result.boss_fights[id] = {"alive": 0, "not_spawned": 0, "skipped": 0}
				fight_samples[id] = []
				censored_samples[id] = []
			if String(fight.status) == "dead":
				fight_samples[id].append(float(fight.duration))
				censored_samples[id].append(Vector2(float(fight.duration), 0.0))
			else:
				result.boss_fights[id][String(fight.status)] += 1
				if String(fight.status) == "alive":
					censored_samples[id].append(Vector2(float(fight.get("elapsed", 0.0)), 1.0))
		for hit: Dictionary in record.get("boss_hits", []):
			var id := str(int(hit.mob_id))
			var source := String(hit.get("source_kind", "other"))
			var fraction := float(hit.fraction)
			fractions.append(fraction)
			if not hit_samples.has(id):
				hit_samples[id] = {"all": [], "sources": {}}
			hit_samples[id].all.append(fraction)
			if not hit_samples[id].sources.has(source):
				hit_samples[id].sources[source] = []
			hit_samples[id].sources[source].append(fraction)
	for id: String in result.boss_fights:
		result.boss_fights[id]["completed"] = statistics(fight_samples[id])
		result.boss_fights[id]["spawned"] = censored_samples[id].size()
		result.boss_fights[id]["censored_median"] = censored_median(censored_samples[id])
	for id: String in hit_samples:
		var sources := {}
		for source: String in hit_samples[id].sources:
			sources[source] = statistics(hit_samples[id].sources[source])
		result.boss_hits[id] = {"whole_fraction": statistics(hit_samples[id].all), "by_source": sources}
	result["death_seconds"] = statistics(deaths)
	result["map_entry_seconds"] = {}
	for number: String in map_entries:
		result.map_entry_seconds[number] = statistics(map_entries[number])
	result["mesos_earned"] = statistics(mesos_earned)
	result["equips_dropped"] = statistics(equips_dropped)
	result["equips_collected"] = statistics(equips_collected)
	if not equips_worn.is_empty():
		result["equips_worn"] = statistics(equips_worn)
	if not shop_samples.sold.is_empty():
		result["shop"] = {"visits": shop_samples.sold.size()}
		for field: String in SHOP_FIELDS:
			result.shop[field] = statistics(shop_samples[field])
	result["boss_hit_fraction"] = statistics(fractions)
	result["end_level"] = statistics(end_levels)
	result["nx_awarded"] = statistics(nx_samples)
	for bucket: Dictionary in result.ordinary_kill_hits_by_min:
		bucket.mean = float(bucket.hits) / int(bucket.kills) if int(bucket.kills) > 0 else null
	return result


## Aggregates each tier separately; unstarted rounds never enter outcome, death or boss denominators.
static func aggregate_chain(records: Array) -> Dictionary:
	var groups := {}
	var result := {"mode": "chain", "runs": records.size(), "tier1_clears": 0, "tiers": {}}
	for record: Dictionary in records:
		for tier in range(1, int(record.target_tier) + 1):
			if not groups.has(str(tier)):
				groups[str(tier)] = []
		for round_record: Dictionary in record.rounds:
			groups[str(int(round_record.tier))].append(round_record)
			if int(round_record.tier) == 1 and round_record.state == "CLEARED":
				result.tier1_clears += 1
	for tier: String in groups:
		result.tiers[tier] = aggregate(groups[tier])
		result.tiers[tier].tier = int(tier)
	return result


## Median fight length over every spawned fight, an unfinished one counting as at least its elapsed seconds (right
## censored). `samples` holds Vector2(seconds, 1 if unfinished else 0). The median is exact when no unfinished fight
## sorts at or below the (upper) middle rank; otherwise the true median can only be larger and `lower_bound` is true
## (reported as ">=").
static func censored_median(samples: Array) -> Dictionary:
	if samples.is_empty():
		return {"count": 0, "censored": 0, "median": null, "lower_bound": false}
	var sorted := samples.duplicate()
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var n := sorted.size()
	var median: float = sorted[n / 2].x if n % 2 else (sorted[n / 2 - 1].x + sorted[n / 2].x) * 0.5
	var censored := 0
	var lower := false
	for i in n:
		if sorted[i].y > 0.0:
			censored += 1
			# Only an unfinished fight at or below the (upper) middle rank can still move the median.
			if i <= n / 2:
				lower = true
	return {"count": n, "censored": censored, "median": median, "lower_bound": lower}


## Readable supplemental systems summary; ranges are min/median/max and include their observation count. Fight lines
## put the completed count next to the spawned count and add the censored median, so a median over completed fights
## alone cannot hide unfinished ones.
static func describe_metrics(summary: Dictionary) -> String:
	if summary.get("mode", "") == "chain":
		var chain_lines := PackedStringArray(["SUMMARY chain %d runs; tier-1 clears feeding tier 2: %d/%d" % [
			int(summary.runs), int(summary.tier1_clears), int(summary.runs)]])
		for tier: String in summary.tiers:
			chain_lines.append(describe_metrics(summary.tiers[tier]))
		return "\n".join(chain_lines)
	var lines := PackedStringArray()
	lines.append("SUMMARY deaths by map: 1:%d 2:%d 3:%d" % [summary.deaths_by_map["1"],
		summary.deaths_by_map["2"], summary.deaths_by_map["3"]])
	for number: String in summary.map_entry_seconds:
		lines.append("  map-%s entry seconds %s" % [number, _range(summary.map_entry_seconds[number])])
	if int(summary.get("tier", 0)) > 0:
		lines.append("SUMMARY tier %d: %d started, %d cleared; end level %s; Lv70 reached %d/%d" % [
			int(summary.tier), int(summary.runs), int(summary.outcomes.CLEARED),
			_range(summary.end_level), int(summary.lv70_reached), int(summary.runs)])
	lines.append("SYSTEMS %d runs: potions used HP %d%s" % [int(summary.runs), int(summary.potions_used.hp),
		_campers(summary)])
	lines.append("  SUMMARY revived %d/%d runs" % [int(summary.get("revived_runs", 0)), int(summary.runs)])
	for job_key: String in summary.get("jobs", {}):
		lines.append("  SUMMARY job %s: %s" % [job_key, summary.jobs[job_key]])
	if summary.has("nx_awarded"):
		lines.append("  NX awarded per run (not credited) " + _range(summary.nx_awarded))
	if summary.has("mesos_earned"):
		lines.append("  mesos earned per round " + _range(summary.mesos_earned))
	if summary.has("equips_dropped"):
		lines.append("  equipment dropped per round " + _range(summary.equips_dropped) + ", picked up " + _range(summary.equips_collected))
	if summary.has("equips_worn"):
		lines.append("  equipment put on mid-round per round " + _range(summary.equips_worn))
	if summary.has("shop"):
		lines.append("  Free Market visits after this tier: %d" % int(summary.shop.visits))
		for field: String in SHOP_FIELDS:
			lines.append("    shop %s per visit %s" % [field, _range(summary.shop[field])])
	lines.append("  card tiers (%d observed runs)" % int(summary.card_tier_runs))
	for tier: String in UpgradePool.TIERS:
		lines.append("  cards %s offered %d picked %d" % [tier.capitalize(), int(summary.card_tiers_offered[tier]),
			int(summary.card_tiers_picked[tier])])
	lines.append("  outcomes %s; death-only seconds %s" % [summary.outcomes, _range(summary.death_seconds)])
	for minute in summary.ordinary_kill_hits_by_min.size():
		var bucket: Dictionary = summary.ordinary_kill_hits_by_min[minute]
		lines.append("  minute %d ordinary hits/kill %s (%d hits / %d kills)" % [minute + 1,
			"undefined" if bucket.mean == null else "%.3f" % float(bucket.mean), int(bucket.hits), int(bucket.kills)])
	lines.append("  boss whole-hit HP percent " + _range(summary.boss_hit_fraction, 100.0))
	for id: String in summary.boss_fights:
		var fight: Dictionary = summary.boss_fights[id]
		lines.append("  boss %s fight seconds %s; completed %d/%d spawned; censored median %s; unfinished %d; not spawned %d; skipped %d" % [
			id, _range(fight.completed), int(fight.completed.count), int(fight.get("spawned", fight.completed.count)),
			_censored(fight.get("censored_median", {})), int(fight.alive), int(fight.not_spawned), int(fight.get("skipped", 0))])
	for id: String in summary.boss_hits:
		lines.append("  boss %s whole-hit HP percent %s" % [id, _range(summary.boss_hits[id].whole_fraction, 100.0)])
		for source: String in summary.boss_hits[id].by_source:
			lines.append("    %s HP percent %s" % [source, _range(summary.boss_hits[id].by_source[source], 100.0)])
	return "\n".join(lines)


## "; campers reached R/N runs (S started)" when camper-policy runs are present, "" otherwise (no "0/0" line).
static func _campers(summary: Dictionary) -> String:
	var runs := int(summary.get("camper_runs", 0))
	if runs == 0:
		return ""
	return "; campers reached %d/%d runs (%d started)" % [int(summary.camper_reached), runs, int(summary.camper_started)]


static func _censored(stats: Dictionary) -> String:
	if int(stats.get("count", 0)) == 0:
		return "none (n=0)"
	return "%s%.2f (n=%d, %d unfinished)" % [">=" if bool(stats.lower_bound) else "", float(stats.median),
		int(stats.count), int(stats.censored)]


static func _range(stats: Dictionary, scale: float = 1.0) -> String:
	return "none (n=0)" if int(stats.count)==0 else "%.2f/%.2f/%.2f (n=%d)" % [float(stats.min)*scale, float(stats.median)*scale, float(stats.max)*scale, int(stats.count)]
