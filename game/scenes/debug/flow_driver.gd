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
##   skill_weapon  weapon-gated skills (#156): a Magician owning Magic Claw and Energy Bolt, with Magic Claw tagged claw-only
##           through the survivor weapon_families override (debug setup; no shipping skill needs a weapon yet); K opens Skill
##           (the held weapon cannot use Magic Claw: greyed row, tooltip "Weapon : Claw (not held)"), Esc closes. Shots:
##           skill_weapon_greyed, skill_weapon_tooltip.
##   skill_warrior  the Warrior's Skill window (#163): a Warrior owning all six skills and a Cleaving Strike card (debug
##           setup); K opens Skill on the Warrior tab, hovering Slash Blast shows its HP / MP cost and weapon line, Esc
##           closes and Iron Body casts itself (debug MP). Shots: skill_warrior_window, skill_warrior_tooltip,
##           skill_warrior_iron_body.
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
##   economy the whole spec-#33 loop (#113): title -> new character, whose slot becomes the Lv38 F/P fixture -> a Henesys
##           round; four meso sprites and two items (Metal Gear, a Dark Calas) lie on the ground, the character walks
##           over them (HUD notices); E and I, the tooltips, Metal Gear worn by double-click; the bot's fixed-tick warp
##           clears the round into the Free Market (saved boundary checked: worn hat, inventory, mesos); the
##           character walks past the four scroll NPCs, Space opens El Moth's shop, a 100% hat INT scroll is bought
##           (quantity box) and the spare Calas sold (YesNo box), Space at Tulcus buys three 10% hat scrolls; they are
##           dragged from the Use tab onto the worn hat (Enchant success, then until one fails); Save & quit,
##           Continue: mesos, worn equipment, inventory and scrolls equal the snapshot before quitting. The warp
##           takes a few minutes. Shots: economy_drops_on_the_ground, economy_pickup_notices, economy_picked_up,
##           economy_item_window_tooltip, economy_tooltip_unmet, economy_equip_window_hat_worn, economy_scroll_npcs,
##           economy_shop_open, economy_shop_buying, economy_shop_sell_selected, economy_shop_selling,
##           economy_shop_sold, economy_shop_tulcus, economy_scroll_success, economy_scrolled_tooltip, economy_scroll_failure, economy_character_scrolled,
##           economy_save_and_quit, economy_character_select, economy_continue_restored; summary.json.
##   warrior the Warrior first job end to end (spec #151 QA #164): title -> new character holding a spare Wooden Shield
##           (debug setup, a kit item in the slot) -> round; EXP drops take it to Lv10 through the real level-up cards
##           and the real job window, where Warrior is picked (the Beginner Warrior's sword 1302077 is worn; the creation sword, a Spear and a Steel Pipe
##           wait in the Equip tab); the bot's
##           steering plays a few seconds, E and I wear the shield by double-click (Equip window, weapon + shield
##           drawn); the slot moves to the Free Market (the carried snapshot is saved at the boundary, a debug
##           shortcut for the multi-minute warp) and Continue opens the hub; Esc -> Save & quit -> character select
##           -> Continue again: job, weapon, shield, skills and mesos equal the snapshot before quitting. Shots:
##           warrior_job_window, warrior_job_confirm, warrior_advanced, warrior_playing, warrior_shield_worn,
##           warrior_hub, warrior_save_and_quit, warrior_character_select, warrior_continue_restored; summary.json.
##   import  for a cache-less start (point MAPLE_SURVIVORS_CACHE / APPDATA at an empty folder): the import screen,
##           types --wz=<folder> into the path field, clicks Import, waits for the importer and the title.
##   cash_shop  the Cash Shop (#118) from a prepared test save (5,000 NX): title -> new character -> map select SHOP -> Equip tab
##           (try-on, sub-tab, buy dialog, OK, a purchase that costs too much, Pet tab with locked upgrades) -> EXIT back to map
##           select -> the saved boundary is turned into a Free Market one, Save & quit, Continue -> status bar SHOP -> EXIT
##           back to the Free Market. Shots: shop_*.png (the first is the Cash Shop shot to compare with the v83 references).
##   cash_equip  the Equip window's Cash tab and Pet page (#122), continuing the #118 purchase: 12,000 NX -> new character ->
##           map select SHOP -> buy the first hat and the first pet -> Free Market (boundary patched, Save & quit, Continue) ->
##           E, Cash tab, a double-click wears the hat -> PET EQUIP., a double-click brings the pet out -> out00 -> the next
##           round has both. Shots: equip_00..07 (equip_02/03 Cash tab, equip_04/05 Pet page).
##   account the whole NX and Cash Shop loop (#126): 11,000 NX prepared -> new character -> tier-1 map select SHOP (buy a hat
##           and a pet) -> round 1: Equip window Cash tab wears the hat, Pet page brings the pet out -> warp clear -> Free
##           Market "+N NX" notice and saved balance -> SHOP: buy Auto HP Potion Pouch -> Save & quit, Continue -> out00 ->
##           tier-2 map select (balance) -> round 2 -> warp death -> results (NX earned) -> the slot is freed and the account
##           keeps NX and every item -> a NEW character: shop shows everything owned, its round's Equip window wears the hat
##           and brings the pet (with the upgrade) out. Shots acct_*.png (+ *_zoom.png crops around character and pet).
##           --account-nx=<n> changes the prepared balance; --seed defaults to 4.
## Other flags: --shots=<abs dir> (required), --time-scale=<k> (default 3: the run plays k times faster, windows and
## effects too), --stop-at=<run s> (full: 300), --seed=<n> (full: 1, rounds: 4), --wz=<folder> (import).
##
## Screenshots are named NN_<step>.png; the driver prints one "flow_driver:" line per step and quits with exit code 1
## when a step times out or the full scenario misses the Magician / pause-resume path. Full also writes summary.json
## from RunScene's public snapshot, including the seed, potion totals, tier counts and missing assets.
## tier C: diagnostic names, seeds 1 (full) and 4 (rounds), 1800s combat cap, 600-tick yields, 100s progress logs,
## 30s/8px exit-walk guard and UI waits/timeouts are automation choices, never survivor tuning.

const CashShopScene := preload("res://scenes/ui/cash_shop.gd")
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
		"skill_weapon":
			_scenario_skill_weapon()
		"skill_warrior":
			_scenario_skill_warrior()
		"warrior":
			_scenario_warrior()
		"keys":
			_scenario_keys()
		"cash_shop":
			_scenario_cash_shop()
		"account":
			_scenario_account()
		"inventory":
			_scenario_inventory()
		"cash_equip":
			_scenario_cash_equip()
		"scrolls":
			_scenario_scrolls()
		"shops":
			_scenario_shops()
		"botshop":
			_scenario_botshop()
		"economy":
			_scenario_economy()
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


func _scenario_cash_shop() -> void:
	# tier C: the prepared save gives the account 5,000 NX: one 3,700 NX hat is affordable, a second item is not.
	flow.save.set_account({"nx": 5000, "owned": []})
	if not await _until(func() -> bool: return flow.current_name == "title", 20.0, "title"):
		return
	await _sleep(1.0)
	await _key(KEY_ENTER)
	if not await _create_character("Shop118"):
		return
	await _sleep(1.5)
	await _shot("shop_00_map_select_button")
	await _click(flow.current.get("shop_button") as Control)
	if not await _until(func() -> bool: return flow.current_name == "cash_shop", 5.0, "Cash Shop from map select"):
		return
	var shop: CashShopScene = flow.current
	await _sleep(0.5)
	_check(shop.snapshot.name == "Shop118" and shop.nx() == 5000, "the shop opened as the current character with its NX")
	await _shot("shop_01_equip_hat")
	# Try on the first hat: the preview wears it, nothing is bought.
	await _click_at(shop.stage.global_position + shop.card_rect(0).position + Vector2(30, 30))
	await _sleep(0.4)
	_check(shop.preview_cash.size() == 1 and shop.owned_ids().is_empty(), "clicking a card tried the hat on")
	await _shot("shop_01b_tried_on")
	await _hover(shop.stage.global_position + shop.card_rect(3).position + Vector2(100, 20))
	await _shot("shop_02_preview_tooltip")
	# Sub-tab Overall by mouse.
	var subs: Array = shop.sub_rects()
	await _click_at(shop.stage.global_position + subs[3].get_center())
	_check(shop.sub == "Overall", "the Overall sub-tab opened")
	await _shot("shop_03_overall")
	await _click_at(shop.stage.global_position + shop.sub_rects()[0].get_center())
	# BUY the first hat -> confirm dialog.
	var hat: int = shop.page_ids()[0]
	await _click(shop.buy_buttons[0])
	_check(shop.pending_id == hat and shop.nx() == 5000, "BUY opened the confirm dialog without spending")
	await _shot("shop_04_buy_dialog")
	await _click(shop.ok_button)
	_check(shop.nx() < 5000 and shop.owned_ids() == [hat] and not shop.listing_ids().has(hat), "OK bought it: NX down, owned, off the list")
	_reload_save()
	_check(flow.save.account.owned == [hat], "the purchase was saved at once")
	await _shot("shop_05_bought")
	# Too expensive now.
	await _click(shop.buy_buttons[1])
	_check(shop.notice_text == "You don't have enough NX.", "the not-enough-NX notice")
	await _shot("shop_06_not_enough_nx")
	await _key(KEY_ENTER)
	_check(shop.notice_text == "", "Enter closed the notice")
	# Pet tab: pet equipment is locked without a pet.
	await _click_at(shop.stage.global_position + shop.TAB_RECTS.pet.get_center())
	_check(shop.tab_key == "pet", "the Pet tab opened")
	await _shot("shop_07_pet")
	await _click_at(shop.stage.global_position + shop.sub_rects()[1].get_center())
	await _shot("shop_08_pet_equip_locked")
	_check(shop.lock_text(1812002) == "Needs a pet.", "pet upgrades say they need a pet")
	# EXIT -> map select; prepare the Free Market boundary, Save & quit, Continue.
	await _click(shop.exit_button)
	if not await _until(func() -> bool: return flow.current_name == "stage_select", 5.0, "EXIT back to map select"):
		return
	var boundary := flow.save.slot(flow.active_slot)
	boundary.phase = "free_market"
	boundary.tier = 1
	flow.save.update_slot(flow.active_slot, boundary)
	await _click(flow.current.back_button)
	if not await _until(func() -> bool: return flow.current_name == "character_select", 10.0, "character select"):
		return
	_reload_save()
	await _click(flow.current.slot_buttons[0])
	await _click(flow.current.select_button)
	if not await _until(func() -> bool: return flow.current_name == "free_market", 10.0, "Free Market"):
		return
	await _sleep(1.0)
	await _shot("shop_09_free_market_shop_button")
	await _click((flow.current as FreeMarket).shop_button)
	if not await _until(func() -> bool: return flow.current_name == "cash_shop", 5.0, "Cash Shop from the Free Market"):
		return
	shop = flow.current
	await _sleep(0.5)
	_check(shop.owned_ids().size() == 1, "the purchase is still owned when reopened")
	await _shot("shop_10_reopened_from_free_market")
	await _key(KEY_ESCAPE)
	_check(await _until(func() -> bool: return flow.current_name == "free_market", 5.0, "Esc back to the Free Market"),
		"Leave returned to the Free Market")
	await _shot("shop_11_back_in_free_market")
	_check(_missing.is_empty(), "no asset lookups failed: %s" % [_missing])
	_quit()


## The Equip window's Cash tab and Pet page (#122), continuing the #118 purchase: a prepared save with 12,000 NX -> new
## character -> map select SHOP -> buy the first hat (Equip tab) and the first pet (Pet tab) through the confirm dialog ->
## EXIT -> the saved boundary is turned into a Free Market one, Save & quit, Continue -> E, the Cash tab, a double-click
## wears the hat (saved at once) -> the PET EQUIP. button, a double-click on the owned pet brings it out -> Esc, walk to
## out00, Up -> tier-2 map select -> Start: the round's character wears the hat and has the pet out.
func _scenario_cash_equip() -> void:
	flow.save.set_account({"nx": 12000, "owned": []})
	if not await _until(func() -> bool: return flow.current_name == "title", 20.0, "title"):
		return
	await _sleep(1.0)
	await _key(KEY_ENTER)
	if not await _create_character("Dress122"):
		return
	await _sleep(1.5)
	await _click(flow.current.get("shop_button") as Control)
	if not await _until(func() -> bool: return flow.current_name == "cash_shop", 5.0, "Cash Shop from map select"):
		return
	var shop: CashShopScene = flow.current
	await _sleep(0.5)
	var hat: int = shop.page_ids()[0]
	await _click(shop.buy_buttons[0])
	await _click(shop.ok_button)
	_check(shop.owned_ids() == [hat], "bought the first hat")
	await _click_at(shop.stage.global_position + shop.TAB_RECTS.pet.get_center())
	var pet: int = shop.page_ids()[0]
	await _click(shop.buy_buttons[0])
	await _click(shop.ok_button)
	_check(shop.owned_ids() == [hat, pet] and shop.nx() >= 0, "bought the first pet: %s NX left" % shop.nx())
	await _shot("equip_00_bought")
	await _click(shop.exit_button)
	if not await _until(func() -> bool: return flow.current_name == "stage_select", 5.0, "EXIT back to map select"):
		return
	var boundary := flow.save.slot(flow.active_slot)
	boundary.phase = "free_market"
	boundary.tier = 1
	flow.save.update_slot(flow.active_slot, boundary)
	await _click(flow.current.back_button)
	if not await _until(func() -> bool: return flow.current_name == "character_select", 10.0, "character select"):
		return
	_reload_save()
	await _click(flow.current.slot_buttons[0])
	await _click(flow.current.select_button)
	if not await _until(func() -> bool: return flow.current_name == "free_market", 10.0, "Free Market"):
		return
	var hub := flow.current as FreeMarket
	await _sleep(1.5)
	await _key(KEY_E)
	await _sleep(0.4)
	var ew := hub.ui_windows.find_window("equip") as EquipWindow
	_check(ew != null, "E opened the Equip window in the Free Market")
	if ew == null:
		return
	await _shot("equip_01_equip_page")
	await _click_at(ew.get_global_rect().position + ew.tab_rect("cash").get_center())
	_check(ew.page == "cash" and ew.owned_items() == [hat], "the Cash tab lists the owned hat")
	await _shot("equip_02_cash_tab_owned")
	await _double_click_at(ew.get_global_rect().position + ew.panel_cell(0).get_center())
	await _sleep(0.4)
	_check(ew.world.worn_cash.size() == 1 and CharacterSnapshot.integers(
		flow.save.slot(flow.active_slot).character.get("cash", {})).values() == [hat],
		"the double-click wore the hat and the slot was saved")
	_check(hub.avatar.look.get("cash", {}).size() == 1, "the avatar wears it at once")
	await _hover(ew.get_global_rect().position + ew.cash_rect(ew.world.worn_cash.keys()[0]).get_center())
	await _shot("equip_03_cash_worn_tooltip")
	await _click(ew._bt_pet)
	_check(ew.page == "pet" and ew.owned_items() == [pet], "PET EQUIP. opens the Pet page listing the owned pet")
	await _shot("equip_04_pet_page")
	await _double_click_at(ew.get_global_rect().position + ew.panel_cell(0).get_center())
	await _sleep(0.6)
	_check(ew.world.pet == pet and hub.pet_renderer != null, "the double-click brought the pet out beside the character")
	_check(int(flow.save.slot(flow.active_slot).character.get("pet", 0)) == pet, "and the slot was saved")
	var catalog := CashCatalog.from_data(hub.inventory.data)
	var no_icon: Array[int] = []
	for c: Dictionary in ew.pet_cells():
		if String(c.payload.kind) == "pet_upgrade" and UiArt.frame(CashShop.icon_path(catalog, int(c.payload.id))) == null:
			no_icon.append(int(c.payload.id))
	_check(no_icon.is_empty(), "every pet upgrade cell has its icon: missing %s" % [no_icon])
	await _shot("equip_05_pet_out")
	await _key(KEY_ESCAPE)
	await _sleep(0.3)
	_check(not hub.windows_open(), "Esc closed the window")
	_collect_missing(hub)
	var exit_pos := Vector2.ZERO
	for portal: Dictionary in hub.motion.portals.links:
		if portal.name == "out00":
			exit_pos = portal.pos
	var t0 := Time.get_ticks_msec()
	while absf(hub.motion.player.pos.x - exit_pos.x) > 8.0:
		if Time.get_ticks_msec() - t0 > 30000:
			_fail("walking to out00 timed out")
			return
		_set_key("left", hub.motion.player.pos.x > exit_pos.x)
		_set_key("right", hub.motion.player.pos.x < exit_pos.x)
		await get_tree().process_frame
	_release_all()
	await _shot("equip_06_dressed_at_out00")
	await _key(KEY_UP)
	if not await _until(func() -> bool: return flow.current_name == "stage_select", 10.0, "tier-2 map select via out00"):
		return
	await _sleep(2.0)
	await _start_selected(flow.current)
	if not await _until(func() -> bool: return flow.current_name == "run", 10.0, "the next round"):
		return
	var run := flow.current as RunScene
	await _sleep(1.0)
	await _hold(KEY_RIGHT, 1.0)
	_check(run.world.worn_cash.size() == 1 and run.world.pet == pet, "the next round: the character wears the hat and has the pet out")
	_check(run.world.cash_fortune > 0.0 and run.world.player_state.fortune > 0.0, "the hat's Fortune applies")
	_check(run.pet_renderer != null and run.avatar.look.get("cash", {}).size() == 1, "and both are drawn")
	await _shot("equip_07_next_round")
	_collect_missing(run)
	_check(_missing.is_empty(), "no asset lookups failed: %s" % [_missing])
	print("flow_driver: cash_equip scenario %s (missing: %s)" % ["FAILED" if _failed else "passed", _missing])
	await _sleep(0.5)
	get_tree().quit(1 if _failed else 0)


## The whole NX and Cash Shop loop (spec #34, #126) with injected input only: a prepared save (11,000 NX) -> new character ->
## tier-1 map select SHOP: buy a hat and a pet -> round 1: E, Cash tab (wear the hat), Pet page (bring the pet out) -> a
## fixed-tick warp clears it -> Free Market: the "+N NX" notice and the saved balance, SHOP: buy Auto HP Potion Pouch ->
## Save & quit, Continue -> out00 -> tier-2 map select (balance shown) -> round -> a warp dies -> results (NX earned),
## the slot is freed, the account keeps NX and every item -> a NEW character: the shop lists everything as owned, the
## round's Equip window offers the hat and the pet with its upgrade, and wears/brings them out.
## Shots: acct_*.png; acct_*_zoom.png are 3x crops around the character and its pet. Uses --seed (default 4, a Henesys
## clear). Pass --account-nx=<n> to change the prepared balance.
func _scenario_account() -> void:
	if not args.has("seed"):
		args["seed"] = "4"
	var start_nx := int(args.get("account-nx", "11000"))
	flow.save.set_account({"nx": start_nx, "owned": []})
	if not await _until(func() -> bool: return flow.current_name == "title", 20.0, "title"):
		return
	await _sleep(1.0)
	await _key(KEY_ENTER)
	if not await _create_character("Acct126"):
		return
	await _sleep(1.5)
	await _shot("acct_00_map_select_balance")
	_check(flow.current.character_label.text.contains("11,000 NX"), "map select shows the NX balance: %s" % flow.current.character_label.text)
	# 1. Cash Shop from tier-1 map select: buy the first hat and the first pet.
	await _click(flow.current.get("shop_button") as Control)
	if not await _until(func() -> bool: return flow.current_name == "cash_shop", 5.0, "Cash Shop from map select"):
		return
	var shop: CashShopScene = flow.current
	await _sleep(0.5)
	var hat: int = shop.page_ids()[0]
	await _click(shop.buy_buttons[0])
	await _click(shop.ok_button)
	await _click_at(shop.stage.global_position + shop.TAB_RECTS.pet.get_center())
	var pet: int = shop.page_ids()[0]
	await _click(shop.buy_buttons[0])
	await _click(shop.ok_button)
	var spent := int(CashCatalog.from_data(shop._data).price_of(hat)) + int(CashCatalog.from_data(shop._data).price_of(pet))
	_check(shop.owned_ids() == [hat, pet] and shop.nx() == start_nx - spent, "bought hat %d and pet %d: %d NX left" % [hat, pet, shop.nx()])
	await _shot("acct_01_bought_hat_and_pet")
	await _click(shop.exit_button)
	if not await _until(func() -> bool: return flow.current_name == "stage_select", 5.0, "EXIT back to map select"):
		return
	_reload_save()
	_check(flow.save.account.owned == [hat, pet] and int(flow.save.account.nx) == start_nx - spent, "the purchases are in the save file")
	# 2. Round 1: wear the hat and bring the pet out through the Equip window.
	await _sleep(2.0)
	await _start_selected(flow.current)
	if not await _until(func() -> bool: return flow.current_name == "run", 10.0, "round 1"):
		return
	var run := flow.current as RunScene
	await _sleep(1.0)
	await _key(KEY_E)
	if not await _until(func() -> bool: return run.ui_windows.find_window("equip") != null, 3.0, "Equip window in round 1"):
		return
	var ew := run.ui_windows.find_window("equip") as EquipWindow
	await _click_at(ew.get_global_rect().position + ew.tab_rect("cash").get_center())
	_check(ew.page == "cash" and ew.owned_items() == [hat], "the Cash tab lists the bought hat")
	await _double_click_at(ew.get_global_rect().position + ew.panel_cell(0).get_center())
	await _sleep(0.3)
	_check(run.world.worn_cash.size() == 1, "round 1: the hat is worn")
	await _click(ew._bt_pet)
	_check(ew.page == "pet" and ew.owned_items() == [pet], "the Pet page lists the bought pet")
	await _double_click_at(ew.get_global_rect().position + ew.panel_cell(0).get_center())
	await _sleep(0.5)
	_check(run.world.pet == pet and run.pet_renderer != null, "round 1: the pet is out")
	await _shot("acct_02_round1_equip_window")
	await _key(KEY_ESCAPE)
	await _sleep(1.5)
	await _shot("acct_03_round1_dressed")
	await _shot_zoom("acct_03_round1_dressed_zoom", run.avatar, run.pet_renderer)
	var gap := (run.world.pet_state().pos as Vector2).distance_to(run.world.player.pos)
	_check(gap < 250.0, "the pet stays beside the character (%.0f px)" % gap)
	# 3. Clear (fixed-tick warp): the Free Market arrival shows "+N NX" and the balance is saved.
	# tier C: the bot with a hat and a pet no longer clears Henesys on the training seeds (it has 0/3 clears anyway), so
	# round 1 is invulnerable (round 2 exercises the real death path); --natural-clear=1 plays it as is.
	run.world.god = String(args.get("natural-clear", "0")) != "1"
	if not await _warp_round():
		return
	var nx_awarded := int(_rounds.back().get("nx_awarded", 0))
	if not await _until(func() -> bool: return flow.current_name == "free_market", 15.0, "Free Market after the clear"):
		return
	var hub := flow.current as FreeMarket
	await _sleep(0.8)
	nx_awarded = int(flow.last_summary.get("nx_awarded", nx_awarded))
	_check(nx_awarded > 0 and hub.notice == "You have gained %d NX." % nx_awarded, "the Free Market notice: '%s'" % hub.notice)
	var balance := start_nx - spent + nx_awarded
	_check(int(flow.save.account.nx) == balance, "the clear's %d NX is in the account (%d)" % [nx_awarded, int(flow.save.account.nx)])
	await _shot("acct_04_free_market_notice")
	await _shot_zoom("acct_04_free_market_zoom", hub.avatar, hub.pet_renderer)
	_check(hub.pet_renderer != null and hub.avatar.look.get("cash", {}).size() == 1, "the Free Market draws the hat and the pet")
	# 4. Buy a pet upgrade in the Free Market shop.
	await _click(hub.shop_button)
	if not await _until(func() -> bool: return flow.current_name == "cash_shop", 5.0, "Cash Shop from the Free Market"):
		return
	shop = flow.current
	await _sleep(0.5)
	await _click_at(shop.stage.global_position + shop.TAB_RECTS.pet.get_center())
	await _click_at(shop.stage.global_position + shop.sub_rects()[1].get_center())
	var upgrade: int = shop.page_ids()[0]
	await _shot("acct_05_upgrades_unlocked")
	await _click(shop.buy_buttons[0])
	await _click(shop.ok_button)
	var price := int(CashCatalog.from_data(shop._data).price_of(upgrade))
	_check(shop.owned_ids() == [hat, pet, upgrade] and shop.nx() == balance - price, "bought pet upgrade %d for %d NX" % [upgrade, price])
	balance -= price
	await _shot("acct_06_upgrade_bought")
	await _key(KEY_ESCAPE)
	if not await _until(func() -> bool: return flow.current_name == "free_market", 5.0, "back in the Free Market"):
		return
	# 5. Save & quit, Continue: the account and the dressed, accompanied character survive.
	await _sleep(1.0)
	await _key(KEY_ESCAPE)
	await _shot("acct_06b_free_market_pause")
	await _key(KEY_2)
	if not await _until(func() -> bool: return flow.current_name == "character_select", 10.0, "Save & quit"):
		return
	_reload_save()
	_check(flow.save.account.owned == [hat, pet, upgrade] and int(flow.save.account.nx) == balance, "the file holds the account after Save & quit")
	await _click(flow.current.slot_buttons[0])
	await _click(flow.current.select_button)
	if not await _until(func() -> bool: return flow.current_name == "free_market", 10.0, "Continue"):
		return
	hub = flow.current as FreeMarket
	await _sleep(1.5)
	_check(hub.pet_renderer != null and hub.avatar.look.get("cash", {}).size() == 1, "Continue: the hat is worn and the pet is out")
	await _shot("acct_07_continued_free_market")
	await _shot_zoom("acct_07_continued_zoom", hub.avatar, hub.pet_renderer)
	# 6. out00 -> tier-2 map select (balance) -> round 2 -> death.
	var exit_pos := Vector2.ZERO
	for portal: Dictionary in hub.motion.portals.links:
		if portal.name == "out00":
			exit_pos = portal.pos
	var t0 := Time.get_ticks_msec()
	while absf(hub.motion.player.pos.x - exit_pos.x) > 8.0:
		if Time.get_ticks_msec() - t0 > 30000:
			_fail("walking to out00 timed out")
			return
		_set_key("left", hub.motion.player.pos.x > exit_pos.x)
		_set_key("right", hub.motion.player.pos.x < exit_pos.x)
		await get_tree().process_frame
	_release_all()
	_collect_missing(hub)
	await _key(KEY_UP)
	if not await _until(func() -> bool: return flow.current_name == "stage_select", 10.0, "tier-2 map select"):
		return
	await _sleep(2.0)
	_check(flow.current.character_label.text.contains(SaveData._group(balance) + " NX"), "tier-2 map select shows %d NX: %s" % [balance, flow.current.character_label.text])
	await _shot("acct_08_tier2_map_select")
	await _start_selected(flow.current)
	if not await _until(func() -> bool: return flow.current_name == "run", 10.0, "round 2"):
		return
	run = flow.current as RunScene
	await _sleep(1.0)
	_check(run.world.worn_cash.size() == 1 and run.world.pet == pet and run.world.pet_has("auto_hp"),
		"round 2: the hat, the pet and its Auto HP upgrade carry over")
	await _shot("acct_09_round2_start")
	await _shot_zoom("acct_09_round2_zoom", run.avatar, run.pet_renderer)
	if not await _warp_round():
		return
	if not await _until(func() -> bool: return flow.current_name == "results", 15.0, "results after the death"):
		return
	await _sleep(1.0)
	var death_nx := int(flow.last_summary.get("nx_awarded", 0))
	_check(flow.last_summary.ending == "died" and death_nx >= 0, "round 2 ended in death (+%d NX)" % death_nx)
	await _shot("acct_10_results_nx")
	await _click(flow.current.back_button)
	if not await _until(func() -> bool: return flow.current_name == "character_select", 10.0, "character select after the death"):
		return
	_reload_save()
	_check(flow.save.slot(0).is_empty(), "the dead character freed its slot")
	_check(flow.save.account.owned == [hat, pet, upgrade] and int(flow.save.account.nx) == balance + death_nx,
		"the account kept every item and %d NX after the death (%d)" % [balance + death_nx, int(flow.save.account.nx)])
	balance += death_nx
	# 7. A NEW character uses the account's items.
	if not await _create_character("Heir126"):
		return
	await _sleep(1.5)
	await _click(flow.current.get("shop_button") as Control)
	if not await _until(func() -> bool: return flow.current_name == "cash_shop", 5.0, "Cash Shop for the new character"):
		return
	shop = flow.current
	await _sleep(0.5)
	_check(shop.snapshot.name == "Heir126" and shop.nx() == balance and shop.owned_ids() == [hat, pet, upgrade]
		and not shop.listing_ids().has(hat), "the new character's shop: same NX, everything owned and off the list")
	await _shot("acct_11_new_character_shop")
	await _click(shop.exit_button)
	if not await _until(func() -> bool: return flow.current_name == "stage_select", 5.0, "back to map select"):
		return
	await _sleep(2.0)
	await _start_selected(flow.current)
	if not await _until(func() -> bool: return flow.current_name == "run", 10.0, "the new character's round"):
		return
	run = flow.current as RunScene
	await _sleep(1.0)
	await _key(KEY_E)
	if not await _until(func() -> bool: return run.ui_windows.find_window("equip") != null, 3.0, "Equip window (new character)"):
		return
	ew = run.ui_windows.find_window("equip") as EquipWindow
	await _click_at(ew.get_global_rect().position + ew.tab_rect("cash").get_center())
	_check(ew.owned_items() == [hat], "the new character's Cash tab lists the account's hat")
	await _double_click_at(ew.get_global_rect().position + ew.panel_cell(0).get_center())
	await _click(ew._bt_pet)
	await _double_click_at(ew.get_global_rect().position + ew.panel_cell(0).get_center())
	await _sleep(0.5)
	_check(run.world.worn_cash.size() == 1 and run.world.pet == pet and run.world.pet_has("auto_hp")
		and run.world.cash_fortune > 0.0, "the new character wears the hat and brings the pet with its upgrade out")
	await _key(KEY_ESCAPE)
	await _sleep(1.5)
	await _shot("acct_12_new_character_dressed")
	await _shot_zoom("acct_12_new_character_zoom", run.avatar, run.pet_renderer)
	_collect_missing(run)
	_check(_missing.is_empty(), "no asset lookups failed: %s" % [_missing])
	print("flow_driver: account scenario %s (missing: %s)" % ["FAILED" if _failed else "passed", _missing])
	await _sleep(0.5)
	get_tree().quit(1 if _failed else 0)


## Saves a 3x enlarged crop of the last drawn frame around `around` (and `also`, e.g. the pet): the evidence that the pet
## and the worn items are visible beside the character.
func _shot_zoom(step: String, around: Node2D, also: Node2D = null) -> void:
	await _sleep(0.2)
	RenderingServer.force_draw()
	var img := get_viewport().get_texture().get_image()
	if img == null or around == null:
		_fail("no frame to crop for " + step)
		return
	var a: Vector2 = around.get_global_transform_with_canvas().origin
	var b: Vector2 = a if also == null else also.get_global_transform_with_canvas().origin
	print("flow_driver: zoom centre ", a, " ", b, " img ", img.get_size())
	var lo := Vector2(minf(a.x, b.x) - 110.0, minf(a.y, b.y) - 110.0).clamp(Vector2.ZERO, Vector2(img.get_width(), img.get_height()))
	var hi := Vector2(maxf(a.x, b.x) + 110.0, maxf(a.y, b.y) + 50.0).clamp(Vector2.ZERO, Vector2(img.get_width(), img.get_height()))
	var crop := img.get_region(Rect2i(Vector2i(lo), Vector2i(hi - lo)))
	crop.resize(crop.get_width() * 3, crop.get_height() * 3, Image.INTERPOLATE_NEAREST)
	_n += 1
	crop.save_png(shots_dir.path_join("%02d_%s.png" % [_n, step]))
	print("flow_driver: shot %02d_%s.png (zoom)" % [_n, step])


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


func _scenario_skill_warrior() -> void:
	if not await _enter_round("SkillWarrior"):
		return
	var run := flow.current as RunScene
	await _sleep(3.0)
	var w := run.world
	w.change_job(100)
	for id: String in ["power_strike_new", "slash_blast_new", "iron_body_new", "improved_hp_recovery_new",
			"improved_max_hp_new", "power_strike_targets"]:
		w.upgrades.apply(id, w)
	await _sleep(0.5)
	await _key(KEY_K)
	if not await _until(func() -> bool: return run.ui_windows.find_window("skill") != null, 3.0, "Skill window (K)"):
		return
	var sw := run.ui_windows.find_window("skill") as SkillWindow
	await _sleep(0.5)
	var rows := sw.rows()
	var blast := -1
	for i in rows.size():
		if String(rows[i].get("key", "")) == "slash_blast":
			blast = i
	_check(blast >= 0, "Slash Blast is listed on the Warrior tab")
	await _shot("skill_warrior_window")
	var origin := sw.get_global_rect().position
	for i in maxi(0, blast - SkillWindow.VISIBLE_ROWS + 1):
		await _wheel(origin + sw.row_rect(1).get_center(), true)
	_hover(origin + sw.row_rect(blast - sw.scroll).get_center())
	await _sleep(0.4)
	var tip := sw.tooltip()
	_check(String(tip.get("key", "")) == "slash_blast" and int(tip.get("hp_cost", 0)) == 8 and bool(tip.get("usable", false)),
		"the tooltip shows Slash Blast's HP cost and says the sword can use it")
	await _shot("skill_warrior_tooltip")
	# Debug setup: enough MP for Iron Body, which auto-casts as soon as Esc lets the sim run again.
	w._base_mp = 100.0
	w.refresh_player_stats()
	w.heal_fraction("mp", 1.0)
	await _key(KEY_ESCAPE)
	await _sleep(0.5)
	_check(w.buffs.has("iron_body"), "Iron Body was cast once the window closed")
	await _shot("skill_warrior_iron_body")
	print("flow_driver: skill_warrior scenario %s" % ("FAILED" if _failed else "passed"))
	await _sleep(0.5)
	get_tree().quit(1 if _failed else 0)


## The Warrior end to end (spec #151 QA #164): Lv10 through the real job window, play, wear a shield, Save & quit and
## Continue. The only debug setup is the spare shield in the slot and the hub boundary (no multi-minute warp).
func _scenario_warrior() -> void:
	const SHIELD := 1092003 # Character.wz Shield, reqJob 0, Lv 5: wearable by a Lv10 Warrior with no STR need
	if not await _until(func() -> bool: return flow.current_name == "title", 20.0, "title"):
		return
	await _sleep(2.0)
	await _key(KEY_ENTER)
	if not await _create_character("Warrior164"):
		return
	var slot := flow.save.slot(flow.active_slot)
	var character: Dictionary = slot.character
	var info: Dictionary = AssetLibrary.get_default().img(AvatarRenderer.part_img_path(SHIELD)).root.get("info", {})
	character.equipment.inventory.append(Equipment.create(SHIELD, info))
	slot.character = character
	_check(flow.save.update_slot(flow.active_slot, slot) == OK, "the spare shield was put in the new character's slot")
	await _sleep(1.0)
	await _start_selected(flow.current)
	if not await _until(func() -> bool: return flow.current_name == "run", 10.0, "run"):
		return
	var run := flow.current as RunScene
	await _sleep(2.0)
	var w := run.world
	var weapon0 := w.weapon_id()
	_check(weapon0 != 0 and w.progression.job_id == 0, "a Beginner holding weapon %d" % weapon0)
	# Lv10: EXP drops, the real level-up cards, then the real job window.
	var spawned_level := 0
	var spawned_at := -100.0
	var job_window_seen := false
	var advanced_shot := false
	for guard in 600:
		if w.state == RunWorld.DEAD:
			_fail("the character died on the way to Lv10")
			return
		if run.window is JobAdvanceWindow and (run.window as MapleWindow).is_open():
			await _sleep(0.6)
			var jw := run.window as JobAdvanceWindow
			var idx := -1
			for i in jw.entries.size():
				if jw.entries[i].kind == "job" and int(jw.entries[i].job_id) == 100 and jw.entries[i].available:
					idx = i
			_check(idx >= 0, "the job window offers the Warrior (entries %s)" % [jw.entries.map(
				func(e: Dictionary) -> String: return "%s%s" % [e.text, "" if e.available else " (" + String(e.reason) + ")"])])
			if idx < 0:
				return
			job_window_seen = true
			await _shot("warrior_job_window")
			await _key((KEY_1 + idx) as Key)
			await _sleep(0.4)
			await _shot("warrior_job_confirm")
			await _key(KEY_ENTER)
			await _sleep(0.9)
		elif run.window is LevelUpWindow and (run.window as MapleWindow).is_open():
			await _sleep(0.5)
			if is_instance_valid(run.window) and run.window is LevelUpWindow:
				var lw := run.window as LevelUpWindow
				var pick := _card_index(run, lw.cards)
				if job_window_seen and not advanced_shot:
					advanced_shot = true
					await _shot("warrior_advanced")
				await _key((KEY_1 + pick) as Key)
				await _sleep(0.4)
		elif job_window_seen and run.window == null and w.state == RunWorld.PLAYING:
			break
		elif w.state == RunWorld.PLAYING and run.window == null and w.progression.level < 10 \
				and (w.progression.level != spawned_level or w.time - spawned_at > 3.0):
			spawned_level = w.progression.level
			spawned_at = w.time
			w.pickups.spawn(w.player.pos, w.progression.exp_to_next(), 4000019)
		await _sleep(0.3)
	_check(job_window_seen and w.progression.job_id == 100, "the real job window made the character a Warrior (job %d)" % w.progression.job_id)
	_check(w.progression.level == 10, "at Lv 10 (%d)" % w.progression.level)
	var inventory_ids: Array = w.equipment.inventory.map(func(i: Dictionary) -> int: return int(i.id))
	_check(w.weapon_id() == 1302077, "the Beginner Warrior's sword is worn (%d)" % w.weapon_id())
	_check(weapon0 in inventory_ids and 1432000 in inventory_ids and 1322006 in inventory_ids,
		"the creation sword, the Spear and the Steel Pipe wait in the Equip tab (%s)" % [inventory_ids])
	weapon0 = w.weapon_id()
	_check(w.loadout.rank("power_strike") + w.loadout.rank("slash_blast") > 0, "the advancement draw gave a Warrior attack")
	# A few seconds of real play with the bot's steering.
	var kills0 := w.kills
	_steer = true
	await _until(func() -> bool: return w.kills > kills0, 25.0, "the Warrior kills something")
	await _sleep(2.0)
	_steer = false
	_release_all()
	await _shot("warrior_playing")
	var kills := w.kills - kills0
	_check(kills > 0, "the Warrior killed %d in this stretch" % kills)
	# Wear the shield: E and I, a double-click in the Item window's Equip tab.
	await _key(KEY_E)
	await _key(KEY_I)
	if not await _until(func() -> bool: return run.ui_windows.find_window("item") != null \
			and run.ui_windows.find_window("equip") != null, 3.0, "Equip and Item windows"):
		return
	var ew := run.ui_windows.find_window("equip") as EquipWindow
	var iw := run.ui_windows.find_window("item") as ItemWindow
	await _sleep(0.5)
	var cell := -1
	for i in iw.cells().size():
		if int(iw.cells()[i].id) == SHIELD:
			cell = i
	_check(cell >= 0 and ew.worn_id("shield") == 0, "the spare shield waits in the Equip tab (cell %d)" % cell)
	if cell < 0:
		return
	await _double_click_at(iw.get_global_rect().position + iw.slot_rect(cell).get_center())
	await _sleep(0.4)
	_check(ew.worn_id("shield") == SHIELD, "the shield is worn by double-click (%d)" % ew.worn_id("shield"))
	_check(ew.worn_id("weapon") == weapon0, "beside the sword")
	_hover(ew.get_global_rect().position + ew.slot_rect("shield").get_center())
	await _sleep(0.4)
	await _shot("warrior_shield_worn")
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	await _sleep(0.6)
	_check(not run.ui_windows.has_windows() and not run.paused, "Esc closed both windows")
	_collect_missing(run)
	# The round boundary (debug shortcut for the warp-clear): the carried snapshot is saved at the Free Market.
	var carried := run.world.character_snapshot()
	slot = flow.save.slot(flow.active_slot)
	slot.character = carried
	slot.phase = "free_market"
	_check(flow.save.update_slot(flow.active_slot, slot) == OK, "the Warrior was saved at the Free Market boundary")
	var active := flow.active_slot
	flow.continue_character(active)
	if not await _until(func() -> bool: return flow.current_name == "free_market", 10.0, "Free Market"):
		return
	var hub := flow.current as FreeMarket
	await _sleep(1.5)
	var expected: Dictionary = JSON.parse_string(JSON.stringify(hub.inventory.character_snapshot()))
	_check(int(expected.job_id) == 100 and int(expected.equipment.worn.shield.id) == SHIELD \
		and int(expected.equipment.worn.weapon.id) == weapon0, "the hub holds the Warrior, shield and weapon")
	await _shot("warrior_hub")
	_collect_missing(hub)
	# Save & quit from the hub's pause menu, then Continue.
	await _key(KEY_ESCAPE)
	await _sleep(0.6)
	await _shot("warrior_save_and_quit")
	await _key(KEY_2)
	if not await _until(func() -> bool: return flow.current_name == "character_select", 10.0, "saved hub"):
		return
	_reload_save()
	await _sleep(1.0)
	await _shot("warrior_character_select")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(flow.save.slot(active).character))
	for key: String in ["job_id", "level", "equipment", "skills", "mesos"]:
		_check(saved.get(key) == expected.get(key), "the saved %s equal the hub's (%s)" % [key, str(saved.get(key)).left(60)])
	await _click(flow.current.slot_buttons[active])
	await _click(flow.current.select_button)
	if not await _until(func() -> bool: return flow.current_name == "free_market", 10.0, "continued hub"):
		return
	var again := flow.current as FreeMarket
	await _sleep(1.5)
	var restored: Dictionary = JSON.parse_string(JSON.stringify(again.inventory.character_snapshot()))
	for key: String in ["job_id", "level", "equipment", "skills", "mesos"]:
		_check(restored.get(key) == expected.get(key), "Continue restored the %s" % key)
	_check(again.inventory.held_weapon_family() == WeaponInfo.family(weapon0), "and the held weapon family")
	await _key(KEY_E)
	await _sleep(0.5)
	var aew := again.ui_windows.find_window("equip") as EquipWindow
	_check(aew != null and aew.worn_id("shield") == SHIELD and aew.worn_id("weapon") == weapon0,
		"the Equip window shows the restored shield and weapon")
	await _shot("warrior_continue_restored")
	_collect_missing(again)
	_check(_missing.is_empty(), "missing assets: %s" % [_missing])
	var report := {"scenario": "warrior", "job_id": int(restored.job_id), "level": int(restored.level), "weapon": weapon0,
		"shield": SHIELD, "kills": kills, "missing": Array(_missing), "failed": _failed}
	var file := FileAccess.open(shots_dir.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("flow_driver: warrior scenario %s (missing: %s)" % ["FAILED" if _failed else "passed", _missing])
	await _sleep(0.5)
	get_tree().quit(1 if _failed else 0)


func _scenario_skill_weapon() -> void:
	if not await _enter_round("SkillGate"):
		return
	var run := flow.current as RunScene
	await _sleep(3.0)
	var w := run.world
	w.change_job(200)
	for id: String in ["energy_bolt_new", "magic_claw_new"]:
		w.upgrades.apply(id, w)
	w.book.defs.magic_claw["weapon_families"] = ["claw"]
	await _sleep(0.5)
	_check(not w.book.usable_with("magic_claw", w.held_weapon_family()),
		"the held '%s' cannot use the claw-only Magic Claw" % [w.held_weapon_family()])
	await _key(KEY_K)
	if not await _until(func() -> bool: return run.ui_windows.find_window("skill") != null, 3.0, "Skill window (K)"):
		return
	var sw := run.ui_windows.find_window("skill") as SkillWindow
	await _sleep(0.5)
	await _shot("skill_weapon_greyed")
	var origin := sw.get_global_rect().position
	var claw := -1
	for i in sw.rows().size():
		if String(sw.rows()[i].get("key", "")) == "magic_claw":
			claw = i
	_check(claw >= 0, "Magic Claw is listed")
	for i in maxi(0, claw - SkillWindow.VISIBLE_ROWS + 1):
		await _wheel(origin + sw.row_rect(1).get_center(), true)
	_hover(origin + sw.row_rect(claw - sw.scroll).get_center())
	await _sleep(0.4)
	var tip := sw.tooltip()
	_check(String(tip.get("key", "")) == "magic_claw" and String(tip.get("needs", "")) == "Claw" \
		and not bool(tip.get("usable", true)), "the tooltip names the Claw and says it is not usable (%s)" % [tip.get("needs", "")])
	await _shot("skill_weapon_tooltip")
	await _key(KEY_ESCAPE)
	print("flow_driver: skill_weapon scenario %s" % ("FAILED" if _failed else "passed"))
	await _sleep(0.5)
	get_tree().quit(1 if _failed else 0)


func _scenario_keys() -> void:
	_backup_settings()
	var settings := get_node_or_null("/root/Settings") as GameSettings
	if settings == null:
		_fail("no Settings autoload")
		return
	# The scenario assumes the project's default keys (jump on C, ...): start from a throwaway settings file instead of
	# the developer's own bindings (the test runner does the same, #103). The real file is put back on quit.
	var scratch := "user://flow_driver_keys_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
	settings.reload_from(scratch)
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


## The whole mesos / equipment / scrolls / shops loop of spec #33 (#113) with injected input. tier C: the drops the
## character picks up are placed by the driver (a real kill drop is random), the round to the Free Market is the bot's
## fixed-tick warp (`_warp_round`), and the hub is topped up to 150,000 mesos if the round earned less (printed).
func _scenario_economy() -> void:
	# tier C: training seed 1 (the fixture is a seed-1 Henesys clear); --seed overrides it.
	if not args.has("seed"):
		args["seed"] = "1"
	if not await _until(func() -> bool: return flow.current_name == "title", 20.0, "title"):
		return
	await _sleep(2.0)
	await _key(KEY_ENTER)
	if not await _create_character("Loop113"):
		return
	var fixture: Variant = DataRepo.load_json("res://tests/fixtures/characters/lv35_magician_2nd.json")
	if not fixture is Dictionary or CharacterSnapshot.validation_error(fixture) != "":
		_fail("the Lv38 F/P fixture did not load")
		return
	var lib := AssetLibrary.get_default()
	var slot := flow.save.slot(flow.active_slot)
	var character: Dictionary = fixture
	character.erase("_doc")
	slot.character = character
	_check(flow.save.update_slot(flow.active_slot, slot) == OK, "the Lv38 F/P fixture was saved into the slot")
	await _sleep(1.0)
	await _start_selected(flow.current)
	if not await _until(func() -> bool: return flow.current_name == "run", 10.0, "run"):
		return
	var run := flow.current as RunScene
	var w := run.world
	await _sleep(2.0)
	# 1. Drops on the ground, then picked up by walking: four meso sprites and two items.
	var mesos0 := w.mesos
	var rng := RandomNumberGenerator.new()
	rng.seed = 113
	var origin := w.player.pos
	var ground_x := origin.x - 430.0 # open ground left of the hut below the spawn platform (as the drop driver)
	var ground_y := w.fhm.y_at(w.fhm.find_below(ground_x, origin.y), ground_x)
	w.player.place(Vector2(ground_x, ground_y), w.fhm)
	w.update_view()
	var meso_total := 0
	for i in 4:
		var amount: int = [30, 75, 400, 2500][i] # bronze, gold, bundle, bag
		meso_total += amount
		w.spawn_meso(Vector2(ground_x + 130.0 + 32.0 * i, ground_y - 30.0), amount)
	var drop_ids := [1002001, 1050049] # Metal Gear (wearable) and a Dark Calas (not: kept to be sold)
	for i in drop_ids.size():
		var id: int = drop_ids[i]
		var img := lib.img(AvatarRenderer.part_img_path(id))
		w.spawn_equipment(Vector2(ground_x + 260.0 + 36.0 * i, ground_y - 30.0),
			Equipment.create_drop(id, img.root.get("info", {}) if img != null else {}, rng))
	await _sleep(1.2)
	await _shot("economy_drops_on_the_ground")
	var inventory0: int = w.equipment.inventory.size()
	var t0 := Time.get_ticks_msec()
	while w.equips_collected < 2 or w.mesos < mesos0 + meso_total:
		if Time.get_ticks_msec() - t0 > 40000:
			_release_all()
			_fail("the character did not pick up the drops (equips %d, mesos %d / %d)" % [w.equips_collected, w.mesos,
				mesos0 + meso_total])
			return
		_set_key("right", true)
		if w.equips_collected >= 1 and not _memo.has("notice_shot"):
			_memo["notice_shot"] = true
			await _shot("economy_pickup_notices")
		await get_tree().process_frame
	_release_all()
	_check(w.equipment.inventory.size() == inventory0 + 2, "both items went into the Equip tab")
	await _sleep(0.6)
	await _shot("economy_picked_up")
	# 2. The Item window: tooltip of the drop, wear it by double-click; the Calas is refused (red requirements).
	await _key(KEY_E)
	await _key(KEY_I)
	if not await _until(func() -> bool: return run.ui_windows.find_window("item") != null, 3.0, "Item window (I)"):
		return
	var ew := run.ui_windows.find_window("equip") as EquipWindow
	var iw := run.ui_windows.find_window("item") as ItemWindow
	var io := iw.get_global_rect().position
	var eo := ew.get_global_rect().position
	_check(iw.meso_text() == InventoryModel.meso_text(w.mesos), "the Item window shows the carried mesos (%s)" % iw.meso_text())
	var hat := -1
	var calas := -1
	for i in iw.cells().size():
		match int(iw.cells()[i].id):
			1002001:
				hat = i
			1050049:
				calas = i
	_check(hat >= 0 and calas >= 0, "the drops are in the Item window's Equip tab")
	_hover(io + iw.slot_rect(hat).get_center())
	await _sleep(0.4)
	_check(bool(iw.tooltip().get("can_equip", false)), "the hat's tooltip is wearable")
	await _shot("economy_item_window_tooltip")
	_hover(io + iw.slot_rect(calas).get_center())
	await _sleep(0.4)
	_check(not bool(iw.tooltip().get("can_equip", true)), "the Calas's tooltip shows unmet requirements")
	await _shot("economy_tooltip_unmet")
	await _double_click_at(io + iw.slot_rect(hat).get_center())
	await _sleep(0.4)
	_check(ew.worn_id("hat") == 1002001, "Metal Gear was worn by double-click")
	_hover(eo + ew.slot_rect("hat").get_center())
	await _sleep(0.4)
	await _shot("economy_equip_window_hat_worn")
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	await _sleep(0.5)
	_check(not run.ui_windows.has_windows(), "Esc closed both windows")
	var mesos_round := w.mesos
	# 3. Clear the round (the bot's fixed-tick warp) and arrive in the Free Market with everything carried.
	if not await _warp_round():
		return
	if not _expect(w.state == RunWorld.CLEARED, "the round was not cleared (%s)" % w.state_name()):
		return
	if not await _until(func() -> bool: return flow.current_name == "free_market", 15.0, "Free Market after the clear"):
		return
	var boundary: Dictionary = flow.save.slot(flow.active_slot).character
	_check(boundary.equipment.worn.has("hat") and int(boundary.equipment.worn.hat.id) == 1002001, "the hat is worn at the boundary")
	_check(boundary.equipment.inventory.any(func(i: Dictionary) -> bool: return int(i.id) == 1050049),
		"the Calas is in the boundary inventory")
	_check(int(boundary.mesos) >= mesos_round, "mesos carried to the hub (%d, was %d at the pickups)" % [int(boundary.mesos), mesos_round])
	var hub := flow.current as FreeMarket
	await _sleep(1.5)
	# The player's own settings.cfg may have given Space to another action: put NPC Chat on its project default in
	# the InputMap only, so the evidence run does not depend on the developer's keys.
	InputMap.action_erase_events("npc_chat")
	for code in GameSettings.default_keys("npc_chat"):
		var ev := InputEventKey.new()
		ev.physical_keycode = code as Key
		InputMap.action_add_event("npc_chat", ev)
	if hub.inventory.mesos < 150000:
		print("flow_driver: the round earned %d mesos; the hub is topped up to 150,000 for the shopping" % hub.inventory.mesos)
		hub.inventory.mesos = 150000
	# 4. Walk to the NPCs (the four are shown on the way), Space opens El Moth's shop.
	if not await _walk_hub_to(hub, -100.0):
		return
	await _sleep(0.6)
	_check(hub.shop_npcs.map(func(n: Dictionary) -> int: return int(n.id)) == [1032103, 2022002, 1052104, 2041016],
		"the four scroll NPCs stand in the Free Market")
	await _shot("economy_scroll_npcs")
	if not await _walk_hub_to(hub, -350.0):
		return
	await _key(KEY_SPACE)
	await _sleep(0.6)
	var shop := hub.ui_windows.find_window("shop") as ShopWindow
	if shop == null or shop.npc_id != 1032103:
		_fail("Space next to El Moth did not open his shop")
		return
	await _shot("economy_shop_open")
	# 5. Buy a 100% hat INT scroll, sell the spare Calas.
	var mesos_hub := hub.inventory.mesos
	if not await _buy_at_shop(hub, shop, 2040024, 1, "economy_shop_buying"):
		return
	_check(int(hub.inventory.scrolls.get("2040024", 0)) == 1 and hub.inventory.mesos == mesos_hub - 35000,
		"one 100%% hat scroll bought for 35,000 (mesos %d)" % hub.inventory.mesos)
	_check(int(flow.save.slot(flow.active_slot).character.mesos) == hub.inventory.mesos, "the purchase was saved at once")
	var origin_shop := shop.get_global_rect().position
	await _click_at(origin_shop + shop.tab_rect(0).get_center())
	await _sleep(0.3)
	var sell_index := -1
	for i in shop.sell_cells().size():
		if int(shop.sell_cells()[i].id) == 1050049:
			sell_index = i
	_check(sell_index >= 0, "the Calas is listed in the shop's sell panel")
	shop.scroll_panel(1, -999)
	shop.scroll_panel(1, maxi(0, sell_index - ShopWindow.ROWS + 1))
	await _click_at(origin_shop + shop.row_rect(1, sell_index - shop.sell_offset).get_center())
	await _sleep(0.3)
	var price := shop.row_price(shop.selected_sale())
	var before_sale := hub.inventory.mesos
	await _shot("economy_shop_sell_selected")
	await _click(shop._bt_sell)
	await _sleep(0.4)
	_check(hub.ui_windows.find_window("drop_confirm") != null, "selling equipment asks first")
	await _shot("economy_shop_selling")
	await _key(KEY_ENTER)
	await _sleep(0.5)
	_check(price > 0 and hub.inventory.mesos == before_sale + price, "the Calas sold for %d" % price)
	_check(not hub.inventory.equipment.inventory.any(func(i: Dictionary) -> bool: return int(i.id) == 1050049), "and left the inventory")
	await _shot("economy_shop_sold")
	await _key(KEY_ESCAPE)
	await _sleep(0.4)
	# Tulcus: three 10% hat INT scrolls (a failure is the point of those).
	if not await _walk_hub_to(hub, -165.0):
		return
	await _key(KEY_SPACE)
	await _sleep(0.6)
	var tulcus := hub.ui_windows.find_window("shop") as ShopWindow
	if tulcus == null or tulcus.npc_id != 1052104:
		_fail("Space next to Tulcus did not open his shop")
		return
	if not await _buy_at_shop(hub, tulcus, 2040026, 3, "economy_shop_tulcus"):
		return
	_check(int(hub.inventory.scrolls.get("2040026", 0)) == 3, "three 10% hat scrolls bought")
	await _key(KEY_ESCAPE)
	await _sleep(0.4)
	# 6. Read them on the worn hat from the Equip window: a success (100%), then 10% scrolls until one fails.
	await _key(KEY_E)
	await _key(KEY_I)
	await _sleep(0.4)
	var hew := hub.ui_windows.find_window("equip") as EquipWindow
	var hiw := hub.ui_windows.find_window("item") as ItemWindow
	if hew == null or hiw == null:
		_fail("the hub's Equip and Item windows did not open")
		return
	var hio := hiw.get_global_rect().position
	var heo := hew.get_global_rect().position
	await _click_at(hio + hiw.tab_rect(1).get_center())
	await _sleep(0.3)
	var worn_hat: Dictionary = hub.inventory.equipment.worn.hat
	var slots0 := int(worn_hat.slots)
	var use_ids := hiw.cells().map(func(c: Dictionary) -> int: return int(c.id))
	_check(2040024 in use_ids and 2040026 in use_ids, "the Use tab holds the two new scroll stacks (%s)" % [use_ids])
	await _drag(hio + hiw.slot_rect(use_ids.find(2040024)).get_center(), heo + hew.slot_rect("hat").get_center())
	worn_hat = hub.inventory.equipment.worn.hat
	_check(int(worn_hat.scrolls) == 1 and int(worn_hat.slots) == slots0 - 1, "the 100% scroll succeeded: +1, one slot spent")
	_check(hub.enchant.renderer.active_count() == 1, "the Enchant effect plays over the character")
	await _shot("economy_scroll_success")
	_hover(heo + hew.slot_rect("hat").get_center())
	await _sleep(0.5)
	await _shot("economy_scrolled_tooltip")
	var failed := false
	for attempt in 3:
		var before_count := int(hub.inventory.equipment.worn.hat.scrolls)
		var cells := hiw.cells().map(func(c: Dictionary) -> int: return int(c.id))
		await _drag(hio + hiw.slot_rect(cells.find(2040026)).get_center(), heo + hew.slot_rect("hat").get_center())
		var plain_failed: bool = int(hub.inventory.equipment.worn.hat.scrolls) == before_count
		print("flow_driver: 10%% hat scroll %d: %s" % [attempt + 1, "failure" if plain_failed else "success"])
		if plain_failed:
			failed = true
			await _shot("economy_scroll_failure")
			break
		await _sleep(1.2)
	_check(failed, "a 10 percent scroll failed within three tries")
	await _sleep(1.5)
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	await _sleep(0.5)
	await _shot("economy_character_scrolled")
	# 7. Save & quit, then Continue: mesos, worn equipment, inventory and scrolls come back from the saved snapshot.
	var active := flow.active_slot
	var expected: Dictionary = JSON.parse_string(JSON.stringify(hub.inventory.character_snapshot()))
	_collect_missing(hub)
	await _key(KEY_ESCAPE)
	await _sleep(0.6) # the pause menu ignores input while it opens
	await _shot("economy_save_and_quit")
	await _key(KEY_2)
	if not await _until(func() -> bool: return flow.current_name == "character_select", 10.0, "saved hub"):
		return
	_reload_save()
	await _sleep(1.0)
	await _shot("economy_character_select")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(flow.save.slot(active).character))
	for key: String in ["mesos", "equipment", "scrolls"]:
		_check(saved.get(key) == expected.get(key), "the saved %s equal the hub's (%s)" % [key, str(saved.get(key)).left(80)])
	await _click(flow.current.slot_buttons[active])
	await _click(flow.current.select_button)
	if not await _until(func() -> bool: return flow.current_name == "free_market", 10.0, "continued hub"):
		return
	var again := flow.current as FreeMarket
	await _sleep(1.5)
	var restored: Dictionary = JSON.parse_string(JSON.stringify(again.inventory.character_snapshot()))
	for key: String in ["mesos", "equipment", "scrolls"]:
		_check(restored.get(key) == expected.get(key), "Continue restored the %s" % key)
	await _key(KEY_E)
	await _key(KEY_I)
	await _sleep(0.5)
	var aew := again.ui_windows.find_window("equip") as EquipWindow
	var aiw := again.ui_windows.find_window("item") as ItemWindow
	_check(aew != null and aew.worn_id("hat") == 1002001, "the Equip window shows the restored hat")
	_check(aiw != null and aiw.meso_text() == InventoryModel.meso_text(int(expected.mesos)),
		"the Item window shows the restored mesos (%s)" % [aiw.meso_text() if aiw != null else ""])
	await _shot("economy_continue_restored")
	_collect_missing(again)
	_check(_missing.is_empty(), "missing assets: %s" % [_missing])
	var report := {"scenario": "economy", "mesos_picked_up": meso_total, "mesos_at_clear": int(boundary.mesos),
		"hat_scrolls": int(expected.equipment.worn.hat.scrolls), "mesos_final": int(expected.mesos),
		"missing": Array(_missing), "failed": _failed}
	var file := FileAccess.open(shots_dir.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("flow_driver: economy scenario %s (missing: %s)" % ["FAILED" if _failed else "passed", _missing])
	await _sleep(0.5)
	get_tree().quit(1 if _failed else 0)


## Holds the arrow keys until the hub's player stands within 8 px of `x`; false (and a failure) after 40 s.
func _walk_hub_to(hub: FreeMarket, x: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while absf(hub.motion.player.pos.x - x) > 8.0:
		if Time.get_ticks_msec() - t0 > 40000:
			_release_all()
			_fail("walking to x %.0f in the Free Market timed out (at %.0f)" % [x, hub.motion.player.pos.x])
			return false
		_set_key("left", hub.motion.player.pos.x > x)
		_set_key("right", hub.motion.player.pos.x < x)
		await get_tree().process_frame
	_release_all()
	await _sleep(0.2)
	return true


## In an open shop: selects scroll `id` in the stock by mouse, clicks Buy, types `count` and confirms. Saves a shot of
## the selected row with its tooltip as `shot`. False (and a failure) when the scroll is not in the stock.
func _buy_at_shop(hub: FreeMarket, shop: ShopWindow, id: int, count: int, shot: String) -> bool:
	var index := shop.stock.map(func(e: Dictionary) -> int: return int(e.id)).find(id)
	if index < 0:
		_fail("scroll %d is not in %s's stock" % [id, shop.npc_name])
		return false
	var origin := shop.get_global_rect().position
	shop.scroll_panel(0, -999)
	shop.scroll_panel(0, maxi(0, index - ShopWindow.ROWS + 1))
	var row := index - shop.buy_offset
	await _click_at(origin + shop.row_rect(0, row).get_center())
	await _sleep(0.3)
	_check(shop.buy_selected == index, "a click selected scroll %d (selected %d)" % [id, shop.buy_selected])
	_hover(origin + shop.row_rect(0, row).get_center() + Vector2(60, 0))
	await _sleep(0.5)
	await _shot(shot)
	await _click(shop._bt_buy)
	await _sleep(0.4)
	if hub.ui_windows.find_window("shop_quantity") == null:
		_fail("Buy did not ask how many")
		return false
	await _key([KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5][clampi(count, 0, 5)])
	await _sleep(0.3)
	await _key(KEY_ENTER)
	await _sleep(0.5)
	return true


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
