class_name Account
extends RefCounted
## The account block of the save (spec #34, ADR 0003): {nx: int, owned: [int cash item ids]}. NX is the currency
## earned at the end of every round; owned lists the cash items bought once and usable by every character.
## A save without the block is an empty account. Pure data helpers; SaveData owns persistence.


## A new account: 0 NX, nothing owned.
static func empty() -> Dictionary:
	return {"nx": 0, "owned": []}


## "" when `value` is a well-formed account (whole nx >= 0, unique whole non-negative owned ids), else a message.
static func validation_error(value: Variant) -> String:
	if not value is Dictionary:
		return "account must be an object"
	if not _whole(value.get("nx")):
		return "account.nx must be a whole number"
	if not value.get("owned") is Array:
		return "account.owned must be a list"
	var seen := {}
	for id: Variant in value.owned:
		if not _whole(id):
			return "account.owned entries must be whole item ids"
		if seen.has(int(id)):
			return "account.owned must not repeat an item"
		seen[int(id)] = true
	return ""


## An independent copy with integer fields (JSON parses numbers as float). `value` must validate.
static func normalized(value: Dictionary) -> Dictionary:
	var owned: Array = []
	for id: Variant in value.owned:
		owned.append(int(id))
	return {"nx": int(value.nx), "owned": owned}


static func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and float(value) >= 0.0 and float(value) == floorf(float(value))
