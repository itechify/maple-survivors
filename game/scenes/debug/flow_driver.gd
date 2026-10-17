extends Node
## Plays the real game (main.tscn under this node: the Flow autoload, every screen and the RunScene) by injecting
## keyboard and mouse events through Input.parse_input_event, exactly like a player, and saves a screenshot of every
## step. A smoke test of the whole flow and the evidence for docs/IMPLEMENTATION_PLAN.md acceptance checks.
##
##   bash scripts/godot.sh --path game res://scenes/debug/flow_driver.tscn -- --scenario=full --shots=C:/abs/dir
##
## Scenarios (--scenario=):
##   rounds  creates two characters through the v83 signboard/form, clears tier 1 (fixed-tick warp), walks to
##           Free Market out00, saves/reloads map select, starts tier 2, quits/reloads the same boundary/seed,
##           plays to death, deletes the spare character and checks both history entries. --diagnostic-victory=1
##           makes ONLY tier 2 invulnerable and applies diagnostic lethal boss hits after 15:00 to inspect victory;
##           this is presentation evidence, not balance evidence. Bosses/rewards still finish through RunWorld.
##   full    title -> character select -> Explorer creation -> tier-1 map select -> keyboard-steered round -> job/cards ->
##           pause/resume -> death -> results -> character select -> new character -> Quit round confirmation ->
##           continue the saved round/seed -> Quit round -> history -> characters -> title -> quit.
##           Slots/history go only to shots_dir/driver_save.json. Delete that file for a fresh repeat.
##   clear   --run tool one-off: waits for clear -> results -> character select -> title -> quit; never saves.
##   title   the title screen only: waits for it, saves the shot, quits (e.g. to check an exported build:
##           MapleSurvivors.exe res://scenes/debug/flow_driver.tscn -- --scenario=title --shots=<dir>).
##   windows the in-run window system (#85): title -> new character -> map select -> run; S opens the Stat window (the
##           sim is checked to hold), its title bar is dragged with the mouse, Esc closes it (the sim runs again); an
##           EXP drop levels the player up, S opens Stat over the level-up choice, Esc returns to the choice, 1 picks;
##           the status bar's Menu button opens the Menu popup, its Stat entry is clicked, Esc closes Stat; Esc pauses,
##           Esc resumes, quit. Shots: stat_window, stat_dragged, stat_over_levelup, menu_popup, menu_stat.
##   skill   the Skill window (#86): title -> new character -> map select -> run; the build is set up directly
##           (Magician, then Wizard (Ice, Lightning), Twin Claw x2, Quick Claw, Forking Storm, Magnet x2); K opens Skill
##           on the 2nd-job tab (the sim is checked to hold), Down selects Thunder Bolt (keyboard tooltip), Left
##           switches to the Magician tab, the wheel scrolls Magic Claw into view and hovering it shows its Upgrades, a
##           click opens the star tab and Magnet is hovered, 1 switches to the Beginner tab, Esc closes; then K over a
##           level-up choice (1 switches the tab instead of picking), Esc back to the choice, 1 picks, quit. Shots:
##           skill_window, skill_keyboard_tooltip, skill_tooltip_upgrades, skill_star_tab, skill_over_levelup.
##   keys    Key Config and Options (#87): title -> new character -> map select -> run (no bot); Esc pauses, 2 opens
##           Key Config over the pause menu, the jump icon is dragged from C onto F, OK; Esc resumes; C no
##           longer jumps, F does; Menu -> Options, WASD is clicked; the right arrow no longer moves the player, D does;
##           Options -> Arrows, Key Config -> Default -> OK. user://settings.cfg (the player's real one) is backed up
##           first and restored before the driver quits, also on failure. Shots: key_config, key_config_rebound,
##           options, options_wasd. These three create a character in the evidence-only driver_save.json (3 slots).
##   inventory the Equip and Item windows (#108): title -> new character; the slot's character becomes the Lv38
##           F/P fixture (tests/fixtures/characters/lv35_magician_2nd.json) holding Metal Gear, a Blue Sauna Robe,
##           Work Gloves and a Dark Calas it cannot wear, with 123,456 mesos -> map select -> run; E opens
##           Equip, I opens Item (the sim is checked to hold), the robe's tooltip, the Calas's tooltip with its
##           red requirements and the refused double-click, the hat worn by double-click, the robe by dragging it
##           onto the Equip window, the gloves by double-click (hat, overall, gloves and wand drawn on the
##           character), the Calas dragged out and the YesNo box answered No, the Use tab, Esc closes both; then
##           the slot is moved to the Free Market and Continue opens the hub: E and I there, the hat taken off and
##           put back, Save & quit shows the dressed character on character select. Shots: equip_window,
##           item_windows, item_tooltip, item_tooltip_unmet, equip_refused, equip_worn, character_dressed,
##           drop_confirm, item_use_tab, hub_windows, hub_hat_off, hub_dressed, character_select_dressed.
##   scrolls scrolls on worn equipment (#110): the Lv38 F/P fixture holds three 100% wand scrolls, six 10% and thirty
##           dark 30% wand scrolls and two 100% hat scrolls, wears Metal Gear -> run; E and I, the Use tab; a 100%
##           scroll is dragged from the Use tab onto the Wooden Wand (Enchant Success plays, the stats and counts
##           follow, the tooltip shows the new upgrade slots), then 10% scrolls until one fails (Enchant Failure, only
##           the slot is spent), then dark scrolls until the wand is destroyed (the character is bare-handed); the slot
##           moves to the Free Market and Continue opens the
##           hub: a hat scroll is dragged onto Metal Gear there (effect, saved slot). Shots: scroll_use_tab,
##           scroll_success, scroll_tooltip, scroll_failure, scroll_destroyed, scroll_bare_handed, hub_scroll_success.
##   shops   the Free Market scroll shops (#111): the Lv38 F/P fixture with 250,000 mesos, a few scrolls and spare
##           equipment is put in the hub; the four scroll NPCs are shown; Space next to El Moth opens his shop; a wand
##           scroll is selected and bought (quantity box, mesos charged), a refused purchase shows the notice; the
##           Use tab sells a scroll stack, the Equip tab a spare item (YesNo box); Esc closes; a double-click on Barun
##           opens his shop (60% stock); NPC Chat is rebound in Key Config's draft. All input is injected. Shots:
##           shop_npcs, shop_open, shop_selected, shop_quantity, shop_bought, shop_refused, shop_sell_use, shop_sell_confirm,
##           shop_sold, shop_barun, shop_vega.
##   botshop the bot shop plan (#112) in the Free Market: the same fixture with 600,000 mesos and spare equipment; the
##           hub's bot hook (FreeMarket.bot_shop, BotShop.visit) sells, buys and reads scrolls through RunWorld and
##           saves; the Item and Equip windows show the result. Shots: botshop_before_item, botshop_after_equip,
##           botshop_after_item.
##   import  for a cache-less start (point MAPLE_SURVIVORS_CACHE / APPDATA at an empty folder): the import screen,
##           types --wz=<folder> into the path field, clicks Import, waits for the importer and the title.
## Other flags: --shots=<abs dir> (required), --time-scale=<k> (default 3: the run plays k times faster, windows and
## effects too), --stop-at=<run s> (full: 300), --seed=<n> (full: 1, rounds: 4), --wz=<folder> (import).
##
## Screenshots are named NN_<step>.png; the driver prints one "flow_driver:" line per step and quits with exit code 1
## when a step times out or the full scenario misses the Magician / pause-resume path. Full also writes summary.json
## from RunScene's public snapshot, including the seed, potion totals, tier counts and missing assets.
## tier C: diagnostic names, seeds 1 (full) and 4 (rounds), 1800s combat cap, 600-tick yields, 100s progress logs,
## 30s/8px exit-walk guard and UI waits/timeouts are automation choices, never survivor tuning.

const MAIN := "res://scenes/main.tscn"
## Keys the steering sends (project.godot defaults: arrows, C jump (Alt too; Space is NPC Chat), Q / End potions; E is
## the Equip window).
const KEYS := {"left": KEY_LEFT, "right": KEY_RIGHT, "up": KEY_UP, "down": KEY_DOWN, "jump": KEY_C,
	"drink_hp": KEY_Q, "drink_mp": KEY_END}

var args := {}
var shots_dir := ""
var flow: SceneFlow
var _n := 0
var _steer := false
var _held := {}
var _memo := {}
var _failed := false
var _missing := PackedStringArray()
var _rounds: Array[Dictionary] = []
## The keys scenario: user://settings.cfg as it was before the run (null = there was none), restored on every exit.
var _settings_backup: Variant = null
var _settings_saved := false


func _ready() -> void:
	args = SceneFlow.parse_flags(OS.get_cmdline_user_args())
	shots_dir = String(args.get("shots", "")).replace("\\", "/")
	if shots_dir == "":
		push_error("flow_driver: --shots=<abs dir> is required")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots_dir)
	flow = get_node_or_null("/root/Flow") as SceneFlow
	# The scripted UI creates/deletes real slots, always in ignored evidence, never the player's save.
	flow.save = SaveData.new(shots_dir.path_join("driver_save.json"))
	add_child((load(MAIN) as PackedScene).instantiate())
	match String(args.get("scenario", "full")):
		"rounds":
			_scenario_rounds()
		"clear":
			_scenario_clear()
		"import":
			_scenario_import()
		"title":
			_scenario_title()
		"windows":
			_scenario_windows()
		"skill":
			_scenario_skill()
		"keys":
			_scenario_keys()
		"inventory":
			_scenario_inventory()
		"scrolls":
			_scenario_scrolls()
		"shops":
			_scenario_shops()
		"botshop":
			_scenario_botshop()
		"full":
			_scenario_full()
		_:
			_fail("unknown scenario: " + String(args.get("scenario")))


func _process(_delta: float) -> void:
	if _steer:
		_steer_run()


# --- scenarios ---------------------------------------------------------------------------------------------------

func _scenario_rounds() -> void:
	# tier C: training seed 4, a bot Henesys clear after #79 (seed 1 no longer clears); --seed overrides it.
	if not args.has("seed"):
		args["seed"] = "4"
	if not await _until(func() -> bool: return flow.current_name == "title", 20.0, "title"):
		return
	await _key(KEY_ENTER)
	if not await _create_character("Spare75"):
		return
	await _click(flow.current.get("back_button") as Control)
	if not await _create_character("Rounds75"):
		return
	await _sleep(2.0)
	await _shot("map_select_tier1")
	await _start_selected(flow.current)
	if not await _until(func() -> bool: return flow.current_name == "run", 10.0, "tier 1"):
		return
	await _shot("tier1_start")
	if not await _warp_round():
		return
	if not await _until(func() -> bool: return flow.current_name == "free_market", 15.0, "Free Market after real clear"):
		return
	var boundary := flow.save.slot(flow.active_slot)
	if not _expect(boundary.phase == "free_market" and int(boundary.tier) == 1
			and int(boundary.rounds_played) == 1, "tier-1 clear did not save the next boundary"):
		return
	await _sleep(0.5)
	await _shot("free_market_arrival")
	# Also check hub Save & quit and disk reload, through the real pause controls.
	await _key(KEY_ESCAPE)
	await _shot("free_market_save_quit")
	await _key(KEY_2)
	if not await _until(func() -> bool: return flow.current_name == "character_select", 10.0, "saved hub"):
		return
	_reload_save()
	# Mouse selects the spare, Right selects the carried character; Start is the shared v83 signboard button.
	await _click(flow.current.slot_buttons[0])
	if not _expect(flow.current.selected == 0, "mouse character selection failed"):
		return
	await _key(KEY_RIGHT)
	if not _expect(flow.current.selected == 1, "keyboard character selection failed"):
		return
	await _shot("selected_carried_character")
	await _click(flow.current.select_button)
	if not await _until(func() -> bool: return flow.current_name == "free_market", 10.0, "continued hub"):
		return
	var hub := flow.current as FreeMarket
	var exit_pos := Vector2.ZERO
	for portal: Dictionary in hub.motion.portals.links:
		if portal.name == "out00":
			exit_pos = portal.pos
	# No teleport or direct scene call: hold arrows from the canonical arrival to the real exit.
	var t0 := Time.get_ticks_msec()
	while absf(hub.motion.player.pos.x - exit_pos.x) > 8.0:
		if Time.get_ticks_msec() - t0 > 30000:
			_fail("walking to out00 timed out")
			return
		_set_key("left", hub.motion.player.pos.x > exit_pos.x)
		_set_key("right", hub.motion.player.pos.x < exit_pos.x)
		await get_tree().process_frame
	_release_all()
	await _shot("free_market_out00")
	_collect_missing(hub)
	await _key(KEY_UP)
	if not await _until(func() -> bool: return flow.current_name == "stage_select", 10.0, "tier-2 map select via out00"):
		return
	await _sleep(2.0)
	if not _expect(flow.current.stages.size() == 1 and flow.current.stages[0].key == "dark_cave",
			"tier 2 offered a stage outside Dark Cave"):
		return
	await _shot("map_select_tier2")
	await _click(flow.current.back_button)
	if not await _until(func() -> bool: return flow.current_name == "character_select", 10.0, "saved map select"):
		return
	_reload_save()
	await _click(flow.current.slot_buttons[1])
	await _click(flow.current.select_button)
	if not await _until(func() -> bool: return flow.current_name == "stage_select", 10.0, "continued map select"):
		return
	await _sleep(2.0)
	await _start_selected(flow.current)
	if not await _until(func() -> bool: return flow.current_name == "run", 10.0, "tier 2"):
		return
	var saved := flow.save.slot(flow.active_slot)
	var bytes := FileAccess.get_file_as_bytes(shots_dir.path_join("driver_save.json"))
	await _sleep(1.0)
	await _shot("dark_cave_start")
	await _quit_round_ui()
	if _failed:
		return
	if not _expect(FileAccess.get_file_as_bytes(shots_dir.path_join("driver_save.json")) == bytes,
			"Quit round changed the boundary file"):
		return
	_reload_save()
	await _click(flow.current.slot_buttons[1])
	await _click(flow.current.select_button)
	if not await _until(func() -> bool: return flow.current_name == "run", 10.0, "continued tier 2"):
		return
	var run := flow.current as RunScene
	# Disk JSON turns numeric fields into floats; compare both snapshots in the same representation.
	var normalized: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var resumed: Dictionary = JSON.parse_string(JSON.stringify(flow.save.slot(flow.active_slot)))
	if resumed != normalized:
		print("flow_driver: boundary before ", JSON.stringify(normalized))
		print("flow_driver: boundary resumed ", JSON.stringify(resumed))
	print("flow_driver: resumed level %s / saved %s" % [run.world.player_state.level, saved.character.level])
	if not _expect(run.run_seed == int(saved.round_seed) and run.stage_key == saved.stage,
			"Continue changed stage or round seed"):
		return
	if not _expect(run.world.player_state.level == int(saved.character.level)
			and resumed == normalized,
			"Continue changed the boundary character"):
		return
	await _shot("dark_cave_replayed")
	if String(args.get("diagnostic-victory", "0")) == "1":
		run.world.god = true
	if not await _warp_round():
		return
	if not await _until(func() -> bool: return flow.current_name == "results", 15.0, "run ending"):
		return
	await _sleep(1.0)
	var ending := "victory" if String(args.get("diagnostic-victory", "0")) == "1" else "died"
	if not _expect(flow.last_summary.ending == ending, "unexpected run ending"):
		return
	await _shot("results_" + ending)
	await _click(flow.current.back_button)
	if not await _until(func() -> bool: return flow.current_name == "character_select", 10.0, "ended character removed"):
		return
	if not _expect(flow.save.slot(1).is_empty(), "ended run still occupies a slot"):
		return
	await _click(flow.current.slot_buttons[0])
	await _click(flow.current.delete_button)
	await _shot("delete_confirmation")
	await _key(KEY_ESCAPE)
	await _sleep(0.3)
	if not _expect(not flow.save.slot(0).is_empty(), "cancel deleted the spare"):
		return
	await _click(flow.current.delete_button)
	await _sleep(0.3) # Respect the same modal input guard when reopening after Cancel.
	await _key(KEY_ENTER)
	if not await _until(func() -> bool: return flow.save.slot(0).is_empty(), 10.0, "confirmed deletion"):
		return
	await _sleep(0.5)
	await _click(flow.current.find_child("RunHistory", true, false) as Control)
	if not await _until(func() -> bool: return flow.current_name == "history", 10.0, "History entry"):
		return
	await _sleep(1.0)
	await _shot("history_" + ending)
	var history := flow.save.history
	if not _expect(history.size() == 2 and history[0].ending == ending
			and history[0].name == "Rounds75" and int(history[0].rounds_played) == 2
			and history[1].ending == "deleted" and history[1].name == "Spare75", "history did not archive both runs"):
		return
	_collect_missing(flow.current)
	if not _expect(_missing.is_empty(), "missing assets: %s" % _missing):
		return
	var report := {"scenario": "rounds", "diagnostic_victory": ending == "victory", "rounds": _rounds,
		"replayed_seed": saved.round_seed, "history": history, "missing": Array(_missing), "failures": []}
	var file := FileAccess.open(shots_dir.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("flow_driver: rounds PASSED ", JSON.stringify(report))
	get_tree().quit()


## Warps actual fixed ticks with the existing bot/choice policy; never fabricates a clear or character.
## UI navigation remains injected input. End events still go through RunScene's normal presentation/Flow path.
func _warp_round() -> bool:
	var run := flow.current as RunScene
	run.set_process(false)
	var memo := {}
	var ticks := 0
	while run.world.time < 1800.0 and run.world.state not in [RunWorld.DEAD, RunWorld.CLEARED]:
		BotInput.auto_choose(run.world)
		if run.world.state in [RunWorld.DEAD, RunWorld.CLEARED]:
			run.handle_events(run.world.drain_events())
			break
		if run.world.state != RunWorld.PLAYING:
			continue
		if run.world.god and run.stage_key == "dark_cave" and run.world.time >= run.world.duration:
			# tier C: supplemental victory-screen staging, not a naturally won round or a balance candidate.
			# Use the real damage/death/reward path; never fabricate a summary or bypass pending choices.
			for record: Dictionary in run.world.bosses.records:
				var slot := int(record.slot)
				if not bool(record.dead) and slot >= 0 and run.world.swarm.is_live(slot):
					run.world.hit_mob(slot, {"skill": "three_snails", "magic": true, "damage_min": 1e9,
						"damage_max": 1e9, "crit": 0.0, "crit_mult": 1.0}, -1)
		run.world.step(RunScene.DT, BotInput.decide(run.world, memo))
		var events := run.world.drain_events()
		if run.world.state in [RunWorld.DEAD, RunWorld.CLEARED]:
			run.handle_events(events)
		ticks += 1
		if ticks % 600 == 0:
			await get_tree().process_frame
		if ticks % 6000 == 0:
			print("flow_driver: warp %.0f s / Lv %d" % [run.world.time, run.world.player_state.level])
	if not _expect(run.world.state in [RunWorld.DEAD, RunWorld.CLEARED], "round timed out during warp"):
		return false
	run._apply_look()
	run._present(0.0)
	_collect_missing(run)
	_rounds.append(run.build_summary())
	if not _expect(run.world.warnings.is_empty(), "world warnings during warp"):
		return false
	await _shot("round_" + run.world.state_name().to_lower())
	run.set_process(true)
	return true


func _quit_round_ui() -> void:
	await _key(KEY_ESCAPE)
	await _sleep(0.3)
	await _key(KEY_4)
	await _shot("quit_round_warning")
	await _key(KEY_4)
	await _until(func() -> bool: return flow.current_name == "character_select", 10.0, "Quit round")


func _reload_save() -> void:
	flow.save = SaveData.new(shots_dir.path_join("driver_save.json"))


func _expect(ok: bool, message: String) -> bool:
	if not ok:
		_fail(message)
	return ok

func _scenario_full() -> void:
	var ts := float(args.get("time-scale", "3"))
	var stop_at := float(args.get("stop-at", "300"))
	if not await _until(func() -> bool: return flow.current_name == "title", 20.0, "title"):
		return
	await _sleep(9.0)
	await _shot("title")
	await _key(KEY_ENTER)
	if not await _create_character("Flow69"):
		return
	await _sleep(3.0)
	await _shot("map_select")
	var sel: Node = flow.current
	await _start_selected(sel)
	if not await _until(func() -> bool: return flow.current_name == "run", 10.0, "run"):
		return
	var run := flow.current as RunScene
	await _sleep(2.0)
	await _shot("run_start")
	# A few seconds of plain keyboard play before the steering takes over.
	await _hold(KEY_RIGHT, 1.2)
	await _key(KEY_C)
	await _sleep(0.25)
	await _shot("run_keyboard_jump")
	await _hold(KEY_LEFT, 0.8)
	Engine.time_scale = ts
	_steer = true
	var windows := 0
	var paused_once := false
	var resumed_once := false
	var job_seen := false
	while is_instance_valid(run) and run.world != null and run.world.state != RunWorld.DEAD:
		await get_tree().process_frame
		if run.world.time >= stop_at and _steer:
			_steer = false
			_release_all()
			print("flow_driver: hands off the keys at %.0f s (level %d)" % [run.world.time, run.world.player_state.level])
			await _shot("hands_off")
		if run.window is LevelUpWindow and (run.window as MapleWindow).is_open():
			_release_all()
			windows += 1
			await _sleep(0.5)
			if not is_instance_valid(run.window):
				continue
			var lw := run.window as LevelUpWindow
			if windows <= 3 or lw.level % 5 == 0:
				await _shot("levelup_%d" % lw.level)
			var pick := _card_index(run, lw.cards)
			if windows == 1:
				await _click_at(lw.card_rect(pick).get_center())
			else:
				await _key((KEY_1 + pick) as Key)
			await _sleep(0.3)
		elif run.window is JobAdvanceWindow and (run.window as MapleWindow).is_open():
			_release_all()
			job_seen = true
			await _sleep(0.6)
			await _shot("job_dialog")
			var jw := run.window as JobAdvanceWindow
			var idx := -1
			for i in jw.entries.size():
				if jw.entries[i].kind == "job" and jw.entries[i].available:
					idx = i
					break
			await _key((KEY_1 + maxi(0, idx)) as Key)
			await _sleep(0.4)
			await _shot("job_confirm")
			await _key(KEY_ENTER)
			await _sleep(0.9)
			await _shot("job_changed")
		elif not paused_once and job_seen and run.window == null and run.world.state == RunWorld.PLAYING:
			paused_once = true
			_release_all()
			await _key(KEY_ESCAPE)
			await _sleep(0.6)
			await _shot("pause_menu")
			await _key(KEY_ESCAPE)
			await _sleep(0.3)
			resumed_once = not run.paused
			print("flow_driver: resumed = %s" % resumed_once)
	_steer = false
	_release_all()
	# Capture the tomb before the accelerated end hold can dispose of the round.
	Engine.time_scale = 1.0
	print("flow_driver: the character died at %.0f s, level %d" % [run.world.time, run.world.player_state.level])
	var snapshot := run.perf_summary(run.build_summary())
	snapshot["flow"] = {"windows": windows, "job_seen": job_seen, "pause_seen": paused_once, "resumed": resumed_once}
	snapshot["card_tiers_offered"] = run.world.card_tiers_offered.duplicate()
	snapshot["card_tiers_picked"] = run.world.card_tiers_picked.duplicate()
	var file := FileAccess.open(shots_dir.path_join("summary.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(snapshot, "\t"))
		file.close()
	print("flow_driver: snapshot %s" % JSON.stringify(snapshot))
	if not job_seen or int(snapshot.job_id) != 200 or not paused_once or not resumed_once:
		_failed = true
		push_error("flow_driver: full scenario did not complete the Magician and pause/resume path")
	await _sleep(1.0)
	await _shot("death_tombstone")
	if not await _until(func() -> bool: return flow.current_name == "results", 30.0, "results"):
		return
	Engine.time_scale = 1.0
	await _sleep(3.0)
	await _shot("results_death")
	await _click(flow.current.get("back_button") as Control)
	if not await _create_character("Quit69"):
		return
	await _sleep(3.0)
	await _start_selected(flow.current)
	if not await _until(func() -> bool: return flow.current_name == "run", 10.0, "new character round"):
		return
	await _sleep(3.0)
	var round_seed := (flow.current as RunScene).run_seed
	await _shot("new_round")
	await _key(KEY_ESCAPE)
	await _sleep(0.6)
	await _key(KEY_4)
	await _sleep(0.5)
	await _shot("quit_round_warning")
	await _key(KEY_4)
	if not await _until(func() -> bool: return flow.current_name == "character_select", 10.0, "characters after quit"):
		return
	await _sleep(1.0)
	await _shot("characters_after_quit")
	await _click(flow.current.get("select_button") as Control)
	if not await _until(func() -> bool: return flow.current_name == "run", 10.0, "continued round"):
		return
	if (flow.current as RunScene).run_seed != round_seed:
		_fail("Continue changed the saved round seed")
		return
	await _sleep(1.0)
	await _shot("continued_round")
	await _key(KEY_ESCAPE)
	await _sleep(0.5)
	await _key(KEY_4)
	await _key(KEY_4)
	if not await _until(func() -> bool: return flow.current_name == "character_select", 10.0, "characters"):
		return
	await _click(flow.current.find_child("RunHistory", true, false) as Control)
	await _sleep(1.0)
	await _shot("history")
	await _key(KEY_ESCAPE)
	await _sleep(0.5)
	await _key(KEY_ESCAPE)
	if not await _until(func() -> bool: return flow.current_name == "title", 10.0, "title (back)"):
		return
	await _sleep(2.0)
	await _shot("title_again")
	_collect_missing(flow.current)
	snapshot["missing"] = Array(_missing)
	file = FileAccess.open(shots_dir.path_join("summary.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(snapshot, "\t"))
		file.close()
	if not _expect(_missing.is_empty(), "full scenario missing assets: %s" % _missing):
		return
	print("flow_driver: done (%d level-up windows answered, job dialog %s)" % [windows, job_seen])
	await _key(KEY_ESCAPE)
	await _sleep(2.0)
	get_tree().quit(1 if _failed else 0)


func _scenario_clear() -> void:
	var save_path := shots_dir.path_join("driver_save.json")
	var before := FileAccess.get_file_as_bytes(save_path) if FileAccess.file_exists(save_path) else PackedByteArray()
	if not await _until(func() -> bool: return flow.current_name == "run", 20.0, "run"):
		return
	var run := flow.current as RunScene
	if not await _until(func() -> bool: return run.world != null and run.world.state == RunWorld.CLEARED, 1800.0,
			"stage clear"):
		return
	# Keep a detached result before any await can let Flow dispose of this accelerated one-off scene.
	var summary := run.build_summary()
	Engine.time_scale = 1.0
	await _sleep(0.8)
	await _shot("clear_notice")
	if not await _until(func() -> bool: return flow.current_name == "results", 30.0, "results"):
		return
	await _sleep(3.5)
	await _shot("results_clear")
	await _click(flow.current.get("back_button") as Control)
	if not await _until(func() -> bool: return flow.current_name == "character_select", 10.0, "character select"):
		return
	await _sleep(1.0)
	await _shot("characters_after_one_off_clear")
	var after := FileAccess.get_file_as_bytes(save_path) if FileAccess.file_exists(save_path) else PackedByteArray()
	if not _expect(before == after and flow.save.history.is_empty(), "one-off clear wrote persistent progress"):
		return
	if not _expect(_missing.is_empty(), "clear scenario missing assets: %s" % _missing):
		return
	summary["missing"] = Array(_missing)
	var file := FileAccess.open(shots_dir.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "\t"))
	file.close()
	await _key(KEY_ESCAPE)
	await _until(func() -> bool: return flow.current_name == "title", 10.0, "title")
	await _sleep(2.0)
	await _key(KEY_ESCAPE)
	await _sleep(2.0)
	get_tree().quit(1 if _failed else 0)


## Keeps the real Start click while fixing only the boundary seed for reproducible keyboard steering.
func _start_selected(screen: Node) -> void:
	var button: WzButton = screen.get("start_button")
	button.pressed.disconnect(screen.start_selected)
	button.pressed.connect(func() -> void:
		# tier C: diagnostic training seed; --seed overrides it. Production map select still randomizes.
		flow.start_round(String(screen.stages[screen.selected].key), int(args.get("seed", "1"))))
	await _click(button)


func _create_character(character_name: String) -> bool:
	if not await _until(func() -> bool: return flow.current_name == "character_select", 10.0, "character select"):
		return false
	await _sleep(0.5)
	await _shot("character_select")
	await _click(flow.current.get("create_button") as Control)
	await _sleep(0.5)
	var creation: Control = flow.current.get("creation")
	await _shot("creation_gender")
	await _click(creation.get("create_button") as Control)
	await _shot("creation_name")
	await _click(creation.get("name_edit") as Control)
	await _type(character_name)
	await _click(creation.get("create_button") as Control)
	await _shot("creation_look")
	await _click(creation.get("create_button") as Control)
	return await _until(func() -> bool: return flow.current_name == "stage_select", 10.0, "map select")


## Title (Enter) -> a new character -> map select -> Start: the way into a round for the in-run window scenarios.
func _enter_round(character_name: String) -> bool:
	if not await _until(func() -> bool: return flow.current_name == "title", 20.0, "title"):
		return false
	await _sleep(2.0)
	await _key(KEY_ENTER)
	if not await _create_character(character_name):
		return false
	await _sleep(1.5)
	await _start_selected(flow.current)
	return await _until(func() -> bool: return flow.current_name == "run", 10.0, "run")


func _scenario_windows() -> void:
	if not await _enter_round("Windows85"):
		return
	var run := flow.current as RunScene
	await _sleep(3.0)
	await _hold(KEY_RIGHT, 0.6)
	# S: the Stat window opens and the sim holds.
	await _key(KEY_S)
	if not await _until(func() -> bool: return run.ui_windows.find_window("stat") != null, 3.0, "Stat window (S)"):
		return
	var t0 := run.world.time
	await _sleep(1.0)
	_check(run.world.time == t0, "the sim holds while Stat is open (%.3f -> %.3f)" % [t0, run.world.time])
	await _shot("stat_window")
	# Drag the title bar.
	var stat := run.ui_windows.find_window("stat")
	var from := stat.get_global_rect().position + Vector2(60, 8)
	var before := stat.position
	await _drag(from, from + Vector2(-170, 30))
	_check(stat.position == before + Vector2(-170, 30), "the title bar dragged Stat %s -> %s" % [before, stat.position])
	await _shot("stat_dragged")
	# Esc closes it and the run goes on.
	await _key(KEY_ESCAPE)
	await _sleep(0.5)
	_check(not run.ui_windows.has_windows() and not run.paused, "Esc closed Stat without pausing")
	_check(run.world.time > t0, "the sim runs again after Esc")
	# A level-up choice; Stat over it, Esc back to it, 1 picks.
	run.world.pickups.spawn(run.world.player.pos, run.world.progression.exp_to_next(), 4000019)
	if not await _until(func() -> bool: return run.window is LevelUpWindow and (run.window as MapleWindow).is_open(),
			10.0, "level-up window"):
		return
	await _sleep(0.6)
	var lw := run.window as LevelUpWindow
	await _key(KEY_S)
	await _sleep(0.4)
	_check(run.ui_windows.find_window("stat") != null and lw.input_blocked, "Stat opened over the level-up choice")
	await _shot("stat_over_levelup")
	await _key(KEY_1)
	await _sleep(0.2)
	_check(run.world.state == RunWorld.CHOOSING_UPGRADE, "1 picked nothing under the Stat window")
	await _key(KEY_ESCAPE)
	await _sleep(0.4)
	_check(not run.ui_windows.has_windows() and run.window == lw and not lw.input_blocked, "Esc returned to the choice")
	await _key(KEY_1)
	if not await _until(func() -> bool: return run.world.state == RunWorld.PLAYING, 5.0, "card picked with 1"):
		return
	await _sleep(1.0)
	# Menu -> Stat with the mouse.
	await _click(run.hud.menu_button)
	await _sleep(0.4)
	var menu := run.ui_windows.top() as GameMenuPopup
	_check(menu != null, "the Menu button opened its popup")
	if menu == null:
		return
	_hover(menu.get_global_rect().position + menu.entry_rect("stat").get_center())
	await _sleep(0.3)
	await _shot("menu_popup")
	await _click_at(menu.get_global_rect().position + menu.entry_rect("stat").get_center())
	await _sleep(0.4)
	_check(run.ui_windows.ids() == PackedStringArray(["stat"]), "Menu -> Stat opened Stat (%s)" % [run.ui_windows.ids()])
	await _shot("menu_stat")
	# The Menu button still works while a window holds the run; a press elsewhere closes the popup only.
	await _click(run.hud.menu_button)
	await _sleep(0.3)
	_check(run.ui_windows.ids() == PackedStringArray(["stat", "menu"]),
		"the Menu button opens its popup while Stat is open (%s)" % [run.ui_windows.ids()])
	await _click_at(Vector2(get_viewport().get_visible_rect().size.x - 120.0, 150.0))
	await _sleep(0.3)
	_check(run.ui_windows.ids() == PackedStringArray(["stat"]),
		"a press outside closed the popup and kept Stat (%s)" % [run.ui_windows.ids()])
	await _key(KEY_ESCAPE)
	await _sleep(0.3)
	_check(not run.ui_windows.has_windows(), "Esc closed Stat")
	await _key(KEY_ESCAPE)
	await _sleep(0.5)
	_check(run.paused, "with no window open Esc pauses")
	await _key(KEY_ESCAPE)
	await _sleep(0.3)
	_check(not run.paused, "Esc resumes")
	print("flow_driver: windows scenario %s" % ("FAILED" if _failed else "passed"))
	await _sleep(0.5)
	get_tree().quit(1 if _failed else 0)


func _scenario_skill() -> void:
	if not await _enter_round("Skill86"):
		return
	var run := flow.current as RunScene
	await _sleep(3.0)
	# A build to show (debug setup, like the windows scenario's EXP drop): Magician, then Wizard (Ice, Lightning), with
	# behaviour cards on Magic Claw and Thunder Bolt and a Magnet card for the star tab.
	var w := run.world
	w.change_job(200)
	for id: String in ["energy_bolt_new", "magic_claw_new", "magic_claw_targets", "magic_claw_targets",
			"magic_claw_cooldown", "magnet", "magnet"]:
		w.upgrades.apply(id, w)
	w.change_job(220)
	for id: String in ["thunder_bolt_new", "thunder_bolt_targets"]:
		w.upgrades.apply(id, w)
	await _sleep(0.5)
	# K opens the Skill window on the current job's tab and holds the sim.
	await _key(KEY_K)
	if not await _until(func() -> bool: return run.ui_windows.find_window("skill") != null, 3.0, "Skill window (K)"):
		return
	var sw := run.ui_windows.find_window("skill") as SkillWindow
	var t0 := run.world.time
	await _sleep(0.8)
	_check(run.world.time == t0, "the sim holds while Skill is open")
	_check(sw.tab == 2 and sw.model.tabs.size() == 4, "opened on the 2nd-job tab of Beginner / I / II / star")
	await _shot("skill_window")
	# Keyboard: Down moves the selection to Thunder Bolt (the last Ice & Lightning skill) with its tooltip; Left
	# switches to the Magician tab.
	for i in sw.rows().size():
		await _key(KEY_DOWN)
	await _sleep(0.3)
	var tb := sw.tooltip()
	_check(String(tb.get("key", "")) == "thunder_bolt" and not (tb.get("upgrades", []) as Array).is_empty(),
		"Down selected Thunder Bolt with its Upgrades (%s)" % [tb.get("key", "")])
	await _shot("skill_keyboard_tooltip")
	await _key(KEY_LEFT)
	await _sleep(0.3)
	_check(sw.tab == 1, "Left switched to the Magician tab")
	# Mouse: the wheel scrolls Magic Claw into view; hovering it shows the tooltip with its Upgrades.
	var origin := sw.get_global_rect().position
	var claw := -1
	for i in sw.rows().size():
		if String(sw.rows()[i].get("key", "")) == "magic_claw":
			claw = i
	for i in maxi(0, claw - SkillWindow.VISIBLE_ROWS + 1):
		await _wheel(origin + sw.row_rect(1).get_center(), true)
	_hover(origin + sw.row_rect(claw - sw.scroll).get_center())
	await _sleep(0.4)
	var tip := sw.tooltip()
	_check(String(tip.get("key", "")) == "magic_claw" and (tip.get("upgrades", []) as Array).size() == 2,
		"hovering Magic Claw shows Twin Claw and Quick Claw (%s)" % [tip.get("upgrades", [])])
	await _shot("skill_tooltip_upgrades")
	# The star tab with the mouse; hover Magnet.
	await _click_at(origin + sw.tab_rect(3).get_center())
	await _sleep(0.3)
	_check(sw.tab == 3 and sw.rows().size() == 1, "clicked the star tab: Magnet")
	_hover(origin + sw.row_rect(0).get_center())
	await _sleep(0.4)
	_check(String(sw.tooltip().get("id", "")) == "magnet", "Magnet's tooltip")
	await _shot("skill_star_tab")
	await _key(KEY_1)
	await _sleep(0.2)
	_check(sw.tab == 0, "1 switched to the Beginner tab")
	await _key(KEY_ESCAPE)
	await _sleep(0.4)
	_check(not run.ui_windows.has_windows() and not run.paused, "Esc closed Skill without pausing")
	_check(run.world.time > t0, "the sim runs again")
	# Over a level-up choice: K opens it, 1 switches its tab instead of picking, Esc returns, 1 picks.
	run.world.pickups.spawn(run.world.player.pos, run.world.progression.exp_to_next(), 4000019)
	if not await _until(func() -> bool: return run.window is LevelUpWindow and (run.window as MapleWindow).is_open(),
			10.0, "level-up window"):
		return
	await _sleep(0.6)
	var lw := run.window as LevelUpWindow
	await _key(KEY_K)
	await _sleep(0.4)
	_check(run.ui_windows.top() is SkillWindow and lw.input_blocked, "Skill opened over the level-up choice")
	await _key(KEY_1)
	await _sleep(0.2)
	_check(run.world.state == RunWorld.CHOOSING_UPGRADE, "1 picked nothing under the Skill window")
	await _key(KEY_DOWN)
	await _sleep(0.3)
	await _shot("skill_over_levelup")
	await _key(KEY_ESCAPE)
	await _sleep(0.4)
	_check(not run.ui_windows.has_windows() and run.window == lw and not lw.input_blocked, "Esc returned to the choice")
	await _key(KEY_1)
	if not await _until(func() -> bool: return run.world.state == RunWorld.PLAYING, 5.0, "card picked with 1"):
		return
	print("flow_driver: skill scenario %s" % ("FAILED" if _failed else "passed"))
	await _sleep(0.5)
	get_tree().quit(1 if _failed else 0)


func _scenario_keys() -> void:
	_backup_settings()
	var settings := get_node_or_null("/root/Settings") as GameSettings
	if settings == null:
		_fail("no Settings autoload")
		return
	if not await _enter_round("Keys87"):
		return
	var run := flow.current as RunScene
	await _sleep(3.0)
	# Esc pauses; 2 opens Key Config over the pause menu.
	await _key(KEY_ESCAPE)
	await _sleep(0.6)
	_check(run.paused and run.window is PauseMenu, "Esc paused the run")
	await _key(KEY_2)
	await _sleep(0.4)
	var kc := run.ui_windows.top() as KeyConfigWindow
	_check(kc != null and (run.window as MapleWindow).input_blocked, "pause menu -> Key Config, over the pause menu")
	if kc == null:
		_quit()
		return
	await _shot("key_config")
	var origin := kc.get_global_rect().position
	await _drag(origin + kc.key_rect(KEY_C).get_center(), origin + kc.key_rect(KEY_F).get_center())
	await _sleep(0.2)
	_check(kc.draft.action_on(KEY_F) == "jump" and kc.draft.action_on(KEY_C) == "",
		"the jump icon moved from C to F (F: '%s', C: '%s')" % [kc.draft.action_on(KEY_F),
		kc.draft.action_on(KEY_C)])
	_hover(origin + kc.key_rect(KEY_F).get_center())
	await _sleep(0.3)
	await _shot("key_config_rebound")
	await _click(kc._bt_ok)
	await _sleep(0.4)
	_check(not run.ui_windows.has_windows(), "OK closed Key Config")
	_check(KEY_F in settings.binding_keys("jump") and not KEY_C in settings.binding_keys("jump"),
		"OK applied: jump on %s" % [settings.binding_keys("jump")])
	await _key(KEY_ESCAPE)
	await _sleep(0.5)
	_check(not run.paused, "Esc resumed")
	# C no longer jumps, F does.
	var c_jumped: bool = await _jumps(run, KEY_C)
	_check(not c_jumped, "C no longer jumps")
	var f_jumped: bool = await _jumps(run, KEY_F)
	_check(f_jumped, "F jumps")
	# Menu -> Options, WASD.
	await _click(run.hud.menu_button)
	await _sleep(0.4)
	var menu := run.ui_windows.top() as GameMenuPopup
	if menu == null:
		_fail("the Menu popup did not open")
		return
	await _click_at(menu.get_global_rect().position + menu.entry_rect("options").get_center())
	await _sleep(0.4)
	var ow := run.ui_windows.top() as OptionsWindow
	_check(ow != null, "Menu -> Options opened Options")
	if ow == null:
		_quit()
		return
	await _shot("options")
	await _click_at(ow.get_global_rect().position + ow.movement_rect("wasd").get_center())
	await _sleep(0.3)
	_check(settings.movement_keys == "wasd", "Options: movement set to WASD")
	await _shot("options_wasd")
	await _key(KEY_ESCAPE)
	await _sleep(0.4)
	_check(not run.ui_windows.has_windows() and not run.paused, "Esc closed Options")
	var dx := await _moved(run, KEY_RIGHT)
	_check(absf(dx) < 4.0, "the right arrow no longer moves the player (dx %.1f)" % dx)
	dx = await _moved(run, KEY_D)
	_check(dx > 20.0, "D moves the player right (dx %.1f)" % dx)
	# Back to the defaults through the windows themselves.
	run.toggle_window("options")
	await _sleep(0.3)
	ow = run.ui_windows.top() as OptionsWindow
	if ow != null:
		await _click_at(ow.get_global_rect().position + ow.movement_rect("arrows").get_center())
		await _sleep(0.2)
	_check(settings.movement_keys == "arrows", "Options: back to Arrows")
	run.ui_windows.close("options")
	run.toggle_window("key_config")
	await _sleep(0.3)
	kc = run.ui_windows.top() as KeyConfigWindow
	if kc != null:
		await _click(kc._bt_default)
		await _click(kc._bt_ok)
		await _sleep(0.3)
	_check(settings.binding_keys("jump") == GameSettings.default_keys("jump")
		and settings.binding_keys("stat_window") == PackedInt32Array([KEY_S]), "Default + OK restored the keys")
	print("flow_driver: keys scenario %s" % ("FAILED" if _failed else "passed"))
	await _sleep(0.5)
	_quit()


## The Equip and Item windows (#108) in a round, in the Free Market and the dressed character on character select.
func _scenario_inventory() -> void:
	if not await _until(func() -> bool: return flow.current_name == "title", 20.0, "title"):
		return
	await _sleep(2.0)
	await _key(KEY_ENTER)
	if not await _create_character("Inv108"):
		return
	# The slot's character becomes the Lv38 F/P fixture carrying the evidence items (tests grant equipment directly).
	var fixture: Variant = DataRepo.load_json("res://tests/fixtures/characters/lv35_magician_2nd.json")
	if not fixture is Dictionary or CharacterSnapshot.validation_error(fixture) != "":
		_fail("the Lv38 F/P fixture did not load")
		return
	var lib := AssetLibrary.get_default()
	var slot := flow.save.slot(flow.active_slot)
	var character: Dictionary = fixture
	character.erase("_doc")
	for id: int in [1002001, 1050018, 1082002, 1050049]:
		var img := lib.img(AvatarRenderer.part_img_path(id))
		character.equipment.inventory.append(Equipment.create(id, img.root.get("info", {}) if img != null else {}))
	character.mesos = 123456
	slot.character = character
	_check(flow.save.update_slot(flow.active_slot, slot) == OK, "the fixture character was saved into the slot")
	await _sleep(1.0)
	await _start_selected(flow.current)
	if not await _until(func() -> bool: return flow.current_name == "run", 10.0, "run"):
		return
	var run := flow.current as RunScene
	await _sleep(3.0)
	await _hold(KEY_RIGHT, 0.4)
	await _key(KEY_E)
	if not await _until(func() -> bool: return run.ui_windows.find_window("equip") != null, 3.0, "Equip window (E)"):
		return
	var ew := run.ui_windows.find_window("equip") as EquipWindow
	var t0 := run.world.time
	await _sleep(0.8)
	_check(run.world.time == t0, "the sim holds while Equip is open")
	_check(ew.worn_id("weapon") == 1372005, "the Wooden Wand is worn (%d)" % ew.worn_id("weapon"))
	await _shot("equip_window")
	await _key(KEY_I)
	if not await _until(func() -> bool: return run.ui_windows.find_window("item") != null, 3.0, "Item window (I)"):
		return
	var iw := run.ui_windows.find_window("item") as ItemWindow
	_check(iw.meso_text() == "123,456", "the meso line reads 123,456 (%s)" % iw.meso_text())
	_check(iw.cells().size() == 4, "four items in the Equip tab (%d)" % iw.cells().size())
	await _shot("item_windows")
	var io := iw.get_global_rect().position
	var eo := ew.get_global_rect().position
	# Tooltips: the robe (wearable) and the Dark Calas (level, INT and LUK unmet, in red).
	_hover(io + iw.slot_rect(1).get_center())
	await _sleep(0.4)
	_check(String(iw.tooltip().get("name", "")) == "Blue Sauna Robe" and bool(iw.tooltip().get("can_equip", false)),
		"the robe's tooltip (%s)" % [iw.tooltip().get("name", "")])
	await _shot("item_tooltip")
	_hover(io + iw.slot_rect(3).get_center())
	await _sleep(0.4)
	_check(String(iw.tooltip().get("name", "")) == "Dark Calas" and not bool(iw.tooltip().get("can_equip", true)),
		"the Calas's tooltip marks its unmet requirements")
	await _shot("item_tooltip_unmet")
	await _double_click_at(io + iw.slot_rect(3).get_center())
	await _sleep(0.3)
	_check(iw.cells().size() == 4 and not run.world.equipment.worn.has("overall"), "the refused Calas stays put")
	await _shot("equip_refused")
	# Wear the hat (double-click), the robe (drag onto the Equip window) and the gloves (double-click). The robe
	# displaces the top (into its slot) and the bottom (appended): [top, gloves, calas, bottom].
	await _double_click_at(io + iw.slot_rect(0).get_center())
	await _sleep(0.3)
	_check(ew.worn_id("hat") == 1002001, "Metal Gear worn by double-click")
	await _drag(io + iw.slot_rect(0).get_center(), eo + ew.slot_rect("top").get_center())
	await _sleep(0.3)
	_check(ew.worn_id("overall") == 1050018, "the Sauna Robe worn by dragging it onto the Equip window")
	await _double_click_at(io + iw.slot_rect(1).get_center())
	await _sleep(0.3)
	_check(ew.worn_id("gloves") == 1082002, "Work Gloves worn by double-click")
	_check(iw.cells().size() == 3, "the top and bottom took the worn items' places, the Calas stays (%d)"
		% iw.cells().size())
	_hover(eo + ew.slot_rect("top").get_center())
	await _sleep(0.4)
	await _shot("equip_worn")
	# Drag the Calas out: the YesNo box; No keeps it.
	var calas := -1
	for i in iw.cells().size():
		if int(iw.cells()[i].id) == 1050049:
			calas = i
	await _drag(io + iw.slot_rect(calas).get_center(), Vector2(get_viewport().get_visible_rect().size.x - 60.0, 120.0))
	await _sleep(0.4)
	var confirm := run.ui_windows.top() as DropConfirm
	_check(confirm != null, "dragging an item out asks the v83 question")
	await _shot("drop_confirm")
	if confirm != null:
		await _click(confirm._bt_no)
		await _sleep(0.3)
	_check(iw.cells().size() == 3, "No kept the Calas")
	await _click_at(io + iw.tab_rect(1).get_center())
	await _sleep(0.3)
	_check(iw.tab == 1 and iw.cells().size() >= 2, "the Use tab shows the potion stacks")
	_hover(io + iw.slot_rect(0).get_center())
	await _sleep(0.4)
	await _shot("item_use_tab")
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	await _sleep(0.6)
	_check(not run.ui_windows.has_windows() and not run.paused, "Esc closed both windows without pausing")
	_check(run.world.time > t0, "the sim runs again")
	await _shot("character_dressed")
	_collect_missing(run)
	# The same character in the Free Market: the slot moves to the hub and Continue opens it.
	var carried := run.world.character_snapshot()
	slot = flow.save.slot(flow.active_slot)
	slot.character = carried
	slot.phase = "free_market"
	_check(flow.save.update_slot(flow.active_slot, slot) == OK, "the dressed character was saved at the hub")
	flow.continue_character(flow.active_slot)
	if not await _until(func() -> bool: return flow.current_name == "free_market", 10.0, "Free Market"):
		return
	var hub := flow.current as FreeMarket
	await _sleep(1.5)
	await _key(KEY_E)
	await _key(KEY_I)
	await _sleep(0.4)
	_check(hub.ui_windows.ids() == PackedStringArray(["equip", "item"]), "E and I open in the hub (%s)" % [hub.ui_windows.ids()])
	await _shot("hub_windows")
	var hew := hub.ui_windows.find_window("equip") as EquipWindow
	if hew != null:
		await _double_click_at(hew.get_global_rect().position + hew.slot_rect("hat").get_center())
		await _sleep(0.4)
		_check(hew.worn_id("hat") == 0 and not flow.save.slot(flow.active_slot).character.equipment.worn.has("hat"),
			"the hat came off in the hub and the slot was saved")
		await _shot("hub_hat_off")
		var hiw := hub.ui_windows.find_window("item") as ItemWindow
		var hat := -1
		for i in hiw.cells().size():
			if int(hiw.cells()[i].id) == 1002001:
				hat = i
		await _double_click_at(hiw.get_global_rect().position + hiw.slot_rect(hat).get_center())
		await _sleep(0.3)
		_check(hew.worn_id("hat") == 1002001, "and back on")
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	await _sleep(0.3)
	_check(not hub.windows_open(), "Esc closed the hub's windows")
	await _hold(KEY_RIGHT, 0.5)
	await _shot("hub_dressed")
	_collect_missing(hub)
	flow.save_and_quit()
	if not await _until(func() -> bool: return flow.current_name == "character_select", 10.0, "character select"):
		return
	await _sleep(1.5)
	await _shot("character_select_dressed")
	_check(_missing.is_empty(), "missing assets: %s" % [_missing])
	print("flow_driver: inventory scenario %s (missing: %s)" % ["FAILED" if _failed else "passed", _missing])
	await _sleep(0.5)
	get_tree().quit(1 if _failed else 0)


## Scrolling (#110) in a round and in the Free Market: real drags from the Use tab onto the worn item.
func _scenario_scrolls() -> void:
	if not await _until(func() -> bool: return flow.current_name == "title", 20.0, "title"):
		return
	await _sleep(2.0)
	await _key(KEY_ENTER)
	if not await _create_character("Scroll110"):
		return
	var fixture: Variant = DataRepo.load_json("res://tests/fixtures/characters/lv35_magician_2nd.json")
	if not fixture is Dictionary or CharacterSnapshot.validation_error(fixture) != "":
		_fail("the Lv38 F/P fixture did not load")
		return
	var lib := AssetLibrary.get_default()
	var slot := flow.save.slot(flow.active_slot)
	var character: Dictionary = fixture
	character.erase("_doc")
	var hat_img := lib.img(AvatarRenderer.part_img_path(1002001))
	character.equipment.worn["hat"] = Equipment.create(1002001, hat_img.root.get("info", {}) if hat_img != null else {})
	character.scrolls = {"2043700": 3, "2043702": 6, "2043705": 30, "2040000": 2}
	slot.character = character
	_check(flow.save.update_slot(flow.active_slot, slot) == OK, "the fixture character was saved into the slot")
	await _sleep(1.0)
	await _start_selected(flow.current)
	if not await _until(func() -> bool: return flow.current_name == "run", 10.0, "run"):
		return
	var run := flow.current as RunScene
	await _sleep(3.0)
	await _key(KEY_E)
	await _key(KEY_I)
	if not await _until(func() -> bool: return run.ui_windows.find_window("item") != null, 3.0, "Item window (I)"):
		return
	var ew := run.ui_windows.find_window("equip") as EquipWindow
	var iw := run.ui_windows.find_window("item") as ItemWindow
	var io := iw.get_global_rect().position
	var eo := ew.get_global_rect().position
	await _click_at(io + iw.tab_rect(1).get_center())
	await _sleep(0.3)
	_check(iw.tab == 1, "the Use tab is shown")
	var ids := iw.cells().map(func(c: Dictionary) -> int: return int(c.id))
	_check(2043700 in ids and 2043705 in ids and 2040000 in ids, "the Use tab holds the scroll stacks (%s)" % [ids])
	_hover(io + iw.slot_rect(ids.find(2043705)).get_center())
	await _sleep(0.4)
	await _shot("scroll_use_tab")
	var world := run.world
	var m_before := int(world.equipment.worn.weapon.stats.get("incMAD", 0))
	var slots_before := int(world.equipment.worn.weapon.slots)
	var t0 := world.time
	await _drag(io + iw.slot_rect(ids.find(2043700)).get_center(), eo + ew.slot_rect("weapon").get_center())
	_check(int(world.scrolls.get("2043700", 0)) == 2, "the 100% scroll was used up")
	_check(int(world.equipment.worn.weapon.stats.get("incMAD", 0)) == m_before + 1, "M.ATT +1 from the 100% scroll")
	_check(int(world.equipment.worn.weapon.slots) == slots_before - 1 and int(world.equipment.worn.weapon.scrolls) == 1,
		"one upgrade slot spent, one scroll counted")
	_check(run.enchant.renderer.active_count() == 1, "the Enchant effect plays over the character")
	await _shot("scroll_success")
	_hover(eo + ew.slot_rect("weapon").get_center())
	await _sleep(0.5)
	var tip := ew.tooltip()
	_check(int(tip.get("slots", -1)) == slots_before - 1 and int(tip.get("scrolls", -1)) == 1,
		"the tooltip shows the new upgrade slots and scroll count")
	await _shot("scroll_tooltip")
	_check(world.time == t0, "the sim held the whole time")
	# Plain 10% scrolls until one fails (the slot is spent, the wand stays), then dark 30% scrolls until the wand is
	# destroyed.
	var failed_shot := false
	for attempt in 6:
		var scrolls_before := int(world.equipment.worn.weapon.scrolls)
		var slots_left := int(world.equipment.worn.weapon.slots)
		var plain := iw.cells().map(func(c: Dictionary) -> int: return int(c.id)).find(2043702)
		await _drag(io + iw.slot_rect(plain).get_center(), eo + ew.slot_rect("weapon").get_center())
		var plain_failed: bool = int(world.equipment.worn.weapon.scrolls) == scrolls_before
		print("flow_driver: 10%% scroll %d: %s" % [attempt + 1, "failure" if plain_failed else "success"])
		if plain_failed:
			_check(world.equipment.worn.has("weapon") and int(world.equipment.worn.weapon.slots) == slots_left - 1,
				"a failed plain scroll spends only the slot")
			failed_shot = true
			await _shot("scroll_failure")
			break
		await _sleep(1.2)
	_check(failed_shot, "a 10 percent scroll failed within six tries")
	for attempt in 6:
		if not world.equipment.worn.has("weapon") or int(world.equipment.worn.weapon.slots) <= 0:
			break
		var dark := iw.cells().map(func(c: Dictionary) -> int: return int(c.id)).find(2043705)
		await _drag(io + iw.slot_rect(dark).get_center(), eo + ew.slot_rect("weapon").get_center())
		var destroyed: bool = not world.equipment.worn.has("weapon")
		print("flow_driver: dark scroll %d: %s" % [attempt + 1, "destroyed" if destroyed else "survived"])
		if destroyed:
			await _shot("scroll_destroyed")
			break
		await _sleep(1.2)
	_check(not world.equipment.worn.has("weapon"), "the wand was destroyed by a failed dark scroll")
	_check(world.weapon_id() == 0 and world.weapon_attack() == 0.0, "the character is bare-handed")
	await _sleep(1.5)
	await _shot("scroll_bare_handed")
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	await _sleep(0.6)
	var kills_before := world.kills
	await _sleep(6.0)
	_check(world.time > t0, "the run goes on after the windows closed")
	print("flow_driver: kills %d -> %d while bare-handed" % [kills_before, world.kills])
	_collect_missing(run)
	# The Free Market: a 100% hat scroll onto Metal Gear.
	var carried := world.character_snapshot()
	slot = flow.save.slot(flow.active_slot)
	slot.character = carried
	slot.phase = "free_market"
	_check(flow.save.update_slot(flow.active_slot, slot) == OK, "the character was saved at the hub")
	flow.continue_character(flow.active_slot)
	if not await _until(func() -> bool: return flow.current_name == "free_market", 10.0, "Free Market"):
		return
	var hub := flow.current as FreeMarket
	await _sleep(1.5)
	await _key(KEY_E)
	await _key(KEY_I)
	await _sleep(0.4)
	var hew := hub.ui_windows.find_window("equip") as EquipWindow
	var hiw := hub.ui_windows.find_window("item") as ItemWindow
	if hew == null or hiw == null:
		_fail("the hub's windows did not open")
		return
	await _click_at(hiw.get_global_rect().position + hiw.tab_rect(1).get_center())
	await _sleep(0.3)
	var hub_ids := hiw.cells().map(func(c: Dictionary) -> int: return int(c.id))
	var hat_slot_before := int(flow.save.slot(flow.active_slot).character.equipment.worn.hat.slots)
	await _drag(hiw.get_global_rect().position + hiw.slot_rect(hub_ids.find(2040000)).get_center(),
		hew.get_global_rect().position + hew.slot_rect("hat").get_center())
	_check(hub.enchant.renderer.active_count() == 1, "the hub plays the Enchant effect")
	var saved: Dictionary = flow.save.slot(flow.active_slot).character
	_check(int(saved.scrolls.get("2040000", 0)) == 1 and int(saved.equipment.worn.hat.slots) == hat_slot_before - 1
		and int(saved.equipment.worn.hat.scrolls) == 1, "the hub saved the scrolled hat and the used scroll")
	await _shot("hub_scroll_success")
	_collect_missing(hub)
	_check(_missing.is_empty(), "missing assets: %s" % [_missing])
	print("flow_driver: scrolls scenario %s (missing: %s)" % ["FAILED" if _failed else "passed", _missing])
	await _sleep(0.5)
	get_tree().quit(1 if _failed else 0)


## The scroll shops (#111) in the Free Market: real key presses, clicks and a double-click.
func _scenario_shops() -> void:
	if not await _until(func() -> bool: return flow.current_name == "title", 20.0, "title"):
		return
	await _sleep(2.0)
	await _key(KEY_ENTER)
	if not await _create_character("Shop111"):
		return
	var fixture: Variant = DataRepo.load_json("res://tests/fixtures/characters/lv35_magician_2nd.json")
	if not fixture is Dictionary or CharacterSnapshot.validation_error(fixture) != "":
		_fail("the Lv38 F/P fixture did not load")
		return
	var lib := AssetLibrary.get_default()
	var slot := flow.save.slot(flow.active_slot)
	var character: Dictionary = fixture
	character.erase("_doc")
	character.mesos = 250000
	character.scrolls = {"2043700": 4, "2043705": 6, "2040000": 2}
	for id: int in [1002001, 1382001, 1082002, 1040004]:
		var img := lib.img(AvatarRenderer.part_img_path(id))
		character.equipment.inventory.append(Equipment.create(id, img.root.get("info", {}) if img != null else {}))
	slot.character = character
	slot.phase = "free_market"
	_check(flow.save.update_slot(flow.active_slot, slot) == OK, "the character was saved at the hub")
	flow.continue_character(flow.active_slot)
	if not await _until(func() -> bool: return flow.current_name == "free_market", 10.0, "Free Market"):
		return
	var hub := flow.current as FreeMarket
	await _sleep(1.5)
	# The player's own settings.cfg may have given Space to another action (then NPC Chat has no key): the driver puts
	# NPC Chat on its project default in the InputMap only, so the evidence run does not depend on the developer's keys.
	InputMap.action_erase_events("npc_chat")
	for code in GameSettings.default_keys("npc_chat"):
		var ev := InputEventKey.new()
		ev.physical_keycode = code as Key
		InputMap.action_add_event("npc_chat", ev)
	_check(hub.shop_npcs.map(func(n: Dictionary) -> int: return int(n.id)) == [1032103, 2022002, 1052104, 2041016],
		"the four scroll NPCs stand in the Free Market")
	hub.motion.player.place(Vector2(-210, 34), hub.motion.fhm)
	hub.camera.snap_to(hub.motion.player.pos)
	await _sleep(0.8)
	await _shot("shop_npcs")
	# Space next to El Moth opens his shop.
	hub.motion.player.place(Vector2(-350, 34), hub.motion.fhm)
	hub.camera.snap_to(hub.motion.player.pos)
	await _sleep(0.5)
	await _key(KEY_SPACE)
	await _sleep(0.6)
	var shop := hub.ui_windows.find_window("shop") as ShopWindow
	if shop == null:
		_fail("Space next to El Moth did not open his shop")
		return
	_check(shop.npc_id == 1032103 and hub.windows_open(), "El Moth's shop is open and the hub holds")
	_check(shop.stock.all(func(e: Dictionary) -> bool: return e.rate == "100"), "El Moth sells only 100% scrolls")
	await _shot("shop_open")
	var origin := shop.get_global_rect().position
	var wand := shop.stock.map(func(e: Dictionary) -> int: return int(e.id)).find(2043700)
	_check(wand >= 0, "the wand Magic Att. 100% scroll is in the stock of a Wizard")
	shop.scroll_panel(0, 99)
	await _sleep(0.3)
	var visible_first := shop.buy_offset
	var row := wand - visible_first
	await _click_at(origin + shop.row_rect(0, clampi(row, 0, ShopWindow.ROWS - 1)).get_center())
	await _sleep(0.3)
	_check(shop.buy_selected == wand, "a click selects the wand scroll row (selected %d, want %d)" % [shop.buy_selected, wand])
	_hover(origin + shop.row_rect(0, clampi(row, 0, ShopWindow.ROWS - 1)).get_center() + Vector2(60, 0))
	await _sleep(0.5)
	await _shot("shop_selected")
	var mesos_before := hub.inventory.mesos
	await _click(shop._bt_buy)
	await _sleep(0.4)
	var quantity := hub.ui_windows.find_window("shop_quantity") as ShopQuantity
	if quantity == null:
		_fail("Buy did not ask how many")
		return
	await _key(KEY_2)
	await _sleep(0.3)
	await _shot("shop_quantity")
	await _key(KEY_ENTER)
	await _sleep(0.5)
	_check(hub.inventory.mesos == mesos_before - 140000 and int(hub.inventory.scrolls.get("2043700", 0)) == 6,
		"two wand scrolls cost 140,000 (mesos %d)" % hub.inventory.mesos)
	_check(int(flow.save.slot(flow.active_slot).character.mesos) == hub.inventory.mesos, "the purchase was saved at once")
	_hover(origin + Vector2(10, 330))
	await _sleep(0.3)
	await _shot("shop_bought")
	# Not enough mesos: 110,000 left, two more wand scrolls need 140,000.
	await _click(shop._bt_buy)
	await _sleep(0.3)
	await _key(KEY_2)
	await _key(KEY_ENTER)
	await _sleep(0.5)
	_check(hub.ui_windows.find_window("shop_notice") != null and shop.last_notice == "You do not have enough mesos.",
		"a purchase without the mesos shows the notice")
	_check(hub.inventory.mesos == mesos_before - 140000, "and changes nothing")
	await _shot("shop_refused")
	await _key(KEY_ENTER)
	await _sleep(0.3)
	# Selling: the Use tab's scroll stack, then a spare item.
	await _click_at(origin + shop.tab_rect(1).get_center())
	await _sleep(0.3)
	await _click_at(origin + shop.row_rect(1, 0).get_center())
	await _sleep(0.3)
	await _shot("shop_sell_use")
	var sold_cells := shop.sell_cells()
	_check(sold_cells.size() == 3 and shop.sell_selected == 0, "the Use tab lists the three scroll stacks, one selected")
	await _click(shop._bt_sell)
	await _sleep(0.4)
	await _key(KEY_ENTER)
	await _sleep(0.4)
	await _click_at(origin + shop.tab_rect(0).get_center())
	await _sleep(0.3)
	await _click_at(origin + shop.row_rect(1, 1).get_center())
	await _sleep(0.3)
	var price := shop.row_price(shop.selected_sale())
	var before_sale := hub.inventory.mesos
	await _click(shop._bt_sell)
	await _sleep(0.4)
	_check(hub.ui_windows.find_window("drop_confirm") != null, "selling equipment asks first")
	await _shot("shop_sell_confirm")
	await _key(KEY_ENTER)
	await _sleep(0.5)
	_check(hub.inventory.mesos == before_sale + price and price > 0, "the spare item sold for its price %d" % price)
	await _shot("shop_sold")
	await _key(KEY_ESCAPE)
	await _sleep(0.4)
	_check(hub.ui_windows.find_window("shop") == null and not hub.windows_open(), "Esc closed the shop")
	# A double-click on Barun opens the 60% shop; Vega sells the dark scrolls.
	var barun: Dictionary = hub.shop_npcs[1]
	var barun_screen: Vector2 = hub.get_canvas_transform() * ((barun.rect as Rect2).get_center())
	await _double_click_at(barun_screen)
	await _sleep(0.6)
	var second := hub.ui_windows.find_window("shop") as ShopWindow
	_check(second != null and second.npc_id == 2022002, "a double-click on Barun opens his shop")
	if second != null:
		await _shot("shop_barun")
		await _key(KEY_ESCAPE)
		await _sleep(0.3)
	hub.motion.player.place(Vector2(30, 34), hub.motion.fhm)
	hub.camera.snap_to(hub.motion.player.pos)
	await _sleep(0.4)
	await _key(KEY_SPACE)
	await _sleep(0.6)
	var third := hub.ui_windows.find_window("shop") as ShopWindow
	_check(third != null and third.npc_id == 2041016, "Space next to Vega opens his shop")
	if third != null:
		await _shot("shop_vega")
		await _key(KEY_ESCAPE)
	_collect_missing(hub)
	_check(_missing.is_empty(), "missing assets: %s" % [_missing])
	print("flow_driver: shops scenario %s (missing: %s)" % ["FAILED" if _failed else "passed", _missing])
	await _sleep(0.5)
	get_tree().quit(1 if _failed else 0)


## The bot shop plan (#112) in the Free Market: the hub's bot hook visits the shops, the windows show the result.
func _scenario_botshop() -> void:
	if not await _until(func() -> bool: return flow.current_name == "title", 20.0, "title"):
		return
	await _sleep(2.0)
	await _key(KEY_ENTER)
	if not await _create_character("Bot112"):
		return
	var fixture: Variant = DataRepo.load_json("res://tests/fixtures/characters/lv35_magician_2nd.json")
	if not fixture is Dictionary or CharacterSnapshot.validation_error(fixture) != "":
		_fail("the Lv38 F/P fixture did not load")
		return
	var lib := AssetLibrary.get_default()
	var slot := flow.save.slot(flow.active_slot)
	var character: Dictionary = fixture
	character.erase("_doc")
	character.mesos = 600000
	for id: int in [1002001, 1382001, 1082002, 1040004]:
		var img := lib.img(AvatarRenderer.part_img_path(id))
		character.equipment.inventory.append(Equipment.create(id, img.root.get("info", {}) if img != null else {}))
	slot.character = character
	slot.phase = "free_market"
	_check(flow.save.update_slot(flow.active_slot, slot) == OK, "the character was saved at the hub")
	flow.continue_character(flow.active_slot)
	if not await _until(func() -> bool: return flow.current_name == "free_market", 10.0, "Free Market"):
		return
	var hub := flow.current as FreeMarket
	await _sleep(1.5)
	await _key(KEY_I)
	await _sleep(0.5)
	await _shot("botshop_before_item")
	await _key(KEY_ESCAPE)
	var mesos_before := hub.inventory.mesos
	var record := hub.bot_shop("bot", 1)
	await _sleep(1.0)
	print("flow_driver: bot shop record ", JSON.stringify(record))
	_check(int(record.bought) > 0 and int(record.used) == int(record.bought), "the bot bought and read scrolls (%s)" % [record])
	_check(int(record.spent) > 0 and hub.inventory.mesos == mesos_before + int(record.sale_mesos) - int(record.spent),
		"mesos add up (%d -> %d)" % [mesos_before, hub.inventory.mesos])
	_check(int(flow.save.slot(flow.active_slot).character.mesos) == hub.inventory.mesos, "the visit was saved at once")
	await _key(KEY_E)
	await _sleep(0.5)
	await _shot("botshop_after_equip")
	await _key(KEY_ESCAPE)
	await _key(KEY_I)
	await _sleep(0.5)
	await _shot("botshop_after_item")
	_collect_missing(hub)
	_check(_missing.is_empty(), "missing assets: %s" % [_missing])
	print("flow_driver: botshop scenario %s (missing: %s)" % ["FAILED" if _failed else "passed", _missing])
	await _sleep(0.5)
	get_tree().quit(1 if _failed else 0)


## Presses `k` once with the player standing; true when the player took off within 0.5 s.
func _jumps(run: RunScene, k: Key) -> bool:
	var p := run.world.player
	await _until(func() -> bool: return p.state != PlayerMotion.ST_AIR, 5.0, "player on the ground")
	await _sleep(0.3)
	_send_key(k, true)
	var took_off := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 500:
		await get_tree().process_frame
		if p.vel.y < -200.0:
			took_off = true
	_send_key(k, false)
	await _sleep(0.8)
	return took_off


## Holds `k` for 0.6 s; how far the player moved along x.
func _moved(run: RunScene, k: Key) -> float:
	await _until(func() -> bool: return run.world.player.state != PlayerMotion.ST_AIR, 5.0, "player on the ground")
	var x0 := run.world.player.pos.x
	await _hold(k, 0.6)
	await _sleep(0.2)
	return run.world.player.pos.x - x0


func _backup_settings() -> void:
	_settings_saved = true
	_settings_backup = FileAccess.get_file_as_bytes(GameSettings.PATH) if FileAccess.file_exists(GameSettings.PATH) \
		else null


## Puts user://settings.cfg back as it was before the keys scenario (no-op for other scenarios).
func _restore_settings() -> void:
	if not _settings_saved:
		return
	_settings_saved = false
	if _settings_backup == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.PATH))
	else:
		var f := FileAccess.open(GameSettings.PATH, FileAccess.WRITE)
		f.store_buffer(_settings_backup)
		f.close()
	print("flow_driver: settings.cfg restored")


func _quit() -> void:
	_restore_settings()
	get_tree().quit(1 if _failed else 0)


## Records a scenario check (a failed one makes the driver exit 1 at the end).
func _check(ok: bool, what: String) -> void:
	print("flow_driver: %s %s" % ["ok" if ok else "FAILED", what])
	if not ok:
		_failed = true
		push_error("flow_driver: " + what)


func _scenario_title() -> void:
	if not await _until(func() -> bool: return flow.current_name == "title", 30.0, "title"):
		return
	await _sleep(9.0)
	await _shot("title")
	await _key(KEY_ESCAPE)
	await _sleep(2.0)
	get_tree().quit(1 if _failed else 0)


func _scenario_import() -> void:
	if not await _until(func() -> bool: return flow.current_name == "import", 20.0, "import screen"):
		return
	await _sleep(1.0)
	await _shot("import_screen")
	var wz := String(args.get("wz", ""))
	if wz == "":
		print("flow_driver: no --wz folder; import screen only")
		get_tree().quit(1 if _failed else 0)
		return
	var screen: Node = flow.current
	var edit := screen.get("path_edit") as LineEdit
	await _click(edit)
	edit.select_all()
	await _type(wz)
	await _sleep(0.3)
	await _shot("import_folder_typed")
	await _click(screen.get("import_button") as Control)
	await _sleep(0.5)
	await _shot("import_running")
	# The screen opens the title 0.8 s after a successful import and is freed then.
	var finished := func() -> bool: return not is_instance_valid(screen) or String(screen.get("state")) in ["done", "failed"]
	if not await _until(finished, 900.0, "importer"):
		return
	if is_instance_valid(screen):
		await _shot("import_" + String(screen.get("state")))
	if not await _until(func() -> bool: return flow.current_name == "title", 20.0, "title after import"):
		return
	await _sleep(9.0)
	await _shot("title_after_import")
	get_tree().quit(1 if _failed else 0)


# --- steering: BotInput's decision sent as key presses -----------------------------------------------------------

func _steer_run() -> void:
	var run := flow.current as RunScene
	if run == null or run.world == null or run.window != null or run.paused or run.world.state != RunWorld.PLAYING:
		return
	var mi := BotInput.decide(run.world, _memo)
	_set_key("left", mi.left)
	_set_key("right", mi.right)
	_set_key("up", mi.up)
	_set_key("down", mi.down)
	_set_key("jump", mi.jump_pressed)
	_set_key("drink_hp", mi.drink_hp)
	_set_key("drink_mp", mi.drink_mp)


func _set_key(action: String, down: bool) -> void:
	if bool(_held.get(action, false)) == down:
		return
	_held[action] = down
	_send_key(KEYS[action], down)


func _release_all() -> void:
	for a: String in KEYS:
		_set_key(a, false)


## The index of the card BotInput.pick_card_for would take.
func _card_index(run: RunScene, cards: Array) -> int:
	var id := BotInput.pick_card_for(run.world, cards)
	for i in cards.size():
		if String(cards[i].get("id", "")) == id:
			return i
	return 0


# --- input and capture helpers -----------------------------------------------------------------------------------

func _send_key(k: Key, down: bool, unicode := 0) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.unicode = unicode
	e.pressed = down
	Input.parse_input_event(e)


func _key(k: Key) -> void:
	_send_key(k, true)
	await get_tree().process_frame
	await get_tree().process_frame
	_send_key(k, false)
	await get_tree().process_frame


func _hold(k: Key, seconds: float) -> void:
	_send_key(k, true)
	await _sleep(seconds)
	_send_key(k, false)
	await get_tree().process_frame


## Types `text` as key presses with unicode characters (into the focused LineEdit).
func _type(text: String) -> void:
	for i in text.length():
		var c := text.unicode_at(i)
		_send_key(KEY_NONE, true, c)
		await get_tree().process_frame
		_send_key(KEY_NONE, false, c)


## A left click at the centre of control `c` (moving the mouse there first).
func _click(c: Control) -> void:
	if c == null:
		_fail("click target missing")
		return
	await _click_at(c.get_global_rect().get_center())


## A left click at logical (viewport) position `p`; events carry window coordinates (the stretch transform applied).
func _click_at(p: Vector2) -> void:
	var w := get_tree().root.get_final_transform() * p
	var m := InputEventMouseMotion.new()
	m.position = w
	m.global_position = w
	Input.parse_input_event(m)
	await get_tree().process_frame
	await get_tree().process_frame
	for down: bool in [true, false]:
		var b := InputEventMouseButton.new()
		b.button_index = MOUSE_BUTTON_LEFT
		b.pressed = down
		b.position = w
		b.global_position = w
		Input.parse_input_event(b)
		await get_tree().process_frame


## A left double-click at logical position `p` (two clicks, the second press flagged double_click as Godot sends it).
func _double_click_at(p: Vector2) -> void:
	await _click_at(p)
	var w := get_tree().root.get_final_transform() * p
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = true
	b.double_click = true
	b.position = w
	b.global_position = w
	Input.parse_input_event(b)
	await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = w
	up.global_position = w
	Input.parse_input_event(up)
	await get_tree().process_frame


## One mouse-wheel notch (down or up) at logical position `p`.
func _wheel(p: Vector2, down: bool) -> void:
	_hover(p)
	await get_tree().process_frame
	var w := get_tree().root.get_final_transform() * p
	for pressed: bool in [true, false]:
		var b := InputEventMouseButton.new()
		b.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
		b.pressed = pressed
		b.position = w
		b.global_position = w
		Input.parse_input_event(b)
		await get_tree().process_frame


## Moves the mouse to logical position `p` (no button).
func _hover(p: Vector2) -> void:
	var w := get_tree().root.get_final_transform() * p
	var m := InputEventMouseMotion.new()
	m.position = w
	m.global_position = w
	Input.parse_input_event(m)


## A left-button drag from logical `a` to `b` in a few motion steps.
func _drag(a: Vector2, b: Vector2) -> void:
	var xf := get_tree().root.get_final_transform()
	_hover(a)
	await get_tree().process_frame
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = xf * a
	down.global_position = down.position
	Input.parse_input_event(down)
	await get_tree().process_frame
	for i in range(1, 7):
		var m := InputEventMouseMotion.new()
		m.position = xf * a.lerp(b, i / 6.0)
		m.global_position = m.position
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(m)
		await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = xf * b
	up.global_position = up.position
	Input.parse_input_event(up)
	await get_tree().process_frame


func _sleep(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _until(cond: Callable, timeout: float, what: String) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > int(timeout * 1000.0):
			_fail("timed out waiting for %s (current: %s)" % [what, flow.current_name])
			return false
		await get_tree().process_frame
	print("flow_driver: %s (%.1f s)" % [what, (Time.get_ticks_msec() - t0) / 1000.0])
	return true


func _shot(step: String) -> void:
	# The collaborative desktop may occlude the window; explicitly render this evidence frame.
	# tier C: let the existing modal input guard and 0.15s open transition finish before the next input/capture.
	await _sleep(0.35)
	await get_tree().process_frame
	RenderingServer.force_draw()
	_collect_missing(flow.current)
	_n += 1
	var path := shots_dir.path_join("%02d_%s.png" % [_n, step])
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path) if img != null else ERR_CANT_CREATE
	print("flow_driver: shot %s %s err=%d" % [path.get_file(), img.get_size() if img != null else Vector2i.ZERO, err])
	if err != OK:
		_failed = true
		push_error("flow_driver: could not save screenshot " + path)


## Retains misses before scene disposal, including renderer/UI lookups outside AssetLibrary.missing.
func _collect_missing(node: Node) -> void:
	if node == null:
		return
	if node is RunScene:
		for path: String in node.setup_missing:
			if not path in _missing:
				_missing.append(path)
	if node is WzImage and not node.has_art() and not node.path in _missing:
		_missing.append(node.path)
	if node is WzButton and not node.has_art() and not node.base_path in _missing:
		_missing.append(node.base_path)
	if node.has_method("missing_paths"):
		for path: String in node.call("missing_paths"):
			if not path in _missing:
				_missing.append(path)
	for property: Dictionary in node.get_property_list():
		if property.name == "missing":
			for item: Variant in node.get("missing"):
				var path := "Mob.wz/%07d.img" % int(item) if node is MobRenderer else String(item)
				if not path in _missing:
					_missing.append(path)
	for child: Node in node.get_children():
		_collect_missing(child)
	for path: String in AssetLibrary.get_default().missing:
		if not path in _missing:
			_missing.append(path)


func _fail(msg: String) -> void:
	_failed = true
	push_error("flow_driver: " + msg)
	print("flow_driver: FAILED " + msg)
	await _shot("failed")
	_restore_settings()
	get_tree().quit(1)
