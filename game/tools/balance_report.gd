extends SceneTree
## Aggregates the supplied balance JSON records without rerunning their worlds or requiring an asset cache.
const BR := preload("res://tools/balance_run.gd")


func _init() -> void:
	var records: Array = []
	for path: String in OS.get_cmdline_user_args():
		if not FileAccess.file_exists(path):
			push_error("balance_report: missing record " + path)
			quit(1)
			return
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not value is Dictionary:
			push_error("balance_report: invalid record " + path)
			quit(1)
			return
		records.append(value)
	var summary := BR.aggregate(records)
	print("METRICS_SUMMARY " + JSON.stringify(summary))
	print(BR.describe_metrics(summary))
	quit()
