extends Node
## Tool-only summon art/performance probe: --shots=<absolute evidence dir> [--skill=elquines|ifrit|hawk|phoenix|eagle|frostprey|summon_dragon|bahamut] [--life=<s>]
## [--without-summon]. --job=<id> and --status=<name> override the skill job and summon priority status; --life=<s> shortens the
## ally's lifetime (a duration modifier) so a 20 s capture shows it expire. A Bishop book skill (230/231/232) runs as job 232.
## `--skill=hawk|phoenix` (spec #332 B6/B11, needs Skill.wz/311.img and 312.img in the cache) runs the shipped Silver Hawk or
## Phoenix on a Bowmaster stand-in (job 312, held bow). `--skill=eagle|frostprey` (spec #360 MS9, needs Skill.wz/321.img and
## 322.img) runs the shipped Golden Eagle or Frostprey on a Marksman stand-in (job 322, held crossbow). Never saves a character.

## Probe name -> [skill key, book, job, weapon]: the shipped physical followers (Bowmaster's B11, Marksman's MS9).
const FOLLOWERS := {
	"hawk": ["silver_hawk", "311", 312, 1452051], "phoenix": ["phoenix", "312", 312, 1452051],
	"eagle": ["golden_eagle", "321", 322, 1462001], "frostprey": ["frostprey", "322", 322, 1462001],
}


func _ready() -> void:
	var shots := ""
	var enabled := true
	var skill := "elquines"
	var follower := ""
	var job := 0
	var status := ""
	var life := 0.0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots = arg.trim_prefix("--shots=")
		if arg.begins_with("--skill="):
			skill = arg.trim_prefix("--skill=")
			if skill in FOLLOWERS:
				follower = skill
				skill = _key_of(follower)
		if arg.begins_with("--job="):
			job = int(arg.trim_prefix("--job="))
		if arg.begins_with("--status="):
			status = arg.trim_prefix("--status=")
		if arg.begins_with("--life="):
			life = float(arg.trim_prefix("--life="))
		if arg == "--without-summon":
			enabled = false
	if shots.is_empty():
		push_error("player_summon_probe requires --shots=<absolute evidence directory>")
		get_tree().quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var run: RunScene = load(RunScene.SCENE_PATH).instantiate()
	run.configure("henesys", 291, {"autopick": true, "use_flow": false, "perf": true,
		"shots_dir": shots, "shot_every": 1.0, "quit_after": 20.0,
		"world_prepared": func(w: RunWorld) -> void:
			w.god = true
			if follower == "":
				var skill_job := int(w.book.def(skill).job)
				w.set_job(job if job > 0 else 232 if skill_job in [230, 231, 232] else skill_job)
			var mark := status if status != "" else String(w.book.def(skill).get("summon", {}).get("priority_status", ""))
			w.loadout.order.clear()
			if enabled and follower != "":
				_learn_follower(w, follower, job)
			elif enabled:
				w.learn_skill(skill)
				w.loadout.set_rank(skill, 8)
				w.loadout.add_skill_mod(skill, "damage", "mul", 0.01)
				if life > 0.0:
					w.loadout.add_skill_mod(skill, "duration", "mul", life / float(w.loadout.stats(skill).duration))
			if enabled and follower != "":
				w.loadout.add_skill_mod(skill, "damage", "mul", 0.01)
			# Diagnostic targets: real mob art, still standing, high HP; this is not survival/balance evidence.
			for kind: MobKind in w.mob_kinds:
				kind.move_speed = 0.0
			for i in 200:
				var slot := w.spawn_mob(0, w.player.pos + Vector2((20 if follower != "" else 70) + i % 20 * 5, 0), w.player.fh, 1.0, false)
				if slot >= 0:
					w.swarm.hp[slot] = 100000
					w.swarm.max_hp[slot] = 100000
					if mark != "" and i % 2 == 0:
						w.swarm.apply_status(slot, mark, {"time": 1000.0}, w.events)
	})
	add_child(run)


## The shipped physical follower `which` learned at rank 8 on a stand-in of its job with the job's weapon held (`--job=<id>` overrides the stand-in's job).
func _learn_follower(w: RunWorld, which: String, job_override := 0) -> void:
	var row: Array = FOLLOWERS[which]
	var key: String = row[0]
	w.book.skill_imgs[row[1]] = AssetLibrary.get_default().img("Skill.wz/%s.img" % row[1]).root
	w.set_job(job_override if job_override > 0 else int(row[2]))
	w.wear_new_item(row[3])
	w.learn_skill(key)
	w.loadout.set_rank(key, 8)


func _key_of(which: String) -> String:
	return FOLLOWERS[which][0]
