class_name InventoryModel
extends RefCounted
## Plain data the Equip and Item windows (#108) draw: the v83 item tooltip of an equipment instance, the Use tab's
## stacks, item names / icon paths and the meso text. Pure and static (no nodes, no cache reads): callers pass the
## Equipment instance, its canonical Character.wz `info` and the character's total stats, and look names up through
## the paths returned here.
##
## Tooltip (tooltip()): {"name", "category": UIWindow.img/ToolTip/Equip/ItemCategory index (-1 for weapons),
## "weapon_category": ToolTip/Equip/WeaponCategory index (item id / 10000 - 100; -1 for armour), "attack_speed":
## ToolTip/Equip/Speed index (-1 without one), "reqs": [{"key": "reqLEV".., "value", "met"}] in v83 order,
## "jobs": the job lines the reqJob mask allows (ToolTip/Equip/Can names), "job_ok", "can_equip",
## "stats": [[inc key, value], ...] in v83 order (non-zero only), "slots" (upgrade slots left), "scrolls"}.

## Item category (id / 10000) -> ToolTip/Equip/ItemCategory canvas (tier A: the v83 label art reads HAT, TOP,
## LONGCOAT, BOTTOM, SHOES, GLOVE, SHIELD (10); the mapping to categories is ours, tier C).
const CATEGORY_LABELS := {100: 1, 104: 5, 105: 21, 106: 6, 107: 7, 108: 8, 109: 10}
## Tooltip requirement rows: ToolTip/Equip/Can|Cannot label -> (info field, character stat; "" = the level).
const REQ_ROWS := [["reqLEV", "reqLevel", "level"], ["reqSTR", "reqSTR", "str"], ["reqDEX", "reqDEX", "dex"],
	["reqINT", "reqINT", "int"], ["reqLUK", "reqLUK", "luk"]]
## Job lines in the tooltip's row, with their reqJob bits (tier A: v83 reqJob masks).
const JOB_ROW := [["beginner", 0], ["warrior", 1], ["magician", 2], ["bowman", 4], ["thief", 8], ["pirate", 16]]
## Stat lines in v83 tooltip order (every `inc*` key an instance may carry, except incMMP: there is no MP, ADR 0006).
const STAT_ORDER := ["incSTR", "incDEX", "incINT", "incLUK", "incMHP", "incPAD", "incMAD", "incPDD",
	"incMDD", "incACC", "incEVA", "incSpeed", "incJump"]
## tier B (v83 weapon speed words, emulator RE): attackSpeed 2 FASTEST, 3 FASTER, 4-5 FAST, 6 NORMAL, 7 SLOW,
## 8 SLOWER, 9 SLOWEST -> ToolTip/Equip/Speed/0..6.
const SPEED_WORDS := {2: 0, 3: 1, 4: 2, 5: 2, 6: 3, 7: 4, 8: 5, 9: 6}


## The tooltip data of an equipment `instance` with canonical `info` for `character` ({level, job_id, str, dex, int,
## luk}: total stats) and its player-visible `name`.
@warning_ignore("integer_division")
static func tooltip(instance: Dictionary, info: Dictionary, character: Dictionary, name: String) -> Dictionary:
	var id := int(instance.get("id", 0))
	var category := id / 10000
	var reqs := []
	var can := true
	for row: Array in REQ_ROWS:
		var value := int(info.get(row[1], 0))
		var have := int(character.get(row[2], 0))
		var met := have >= value
		can = can and met
		reqs.append({"key": String(row[0]), "value": value, "met": met})
	var mask := int(info.get("reqJob", 0))
	var jobs := []
	for job: Array in JOB_ROW:
		if mask == 0 or (mask & int(job[1])) != 0:
			jobs.append(String(job[0]))
	var job_ok := mask == 0 or (mask & int(Equipment.JOB_BITS.get(int(character.get("job_id", 0)) / 100, 0))) != 0
	var stats := []
	for key: String in STAT_ORDER:
		var v := int(instance.get("stats", {}).get(key, 0))
		if v != 0:
			stats.append([key, v])
	var weapon := Equipment.slot_of(id) == "weapon"
	return {"name": name, "category": -1 if weapon else int(CATEGORY_LABELS.get(category, -1)),
		"weapon_category": category - 100 if weapon else -1,
		"attack_speed": speed_index(int(info.get("attackSpeed", 0))) if weapon else -1,
		"reqs": reqs, "jobs": jobs, "job_ok": job_ok, "can_equip": can and job_ok, "stats": stats,
		"slots": int(instance.get("slots", 0)), "scrolls": int(instance.get("scrolls", 0))}


## ToolTip/Equip/Speed index of a weapon's attackSpeed (-1 for none).
static func speed_index(attack_speed: int) -> int:
	return int(SPEED_WORDS.get(attack_speed, -1))


## Icon canvas path of an item: equipment from its Character.wz img, other items from Item.wz.
static func icon_path(id: int) -> String:
	if Equipment.slot_of(id) != "":
		return AvatarRenderer.part_img_path(id) + "/info/icon"
	return AssetLibrary.item_icon_path(id, false)


## String.wz path of an item's `field` ("name", "desc"): equipment under Eqp.img/Eqp/<Character.wz folder>/<id>,
## other items under Consume.img/<id> (keys are unpadded ids).
@warning_ignore("integer_division")
static func string_path(id: int, field: String) -> String:
	if Equipment.slot_of(id) == "":
		return "String.wz/Consume.img/%d/%s" % [id, field]
	var folder := "Weapon" if Equipment.slot_of(id) == "weapon" else String(AvatarRenderer.EQUIP_DIRS.get(id / 10000, ""))
	return "String.wz/Eqp.img/Eqp/%s/%d/%s" % [folder, id, field]


## String.wz name path of an item.
static func name_path(id: int) -> String:
	return string_path(id, "name")


## String.wz description path of an item.
static func desc_path(id: int) -> String:
	return string_path(id, "desc")


## A String.wz description as shown: its literal `\n` become line breaks, and the dark scrolls' broken break
## ("...+1nIf failed, the item will be destroyed...": the backslash is missing in v83's data) is repaired (tier C).
static func clean_desc(text: String) -> String:
	return text.replace("\\n", "\n").replace("nIf failed", "\nIf failed")


## Mesos with thousands separators, as the v83 meso line shows them.
static func meso_text(mesos: int) -> String:
	var s := str(maxi(0, mesos))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out


## The Use tab's scroll stacks (`scrolls`: {"<id>": count}) by id. Potions live only in the quick slot.
static func use_cells(scrolls: Dictionary) -> Array:
	var out := []
	var ids := []
	for key: Variant in scrolls:
		ids.append(int(key))
	ids.sort()
	for id: int in ids:
		out.append({"kind": "scroll", "id": id, "count": int(scrolls.get(str(id), scrolls.get(id, 0)))})
	return out
