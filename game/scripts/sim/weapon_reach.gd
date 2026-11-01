class_name WeaponReach
extends RefCounted
## How far the held weapon reaches (docs/GAME_DESIGN.md 6.1.1): the canonical afterimage boxes and body-frame timing of
## its swing stances. There is no automatic basic attack (#284, ADR 0006); weapon_reach skills (Warrior Power Strike)
## strike inside envelope(), Final Attack's spread measures reach(), and the weapon gallery draws action_spec().

## The five one-handed swing/stab actions (WeaponInfo.ACTIONS_ONE_HANDED, tier B): the bare-handed punch and the
## Beginner/Magician weapons use them in this order. Other weapons ask WeaponInfo.basic_actions.
const ACTIONS := WeaponInfo.ACTIONS_ONE_HANDED
## Bare hands (v83 lets a character fight without a weapon). tier A: the sound is Sound.wz/Weapon.img/barehands.
## tier C: normal attack speed 6, the same five body actions, no afterimage.
const BARE_HANDS := {"attackSpeed": WeaponInfo.NORMAL_SPEED, "sfx": "barehands"}
## tier C: the punch's reach, feet-relative and facing left (shorter than the starter Sword's swing).
const BARE_HANDS_BOX := Rect2(-55, -55, 50, 50)

var _body: Dictionary
var _images: Dictionary
## weapon id -> reach(); the afterimage and body data never change during a run.
var _reach := {}
## weapon id -> envelope(), cached like _reach.
var _envelope := {}


func _init(body: Dictionary = {}, images: Dictionary = {}) -> void:
	_body = body
	_images = images


## Horizontal reach in px of the held weapon's swing: its farthest box edge, or the punch's box bare-handed; 0 when the
## weapon cannot swing. Base reach is cached per weapon; a ranged weapon adds its currently usable passive range.
func reach(world: RunWorld) -> float:
	var weapon := world.weapon_id()
	if _reach.has(weapon):
		return float(_reach[weapon]) + _range_bonus(world)
	var info := world.weapon_info() if weapon > 0 else BARE_HANDS
	var far := 0.0
	if not info.is_empty():
		for action: String in WeaponInfo.basic_actions(weapon):
			var spec := _spec(weapon, info, action)
			if not spec.is_empty():
				far = maxf(far, -(spec.box as Rect2).position.x)
	_reach[weapon] = far
	return far + _range_bonus(world)


## The held weapon's swing envelope: the union of the afterimage boxes of the stances reach() looks at (feet-relative,
## facing left), the box a "weapon_reach" skill (Warrior Power Strike) strikes inside; an empty Rect2 when the weapon
## cannot swing. Its far edge is reach(). Base boxes are cached per weapon; passive range is added live.
func envelope(world: RunWorld) -> Rect2:
	var weapon := world.weapon_id()
	if _envelope.has(weapon):
		return _extended_box(_envelope[weapon], _range_bonus(world))
	var info := world.weapon_info() if weapon > 0 else BARE_HANDS
	var union := Rect2()
	var any := false
	if not info.is_empty():
		for action: String in WeaponInfo.basic_actions(weapon):
			var spec := _spec(weapon, info, action)
			if spec.is_empty():
				continue
			union = (spec.box as Rect2) if not any else union.merge(spec.box as Rect2)
			any = true
	_envelope[weapon] = union
	return _extended_box(union, _range_bonus(world))


## The held weapon's hit spark (Character.wz/Afterimage/hit.img/...) for body action `action`; "" when bare-handed or the
## weapon is unknown. For a skill whose WZ node has no hit art (Sacrifice, `hit_from_weapon`).
func hit_spark(world: RunWorld, action: String) -> String:
	var info := world.weapon_info()
	if info.is_empty():
		return ""
	return WeaponInfo.hit_spark_path(WeaponInfo.afterimage_name(info), action)


func _range_bonus(world: RunWorld) -> float:
	return world.loadout.passive_total(Loadout.RANGE) if WeaponInfo.is_ranged(world.weapon_id()) else 0.0


## tier C (#199): grow only the far horizontal edge, preserving the vertical and point-blank reach.
static func _extended_box(box: Rect2, bonus: float) -> Rect2:
	if not box.has_area() or bonus == 0.0:
		return box
	return Rect2(box.position - Vector2(bonus, 0.0), box.size + Vector2(bonus, 0.0))


## The timing, box and effect paths of one action of `weapon` ({} when it cannot be played); what a swing starts with.
## For tools and tests (the weapon gallery draws exactly this); reach() and envelope() read the same code.
func action_spec(weapon: int, info: Dictionary, action: String, boost: int = 0) -> Dictionary:
	return _spec(weapon, info, action, boost)


## One action's timing, box and effect paths for the weapon, or {} when the body or the afterimage cannot play it. `boost`
## Booster steps shorten the interval by the speed table and the body timing (hit_after, action_time) by `scale`
## (WeaponInfo.speed_factor; 1.0 without a Booster). A
## melee weapon needs the afterimage's lt/rb box and lands on the afterimage's first frame. A ranged family (bow,
## crossbow, claw, gun) reaches WeaponInfo.ranged_box, lands on the afterimage's first frame when it has one (the Bow's
## draw frame) else on the body's last frame, and shows no afterimage when the node is a melee trail with a box (a
## Claw's swordOL) or missing (the Gun's).
func _spec(weapon: int, info: Dictionary, action: String, boost: int = 0) -> Dictionary:
	var body: Dictionary = _body.get(action, {})
	if is_same(info, BARE_HANDS):
		return _bare_spec(body, action, boost)
	var name := WeaponInfo.afterimage_name(info)
	var node: Dictionary = _images.get(name, {}).get(WeaponInfo.AFTERIMAGE_VARIANT, {}).get(action, {})
	var ranged := WeaponInfo.is_ranged(weapon)
	var boxed := node.has("lt") and node.has("rb")
	if body.is_empty() or (not ranged and (node.is_empty() or not boxed)):
		return {}
	var frame := 999
	for key: String in node:
		if key.is_valid_int():
			frame = mini(frame, int(key))
	if frame == 999 and not ranged:
		return {}
	var last := -1
	for key: String in body:
		if key.is_valid_int():
			last = maxi(last, int(key))
	if last < 0:
		return {}
	var impact := frame if frame != 999 else last
	var timing := WeaponInfo.frame_times(body, impact)
	var box := WeaponInfo.ranged_box(weapon)
	if not ranged:
		var lt := Vector2(float(node.lt["$v"][0]), float(node.lt["$v"][1]))
		var rb := Vector2(float(node.rb["$v"][0]), float(node.rb["$v"][1]))
		box = Rect2(lt, rb - lt).abs()
	var trail := frame != 999 and not (ranged and boxed)
	var scale := WeaponInfo.speed_factor(int(info.get("attackSpeed", 0)), boost)
	return {"box": box, "hit_after": float(timing.before) * scale, "action_time": float(timing.total) * scale, "scale": scale,
		"interval": WeaponInfo.attack_interval(info, boost),
		"afterimage": WeaponInfo.afterimage_frame_path(name, action, frame) if trail else "",
		"hit_visual": WeaponInfo.hit_spark_path(name, action), "sound": WeaponInfo.sound_path(info)}


## tier C: a punch lands when the body action's last frame starts; reach BARE_HANDS_BOX, no afterimage or spark.
func _bare_spec(body: Dictionary, action: String, boost: int = 0) -> Dictionary:
	var last := -1
	for key: String in body:
		if key.is_valid_int():
			last = maxi(last, int(key))
	if last < 0:
		return {}
	var timing := WeaponInfo.frame_times(body, last)
	var scale := WeaponInfo.speed_factor(int(BARE_HANDS.attackSpeed), boost)
	return {"box": BARE_HANDS_BOX, "hit_after": float(timing.before) * scale, "action_time": float(timing.total) * scale, "scale": scale,
		"interval": WeaponInfo.attack_interval(BARE_HANDS, boost), "afterimage": "", "hit_visual": "",
		"sound": WeaponInfo.sound_path(BARE_HANDS)}
