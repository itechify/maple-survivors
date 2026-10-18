extends TestCase
## Melee-aware bot movement (#162): SkillRunner.reach_of, BasicAttack.reach and BotInput's engage mode, on the
## synthetic map of run_fixtures.gd with seeded RNG and fixed dt. Magician and Beginner inputs must stay identical to the
## kiting bot of main (digests captured from main before the engage mode existed).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BF := preload("res://tests/fixtures/basic_attack_fixtures.gd")
const DT := 1.0 / 60.0

## Digest of 900 bot inputs plus player positions in the fixed swarm below, captured on main (b2ef00d lineage).
const MAGICIAN_DIGEST := 597847271
const BEGINNER_DIGEST := 130203406


## Rolling digest over the decided inputs and the resulting player position, so any change to a decision shows.
func _trace(w: RunWorld, ticks: int) -> int:
	var memo := {}
	var h := 7
	for t in ticks:
		var mi := BotInput.decide(w, memo)
		var bits := int(mi.left) + 2 * int(mi.right) + 4 * int(mi.up) + 8 * int(mi.down) + 16 * int(mi.jump_pressed) \
				+ 32 * int(mi.jump_held) + 64 * int(mi.drink_hp) + 128 * int(mi.drink_mp)
		h = (h * 31 + bits) % 1000000007
		w.step(DT, mi)
		w.drain_events()
		h = (h * 31 + int(w.player.pos.x * 4.0)) % 1000000007
	return h


## A seeded swarm of tough snails on both sides of the player; the player is invulnerable so the trace is long.
func _swarm(w: RunWorld) -> void:
	w.god = true
	for i in 6:
		RF.put_mob(w, 100100, 150.0 + 90.0 * i, 190, 100.0)
	for i in 4:
		RF.put_mob(w, 100100, 700.0 + 130.0 * i, 190, 100.0)


func test_magician_inputs_are_identical_to_main() -> void:
	var w := RF.quiet_world(400, 9)
	RF.change_job_bare(w, 200)
	w.learn_skill("energy_bolt")
	_swarm(w)
	w.heal_fraction("mp", 1.0)
	var digest := _trace(w, 900)
	assert_eq(digest, MAGICIAN_DIGEST, "Magician bot inputs match main")


func test_beginner_inputs_are_identical_to_main() -> void:
	var w := RF.quiet_world(400, 9)
	_swarm(w)
	w.heal_fraction("mp", 1.0)
	var digest := _trace(w, 900)
	assert_eq(digest, BEGINNER_DIGEST, "Beginner bot inputs match main")
