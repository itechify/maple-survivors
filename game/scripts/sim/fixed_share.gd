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
