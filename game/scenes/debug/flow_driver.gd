extends Node
## Plays the real game (main.tscn under this node: the Flow autoload, every screen and the RunScene) by injecting
## keyboard and mouse events through Input.parse_input_event, exactly like a player, and saves a screenshot of every
## step. A smoke test of the whole flow and the evidence for docs/IMPLEMENTATION_PLAN.md acceptance checks.
##
##   bash scripts/godot.sh --path game res://scenes/debug/flow_driver.tscn -- --scenario=full --shots=C:/abs/dir
##
## Scenarios (--scenario=):
##   redesign the F/P slice end to end (#294): title -> create an Arch Mage (name, look, Job page) -> Free Market -> map select
##           (only Henesys open: Ellinia locked, Start refused) -> an invulnerable diagnostic Henesys round (fixed-tick bot warp, lethal boss
##           hits after each map timer, the real CLEAR/fade/arrival presentation; the first level-up, the first full-slots
##           offer, the first Mastery offer and the boss bonus draw open the real window and are answered with a number key)
##           -> results -> Free Market (Ellinia unlocked, loot kept) -> the highest-reqLevel drop worn at Lv1 by a double-click
##           -> Ellinia round (loot picked up, a lethal diagnostic hit) -> results -> Free Market (loot, worn item and the
##           unlock kept) -> Save & quit -> delete the character -> history. Shots redesign_*.png; summary.json holds the
##           offers (kinds, rarities, picks), the showcased windows and the history. `--seed` (default 1).
##   progression the region progression (spec #447, ADR 0007, #455): title -> create a character (`--job=<id>`, default 212) -> map select
##           (only Henesys startable, a locked Ellinia refused, Henesys the frontier and selected) -> a diagnostic invulnerable
##           Henesys clear (fixed-tick bot warp, lethal boss hits after each map timer) -> results -> Free Market -> map select
##           (Henesys CLEAR, Ellinia NEW and selected by default) -> the same for Ellinia (Perion unlocked) -> Save & quit, character
##           select, Continue: the cleared set survives on disk and on map select -> a Perion round and a lethal hit: the set is
##           unchanged -> the slot swapped for a HubTestKit all-cleared character: map select reads "Regions cleared 5/5" with
##           nothing locked. Shots progression_*.png, summary.json. `--seed` (default 1). tier C: automation, not survival evidence.
##   creation the Job page and character creation (spec #296, H9): title -> create a character of each job in `--jobs=<id,id>` (at most three)
##           (default: every playable job, in separate slots, then the Job page is checked to list them in order and to show the
##           chosen row) -> Free Market each time -> character select with all character slots. Shots creation_*.png, job_<id>_*.png.
##   title   the title screen only: waits for it, saves the shot, quits (e.g. to check an exported build:
##           MapleSurvivors.exe res://scenes/debug/flow_driver.tscn -- --scenario=title --shots=<dir>).
##   clear   --run tool one-off (`--run=<stage> --seed=<n> --autoplay --autopick --speed=<k>`): waits for the clear -> results ->
##           character select -> title -> quit; never saves (the save file is checked unchanged).
##   import  a cache-less start, or the title's Re-import link when a cache exists: the import screen,
##           types --wz=<folder> into the path field, clicks Import, waits for the importer and the title.
##           Without --wz this checks the screen only and never writes the cache.
##   windows the in-run window system (#85): title -> new character -> Free Market -> map select -> run; S opens the Stat window
##           (the sim is checked to hold), its title bar is dragged with the mouse, Esc closes it (the sim runs again); an
##           EXP drop levels the player up, S opens Stat over the level-up choice, Esc returns to the choice, 1 picks;
##           the status bar's Menu button opens the Menu popup, its Stat entry is clicked, Esc closes Stat; Esc pauses,
##           Esc resumes, quit. Shots: stat_window, stat_dragged, stat_over_levelup, menu_popup, menu_stat.
##   skill   the Skill window (#86): a round with a small build set up directly (Magic Claw, Fire Arrow, Explosion with ranks and
##           two common passives); K opens it on the job's own tab (the sim is checked to hold), Down selects the last row,
##           Left switches to the previous job tab, a click picks the Common tab (nine passives) and its tooltip, the tab
##           strip ends after the job's tab, 2 switches tabs, Esc closes; then K over a level-up choice (1 switches the tab
##           instead of picking), Esc back to the choice, 1 picks. Shots: skill_window, skill_common_tab, skill_over_levelup.
##   keys    Key Config and Options (#87): new character -> map select -> run (no bot); Esc pauses, 2 opens Key Config over the
##           pause menu, the jump icon is dragged from C onto F, OK; Esc resumes; C no longer jumps, F does; Menu -> Options,
##           WASD is clicked; the right arrow no longer moves the player, D does; Options -> Arrows, Key Config -> Default
##           -> OK. user://settings.cfg (the player's real one) is backed up first and restored before the driver quits, also
##           on failure. Shots: key_config, key_config_rebound, options, options_wasd.
##   inventory the Equip and Item windows (#108): the slot's character becomes the F/P fixture (tests/fixtures/characters/
##           fp_arch_mage.json) holding Metal Gear, a Blue Sauna Robe, Work Gloves and a Warrior shield it cannot wear (job
##           only: no level or stat rows), with 123,456 mesos -> Free Market -> map select -> run; E opens Equip, I opens Item
##           (the sim holds), the robe's tooltip, the shield's tooltip and the refused double-click, the hat worn by
##           double-click, the robe by dragging it onto the Equip window, the gloves by double-click, the shield dragged out
##           and the YesNo box answered No, the Use tab, Esc closes both; then the slot is moved to the Free Market and
##           Continue opens the hub: E and I there, the hat taken off and put back, Save & quit shows the dressed character.
##   scrolls scrolls on worn equipment (#110): the F/P fixture holds staff scrolls and hat scrolls -> run; E and I, the Use tab;
##           a 100% scroll is dragged from the Use tab onto the weapon (Enchant Success plays, the stats and counts follow),
##           then 10% scrolls until one fails (only the slot is spent), then dark scrolls until the weapon is destroyed (the
##           character is bare-handed and still casts); the slot moves to the Free Market and Continue opens the hub: a hat
##           scroll is dragged onto the hat there (effect, saved slot).
##   shops   the Free Market scroll shops (#111): the F/P fixture with 250,000 mesos, a few scrolls and spare equipment is put in
##           the hub; the four scroll NPCs are shown; Space next to El Moth opens his shop; a scroll is selected and bought
##           (quantity box, mesos charged), a refused purchase shows the notice; the Use tab sells a scroll stack, the Equip tab a
##           spare item (YesNo box); Esc closes; a double-click on Barun opens his shop; NPC Chat is rebound in Key Config's draft.
##   botshop the bot shop plan (#112) in the Free Market: the same fixture with 600,000 mesos and spare equipment; the hub's bot
##           hook (FreeMarket.bot_shop, BotShop.visit) sells, buys and reads scrolls through RunWorld and saves; the Item and
##           Equip windows show the result.
##   cash_shop  the Cash Shop (#118) from a prepared test save (5,000 NX): title -> new character -> map select SHOP -> Equip tab
##           (try-on, sub-tab, buy dialog, OK, a purchase that costs too much, Pet tab with locked upgrades) -> EXIT -> back to
##           the Free Market, Save & quit, Continue -> status bar SHOP -> EXIT back to the Free Market. Shots: shop_*.png.
##   cash_equip  the Equip window's Cash tab and Pet page (#122): 12,000 NX -> new character -> map select SHOP -> buy the first
##           hat and the first pet -> Free Market (Save & quit, Continue) -> E, Cash tab, a double-click wears the hat -> PET
##           EQUIP., a double-click brings the pet out -> out00 -> the next round has both. Shots: equip_00..07.
##   account the whole NX and Cash Shop loop (#126): 11,000 NX prepared -> new character -> map select SHOP (buy a hat and a pet)
##           -> round 1: Equip window Cash tab wears the hat, Pet page brings the pet out -> warp clear -> results -> Free Market
##           "+N NX" notice and saved balance -> SHOP: buy Auto HP Potion Pouch -> Save & quit, Continue -> out00 -> Ellinia
##           (the only region the clear unlocked; Perion stays locked) -> round 2 -> warp death -> results (NX earned) -> the character survives and the account
##           keeps NX and every item -> a NEW character uses them. Shots acct_*.png (+ *_zoom.png crops). `--account-nx=<n>`
##           changes the prepared balance; `--seed` defaults to 4; `--natural-clear=1` plays round 1 without invulnerability.
## The scenarios of the removed systems (maps, rounds, full, economy and the Warrior, Pirate, Bowman and Thief job/weapon pages)
## were deleted with job advancement, saved rounds and the old creation flow (#284, #286, #294).
## The skill scenario accepts --job=<playable id> (default 212).
## Other flags: --shots=<abs dir> (required), --seed=<n>, --wz=<folder> (import). The driver runs uncapped (vsync off).
##
## Screenshots are named NN_<step>.png; the driver prints one "flow_driver:" line per step and quits with exit code 1
## when a step times out or a check fails. Saves go to shots_dir/driver_save.json (delete the folder to repeat a scenario).
## tier C: diagnostic names, seeds 1 (redesign) and 4 (account), the 1800 s combat cap, 600-tick yields, the 400 + 75 meso
## loot, the 1e9 lethal hit, the Lv45 fallback staff, the card policy "rank the highest-ranked owned active once the slots are
## full" and the UI waits/timeouts are automation choices, never survivor tuning.

const CashShopScene := preload("res://scenes/ui/cash_shop.gd")
const StageSelectScene := preload("res://scenes/ui/stage_select.gd")
const MAIN := "res://scenes/main.tscn"
## Diagnostic build from the selected job's first three unlearned pool actives, plus common passives.
## tier C: automation policy, not tuning. No job-specific card list.
static func skill_build(w: RunWorld) -> Array:
	var cards := []
	var added := 0
	for key: String in w.jobs.skill_pool(w.job_id()):
		if not w.book.has(key) or w.loadout.has(key):
			continue
		cards.append(key + "_new")
		cards.append(key + "_rank")
		added += 1
		if added == 3:
			break
	cards.append_array(["passive_might_new", "passive_speed_new", "passive_speed_rank"])
	return cards


## Keys the steering sends (project.godot defaults: arrows, C jump (Alt too; Space is NPC Chat), Q potion; E is the
## Equip window).
const KEYS := {"left": KEY_LEFT, "right": KEY_RIGHT, "up": KEY_UP, "down": KEY_DOWN, "jump": KEY_C,
	"drink_hp": KEY_Q}

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
## The redesign scenario's card bookkeeping: every offer counted by kind and rarity, and the offers shown in a real window.
var _offers := {"picks": 0, "bonus": 0, "kinds": {}, "tiers": {}, "taken": {}}
var _showcased := {}
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
	# tier C: automation choice. An unfocused or occluded window is throttled to about 1 frame per second under vsync, which
	# starves every timeout below; uncapped frames keep the scripted run quick (and make `--vsync=off` the default here).
	GameSettings.apply_frame_cap(-1, true)
	flow = get_node_or_null("/root/Flow") as SceneFlow
	# The scripted UI creates/deletes real slots, always in ignored evidence, never the player's save.
	flow.save = SaveData.new(shots_dir.path_join("driver_save.json"))
	add_child((load(MAIN) as PackedScene).instantiate())
	match String(args.get("scenario", "full")):
		"clear":
			_scenario_clear()
		"import":
			_scenario_import()
		"redesign":
			_scenario_redesign()
		"progression":
			_scenario_progression()
		"creation":
			_scenario_creation()
		"title":
			_scenario_title()
		"windows":
			_scenario_windows()
		"skill":
			_scenario_skill()
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
		_:
			_fail("unknown scenario: " + String(args.get("scenario")))


func _process(_delta: float) -> void:
	if _steer:
		_steer_run()


# --- scenarios ---------------------------------------------------------------------------------------------------

## The map-select card index of the stage in flags `stage` (default henesys); -1 when that card is not offered.
func maps_stage_card(flags: Dictionary, cards: Array[Dictionary]) -> int:
	var key := String(flags.get("stage", "henesys"))
	for i in cards.size():
		if String(cards[i].key) == key:
			return i
	return -1


## Warps one map with fixed-tick bot inputs, then lets RunScene present its actual clear/fade/arrival.
func _warp_map(run: RunScene) -> bool:
	run.set_process(false)
	var w := run.world
	var index := w.map_index
	var memo := {}
	var ticks := 0
	var boundary_events: Array = []
	# tier C: same 1800 s safety cap / 600-tick yields as the existing diagnostic round warp.
	while w.time < 1800.0:
		if not await _answer_choices(run):
			return false
		if w.transfer_pending or w.state in [RunWorld.CLEARED, RunWorld.DEAD]:
			break
		if w.time - w.map_entered_at >= float(w.stage.map_seconds):
			# tier C: diagnostic post-timer hit, through real damage/death/reward settlement.
			for record: Dictionary in w.bosses.records:
				var slot := int(record.slot)
				if int(record.map_index) == index and not bool(record.dead) and slot >= 0 and w.swarm.is_live(slot):
					w.hit_mob(slot, {"skill": "energy_bolt", "magic": true, "damage_min": 1e9,
						"damage_max": 1e9, "crit": 0.0, "crit_mult": 1.0}, -1)
		w.step(RunScene.DT, BotInput.decide(w, memo))
		# Choice requests were answered by the bot; only the boundary events go to the real presentation.
		var events := w.drain_events()
		boundary_events.append_array(events.filter(func(e: Dictionary) -> bool:
			return String(e.type) in ["map_cleared", "stage_cleared", "player_died"]))
		ticks += 1
		if ticks % 600 == 0:
			await get_tree().process_frame
		if ticks % 6000 == 0:
			print("flow_driver: maps map %d warp %.0f s / Lv %d" % [index + 1, w.time, w.progression.level])
	boundary_events.append_array(w.drain_events().filter(func(e: Dictionary) -> bool:
		return String(e.type) in ["map_cleared", "stage_cleared", "player_died"]))
	if not _expect(w.transfer_pending or w.state == RunWorld.CLEARED, "diagnostic map did not clear"):
		return false
	run._apply_look()
	run._present(0.0)
	_collect_missing(run)
	if not _expect(w.warnings.is_empty(), "map warp warnings: %s" % w.warnings):
		return false
	if w.state == RunWorld.CLEARED:
		_rounds.append(run.build_summary())
	# Drain the warp's long frame before starting real-time effects or their first delta can skip the CLEAR art.
	await get_tree().process_frame
	await get_tree().process_frame
	run.handle_events(boundary_events)
	run.set_process(true)
	await _shot("map_%d_cleared" % (index + 1), 1.0)
	if index < 2:
		if not await _until(func() -> bool: return run._transfer_phase == "out", 10.0, "map fade"):
			return false
		await _shot("map_%d_fade" % (index + 1), RunScene.MAP_FADE_TIME * 0.5)
		if not await _until(func() -> bool: return w.map_index == index + 1 and run._transfer_phase == "",
				10.0, "map arrival"):
			return false
		await _shot("map_%d_enter" % (index + 2))
	return true

## Warps actual fixed ticks with the existing bot/choice policy; never fabricates a clear or character.
## UI navigation remains injected input. End events still go through RunScene's normal presentation/Flow path.
func _warp_round() -> bool:
	var run := flow.current as RunScene
	run.set_process(false)
	var memo := {}
	var ticks := 0
	while run.world.time < 1800.0 and run.world.state not in [RunWorld.DEAD, RunWorld.CLEARED]:
		while run.world.state == RunWorld.CHOOSING_UPGRADE:
			run.world.apply_choice(BotInput.pick_card_for(run.world, run.world.pending_cards))
		var choice_events := run.world.drain_events()
		# Settlement can clear inside the last answer, without another tick to emit the end event.
		# Earlier card requests in the batch have already been answered; do not reopen them over CLEAR.
		if run.world.state in [RunWorld.DEAD, RunWorld.CLEARED]:
			run.handle_events(choice_events.filter(func(e: Dictionary) -> bool:
				return String(e.type) in ["player_died", "stage_cleared"]))
		if run.world.transfer_pending:
			run.world.advance_map()
		if run.world.state in [RunWorld.DEAD, RunWorld.CLEARED]:
			run.handle_events(run.world.drain_events())
			break
		if run.world.state != RunWorld.PLAYING:
			continue
		if run.world.god and run.world.time >= run.world.duration \
				and (run.stage_key == "sleepywood" or String(args.get("scenario", "")) == "account"):
			# tier C (#232): flow/victory staging, not a naturally won round or a balance candidate.
			# Use the real damage/death/reward path; never fabricate a summary or bypass pending choices.
			for record: Dictionary in run.world.bosses.records:
				var slot := int(record.slot)
				if not bool(record.dead) and slot >= 0 and run.world.swarm.is_live(slot):
					run.world.hit_mob(slot, {"skill": "energy_bolt", "magic": true, "damage_min": 1e9,
						"damage_max": 1e9, "crit": 0.0, "crit_mult": 1.0}, -1)
		run.world.step(RunScene.DT, BotInput.decide(run.world, memo))
		if run.world.transfer_pending:
			run.world.advance_map()
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
	run.set_process(true)
	# Let the end effect advance before capturing it; the warp held presentation while settling choices.
	await _shot("round_" + run.world.state_name().to_lower(), 1.0 if run.world.state == RunWorld.CLEARED else 0.35)
	return true


## The hub's Esc menu -> Save & quit (2): back to character select with the slot saved.
func _save_and_quit_ui() -> void:
	await _key(KEY_ESCAPE)
	await _sleep(0.3)
	await _key(KEY_2)
	await _until(func() -> bool: return flow.current_name == "character_select", 10.0, "Save & quit to character select")


func _reload_save() -> void:
	flow.save = SaveData.new(shots_dir.path_join("driver_save.json"))


func _expect(ok: bool, message: String) -> bool:
	if not ok:
		_fail(message)
	return ok

## The F/P slice end to end (spec #282, #294) with injected input for every menu: title -> create an Arch Mage (name, look, Job
## page) -> Free Market -> map select (only Henesys open: Ellinia locked, its Start refused) -> a diagnostic Henesys round (invulnerable, the
## bot's fixed-tick warp, diagnostic boss hits after each map timer; the real CLEAR/fade/arrival presentation) whose first
## level-up, full-slots offer, first Mastery offer and boss bonus draw are answered through the real window with a number key
## -> results -> Free Market (Ellinia unlocked, loot kept) -> an equipment drop with a high reqLevel worn at Lv1 by a double-click ->
## Ellinia round (loot on the ground is picked up, then a diagnostic lethal boss hit) -> results -> Free Market (loot and
## the unlock kept, the item still worn) -> Save & quit -> delete the character -> round history -> the file is reloaded and
## checked. Shots: redesign_*.png, summary.json (offers, picks, slot counts, history); driver_save.json is the evidence-only
## save. Uses --seed (default 1) and --job=<id> (default 212, the Arch Mage; 112 is Hero, spec #296 H9: the Job page row of that
## job is clicked and the checks name its start skills, and its diagnostic fallback item). tier C: automation choices, not survivor
## tuning or survival evidence.
func _scenario_redesign() -> void:
	if not args.has("seed"):
		args["seed"] = "1"
	var job := _job_arg()
	if job < 0:
		return
	var data := DataRepo.load_all()
	var job_name := JobTree.from_data(data.jobs, data.jobs_survivor).name_of(job)
	if not await _until(func() -> bool: return flow.current_name == "title", 20.0, "title"):
		return
	await _sleep(2.0)
	await _key(KEY_ENTER)
	# 1. Creation: name -> look -> Job page -> Create.
	if not await _create_character("Redesign294", job):
		return
	var slot := flow.save.slot(flow.active_slot)
	var fresh: Dictionary = slot.character
	if not _expect(String(slot.name) == "Redesign294" and int(fresh.job_id) == job and fresh.cleared_regions == []
			and int(slot.rounds_played) == 0 and not fresh.has("level") and not fresh.has("skills"),
			"a new character is a %s with no region cleared and no build" % job_name):
		return
	await _shot("redesign_free_market_home")
	# 2. Map select: only Henesys is open; Ellinia (and every later region) is locked and cannot be started.
	if not await _open_map_select():
		return
	if not _expect(flow.current.unlocked_keys() == ["henesys"], "a new character can start only Henesys: %s"
			% [flow.current.unlocked_keys()]):
		return
	if not await _select_stage("ellinia"):
		return
	await _shot("redesign_map_select_ellinia_locked")
	var locked_card: Dictionary = flow.current.stages[flow.current.selected]
	if not _expect(bool(locked_card.locked) and (flow.current.start_button as WzButton).disabled,
			"Ellinia is locked for a character that has cleared nothing"):
		return
	await _click(flow.current.start_button)
	await _sleep(0.5)
	if not _expect(flow.current_name == "stage_select", "Start on a locked region must not start a round"):
		return
	while flow.current.selected > 0:
		await _key(KEY_UP)
	# 3. Henesys, diagnostic: Start with the driver's seed, then play the three maps.
	await _start_selected(flow.current)
	if not await _until(func() -> bool: return flow.current_name == "run", 10.0, "Henesys round"):
		return
	var run := flow.current as RunScene
	var w := run.world
	var start_skills := w.jobs.start_skills(job)
	if not _expect(w.job_id() == job and int(w.player_state.level) == 1
			and start_skills.size() > 0 and start_skills.size() == Array(start_skills).filter(w.loadout.has).size(),
			"the round starts at Lv1 with the %s start skills %s" % [job_name, start_skills]):
		return
	w.god = true # tier C: invulnerable flow staging, with diagnostic boss hits after each map timer
	await _sleep(1.0)
	await _shot("redesign_henesys_start")
	var mesos_before := int(slot.character.mesos)
	for index in 3:
		if not await _warp_map(run):
			return
		if index < 2 and not _expect(w.map_index == index + 1, "map %d clear must enter map %d" % [index + 1, index + 2]):
			return
	var checks := [
		_expect(int(_offers.picks) >= 30, "a full Henesys round makes dozens of picks (%d)" % int(_offers.picks)),
		_expect(w.loadout.slot_count("active") == w.loadout.slot_limit("active"),
			"all six active slots are filled (%s)" % w.loadout.slot_summary()),
		_expect(int(_offers.kinds.get("mastery", 0)) > 0, "a Mastery card was offered (kinds %s)" % [_offers.kinds]),
		_expect(int(_offers.bonus) >= 1, "the boss bonus draw was offered (%d)" % int(_offers.bonus)),
		_expect(_showcased.has("mastery") and _showcased.has("boss_draw") and _showcased.has("slots_full"),
			"the real windows showed the full-slots, Mastery and boss-draw offers (%s)" % [_showcased.keys()])]
	if false in checks:
		return
	var round_one := run.build_summary()
	# 4. Clear -> results -> Free Market, Ellinia unlocked, the round's loot kept.
	if not await _until(func() -> bool: return flow.current_name == "results", 20.0, "results after the clear"):
		return
	await _sleep(3.0)
	await _shot("redesign_results_clear")
	if not _expect(flow.last_summary.ending == "cleared", "the Henesys round ended cleared"):
		return
	await _click(flow.current.back_button)
	if not await _until(func() -> bool: return flow.current_name == "free_market", 15.0, "Free Market after the clear"):
		return
	await _sleep(1.0)
	await _shot("redesign_free_market_after_clear")
	slot = flow.save.slot(flow.active_slot)
	var kept: Dictionary = slot.character
	if not _expect(kept.cleared_regions == ["henesys"] and int(slot.rounds_played) == 1 and int(kept.mesos) >= mesos_before
			and Equipment.held_ids(kept.equipment).size() >= 4, "a clear unlocks Ellinia and keeps the loot"):
		return
	# 5. A drop whose reqLevel is far above Lv1 is worn from the Item window by a double-click.
	var item := await _equip_high_req_item(flow.current as FreeMarket, kept, job)
	if item.is_empty():
		return
	# 6. Ellinia is open now (and only Ellinia): loot on the ground is picked up, then a lethal hit ends the round.
	if not await _open_map_select():
		return
	if not _expect(flow.current.unlocked_keys() == ["henesys", "ellinia"], "the clear unlocked Ellinia and nothing else: %s"
			% [flow.current.unlocked_keys()]):
		return
	if not await _select_stage("ellinia"):
		return
	await _shot("redesign_map_select_ellinia_unlocked")
	if not _expect(not bool(flow.current.stages[flow.current.selected].locked), "Ellinia is startable after the clear"):
		return
	await _start_selected(flow.current)
	if not await _until(func() -> bool: return flow.current_name == "run", 10.0, "Ellinia round"):
		return
	run = flow.current as RunScene
	w = run.world
	await _sleep(1.0)
	await _shot("redesign_ellinia_start")
	if not _expect(w.equipment.worn.has(String(item.slot)) and int(w.equipment.worn[String(item.slot)].id) == int(item.id)
			and int(w.player_state.level) == 1, "the Lv1 round wears the high-reqLevel item (reqLevel %d)" % int(item.req_level)):
		return
	var mesos_round_start := w.mesos
	var loot_at := w.player.pos + Vector2(0.0, -30.0)
	w.god = true # only while the loot is collected: a Lv1 Sleepywood opening can end the round first
	w.spawn_meso(loot_at, 400)
	w.spawn_meso(loot_at + Vector2(24.0, 0.0), 75)
	var t0 := Time.get_ticks_msec()
	while w.mesos < mesos_round_start + 475:
		if Time.get_ticks_msec() - t0 > 20000:
			_fail("the character did not pick up the loot (%d mesos)" % w.mesos)
			return
		await get_tree().process_frame
	await _shot("redesign_ellinia_loot")
	w.god = false
	var round_two_mesos := w.mesos
	# "unrevivable": a ready second-life skill (Resurrection) must not turn this diagnostic hit into a survived one (#375).
	var lethal := {"boss": true, "source_kind": "attack", "mob": -1, "unrevivable": true}
	t0 = Time.get_ticks_msec()
	while w.state != RunWorld.DEAD:
		w.take_hit(1.0e9, false, "", w.player.pos + Vector2(40.0, 0.0), lethal)
		run.handle_events(w.drain_events()) # the world only drains its events while stepping: hand over the death
		if Time.get_ticks_msec() - t0 > 10000:
			_fail("the diagnostic lethal hit did not kill the character")
			return
		await get_tree().process_frame
	if not await _until(func() -> bool: return flow.current_name == "results", 20.0, "results after the death"):
		return
	await _sleep(3.0)
	await _shot("redesign_results_death")
	if not _expect(flow.last_summary.ending == "died", "the Ellinia round ended in a death"):
		return
	await _click(flow.current.back_button)
	if not await _until(func() -> bool: return flow.current_name == "free_market", 15.0, "Free Market after the death"):
		return
	await _sleep(1.0)
	await _shot("redesign_free_market_after_death")
	slot = flow.save.slot(flow.active_slot)
	var after: Dictionary = slot.character
	if not _expect(after.cleared_regions == ["henesys"] and int(slot.rounds_played) == 2 and int(after.mesos) >= round_two_mesos
			and after.equipment.worn.has(String(item.slot)) and int(after.equipment.worn[String(item.slot)].id) == int(item.id),
			"the death keeps the loot (%d mesos), the cleared Henesys and the worn item" % int(after.mesos)):
		return
	# 7. Save & quit, delete the character, read the history; the evidence-only save file carries all of it.
	await _save_and_quit_ui()
	if _failed:
		return
	_reload_save()
	if not _expect(not flow.save.slot(0).is_empty() and flow.save.slot(0).character.cleared_regions == ["henesys"]
			and flow.save.history.size() == 2, "Save & quit left the character and two history entries on disk"):
		return
	await _click(flow.current.slot_buttons[0])
	await _click(flow.current.delete_button)
	await _shot("redesign_delete_confirmation")
	await _sleep(0.3)
	await _key(KEY_ENTER)
	if not await _until(func() -> bool: return flow.save.slot(0).is_empty(), 10.0, "confirmed deletion"):
		return
	await _sleep(0.5)
	await _click(flow.current.find_child("RunHistory", true, false) as Control)
	if not await _until(func() -> bool: return flow.current_name == "history", 10.0, "round history"):
		return
	await _sleep(1.0)
	await _shot("redesign_history")
	_reload_save()
	var history: Array = flow.save.history
	if not _expect(history.size() == 3 and history[0].ending == "cleared" and history[1].ending == "died"
			and history[2].ending == "deleted" and history[0].stage == "henesys" and history[1].stage == "ellinia"
			and String(history[0].name) == "Redesign294" and int(history[0].job_id) == job,
			"the history lists the clear, the death and the deletion"):
		return
	var saved := FileAccess.open(shots_dir.path_join("driver_save.json"), FileAccess.READ)
	if not _expect(saved != null and JSON.parse_string(saved.get_as_text()) is Dictionary, "driver_save.json holds the save"):
		return
	_collect_missing(flow.current)
	if not _expect(_missing.is_empty() and not _failed, "missing assets or failed checks: %s" % [_missing]):
		return
	var report := {"scenario": "redesign", "seed": int(args.seed), "job": job, "diagnostic": true, "henesys": round_one,
		"offers": _offers, "showcased": _showcased, "equipped": item, "mesos_after_death": int(after.mesos),
		"history": history, "missing": Array(_missing), "failures": []}
	var file := FileAccess.open(shots_dir.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("flow_driver: redesign PASSED ", JSON.stringify({"picks": _offers.picks, "kinds": _offers.kinds, "bonus": _offers.bonus}))
	get_tree().quit()


## The region progression end to end (spec #447, #455) with injected input: a new character can start only Henesys (a locked Ellinia
## is refused and Henesys is the selected frontier) -> a diagnostic invulnerable Henesys clear (fixed-tick bot warp, lethal boss
## hits after each map timer, the real CLEAR/fade/arrival presentation) -> results -> Free Market -> map select (Henesys CLEAR,
## Ellinia NEW and selected by default, Perion locked) -> Ellinia the same way (Perion unlocked, Kerning still locked) ->
## Save & quit, character select, Continue (the cleared set read back from the file and shown by map select) -> a Perion round
## ended by a lethal hit (the set unchanged, the history says died) -> the slot swapped for a HubTestKit all-cleared character
## (header "Regions cleared N/N", nothing locked, the last region selected). Shots progression_*.png, summary.json. Uses --seed
## (default 1) and --job=<id> (default 212). tier C: diagnostic flow staging (invulnerable clears, a 1e9 lethal hit), never survival evidence.
func _scenario_progression() -> void:
	if not args.has("seed"):
		args["seed"] = "1"
	var job := _job_arg()
	if job < 0:
		return
	var order: Array = SceneFlow.progression()
	if not _expect(order.size() >= 4 and order.slice(0, 3) == ["henesys", "ellinia", "perion"], "the progression starts Henesys, Ellinia, Perion: %s" % [order]):
		return
	if not await _until(func() -> bool: return flow.current_name == "title", 20.0, "title"):
		return
	await _sleep(2.0)
	await _key(KEY_ENTER)
	if not await _create_character("Progress455", job):
		return
	var fresh: Dictionary = flow.save.slot(flow.active_slot).character
	if not _expect(fresh.cleared_regions == [] and not fresh.has("tiers_unlocked"), "a new character has cleared no region"):
		return
	# 1. A new character: only Henesys is startable, it is the selected frontier, a locked Start is refused.
	if not await _open_map_select():
		return
	var select: StageSelectScene = flow.current
	if not _expect(select.unlocked_keys() == ["henesys"] and select.stages.size() == order.size(), "a new character can start only Henesys: %s" % [select.unlocked_keys()]):
		return
	if not _expect(_card_states(select) == _states(order, 0, "henesys"), "new character card states: %s" % [_card_states(select)]):
		return
	if not _expect(select.stages[select.selected].key == "henesys" and not (select.start_button as WzButton).disabled
			and select.progress_label.text == "Regions cleared 0/%d" % order.size(), "Henesys is selected and startable, header %s" % select.progress_label.text):
		return
	await _shot("progression_01_new_character")
	if not await _select_stage("ellinia"):
		return
	await _shot("progression_02_new_ellinia_locked")
	if not _expect((select.start_button as WzButton).disabled and bool(select.stages[select.selected].locked), "Ellinia is locked and its Start disabled"):
		return
	await _click(select.start_button)
	await _sleep(0.5)
	if not _expect(flow.current_name == "stage_select" and flow.save.slot(flow.active_slot).rounds_played == 0, "Start on a locked region does not start a round"):
		return
	await _select_stage("henesys")
	# 2. The first diagnostic clear: Henesys.
	if not await _clear_selected_region("henesys", "01_henesys"):
		return
	var slot := flow.save.slot(flow.active_slot)
	if not _expect(slot.character.cleared_regions == ["henesys"] and int(slot.rounds_played) == 1, "the Henesys clear is saved: %s" % [slot.character.cleared_regions]):
		return
	# 3. Mid-progression: Henesys CLEAR, Ellinia NEW and selected on opening, the rest locked.
	if not await _open_map_select():
		return
	select = flow.current
	if not _expect(_card_states(select) == _states(order, 1, "ellinia") and select.stages[select.selected].key == "ellinia"
			and select.unlocked_keys() == ["henesys", "ellinia"] and select.progress_label.text == "Regions cleared 1/%d" % order.size(),
			"Henesys cleared, Ellinia the selected frontier: %s / %s" % [_card_states(select), select.progress_label.text]):
		return
	await _shot("progression_05_after_henesys")
	# 4. Ellinia: the selection on opening is the frontier, so Start needs no navigation.
	if not await _clear_selected_region("ellinia", "02_ellinia"):
		return
	slot = flow.save.slot(flow.active_slot)
	if not _expect(slot.character.cleared_regions == ["ellinia", "henesys"] and int(slot.rounds_played) == 2, "the Ellinia clear is saved: %s" % [slot.character.cleared_regions]):
		return
	if not await _open_map_select():
		return
	select = flow.current
	if not _expect(_card_states(select) == _states(order, 2, "perion") and select.stages[select.selected].key == "perion"
			and select.unlocked_keys() == ["henesys", "ellinia", "perion"] and select.progress_label.text == "Regions cleared 2/%d" % order.size(),
			"Ellinia cleared unlocked Perion and not Kerning: %s" % [_card_states(select)]):
		return
	await _shot("progression_08_after_ellinia")
	await _key(KEY_DOWN)
	await _shot("progression_09_kerning_locked")
	if not _expect(String(select.stages[select.selected].key) == "kerning" and bool(select.stages[select.selected].locked), "Kerning stays locked behind Perion"):
		return
	await _key(KEY_UP)
	# 5. Save & quit, character select, Continue: the cleared set survives.
	await _key(KEY_ESCAPE) # map select -> the character's Free Market
	if not await _until(func() -> bool: return flow.current_name == "free_market", 10.0, "Free Market from map select"):
		return
	await _save_and_quit_ui()
	if _failed:
		return
	_reload_save()
	if not _expect(flow.save.slot(0).character.cleared_regions == ["ellinia", "henesys"], "Save & quit left the cleared set on disk: %s" % [flow.save.slot(0).character.cleared_regions]):
		return
	await _sleep(0.5)
	await _click(flow.current.slot_buttons[0])
	await _click(flow.current.select_button)
	if not await _until(func() -> bool: return flow.current_name == "free_market", 10.0, "Continue"):
		return
	if not await _open_map_select():
		return
	select = flow.current
	if not _expect(_card_states(select) == _states(order, 2, "perion") and select.stages[select.selected].key == "perion",
			"Continue shows the same progression: %s" % [_card_states(select)]):
		return
	await _shot("progression_10_continued")
	# 6. Perion (selected by default): a lethal hit ends the round and the set does not change.
	await _start_selected(select)
	if not await _until(func() -> bool: return flow.current_name == "run", 10.0, "Perion round"):
		return
	var run := flow.current as RunScene
	var w := run.world
	if not _expect(run.stage_key == "perion" and int(w.player_state.level) == 1, "the Perion round starts at Lv1"):
		return
	await _sleep(1.0)
	await _shot("progression_11_perion_start")
	var lethal := {"boss": true, "source_kind": "attack", "mob": -1, "unrevivable": true}
	var t0 := Time.get_ticks_msec()
	while w.state != RunWorld.DEAD:
		w.take_hit(1.0e9, false, "", w.player.pos + Vector2(40.0, 0.0), lethal)
		run.handle_events(w.drain_events())
		if Time.get_ticks_msec() - t0 > 10000:
			_fail("the diagnostic lethal hit did not kill the character")
			return
		await get_tree().process_frame
	if not await _until(func() -> bool: return flow.current_name == "results", 20.0, "results after the death"):
		return
	await _sleep(3.0)
	await _shot("progression_12_perion_death")
	if not _expect(flow.last_summary.ending == "died" and flow.last_summary.stage == "perion", "the Perion round ended in a death"):
		return
	await _click(flow.current.back_button)
	if not await _until(func() -> bool: return flow.current_name == "free_market", 15.0, "Free Market after the death"):
		return
	slot = flow.save.slot(flow.active_slot)
	if not _expect(slot.character.cleared_regions == ["ellinia", "henesys"] and int(slot.rounds_played) == 3,
			"the death in Perion left the cleared set unchanged: %s" % [slot.character.cleared_regions]):
		return
	if not await _open_map_select():
		return
	select = flow.current
	if not _expect(_card_states(select) == _states(order, 2, "perion") and select.progress_label.text == "Regions cleared 2/%d" % order.size(),
			"map select after the death: %s" % [_card_states(select)]):
		return
	await _shot("progression_13_after_perion_death")
	# 7. All cleared (the HubTestKit character): nothing locked, no frontier, the last region selected.
	slot = flow.save.slot(flow.active_slot)
	slot.character = HubTestKit.apply(slot.character, HubTestKit.DEFAULT_MESOS, SceneFlow.equipment_info_loader())
	if not _expect(flow.save.update_slot(flow.active_slot, slot) == OK, "the all-cleared character was saved"):
		return
	await _key(KEY_ESCAPE)
	if not await _until(func() -> bool: return flow.current_name == "free_market", 10.0, "Free Market"):
		return
	if not await _reopen_hub():
		return
	if not await _open_map_select():
		return
	select = flow.current
	var all_states := _card_states(select)
	if not _expect(select.unlocked_keys().size() == order.size() and not all_states.values().has("locked") and not all_states.values().has("frontier")
			and select.progress_label.text == "Regions cleared %d/%d" % [order.size(), order.size()] and select.selected == order.size() - 1,
			"all-cleared character: %s, header %s, selected %d" % [all_states, select.progress_label.text, select.selected]):
		return
	await _shot("progression_14_all_cleared")
	await _key(KEY_UP)
	await _shot("progression_15_all_cleared_scrolled")
	_collect_missing(flow.current)
	if not _expect(_missing.is_empty() and not _failed, "missing assets or failed checks: %s" % [_missing]):
		return
	var report := {"scenario": "progression", "seed": int(args.seed), "job": job, "diagnostic": true, "rounds": _rounds,
		"history": flow.save.history, "missing": Array(_missing), "failures": []}
	var file := FileAccess.open(shots_dir.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("flow_driver: progression PASSED")
	get_tree().quit()


## Map select's cards as {key: "cleared"|"frontier"|"locked"|"open"} (an unlocked region that is neither cleared nor the frontier).
func _card_states(select: StageSelectScene) -> Dictionary:
	var out := {}
	for card: Dictionary in select.stages:
		out[String(card.key)] = "cleared" if bool(card.cleared) else ("frontier" if bool(card.frontier) else ("locked" if bool(card.locked) else "open"))
	return out


## The states of `order` when its first `cleared` regions are cleared and `frontier` is the next one; the rest are locked.
func _states(order: Array, cleared: int, frontier: String) -> Dictionary:
	var out := {}
	for i in order.size():
		out[String(order[i])] = "cleared" if i < cleared else ("frontier" if String(order[i]) == frontier else "locked")
	return out


## Starts the map-select selection (which must be `key`), plays the three maps with the diagnostic fixed-tick warp and goes back to
## the Free Market through the results screen. `prefix` names the shots.
func _clear_selected_region(key: String, prefix: String) -> bool:
	var select: StageSelectScene = flow.current
	if not _expect(String(select.stages[select.selected].key) == key, "%s is the selected region" % key):
		return false
	await _start_selected(select)
	if not await _until(func() -> bool: return flow.current_name == "run", 10.0, key + " round"):
		return false
	var run := flow.current as RunScene
	var w := run.world
	if not _expect(run.stage_key == key and int(w.player_state.level) == 1, "the %s round starts at Lv1" % key):
		return false
	w.god = true # tier C: invulnerable flow staging, with diagnostic boss hits after each map timer
	await _sleep(1.0)
	await _shot("progression_%s_start" % prefix)
	for index in 3:
		if not await _warp_map(run):
			return false
		if index < 2 and not _expect(w.map_index == index + 1, "map %d clear must enter map %d" % [index + 1, index + 2]):
			return false
	if not await _until(func() -> bool: return flow.current_name == "results", 20.0, "results after the %s clear" % key):
		return false
	await _sleep(3.0)
	await _shot("progression_%s_results" % prefix)
	if not _expect(flow.last_summary.ending == "cleared" and flow.last_summary.stage == key, "the %s round ended cleared" % key):
		return false
	await _click(flow.current.back_button)
	if not await _until(func() -> bool: return flow.current_name == "free_market", 15.0, "Free Market after the %s clear" % key):
		return false
	await _sleep(1.0)
	return true


## Wears, with a double-click in the Item window's Equip tab, the carried item with the highest reqLevel this job can wear
## (the round's own drop). When the round dropped none, the job's hub_kit fallback_item (a Lv40-45 weapon) is added to the Equip tab
## (diagnostic) and the report says so. Returns {id, slot, req_level, source}, empty after a failure.
func _equip_high_req_item(hub: FreeMarket, character: Dictionary, job: int = 212) -> Dictionary:
	var lib := AssetLibrary.get_default()
	var best := {}
	for held: Dictionary in character.equipment.inventory:
		var id := int(held.id)
		var img := lib.img(AvatarRenderer.part_img_path(id))
		var info: Dictionary = img.root.get("info", {}) if img != null else {}
		if Equipment.requirement_error(info, {"job_id": job}) == "" and int(info.get("reqLevel", 0)) > int(best.get("req_level", 1)) \
				and Equipment.slot_of(id) != "":
			best = {"id": id, "slot": Equipment.slot_of(id), "req_level": int(info.get("reqLevel", 0)), "source": "round drop"}
	if best.is_empty():
		var weapon: int = HubTestKit.fallback_item(job)
		if not _expect(weapon != 0, "the scenario has no diagnostic fallback item for job %d" % job):
			return {}
		var img := lib.img(AvatarRenderer.part_img_path(weapon))
		var info: Dictionary = img.root.get("info", {}) if img != null else {}
		hub.inventory.equipment.inventory.append(Equipment.create(weapon, info))
		best = {"id": weapon, "slot": "weapon", "req_level": int(info.get("reqLevel", 0)), "source": "diagnostic grant"}
	if not _expect(int(best.req_level) > 1, "an item with a reqLevel above Lv1 is available"):
		return {}
	await _key(KEY_E)
	await _key(KEY_I)
	await _sleep(0.6)
	var iw := hub.ui_windows.find_window("item") as ItemWindow
	var ew := hub.ui_windows.find_window("equip") as EquipWindow
	if not _expect(iw != null and ew != null, "E and I open the Equip and Item windows in the Free Market"):
		return {}
	var cell := -1
	for i in iw.cells().size():
		if int(iw.cells()[i].id) == int(best.id):
			cell = i
	if not _expect(cell >= 0, "the Item window's Equip tab lists the item"):
		return {}
	_hover(iw.get_global_rect().position + iw.slot_rect(cell).get_center())
	await _sleep(0.5)
	await _shot("redesign_item_tooltip_no_requirements")
	await _double_click_at(iw.get_global_rect().position + iw.slot_rect(cell).get_center())
	await _sleep(0.6)
	if not _expect(ew.worn_id(String(best.slot)) == int(best.id), "the double-click wore the reqLevel-%d item at Lv1" % int(best.req_level)):
		return {}
	await _shot("redesign_item_worn")
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	await _sleep(0.4)
	return best


## Answers the pending card choices of `run`'s world like BotInput.auto_choose, recording every offer in `_offers`. The first
## full-slots offer, Mastery offer and boss bonus draw (and the very first level-up) go through the real LevelUpWindow, answered
## by an injected number key; the rest are applied directly (a fixed-tick warp). False after a failure.
func _answer_choices(run: RunScene) -> bool:
	var w := run.world
	var guard := 0
	while w.state == RunWorld.CHOOSING_UPGRADE and guard < 64:
		guard += 1
		var cards: Array = w.pending_cards.duplicate(true)
		var bonus := w.choice_bonus
		var pick := _scenario_pick(w, cards)
		var show := _showcase_of(w, cards, bonus)
		_note_offer(cards, bonus, pick)
		if show == "":
			w.apply_choice(pick)
			continue
		_showcased[show] = {"level": int(w.player_state.level), "time": snappedf(w.time, 0.1)}
		var index := 0
		for i in cards.size():
			var wanted := String(cards[i].card_kind) == "mastery" if show == "mastery" else String(cards[i].id) == pick
			if wanted:
				index = i
				break
		# Direct warp picks can queue further choice_pending events. They describe older offers by the
		# time we showcase this one; do not let RunScene._process reopen one over the live cards.
		run.handle_events(w.drain_events().filter(func(e: Dictionary) -> bool:
			return String(e.type) != "choice_pending"))
		run._pending_window = {}
		if run.window != null:
			run._close_window()
		run.handle_events([{"type": "choice_pending", "cards": cards, "bonus": bonus}])
		run.set_process(true)
		if not await _until(func() -> bool: return run.window is LevelUpWindow and (run.window as MapleWindow).is_open() \
				and run.window._since_open >= run.window.input_delay,
				10.0, "the %s window" % show):
			return false
		await _shot("redesign_offer_" + show, 0.9)
		var first_window := run.window
		await _key((KEY_1 + index) as Key)
		if not await _until(func() -> bool: return w.state != RunWorld.CHOOSING_UPGRADE or run.window != first_window,
				10.0, "the card picked with a number key"):
			return false
		run.set_process(false)
		# Anything queued behind this pick is answered by the next loop turn, not by a second window.
		run._pending_window = {}
		if run.window != null and run.window != first_window:
			run._close_window()
	return true


## The scenario's card policy (tier C, automation): the bot's pick, except that once every active slot is filled the rank (or
## Mastery) card of the highest-ranked owned active is taken, so a Mastery card can appear within one round. The bot itself
## ranks passives first and rarely reaches rank 8 (GAME_DESIGN 4.2, #294), so this is flow evidence, not a play-style claim.
func _scenario_pick(w: RunWorld, cards: Array) -> String:
	var best := BotInput.pick_card_for(w, cards)
	if w.loadout.slot_count("active") < w.loadout.slot_limit("active"):
		return best
	var best_rank := -1
	for card: Dictionary in cards:
		if String(card.card_kind) == "mastery":
			return String(card.id)
		if String(card.card_kind) == "owned_active" and int(card.skill_rank_before) > best_rank:
			best_rank = int(card.skill_rank_before)
			best = String(card.id)
	return best


## The showcase an offer earns (once each): the first level-up, the first offer with every active slot filled, the first Mastery
## offer and the first boss bonus draw; "" for every other offer.
func _showcase_of(w: RunWorld, cards: Array, bonus: bool) -> String:
	if bonus and not _showcased.has("boss_draw"):
		return "boss_draw"
	for card: Dictionary in cards:
		if String(card.card_kind) == "mastery" and not _showcased.has("mastery"):
			return "mastery"
	if w.loadout.slot_count("active") >= w.loadout.slot_limit("active") and not _showcased.has("slots_full"):
		return "slots_full"
	if not _showcased.has("first_levelup"):
		return "first_levelup"
	return ""


## Counts one offer: picks, boss bonus draws, the kinds and rarities of the cards on it, and the kind of the card taken.
func _note_offer(cards: Array, bonus: bool, pick: String) -> void:
	_offers.picks = int(_offers.picks) + 1
	if bonus:
		_offers.bonus = int(_offers.bonus) + 1
	for card: Dictionary in cards:
		var kind := String(card.card_kind)
		_offers.kinds[kind] = int(_offers.kinds.get(kind, 0)) + 1
		var tier := String(card.tier)
		_offers.tiers[tier] = int(_offers.tiers.get(tier, 0)) + 1
		if String(card.id) == pick:
			_offers.taken[kind] = int(_offers.taken.get(kind, 0)) + 1


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


## The scenario's `--job=<id>` (default 212): the id, or -1 after a failure when it is malformed.
func _job_arg() -> int:
	var text := String(args.get("job", "212"))
	var job := JobTree.parse_job(text)
	if job < 0:
		_fail("--job=%s is not a job id" % text)
	return job


## Character select -> name -> look -> Job page (the `job` row clicked) -> Create: ends in the new character's Free Market.
func _create_character(character_name: String, job: int = 212, shot_prefix := "") -> bool:
	var prefix := shot_prefix + "_" if shot_prefix != "" else ""
	if not await _until(func() -> bool: return flow.current_name == "character_select", 10.0, "character select"):
		return false
	await _sleep(0.5)
	await _shot(prefix + "character_select")
	await _click(flow.current.get("create_button") as Control)
	await _sleep(0.5)
	var creation: Control = flow.current.get("creation")
	await _shot(prefix + "creation_name")
	await _click(creation.get("name_edit") as Control)
	await _type(character_name)
	await _click(creation.get("create_button") as Control)
	await _shot(prefix + "creation_look")
	await _click(creation.get("create_button") as Control)
	var job_row := creation.find_child("Job_%d" % job, true, false) as Control
	if not _expect(job_row != null, "the Job page lists no row for job %d (listed %s)" % [job, creation.get("job_ids")]):
		return false
	await _click(job_row)
	await _shot(prefix + "creation_job")
	await _click(creation.get("create_button") as Control)
	return await _until(func() -> bool: return flow.current_name == "free_market", 10.0, "Free Market (home)")


## Walks the Free Market character to the scripted out00 portal with the arrow keys and presses Up: map select.
func _open_map_select() -> bool:
	if not await _until(func() -> bool: return flow.current_name == "free_market", 10.0, "Free Market"):
		return false
	await _sleep(1.0)
	var hub := flow.current as FreeMarket
	var exit_pos := Vector2.ZERO
	for portal: Dictionary in hub.motion.portals.links:
		if portal.name == "out00":
			exit_pos = portal.pos
	var t0 := Time.get_ticks_msec()
	while absf(hub.motion.player.pos.x - exit_pos.x) > 8.0:
		if Time.get_ticks_msec() - t0 > 30000: # tier C: automation guard, never survivor tuning
			_fail("walking to out00 timed out")
			return false
		_set_key("left", hub.motion.player.pos.x > exit_pos.x)
		_set_key("right", hub.motion.player.pos.x < exit_pos.x)
		await get_tree().process_frame
	_release_all()
	await _shot("free_market_out00")
	_collect_missing(hub)
	await _key(KEY_UP)
	if not await _until(func() -> bool: return flow.current_name == "stage_select", 10.0, "map select via out00"):
		return false
	await _sleep(2.0)
	return true


## Continues the active character (the hub is rebuilt from the saved slot) and waits for the NEW Free Market scene.
func _reopen_hub() -> bool:
	var old_id := flow.current.get_instance_id()
	flow.continue_character(flow.active_slot)
	return await _until(func() -> bool: return is_instance_valid(flow.current) and flow.current.get_instance_id() != old_id \
			and flow.current_name == "free_market", 10.0, "Free Market (continued)")


## Presses Down or Up on the open map select until the card of stage `key` is selected (map select opens on the frontier, #451).
func _select_stage(key: String) -> bool:
	var select: StageSelectScene = flow.current
	var card := maps_stage_card({"stage": key}, select.stages)
	if not _expect(card >= 0, "map select offers no %s card" % key):
		return false
	while select.selected < card:
		await _key(KEY_DOWN)
	while select.selected > card:
		await _key(KEY_UP)
	return _expect(select.selected == card, "Down/Up did not select the %s card" % key)


## Title (Enter) -> a new character -> Free Market -> map select -> Start: the way into a round for the in-run scenarios.
func _enter_round(character_name: String, job: int = 212) -> bool:
	if not await _until(func() -> bool: return flow.current_name == "title", 20.0, "title"):
		return false
	await _sleep(2.0)
	await _key(KEY_ENTER)
	if not await _create_character(character_name, job):
		return false
	if not await _open_map_select():
		return false
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
	if not await _open_map_select():
		return
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
	await _click(flow.current.back_button)
	if not await _until(func() -> bool: return flow.current_name == "free_market", 10.0, "Free Market"):
		return
	await _save_and_quit_ui()
	if _failed:
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
## out00, Up -> map select -> Start: the round's character wears the hat and has the pet out.
func _scenario_cash_equip() -> void:
	flow.save.set_account({"nx": 12000, "owned": []})
	if not await _until(func() -> bool: return flow.current_name == "title", 20.0, "title"):
		return
	await _sleep(1.0)
	await _key(KEY_ENTER)
	if not await _create_character("Dress122"):
		return
	if not await _open_map_select():
		return
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
	await _click(flow.current.back_button)
	if not await _until(func() -> bool: return flow.current_name == "free_market", 10.0, "Free Market"):
		return
	await _save_and_quit_ui()
	if _failed:
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
	if not await _open_map_select():
		return
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
## map select SHOP: buy a hat and a pet -> round 1: E, Cash tab (wear the hat), Pet page (bring the pet out) -> a
## fixed-tick warp clears it -> Free Market: the "+N NX" notice and the saved balance, SHOP: buy Auto HP Potion Pouch ->
## Save & quit, Continue -> out00 -> map select (balance shown) -> round -> a warp dies -> results (NX earned),
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
	if not await _open_map_select():
		return
	await _shot("acct_00_map_select_balance")
	_check(flow.current.unlocked_keys() == ["henesys"], "a new character can start only Henesys: %s" % [flow.current.unlocked_keys()])
	_check(flow.current.character_label.text.contains("11,000 NX"), "map select shows the NX balance: %s" % flow.current.character_label.text)
	# 1. Cash Shop from map select: buy the first hat and the first pet.
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
	# 3. Diagnostic clear: Free Market arrival shows "+N NX" and the balance is saved.
	# tier C: the bot with a hat and a pet no longer clears Henesys on the training seeds (it has 0/3 clears anyway), so
	# round 1 is invulnerable, with diagnostic boss hits after its timer (round 2 exercises the real death path).
	# --natural-clear=1 disables invulnerability and diagnostic boss hits.
	run.world.god = String(args.get("natural-clear", "0")) != "1"
	if not await _warp_round():
		return
	var nx_awarded := int(_rounds.back().get("nx_awarded", 0))
	if not await _until(func() -> bool: return flow.current_name == "results", 15.0, "results after the clear"):
		return
	await _sleep(1.0)
	await _shot("acct_03b_results_clear")
	await _click(flow.current.back_button)
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
	# 6. out00 -> map select (balance; the Henesys clear unlocked Ellinia and nothing else) -> round 2 -> death.
	if not await _open_map_select():
		return
	_check(flow.current.unlocked_keys() == ["henesys", "ellinia"], "the clear unlocked Ellinia only: %s" % [flow.current.unlocked_keys()])
	if not await _select_stage("ellinia"):
		return
	_check(flow.current.character_label.text.contains(SaveData._group(balance) + " NX"), "map select shows %d NX: %s" % [balance, flow.current.character_label.text])
	await _shot("acct_08_ellinia_map_select")
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
	if not await _until(func() -> bool: return flow.current_name == "free_market", 10.0, "Free Market after the death"):
		return
	await _save_and_quit_ui()
	if _failed:
		return
	_reload_save()
	_check(not flow.save.slot(0).is_empty(), "the character survived its death (no permadeath)")
	_check(flow.save.account.owned == [hat, pet, upgrade] and int(flow.save.account.nx) == balance + death_nx,
		"the account kept every item and %d NX after the death (%d)" % [balance + death_nx, int(flow.save.account.nx)])
	balance += death_nx
	# 7. A NEW character uses the account's items.
	if not await _create_character("Heir126"):
		return
	if not await _open_map_select():
		return
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
	var view := get_viewport().get_visible_rect().size
	var lo := Vector2(minf(a.x, b.x) - 110.0, minf(a.y, b.y) - 110.0).clamp(Vector2.ZERO, view)
	var hi := Vector2(maxf(a.x, b.x) + 110.0, maxf(a.y, b.y) + 50.0).clamp(Vector2.ZERO, view)
	# The capture has window pixels (canvas_items stretch, #224): crop at the capture's scale, save at 3x logical size.
	var crop := img.get_region(GameSettings.capture_rect(img, get_viewport(), Rect2(lo, hi - lo)).intersection(
		Rect2i(Vector2i.ZERO, img.get_size())))
	crop.resize(int(hi.x - lo.x) * 3, int(hi.y - lo.y) * 3, Image.INTERPOLATE_NEAREST)
	_n += 1
	crop.save_png(shots_dir.path_join("%02d_%s.png" % [_n, step]))
	print("flow_driver: shot %02d_%s.png (zoom)" % [_n, step])


func _scenario_skill() -> void:
	var job := _job_arg() # `--job=<id>` (default 212; 222 is the I/L Arch Mage, #330)
	if job < 0:
		return
	if not await _enter_round("Skill86", job):
		return
	var run := flow.current as RunScene
	await _sleep(3.0)
	# A build to show (debug setup, like the windows scenario's EXP drop): three more pool actives with ranks, and two
	# common passives (cards applied directly; the Teleport key skill and the starting Energy Bolt are already known).
	var w := run.world
	for id: String in skill_build(w):
		w.upgrades.apply(id, w)
	await _sleep(0.5)
	# K opens the Skill window on the job's tab (the last) and holds the sim.
	await _key(KEY_K)
	if not await _until(func() -> bool: return run.ui_windows.find_window("skill") != null, 3.0, "Skill window (K)"):
		return
	var sw := run.ui_windows.find_window("skill") as SkillWindow
	var t0 := run.world.time
	await _sleep(0.8)
	_check(run.world.time == t0, "the sim holds while Skill is open")
	var last_tab: int = sw.model.tabs.size() - 1
	_check(sw.model.tabs[0].name == "Common" and last_tab >= 1 and sw.tab == last_tab,
		"opened on the job's own tab, the last, after the Common tab (no Beginner or star tab; %d tabs)" % sw.model.tabs.size())
	_check(sw.model.loadout.slot_summary().begins_with("Active 4/6"), "four active skills held (%s)" % sw.model.loadout.slot_summary())
	await _shot("skill_window")
	# Keyboard: Down moves the selection to the last row with its tooltip; Left switches to the Common tab.
	for i in sw.rows().size():
		await _key(KEY_DOWN)
	await _sleep(0.3)
	if not sw.rows().is_empty(): # a sparse synthetic book may have no rows
		var last := sw.tooltip()
		_check(String(last.get("key", "")) == String(sw.rows()[sw.rows().size() - 1].key), "Down selected the last row (%s)" % [last.get("key", "")])
		await _shot("skill_keyboard_tooltip")
	await _key(KEY_LEFT)
	await _sleep(0.3)
	_check(sw.tab == last_tab - 1, "Left switched to the previous job tab")
	var origin := sw.get_global_rect().position
	await _click_at(origin + sw.tab_rect(0).get_center())
	await _sleep(0.3)
	_check(sw.tab == 0, "a click picked the Common tab")
	var common_keys: Array = sw.rows().map(func(row: Dictionary) -> String: return String(row.key))
	_check(common_keys.size() == 9 and "passive_might" in common_keys and "passive_crit" in common_keys,
		"the Common tab lists the nine common passives (%s)" % [common_keys])
	await _shot("skill_common_tab")
	# Mouse: hovering a learned common passive shows its tooltip.
	var might := common_keys.find("passive_might")
	_hover(origin + sw.row_rect(might - sw.scroll).get_center())
	await _sleep(0.4)
	var tip := sw.tooltip()
	_check(String(tip.get("key", "")) == "passive_might" and int(tip.get("level", 0)) == 1,
		"hovering Maple Warrior shows rank 1 (%s)" % [tip.get("key", "")])
	await _shot("skill_tooltip_passive")
	# The mouse picks the job's tab; the strip ends after the last job tab.
	await _click_at(origin + sw.tab_rect(last_tab).get_center())
	await _sleep(0.3)
	_check(sw.tab == last_tab, "clicked the job's tab")
	await _click_at(origin + sw.tab_rect(last_tab + 1).get_center())
	await _sleep(0.3)
	_check(sw.tab == last_tab, "no tab past the job's own to click")
	for tab_index in range(last_tab + 1): # every tab: Common, then each book of the lineage (220 holds Teleport for the I/L)
		await _click_at(origin + sw.tab_rect(tab_index).get_center())
		await _sleep(0.2)
		_check(sw.tab == tab_index, "skill tab %d shown" % tab_index)
		await _shot("skill_tab_%d" % tab_index)
	await _key(KEY_2)
	await _sleep(0.2)
	_check(sw.tab == 1, "2 switched to the second tab (the Magician)")
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
	_check(run.world.state == RunWorld.CHOOSING_UPGRADE, "1 picked nothing under the Skill window (it switches tabs)")
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
	var fixture: Variant = DataRepo.load_json("res://tests/fixtures/characters/fp_arch_mage.json")
	if not fixture is Dictionary or CharacterSnapshot.validation_error(fixture) != "":
		_fail("the Lv38 F/P fixture did not load")
		return
	var lib := AssetLibrary.get_default()
	var slot := flow.save.slot(flow.active_slot)
	var character: Dictionary = fixture
	character.erase("_doc")
	for id: int in [1002001, 1050018, 1082002, 1092000]:
		var img := lib.img(AvatarRenderer.part_img_path(id))
		character.equipment.inventory.append(Equipment.create(id, img.root.get("info", {}) if img != null else {}))
	character.mesos = 123456
	character.scrolls = {"2040000": 2, "2043700": 1}
	slot.character = character
	_check(flow.save.update_slot(flow.active_slot, slot) == OK, "the fixture character was saved into the slot")
	if not await _reopen_hub():
		return
	if not await _open_map_select():
		return
	await _start_selected(flow.current)
	if not await _until(func() -> bool: return flow.current_name == "run", 10.0, "run"):
		return
	var run := flow.current as RunScene
	await _sleep(3.0)
	# #239: a real potion-key press, followed by five sim seconds, leaves a visible mid-sweep wedge while the
	# inventory windows hold the simulation. Read the live binding so the developer's Key Config still works.
	var drink_keys := InputMap.action_get_events("drink_hp")
	if not drink_keys.is_empty() and drink_keys[0] is InputEventKey:
		var drink_key := drink_keys[0] as InputEventKey
		await _key(drink_key.physical_keycode if drink_key.physical_keycode != 0 else drink_key.keycode)
		await _sleep(5.0)
		var step := int(run.hud.quick_slot.displayed("hp").sweep_step)
		_check(step > 0 and step < HudSkills.SWEEP_STEPS, "the HP potion shows a mid-sweep wedge")
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
	# Tooltips: the robe (wearable) and a Warrior shield (the job row only; no level or stat rows, ADR 0006).
	_hover(io + iw.slot_rect(1).get_center())
	await _sleep(0.4)
	_check(String(iw.tooltip().get("name", "")) == "Blue Sauna Robe" and bool(iw.tooltip().get("can_equip", false)),
		"the robe's tooltip (%s)" % [iw.tooltip().get("name", "")])
	await _shot("item_tooltip")
	_hover(io + iw.slot_rect(3).get_center())
	await _sleep(0.4)
	_check(not bool(iw.tooltip().get("can_equip", true)) and not iw.tooltip().has("reqs"),
		"the Warrior shield's tooltip marks the job it cannot be worn by, with no level or stat rows")
	await _shot("item_tooltip_unmet")
	await _double_click_at(io + iw.slot_rect(3).get_center())
	await _sleep(0.3)
	_check(iw.cells().size() == 4 and not run.world.equipment.worn.has("overall"), "the refused Warrior shield stays put")
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
	_check(iw.cells().size() == 3, "the top and bottom took the worn items' places, the shield stays (%d)"
		% iw.cells().size())
	_hover(eo + ew.slot_rect("top").get_center())
	await _sleep(0.4)
	await _shot("equip_worn")
	# Drag the Calas out: the YesNo box; No keeps it.
	var calas := -1
	for i in iw.cells().size():
		if int(iw.cells()[i].id) == 1092000:
			calas = i
	await _drag(io + iw.slot_rect(calas).get_center(), Vector2(get_viewport().get_visible_rect().size.x - 60.0, 120.0))
	await _sleep(0.4)
	var confirm := run.ui_windows.top() as DropConfirm
	_check(confirm != null, "dragging an item out asks the v83 question")
	await _shot("drop_confirm")
	if confirm != null:
		await _click(confirm._bt_no)
		await _sleep(0.3)
	_check(iw.cells().size() == 3, "No kept the shield")
	await _click_at(io + iw.tab_rect(1).get_center())
	await _sleep(0.3)
	_check(iw.tab == 1 and iw.cells() == [{"kind": "scroll", "id": 2040000, "count": 2},
		{"kind": "scroll", "id": 2043700, "count": 1}], "the Use tab shows scroll stacks only, with no potions")
	_hover(io + iw.slot_rect(0).get_center())
	await _sleep(0.4)
	await _shot("item_use_tab")
	# Every tab shown once (#219: the v83 tab shapes, the shown one pink).
	for t in [2, 3, 4]:
		await _click_at(io + iw.tab_rect(t).get_center())
		await _sleep(0.2)
		_check(iw.tab == t, "tab %d shown" % t)
		await _shot("item_tab_%s" % ItemWindow.TABS[t])
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
	_check(flow.save.update_slot(flow.active_slot, slot) == OK, "the dressed character was saved at the hub")
	if not await _reopen_hub():
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
	var fixture: Variant = DataRepo.load_json("res://tests/fixtures/characters/fp_arch_mage.json")
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
	if not await _reopen_hub():
		return
	if not await _open_map_select():
		return
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
	_check(flow.save.update_slot(flow.active_slot, slot) == OK, "the character was saved at the hub")
	if not await _reopen_hub():
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
	var fixture: Variant = DataRepo.load_json("res://tests/fixtures/characters/fp_arch_mage.json")
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
	_check(flow.save.update_slot(flow.active_slot, slot) == OK, "the character was saved at the hub")
	if not await _reopen_hub():
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
	# Every sell tab shown once (#219: the v83 tab shapes), ending on Use.
	for t in [2, 3, 4, 0]:
		await _click_at(origin + shop.tab_rect(t).get_center())
		await _sleep(0.2)
		_check(shop.tab == t, "sell tab %d shown" % t)
		await _shot("shop_tab_%s" % ShopWindow.TABS[t])
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
	var fixture: Variant = DataRepo.load_json("res://tests/fixtures/characters/fp_arch_mage.json")
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
	_check(flow.save.update_slot(flow.active_slot, slot) == OK, "the character was saved at the hub")
	if not await _reopen_hub():
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


## Creates one character per job (`--jobs=<id,id>`, at most the three save slots; default every playable job, which fails when more than three ship) through the real creation screens, looking at the
## Job page each time, then checks each slot holds its job with its creation weapon and nothing cleared.
func _scenario_creation() -> void:
	var data := DataRepo.load_all()
	var tree := JobTree.from_data(data.jobs, data.jobs_survivor)
	var jobs: Array[int] = []
	if args.has("jobs"):
		for part: String in String(args.jobs).split(","):
			jobs.append(JobTree.parse_job(part))
	else:
		jobs = tree.playable_jobs()
	if not _expect(not jobs.is_empty() and not (-1 in jobs), "--jobs=%s names no job" % String(args.get("jobs", ""))):
		return
	if not _expect(jobs.size() <= SaveData.SLOT_COUNT, "creation makes one character per job in its own slot: %d jobs do not fit %d slots; pass --jobs=<id,id> with at most %d" \
			% [jobs.size(), SaveData.SLOT_COUNT, SaveData.SLOT_COUNT]):
		return
	if not await _until(func() -> bool: return flow.current_name == "title", 20.0, "title"):
		return
	await _sleep(2.0)
	await _key(KEY_ENTER)
	for i in jobs.size():
		var job: int = jobs[i]
		if not await _create_character("Create%d" % (3050 + job), job, "job_%d" % job):
			return
		var character: Dictionary = flow.save.slot(i).character
		if not _expect(int(character.job_id) == job and character.cleared_regions == []
				and int(character.equipment.worn.weapon.id) == tree.creation_weapon(job),
				"slot %d holds a %s with its creation weapon %d" % [i, tree.name_of(job), tree.creation_weapon(job)]):
			return
		await _sleep(1.0)
		await _shot("job_%d_free_market" % job)
		await _save_and_quit_ui()
		if _failed:
			return
	await _shot("creation_character_select")
	_collect_missing(flow.current)
	if not _expect(_missing.is_empty(), "missing assets: %s" % [_missing]):
		return
	print("flow_driver: creation PASSED ", jobs)
	get_tree().quit()


func _scenario_title() -> void:
	if not await _until(func() -> bool: return flow.current_name == "title", 30.0, "title"):
		return
	await _sleep(9.0)
	await _shot("title")
	await _key(KEY_ESCAPE)
	await _sleep(2.0)
	get_tree().quit(1 if _failed else 0)


func _scenario_import() -> void:
	if not await _until(func() -> bool: return flow.current_name in ["title", "import"], 20.0, "import or title"):
		return
	if flow.current_name == "title":
		await _click(flow.current.get("reimport") as Control)
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


func _shot(step: String, settle_seconds := 0.35) -> void:
	# The collaborative desktop may occlude the window; explicitly render this evidence frame.
	# tier C: let the existing modal input guard and 0.15s open transition finish before the next input/capture.
	await _sleep(settle_seconds)
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
	if node is WzImage and node.path != "" and not node.has_art() and not node.path in _missing:
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
