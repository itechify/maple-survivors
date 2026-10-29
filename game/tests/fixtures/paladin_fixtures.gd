extends RefCounted
## Synthetic Paladin (122) worlds for the bot test and the baseline oracle (spec #308, P9 #317). Skill.wz-shaped books for every
## Paladin skill (Rush, Blast, Monster Magnet, the four Charges, Charged Blow and Heaven's Hammer: shapes and the eight mapped
## levels from P4-P8's tests, intermediate levels repeat the next mapped one), the shipped skill data and the synthetic Henesys
## stage. Power Strike and Slash Blast are Hero's definitions and need no book. No cache is read.

const RF := preload("res://tests/fixtures/run_fixtures.gd")

## The Paladin pool the oracle is frozen to (jobs/paladin.json `skill_pool` at capture).
const POOL := ["power_strike", "slash_blast", "blast", "monster_magnet_paladin", "fire_charge", "ice_charge", "thunder_charge",
	"holy_charge"]
## Rank -> WZ level of the 30-level tables and of Holy Charge's 20-level table (tier A reading, P1 #309).
const LEVELS_30 := [4, 8, 12, 15, 19, 23, 27, 30]
const LEVELS_20 := [3, 5, 8, 10, 13, 15, 18, 20]
const CHARGE_DAMAGE := {
	1211003: [105, 109, 111, 112, 114, 116, 118, 120],
	1211005: [102, 103, 104, 105, 107, 108, 109, 110],
	1211007: [107, 111, 115, 117, 119, 121, 123, 125],
}
const BLOW := {"damage": [168, 176, 186, 195, 207, 222, 238, 250], "prop": [38, 46, 54, 60, 68, 76, 84, 90],
	"time": [2, 2, 3, 3, 3, 4, 4, 4], "range": [130, 130, 140, 140, 140, 150, 150, 150],
	"hpCon": [15, 15, 20, 20, 20, 25, 25, 25], "mobCount": [6, 6, 6, 6, 6, 6, 6, 6]}
const HOLY_DAMAGE := [106, 110, 116, 120, 126, 130, 136, 140]
const HAMMER_DAMAGE := [480, 560, 640, 700, 780, 830, 870, 900]
## The creation Mace (1322000) is not in the shared fixtures' equipment table; its swing is the Mace afterimage's.
const MACE_INFO := {"incPAD": 34.0, "attackSpeed": 6.0, "afterImage": "mace", "sfx": "mace"}


## `count` level rows from `rows` (field -> its eight values at `mapped`): a mapped level holds its value, the levels between
## the next mapped one's.
static func levels(rows: Dictionary, mapped: Array, count: int) -> Dictionary:
	var out := {}
	for lv in range(1, count + 1):
		var index := 0
		while mapped[index] < lv:
			index += 1
		var row := {}
		for field: String in rows:
			row[field] = rows[field][index]
		out[str(lv)] = row
	return out


static func _box(rows: Dictionary, lt: Array, rb: Array) -> Dictionary:
	for row: Dictionary in rows.values():
		row["lt"] = {"$v": lt}
		row["rb"] = {"$v": rb}
	return rows


## Writes the books 121 and 122 into `setup.skill_imgs`.
static func books(setup: Dictionary) -> void:
	var magnet := {}
	var blast := {}
	for lv in range(1, 31):
		magnet[str(lv)] = {"mobCount": 6, "prop": 40 + 2 * lv, "range": 160 + 8 * lv}
		blast[str(lv)] = {"damage": 160 + 13 * lv}
	var rush := {}
	for lv in range(1, 31):
		var reach := 160.0 if lv < 4 else 170.0 if lv == 4 else 250.0
		rush[str(lv)] = {"damage": 72.0 if lv < 4 else 78.0 if lv == 4 else 130.0, "mobCount": 15.0,
			"lt": {"$v": [-reach, -50.0]}, "rb": {"$v": [0.0, 0.0]}}
	var book_121 := {}
	for id: int in CHARGE_DAMAGE:
		book_121[str(id)] = {"level": levels({"damage": CHARGE_DAMAGE[id]}, LEVELS_30, 30)}
	book_121["1211002"] = {"level": levels(BLOW, LEVELS_30, 30)}
	setup.skill_imgs["121"] = {"skill": book_121}
	setup.skill_imgs["122"] = {"skill": {
		"1221007": {"level": rush},
		"1221009": {"level": blast},
		"1221001": {"level": magnet},
		"1221003": {"level": levels({"damage": HOLY_DAMAGE}, LEVELS_20, 20)},
		"1221011": {"level": _box(levels({"damage": HAMMER_DAMAGE, "mobCount": [15, 15, 15, 15, 15, 15, 15, 15]}, LEVELS_30, 30),
			[-400, -350], [400, 250])}}}


## A Paladin setup on `stage` (the synthetic stage by default "henesys"): job 122, the Mace's swing and every Paladin book.
static func setup(stage := "henesys", p_seed := 317, data: Dictionary = {}) -> Dictionary:
	var out := RF.with_basic_attack(RF.setup(stage, p_seed, data))
	out.equipment_info[1322000] = MACE_INFO.duplicate()
	books(out)
	out["job"] = 122
	return out


## A Paladin round on the quiet stage with the player at x 400 facing right, god mode on.
static func round_world(p_seed := 317) -> RunWorld:
	var w := RunWorld.new(setup("quiet", p_seed, RF.quiet_data()))
	RF.place_player(w, 400)
	w.player.facing = 1
	w.god = true
	return w
