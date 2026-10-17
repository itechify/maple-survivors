extends RefCounted
## Worlds with a pet out for the spec #34 pet tests (ticket #119): the quiet synthetic stage on the WorldFixtures
## "tiers" map (ground y=0 over x 0..1200, two low platforms at y=-60 and a top one at y=-120), or on the big
## RunFixtures map, with an account that owns the pet and any wanted upgrades.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const WF := preload("res://tests/fixtures/world_fixtures.gd")
const DT := 1.0 / 60.0

const KITTY := 5000000
const AUTO_HP := 1812002
const AUTO_MP := 1812003
const WING := 1812004
const BINOCULAR := 1812005
const VAC := 9990000
const EVERYTHING: Array = [KITTY, AUTO_HP, AUTO_MP, WING, BINOCULAR, VAC]


## Quiet data with `overrides` ({pet tuning key: value}) merged into the pet block.
static func data(overrides: Dictionary = {}) -> Dictionary:
	var d := RF.quiet_data()
	for key: String in overrides:
		d.cash_items.pet[key] = overrides[key]
	return d


## A quiet-stage setup on the tiers map (the player starts at x=300 on the ground) with `owned` account items, `pet`
## worn by the carried character (0 = none) and ALERT fractions.
static func setup(d: Dictionary, pet: int, owned: Array, alert: Dictionary = {}, seed_value := 5) -> Dictionary:
	var s := RF.setup("quiet", seed_value, d)
	s.map_img = RF.map_from_segments(WF.tiers_segments(), [Vector2(300, 0)])
	var character := RunWorld.new(s).character_snapshot()
	if pet > 0:
		character.pet = pet
	s.character = character
	s.account = {"owned": owned}
	if not alert.is_empty():
		s.alert = alert
	return s


## A busy Henesys round on the big synthetic map with the real data, the pet out, the whole account and ALERT 60 %.
static func busy_setup(seed_value: int) -> Dictionary:
	var s := RF.setup("henesys_hg1", seed_value)
	var character := RunWorld.new(s).character_snapshot()
	character.pet = KITTY
	s.character = character
	s.account = {"owned": EVERYTHING}
	s.alert = {"hp": 0.6, "mp": 0.6}
	return s


## A world with the pet out and `owned` items; the pet starts beside the player.
static func world(owned: Array = [KITTY], alert: Dictionary = {}, d: Dictionary = {}, seed_value := 5) -> RunWorld:
	return RunWorld.new(setup(d if not d.is_empty() else data(), KITTY, owned, alert, seed_value))


## Steps the world `ticks` times with no input; returns every event it emitted.
static func run(w: RunWorld, ticks: int, input: MoveInput = null) -> Array:
	var out: Array = []
	var move := input if input != null else MoveInput.new()
	for i in ticks:
		w.step(DT, move)
		out.append_array(w.drain_events())
	return out


## Events of `type` in `events`.
static func of_type(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


## Puts the player on the floor under x at the foothold nearest y (a platform), and the pet where it already is.
static func put_player(w: RunWorld, x: float, y: float) -> void:
	w.player.place(Vector2(x, y), w.fhm)
	w.update_view()


## Puts the pet at `p` at rest and clears its lost timer.
static func put_pet(w: RunWorld, p: Vector2) -> void:
	w.pet_system.place(p, w.fhm)
