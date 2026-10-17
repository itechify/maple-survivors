extends Node
## Bootstrap scene (main.tscn): registers itself as the scene flow's host and shows the first screen
## (docs/ARCHITECTURE.md 4.1): the importer when the asset cache is missing, else the title, or straight into a run
## with `--run=<stage>` (playtests: `bash scripts/playtest.sh`, or `bash scripts/run.sh -- --run=henesys_hg1 --autoplay
## --quit-after=60`; flags in SceneFlow.parse_run_args). The frame rate is capped at the display's refresh rate by the
## Settings autoload (GameSettings.apply_frame_cap); `--vsync=off` (any screen) uncaps it for perf runs.
## `--shot=<abs png> [--shot-at=<s>]` saves one screenshot of whatever is shown after s seconds (default 10) and quits:
## a check that a build (e.g. the exported exe) starts and reaches its first screen.


func _ready() -> void:
	var flow := get_node_or_null("/root/Flow") as SceneFlow
	if flow == null:
		push_error("main: the Flow autoload is missing")
		return
	flow.host = self
	var flags := SceneFlow.parse_flags(OS.get_cmdline_user_args())
	if String(flags.get("vsync", "")) == "off":
		GameSettings.apply_frame_cap(-1, true)
	if flags.has("shot"):
		_shot_and_quit(String(flags.shot), float(flags.get("shot-at", "10")))
	print("Maple Survivors: cache root = ", AssetCachePaths.resolve_cache_root())
	var assets := get_node_or_null("/root/Assets") as AssetLibrary
	if assets == null or not assets.has_cache():
		flow.goto_import()
		return
	flow.autoplay = flags.has("autoplay") and String(flags.autoplay) != "0" # menu-started characters play with the bot too
	var run := SceneFlow.parse_run_args(OS.get_cmdline_user_args())
	if not run.is_empty():
		flow.start_run(String(run.run), int(run.seed), run.options)
		return
	flow.goto_title()


## Waits `seconds` (real time), saves the viewport to `path` and quits (--shot).
func _shot_and_quit(path: String, seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var flow := get_node_or_null("/root/Flow") as SceneFlow
	var err := img.save_png(path) if img != null else ERR_CANT_CREATE
	print("main: --shot %s (screen %s) err=%d" % [path, flow.current_name if flow != null else "?", err])
	get_tree().quit(0 if err == OK else 1)
