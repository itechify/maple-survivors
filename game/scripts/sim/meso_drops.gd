class_name MesoDrops
extends RefCounted
## Meso drop rules (spec #33, #107), pure functions: which coin sprite an amount uses, the amount range of a mob (its
## listed v83 range or a level-based fallback) and one seeded roll. Ranges, chance and multiplier are survivor data
## (mobs.json "mesos", balance.json "mesos"); nothing here touches nodes or files.

## Sprite items (Item.wz/Special/0900.img) and the amount from which each is used. tier B: two third-party client
## reimplementations (bronze below 50, gold 50-99, bundle 100-999, bag from 1000).
const BRACKETS := [[1000, 9000003], [100, 9000002], [50, 9000001]]
const BRONZE := 9000000
## tier C: the coin animation plays at 100 ms a frame (the WZ icons have no delay node).
const FRAME_TIME := 0.1
const FRAMES := 4


## The coin sprite item id for a meso amount.
static func sprite_item(amount: int) -> int:
	for b: Array in BRACKETS:
		if amount >= int(b[0]):
			return int(b[1])
	return BRONZE


## Whether `item_id` is one of the coin sprites.
static func is_sprite(item_id: int) -> bool:
	return item_id >= BRONZE and item_id <= 9000003


## The [min, max) range for a mob: its listed range ([min, max] from mobs.json) or, without one, a range around
## `fallback.base + fallback.per_level * level` (tier C: fitted to the v83 ranges of the early rosters).
static func amount_range(level: int, listed: Array, fallback: Dictionary) -> Vector2i:
	if listed.size() == 2 and int(listed[1]) > 0:
		return Vector2i(int(listed[0]), int(listed[1]))
	var centre := float(fallback.get("base", 4.0)) + float(fallback.get("per_level", 1.5)) * float(maxi(1, level))
	var lo := maxi(1, int(floor(centre * float(fallback.get("low", 0.8)))))
	var hi := maxi(lo + 1, int(ceil(centre * float(fallback.get("high", 1.2)))))
	return Vector2i(lo, hi)


## One roll: uniform integer in [min, max) (tier B: v83 servers), times the survivor multiplier, at least 1.
static func roll(rng: RandomNumberGenerator, span: Vector2i, mult: float) -> int:
	var base := span.x if span.y <= span.x else rng.randi_range(span.x, span.y - 1)
	return maxi(1, roundi(float(base) * mult))
