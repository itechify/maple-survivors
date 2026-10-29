extends RefCounted
## Heal (2301002) fixtures for the Bishop tests (spec #372, BS4 #376): a synthetic Skill.wz `230.img` Heal table, a Bishop
## (job 232, made playable in the test's own data copy) world that knows only Heal, and the small helpers the Heal tests share.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
## Rank 1..8 are these WZ levels (the default 30-level table, GAME_DESIGN 8).
const RANK_LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
const MAX_HP := 1000


## Heal's Skill.wz levels 1..30 as v83 has them: `hp` 10 x level, `mobCount` 6, box (-250,-150)..(250,150) up to level 15 and
## (-300,-200)..(300,200) from level 16.
static func levels() -> Dictionary:
	var out := {}
	for lv in range(1, 31):
		var wide := lv >= 16
		out[str(lv)] = {"hp": 10.0 * lv, "mpCon": 10.0 + lv, "mobCount": 6.0,
			"lt": {"$v": [-300.0, -200.0] if wide else [-250.0, -150.0]},
			"rb": {"$v": [300.0, 200.0] if wide else [250.0, 150.0]}}
	return out


## Quiet-stage data with Bishop playable (so its pool cards exist) and 1000 max HP.
static func data() -> Dictionary:
	var d := RF.quiet_data()
	d.balance.player.hp = MAX_HP
	d.jobs_survivor.jobs["232"]["playable"] = true
	return d


## A Bishop standing at x 400 knowing only Heal at `rank`, caster INT 50 / Magic 23 so the top rank recovers a few hundred HP,
## well inside the 1000 max. `book` replaces the synthetic 230 Heal node (the real-cache test passes Skill.wz's own).
static func world(rank := 8, p_seed := 376, p_data: Dictionary = {}, book: Dictionary = {}) -> RunWorld:
	var setup := RF.setup("quiet", p_seed, data() if p_data.is_empty() else p_data)
	if book.is_empty():
		setup.skill_imgs["230"].skill["2301002"] = {"level": levels()}
	else:
		setup.skill_imgs["230"] = book
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	w.set_job(232)
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	w.learn_skill("heal")
	w.loadout.set_rank("heal", rank)
	w.loadout.set_caster(50.0, 23.0, 70)
	w.drain_events()
	return w


## Sets the character's HP exactly (the private field and the mirrored state).
static func set_hp(w: RunWorld, hp: float) -> void:
	w._hp = hp
	w._write_player_state(0.0)


## Marks `slot`'s kind undead with no magic defence, so a strike does not roll to 0.
static func make_undead(w: RunWorld, slot: int) -> void:
	var kind := w.swarm.mob_kind(slot)
	kind.undead = true
	kind.mdd = 0


## An undead mob `dx` px in front of the caster's feet (the player faces right), rebuilt into the grid.
static func put_undead(w: RunWorld, dx: float, hp_mult := 100000.0) -> int:
	var slot := RF.put_mob(w, MOB, w.player.pos.x + dx, 190.0, hp_mult)
	make_undead(w, slot)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return slot


## One runner step: returns {fired, restored, hits, damages, events}. `hits` are the hit dictionaries the listeners saw
## ({skill, level, magic, damage (the rolled line), element, damage_type}); `damages` the rolled damage of each `mob_hit` event.
static func cast(w: RunWorld) -> Dictionary:
	var hits: Array = []
	var listener := func(slot: int, hit: Dictionary) -> void: hits.append({"slot": slot, "hit": hit.duplicate()})
	w.add_hit_listener(listener)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()
	w.runner.step(DT, w)
	var events := w.drain_events()
	var restored := 0
	var damages: Array = []
	for e: Dictionary in events:
		if e.type == "player_restored":
			restored += int(e.amount)
		elif e.type == "mob_hit":
			damages.append(int(e.damage))
	return {"fired": w.runner.fired_this_tick, "restored": restored, "hits": hits, "damages": damages, "events": events}
