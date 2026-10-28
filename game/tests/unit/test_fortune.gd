extends TestCase
## Seeded Fortune offers and their public RunWorld/choice_card behavior (spec #30, ticket #43).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const TIERS := ["normal", "rare", "epic", "unique", "legendary"]
## Synthetic stand-ins for the deleted Beginner cards (#284): the old Three Snails count / cooldown card shapes on the
## start skill Energy Bolt, and a learn card for the three-rank Nimble Feet (its skill data stays).
const LEGACY_CARDS := {
	"bolt_count": {"id": "bolt_count", "kind": "skill_mod", "skill": "energy_bolt", "name": "Additional Bolt",
		"desc": "Energy Bolt fires +{value} shell.", "value": 1, "max_rank": 4, "weight": 1,
		"effects": [{"stat": "count", "op": "add", "value": 1}]},
	"bolt_cooldown": {"id": "bolt_cooldown", "kind": "skill_mod", "skill": "energy_bolt", "name": "Faster Bolt",
		"desc": "Energy Bolt cooldown -{value}%.", "value": 12, "max_rank": 4, "weight": 1,
		"effects": [{"stat": "cooldown", "op": "mul", "value": 0.88}]},
	"nimble_feet": {"id": "nimble_feet", "kind": "skill_new", "skill": "nimble_feet", "name": "Nimble Feet",
		"desc": "Learn Nimble Feet.", "max_rank": 1, "weight": 1, "effects": []},
}


func _world(fortune: float = 0.0) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player["fortune"] = fortune
	# A roomy stacking card preserves every rolled tier, so headroom cannot skew the odds measurement.
	data.upgrades.cards = [{"id": "roomy", "kind": "skill_rank", "skill": "energy_bolt", "max_rank": 100,
		"effects": [{"stat": "count", "op": "add", "value": 1}]}]

	return RunWorld.new(RF.setup("quiet", 43, data))


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _counts(w: RunWorld, seed_value: int, draws: int) -> Dictionary:
	var counts := {"normal": 0, "rare": 0, "epic": 0, "unique": 0, "legendary": 0}
	var rng := _rng(seed_value)
	for draw in draws:
		var c: Dictionary = w.upgrades.roll_choices(w, rng, 1)[0]
		var tier := String(c.get("tier", "missing"))
		if not counts.has(tier):
			assert_true(false, "every offer carries a known tier")
			return counts
		counts[tier] += 1
	return counts


func test_seeded_fortune_distribution_and_base_run_stat() -> void:
	var zero := _world()
	var lucky := _world(100.0)
	assert_eq(float(zero.player_state.get("fortune", -1)), 0.0)
	assert_eq(float(lucky.player_state.get("fortune", -1)), 100.0, "Fortune comes from survivor balance")
	var counts := _counts(zero, 43, 20000)
	# Literal bands follow the spec #30 design table, independently of the configured data under test.
	var bounds := {"normal": [0.73, 0.77], "rare": [0.165, 0.195], "epic": [0.042, 0.058],
		"unique": [0.013, 0.021], "legendary": [0.0015, 0.0047]}
	for tier: String in TIERS:
		var frequency := float(counts[tier]) / 20000.0
		assert_true(frequency >= float(bounds[tier][0]) and frequency <= float(bounds[tier][1]),
			"Fortune 0 %s frequency %.4f matches 75/18/5/1.7/0.3%%" % [tier, frequency])
	var higher := _counts(lucky, 43, 20000)
	# At Fortune 100 the documented normalized shares are 50/36/10/3.4/0.6%.
	var high_bounds := {"normal": [0.48, 0.52], "rare": [0.34, 0.38], "epic": [0.09, 0.11],
		"unique": [0.029, 0.039], "legendary": [0.004, 0.0082]}
	for tier: String in TIERS:
		var frequency := float(higher[tier]) / 20000.0
		assert_true(frequency >= float(high_bounds[tier][0]) and frequency <= float(high_bounds[tier][1]),
			"Fortune 100 %s frequency %.4f matches the documented normalized shares" % [tier, frequency])
	assert_true(int(higher.normal) < int(counts.normal) - 3500, "Fortune 100 measurably raises non-Normal offers")
	for tier: String in ["rare", "epic", "unique", "legendary"]:
		assert_true(int(higher[tier]) > int(counts[tier]), "%s grows with Fortune" % tier)


func _tier_world(tier: String, id: String) -> RunWorld:
	var data := RF.quiet_data()
	data.upgrades.rarity.weights = {tier: 1.0}
	if id == "energy_bolt_new":
		data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = "" # learning it needs a character without it
	data.upgrades.cards = [LEGACY_CARDS[id]] if LEGACY_CARDS.has(id) \
		else data.upgrades.cards.filter(func(c: Dictionary) -> bool: return c.id == id)
	var w := RunWorld.new(RF.setup("quiet", 43, data))
	RF.place_player(w, 400)
	return w


func _open_level(w: RunWorld) -> void:
	w.pickups.spawn(w.player.pos - Vector2(0, 25), w.progression.exp_to_next(), 4000019)
	w.step(1.0 / 60.0, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE)
