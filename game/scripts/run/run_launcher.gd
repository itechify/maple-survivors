class_name RunLauncher
extends Node
## Starts a run straight from the command line (user args after --), for playtests, automated runs and benchmarks:
##
##   bash scripts/godot.sh --path game res://scenes/run/run_launcher.tscn -- --run=henesys_hg1 --seed=7 \
##       --autoplay --autopick --speed=4 --shots=C:/abs/dir --shot-every=30 --quit-after=900 --perf
##
## Flags: --run=<stage key> (default henesys_hg1), --seed=<n> (default random), --autoplay (BotInput plays),
## --autopick (BotInput's choices, no windows: the first available job and BotInput.pick_card_for's card),
## --speed=<ticks per frame>, --shots=<abs dir> with --shot-every=<run s> (t<s>.png + final.png),
## --quit-after=<run s> (writes <shots>/summary.json and quits), --perf (perf overlay on at start with --autoplay; F3
## toggles it any time), --name=<character name>, --window-autopick=<s> (level-up / job windows open and answer
## themselves after s seconds), --vsync=off (uncapped frame rate for perf runs; otherwise the Settings autoload caps it
## at the refresh rate), --warp=<run s> (fast-forward the sim before the first frame).
## main.gd can reuse has_run_args() / options_from_args() / start() to go straight into a run.
##
## When the run ends: with the "Flow" autoload, RunScene hands the summary to Flow.finish_run; without it this launcher
## prints the summary and quits.

const RUN_SCENE := "res://scenes/run/run_scene.tscn"
const DEFAULT_STAGE := "henesys_hg1"

## The run started by _ready() (null when the args did not ask for one and no default applies).
var run: RunScene


func _ready() -> void:
	var args := parse_args(OS.get_cmdline_user_args())
	if str(args.get("vsync", "on")) == "off":
		GameSettings.apply_frame_cap(-1, true)
	run = start(self, args)
	run.run_finished.connect(_on_run_finished)


## True when the user args ask for a run (--run=...).
static func has_run_args(args: Dictionary) -> bool:
	return args.has("run")


## RunScene.configure() options from parsed args.
static func options_from_args(args: Dictionary) -> Dictionary:
	var o := {}
	o["autoplay"] = args.has("autoplay")
	o["autopick"] = args.has("autopick")
	o["speed"] = maxi(1, int(args.get("speed", "1")))
	if args.has("shots"):
		o["shots_dir"] = str(args.shots).replace("\\", "/")
	if args.has("shot-every"):
		o["shot_every"] = float(args["shot-every"])
	if args.has("quit-after"):
		o["quit_after"] = float(args["quit-after"])
	o["perf"] = args.has("perf")
	if args.has("name"):
		o["name"] = str(args.name)
	if args.has("window-autopick"):
		o["window_autopick"] = float(args["window-autopick"])
	if args.has("warp"):
		o["warp"] = float(args.warp)
	if args.has("job"):
		JobTree.put_forced(o, str(args.job)) # --job=<id>[:<weapon path>]
	return o


## Stage key from parsed args (--run=<key>; a bare --run means the default stage).
static func stage_from_args(args: Dictionary) -> String:
	var s := str(args.get("run", DEFAULT_STAGE))
	return DEFAULT_STAGE if s == "" or s == "1" else s


## Instantiates, configures and adds a RunScene under `parent` from parsed args; returns it.
static func start(parent: Node, args: Dictionary) -> RunScene:
	var r: RunScene = (load(RUN_SCENE) as PackedScene).instantiate()
	r.configure(stage_from_args(args), int(args.get("seed", "-1")), options_from_args(args))
	parent.add_child(r)
	return r


## Parses "--key=value" / "--flag" user args into a Dictionary (a flag maps to "1").
static func parse_args(list: PackedStringArray) -> Dictionary:
	var out := {}
	for a in list:
		if not a.begins_with("--"):
			continue
		var s := a.substr(2)
		var i := s.find("=")
		if i < 0:
			out[s] = "1"
		else:
			out[s.substr(0, i)] = s.substr(i + 1)
	return out


func _on_run_finished(summary: Dictionary) -> void:
	# Automated runs (--quit-after) write their summary and quit by themselves; with Flow the results screen follows.
	if get_node_or_null("/root/Flow") != null or float(run.options.get("quit_after", 0.0)) > 0.0:
		return
	print("RunLauncher: run finished %s" % JSON.stringify(summary))
	WebHandoff.exit_app(get_tree())
