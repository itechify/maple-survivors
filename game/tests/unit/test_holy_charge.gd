extends TestCase
## Holy Charge and Heaven's Hammer (spec #308, P8 #316): the level-20 Form and its once-per-window delayed screen strike.
## Synthetic Skill.wz books shaped like 121.img / 122.img (the eight mapped levels hold the real numbers, the levels between
## repeat the next mapped one), the shipped skill data and a quiet Paladin world; the real-cache tests at the end read Skill.wz
## itself and SKIP without it.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const CASTER_X := 1000.0
const FLAT := [{"x1": 0, "y1": 200, "x2": 2000, "y2": 200}]
## Rank -> WZ level of the 20-level table (Holy Charge) and of the 30-level table (Charged Blow and the Hammer), tier C ADR 0006.
const HOLY_LEVELS := [3, 5, 8, 10, 13, 15, 18, 20]
const LEVELS_30 := [4, 8, 12, 15, 19, 23, 27, 30]
## Tier A, Skill.wz 122.img `damage` at the eight mapped levels (P1 #309).
const HOLY_DAMAGE := [106, 110, 116, 120, 126, 130, 136, 140]
const HAMMER_DAMAGE := [480, 560, 640, 700, 780, 830, 870, 900]
const BLOW := {"damage": [168, 176, 186, 195, 207, 222, 238, 250], "prop": [38, 46, 54, 60, 68, 76, 84, 90],
	"time": [2, 2, 3, 3, 3, 4, 4, 4], "range": [130, 130, 140, 140, 140, 150, 150, 150],
	"hpCon": [15, 15, 20, 20, 20, 25, 25, 25]}
## Ticks of the first cast (0.5 s in) and of the strike (1.56 s after the cast, P1 #309).
const CAST_TICKS := 30
const DELAY := 1.56

## slot -> x of the mobs `_mob` placed: knock-back from Charged Blow must not walk them out of the boxes between casts.
var _pinned := {}


## `levels` count rows from `rows` (field -> its eight values): a mapped level holds its value, the levels between the next one's.
static func _levels(rows: Dictionary, mapped: Array, levels: int) -> Dictionary:
	var out := {}
	for lv in range(1, levels + 1):
		var index := 0
		while mapped[index] < lv:
			index += 1
		var row := {}
		for field: String in rows:
			row[field] = rows[field][index]
		out[str(lv)] = row
	return out


static func _books(setup: Dictionary) -> void:
	var blow := BLOW.duplicate()
	blow["mobCount"] = [6, 6, 6, 6, 6, 6, 6, 6]
	setup.skill_imgs["121"] = {"skill": {"1211002": {"level": _levels(blow, LEVELS_30, 30)}}}
	var hammer := _levels({"damage": HAMMER_DAMAGE, "mobCount": [15, 15, 15, 15, 15, 15, 15, 15]}, LEVELS_30, 30)
	for level: Dictionary in hammer.values():
		level["lt"] = {"$v": [-400, -350]}
		level["rb"] = {"$v": [400, 250]}
	setup.skill_imgs["122"] = {"skill": {
		"1221003": {"level": _levels({"damage": HOLY_DAMAGE}, HOLY_LEVELS, 20)},
		"1221011": {"level": hammer}}}


## A quiet Paladin (122) on a flat floor at x 1000 that learned `keys`, with mobs that never walk.
func _world(keys: Array = [], p_seed := 316) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["122"]["playable"] = true # P9 #317 flips it for real; the pool's cards need it
	data.stages.stages.quiet.maps.append(data.stages.stages.quiet.maps[0].duplicate(true)) # a second map to transfer to
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	_books(setup)
	var w := RunWorld.new(setup)
	w.set_job(122)
	w.bounds = Rect2(0, -500, 2000, 1000)
	w.fhm = FootholdMap.from_segments(FLAT)
	w.swarm.fhm = w.fhm
	RF.place_player(w, CASTER_X)
	w.loadout.order.clear()
	w.loadout.ranks.clear()
	for key: String in keys:
		w.learn_skill(key)
	w.god = true # mob contact must not push the caster off the crowd, and Charged Blow's HP cost is never lethal anyway
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
		mk.move_speed = 0.0
	w.drain_events()
	_pinned.clear()
	return w


## One tick the way the runner takes it, collecting the events it raised into `log`.
func _tick(w: RunWorld, log: Array, ticks := 1) -> void:
	for i in ticks:
		w.restore_player("hp", 100, "test") # Charged Blow pays HP and waits when it cannot
		w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
		w.runner.step(DT, w)
		log.append_array(w.drain_events())
		for slot: int in _pinned:
			w.swarm.x[slot] = _pinned[slot]


func _mob(w: RunWorld, dx: float, hp := 100000.0, dy := 0.0) -> int:
	var m := RF.put_mob(w, MOB, CASTER_X + dx, 190.0 + dy, hp)
	_pinned[m] = w.swarm.x[m]
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m


## `n` mobs inside the Hammer's box (x -380 .. 380), none within Charged Blow's 130 px, so only the Hammer has targets.
func _screen(w: RunWorld, n := 20) -> Array:
	var slots := []
	for i in n:
		var side := 1.0 if i % 2 == 0 else -1.0
		slots.append(_mob(w, side * (200.0 + 9.0 * i)))
	return slots


func _start(w: RunWorld, rank := 1) -> void:
	w.runner.forms.start(w, "holy_charge", w.loadout.stats("holy_charge", rank))
	w.drain_events()


func _of(log: Array, type: String, skill := "") -> Array:
	return log.filter(func(e: Dictionary) -> bool: return e.type == type and (skill.is_empty() or String(e.get("skill", "")) == skill))


# --- The definitions ---------------------------------------------------------------------------------------------------

func test_holy_charge_is_a_pool_form_of_book_122_with_the_level_20_table() -> void:
	var w := _world()
	assert_true(w.book.has("holy_charge"), "defined by skills/paladin.json")
	var d := w.book.def("holy_charge")
	assert_eq(int(d.skill_id), 1221003)
	assert_eq(String(d.book), "122")
	assert_eq(int(d.job), 122)
	assert_eq(String(d.kind), "form")
	assert_eq(String(d.slot), "active")
	assert_eq(String(d.damage), "none", "a Form deals no damage itself")
	assert_eq(float(d.cooldown), 18.0)
	assert_eq(String(d.cast.rule), "form")
	assert_eq(int(d.cast.mob_within), 400)
	assert_eq(String(d.action), "alert4")
	assert_true("holy_charge" in w.jobs.skill_pool(122), "in the Paladin pool")
	assert_eq(d.form.duration, 12.0)
	assert_eq(d.form.exclusive_group, "paladin_charge", "the group every Charge shares")
	assert_eq(d.form.effects, {"element": "h", "damage": {"field": "damage"}})
	assert_eq(d.form.subs, [{"skill": "charged_blow", "first_after": 1.0, "interval": 3.0},
		{"skill": "heavens_hammer", "first_after": 0.5, "once": true}])
	assert_eq(d.art_by_family.keys(), ["blunt"])
	assert_eq(int(d.art_by_family.blunt), 1221004)
	assert_eq(w.book.rank_table("holy_charge").map(func(v: Variant) -> int: return int(v)), HOLY_LEVELS)
	assert_eq(w.book.max_rank("holy_charge"), 8)
	assert_eq(String(d.effect), "Skill.wz/122.img/skill/1221003/effect")
	assert_eq(String(d.icon), "Skill.wz/122.img/skill/1221003/icon")
	assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/1221003/Use")


func test_heavens_hammer_is_a_pool_less_form_sub_with_a_pending_strike() -> void:
	var w := _world()
	assert_true(w.book.has("heavens_hammer"), "defined by skills/paladin.json")
	var d := w.book.def("heavens_hammer")
	assert_eq(int(d.skill_id), 1221011)
	assert_eq(String(d.book), "122")
	assert_eq(int(d.job), 122)
	assert_eq(String(d.slot), "form_sub")
	assert_eq(d.form_sub_of, ["holy_charge"], "only Holy carries it")
	assert_eq(String(d.damage), "physical")
	assert_eq(String(d.element), "h", "WZ elemAttr h")
	assert_eq(String(d.cast.rule), "box")
	assert_eq(String(d.action), "sanctuary")
	assert_eq(d.pending, {"delay": 1.56, "effect": "", "follow_player": true})
	assert_eq(w.book.rank_table("heavens_hammer").map(func(v: Variant) -> int: return int(v)), LEVELS_30)
	assert_false(d.has("rarity_bonuses"), "a sub-skill has no rarity list")
	assert_true(String(d.sounds.use).ends_with("1221011/Use"))
	assert_true(String(d.sounds.hit).ends_with("1221011/Hit"))
	assert_eq(String(d.effect), "Skill.wz/122.img/skill/1221011/effect")
	for job: Dictionary in w.setup.data.jobs_survivor.jobs.values():
		assert_false("heavens_hammer" in job.get("skill_pool", []), "never in a pool")
	assert_false(w.loadout.add_skill("heavens_hammer"), "the loadout refuses a form_sub")
	for card: Dictionary in w.setup.data.upgrades.cards:
		assert_ne(String(card.get("skill", "")), "heavens_hammer", "not a card")


func test_the_catalog_validates_with_holy_charge_defined() -> void:
	var errors := Array(PlayerForms.validation_errors(_world().book.defs)).filter(func(e: String) -> bool:
		return "holy_charge" in e or "heavens_hammer" in e)
	assert_eq(errors, [])


func test_the_hammer_geometry_and_damage_at_the_eight_ranks() -> void:
	var w := _world()
	for rank in range(1, 9):
		var st := w.loadout.stats("heavens_hammer", rank)
		assert_eq(st.level, LEVELS_30[rank - 1], "rank %d reads the level-30 table" % rank)
		assert_eq(st.mob_count, 15)
		assert_true(bool(st.has_box))
		assert_eq(st.box, Rect2(-400, -350, 800, 600), "lt (-400,-350) rb (400,250) around the player")
		assert_near(float(st.damage_pct), float(HAMMER_DAMAGE[rank - 1]) / 100.0, 1e-9, "rank %d damage" % rank)


# --- Holy Charge itself ------------------------------------------------------------------------------------------------

func test_the_multiplier_follows_the_level_20_table() -> void:
	var w := _world()
	for rank in range(1, 9):
		assert_eq(w.loadout.stats("holy_charge", rank).level, HOLY_LEVELS[rank - 1])
		w.runner.forms.clear(w, "test")
		_start(w, rank)
		var window: Dictionary = w.runner.forms.snapshot()[0]
		assert_eq(window.effects.element, "h")
		assert_near(float(window.effects.damage), float(HOLY_DAMAGE[rank - 1]) / 100.0, 1e-9, "rank %d" % rank)
		assert_eq(window.rank, rank)


func test_every_attack_takes_the_holy_element() -> void:
	# Power Strike and Slash Blast against a holy-weak, a plain and a holy-immune mob (Skill.wz elements: H).
	for key in ["power_strike", "slash_blast"]:
		var damage := {}
		for mult: float in [1.5, 1.0, 0.0]:
			var w := _world([key])
			w.loadout.add_skill_mod(key, "damage", "mul", 50.0) # whole hits large enough for the 1.5 ratio to show
			var m := _mob(w, 60.0)
			w.swarm.mob_kind(m).elements = {"H": mult}
			_start(w)
			var log := []
			_tick(w, log, 90)
			var hits := _of(log, "mob_hit", key).filter(func(e: Dictionary) -> bool: return e.mob == m)
			assert_true(hits.size() > 0, "%s landed at %s" % [key, mult])
			damage[mult] = hits.map(func(e: Dictionary) -> float: return float(e.damage)).reduce(func(a: float, b: float) -> float: return a + b) / hits.size()
		assert_true(float(damage[1.5]) > float(damage[1.0]) * 1.2, "%s: a holy-weak mob takes more" % key)
		assert_eq(float(damage[0.0]), 0.0, "%s: a holy-immune mob takes nothing" % key)


func test_a_charge_in_the_group_blocks_holy_and_holy_blocks_it() -> void:
	var w := _world()
	# A stand-in Charge of the shared group (P7 #315 defines the real ones; the group name is what excludes).
	w.book.defs["test_other_charge"] = w.book.def("holy_charge").duplicate(true)
	w.book.defs["test_other_charge"]["skill_id"] = 1211003
	assert_true(w.runner.forms.admits(w, "holy_charge"))
	_start(w)
	assert_false(w.runner.forms.admits(w, "holy_charge"), "Holy does not overlap itself")
	assert_false(w.runner.forms.admits(w, "test_other_charge"), "nor another Charge")
	w.runner.forms.clear(w, "test")
	assert_true(w.runner.forms.admits(w, "test_other_charge"))
	w.runner.forms.start(w, "test_other_charge", w.loadout.stats("test_other_charge"))
	assert_false(w.runner.forms.admits(w, "holy_charge"), "another Charge does not let Holy overlap it")
	assert_eq(w.runner.forms.snapshot().size(), 1)


func test_art_skill_id_picks_the_blunt_twin_only_for_a_blunt_weapon() -> void:
	var w := _world()
	assert_eq(w.book.art_skill_id("holy_charge", "blunt"), 1221004)
	for family in ["sword", "", "axe"]:
		assert_eq(w.book.art_skill_id("holy_charge", family), 1221003, "family '%s' keeps the sword's" % family)
	assert_eq(w.book.art_skill_id("heavens_hammer", "blunt"), 1221011, "the Hammer has no twin")
	assert_eq(w.book.art_path("holy_charge", "Skill.wz/122.img/skill/1221003/effect", "blunt"), "Skill.wz/122.img/skill/1221004/effect")


# --- Heaven's Hammer: timing -------------------------------------------------------------------------------------------

func test_the_hammer_is_cast_half_a_second_in_and_lands_1_56_seconds_later() -> void:
	var w := _world()
	var mobs := _screen(w, 3)
	_start(w)
	var log := []
	_tick(w, log, CAST_TICKS - 2)
	assert_eq(_of(log, "cast", "heavens_hammer").size(), 0, "not yet at 0.47 s")
	_tick(w, log, 3)
	var casts := _of(log, "cast", "heavens_hammer")
	assert_eq(casts.size(), 1, "cast at 0.5 s")
	assert_eq(int(casts[0].skill_id), 1221011)
	assert_eq(String(casts[0].action), "sanctuary")
	assert_eq(String(casts[0].effect), "Skill.wz/122.img/skill/1221011/effect")
	assert_eq(_of(log, "mob_hit", "heavens_hammer").size(), 0, "a delayed strike: nothing lands with the cast")
	# 1.56 s after the cast (93.6 ticks): no hit at 93 ticks, hits by 95.
	_tick(w, log, 90)
	assert_eq(_of(log, "mob_hit", "heavens_hammer").size(), 0, "still falling 1.5 s on")
	assert_eq(_of(log, "skill_impact", "heavens_hammer").size(), 0)
	_tick(w, log, 5)
	var hits := _of(log, "mob_hit", "heavens_hammer")
	assert_eq(hits.size(), mobs.size(), "every mob in the box is struck once, by the 95th tick after the cast")
	assert_eq(_of(log, "skill_impact", "heavens_hammer").size(), 1)


func test_the_hammer_hits_at_most_15_mobs_inside_the_box() -> void:
	var w := _world()
	var inside := _screen(w, 20)
	var past_x := _mob(w, 450.0) # 50 px past the right edge
	_start(w)
	var log := []
	_tick(w, log, CAST_TICKS + 100)
	var struck := {}
	for e: Dictionary in _of(log, "mob_hit", "heavens_hammer"):
		assert_false(struck.has(int(e.mob)), "each mob once")
		struck[int(e.mob)] = true
	assert_eq(struck.size(), 15, "mobCount 15 of the 21 mobs")
	assert_false(struck.has(past_x), "a mob past the box edge is never struck")
	assert_eq(inside.size(), 20)


func test_the_hammer_waits_for_a_mob_in_the_box_and_then_casts_once() -> void:
	var w := _world()
	_start(w)
	var log := []
	_tick(w, log, 150)
	assert_eq(_of(log, "cast", "heavens_hammer").size(), 0, "no mob in the box: the due Hammer waits (it is not wasted)")
	_mob(w, 300.0)
	_tick(w, log, 2)
	assert_eq(_of(log, "cast", "heavens_hammer").size(), 1, "it goes the tick a mob is in the box")
	_tick(w, log, 600)
	assert_eq(_of(log, "cast", "heavens_hammer").size(), 1)


func test_it_never_fires_twice_in_one_window_and_fires_again_in_a_new_one() -> void:
	var w := _world()
	_screen(w, 5)
	_start(w)
	var log := []
	_tick(w, log, 60 * 11) # the whole 12 s window, less a second
	assert_eq(_of(log, "cast", "heavens_hammer").size(), 1, "once per window")
	assert_eq(_of(log, "skill_impact", "heavens_hammer").size(), 1)
	_tick(w, log, 120)
	assert_eq(_of(log, "form_ended").size(), 1)
	_start(w) # a recast Holy Charge opens a new window
	_tick(w, log, 60 * 4)
	assert_eq(_of(log, "cast", "heavens_hammer").size(), 2, "a new window, a new Hammer")
	assert_eq(_of(log, "skill_impact", "heavens_hammer").size(), 2)


func test_the_real_cast_path_gives_one_hammer_per_window_over_many_windows() -> void:
	var w := _world(["holy_charge"])
	_screen(w, 10)
	var log := []
	_tick(w, log, 60 * 40)
	var windows := _of(log, "form_started").size()
	assert_true(windows >= 2, "Holy cast again after its 18 s cooldown: %d" % windows)
	assert_eq(_of(log, "cast", "heavens_hammer").size(), windows, "exactly one Hammer per window")
	assert_eq(_of(log, "skill_impact", "heavens_hammer").size(), windows)


func test_no_hammer_when_the_window_ends_before_it_is_due() -> void:
	var w := _world()
	w.loadout.add_skill_mod("holy_charge", "form_time", "mul", 0.03) # a 0.36 s window
	_screen(w, 5)
	_start(w)
	var log := []
	_tick(w, log, 60 * 4)
	assert_eq(_of(log, "form_ended").size(), 1)
	assert_eq(_of(log, "cast", "heavens_hammer").size(), 0, "the window closed before 0.5 s")
	assert_eq(_of(log, "mob_hit", "heavens_hammer").size(), 0)


func test_a_strike_in_flight_outlives_its_window() -> void:
	# The Hammer is a committed map-space strike (as Meteor Shower): a 1.0 s window ends before it lands and it still does.
	var w := _world()
	w.loadout.add_skill_mod("holy_charge", "form_time", "mul", 1.0 / 12.0)
	_screen(w, 5)
	_start(w)
	var log := []
	_tick(w, log, 60 * 4)
	assert_eq(_of(log, "form_ended").size(), 1)
	assert_eq(_of(log, "cast", "heavens_hammer").size(), 1)
	assert_eq(_of(log, "mob_hit", "heavens_hammer").size(), 5)


func test_the_strike_follows_the_player() -> void:
	var w := _world()
	var near := _mob(w, 100.0)
	_start(w)
	var log := []
	_tick(w, log, CAST_TICKS + 5)
	assert_eq(_of(log, "cast", "heavens_hammer").size(), 1)
	# The player walks 300 px right while it falls; a mob that was 500 px away is now inside the box, the first is 200 behind.
	var far := _mob(w, 500.0)
	w.player.pos.x += 300.0
	_tick(w, log, 100)
	var struck := _of(log, "mob_hit", "heavens_hammer").map(func(e: Dictionary) -> int: return int(e.mob))
	assert_true(far in struck, "the box is re-centred on the player where it lands")
	assert_true(near in struck, "100 px behind the old spot is still 200 px behind the new")


func test_a_map_transfer_loses_the_pending_strike_and_keeps_the_window_state() -> void:
	var control := _world()
	_screen(control, 5)
	_start(control)
	var control_log := []
	_tick(control, control_log, CAST_TICKS + 100)
	assert_eq(_of(control_log, "mob_hit", "heavens_hammer").size(), 5, "control: the strike lands")
	var w := _world()
	_screen(w, 5)
	_start(w)
	var log := []
	_tick(w, log, CAST_TICKS + 5)
	assert_eq(_of(log, "cast", "heavens_hammer").size(), 1)
	w.transfer_pending = true
	w.advance_map()
	_screen(w, 5)
	_tick(w, log, 100)
	assert_eq(_of(log, "mob_hit", "heavens_hammer").size(), 0, "the strike in flight is lost")
	assert_eq(_of(log, "skill_impact", "heavens_hammer").size(), 0)
	assert_eq(w.runner.forms.snapshot().size(), 1, "the window itself carries over")
	_tick(w, log, 60 * 3)
	assert_eq(_of(log, "cast", "heavens_hammer").size(), 1, "the consumed Hammer is not recast on the new map")


# --- Heaven's Hammer: rank and the Charge's modifiers -----------------------------------------------------------------

func test_the_hammer_ranks_with_holy_charge_through_the_level_30_table() -> void:
	for rank in [1, 4, 8]:
		var w := _world()
		w.loadout.ranks["holy_charge"] = rank
		_screen(w, 3)
		_start(w, rank)
		var log := []
		_tick(w, log, CAST_TICKS + 3)
		var cast: Dictionary = _of(log, "cast", "heavens_hammer")[0]
		assert_eq(int(cast.level), LEVELS_30[rank - 1], "rank %d casts level %d" % [rank, LEVELS_30[rank - 1]])
	assert_eq(HAMMER_DAMAGE[7], 900, "rank 8 = level 30 = 900 %")
	var top := _world()
	assert_near(float(top.loadout.stats("heavens_hammer", 8).damage_pct), 9.0, 1e-9)


func test_the_hammer_does_more_at_a_higher_rank() -> void:
	var damage := {}
	for rank in [1, 8]:
		var w := _world()
		_mob(w, 100.0) # one mob: the same roll count, only the rank differs
		_start(w, rank)
		var log := []
		_tick(w, log, CAST_TICKS + 100)
		damage[rank] = _of(log, "mob_hit", "heavens_hammer").map(func(e: Dictionary) -> float: return float(e.damage))
		assert_eq(damage[rank].size(), 1)
	assert_true(float(damage[8][0]) > float(damage[1][0]) * 1.5, "900 pct against 480 pct: %s vs %s" % [damage[8], damage[1]])


func test_the_hammer_is_holy() -> void:
	var weak := _world()
	var plain := _world()
	var a := _mob(weak, 100.0)
	var b := _mob(plain, 100.0)
	weak.swarm.mob_kind(a).elements = {"H": 1.5}
	plain.swarm.mob_kind(b).elements = {"H": 1.0}
	var damage := []
	for w: RunWorld in [weak, plain]:
		_start(w)
		var log := []
		_tick(w, log, CAST_TICKS + 100)
		damage.append(float(_of(log, "mob_hit", "heavens_hammer")[0].damage))
	assert_near(damage[0] / damage[1], 1.5, 0.25, "a holy-weak mob takes about 1.5x")


func test_the_charges_damage_modifier_raises_the_hammer_and_charged_blow_not_the_multiplier() -> void:
	var damage := {}
	for mult: float in [1.0, 1.3]:
		var w := _world()
		w.loadout.add_skill_mod("holy_charge", "damage", "mul", mult) # Advanced Charge's x1.3
		_mob(w, 100.0)
		_start(w)
		var window: Dictionary = w.runner.forms.snapshot()[0]
		assert_near(float(window.effects.damage), 1.06, 1e-9, "the Charge's own multiplier is untouched")
		var log := []
		_tick(w, log, CAST_TICKS + 100)
		damage[mult] = float(_of(log, "mob_hit", "heavens_hammer")[0].damage)
	assert_true(damage[1.3] > damage[1.0] * 1.15, "x1.3 on the sub: %s vs %s" % [damage[1.3], damage[1.0]])


func test_form_power_and_form_time_move_the_window() -> void:
	var w := _world()
	w.loadout.add_skill_mod("holy_charge", "form_power", "add", 0.10)
	w.loadout.add_skill_mod("holy_charge", "form_time", "mul", 1.25)
	_start(w)
	var window: Dictionary = w.runner.forms.snapshot()[0]
	assert_near(float(window.effects.damage), 1.16, 1e-6, "1.06 + 0.10")
	assert_near(float(window.remaining), 15.0, 1e-9, "12 s x 1.25")


# --- Charged Blow inside Holy ------------------------------------------------------------------------------------------

func test_charged_blow_fires_inside_holy_on_its_interval_with_the_holy_art() -> void:
	var w := _world()
	for i in 4:
		_mob(w, -60.0 + 40.0 * i)
	_start(w)
	var log := []
	_tick(w, log, 60 * 10)
	var blows := _of(log, "cast", "charged_blow")
	assert_true(blows.size() >= 3, "1.0 s, then every 3.0 s: %d" % blows.size())
	assert_eq(String(blows[0].effect), "Skill.wz/121.img/skill/1211002/effect/5", "holy is art key 5")
	assert_eq(String(_of(log, "mob_hit", "charged_blow")[0].hit_visual), "Skill.wz/121.img/skill/1211002/hit/0/5")
	var hammers := _of(log, "cast", "heavens_hammer")
	assert_eq(hammers.size(), 1, "the Hammer fires beside the blows")


# --- Text and presentation data ----------------------------------------------------------------------------------------

func test_the_texts_name_holy_the_window_and_the_hammer() -> void:
	var w := _world()
	var text := SkillText.new(w.book)
	var hammer := text.level_line("heavens_hammer", 4, w.loadout.stats("heavens_hammer"))
	assert_true("480%" in hammer and "15" in hammer, hammer)
	var holy := String(w.book.def("holy_charge").text.desc)
	assert_true("Hammer" in holy and "holy" in holy.to_lower(), holy)


# --- Real cache --------------------------------------------------------------------------------------------------------

func _real_world(lib: AssetLibrary) -> RunWorld:
	var w := _world()
	w.book.skill_imgs["121"] = lib.img("Skill.wz/121.img").root
	w.book.skill_imgs["122"] = lib.img("Skill.wz/122.img").root
	return w


func test_real_cache_holy_charge_reads_the_level_20_table_at_all_eight_ranks() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	var w := _real_world(lib)
	for key in ["holy_charge"]:
		assert_eq(w.book.max_level(key), 20)
	for rank in range(1, 9):
		var st := w.loadout.stats("holy_charge", rank)
		assert_eq(st.level, HOLY_LEVELS[rank - 1], "rank %d" % rank)
		assert_eq(int(w.book.level_node("holy_charge", st.level).damage), HOLY_DAMAGE[rank - 1], "rank %d damage" % rank)
		w.runner.forms.clear(w, "test")
		_start(w, rank)
		assert_near(float(w.runner.forms.snapshot()[0].effects.damage), float(HOLY_DAMAGE[rank - 1]) / 100.0, 1e-9)
	assert_eq(int(w.book.level_node("holy_charge", 1).damage), 102, "level 1 is not rank 1")
	lib.free()


func test_real_cache_the_hammer_reads_the_level_30_table_at_all_eight_ranks() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	var w := _real_world(lib)
	assert_eq(w.book.max_level("heavens_hammer"), 30)
	for rank in range(1, 9):
		var st := w.loadout.stats("heavens_hammer", rank)
		assert_eq(st.level, LEVELS_30[rank - 1], "rank %d" % rank)
		var node := w.book.level_node("heavens_hammer", st.level)
		assert_eq(int(node.damage), HAMMER_DAMAGE[rank - 1], "rank %d damage" % rank)
		assert_eq(int(node.mobCount), 15)
		assert_eq(st.mob_count, 15)
		assert_eq(st.box, Rect2(-400, -350, 800, 600))
		assert_near(float(st.damage_pct), float(HAMMER_DAMAGE[rank - 1]) / 100.0, 1e-9)
	assert_eq(int(w.book.level_node("heavens_hammer", 1).damage), 420)
	lib.free()


func test_real_cache_both_twins_and_the_hammer_art_and_sounds_exist() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	var w := _real_world(lib)
	for id: int in [1221003, 1221004]:
		assert_true(lib.find_anim("Skill.wz/122.img/skill/%d/effect" % id) != null, "%d effect" % id)
		assert_true((lib.img("Skill.wz/122.img").root.skill[str(id)] as Dictionary).has("icon"), "%d icon" % id)
		assert_true(lib.sound("Sound.wz/Skill.img/%d/Use" % id) != null, "%d Use" % id)
	assert_true(lib.find_anim("Skill.wz/122.img/skill/1221011/effect") != null, "Hammer effect")
	assert_true(lib.sound("Sound.wz/Skill.img/1221011/Use") != null, "Hammer Use")
	assert_true(lib.sound("Sound.wz/Skill.img/1221011/Hit") != null, "Hammer Hit")
	# The twin art the blunt weapon resolves to is the node that exists.
	var path := w.book.art_path("holy_charge", String(w.book.def("holy_charge").effect), "blunt")
	assert_eq(path, "Skill.wz/122.img/skill/1221004/effect")
	assert_true(lib.find_anim(path) != null)
	lib.free()
