extends SceneTree
## Headless draft tool for a new region's level scale and boss multipliers (spec #449 "Level scale, first draft" and
## "Bosses, first draft"; ticket #462, C0). It prints the numbers a region ticket pastes into `stages/<key>.json`; it
## writes nothing and runs no round.
##
##   ISOLATE=<name> bash scripts/godot.sh --headless --path _scratch/godot_runs/<name>/game \
##     --script res://tools/level_scale_draft.gd -- --step=6 --stage=ludibrium
##
## Flags: `--step=<k>` (the region's place in `progression`, 1-based; 6 for Ludibrium) and `--stage=<key>` (the region
## being drafted: its three scheduled bosses are read from `stages/<key>.json`, each map's `boss.mob_id`, `final_form` and
## `attacks`, in slot order). `--reference=<key>` is the stage the numbers are carried from (default sleepywood). Optional
## overrides for a stage file that does not exist yet (or to try other bosses): `--bosses=<id,id,id>` (one mob id per map),
## `--attacks=<a,b|c|d>` (per boss, `|` between bosses: the scheduled `attackN` stances; a boss with none listed uses every
## `attackN` stance it has) and `--finals=<id,id,id>` (a final form per boss, 0 for none); each replaces the same list read
## from the stage file. `--final-share=<0..1>` is the share of the encounter's effective HP the final form carries
## (default 0.5) and `--offset=<n>` the levels per step above Sleepywood (default 3). Needs the asset cache
## (`MAPLE_SURVIVORS_CACHE`): canonical HP, damage and the reference maps' life lists come from it.
##
## The formulas (tier C, all of them: #449's first draft; the numbers are re-tuned by the calibration ticket, never by
## hand here):
##  * E_ref(t), the reference stage's effective level at curve time t: the level whose reference `hp` curve value equals
##    the weighted mean canonical HP of the live ordinary pool at t, times the stage's opening-ramp HP multiplier at
##    nominal round time t. The pool of map 1 is the last keyframe pool at or before t among keyframes with t below
##    map_seconds; a later map's pool is StagePools.resolve of its entry. The map is the one being entered at a
##    boundary (t = 300 is map 2's first moment): `map_index_at`. The keyframe `hp` multiplier is left out: the new
##    region copies the reference stage's keyframes, so it applies it on top again.
##  * Step k >= 6: `level(t) = E_ref(t) + offset * (k - 5)` and `exp_level(t) = E_ref(t)` at each reference keyframe time.
##  * Boss j, arriving at curve time t_j = j * map_seconds + time (also nominal round time): the reference boss's effective
##    HP, contact damage and strongest scheduled attack's damage at t_j (canonical value x its multiplier x the ramp at
##    t_j) is carried to the new boss by the level scale's own ratios, `hp(level)/hp(E_ref)` for HP and `pad(level)/pad(E_ref)`
##    (`mad` for a magic attack) for damage; `hp_mult`, `dmg_mult` and `attack_dmg_mult` are what make the new boss's
##    effective value (canonical x multiplier x `curve(level)/curve(its own level)`) equal that target. `level` cancels,
##    so the multipliers do not move when the offset does. Both sides read only their scheduled `attacks` (the entry's
##    list; every `attackN` stance when it names none), and `attack_dmg_mult` is matched on the strongest of them alone.
##    A boss with a final form splits the target HP by `--final-share`; the form's multiplier is `final_form_hp_mult`.
##    The form is matched at the shell's nominal arrival level, but at runtime it spawns later (when the shell dies), at a
##    higher level, so its HP lands above the target by `hp(level_later)/hp(level_arrival)`. No model change (tier C).
##  * `attack_interval` is 8, as every boss today.
## A `level` above 131 is warned about: the reference curve holds its Lv131 values from there on (GAME_DESIGN "Level
## scale" known limits), so a higher effective level makes a stage no harder.

## The curve ends here: above it the reference curves hold their last sampled values (tier A: v83 has no stronger ordinary
## monster; docs/GAME_DESIGN.md "Level scale").
const CURVE_FLAT_ABOVE := 131
## Tier C (#449): levels harder per region step above Sleepywood.
const DEFAULT_OFFSET := 3.0
## Tier C (#449): the progression step Sleepywood holds; step k adds `offset * (k - SLEEPYWOOD_STEP)`.
const SLEEPYWOOD_STEP := 5
## Tier C (#449): the final form's share of an encounter's effective HP when a boss has one (B1 #456 weights it).
const DEFAULT_FINAL_SHARE := 0.5
## Tier C (every boss today): seconds between a boss's attacks.
const ATTACK_INTERVAL := 8
## Tier C: keyframe levels are written to this resolution.
const LEVEL_STEP := 0.01
## Tier C: boss multipliers are written to this resolution.
const MULT_STEP := 0.001


func _init() -> void:
	var args := _parse(OS.get_cmdline_user_args())
	var problem := String(args.get("error", ""))
	if problem != "":
		print("level_scale_draft: %s" % problem)
		quit(2)
		return
	var library := AssetLibrary.new()
	library.open()
	var data := DataRepo.load_all()
	var stage: Dictionary = data.stages.stages.get(args.reference, {})
	if stage.is_empty() or data.level_curve.is_empty() or not library.has_img(DataRepo.map_img_path(int(stage.maps[0].map_id))):
		print("level_scale_draft: needs reference stage '%s', level_curve.json and the asset cache (MAPLE_SURVIVORS_CACHE)" % args.reference)
		library.free()
		quit(1)
		return
	var plan := bosses_of(data.stages.stages.get(args.stage, {}), args.bosses, args.attacks, args.finals)
	if plan.bosses.is_empty():
		print("level_scale_draft: stage '%s' has no stages/%s.json; give --bosses=<id,id,id>" % [args.stage, args.stage])
		library.free()
		quit(2)
		return
	var map_imgs: Array = []
	for entry: Dictionary in stage.maps:
		var img := library.img(DataRepo.map_img_path(int(entry.map_id)))
		map_imgs.append(img.root if img != null else {})
	var result := draft(stage, data.level_curve, map_imgs, func(id: int) -> Dictionary: return library.mob_root(id),
			int(args.step), plan.bosses, plan.attacks, plan.finals, float(args.final_share), float(args.offset))
	print(describe(result, int(args.step), args.reference, args.stage))
	library.free()
	quit(1 if not result.errors.is_empty() else 0)


## The flags as {step, bosses, attacks, finals, final_share, offset, stage, reference}, or {error}.
static func _parse(argv: PackedStringArray) -> Dictionary:
	var out := {"step": 0, "bosses": [], "attacks": [], "finals": [], "final_share": DEFAULT_FINAL_SHARE,
		"offset": DEFAULT_OFFSET, "stage": "", "reference": "sleepywood"}
	for arg in argv:
		var parts := arg.trim_prefix("--").split("=", true, 1)
		var value := parts[1] if parts.size() > 1 else ""
		match parts[0]:
			"step": out.step = int(value)
			"bosses":
				for id in value.split(",", false):
					out.bosses.append(int(id))
			"attacks":
				for names in value.split("|"):
					out.attacks.append(Array(names.split(",", false)))
			"finals":
				for id in value.split(",", false):
					out.finals.append(int(id))
			"final-share": out.final_share = float(value)
			"offset": out.offset = float(value)
			"stage": out.stage = value
			"reference": out.reference = value
			_: return {"error": "unknown flag '%s'" % arg}
	if int(out.step) < 1 or (String(out.stage).is_empty() and out.bosses.is_empty()):
		return {"error": "give --step=<k> and --stage=<region key> (or --bosses=<id,id,id> for a stage without a file)"}
	return out


## The bosses to draft, {bosses, attacks, finals} (one entry per map): read from `stage`'s maps (`boss.mob_id`,
## `boss.attacks`, `boss.final_form`, 0 and [] when absent), each list replaced by its non-empty override.
static func bosses_of(stage: Dictionary, bosses: Array = [], attacks: Array = [], finals: Array = []) -> Dictionary:
	var out := {"bosses": [], "attacks": [], "finals": []}
	for entry: Dictionary in stage.get("maps", []):
		var boss: Dictionary = entry.get("boss", {})
		out.bosses.append(int(boss.get("mob_id", 0)))
		out.attacks.append(Array(boss.get("attacks", [])))
		out.finals.append(int(boss.get("final_form", 0)))
	for key: String in ["bosses", "attacks", "finals"]:
		var given: Array = {"bosses": bosses, "attacks": attacks, "finals": finals}[key]
		if not given.is_empty():
			out[key] = given.duplicate()
	return out


## The draft of step `step` over the reference `stage`: {keyframes: [{t, level, exp_level}], bosses: [{...}], rows:
## [{t, map, pool_hp, ramp, e_ref}] (the working), warnings, errors}. `map_imgs` holds the reference stage's map imgs in
## order, `mob_root` returns a mob's img root (`info`, `attackN/info`) for a mob id, `bosses` the new region's boss ids
## (one per map), `attacks` its scheduled attack names per boss (empty list: every attackN stance), `finals` a final
## form id per boss (0: none). Pure given those inputs.
static func draft(stage: Dictionary, curve: Dictionary, map_imgs: Array, mob_root: Callable, step: int, bosses: Array,
		attacks: Array = [], finals: Array = [], final_share: float = DEFAULT_FINAL_SHARE,
		offset: float = DEFAULT_OFFSET) -> Dictionary:
	var out := {"keyframes": [], "bosses": [], "rows": [], "warnings": PackedStringArray(), "errors": PackedStringArray()}
	var map_pools: Array = []
	for i in stage.maps.size():
		map_pools.append(StagePools.resolve(stage.maps[i], map_imgs[i] if i < map_imgs.size() else {}))
	var hp_of := func(id: int) -> float: return float(mob_root.call(id).get("info", {}).get("maxHP", 0.0))
	var e_values: Array = []
	var times: Array = []
	for keyframe: Dictionary in stage.keyframes:
		var t := float(keyframe.t)
		var row := reference_level(stage, map_pools, curve.hp, hp_of, t)
		if float(row.pool_hp) <= 0.0:
			out.errors.append("no canonical HP for the pool at t=%d (is the asset cache complete?)" % int(t))
			return out
		times.append(t)
		e_values.append(row.e_ref)
		out.rows.append(row)
	out.keyframes = scale_keyframes(times, e_values, step, offset)
	out.warnings.append_array(level_warnings(out.keyframes))
	if bosses.size() != stage.maps.size():
		out.errors.append("the reference stage has %d maps; give %d boss ids" % [stage.maps.size(), stage.maps.size()])
		return out
	for j in bosses.size():
		var entry: Dictionary = stage.maps[j].boss
		var t_j := arrival_time(stage, j)
		var e_j: float = reference_level(stage, map_pools, curve.hp, hp_of, t_j).e_ref
		# Both sides read only their scheduled attacks (the entry's `attacks`).
		var ref_canon := canonical_boss(mob_root.call(int(entry.mob_id)), Array(entry.get("attacks", [])))
		var reference := boss_effective(entry, ref_canon, ramp_of(stage, j), t_j)
		var names: Array = attacks[j] if j < attacks.size() else []
		var final_id := int(finals[j]) if j < finals.size() else 0
		var canon := canonical_boss(mob_root.call(int(bosses[j])), names)
		var final_canon := canonical_boss(mob_root.call(final_id), names) if final_id > 0 else {}
		for check: Array in [[int(bosses[j]), canon], [final_id, final_canon]]:
			if int(check[0]) > 0 and float(check[1].hp) <= 0.0:
				out.errors.append("mob %d has no canonical HP: list it in the region's manifest fragment and import it" % int(check[0]))
		if not out.errors.is_empty():
			return out
		var matched := match_boss(reference, curve, e_j, canon, level_for(e_j, step, offset),
				final_share if final_id > 0 else 0.0, final_canon)
		matched.mob_id = int(bosses[j])
		matched.arrival = t_j
		matched.e_ref = e_j
		matched.level = level_for(e_j, step, offset)
		if final_id > 0:
			matched.final_form = final_id
		out.bosses.append(matched)
		if float(matched.level) > CURVE_FLAT_ABOVE:
			out.warnings.append("boss %d arrives at level %.1f, above %d" % [int(bosses[j]), matched.level, CURVE_FLAT_ABOVE])
	return out


## The reference stage's effective level at curve time t, with its working: {t, map (1-based), pool_hp (the live pool's
## weighted mean canonical HP), ramp (the opening ramp's HP multiplier there), e_ref}.
static func reference_level(stage: Dictionary, map_pools: Array, hp_curve: Array, hp_of: Callable, t: float) -> Dictionary:
	var mean := mean_hp(pool_at(stage, map_pools, t), hp_of)
	var index := map_index_at(stage, t)
	var ramp := ramp_value(ramp_of(stage, index), "hp", t)
	return {"t": t, "map": index + 1, "pool_hp": mean, "ramp": ramp, "e_ref": effective_level(hp_curve, mean * ramp)}


## The map a curve time belongs to: the one being entered at a boundary (t = map_seconds is map 2's first moment), the last
## map after the last boundary. Tier C.
static func map_index_at(stage: Dictionary, t: float) -> int:
	var seconds := float(stage.get("map_seconds", 300.0))
	return clampi(int(floorf(t / seconds)), 0, stage.maps.size() - 1)


## Curve time at which map `index`'s scheduled boss arrives: index * map_seconds + its time since entry.
static func arrival_time(stage: Dictionary, index: int) -> float:
	return float(index) * float(stage.get("map_seconds", 300.0)) + float(stage.maps[index].boss.get("time", 300.0))


## The ordinary pool {mob id: weight} live at curve time t: map 1's keyframe pool (the last keyframe at or before t among
## those below map_seconds) or the resolved pool of a later map (`map_pools`, StagePools.resolve per map).
static func pool_at(stage: Dictionary, map_pools: Array, t: float) -> Dictionary:
	var index := map_index_at(stage, t)
	if not (map_pools[index] as Dictionary).is_empty():
		return map_pools[index]
	var seconds := float(stage.get("map_seconds", 300.0))
	var pool := {}
	for keyframe: Dictionary in stage.keyframes:
		if float(keyframe.t) >= seconds or float(keyframe.t) > t + 1e-9:
			break
		if keyframe.has("pool"):
			pool = {}
			for id: Variant in keyframe.pool:
				pool[int(id)] = float(keyframe.pool[id])
	return pool


## The opening ramp that applies on map `index`: the map's own, else the stage's ({} when none; RunWorld.opening_multiplier).
static func ramp_of(stage: Dictionary, index: int) -> Dictionary:
	return stage.maps[index].get("opening_ramp", stage.get("opening_ramp", {}))


## RunWorld.opening_multiplier of `ramp` for `stat` ("hp" or "damage") at round time `time` (the same arithmetic, without a world).
static func ramp_value(ramp: Dictionary, stat: String, time: float) -> float:
	var values: Dictionary = ramp.get(stat, {})
	var seconds := float(ramp.get("seconds", 0.0))
	var progress := clampf(time / seconds, 0.0, 1.0) if seconds > 0.0 else 1.0
	progress = pow(progress, float(ramp.get("power", 1.0)))
	return lerpf(float(values.get("start", 1.0)), float(values.get("end", 1.0)), progress)


## The weighted mean of `hp_of.call(id)` over `pool` {id: weight}; 0 for an empty pool or one without HP.
static func mean_hp(pool: Dictionary, hp_of: Callable) -> float:
	var total := 0.0
	var weights := 0.0
	for id: Variant in pool:
		total += float(pool[id]) * float(hp_of.call(int(id)))
		weights += float(pool[id])
	return total / weights if weights > 0.0 else 0.0


## The fractional level (1-200) at which the non-decreasing `values` curve (index = level - 1) reaches `target`: the first
## level it gets there, interpolated linearly like LevelScale.value; clamped to 1 and to the last level.
static func effective_level(values: Array, target: float) -> float:
	if target <= float(values[0]):
		return 1.0
	for i in range(1, values.size()):
		if float(values[i]) >= target:
			var low := float(values[i - 1])
			return float(i) + (target - low) / (float(values[i]) - low)
	return float(values.size())


## `values` (index = level - 1) at a fractional level, clamped to the curve; LevelScale.value on a plain array.
static func curve_at(values: Array, level: float) -> float:
	var x := clampf(level, 1.0, float(values.size())) - 1.0
	var i := mini(int(x), values.size() - 2)
	return lerpf(float(values[i]), float(values[i + 1]), x - float(i))


## The region's effective level for a reference level e at step `step`: e + offset * (step - 5).
static func level_for(e: float, step: int, offset: float = DEFAULT_OFFSET) -> float:
	return e + offset * float(step - SLEEPYWOOD_STEP)


## The `level_scale` keyframes of step `step`: for each reference time (`times`, `e_values` aligned) {t, level =
## E + offset * (step - 5), exp_level = E}, levels rounded to LEVEL_STEP.
static func scale_keyframes(times: Array, e_values: Array, step: int, offset: float = DEFAULT_OFFSET) -> Array:
	var out: Array = []
	for i in times.size():
		out.append({"t": int(times[i]) if float(times[i]) == floorf(float(times[i])) else times[i],
			"level": snappedf(level_for(float(e_values[i]), step, offset), LEVEL_STEP),
			"exp_level": snappedf(float(e_values[i]), LEVEL_STEP)})
	return out


## One warning per keyframe whose `level` (or `exp_level`) is above CURVE_FLAT_ABOVE, where the stage stops getting harder.
static func level_warnings(keyframes: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for keyframe: Dictionary in keyframes:
		for field: String in ["level", "exp_level"]:
			if float(keyframe.get(field, 0.0)) > float(CURVE_FLAT_ABOVE):
				out.append("keyframe t=%s %s %.2f is above %d: the reference curves are flat there" % [
					str(keyframe.t), field, float(keyframe[field]), CURVE_FLAT_ABOVE])
	return out


## The canonical numbers of a boss from its mob img root: {level, hp, pad, attack, magic}. `attack` is the damage of the
## strongest of the scheduled `attack_names` (every `attackN` stance when empty) by the rule MobAttacks uses (MADamage when
## the attack is magic or has only MADamage, else PADamage, defaulting to the mob's own), `magic` which stat it is.
static func canonical_boss(root: Dictionary, attack_names: Array) -> Dictionary:
	var info: Dictionary = root.get("info", {})
	var out := {"level": int(info.get("level", 1)), "hp": float(info.get("maxHP", 0.0)),
		"pad": float(info.get("PADamage", 0.0)), "attack": 0.0, "magic": false}
	var names := attack_names.duplicate()
	if names.is_empty():
		for key: Variant in root:
			if String(key).begins_with("attack") and String(key).substr(6).is_valid_int():
				names.append(String(key))
	names.sort()
	for attack: Variant in names:
		var stance: Variant = root.get(attack)
		if not stance is Dictionary:
			continue
		var attack_info: Dictionary = stance.get("info", {})
		var magic := int(attack_info.get("magic", 0)) != 0 or (attack_info.has("MADamage") and not attack_info.has("PADamage"))
		var damage := float(attack_info.get("MADamage" if magic else "PADamage", info.get("MADamage" if magic else "PADamage", 0.0)))
		if damage > float(out.attack):
			out.attack = damage
			out.magic = magic
	return out


## What a stage boss entry is worth at arrival time `t` (nominal round time): {hp, touch, attack} = canonical x the entry's
## multipliers x the ramp (`hp` for HP, `damage` for both damages), as RunWorld.spawn_mob and BossDirector capture them.
static func boss_effective(entry: Dictionary, canon: Dictionary, ramp: Dictionary, t: float) -> Dictionary:
	var dmg := float(entry.get("dmg_mult", 1.0))
	var damage_ramp := ramp_value(ramp, "damage", t)
	return {"hp": float(canon.hp) * float(entry.get("hp_mult", 1.0)) * ramp_value(ramp, "hp", t),
		"touch": float(canon.pad) * dmg * damage_ramp,
		"attack": float(canon.attack) * float(entry.get("attack_dmg_mult", dmg)) * damage_ramp,
		"magic": bool(canon.magic)}


## The multipliers that carry `reference` (boss_effective of the reference stage's boss) to a new boss of canonical numbers
## `canon` under the level scale: effective level `level` for the new region, `e_ref` for the reference. Returns {hp_mult,
## dmg_mult, attack_dmg_mult, attack_interval} plus `final_form_hp_mult` when `final_share` > 0 (then `final_canon` is the
## form's canonical numbers and hp_mult covers the remaining share). A canonical value of 0 leaves its multiplier at 1.
static func match_boss(reference: Dictionary, curve: Dictionary, e_ref: float, canon: Dictionary, level: float,
		final_share: float = 0.0, final_canon: Dictionary = {}) -> Dictionary:
	var target_hp := float(reference.hp) * curve_at(curve.hp, level) / curve_at(curve.hp, e_ref)
	var out := {"attack_interval": ATTACK_INTERVAL}
	out.hp_mult = _snap_mult(_carry(target_hp * (1.0 - final_share), float(canon.hp), curve.hp, level, int(canon.level)))
	if final_share > 0.0:
		out.final_form_hp_mult = _snap_mult(_carry(target_hp * final_share, float(final_canon.hp), curve.hp, level,
				int(final_canon.level)))
	var pad_target := float(reference.touch) * curve_at(curve.pad, level) / curve_at(curve.pad, e_ref)
	out.dmg_mult = _snap_mult(_carry(pad_target, float(canon.pad), curve.pad, level, int(canon.level)))
	# The attack uses the new boss's stat (pad or mad) for both the target and the carry; a reference attack of the other
	# stat is carried as a number, not converted.
	var stat: Array = curve.mad if bool(canon.magic) else curve.pad
	var attack_target := float(reference.attack) * curve_at(stat, level) / curve_at(stat, e_ref)
	out.attack_dmg_mult = _snap_mult(_carry(attack_target, float(canon.attack), stat, level, int(canon.level)))
	return out


## The multiplier m with canonical x m x curve(level)/curve(canonical_level) = target; 1 when the canonical value is 0.
static func _carry(target: float, canonical: float, values: Array, level: float, canonical_level: int) -> float:
	var per_mult := canonical * curve_at(values, level) / curve_at(values, float(canonical_level))
	return target / per_mult if per_mult > 0.0 else 1.0


static func _snap_mult(m: float) -> float:
	return snappedf(m, MULT_STEP) if m >= 0.01 else snappedf(m, 1.0e-6)


## The printed draft: the working (one line per reference keyframe), the `level_scale` block and each boss's multipliers
## as JSON a region file takes, and the warnings.
static func describe(result: Dictionary, step: int, reference: String, stage_key: String = "") -> String:
	var lines := PackedStringArray()
	lines.append("level_scale_draft: step %d%s over %s (tier C draft; E_ref = the reference stage's effective level)" % [
		step, " of %s" % stage_key if stage_key != "" else "", reference])
	if not result.errors.is_empty():
		for e: String in result.errors:
			lines.append("ERROR: " + e)
		return "\n".join(lines)
	lines.append("   t  map  pool_hp_mean  ramp_hp   E_ref")
	for row: Dictionary in result.rows:
		lines.append("%4d  %3d  %12.1f  %7.4f  %6.2f" % [int(row.t), int(row.map), row.pool_hp, row.ramp, row.e_ref])
	lines.append("\"level_scale\": " + JSON.stringify({"keyframes": result.keyframes}, "", false))
	for i in result.bosses.size():
		var boss: Dictionary = result.bosses[i]
		var fields := {"mob_id": boss.mob_id, "hp_mult": boss.hp_mult, "dmg_mult": boss.dmg_mult,
			"attack_dmg_mult": boss.attack_dmg_mult, "attack_interval": boss.attack_interval}
		if boss.has("final_form"):
			fields.final_form = boss.final_form
			fields.final_form_hp_mult = boss.final_form_hp_mult
		lines.append("map %d boss (arrives t=%d, E_ref %.2f, level %.2f): %s" % [i + 1, int(boss.arrival), boss.e_ref,
			boss.level, JSON.stringify(fields, "", false)])
	lines.append("(tier C: #449's first draft, `_tier` C on every number you paste. attack_dmg_mult is matched on the strongest scheduled attack only; a final form is matched at the shell's nominal arrival level, so at runtime its HP lands above target.)")
	for w: String in result.warnings:
		lines.append("WARNING: " + w)
	return "\n".join(lines)
