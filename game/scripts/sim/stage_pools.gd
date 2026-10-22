class_name StagePools
extends RefCounted
## Resolves per-map ordinary mob weights from plain cache data; never reads files (#241/#245).


## Visible mob life counts minus exclusions, or the explicit pool; curve maps return {}.
static func resolve(map_entry: Dictionary, map_img: Dictionary) -> Dictionary:
	var pool: Variant = map_entry.get("pool", {})
	var out := {}
	if pool is Dictionary and not pool.is_empty():
		for id: Variant in pool:
			out[int(id)] = float(pool[id])
		return out
	if not bool(map_entry.get("pool_from_life", false)):
		return out
	var excluded := {}
	for id: Variant in map_entry.get("exclude", []):
		excluded[int(id)] = true
	for entry: Dictionary in map_img.get("life", {}).values():
		if entry.get("type", "") != "m" or int(entry.get("hide", 0)) != 0:
			continue
		var id := int(entry.get("id", 0))
		if id > 0 and not excluded.has(id):
			out[id] = float(out.get(id, 0.0)) + 1.0
	return out


## Sorted unique mob ids from every resolved map pool; curve ids remain StageRoster's responsibility.
static func stage_pool_ids(stage: Dictionary, map_imgs: Array) -> Array:
	var ids: Array = []
	var maps: Array = stage.get("maps", [])
	for i in maps.size():
		var img: Dictionary = map_imgs[i] if i < map_imgs.size() else {}
		for id: int in resolve(maps[i], img):
			if id not in ids:
				ids.append(id)
	ids.sort()
	return ids
