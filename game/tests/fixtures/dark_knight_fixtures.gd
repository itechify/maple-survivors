extends RefCounted
## Synthetic Skill.wz for the Dark Knight (spec #348, D10 #358): every pool skill, Rush and the Beholder with the numbers the
## D1-D9 tests use, a spear with the swing reach the way Hero's oracle got it (#346), and a `setup` for job 132. Used by the bot
## test and the baseline oracle; the skill tests keep their own builders. No asset cache needed.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const SPEAR := 1432000
const POLE_ARM := 1442000
const BEHOLDER_LEVELS := [2, 3, 4, 5, 7, 8, 9, 10]
const SUB_LEVELS := [4, 7, 10, 13, 16, 19, 22, 25]
const AURA_HP := [85, 170, 200, 280, 360, 390, 470, 500]
const AURA_X := [10, 9, 8, 7, 7, 6, 5, 4]
const HEX_ROWS := [
	{"pdd": 20, "time": 20, "x": 42},
	{"pdd": 40, "mdd": 25, "time": 40, "x": 36},
	{"pdd": 40, "mdd": 25, "time": 40, "x": 30},
	{"pdd": 60, "mdd": 50, "acc": 10, "time": 60, "x": 24},
	{"pdd": 80, "mdd": 75, "acc": 20, "eva": 30, "time": 80, "x": 18},
	{"pdd": 80, "mdd": 75, "acc": 20, "eva": 30, "time": 80, "x": 12},
	{"pdd": 100, "mdd": 100, "acc": 25, "eva": 50, "pad": 6, "time": 100, "x": 7},
	{"pdd": 100, "mdd": 100, "acc": 25, "eva": 50, "pad": 15, "time": 99, "x": 4},
]
const UNLOCK := {"pdd": 1, "mdd": 6, "acc": 11, "eva": 16, "pad": 21}
const TIME_WZ := [720, 780, 840, 900, 1020, 1080, 1140, 1200]
## Dragon Roar at its eight mapped levels (Skill.wz 1311006, D7): damage %, x (HP cost % of max HP), y (stun s), box half-width.
const ROAR_LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
const ROAR_DAMAGE := [114, 138, 160, 175, 195, 212, 228, 240]
const ROAR_COST := [56, 52, 48, 45, 41, 37, 33, 30]
const ROAR_STUN := [4, 4, 3, 3, 3, 2, 2, 2]
const ROAR_HALF_W := [140, 180, 220, 250, 290, 330, 370, 400]
const ROAR_TOP := [-155, -185, -215, -237, -267, -297, -327, -350]
const ROAR_BOTTOM := [55, 85, 115, 138, 168, 198, 228, 250]


static func _anim(frames: int, ms := 100.0) -> Dictionary:
	var out := {}
	for i in frames:
		out[str(i)] = {"delay": ms}
	return out


static func _sub_levels(rows: Array, unlock: Dictionary) -> Dictionary:
	var levels := {}
	for lv in range(1, 26):
		var row: Dictionary = rows[SUB_LEVELS.size() - 1]
		for i in SUB_LEVELS.size():
			if SUB_LEVELS[i] >= lv:
				row = rows[i]
				break
		var out := {}
		for field: String in row:
			if lv >= int(unlock.get(field, 1)):
				out[field] = float(row[field])
		levels[str(lv)] = out
	return levels


static func _crusher_levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		var lt := [-130, -50] if lv <= 8 else [-140, -60] if lv <= 15 else [-150, -70]
		levels[str(lv)] = {"damage": 50 + lv, "attackCount": 2 if lv <= 15 else 3, "mobCount": ((lv - 1) % 15) / 5 + 1,
			"action": "burster1" if lv <= 15 else "burster2", "lt": {"$v": lt}, "rb": {"$v": [-16, 0]}}
	return levels


static func _roar_levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		var i := ROAR_LEVELS.find(lv)
		var r := i if i >= 0 else clampi(lv / 4, 0, 7)
		levels[str(lv)] = {"damage": ROAR_DAMAGE[r], "x": ROAR_COST[r], "y": ROAR_STUN[r], "mobCount": 15, "mpCon": 16,
			"lt": {"$v": [-ROAR_HALF_W[r], ROAR_TOP[r]]}, "rb": {"$v": [ROAR_HALF_W[r], ROAR_BOTTOM[r]]}}
	return levels


static func _plain_levels(fields: Dictionary) -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = fields.duplicate()
	return levels


## Synthetic Skill.wz for every Dark Knight skill (books 131 and 132) on top of the shared F/P, Warrior and Hero ones.
static func skill_imgs() -> Dictionary:
	var imgs := RF.skill_imgs()
	var fury := _plain_levels({"damage": 150, "mobCount": 6, "hpCon": 20})
	var sacrifice := _plain_levels({"damage": 200, "x": 18})
	imgs["131"] = {"skill": {
		"1311001": {"level": _crusher_levels()}, "1311002": {"level": _crusher_levels()},
		"1311003": {"level": fury}, "1311004": {"level": fury},
		"1311005": {"level": sacrifice},
		"1311006": {"level": _roar_levels()},
	}}
	var magnet := {}
	var rush := {}
	for lv in range(1, 31):
		magnet[str(lv)] = {"mobCount": 6, "prop": 40 + 2 * lv, "range": 160 + 8 * lv}
		var reach := 160.0 if lv < 4 else 170.0 if lv == 4 else 250.0
		rush[str(lv)] = {"damage": 72.0 if lv < 4 else 78.0 if lv == 4 else 130.0, "mobCount": 15.0,
			"lt": {"$v": [-reach, -50.0]}, "rb": {"$v": [0.0, 0.0]}}
	var beholder := {"1": {"time": 660.0}}
	for i in BEHOLDER_LEVELS.size():
		beholder[str(BEHOLDER_LEVELS[i])] = {"time": float(TIME_WZ[i]), "mastery": 1.0}
	for lv in range(1, 11):
		if not beholder.has(str(lv)):
			beholder[str(lv)] = {"time": 700.0}
	var summon := {"summoned": _anim(16), "stand": _anim(16), "move": _anim(8), "die": _anim(8), "skill1": _anim(24)}
	for n in range(2, 7):
		summon["skill%d" % n] = _anim(16)
	var aura_rows := []
	for i in 8:
		aura_rows.append({"hp": AURA_HP[i], "x": AURA_X[i]})
	imgs["132"] = {"skill": {
		"1321001": {"level": magnet},
		"1321003": {"icon": RF._canvas(32, 32), "action": {"0": "rush"}, "effect": RF._anim(7, 120.0, 86, 98), "level": rush},
		"1321007": {"level": beholder, "summon": summon, "affected": _anim(9, 90.0)},
		"1320008": {"level": _sub_levels(aura_rows, {})},
		"1320009": {"level": _sub_levels(HEX_ROWS, UNLOCK)},
	}}
	return imgs


## A RunWorld setup for a Dark Knight (job 132): the synthetic map with the spear's swing reach (RF.with_basic_attack, which
## carries the Spear and the afterimage of every one-handed stance), the pole arm beside it, every Dark Knight skill defined and
## 132 playable in `data`.
static func setup(stage := "henesys", p_seed := 1, data: Dictionary = {}) -> Dictionary:
	if data.is_empty():
		data = DataRepo.load_all()
	data.jobs_survivor.jobs["132"]["playable"] = true
	var s := RF.with_basic_attack(RF.setup(stage, p_seed, data))
	s.equipment_info[POLE_ARM] = {"reqJob": 13, "reqLevel": 10, "incPAD": 34.0, "attackSpeed": 6.0, "afterImage": "spear",
		"sfx": "spear"}
	s.body_img["rush"] = {"0": {"delay": 300.0}}
	s.skill_imgs = skill_imgs()
	s["job"] = 132
	return s
