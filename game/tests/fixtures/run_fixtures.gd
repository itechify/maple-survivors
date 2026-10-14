extends RefCounted
## Synthetic data for the sim-run tests (no Nexon data): Skill.wz-shaped skill imgs, Mob.wz-shaped mob imgs and a
## large multi-platform map, plus RunWorld setups built from them and the real game/data JSON (DataRepo).
##
## Canonical numbers are the v83 values recorded in docs/research/cosmic-data.md section 4 / 6 and
## docs/research/wz-inventory.md section 6 (level 1 and max level of each skill, the mob info rows); levels in between
## are filled in by linear interpolation (synthetic, labelled as such where tests rely on them).

const WF := preload("res://tests/fixtures/world_fixtures.gd")


## Skill.wz-shaped imgs keyed by book ("000", "200", "210") like setup.skill_imgs.
static func skill_imgs() -> Dictionary:
	var snails := {}
	var fix := [10.0, 25.0, 40.0]
	var mp := [3.0, 5.0, 7.0]
	for lv in 3:
		snails[str(lv + 1)] = {"hs": "h%d" % (lv + 1), "mpCon": mp[lv], "fixdamage": fix[lv],
			"ball": _anim(3, 90.0, 32, 35), "hit": {"0": _anim(6, 90.0, 76, 79)}}
	var b000 := {"skill": {
		"0001000": {"icon": _canvas(32, 32), "level": snails},
		"0001001": {"icon": _canvas(32, 32), "level": _levels(3, {"mpCon": [5.0, 15.0], "x": [4.0, 12.0]})},
		"0001002": {"icon": _canvas(32, 32), "level": _levels(3, {"mpCon": [4.0, 10.0], "speed": [10.0, 20.0]})},
	}}
	var b200 := {"skill": {
		"2000000": {"icon": _canvas(32, 32), "level": _levels(16, {})},
		"2000001": {"icon": _canvas(32, 32), "level": _levels(10, {"x": [2.0, 20.0], "y": [1.0, 10.0]})},
		"2001002": {"icon": _canvas(32, 32), "action": {"0": "alert2"}, "effect": _anim(12, 100.0, 60, 60),
			"level": _levels(20, {"time": [111.0, 600.0], "mpCon": [6.0, 12.0], "x": [11.0, 80.0]})},
		"2001003": {"icon": _canvas(32, 32), "action": {"0": "alert2"},
			"level": _levels(20, {"time": [54.0, 400.0], "mpCon": [8.0, 16.0], "pdd": [2.0, 40.0]})},
		"2001004": {"icon": _canvas(32, 32), "ball": _anim(4, 80.0, 33, 33),
			"hit": {"0": _anim(3, 90.0, 60, 60), "1": _anim(3, 90.0, 60, 60)},
			"level": _levels(20, {"mpCon": [6.0, 14.0], "mad": [20.0, 55.0], "mastery": [1.0, 10.0]})},
		"2001005": {"icon": _canvas(32, 32), "req": {"2001004": 1.0}, "hit": {"0": _anim(5, 120.0, 80, 80)},
			"effect": _anim(4, 80.0, 86, 80),
			"CharLevel": {"10": {"hit": {"0": _anim(5, 120.0, 80, 80)}, "effect": _anim(8, 80.0, 86, 80)}},
			"level": _levels(20, {"mpCon": [10.0, 20.0], "mad": [11.0, 40.0], "mastery": [1.0, 10.0],
				"attackCount": [2.0, 2.0]})},
	}}
	var b210 := {"skill": {
		"2101004": {"icon": _canvas(32, 32), "elemAttr": "f", "action": {"0": "shoot1"},
			"ball": _anim(3, 30.0, 84, 20), "hit": {"0": _anim(5, 90.0, 60, 60)},
			"level": _levels(30, {"mpCon": [14.0, 28.0], "mad": [33.0, 120.0], "mastery": [1.0, 10.0]})},
	}}
	return {"000": b000, "200": b200, "210": b210}


## Canonical info rows of the stage mobs (cosmic-data.md section 6).
const MOB_INFO := {
	100100: {"level": 1, "maxHP": 8, "exp": 3, "PADamage": 12, "PDDamage": 0, "MDDamage": 0, "speed": -65},
	100101: {"level": 2, "maxHP": 15, "exp": 4, "PADamage": 17, "PDDamage": 0, "MDDamage": 0, "speed": -50},
	120100: {"level": 2, "maxHP": 20, "exp": 5, "PADamage": 17, "PDDamage": 0, "MDDamage": 0, "speed": -30},
	130101: {"level": 4, "maxHP": 40, "exp": 8, "PADamage": 27, "PDDamage": 3, "MDDamage": 10, "speed": -50},
	210100: {"level": 6, "maxHP": 50, "exp": 10, "PADamage": 32, "PDDamage": 5, "MDDamage": 10, "speed": -20,
		"jump": true},
	1210100: {"level": 7, "maxHP": 75, "exp": 15, "PADamage": 37, "PDDamage": 5, "MDDamage": 20, "speed": 0,
		"jump": true},
	1210102: {"level": 8, "maxHP": 80, "exp": 15, "PADamage": 42, "PDDamage": 0, "MDDamage": 10, "speed": 0,
		"jump": true},
	1110100: {"level": 15, "maxHP": 250, "exp": 26, "PADamage": 82, "PDDamage": 12, "MDDamage": 40, "speed": -20},
	9300063: {"level": 6, "maxHP": 60, "exp": 22, "PADamage": 22, "PDDamage": 5, "MDDamage": 20, "flySpeed": -28},
	9300062: {"level": 8, "maxHP": 80, "exp": 10, "PADamage": 25, "PDDamage": 5, "MDDamage": 30, "flySpeed": -30},
	9300064: {"level": 11, "maxHP": 155, "exp": 22, "PADamage": 35, "PDDamage": 10, "MDDamage": 40, "flySpeed": -50},
	2300100: {"level": 20, "maxHP": 300, "exp": 33, "PADamage": 85, "PDDamage": 20, "MDDamage": 20, "flySpeed": 5},
}


## Mob.wz-shaped img for one of MOB_INFO's ids (snail-like frames; a jump stance for jumpers).
static func mob_img(id: int) -> Dictionary:
	var info: Dictionary = MOB_INFO[id]
	var img := WF.mob_img(bool(info.get("jump", false)))
	var i: Dictionary = img.info
	for k: String in info:
		if k != "jump":
			i[k] = float(info[k])
	if not bool(info.get("jump", false)):
		img.erase("jump")
	if info.has("flySpeed"):
		img.fly = img.move
		img.erase("move")
		img.erase("stand")
	return img


## setup.mob_imgs for every MOB_INFO id.
static func mob_imgs() -> Dictionary:
	var out := {}
	for id: int in MOB_INFO:
		out[id] = mob_img(id)
	return out


## A 4000 x ~950 px map shaped like a v83 hunting ground: ground with a pit and a raised block, three tiers of floating
## platforms 120-140 px apart (too high for a mob hop, so they are reached by dropping or by spawning there), one low
## step 60 px above the ground (a jump edge), two ladders and spawn portals on the ground. WZ-shaped
## (foothold/<layer>/<group>/<id> with prev/next ids).
static func big_map_img() -> Dictionary:
	var segs: Array = []
	_chain(segs, [Vector2(-1000, 200), Vector2(0, 200), Vector2(900, 200)])
	segs.append([Vector2(900, 200), Vector2(900, 260)])
	_chain(segs, [Vector2(900, 260), Vector2(1100, 260)])
	segs.append([Vector2(1100, 260), Vector2(1100, 200)])
	_chain(segs, [Vector2(1100, 200), Vector2(1800, 200)])
	segs.append([Vector2(1800, 200), Vector2(1800, 150)])
	_chain(segs, [Vector2(1800, 150), Vector2(2200, 150)])
	segs.append([Vector2(2200, 150), Vector2(2200, 200)])
	_chain(segs, [Vector2(2200, 200), Vector2(2600, 220), Vector2(3000, 200)])
	_chain(segs, [Vector2(2350, 150), Vector2(2550, 150)])
	var y := 80.0
	for tier in 3:
		for p in 6:
			var x0 := -900.0 + p * 650.0 + tier * 90.0
			var w := 260.0 + 40.0 * ((p + tier) % 3)
			var pts: Array = [Vector2(x0, y)]
			for s in 4:
				pts.append(Vector2(x0 + w * (s + 1) / 4.0, y - 6.0 * ((s + p) % 2)))
			_chain(segs, pts)
		y -= 140.0
	var fh := {}
	for i in segs.size():
		var s: Array = segs[i]
		fh[str(i + 1)] = {"x1": s[0].x, "y1": s[0].y, "x2": s[1].x, "y2": s[1].y, "prev": 0.0, "next": 0.0}
	for i in segs.size():
		for j in segs.size():
			if i != j and segs[i][1] == segs[j][0]:
				fh[str(i + 1)].next = float(j + 1)
				fh[str(j + 1)].prev = float(i + 1)
	return {
		"info": {"version": 10.0, "bgm": "Bgm00/Test"},
		"foothold": {"1": {"0": fh}},
		"ladderRope": {
			"1": {"l": 1.0, "uf": 1.0, "x": 1200.0, "y1": 82.0, "y2": 198.0, "page": 1.0},
			"2": {"l": 0.0, "uf": 1.0, "x": -100.0, "y1": 82.0, "y2": 198.0, "page": 1.0},
		},
		"portal": {
			"0": {"pn": "sp", "pt": 0.0, "x": 400.0, "y": 180.0},
			"1": {"pn": "sp", "pt": 0.0, "x": 1500.0, "y": 180.0},
		},
	}


## A RunWorld setup on the synthetic map with the real game data files.
static func setup(stage := "henesys_hg1", p_seed := 12345, data: Dictionary = {}) -> Dictionary:
	return {
		"map_img": big_map_img(),
		"physics_img": WF.physics_img_v83(),
		"mob_imgs": mob_imgs(),
		"skill_imgs": skill_imgs(),
		# Synthetic item nodes with independently verified v83 restore amounts.
		"item_info": {2000000: {"spec": {"hp": 50}}, 2000001: {"spec": {"hp": 150}},
			2000002: {"spec": {"hp": 300}}, 2000003: {"spec": {"mp": 100}}, 2000006: {"spec": {"mp": 300}}},
		"data": data if not data.is_empty() else DataRepo.load_all(),
		"stage": stage,
		"seed": p_seed,
		"view_size": Vector2(800, 600),
	}


## Level nodes 1..n; fields maps name -> [value at level 1, value at level n] (linear in between, rounded).
static func _levels(n: int, fields: Dictionary) -> Dictionary:
	var out := {}
	for lv in range(1, n + 1):
		var node := {"hs": "h%d" % lv}
		var f := float(lv - 1) / float(maxi(1, n - 1))
		for k: String in fields:
			var ab: Array = fields[k]
			node[k] = float(roundi(lerpf(float(ab[0]), float(ab[1]), f)))
		out[str(lv)] = node
	return out


static func _canvas(w: int, h: int) -> Dictionary:
	return {"$canvas": [0.0, 0.0, 0.0, float(w), float(h)], "origin": {"$v": [0.0, float(h)]}}


static func _anim(frames: int, delay: float, w: int, h: int) -> Dictionary:
	var out := {}
	for i in frames:
		out[str(i)] = {"$canvas": [0.0, 0.0, 0.0, float(w), float(h)], "origin": {"$v": [w / 2.0, h / 2.0]},
			"delay": delay}
	return out


static func _chain(segs: Array, pts: Array) -> void:
	for i in pts.size() - 1:
		segs.append([pts[i], pts[i + 1]])


## The kiting bot (BotInput.decide, game/scripts/sim/bot_input.gd); `memo` keeps its state between ticks.
static func bot_input(w: RunWorld, memo: Dictionary) -> MoveInput:
	return BotInput.decide(w, memo)


## Resolves an open window like BotInput: the first available job (else "Not now") and BotInput.pick_card_for's card.
static func auto_choose(w: RunWorld) -> void:
	BotInput.auto_choose(w)


## The real game data with an extra stage "quiet" (the henesys_hg1 pool, but no spawns, bursts or elites) so tests
## can place every mob themselves.
static func quiet_data() -> Dictionary:
	var data := DataRepo.load_all()
	# Isolated combat/physics tests opt into potion rolls explicitly when they need them.
	data.balance.potions.drops = {"normal": {"hp": 0.0, "mp": 0.0}, "elite": {"hp": 0.0, "mp": 0.0}}
	var stages: Dictionary = data.stages.stages
	var pool := {}
	for id: int in MOB_INFO:
		pool[str(id)] = 1.0
	stages["quiet"] = {
		"map_id": 0, "name": "quiet", "duration": 900.0, "hard_cap": 400,
		"keyframes": [{"t": 0.0, "rate": 0.0, "max_alive": 0.0, "hp": 1.0, "speed": 1.0, "pool": pool}],
		"bursts": {}, "elites": {},
	}
	return data


## A RunWorld on the synthetic map with the "quiet" stage, the player standing on the ground at x.
static func quiet_world(x := 400.0, p_seed := 7) -> RunWorld:
	var w := RunWorld.new(setup("quiet", p_seed, quiet_data()))
	place_player(w, x)
	return w


## Changes the job like RunWorld.change_job (MP, guarantee) but forgets the skills the job grants (jobs.json
## grants.skills, e.g. the Magician's Energy Bolt), for tests of a Magician who has not learned them yet.
static func change_job_bare(w: RunWorld, job_id: int) -> void:
	w.change_job(job_id)
	for key: Variant in w.jobs.job(job_id).get("grants", {}).get("skills", []):
		w.loadout.ranks.erase(String(key))
		w.loadout.order.erase(String(key))
	w.loadout.version += 1
	w.refresh_player_stats()


## Stands the player on the first floor at or below (x, y) (default: the ground) and refreshes the view.
static func place_player(w: RunWorld, x: float, y := 190.0) -> void:
	var f := w.fhm.find_below(x, y)
	w.player.place(Vector2(x, w.fhm.y_at(f, x)), w.fhm)
	w.update_view()


## Spawns mob `mob_id` standing on the first floor at or below (x, y) (default: the ground); returns its slot.
static func put_mob(w: RunWorld, mob_id: int, x: float, y := 190.0, hp_mult := 1.0, elite := false) -> int:
	var f := w.fhm.find_below(x, y)
	return w.spawn_mob(int(w.kind_of_id[mob_id]), Vector2(x, w.fhm.y_at(f, x)), f, hp_mult, elite)


## A WZ-shaped map img from segment Dictionaries {x1, y1, x2, y2} (ends that touch are linked), with optional spawn
## portals at `portals` (Vector2 list).
static func map_from_segments(list: Array, portals: Array = []) -> Dictionary:
	var fh := {}
	for i in list.size():
		var s: Dictionary = list[i]
		fh[str(i + 1)] = {"x1": float(s.x1), "y1": float(s.y1), "x2": float(s.x2), "y2": float(s.y2),
			"prev": 0.0, "next": 0.0}
	for i in list.size():
		for j in list.size():
			var a: Dictionary = list[i]
			var b: Dictionary = list[j]
			if i != j and float(a.x2) == float(b.x1) and float(a.y2) == float(b.y1):
				fh[str(i + 1)].next = float(j + 1)
				fh[str(j + 1)].prev = float(i + 1)
	var po := {}
	for k in portals.size():
		po[str(k)] = {"pn": "sp", "pt": 0.0, "x": portals[k].x, "y": portals[k].y}
	return {"info": {}, "foothold": {"1": {"0": fh}}, "portal": po}
