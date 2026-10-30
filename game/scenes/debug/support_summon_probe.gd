extends Node
## Tool-only support-summon probe (#352): --shots=<absolute evidence dir>. A real Henesys round with a diagnostic support
## summon wearing the v83 Beholder's art (Skill.wz/132.img, from the asset cache) and made-up sub-skills that pulse every
## few seconds (a heal and a buff), so a screenshot shows the summon beside the character and the owner-side art.
## `--real` (D9 #357) drops the made-up subs: a job-132 round learns the shipped Beholder at rank 8 (Aura and Hex from the
## real tables), shorter first pulses are not forced, so the run lasts 24 s. Needs job 132 playable in the data (a local,
## uncommitted flip). Evidence, not balance: the character is hurt once to show the heal and never saved.
const PARENT_ID := 1321007
const BOOK := "132"

func _ready() -> void:
	var shots := ""
	var real := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots = arg.trim_prefix("--shots=")
		elif arg == "--real":
			real = true
	if shots.is_empty():
		push_error("support_summon_probe requires --shots=<absolute evidence directory>")
		get_tree().quit(1)
		return
	var lib := AssetLibrary.new()
	if not lib.open() or lib.img("Skill.wz/%s.img" % BOOK) == null:
		push_error("support_summon_probe needs an asset cache holding Skill.wz/%s.img" % BOOK)
		get_tree().quit(1)
		return
	var beholder_img: Dictionary = lib.img("Skill.wz/%s.img" % BOOK).root
	lib.free()
	var run: RunScene = load(RunScene.SCENE_PATH).instantiate()
	run.configure("henesys", 352, {"autopick": true, "use_flow": false, "shots_dir": shots, "shot_every": 1.0,
		"quit_after": 24.0 if real else 14.0, "job": 132 if real else 212,
		"world_prepared": func(w: RunWorld) -> void:
			w.god = true
			if real:
				w.loadout.order.clear()
				w.learn_skill("beholder")
				w.loadout.set_rank("beholder", 8)
				w.spend_hp(maxi(0, int(w.player_state.max_hp) - 20))
				return
			var aura := {"1": {"hp": 150.0, "x": 5.0}}
			var hex := {"1": {"x": 7.0, "time": 12.0, "pdd": 40.0, "mdd": 30.0}}
			w.book.skill_imgs["probe"] = {"skill": {"9990002": {"level": aura}, "9990003": {"level": hex}}}
			w.book.skill_imgs[BOOK] = beholder_img
			w.book.defs["probe_beholder"] = {"skill_id": PARENT_ID, "book": BOOK, "job": 132, "name": "Probe Beholder",
				"kind": "summon", "slot": "active", "cast": {"rule": "summon"}, "cooldown": 45.0, "damage": "none",
				"ranks": [1], "icon": "", "action": "alert2", "action_time": 0.6,
				"summon": {"path": "Skill.wz/%s.img/skill/%d/summon" % [BOOK, PARENT_ID], "attack": "",
					"follow_speed": 180.0, "follow_distance": 60.0, "teleport_distance": 600.0,
					"support": {"pulses": [
						{"skill": "probe_aura", "kind": "heal", "first_after": 2.0, "anim": "skill1"},
						{"skill": "probe_hex", "kind": "buff", "first_after": 4.0, "anim": "skill2"}]}}}
			w.book.defs["probe_aura"] = {"skill_id": 9990002, "book": "probe", "job": 132, "name": "Probe Aura",
				"kind": "support", "slot": "summon_sub", "summon_sub_of": "probe_beholder", "ranks": [1]}
			w.book.defs["probe_hex"] = {"skill_id": 9990003, "book": "probe", "job": 132, "name": "Probe Hex",
				"kind": "support", "slot": "summon_sub", "summon_sub_of": "probe_beholder", "ranks": [1],
				"buff": {"effects": [{"stat": "pdd", "field": "pdd"}, {"stat": "mdd", "field": "mdd"}]}}
			w.loadout.order.clear()
			w.learn_skill("probe_beholder")
			w.spend_hp(maxi(0, int(w.player_state.max_hp) - 20))
	})
	add_child(run)
