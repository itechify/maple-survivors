extends RefCounted
## Synthetic ordinary-mob attackers for the #76 seams: a Tauromacis-shaped 7130100 (type 0 magic `attack1`, the v83
## range box and attackAfter, synthetic frames) and a Jr. Boogie-shaped 3230300 (contact damage only; it still lists
## MobSkill 120 and 124 L1 with the v83 interval/time/box and prop 100, which ordinary mobs never cast).
## Canonical-shaped values are the ones checked against the real v83 cache during #76 triage; frames, HP and speed are
## synthetic. Both mobs stand still (speed -100).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const TAURO := 7130100
const BOOGIE := 3230300
## v83 Tauromacis attack1 range and attackAfter (Mob.wz/7130100.img/attack1/info).
const TAURO_LT := Vector2(-320, -240)
const TAURO_RB := Vector2(84, -1)
const TAURO_AFTER_MS := 480.0
const TAURO_MAD := 320.0


## A quiet seeded setup with both fixture mobs in the (rate 0) pool. `attack` overrides balance.mob_attacks.
static func setup(p_seed: int = 76, attack: Dictionary = {}, view := Vector2(800, 600)) -> Dictionary:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.balance.player.hp = 5000
	data.balance.player.stats.dex = 0
	data.balance.player.stats.luk = 0
	data.balance.mob_motion.push_px = 0
	data.balance.magnet_radius = 0
	data.balance["mob_attacks"] = {"default_interval": 5.0,
		"mobs": {str(TAURO): {"interval": 3.0, "dmg_mult": 0.5}}}.merged(attack, true)
	data.stages.stages.quiet.keyframes[0].pool[str(TAURO)] = 1.0
	data.stages.stages.quiet.keyframes[0].pool[str(BOOGIE)] = 1.0
	var out := RF.setup("quiet", p_seed, data)
	out.view_size = view
	out.mob_imgs[TAURO] = tauro_img()
	out.mob_imgs[BOOGIE] = boogie_img([120, 124])
	out["mob_skill_img"] = mob_skill_img()
	return out


## A RunWorld from setup() with the player standing on the ground at x = 400.
static func world(p_seed: int = 76, attack: Dictionary = {}, view := Vector2(800, 600)) -> RunWorld:
	var w := RunWorld.new(setup(p_seed, attack, view))
	RF.place_player(w, 400)
	return w


static func tauro_img() -> Dictionary:
	var img: Dictionary = RF.mob_img(100100).duplicate(true)
	img.info = {"level": 70.0, "maxHP": 1000000.0, "exp": 1.0, "PADamage": 100.0, "MADamage": TAURO_MAD,
		"PDDamage": 0.0, "MDDamage": 0.0, "speed": -100.0, "acc": 0.0}
	img["attack1"] = {"info": {"type": 0.0, "magic": 1.0, "elemAttr": "L", "conMP": 2.0,
		"attackAfter": TAURO_AFTER_MS,
		"range": {"lt": {"$v": [TAURO_LT.x, TAURO_LT.y]}, "rb": {"$v": [TAURO_RB.x, TAURO_RB.y]}},
		"hit": RF._anim(3, 100.0, 60, 230)}}
	for i in 5:
		var frame: Dictionary = img.move["0"].duplicate(true)
		frame.delay = 200.0
		img.attack1[str(i)] = frame
	return img


static func boogie_img(skills: Array) -> Dictionary:
	var img: Dictionary = RF.mob_img(100100).duplicate(true)
	img.info = {"level": 35.0, "maxHP": 1000000.0, "exp": 1.0, "PADamage": 50.0, "PDDamage": 0.0,
		"MDDamage": 0.0, "speed": -100.0, "acc": 0.0, "bodyAttack": 1.0, "skill": {}}
	for id: int in skills:
		img.info.skill[str(img.info.skill.size())] = {"skill": float(id), "level": 1.0, "action": 1.0,
			"effectAfter": 0.0}
	img["skill1"] = {}
	for i in 6:
		var frame: Dictionary = img.move["0"].duplicate(true)
		frame.delay = 100.0
		img.skill1[str(i)] = frame
	return img


## Skill.wz/MobSkill.img-shaped 120 and 124 level 1 nodes (v83 values except prop 100, so any cast would land).
static func mob_skill_img() -> Dictionary:
	return {
		"120": {"level": {"1": {"mpCon": 5.0, "interval": 10.0, "time": 30.0, "prop": 100.0,
			"lt": {"$v": [-300.0, -120.0]}, "rb": {"$v": [300.0, 120.0]},
			"affected": RF._anim(10, 100.0, 50, 42).merged({"pos": 1.0, "repeat": 1.0}),
			"effect": RF._anim(8, 100.0, 110, 113).merged({"pos": 3.0})}}},
		"124": {"level": {"1": {"mpCon": 5.0, "interval": 10.0, "time": 60.0, "prop": 100.0,
			"lt": {"$v": [-300.0, -120.0]}, "rb": {"$v": [300.0, 120.0]},
			"affected": RF._anim(4, 100.0, 50, 42), "effect": RF._anim(4, 100.0, 110, 113)}}},
	}
