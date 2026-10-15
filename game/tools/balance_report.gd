extends SceneTree
## Aggregates the supplied balance JSON records without rerunning their worlds or requiring an asset cache.
const BR := preload("res://tools/balance_run.gd")


## Parses one current or preserved legacy record without changing its source text.
static func parse_record(text: String) -> Dictionary:
	# Old Godot snapshots encoded the unobserved boss route sentinel as1e99999. Normalize that diagnostic only,
	# before JSON parsing can overflow; measurements and the preserved raw file remain untouched.
	var legacy := RegEx.new()
	legacy.compile('"best_distance"\\s*:\\s*-?1[eE]\\+?99999(?=\\s*[,}])')
	var count := legacy.search_all(text).size()
	var parser := JSON.new()
	var status := parser.parse(legacy.sub(text, '"best_distance":null', true) if count > 0 else text)
	var error := parser.get_error_message() if status != OK else "" if parser.data is Dictionary else "expected a record object"
	return {"record": parser.data if error == "" else {}, "normalized_diagnostics": count, "error": error}


func _init() -> void:
	var records: Array = []
	for path: String in OS.get_cmdline_user_args():
		if not FileAccess.file_exists(path):
			push_error("balance_report: missing record " + path)
			quit(1)
			return
		var parsed := parse_record(FileAccess.get_file_as_string(path))
		if parsed.error != "":
			push_error("balance_report: invalid record %s: %s" % [path, parsed.error])
			quit(1)
			return
		if int(parsed.normalized_diagnostics) > 0:
			print("balance_report: normalized %d legacy nonfinite boss diagnostics in %s (raw file unchanged)" % [
				parsed.normalized_diagnostics, path])
		records.append(parsed.record)
	var summary := BR.aggregate(records)
	print("METRICS_SUMMARY " + JSON.stringify(summary))
	print(BR.describe_metrics(summary))
	quit()
