class_name CharacterCreation
extends RefCounted
## Explorer creation options from Etc.wz/MakeCharInfo.img. IDs and option names remain canonical data.
## The numeric Info columns and hair colour suffix are tier A: original v83 MakeCharInfo/Character.wz.

const IMG := "Etc.wz/MakeCharInfo.img"
const FIELDS := ["face", "hair", "hair_colour", "skin", "top", "bottom", "shoes", "weapon"]
const GENDERS := ["CharMale", "CharFemale"]
var root: Dictionary


func _init(img: Dictionary) -> void:
	root = img


## Ordered values of one option; premium and other creation families are deliberately excluded.
func options(gender: int, field: String) -> Array:
	if field == "gender":
		return [0, 1]
	var index := FIELDS.find(field)
	if gender < 0 or gender >= GENDERS.size() or index < 0:
		return []
	var column: Dictionary = root.get("Info", {}).get(GENDERS[gender], {}).get(str(index), {})
	var keys := column.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	var values := []
	for key: Variant in keys:
		if str(key).is_valid_int():
			values.append(int(column[key]))
	return values


## Chosen value from a field -> option-index dictionary, wrapping at either end.
func value(gender: int, field: String, choices: Dictionary) -> int:
	var values := options(gender, field)
	return 0 if values.is_empty() else int(values[posmod(int(choices.get(field, 0)), values.size())])


## Snapshot look; weapons are stored separately so job advancement can replace them.
func look(gender: int, choices: Dictionary) -> Dictionary:
	return {"skin": value(gender, "skin", choices), "face": value(gender, "face", choices),
		"hair": value(gender, "hair", choices) + value(gender, "hair_colour", choices),
		"equips": [value(gender, "top", choices), value(gender, "bottom", choices), value(gender, "shoes", choices)]}


## The gameplay Beginner weapon selected in the last MakeCharInfo column.
func weapon(gender: int, choices: Dictionary) -> int:
	return value(gender, "weapon", choices)


## Canonical display name when MakeCharInfo supplies one; other item names come from String.wz.
func option_name(gender: int, field: String, id: int) -> String:
	return str(root.get("Name", {}).get(GENDERS[gender], {}).get(str(FIELDS.find(field)), {}).get(str(id), ""))


## True only when every required Explorer column exists for both genders.
func available() -> bool:
	for gender in GENDERS.size():
		for field: String in FIELDS:
			if options(gender, field).is_empty():
				return false
	return true
