class_name AssetManifest
extends RefCounted
## Reads the asset manifest with its include fragments (docs/ASSET_PIPELINE.md 4.1): res://data/asset_manifest.json plus
## every *.json in the sibling folder res://data/asset_manifest.d/, sorted by file name and appended after the main
## file's entries. This mirrors the importer's Manifest::load/merge (tools/wzimport/src/manifest.rs), which decides
## what is actually imported; GDScript readers (the import screen, data tests) use this so they see the same entries.
##
## A key listed in two files is an error naming both files: an `imgs` entry is keyed by (img, sub-path), or by img when it
## exports the whole img (a whole-img entry in one file conflicts with any entry for that img in another); a
## maps/mobs/character/items id by its id; a mapimgs entry by its path. Repeats inside one file are tolerated.
## Fragments may omit `format` (else it must be 1) and may not hold keys other than the manifest's own.

const FRAGMENT_KEYS := ["format", "_doc", "imgs", "maps", "mapimgs", "mobs", "character", "items"]
const LIST_KEYS := ["imgs", "maps", "mapimgs", "mobs", "character", "items"]
## Id lists and the word the duplicate error uses for their entries (as in the importer's messages).
const ID_KEYS := {"maps": "map", "mapimgs": "mapimg", "mobs": "mob", "character": "character", "items": "item"}


## The include folder of a manifest path: "res://data/asset_manifest.json" -> "res://data/asset_manifest.d".
static func fragment_dir(path: String) -> String:
	return path.get_basename() + ".d"


## The merged manifest of `path` and its fragments, or {} (after push_error) when a file is missing, malformed or a
## key is listed in two files.
static func load_merged(path: String) -> Dictionary:
	var result := load_checked(path)
	if str(result.error) != "":
		push_error("AssetManifest: " + str(result.error))
		return {}
	return result.manifest


## JSON text of a merged manifest for the importer: Godot parses every number as float and would print ids as
## "104040000.0", which the Rust reader rejects, so the id lists are written as integers.
static func to_json(manifest: Dictionary) -> String:
	var out := manifest.duplicate()
	for key: String in ["maps", "mobs", "character", "items"]:
		var ints := []
		for id: Variant in manifest.get(key, []):
			ints.append(int(id))
		out[key] = ints
	return JSON.stringify(out)


## Like load_merged, but returns {"manifest": Dictionary, "error": String} (error "" on success).
static func load_checked(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"manifest": {}, "error": "%s not found" % path}
	var main: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not main is Dictionary:
		return {"manifest": {}, "error": "%s is not a JSON object" % path}
	var fragments: Array = []
	var dir := fragment_dir(path)
	var names := PackedStringArray()
	if DirAccess.dir_exists_absolute(dir):
		for f: String in DirAccess.get_files_at(dir):
			if f.ends_with(".json"):
				names.append(f)
	names.sort()
	for f: String in names:
		var file := dir.path_join(f)
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
		if not data is Dictionary:
			return {"manifest": {}, "error": "manifest fragment %s is not a JSON object" % f}
		fragments.append({"name": f, "data": data})
	return merge(path.get_file(), main, fragments)


## Merges parsed JSON: `main` is the main file, `fragments` an Array of {"name": String, "data": Dictionary} in merge
## order. Returns {"manifest": Dictionary, "error": String}.
static func merge(main_name: String, main: Dictionary, fragments: Array) -> Dictionary:
	if int(main.get("format", 0)) != 1:
		return {"manifest": {}, "error": "%s: unsupported format %s" % [main_name, str(main.get("format"))]}
	var out := {"format": 1, "_doc": main.get("_doc", "")}
	for key: String in LIST_KEYS:
		out[key] = []
	var owners := {}
	var files: Array = [{"name": main_name, "data": main}] + fragments
	for i: int in files.size():
		var name := str(files[i].name)
		var data: Dictionary = files[i].data
		if i > 0:
			var bad := _fragment_error(data)
			if bad != "":
				return {"manifest": {}, "error": "manifest fragment %s: %s" % [name, bad]}
		var claimed := _claim(owners, data, name)
		if claimed != "":
			return {"manifest": {}, "error": claimed}
		for key: String in LIST_KEYS:
			out[key].append_array(data.get(key, []))
	return {"manifest": out, "error": ""}


static func _fragment_error(data: Dictionary) -> String:
	for key: String in data:
		if not FRAGMENT_KEYS.has(key):
			return "unknown key \"%s\" (allowed: %s)" % [key, ", ".join(FRAGMENT_KEYS)]
	if data.has("format") and int(data.format) != 1:
		return "unsupported format %s" % str(data.format)
	for key: String in LIST_KEYS:
		if data.has(key) and not data[key] is Array:
			return "\"%s\" must be an array" % key
	return ""


## Checks one file's keys against the files before it (an error string, "" when fine), then records them in `owners`.
static func _claim(owners: Dictionary, data: Dictionary, file: String) -> String:
	var ids := {}
	for key: String in ID_KEYS:
		for id: Variant in data.get(key, []):
			ids["%s %s" % [ID_KEYS[key], str(int(id)) if id is float or id is int else str(id)]] = true
	var whole := {}
	var paths := {}
	for entry: Variant in data.get("imgs", []):
		if not entry is Dictionary or not entry.has("img"):
			return "%s: every imgs entry needs an \"img\"" % file
		var img: String = entry.img
		if entry.get("paths") == null:
			whole[img] = true
		else:
			for p: String in entry.paths:
				paths["%s|%s" % [img, p]] = img
	for k: String in ids:
		if owners.has("id|" + k):
			return _dup("`%s`" % k, owners["id|" + k], file)
	for img: String in whole:
		for k: String in ["whole|" + img, "partial|" + img]:
			if owners.has(k):
				return _dup("`img %s`" % img, owners[k], file)
	for k: String in paths:
		var img: String = paths[k]
		if owners.has("whole|" + img):
			return _dup("`img %s`" % img, owners["whole|" + img], file)
		if owners.has("path|" + k):
			return _dup("`img %s` path \"%s\"" % [img, k.substr(img.length() + 1)], owners["path|" + k], file)
	for k: String in ids:
		owners["id|" + k] = file
	for img: String in whole:
		owners["whole|" + img] = file
	for k: String in paths:
		owners["path|" + k] = file
		owners["partial|" + str(paths[k])] = file
	return ""


static func _dup(what: String, first: String, second: String) -> String:
	return "manifest entry %s is listed in both %s and %s" % [what, first, second]
