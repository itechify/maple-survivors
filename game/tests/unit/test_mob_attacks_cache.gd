extends TestCase
## #76 against the real v83 asset cache (SKIP without it): Tauromacis 7130100 and Taurospear 7130101 resolve their
## canonical attacks, Jr. Boogie 3230300 still lists its (uncast) Seal and Curse, and a Dark Cave RunScene draws the
## attack stances, hit art (Taurospear's 1x1 placeholder hit canvases included) and sounds with nothing missing, while
## Jr. Boogie draws no cast and the buff row shows no status.

const DT := 1.0 / 60.0
const TAURO := 7130100
const SPEAR := 7130101
const BOOGIE := 3230300

var lib: AssetLibrary
var scene: RunScene


func before_each() -> void:
	lib = AssetLibrary.new()
	lib.open()


func after_each() -> void:
	if scene != null and is_instance_valid(scene):
		scene.free()
	scene = null
	lib.free()


func _make() -> RunScene:
	var s: RunScene = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	s.library = lib
	s.configure("dark_cave", 2026, {"use_flow": false})
	var tree := Engine.get_main_loop() as SceneTree
	(tree.current_scene if tree.current_scene != null else tree.root).add_child(s)
	return s


## Spawns `id` on the floor under the character's x + dx; returns the slot (-1 without a floor).
func _put(w: RunWorld, id: int, dx: float) -> int:
	var x := w.player.pos.x + dx
	var f := w.fhm.find_below(x, w.player.pos.y - 40.0)
	if f < 0:
		return -1
	return w.spawn_mob(int(w.kind_of_id[id]), Vector2(x, w.fhm.y_at(f, x)), f, 1.0, false)


func test_canonical_attack_data_resolve() -> void:
	if not require_cache():
		return
	scene = _make()
	var w := scene.world
	assert_eq(MobAttacks.attack_names(w.mob_img(TAURO)), PackedStringArray(["attack1"]))
	assert_eq(MobAttacks.attack_names(w.mob_img(SPEAR)), PackedStringArray(["attack1", "attack2"]))
	var tauro: Dictionary = w.mob_img(TAURO).attack1.info
	assert_eq(int(tauro.type), 0)
	assert_eq(int(tauro.magic), 1)
	assert_eq(String(tauro.elemAttr), "L")
	assert_eq(int(tauro.attackAfter), 480)
	assert_eq(w.swarm.kinds[w.kind_of_id[TAURO]].mad, 320, "canonical MADamage")
	assert_eq(w.swarm.kinds[w.kind_of_id[SPEAR]].mad, 390)
	for attack: String in ["attack1", "attack2"]:
		assert_eq(int(w.mob_img(SPEAR)[attack].info.attackAfter), 420)
	var skills: Array = w.mob_img(BOOGIE).info.skill.values().map(func(s: Dictionary) -> int: return int(s.skill))
	assert_eq(skills, [120, 124])
	for path: String in ["Mob.wz/7130100.img/attack1", "Mob.wz/7130100.img/attack1/info/hit",
			"Mob.wz/7130101.img/attack1", "Mob.wz/7130101.img/attack2", "Mob.wz/7130101.img/attack1/info/hit",
			"Mob.wz/7130101.img/attack2/info/hit"]:
		assert_true(lib.find_anim(path) != null, "art for %s" % path)
	for path: String in ["Sound.wz/Mob.img/7130100/Attack1", "Sound.wz/Mob.img/7130101/Attack1",
			"Sound.wz/Mob.img/7130101/Attack2"]:
		assert_true(lib.sound(path) != null, "sound %s" % path)
	_assert_nothing_missing(scene, "data lookups")


func test_dark_cave_draws_tauro_attacks_and_no_boogie_cast_with_nothing_missing() -> void:
	if not require_cache():
		return
	scene = _make()
	var w := scene.world
	w.god = true
	var slots := [_put(w, TAURO, 150.0), _put(w, SPEAR, 100.0), _put(w, SPEAR, -230.0)]
	var boogie := _put(w, BOOGIE, 60.0)
	assert_false(-1 in slots or boogie == -1, "the fixture mobs stand on the character's floor")
	var drawn_attack := false
	var boogie_cast := false
	for frame in 1500:
		scene.advance_frame(DT)
		var view := w.mob_action_view()
		for slot: int in slots:
			if w.swarm.is_live(slot) and String(view.actions[slot]).begins_with("attack"):
				drawn_attack = true
		if String(view.actions[boogie]) != "":
			boogie_cast = true
	assert_true(drawn_attack, "an attack stance is in the drawn action view")
	assert_true(scene._mob_attack_shot_taken and scene._mob_hit_shot_taken, "an ordinary windup and hit were shown")
	assert_false(boogie_cast, "Jr. Boogie draws no cast stance")
	assert_true(scene.hud.buff_row.displayed().is_empty(), "no status on the buff row")
	_assert_nothing_missing(scene, "Dark Cave mob attacks")


func _assert_nothing_missing(s: RunScene, label: String) -> void:
	assert_eq(lib.missing.size(), 0, "%s: library misses %s" % [label, lib.missing])
	assert_eq(s.map.missing.size(), 0, "%s: map misses %s" % [label, s.map.missing])
	assert_eq(s.avatar.missing.size(), 0, "%s: avatar misses %s" % [label, s.avatar.missing])
	for mr in s.mob_renderers:
		assert_eq(mr.missing.size(), 0, "%s: mob renderer misses %s" % [label, mr.missing])
	assert_eq(s.setup_missing.size(), 0, "%s: setup misses %s" % [label, s.setup_missing])
