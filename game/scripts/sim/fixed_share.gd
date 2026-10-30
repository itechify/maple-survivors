class_name FixedShare
extends RefCounted
## Pure capped max-HP share arithmetic (M15); no rolls, defence, crit or element.


## Resolves the rank's share and caps from physical bounds before damage modifiers or skill percent.
static func resolve(block: Dictionary, rank: int, bounds: Vector2, damage_mult: float) -> Dictionary:
	var shares: Array = block.share
	var share := float(shares[clampi(rank - 1, 0, shares.size() - 1)])
	var base := (bounds.x + bounds.y) * 0.5
	var boss: Dictionary = block.boss
	return {"share": share, "cap_mult": float(block.cap_mult), "cap": base * float(block.cap_mult),
		"boss": {"share_scale": float(boss.share_scale), "cap_mult": float(boss.cap_mult),
			"cap": base * float(boss.cap_mult)}, "damage_mult": damage_mult}


## One whole damage line, with the modifier applied after the cap. Boss means canonical or scheduled.
static func amount(max_hp: int, boss: bool, resolved: Dictionary) -> int:
	var share := float(resolved.share)
	var cap := float(resolved.cap)
	if boss:
		share *= float(resolved.boss.share_scale)
		cap = float(resolved.boss.cap)
	# tier C: truncate the final capped, modified amount to whole HP; a fixed-share line always deals at least 1.
	return maxi(1, floori(minf(floorf(max_hp * share), cap) * float(resolved.damage_mult)))


## What is wrong with the `fixed_share` blocks of a skills file's `skills` object: one message per skill. A block needs the
## physical damage type (the cap base is the physical bounds; any other type leaves it 0 and every hit would deal 1), a
## non-empty `share` array and a `boss` block. Empty when the data is fine.
static func definition_errors(skills: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for key: String in skills:
		var def: Variant = skills[key]
		if not (def is Dictionary) or not def.has("fixed_share"):
			continue
		var block: Variant = def.fixed_share
		if String(def.get("damage", "")) != "physical":
			errors.append("skill '%s': fixed_share needs damage \"physical\" (its cap reads the physical bounds)" % key)
		if not (block is Dictionary):
			errors.append("skill '%s': fixed_share must be an object" % key)
			continue
		if not (block.get("share") is Array) or (block.share as Array).is_empty():
			errors.append("skill '%s': fixed_share needs a non-empty share array" % key)
		if not block.has("cap_mult") or not (block.get("boss") is Dictionary) \
				or not block.boss.has("share_scale") or not block.boss.has("cap_mult"):
			errors.append("skill '%s': fixed_share needs cap_mult and boss {share_scale, cap_mult}" % key)
	return errors
