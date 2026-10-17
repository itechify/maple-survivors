class_name AccountFile
extends RefCounted
## The account file of tool rounds (`--account=<absolute JSON>` on balance.sh, playtest.sh and `--run`, spec #34):
##
##   {"owned": [item ids], "cash": {slot: item id}, "pet": species id, "alert": {"hp": 0..1, "mp": 0..1}}
##
## Every key is optional; unknown keys (`_doc`, `nx`) are ignored, because tool rounds never credit NX. `owned` is the
## account's cash items. `cash`, `pet` and `alert` are applied to the round's character (a fresh one or the carried
## `--character`): `cash`/`pet` replace what the character wears and has out when the file names them, `alert` becomes
## the round setup's `alert` (fractions of max HP/MP; 0 = do not alert). Leaving the flag out is an empty account and
## changes nothing. Presentation/core code: it reads files; the sim only sees the resulting setup keys.

## Reads and validates an account file; {} plus a message in `errors` when it is missing or malformed. The result is
## normalised (see `normalized`).
static func load_file(path: String, errors: PackedStringArray) -> Dictionary:
	var value: Variant = DataRepo.load_json(path)
	var error := "cannot read the file" if value == null else validation_error(value)
	if error != "":
		errors.append("account '%s': %s" % [path, error])
		return {}
	return normalized(value)


## Structural validation; an empty message means a usable account.
static func validation_error(value: Variant) -> String:
	if not value is Dictionary:
		return "expected an account object"
	if value.has("owned"):
		if not value.owned is Array:
			return "invalid owned"
		for id: Variant in value.owned:
			if not _whole(id) or int(id) <= 0:
				return "invalid owned"
	var error := CharacterSnapshot.cash_error(value)
	if error != "":
		return error
	if value.has("alert"):
		if not value.alert is Dictionary:
			return "invalid alert"
		for kind: String in ["hp", "mp"]:
			var level: Variant = value.alert.get(kind, 0.0)
			if not _number(level) or float(level) < 0.0 or float(level) > 1.0:
				return "invalid alert"
	return ""


## A validated account as plain typed data: {owned: [int], alert: {hp, mp}} always, plus cash {slot: int} and pet int
## only when the file names them.
static func normalized(value: Dictionary) -> Dictionary:
	var owned: Array = []
	for id: Variant in value.get("owned", []):
		owned.append(int(id))
	var alert: Dictionary = value.get("alert", {})
	var out := {"owned": owned, "alert": {"hp": float(alert.get("hp", 0.0)), "mp": float(alert.get("mp", 0.0))}}
	if value.has("cash"):
		out["cash"] = CharacterSnapshot.integers(value.cash)
	if value.has("pet"):
		out["pet"] = int(value.pet)
	return out


## Puts a normalised account on a RunWorld setup: `account`, `alert` and, when the account names cash or a pet, the
## worn items on the setup's character (creating the fresh character when the setup has none).
static func apply(setup: Dictionary, account: Dictionary) -> void:
	setup["account"] = {"owned": account.get("owned", []).duplicate()}
	setup["alert"] = account.get("alert", {"hp": 0.0, "mp": 0.0}).duplicate()
	if not account.has("cash") and not account.has("pet"):
		return
	var character: Dictionary
	if setup.has("character"):
		character = (setup.character as Dictionary).duplicate(true)
	else:
		character = RunWorld.new({"data": setup.get("data", {})}).character_snapshot()
	if account.has("cash"):
		_set_or_erase(character, "cash", not account.cash.is_empty(), account.cash.duplicate())
	if account.has("pet"):
		_set_or_erase(character, "pet", int(account.pet) > 0, int(account.pet))
	setup["character"] = character


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _whole(value: Variant) -> bool:
	return _number(value) and float(value) == floorf(float(value))


static func _set_or_erase(character: Dictionary, key: String, keep: bool, value: Variant) -> void:
	if keep:
		character[key] = value
	else:
		character.erase(key)
