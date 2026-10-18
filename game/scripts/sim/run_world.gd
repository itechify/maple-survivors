class_name RunWorld
extends RefCounted
## One survivor run (docs/ARCHITECTURE.md 4.3, 4.4, 4.4.1-4.4.3): built from a setup Dictionary, advanced by fixed
## 1/60 s step() calls, reporting what happened through `events`. Pure: no nodes, input, time, files or autoloads.
##
## Per PLAYING tick: drinks -> portals/movement -> view/timers (regen/buffs) -> swarm -> boss lifecycle,
## skills/attacks/monster balls -> ordinary spawns/hash -> SkillRunner/BasicAttack -> player shots/kills/rewards ->
## pickups -> touch -> collected EXP/level-ups -> state snapshot. Death takes priority; bonus choices precede clear,
## and can_clear requires all bosses dead and all bonus/level choices resolved. Normal queued levels open last.
##
## Pause protocol (4.4.2): step() does nothing unless `state` is PLAYING. For each queued level the job tree is checked
## first (CHOOSING_JOB + job_advance_pending when JobTree.should_offer), then CHOOSING_UPGRADE + choice_pending with
## cards drawn when the window opens. apply_job(id) adds an advancement draw; decline_job() skips it;
## apply_choice(id) applies the card and moves to the next queued level or back to PLAYING. They return false (and
## change nothing) when called in the wrong state or with an id that is not on offer.
##
## Events: every emitted Dictionary has `type` plus exactly the fields of EVENT_FIELDS[type]. `player_hit.damage` is the
## whole hit (the number shown), `mp_absorbed` the part Magic Guard paid with MP; `miss` hits spend neither and
## cause no knockback or invincibility. `choice_pending` card `rank` is the
## rank the card gives when taken. Swarm/projectile/pickup visuals are read from state (4.4.3).
##
## Player stats live in `player_state` (hp, mp, max_hp, max_mp, exp, level, job_id, str, dex, int, luk, pdd, mdd,
## avoid, acc, fortune (survivor card-tier stat, separate from LUK), invincible_t, action,
## action_t, action_scale, dead, plus exp_next = EXP needed for the next level); `action` is the body stance to draw
## ("dead", the cast stance while standing, else PlayerMotion.stance()), `action_t` seconds since it started,
## `action_scale` the fraction of the canonical frame time an attack stance plays in (attack speed). Main stats, W.DEF,
## M.DEF, acc, avoid and max HP/MP are totals: worn equipment's `inc*` adds on top of the base (equipment_bonus()).
##
## Live character state (docs/ARCHITECTURE.md 4.4): RunWorld owns the character's worn equipment and inventory
## (`equipment`, the Equipment state shape), `scrolls` and `mesos`. UI and bots change them only through these
## methods, which apply the pure Equipment functions, refresh the derived stats and emit `equipment_changed`; each
## returns "" on success or an Equipment reason (reqLevel, reqJob, reqSTR..., inventory_full, no_item, empty) and then
## changes nothing:
##   equip_item(inventory_index)  - wear an inventory item (v83 requirements against total stats)
##   unequip_item(slot)           - move a worn item to the inventory
##   discard_item(inventory_index) - destroy an inventory item (worn items cannot be discarded)
## Equipment drops (#109) come from kills and bosses (EquipmentDrops, equipment_drops.json); collecting one appends it
## to the inventory (`equipment_changed` action "pickup") while the Equip tab has room, otherwise it stays on the
## ground and `pickup_blocked` (reason inventory_full) is emitted. equips_dropped / equips_collected count them.
##   use_scroll(scroll_id, slot)  - scroll the item worn in an equip slot (Scrolls rules, #110): "" when the scroll was
##                                  used up (the result is the `scroll_used` event: success, failure or destroyed),
##                                  else no_item (none held) or a Scrolls refusal (scroll_type, scroll_slots, empty,
##                                  not_worn, scroll_unknown) and the scroll is kept
##   grant_scrolls(scroll_id, count) - add scrolls to the Use tab stacks (test hook until shops); returns how many fit
##   discard_scrolls(scroll_id)   - destroy a whole scroll stack
## Scroll shops (#111, Shop): shop_stock(npc_id) lists what a Free Market NPC sells this character's job; buy_scroll(npc_id,
## scroll_id, count), sell_item(inventory_index) and sell_scrolls(scroll_id, count) trade mesos for scrolls and spare
## equipment and return "" or a Shop reason (count, mesos, use_full, no_item, unsellable, not_sold), changing nothing then;
## each success emits equipment_changed (action "buy" / "sell"). Worn equipment is never sold (sell_item takes inventory
## indices; Shop.sell_worn is the refusal).
## change_job(200) grants and wears balance.player.weapon_grants' weapon (the Wooden Wand). weapon_id() is the worn
## weapon (0 bare-handed), weapon_attack() the W.ATT summed over all worn items.
##
## Separate seeded RNG streams keep e.g. card draws independent of damage rolls: 1 combat rolls, 2 spawning, 3 card
## draws, 4 drop pops, 5 basic-attack stances/damage/crits, 6 boss reward scatter, 7 potion drop rolls, 8 bot branch choices,
## 9 meso drop chance and amount rolls, 10 equipment drop chance, item and stat rolls, 11 scroll success and curse rolls,
## 12 Final Attack proc and follow-up damage/crit rolls; 13 Threaten (spec #165; no prop in v83, so unused),
## 14 reserved for Bowman,
## 15 Thief-only rolls (thief_rng, Steal success in #214),
## 16 Pirate-only rolls (pirate_rng, e.g. Oak Barrel's failure chance in #194).
## Each stream has exactly one owner.

const PLAYING := 0
const CHOOSING_JOB := 1
const CHOOSING_UPGRADE := 2
const DEAD := 3
const CLEARED := 4
const STATE_NAMES := ["PLAYING", "CHOOSING_JOB", "CHOOSING_UPGRADE", "DEAD", "CLEARED"]
## read_skill_cooldowns states of a skill icon: waiting for MP, or blocked by the held weapon (0 = normal).
const SKILL_STATE_MP_WAIT := 1
const SKILL_STATE_BLOCKED := 2

## Event type -> its fields (besides `type`), docs/ARCHITECTURE.md 4.4.3.
const EVENT_FIELDS := {
	"teleport": ["skill", "skill_id", "level", "phase", "pos", "facing", "effect"],
	"cast": ["skill", "skill_id", "level", "pos", "facing", "action", "effect"],
	"mp_short": ["skill", "skill_id", "required_mp", "mp"],
	"player_restored": ["stat", "amount", "skill", "pos"],
	"mp_eater_absorbed": ["mob", "amount", "skill", "pos"],
	"final_attack": ["skill", "skill_id", "level", "mob", "pos", "facing", "action", "effect"],
	"boss_skill": ["mob", "mob_id", "skill_id", "level", "pos", "facing", "action", "duration", "effect", "player_effect", "targets", "summon_effect", "recipient_effect"],
	"buff_cast": ["skill", "skill_id", "level", "duration"],
	"buff_expired": ["skill", "skill_id"],
	# #194: a buff cast with a failure chance (Oak Barrel) that failed; nothing started.
	"buff_failed": ["skill", "skill_id", "level"],
	"buff_pulse": ["skill", "skill_id", "amount"],
	"basic_attack": ["phase", "weapon_id", "action", "facing", "pos", "afterimage", "sound", "hit_after", "interval"],
	"mob_spawned": ["mob", "mob_id", "pos", "elite", "relocated_from"],
	"mob_hit": ["mob", "mob_id", "damage", "crit", "pos", "hit_visual", "skill"],
	"mob_status_applied": ["mob", "mob_id", "status", "duration"],
	"mob_status_expired": ["mob", "mob_id", "status"],
	"mob_died": ["mob", "mob_id", "pos", "exp", "elite"],
	"mob_revives_spawned": ["boss_index", "mob", "mob_id", "pos", "revives", "time"],
	"player_hit": ["damage", "mp_absorbed", "miss", "dir", "pos", "mob", "mob_id", "boss", "max_hp", "source_kind"],
	"player_jump": ["pos"],
	"portal_used": ["portal", "target", "pos"],
	"player_died": ["pos"],
	"pickup_spawned": ["pickup", "item_id", "pos", "kind", "potion_kind", "count"],
	"pickup_collected": ["pickup", "item_id", "exp", "pos", "kind", "potion_kind", "count", "collector"],
	"potion_used": ["kind", "item_id", "restored", "count"],
	# Spec #34 pet events (only with a pet out): its own drinks (never counted as the player's) and its teleports.
	"pet_potion_used": ["kind", "item_id", "restored", "count"],
	"pet_teleported": ["from", "pos"],
	"potion_tier_up": ["kind", "from_item_id", "item_id", "count"],
	"level_up": ["level"],
	"job_advance_pending": ["options"],
	"job_changed": ["job_id", "name"],
	"choice_pending": ["cards", "bonus", "advancement"],
	"upgrade_applied": ["id", "rank", "tier", "magnitude"],
	"skill_learned": ["skill", "skill_id"],
	"burst": ["count"],
	"stage_cleared": ["time"],
	"boss_warning": ["boss_index", "mob_id", "time"],
	"boss_spawned": ["boss_index", "mob", "mob_id", "pos", "time"],
	"boss_died": ["boss_index", "mob", "mob_id", "pos", "time"],
	"boss_attack": ["boss_index", "mob", "mob_id", "attack", "phase", "pos", "facing", "area", "time", "impact_time", "effect", "sound"],
	# #76 ordinary (non-boss) mobs: a mob attack's phases (as boss_attack). Ordinary mobs cast no mob skills.
	"mob_attack": ["mob", "mob_id", "attack", "phase", "pos", "facing", "area", "time", "impact_time", "effect", "sound"],
	"mob_projectile_spawned": ["proj", "mob", "mob_id", "pos", "velocity", "range", "speed", "ball", "hit", "time"],
	"mob_projectile_hit": ["proj", "mob", "mob_id", "pos", "hit", "facing", "time"],
	"mob_healed": ["mob", "mob_id", "skill_id", "level", "amount", "pos", "time"],
	"boss_teleported": ["boss_index", "mob", "mob_id", "pos", "time"],
	"equipment_changed": ["action", "slot", "item_id"],
	"pickup_blocked": ["pickup", "item_id", "pos", "reason"],
	"scroll_used": ["result", "scroll_id", "slot", "item_id"],
	# #155: the held ranged weapon's endless ammo moved to a higher tier (family, previous and new Item.wz id, character level).
	"ammo_upgraded": ["family", "from_item_id", "item_id", "level"],
	# #192: a Gunslinger Grenade thrown (a cluster skill): the ball flies from the hand `from` to `to` in `seconds`; the blast art
	# `burst` plays at `to` on arrival, when the sim strikes the mobs (the mob_hit events).
	"skill_thrown": ["skill", "skill_id", "from", "to", "seconds", "ball", "burst"],

}

## tier C defaults used when balance.json lacks a value.
const DEFAULT_BODY := Rect2(-14, -58, 28, 58)
const DEFAULT_CAST_HEIGHT := 30.0
## Shots leave this far in front of the cast origin, toward their target (the hand, not the face). tier C: ours.
const DEFAULT_CAST_FORWARD := 22.0
const DEFAULT_VIEW := Vector2(800, 600)
## tier B: pre-Big-Bang avoidability formula, Exoot 2009 (refs/research/v83-mechanics/notes.md).
const AVOID_DEX_FACTOR := 0.25
const AVOID_LUK_FACTOR := 0.5
## balance.regen fallback (PlayerUpkeep owns the pulse clock).
const DEFAULT_REGEN := PlayerUpkeep.DEFAULT_REGEN
## balance.hit_window fallback (tier C, spec #88; PlayerUpkeep owns the chain).
const DEFAULT_HIT_WINDOW := PlayerUpkeep.DEFAULT_HIT_WINDOW
## tier C: the survivor starter attributes; balance.player.stats overrides each one.
const DEFAULT_STATS := {"str": 12, "dex": 5, "int": 4, "luk": 4}
## balance.level_up_refill fallback: fraction of the new maximum restored per level-up. MP tier B (v83 servers refill
## it: Cosmic Character.levelUp calls changeHpMp(maxhp, maxmp)); HP tier C (owner choice: no heal on level-up).
const DEFAULT_LEVEL_UP_REFILL := {"hp": 0.0, "mp": 1.0}
## tier C: px between MobSkill 200 summons and revive offspring when balance.mob_skills has no summon_spacing.
const DEFAULT_SUMMON_SPACING := 24.0
## balance.player.inventory_slots fallback. tier A: a new v83 character's Equip tab has 24 slots.
const DEFAULT_INVENTORY_SLOTS := 24
## Grid candidates skill_box_count checks before it reads the whole query. Performance only, not behaviour (no
## tier): the count is the same for any value.
const BOX_PROBE := 16
## Buff effect stats of Hyper Body (percent of the whole Max HP / Max MP). Not the max_mp_percent passive: that one
## rescales current MP on growth, a buff leaves current HP/MP alone (spec #165 ticket #184).
const MAX_HP_PCT := "max_hp_pct" # tier B: percent of the whole maximum (GAME_DESIGN 11, Hyper Body); the values are tier A.
const MAX_MP_PCT := "max_mp_pct" # tier B: percent of the whole maximum (GAME_DESIGN 11, Hyper Body); the values are tier A.
## The buff stat both Power Guard skills feed (percent of contact damage). tier B: the String desc of the skill, a
## third-party v83 reimplementation.
const POWER_GUARD_STAT := "power_guard"
## The most one Power Guard reflect may take off a monster, as a fraction of its Max HP. tier B: only in the String desc
## of the skill (no WZ field), a third-party v83 reimplementation.
const POWER_GUARD_CAP := 0.10

var setup: Dictionary
var data: Dictionary
var balance: Dictionary
var stage: Dictionary
var stage_key := ""
var seed_value := 0
var duration := 900.0
## Combat rolls (damage, touch damage).
var rng: RandomNumberGenerator
var spawn_rng: RandomNumberGenerator
var card_rng: RandomNumberGenerator
var drop_rng: RandomNumberGenerator
var potion_rng: RandomNumberGenerator
var meso_rng: RandomNumberGenerator
var equip_rng: RandomNumberGenerator
var scroll_rng: RandomNumberGenerator
var reward_rng: RandomNumberGenerator
## Independent seeded branch choices do not perturb card, combat or careless-card streams.
var job_rng: RandomNumberGenerator
## Final Attack's proc and damage/crit rolls only (stream 12, #161).
var final_rng: RandomNumberGenerator
## Thief-only rolls (stream 15, #207): reserved for Steal's success chance (#214).
var thief_rng: RandomNumberGenerator
## Pirate-only rolls (stream 16, #186): today Oak Barrel's failure chance (#194). A future non-Pirate failure chance
## needs its own stream.
var pirate_rng: RandomNumberGenerator
## Boss bonus picks have priority and never consume progression.queue.
var pending_bonus_choices := 0
var choice_bonus := false

var physics: PhysicsConstants
var fhm: FootholdMap
var bounds := Rect2()
var ladders: LadderSet
var portals: PortalSet
var nav: NavGraph
var nav_jump: NavGraph
var player: PlayerMotion
var player_state := {}
var swarm: MobSwarm
var mob_kinds: Array = []
## Original mob id -> index in mob_kinds.
var kind_of_id := {}
## Per mob slot: 1 when the mob in it spawned as an elite.
var mob_elite := PackedByteArray()
## Per slot: schedule index for a boss, -1 for ordinary mobs.
var mob_boss := PackedInt32Array()
## Summoning encounter index, -1 for ordinary spawns; preserved through relocation and reset on new slot use.
var mob_summon_owner := PackedInt32Array()
var _live_mdd := PackedFloat32Array()
var _live_pdd := PackedFloat32Array()
var _live_physical_allowed := PackedByteArray()
## Canonical MDD/PDD per mob kind index (refreshed every tick for the live defense fill).
var _kind_mdd := PackedFloat64Array()
var _kind_pdd := PackedFloat64Array()
## Grid candidates of the latest _skill_box_matches query.
var _box_candidates := 0
var mob_grid: SpatialHash
var projectiles: ProjectileSystem
var pickups: PickupSystem
var potions: PotionInventory
var buffs := PlayerBuffs.new()
## Buff, invincibility, cast-hold and regeneration timers.
var upkeep: PlayerUpkeep
var book: SkillBook
var loadout: Loadout
var runner: SkillRunner
var _teleport_left := 0.0
var _teleport_total := 0.0
var progression: RunProgression
var jobs: JobTree
var upgrades: UpgradePool
var director: SpawnDirector
var mob_skills: MobSkillRunner
var bosses: BossDirector
var boss_attacks := BossAttacks.new()
## Ordinary mobs' canonical attacks and their per-slot stances (#76).
var mob_attacks: MobAttacks
var mob_actions := MobActions.new()
var mob_projectiles := MobProjectileSystem.new()

var events: Array = []
var time := 0.0
var kills := 0
## Character level when the round began (a carried character keeps its level); see levels_gained().
var start_level := 1
## Total damage the player dealt: shots, instant skill hits and nonlethal poison (read-only).
var damage_dealt: int:
	get:
		return projectiles.dealt + _instant_dealt + swarm.poison_dealt
var state := PLAYING
var view_size := DEFAULT_VIEW
## Player-centred logical view clamped to the bounds (spawn logic keeps mobs outside it).
var view := Rect2()
## WZ paths referenced by ProjectileSystem.visual (and hit visuals); append-only.
var visual_paths: Array = []
## The weapon path the first job was taken with (JobTree.paths_of id: "claw", "dagger", ...; "" = none). Set by
## change_job/apply_job, carried by the snapshot's optional `weapon_path` key (spec #151 #157).
var weapon_path := ""
## The ammo item the held ranged weapon uses (0 for a melee weapon or bare hands), derived from the weapon family, job and
## level by _sync_ammo; never saved, never consumed (Ammo, spec #151 #155).
var _ammo_id := 0
var _ammo_family := ""
## Options / cards of the open window.
var pending_jobs: Array = []
var pending_cards: Array = []
## True while the extra new-job skill draw is open; it does not consume a queued level or boss reward.
var choice_advancement := false
## Card draws in a row that offered no power card (UpgradePool pity).
var power_dry := 0
## Offered cards / selected cards per displayed tier, counting cards once rather than the steps they grant.
var card_tiers_offered := UpgradePool.empty_tier_counts()
var card_tiers_picked := UpgradePool.empty_tier_counts()
## Setup problems the sim worked around (e.g. a pool mob without a mob img).
var warnings := PackedStringArray()
## Largest feet-to-body-box-corner distance over all mob kinds (pads feet-point hash queries).
var body_pad := 64.0
var magnet_r := 90.0
## Additional HP/MP per regeneration pulse; Recovery's separate PlayerBuffs timeline heals independently.
var hp_regen := 0.0
var mp_regen := 0.0
var player_pdd := 0.0
var player_mdd := 0.0
var player_avoid := 0.0
## Job-base accuracy plus worn equipment (incACC); buffs add on top in the caster and presentation totals.
var player_acc := 0.0
var body := DEFAULT_BODY
var cast_height := DEFAULT_CAST_HEIGHT
var cast_forward := DEFAULT_CAST_FORWARD
## Tests and benchmarks only: the player takes no touch damage.
var god := false

var _hp := 0.0
var _hit_listeners: Array[Callable] = []
## Final Attack follow-ups won by _final_attack_hit, played after the tick's attacks: {slot, identity, skill}.
var _final_queue: Array[Dictionary] = []
## Owned Final Attack skill keys, rebuilt when the loadout's version changes.
var _final_keys: Array[String] = []
var _final_keys_version := -1
var _mp := 0.0
var _max_hp := 1
var _max_mp := 0
## The Hyper Body percentages (x = Max HP, y = Max MP) already inside _max_hp/_max_mp; a change refreshes the maxima.
var _max_buff_applied := Vector2.ZERO
var _base_hp := 50.0
var _base_mp := 5.0
var _job_mp := 0.0
var _base_stats := DEFAULT_STATS.duplicate()
var _attributes := {}
var _earned_ap := 0
var _base_fortune := 0.0
## Spec #34 cash items. `setup.account` ({owned: [item ids]}, absent = an empty account) decides which of the
## character's worn cash equipment and pet count; `setup.alert` ({hp, mp}: fractions of max, 0 = do not alert).
## worn_cash: {slot: id} of the cash slots actually filled by owned items; pet: the owned pet species out (0 = none);
## cash_fortune: the Fortune those slots add, computed live and added to player_state.fortune, never stored in the
## character; account_owned: the owned item ids; alert: {hp, mp}.
var account_owned: Array = []
var worn_cash := {}
var pet := 0
var cash_fortune := 0.0
var alert := {"hp": 0.0, "mp": 0.0}
## The pet simulation (PetSystem), null when no owned pet is out. See pet_state() and pet_has().
var pet_system: PetSystem
var _cash_carried := {}
var _pet_carried := 0
var _catalog: CashCatalog
## Carried appearance {skin, face, hair}; worn equipment is drawn over it (DataRepo.character_look).
var character_look := {}
## Worn equipment and inventory (Equipment state); change it only through equip_item/unequip_item/discard_item.
var equipment := Equipment.empty_state()
## Scroll stacks: {"<scroll item id>": count}.
var scrolls := {}
var mesos := 0
## Equipment drops spawned and picked up this round (balance records, #109).
var equips_dropped := 0
var equips_collected := 0
var _equipment_speed := 0.0
var _equipment_jump := 0.0
var _dead := false
var basic: BasicAttack
var basic_rng: RandomNumberGenerator
var _action := ""
var _action_t := 0.0
var _job_checked := false
var _instant_dealt := 0
var _ctx := {}
var _visual_ids := {}
var _touch_buf := PackedInt32Array()


func _init(p_setup: Dictionary = {}) -> void:
	setup = p_setup
	data = setup.get("data", {})
	balance = data.get("balance", {})
	stage_key = String(setup.get("stage", ""))
	stage = data.get("stages", {}).get("stages", {}).get(stage_key, {})
	duration = float(stage.get("duration", 900.0))
	seed_value = int(setup.get("seed", 0))
	view_size = setup.get("view_size", DEFAULT_VIEW)
	_init_rng_streams()
	_init_map()
	_init_mobs()
	_init_drops_and_shots()
	_init_skills_and_progression()
	_init_directors()
	_init_player_motion()
	_init_player()
	start_level = progression.level
	add_hit_listener(_mp_eater_hit)
	add_hit_listener(_final_attack_hit)
	add_hit_listener(_steal_hit)
	update_view()
	_write_player_state(0.0)


## One seeded stream per owner (see the header).
func _init_rng_streams() -> void:
	rng = _stream(1)
	basic_rng = _stream(5)
	spawn_rng = _stream(2)
	card_rng = _stream(3)
	drop_rng = _stream(4)
	potion_rng = _stream(7)
	reward_rng = _stream(6)
	job_rng = _stream(8) # tier C: independent bot branch stream, #53.
	meso_rng = _stream(9) # tier C: meso rolls never shift another stream, #107.
	equip_rng = _stream(10) # tier C: equipment rolls never shift another stream, #109.
	scroll_rng = _stream(11) # tier C: scroll success/curse rolls never shift another stream, #110.
	final_rng = _stream(12) # tier C: Final Attack procs and follow-up rolls never shift another stream, #161.
	thief_rng = _stream(15) # tier C: independent Thief-only rolls; reserved for Steal success, #207/#214.
	pirate_rng = _stream(16) # tier C: Pirate-only rolls never shift another stream; 14 reserved, #186.


## Physics, footholds, bounds, ropes, portals and the two mob navigation graphs from the map img.
func _init_map() -> void:
	var map_img: Dictionary = setup.get("map_img", {})
	physics = PhysicsConstants.from_wz(setup.get("physics_img", {}))
	fhm = FootholdMap.from_wz(map_img)
	bounds = MapBounds.from_map(map_img, fhm)
	ladders = LadderSet.from_wz(map_img)
	portals = PortalSet.from_wz(map_img, int(stage.get("map_id", 0)), balance.get("portals", {}))
	var nav_opts := {"gravity": physics.gravity_acc, "fall_speed": physics.fall_speed, "jump_speed": physics.jump_speed}
	nav = NavGraph.build(fhm, nav_opts.merged({"can_jump": false}))
	nav_jump = NavGraph.build(fhm, nav_opts.merged({"can_jump": true}))


## Mob kinds, the swarm with its per-slot arrays, its spatial hash and its step context.
func _init_mobs() -> void:
	_build_mob_kinds()
	body_pad = ProjectileSystem.max_body_extent(mob_kinds)
	swarm = MobSwarm.new(256, mob_kinds, balance.get("mob_motion", {}))
	swarm.fhm = fhm
	mob_elite.resize(swarm.capacity())
	mob_boss.resize(swarm.capacity())
	mob_boss.fill(-1)
	mob_grid = SpatialHash.new(64.0, bounds.grow(64.0))
	_ctx = {"fhm": fhm, "nav": nav, "nav_jump": nav_jump, "bounds": bounds, "physics": physics,
		"target": Vector2.ZERO, "target_fh": -1, "speed_mult": 1.0}


## Player shots, EXP/potion drops and the potion stock.
func _init_drops_and_shots() -> void:
	projectiles = ProjectileSystem.new(64, rng)
	projectiles.paths = visual_paths
	projectiles.alt_rng = basic_rng # the ranged basic attack's shots roll on stream 5, like its instant swings
	projectiles.bounds = bounds
	projectiles.magic_defense_k = float(balance.get("magic_defense_k", CombatMath.MAGIC_DEFENSE_K))
	var pk: Dictionary = balance.get("pickup", {}).duplicate()
	pk["collect_radius"] = float(balance.get("collect_radius", PickupSystem.TUNING_DEFAULTS.collect_radius))
	pk["gravity"] = physics.gravity_acc
	pk["fall_speed"] = physics.fall_speed
	pickups = PickupSystem.new(128, pk, drop_rng)
	potions = PotionInventory.new(balance.get("potions", {}), setup.get("item_info", {}))


## Skill book, loadout, casters, EXP curve, job tree and upgrade cards.
func _init_skills_and_progression() -> void:
	book = SkillBook.from_data(data.get("skills", {}), setup.get("skill_imgs", {}))
	loadout = Loadout.new(book)
	var crit: Dictionary = balance.get("crit", {})
	loadout.crit_chance = float(crit.get("chance", 0.0))
	loadout.crit_mult = float(crit.get("mult", 1.5))
	loadout.crit_per_acc = float(crit.get("per_acc", 0.0))
	runner = SkillRunner.new()
	basic = BasicAttack.new(setup.get("body_img", {}), setup.get("afterimage_imgs", {}))
	progression = RunProgression.new(ExpCurve.from_data(balance.get("exp_curve", {})),
		int(balance.get("max_level", 200)))
	jobs = JobTree.from_data(data.get("jobs", {}), data.get("jobs_survivor", {}))
	upgrades = UpgradePool.from_data(data.get("upgrades", {}))


## Ordinary spawning, the boss schedule and the bosses' canonical skills.
func _init_directors() -> void:
	director = SpawnDirector.create(stage, kind_of_id, balance.get("spawn", {}))
	bosses = BossDirector.new(stage.get("bosses", []), balance.get("bosses", {}))
	mob_skills = MobSkillRunner.new(setup, balance.get("mob_skills", {}))
	mob_attacks = MobAttacks.new(self)
	_sync_slots()


## The player's movement model (with the survivor knockback) and per-tick timers.
func _init_player_motion() -> void:
	var kb: Dictionary = balance.get("knockback", {})
	player = PlayerMotion.new(physics, {
		"knockback_speed": float(kb.get("speed", 187.5)), "knockback_hop": float(kb.get("hop", 200.0)),
		"knockback_lock": float(kb.get("lock", 0.3)),
	})
	upkeep = PlayerUpkeep.new(buffs, balance.get("regen", DEFAULT_REGEN), balance.get("hit_window", DEFAULT_HIT_WINDOW))


## Name of the current state ("PLAYING", ...).
func state_name() -> String:
	return STATE_NAMES[state]


## Returns independent round-boundary data; unresolved rewards/jobs/advancement draws are an error, never dropped.
## In release returns {} after push_error; debug also asserts so callers cannot silently discard a choice.
func character_snapshot() -> Dictionary:
	if state in [CHOOSING_JOB, CHOOSING_UPGRADE] or progression.has_pending() or pending_bonus_choices > 0 \
			or choice_bonus or choice_advancement or not pending_jobs.is_empty() or not pending_cards.is_empty():
		push_error("RunWorld.character_snapshot: a character choice is pending")
		assert(false, "RunWorld.character_snapshot: a character choice is pending")
		return {}
	var skills := {}
	for key: String in loadout.order:
		skills[key] = {"rank": loadout.rank(key),
			"mods": CharacterSnapshot.encode_mods(loadout.skill_mods.get(key, {}))}
	var snapshot := {"format": CharacterSnapshot.FORMAT, "level": progression.level, "exp": progression.exp,
		"job_id": progression.job_id, "attributes": _attributes.duplicate(),
		"base_attributes": _base_stats.duplicate(), "earned_ap": _earned_ap,
		"base_hp": _base_hp, "base_mp": _base_mp, "job_mp": _job_mp,
		"skills": skills, "skill_order": loadout.order.duplicate(),
		"player_mods": CharacterSnapshot.encode_mods(loadout.player_mods),
		"card_ranks": loadout.card_ranks.duplicate(), "potions": potions.snapshot(),
		"fortune": _own_fortune(), "base_fortune": _base_fortune,
		"look": character_look.duplicate(true), "equipment": equipment.duplicate(true),
		"scrolls": scrolls.duplicate(), "mesos": mesos}
	if weapon_path != "":
		snapshot["weapon_path"] = weapon_path
	# Spec #34 optional keys: written only when set, so characters without cash items keep their exact old bytes.
	if not _cash_carried.is_empty():
		snapshot["cash"] = _cash_carried.duplicate()
	if _pet_carried > 0:
		snapshot["pet"] = _pet_carried
	return snapshot


## The character's own Fortune (base plus card modifiers), without the live cash-slot part.
func _own_fortune() -> float:
	return maxf(0.0, loadout.player_stat("fortune", _base_fortune))


## Levels the character gained in this round (queued level-ups included).
func levels_gained() -> int:
	return maxi(0, progression.level - start_level)


## Scheduled bosses killed so far in this round.
func bosses_killed() -> int:
	return bosses.dead_count()


## NX this round pays now (spec #34, NxAward): the tier's clear bonus only when CLEARED, plus levels and bosses.
## Tools record it as `nx_awarded`; only Flow credits it, at the round boundary or the run archive.
func nx_awarded() -> int:
	return NxAward.compute(balance.get("nx_award", {}), NxAward.tier_of(data.get("stages", {}), stage_key),
		state == CLEARED, levels_gained(), bosses_killed())


## Boss stages finish after every scheduled boss dies; unscheduled stages retain the duration clear.
## Reward/choice tickets may defer this decision until their pending rewards have been answered.
func can_clear() -> bool:
	if bosses.has_bosses():
		return bosses.all_dead() and pending_bonus_choices == 0 and not choice_bonus and not progression.has_pending()
	return time >= duration - 1e-6


## Drinks one HP or MP potion instantly while playing, including on ropes; false when stock or spec is unavailable.
func drink_potion(kind: String) -> bool:
	return _drink(kind, false)


## The shared drink: `by_pet` counts it in the pet's totals and reports `pet_potion_used` instead of `potion_used`.
func _drink(kind: String, by_pet: bool) -> bool:
	if state != PLAYING or _dead:
		return false
	var sip := potions.consume(kind, by_pet)
	if sip.is_empty():
		return false
	var before := int(player_state[kind])
	if kind == "hp":
		_hp = minf(_max_hp, _hp + int(sip.amount))
	else:
		_mp = minf(_max_mp, _mp + int(sip.amount))
	_write_player_state(0.0)
	emit("pet_potion_used" if by_pet else "potion_used", {"kind": kind, "item_id": int(sip.item_id),
		"restored": int(player_state[kind]) - before, "count": int(sip.count)})
	return true


## Upgrades a potion kind's current item, preserving stock and exposing the new icon/restoration immediately.
func upgrade_potion(kind: String, item_id: int) -> bool:
	var from_id := int(potions.stock.get(kind, {}).get("item_id", 0))
	if not potions.upgrade(kind, item_id):
		return false
	_write_player_state(0.0)
	emit("potion_tier_up", {"kind": kind, "from_item_id": from_id, "item_id": item_id,
		"count": int(potions.stock[kind].count)})
	return true


## Drops a bundle of the current HP/MP tier, including boss rewards; potion slots never consume the EXP drop cap.
func spawn_potion(kind: String, pos: Vector2, count: int = 1) -> int:
	if not potions.stock.has(kind):
		return -1
	var id := int(potions.stock[kind].item_id)
	var slot := pickups.spawn_potion(pos, count, id, kind)
	if slot >= 0:
		emit("pickup_spawned", {"pickup": slot, "item_id": id, "pos": pos,
			"kind": "potion", "potion_kind": kind, "count": count})
	return slot



## Whether an inactive buff meets its optional survivor HP threshold; casting/cooldown gates remain in SkillRunner.
func can_start_buff(skill: String, stats: Dictionary) -> bool:
	var threshold := float(stats.hp_threshold)
	return not buffs.has(skill) and (threshold <= 0 or _hp < float(_max_hp) * threshold)


## The whole HP paid by one HP-to-MP conversion of resolved stats `st`: its `pay` share of MaxHP rounded to whole points,
## at least 1 (tier C: the rounding; the shares are canonical, docs/GAME_DESIGN.md 7.16).
func conversion_hp(st: Dictionary) -> int:
	return maxi(1, roundi(float(_max_hp) * float(st.conversion.get("pay", 0.0))))


## Whether a `self` cast (SkillRunner) of resolved stats `st` is admitted now: the cast block's survivor conditions hold
## (`mp_below`: MP under that fraction of MaxMP; `hp_at_least`: HP at least that fraction of MaxHP, both before paying;
## an absent or zero key is not checked) and a conversion's HP payment would leave the character alive.
func self_cast_ready(st: Dictionary) -> bool:
	var params: Dictionary = st.cast_params
	var mp_below := float(params.get("mp_below", 0.0))
	if mp_below > 0.0 and not _mp < float(_max_mp) * mp_below:
		return false
	var hp_at_least := float(params.get("hp_at_least", 0.0))
	if hp_at_least > 0.0 and _hp < float(_max_hp) * hp_at_least - 1e-6:
		return false
	return (st.conversion as Dictionary).is_empty() or can_pay_hp(conversion_hp(st))


## Pays a conversion's HP and returns the MP it gives (`gain` of the HP paid, whole points down), as player_restored
## reports it; the MP is clamped to MaxMP. Returns 0 and changes nothing when the payment would leave 0 HP.
func convert_hp_to_mp(key: String, st: Dictionary) -> int:
	var paid := conversion_hp(st)
	if not spend_hp(paid):
		return 0
	return restore_player("mp", floori(float(paid) * float(st.conversion.get("gain", 0.0)) + 1e-6), key)


## Whether the character is Hidden (docs/GAME_DESIGN.md 7.18): an active buff makes monsters, bosses included, ignore
## the character and stops its attacks. Oak Barrel (#194) and Thief Dark Sight (#167) use it.
func is_hidden() -> bool:
	return buffs.hidden()


## The Morph.wz id the character is drawn as while a morphing buff is active, 0 for the plain avatar.
func morph_id() -> int:
	return buffs.morph()


## Starts a resolved timed buff; SkillRunner pays MP and applies the shared casting gate before this call. A buff with a
## `fail_chance` (Oak Barrel: Skill.wz `prop`, tier A) rolls it once on the Pirate stream 16 first (every `fail_field`
## buff draws it, so a future non-Pirate failure chance needs its own stream) and, when the cast fails, starts nothing and
## emits `buff_failed`. Returns whether the buff started.
func start_buff(skill: String, stats: Dictionary) -> bool:
	if float(stats.get("fail_chance", 0.0)) > 0.0 and pirate_rng.randf() < float(stats.fail_chance):
		emit("buff_failed", {"skill": skill, "skill_id": int(stats.skill_id), "level": int(stats.level)})
		return false
	buffs.start(skill, stats)
	_refresh_caster()
	refresh_player_speed()
	_refresh_max_buffs()
	emit("buff_cast", {"skill": skill, "skill_id": int(stats.skill_id), "level": int(stats.level),
		"duration": float(stats.duration)})
	_write_player_state(0.0)
	return true


## Returns the pending events and clears the list (what the presentation does every frame).
func drain_events() -> Array:
	var out := events
	events = []
	return out


## Appends an event of `type` with `fields` (exactly EVENT_FIELDS[type]).
func emit(type: String, fields: Dictionary) -> void:
	var e := {"type": type}
	e.merge(fields)
	events.append(e)


## Advances the run by dt seconds with the player's input (no-op unless PLAYING).
func step(dt: float, input: MoveInput) -> void:
	if state != PLAYING:
		return
	time += dt
	refresh_player_speed()
	_step_player(dt, input)
	_step_monsters(dt)
	_step_player_attacks(dt)
	if pet_system != null:
		_step_pet(dt)
	var got := _step_pickups(dt)
	_touch()
	if got > 0 and not _dead:
		_gain_exp(got)
	_write_player_state(dt)
	_end_tick()


## Drinks, then a same-map portal warp or ordinary movement, the view, and the player's timers.
func _step_player(dt: float, input: MoveInput) -> void:
	_teleport_left = maxf(0.0, _teleport_left - dt)
	if input.drink_hp:
		drink_potion("hp")
	if input.drink_mp:
		drink_potion("mp")
	_try_manual_buffs(input)
	if not _try_teleport(input) and not _take_portal(dt, input):
		var flags := player.step(dt, input, fhm, ladders, bounds)
		if flags & PlayerMotion.EV_JUMP:
			emit("player_jump", {"pos": player.pos})
	update_view()
	_tick_timers(dt)


## The skill keys of the manual skills the character has learned (Key Config lists exactly these): one
## {action, name, icon, skill} per skill key id in learning order, whatever weapon is held. The id is the skill's
## `skill_key` and the name of its input action ("teleport", "dash"); Teleport's three job-line variants share one.
func manual_skill_keys() -> Array:
	var out: Array = []
	var seen := {}
	for key: String in loadout.order:
		var id := skill_key_of(key)
		if id == "" or seen.has(id):
			continue
		seen[id] = true
		var d := book.def(key)
		out.append({"action": id, "name": String(d.get("name", key)), "icon": String(d.get("icon", "")), "skill": key})
	return out


## The skill key id of skill `key` ("" when it is not a manual skill).
func skill_key_of(key: String) -> String:
	var d: Variant = book.defs.get(key)
	return String((d as Dictionary).get("skill_key", "")) if d is Dictionary else ""


## Owned manual skill of skill key `id` that the held weapon can use (SkillBook.usable_with), or "".
func manual_skill(id: String) -> String:
	var held := held_weapon_family()
	for key: String in loadout.order:
		if skill_key_of(key) == id and book.usable_with(key, held):
			return key
	return ""


## Owned branch Teleport key the held weapon can use (SkillBook.usable_with), or empty before learning it or while the
## weapon blocks it: a weapon-gated manual skill neither casts nor is offered to the bot.
func teleport_skill() -> String:
	var held := held_weapon_family()
	for key: String in loadout.order:
		if _is_teleport(key) and book.usable_with(key, held):
			return key
	return ""


## Whether an owned Teleport can currently be paid for (also used by the HUD and autoplay).
func teleport_affordable() -> bool:
	var key := teleport_skill()
	return key != "" and _mp >= int(runner.stats_of(self, key).mp_cost)


## HUD readiness of an owned skill: `left` seconds until ready (>= 0), the cooldown `total` set at its last cast
## (0 before any), `mp_short` (ready and would cast, but MP is below its cost) and `blocked` (the held weapon cannot use
## the skill, SkillBook.usable_with; it is then never mp_short). Teleport reports its repeat timer.
func skill_readiness(key: String) -> Dictionary:
	var blocked := not book.usable_with(key, held_weapon_family())
	return {"left": _cooldown_left(key), "total": _cooldown_total(key),
		"mp_short": not blocked and _mp_short(key), "blocked": blocked}


## The HUD's per-frame readiness of every owned skill, in loadout.order, written into the caller's reused buffers
## (resized in place; nothing is allocated once they have the right size): left and total as skill_readiness reports
## them, and `state` per skill (SKILL_STATE_*): 0 normal, 1 waiting for MP, 2 blocked by the held weapon.
func read_skill_cooldowns(left: PackedFloat32Array, total: PackedFloat32Array, state: PackedByteArray) -> void:
	var n := loadout.order.size()
	left.resize(n)
	total.resize(n)
	state.resize(n)
	var held := held_weapon_family()
	for i in n:
		var key: String = loadout.order[i]
		left[i] = _cooldown_left(key)
		total[i] = _cooldown_total(key)
		state[i] = SKILL_STATE_BLOCKED if not book.usable_with(key, held) \
			else SKILL_STATE_MP_WAIT if _mp_short(key) else 0


## Pressing (or holding) the skill key of a manual buff such as Dash casts it: it needs no cooldown left, no active
## copy, a free casting state and the MP; otherwise the press does nothing (no event, no MP spent). Teleport has
## its own handler (_try_teleport).
func _try_manual_buffs(input: MoveInput) -> void:
	if input.skills_pressed.is_empty() and input.skills_held.is_empty():
		return
	for id: String in input.skills_pressed.keys() + input.skills_held.keys():
		var key := manual_skill(id)
		if key != "" and not _is_teleport(key) and book.kind(key) == "buff" and can_cast():
			runner.cast_manual_buff(self, key)


func _is_teleport(key: String) -> bool:
	var d: Variant = book.defs.get(key)
	return d is Dictionary and (d as Dictionary).has("teleport")


func _cooldown_left(key: String) -> float:
	if _is_teleport(key):
		return _teleport_left
	return maxf(0.0, float(runner.cooldowns.get(key, 0.0)))


func _cooldown_total(key: String) -> float:
	if _is_teleport(key):
		return _teleport_total
	return float(runner.cooldown_totals.get(key, 0.0))


func _mp_short(key: String) -> bool:
	if _is_teleport(key):
		return _teleport_left <= 1e-6 and key == teleport_skill() and not teleport_affordable()
	if String(book.def(key).get("skill_key", "")) != "":
		# A manual buff waits for MP whenever its key could be pressed but could not pay.
		return _cooldown_left(key) <= 1e-6 and not buffs.has(key) and _mp < float(runner.stats_of(self, key).mp_cost)
	return _cooldown_left(key) <= 1e-6 and runner.is_waiting_mp(key) \
		and _mp < float(runner.stats_of(self, key).mp_cost)


func _try_teleport(input: MoveInput) -> bool:
	if not input.skill_requested("teleport") or _teleport_left > 1e-6 or not can_cast():
		return false
	var key := teleport_skill()
	if key == "":
		return false
	var stats := runner.stats_of(self, key)
	# tier C: vertical intent wins a diagonal; opposing keys cancel, then fall back to facing.
	var vertical := int(input.down) - int(input.up)
	var direction := Vector2(0, vertical) if vertical != 0 else Vector2(input.dir(), 0)
	if direction == Vector2.ZERO:
		direction.x = player.facing
	var dest := player.teleport_destination(direction, float(stats.teleport_range), fhm, bounds)
	if dest.is_empty() or not spend_mp(int(stats.mp_cost)):
		return false
	var departure := player.pos
	player.place(dest.pos, fhm)
	if direction.x != 0:
		player.facing = int(direction.x)
	_teleport_left = float(stats.repeat_delay)
	_teleport_total = _teleport_left
	for phase: String in ["departure", "arrival"]:
		emit("teleport", {"skill": key, "skill_id": int(stats.skill_id), "level": int(stats.level),
			"phase": phase, "pos": departure if phase == "departure" else player.pos,
			"facing": player.facing, "effect": String(stats.effect)})
	return true


## Holding Up in a same-map portal's box places the player at its destination (emits portal_used); true when warped.
func _take_portal(dt: float, input: MoveInput) -> bool:
	var warp := portals.step(dt, player.pos, input.up)
	if warp.is_empty():
		return false
	player.place(warp.pos, fhm)
	emit("portal_used", warp)
	return true


## Swarm movement, the boss lifecycle, boss skills/attacks, monster balls, ordinary spawns and the mob hash.
func _step_monsters(dt: float) -> void:
	_ctx.target = player.pos
	_ctx.target_fh = player.fh
	_ctx.speed_mult = director.value_at("speed", time)
	# Hidden (#194): the swarm gets no target to chase, so ground mobs patrol and flyers hover.
	_ctx["hidden"] = is_hidden()
	_ctx["boss_actions"] = mob_actions.view(bosses.prepare_actions(self), bosses, swarm, time)
	_ctx["events"] = events
	swarm.step(dt, _ctx)
	bosses.step(self, dt)
	mob_skills.step(self)
	boss_attacks.step(self)
	mob_attacks.step(self, dt)
	mob_projectiles.step(dt, self)
	director.step(dt, self)
	_sync_slots()
	mob_grid.rebuild(swarm.x, swarm.y, swarm.active, swarm.capacity())


## Auto-casts, the basic swing, then the player's shots against live defense/immunity; kills drop their rewards.
func _step_player_attacks(dt: float) -> void:
	runner.step(dt, self)
	basic.step(dt, self)
	_fill_live_defense()
	projectiles.step(dt, swarm, mob_grid, events, _live_mdd, _live_physical_allowed, _on_player_hit, _live_pdd)
	for m in projectiles.kills:
		_on_kill(m)
	_play_final_attacks()


## Live MDD, PDD and physical_hit_allowed(slot) of every live slot, for the shots, in one pass (#146).
func _fill_live_defense() -> void:
	_live_mdd.resize(swarm.capacity())
	_live_pdd.resize(swarm.capacity())
	_live_physical_allowed.resize(swarm.capacity())
	_kind_mdd.resize(mob_kinds.size())
	_kind_pdd.resize(mob_kinds.size())
	for k in mob_kinds.size():
		_kind_mdd[k] = float((mob_kinds[k] as MobKind).mdd)
		_kind_pdd[k] = float((mob_kinds[k] as MobKind).pdd)
	mob_skills.fill_live_defense(swarm.active, swarm.kind, _kind_mdd, swarm.capacity(), time, _live_mdd,
		_live_physical_allowed, _kind_pdd, _live_pdd)
	swarm.lower_threatened_pdd(_live_pdd) # Threaten (#183): the same cut mob_defense applies


## Moves and collects drops; collected potions join the stock. Returns the EXP collected this tick.
func _step_pickups(dt: float) -> int:
	var equip_room := maxi(0, inventory_slots() - equipment.inventory.size())
	var got := 0
	if pet_system == null:
		got = pickups.step(dt, player.pos, magnet_r, fhm, events, equip_room)
	else:
		got = pickups.step(dt, player.pos, magnet_r, fhm, events, equip_room, pet_system.center(),
			pet_system.pickup_radius(), pet_system.abilities.vac)
		pet_system.pickups += pickups.pet_collected
	for kind: String in pickups.collected_potions:
		potions.add(kind, int(pickups.collected_potions[kind]))
	mesos += pickups.step_mesos
	for instance: Dictionary in pickups.collected_equipment:
		equipment.inventory.append(instance)
		equips_collected += 1
		_equipment_changed("pickup", "", int(instance.id))
	return got


## The pet's tick: movement, then its auto-potion drinks (below the ALERT level, from the shared stock).
func _step_pet(dt: float) -> void:
	pet_system.step(dt, player, fhm, bounds, pickups, events, maxi(0, inventory_slots() - equipment.inventory.size()))
	for kind: String in ["hp", "mp"]:
		var current := _hp if kind == "hp" else _mp
		var maximum := _max_hp if kind == "hp" else _max_mp
		if pet_system.should_drink(kind, current, maximum, float(alert[kind])) and _drink(kind, true):
			pet_system.drank(kind)


## What the pet looks like right now ({} without a pet): species, pos (feet), facing (-1/1), action (stand, move, jump,
## hang), fetching, abilities. Position jumps are announced by `pet_teleported` events.
func pet_state() -> Dictionary:
	return pet_system.view() if pet_system != null else {}


## Whether a pet with `ability` (auto_hp, auto_mp, wing_boots, binocular, vac) is out.
func pet_has(ability: String) -> bool:
	return pet_system != null and bool(pet_system.abilities.get(ability, false))


## After a living tick: boss bonus choices first, then the clear, then queued level-ups.
func _end_tick() -> void:
	if _dead:
		return
	if pending_bonus_choices > 0:
		_advance_queue()
		if state != PLAYING:
			return
	if can_clear():
		state = CLEARED
		emit("stage_cleared", {"time": time})
		return
	if progression.has_pending():
		_advance_queue()


## Takes job `job_id` (with weapon `path` when the window lists the job per path) from the open advancement window;
## false when not on offer or not available.
func apply_job(job_id: int, path := "") -> bool:
	if state != CHOOSING_JOB:
		return false
	var ok := false
	for o: Dictionary in pending_jobs:
		if int(o.job_id) == job_id and String(o.get("path", "")) == path and bool(o.available):
			ok = true
	if not ok:
		return false
	pending_jobs = []
	change_job(job_id, path)
	choice_bonus = false
	choice_advancement = true
	pending_cards = upgrades.roll_advancement_choices(self, card_rng)
	state = CHOOSING_UPGRADE
	emit("choice_pending", {"cards": pending_cards.duplicate(true), "bonus": false, "advancement": true})
	return true


## "Not now": keeps the current job and continues to the level's upgrade choice.
func decline_job() -> bool:
	if state != CHOOSING_JOB:
		return false
	pending_jobs = []
	state = PLAYING
	_advance_queue()
	return true


## Applies card `card_id` from the open choice window and continues with the next queued level (or play).
func apply_choice(card_id: String) -> bool:
	if state != CHOOSING_UPGRADE:
		return false
	var selected := {}
	for c: Dictionary in pending_cards:
		if String(c.id) == card_id:
			selected = c
	if selected.is_empty():
		return false
	if upgrades.apply(card_id, self, String(selected.get("tier", "normal"))) == 0:
		return false
	var tier := String(selected.get("tier", "normal"))
	card_tiers_picked[tier] += 1
	pending_cards = []
	if choice_advancement:
		choice_advancement = false
	elif choice_bonus:
		pending_bonus_choices -= 1
		choice_bonus = false
	else:
		progression.pop_front()
		_job_checked = false
	state = PLAYING
	_advance_queue()
	_write_player_state(0.0)
	return true


## Changes the job and its Max HP / Max MP grants, without learning skills; emits job_changed. grants.max_mp is
## kept apart in `_job_mp`; grants.max_hp joins `_base_hp` (the snapshot's base_hp), the same pool level growth feeds, so
## it survives a save/Continue without a new CharacterSnapshot field. A known weapon `path` of the job's line is
## recorded in `weapon_path`; the weapon the job grants is worn by _grant_job_weapon, its `grants.items` join the Equip tab
## by _grant_job_items.
func change_job(job_id: int, path := "") -> void:
	progression.job_id = job_id
	if path != "" and not jobs.path_of(job_id, path).is_empty():
		weapon_path = path
	var j := jobs.job(job_id)
	var grants: Dictionary = j.get("grants", {})
	_base_hp += float(grants.get("max_hp", 0.0))
	_job_mp += float(grants.get("max_mp", 0.0))
	refresh_player_stats()
	emit("job_changed", {"job_id": job_id, "name": jobs.name_of(job_id)})
	_grant_job_weapon(job_id, path)
	_grant_job_items(job_id, path)


## Learns a skill (emits skill_learned); false when unknown or owned.
func learn_skill(key: String) -> bool:
	if not loadout.add_skill(key):
		return false
	emit("skill_learned", {"skill": key, "skill_id": book.skill_id(key)})
	refresh_player_stats()
	return true


## Restores `fraction` of max HP (stat "hp") or MP (stat "mp").
func heal_fraction(stat: String, fraction: float) -> void:
	if stat == "hp":
		_hp = minf(_max_hp, _hp + fraction * _max_hp)
	elif stat == "mp":
		_mp = minf(_max_mp, _mp + fraction * _max_mp)
	_write_player_state(0.0)


## Whether spend_mp(amount) would succeed now (nothing is paid).
func mp_affordable(amount: int) -> bool:
	return not (_mp < maxi(0, amount))


## Pays an action's MP cost; unaffordable actions leave the pool unchanged.
func spend_mp(amount: int) -> bool:
	var cost := maxi(0, amount)
	if not mp_affordable(cost):
		return false
	_mp -= cost
	_write_player_state(0.0)
	return true


## Whether paying `amount` HP would leave the player alive (HP above the cost); a zero cost is always payable.
func can_pay_hp(amount: int) -> bool:
	return amount <= 0 or _hp > float(amount)


## Pays an action's HP cost (Slash Blast); refuses, changing nothing, when it would leave 0 HP.
func spend_hp(amount: int) -> bool:
	if amount <= 0:
		return true
	if not can_pay_hp(amount):
		return false
	_hp -= amount
	_write_player_state(0.0)
	return true


## Restores HP or MP, clamped to its maximum; returns and emits the actual integer pool gain (no event at zero).
func restore_player(stat: String, amount: int, skill: String) -> int:
	if stat not in ["hp", "mp"] or amount <= 0:
		return 0
	var before := ceili(_hp) if stat == "hp" else floori(_mp)
	if stat == "hp":
		_hp = minf(_max_hp, _hp + amount)
	else:
		_mp = minf(_max_mp, _mp + amount)
	_write_player_state(0.0)
	var gain := int(player_state[stat]) - before
	if gain > 0:
		emit("player_restored", {"stat": stat, "amount": gain, "skill": skill, "pos": player.pos})
	return gain


## Recomputes max HP/MP, speed, magnet, regen, defence and the caster inputs from the base stats, job and upgrade
## modifiers. The MaxMP passive preserves the MP ratio on growth; other explicit pool modifiers grant the
## difference, while ordinary level growth passes grant_growth=false and grants nothing.
func refresh_player_stats(grant_growth: bool = true) -> void:
	var pb: Dictionary = balance.get("player", {})
	var primary := String(_job_value(pb.get("ap_stat", {}), "str", true))
	# Earned AP splits between the job line's secondary stat (AutoAp, ticket #106) and the primary stat.
	var secondary_cfg: Dictionary = _job_value(pb.get("ap_secondary", {}), {}, true)
	var secondary := String(secondary_cfg.get("stat", ""))
	if secondary == primary or not _base_stats.has(secondary):
		secondary = ""
	var secondary_ap := 0
	if secondary != "":
		secondary_ap = AutoAp.secondary_ap(_earned_ap, progression.level, float(_base_stats[secondary]),
			secondary_cfg.get("keyframes", []))
	for stat: String in _base_stats:
		var ap := 0
		if stat == primary:
			ap = _earned_ap - secondary_ap
		elif stat == secondary:
			ap = secondary_ap
		_attributes[stat] = roundi(loadout.player_stat(stat, float(_base_stats[stat]) + ap))
	# Total = base + worn equipment (decisions #33: the Stat window's "base + bonus" split).
	for stat: String in _attributes:
		_attributes[stat] += roundi(equipment_bonus("inc" + stat.to_upper()))
	var old_hp := _max_hp
	var old_mp := _max_mp
	# tier C: equipment max HP/MP adds flat after card modifiers and the MaxMP passive. The Hyper Body buff then scales
	# that whole total (base, growth, passives, equipment; tier B, v83), unlike the passive, which leaves equipment out.
	_max_buff_applied = _max_buff_percents()
	_max_hp = maxi(1, roundi((loadout.player_stat("max_hp", _base_hp) + equipment_bonus("incMHP"))
		* (1.0 + _max_buff_applied.x / 100.0)))
	var mp_percent := loadout.passive_total(Loadout.MAX_MP_PERCENT)
	_max_mp = maxi(0, roundi((loadout.player_stat("max_mp", _base_mp + _job_mp) * (1.0 + mp_percent)
		+ equipment_bonus("incMMP")) * (1.0 + _max_buff_applied.y / 100.0)))
	if grant_growth and _max_hp > old_hp:
		_hp += _max_hp - old_hp
	if mp_percent > 0.0 and old_mp > 0 and _max_mp > old_mp:
		_mp = (_mp / old_mp) * _max_mp
	elif grant_growth and _max_mp > old_mp:
		_mp += _max_mp - old_mp
	_hp = minf(_hp, _max_hp)
	_mp = minf(_mp, _max_mp)
	_equipment_speed = equipment_bonus("incSpeed")
	_equipment_jump = equipment_bonus("incJump")
	player_acc = CombatMath.base_accuracy(float(_attributes.dex), float(_attributes.luk), jobs.lineage(progression.job_id)) \
		+ equipment_bonus("incACC")
	refresh_player_speed()
	magnet_r = loadout.player_stat("magnet", float(balance.get("magnet_radius", 90.0)))
	hp_regen = loadout.player_stat("hp_regen", float(balance.get("hp_regen", 0.0)))
	mp_regen = loadout.player_stat("mp_regen", float(balance.get("mp_regen", 0.0)))
	player_pdd = loadout.player_stat("pdd", equipment_bonus("incPDD")) + loadout.passive_total("pdd")
	player_mdd = loadout.player_stat("mdd", equipment_bonus("incMDD")) + loadout.passive_total("mdd")
	player_avoid = loadout.player_stat("avoid", float(_attributes.dex) * AVOID_DEX_FACTOR
		+ float(_attributes.luk) * AVOID_LUK_FACTOR + equipment_bonus("incEVA")) + loadout.passive_total("avoid")
	_refresh_caster()
	_write_player_state(0.0)


## Upgraded movement speed plus worn equipment's incSpeed and active canonical buff points, capped at the v83 140
## (Equipment.SPEED_CAP), then composed with the canonical-area slow.
func player_speed_stat() -> float:
	var speed := loadout.player_stat("speed", 100.0) + _equipment_speed + buffs.effect_total("speed")
	return minf(speed, Equipment.SPEED_CAP) * mob_skills.speed_multiplier(time)


func _refresh_caster() -> void:
	loadout.weapon_id = weapon_id()
	loadout.weapon_family = held_weapon_family() # first: the weapon-gated passives below read it
	loadout.set_caster(float(_attributes.int), equipment_bonus("incMAD") + buffs.effect_total("matk"), progression.level)
	loadout.str_stat = float(_attributes.str)
	loadout.dex_stat = float(_attributes.dex)
	loadout.luk_stat = float(_attributes.luk)
	_sync_ammo()
	loadout.watk = weapon_attack(WeaponInfo.is_ranged(loadout.weapon_id))
	loadout.acc = player_acc + buffs.effect_total("acc") + loadout.passive_total(Loadout.ACC)
	loadout.job_id = progression.job_id
	var held := weapon_info()
	loadout.weapon_speed = attack_speed_step()
	loadout.speed_steps = attack_speed_boost()
	player.stand_stance = WeaponInfo.stand_stance(held)
	player.walk_stance = WeaponInfo.walk_stance(held)
	# Weapon-gated passives (#161): mastery replaces the untrained 10%; crit chance is a percent; crit damage is the
	# critical hit's total percent, so its additive bonus is the part above 100.
	var mastery := loadout.passive_best(Loadout.MASTERY)
	loadout.mastery = CombatMath.mastery_fraction(int(mastery)) if mastery > 0.0 else Loadout.BASE_MASTERY
	loadout.crit_bonus = loadout.passive_total(Loadout.CRIT_CHANCE) / 100.0
	loadout.crit_damage_bonus = maxf(0.0, loadout.passive_best(Loadout.CRIT_DAMAGE) - 100.0)


## The held weapon's attack speed step (its Item.wz attackSpeed; WeaponInfo.NORMAL_SPEED bare-handed or when the weapon's
## info is unknown). Lower is faster.
func attack_speed_step() -> int:
	var info := weapon_info()
	return int(info.get("attackSpeed", 0)) if not info.is_empty() else WeaponInfo.NORMAL_SPEED


## Attack speed steps the active Boosters add (positive = faster). A buff counts only while the held weapon fits its
## skill's weapon families (SkillBook.usable_with): a Sword Booster keeps running through a weapon change but does
## nothing until a sword is held again (spec #151, #160).
func attack_speed_boost() -> int:
	var held := held_weapon_family()
	return roundi(buffs.effect_total_where("attack_speed", func(skill: String) -> bool:
		return loadout.book.usable_with(skill, held)))


## Applies player_speed_stat() to the movement model (whole speed points) and the jump stat (100 + worn incJump,
## capped at the v83 123, Equipment.JUMP_CAP).
func refresh_player_speed() -> void:
	player.speed_stat = roundi(player_speed_stat())
	player.jump_stat = mini(Equipment.JUMP_CAP, 100 + roundi(_equipment_jump + buffs.effect_total("jump")))


## Index of a WZ path in visual_paths (registered on first use); -1 for "".
func visual_index(path: String) -> int:
	if path == "":
		return -1
	if _visual_ids.has(path):
		return _visual_ids[path]
	var i := visual_paths.size()
	visual_paths.append(path)
	_visual_ids[path] = i
	return i


## Where targeting measures from: the player's body (feet - cast_height). Shots start shot_origin().
func cast_origin() -> Vector2:
	return player.pos - Vector2(0.0, cast_height)


## Where a shot flying toward `aim` starts: cast_forward px in front of the cast origin on the target's side (the
## throwing hand, so the shell does not cover the face), level with it.
func shot_origin(aim: Vector2) -> Vector2:
	var o := cast_origin()
	var side := signf(aim.x - o.x)
	if side == 0.0:
		side = float(player.facing)
	return o + Vector2(side * cast_forward, 0.0)


## Centre of mob m's body box (where shots aim).
func mob_center(m: int) -> Vector2:
	var mk: MobKind = mob_kinds[swarm.kind[m]]
	return mk.hitbox_at(swarm.x[m], swarm.y[m], swarm.facing[m]).get_center()


## True when slot m holds a scheduled boss (a BossDirector encounter); elites and boss offspring are not.
func is_scheduled_boss(m: int) -> bool:
	return m >= 0 and m < mob_boss.size() and mob_boss[m] >= 0


## Target order shared by every player targeting rule: scheduled bosses first, then nearer `d2`, then lower slot.
## tier C: ours (#83), so attacks reach a boss in range ahead of the swarm around it.
func targets_before(a: int, da: float, b: int, db: float) -> bool:
	var boss_a := is_scheduled_boss(a)
	if boss_a != is_scheduled_boss(b):
		return boss_a
	return da < db if da != db else a < b


## All live bodies intersecting a canonical feet-relative, left-facing skill box; scheduled bosses first, then nearest
## centre, then slot (targets_before).
## Minimum edges include touching bodies; maximum edges exclude them, matching SpatialHash.query_rect.
## `facing` (-1 / 1) tests that side; 0 uses the player's facing. Turning skills ask both sides.
func skill_box_targets(box: Rect2, filter: Callable = Callable(), facing := 0) -> PackedInt32Array:
	var matches := _skill_box_matches(box, filter, 0, 0, PackedByteArray(), facing)
	# Each match's distance is computed once, not in every comparison (#146). targets_before is a strict total order
	# (the slot breaks every tie), so any sort of the same keys gives the same list.
	var origin := cast_origin()
	var d2 := {}
	for m: int in matches:
		d2[m] = mob_center(m).distance_squared_to(origin)
	matches.sort_custom(func(a: int, b: int) -> bool: return targets_before(a, d2[a], b, d2[b]))
	return PackedInt32Array(matches)


## How many bodies skill_box_targets(box, filter) would return, counting no further than `limit` (> 0); with `kinds_ok`
## (per mob kind index, 1 = allowed) only bodies of those kinds count, a filter on the kind without a Callable. It looks
## first at only the first BOX_PROBE grid candidates (often enough) and reads the whole query only when they fall short.
func skill_box_count(box: Rect2, limit: int, filter: Callable = Callable(),
		kinds_ok: PackedByteArray = PackedByteArray(), facing := 0) -> int:
	var probe := maxi(BOX_PROBE, limit)
	var found := _skill_box_matches(box, filter, limit, probe, kinds_ok, facing)
	if found.size() >= limit or _box_candidates < probe:
		return found.size()
	return _skill_box_matches(box, filter, limit, 0, kinds_ok, facing).size()


## Up to `limit` live bodies intersecting `rect` (world coordinates, skill_box_targets' edge rules), scheduled bosses
## first, then nearest to `from`, then slot (targets_before). A charge's swept path (7.13).
func skill_rect_targets(rect: Rect2, from: Vector2, limit: int) -> PackedInt32Array:
	var matches := _world_rect_matches(rect, Callable(), 0)
	var d2 := {}
	for m: int in matches:
		d2[m] = mob_center(m).distance_squared_to(from)
	matches.sort_custom(func(a: int, b: int) -> bool: return targets_before(a, d2[a], b, d2[b]))
	if limit > 0 and matches.size() > limit:
		matches.resize(limit)
	return PackedInt32Array(matches)


## Moves the grounded player up to `distance` px toward `side` (-1 / 1) along its platform for a moving attack, stopping
## at the platform's edge and at walls (PlayerMotion.displace). Never fails: returns the px actually covered (0 while
## airborne or climbing, or when blocked), and the spent cast stands either way. The view follows on the next tick.
func displace_player(side: int, distance: float) -> float:
	return player.displace(side, distance, fhm, bounds)


## The live bodies of skill_box_targets in candidate order (unsorted), stopping at `limit` matches (0 = all), among
## the first `probe` grid candidates (0 = all; _box_candidates says how many the query gave), of the kinds `kinds_ok`
## allows (empty = any).
func _skill_box_matches(box: Rect2, filter: Callable, limit: int, probe: int = 0,
		kinds_ok: PackedByteArray = PackedByteArray(), facing := 0) -> Array[int]:
	if not box.has_area():
		_box_candidates = 0
		return []
	if (facing if facing != 0 else player.facing) > 0:
		box.position.x = -box.end.x
	box.position += player.pos
	return _world_rect_matches(box, filter, limit, probe, kinds_ok)


## The live bodies intersecting a rect in world coordinates, with _skill_box_matches' edge rules, filter, limit, probe
## and kinds_ok (candidate order, unsorted).
func _world_rect_matches(box: Rect2, filter: Callable, limit: int, probe: int = 0,
		kinds_ok: PackedByteArray = PackedByteArray()) -> Array[int]:
	var matches: Array[int] = []
	_box_candidates = 0
	if not box.has_area():
		return matches
	var candidates := PackedInt32Array()
	var n := mob_grid.query_rect(box.grow(body_pad), candidates, probe)
	_box_candidates = n
	for i in n:
		var m := candidates[i]
		if not swarm.is_live(m):
			continue
		if not kinds_ok.is_empty() and kinds_ok[swarm.kind[m]] == 0:
			continue
		var mk: MobKind = mob_kinds[swarm.kind[m]]
		var body_box := mk.hitbox_at(swarm.x[m], swarm.y[m], swarm.facing[m])
		if body_box.end.x < box.position.x or body_box.position.x >= box.end.x \
				or body_box.end.y < box.position.y or body_box.position.y >= box.end.y:
			continue
		if filter.is_valid() and not bool(filter.call(m)):
			continue
		matches.append(m)
		if limit > 0 and matches.size() >= limit:
			break
	return matches


## The setup's Mob.wz img root of mob `id` (int or String keys); {} when absent.
func mob_img(id: int) -> Dictionary:
	var imgs: Dictionary = setup.get("mob_imgs", {})
	return imgs.get(id, imgs.get(str(id), {}))


## The player's world-space body box (feet + `body`): what monster touches, attacks and balls test.
func player_box() -> Rect2:
	return Rect2(player.pos + body.position, body.size)


## Centre of the player's body box (where monster balls aim).
func player_body_center() -> Vector2:
	return player.pos + body.get_center()


## Number of living slots owned by summoning encounter `owner` (MobSkill 200 summons and revive offspring).
func summoned_alive(owner: int) -> int:
	var count := 0
	for slot in swarm.capacity():
		if swarm.active[slot] != 0 and mob_summon_owner[slot] == owner:
			count += 1
	return count


## Spawns `ids` (in list order) as ordinary mobs owned by encounter `owner` on mob `source`'s platform, spread
## `balance.mob_skills.summon_spacing` px apart around `center_x` and centred on the whole list even when `max_count`
## (-1 = all) spawns only its first entries. Ids without a mob kind and points without a foothold are skipped (their
## place in the spread stays empty). Returns the new slots; none when the source has no platform.
func spawn_offspring(source: int, center_x: float, ids: PackedInt32Array, owner: int,
		max_count: int = -1) -> PackedInt32Array:
	var slots := PackedInt32Array()
	var platform := swarm.platform[source]
	if platform < 0:
		return slots
	var span := fhm.platform_span(platform)
	# tier C: symmetric survivor spawn spacing; canonical list/limit/stats remain unchanged.
	var spacing := float(balance.get("mob_skills", {}).get("summon_spacing", DEFAULT_SUMMON_SPACING))
	for i in (ids.size() if max_count < 0 else mini(ids.size(), max_count)):
		var id := ids[i]
		if not kind_of_id.has(id):
			continue
		var x := clampf(center_x + (i - (ids.size() - 1) * 0.5) * spacing, span.x, span.y)
		var fh := fhm.platform_fh_at(platform, x)
		if fh < 0:
			continue
		var slot := spawn_mob(int(kind_of_id[id]), Vector2(x, fhm.y_at(fh, x)), fh, 1.0, false)
		mob_summon_owner[slot] = owner
		slots.append(slot)
	return slots


## Platform the player stands on or is above (-1 when none).
func player_platform() -> int:
	if player.fh >= 0:
		return fhm.platform_of(player.fh)
	return fhm.platform_of(fhm.find_below(player.pos.x, player.pos.y))


## The floor right below a player standing on a low step, which walkers also count as the player's
## (MobSwarm.low_platform, reach_y); -1 when there is none.
func player_low_platform() -> int:
	var tp := player_platform()
	if tp < 0:
		return -1
	return MobSwarm.low_platform(fhm, player.pos, tp, float(swarm.tuning.reach_y))


## Turns a standing player toward x (casting at a target); a walking player keeps facing its way. `any_state` turns the
## player in every movement state for this cast (Power Strike, Slash Blast; tier C): a held direction sets the facing
## again on the next motion step, so the turn does not fight walking.
func face_toward(tx: float, any_state := false) -> void:
	if (any_state or player.state == PlayerMotion.ST_STAND) and absf(tx - player.pos.x) > 0.5:
		player.facing = 1 if tx > player.pos.x else -1


## Starts a stance for its frame time; airborne opts basic swings into the same visual without changing motion; `scale`
## is the attack-speed fraction of the frame time it plays in (WeaponInfo.speed_factor).
func start_action(action: String, seconds: float, airborne: bool = false, scale: float = 1.0) -> void:
	upkeep.start_action(action, seconds, airborne, scale)


## The worn weapon's item id; 0 when bare-handed.
func weapon_id() -> int:
	return int(equipment.worn.weapon.id) if equipment.worn.has("weapon") else 0


## The worn weapon's family ("sword", "claw", ...; WeaponInfo.FAMILIES); "" when bare-handed.
func held_weapon_family() -> String:
	return WeaponInfo.family(weapon_id())


## The worn weapon's canonical info node (empty when bare-handed or absent from setup.equipment_info).
func weapon_info() -> Dictionary:
	var id := weapon_id()
	return Equipment.info_of(setup.get("equipment_info", {}), id) if id > 0 else {}


## W.ATT: every worn incPAD plus active W.Att buffs; a ranged attack adds the current ammo's incPAD (tier A: v83 adds the
## ammo stack's incPAD to weapon attack for ranged attacks).
func weapon_attack(ranged: bool = false) -> float:
	var attack := equipment_bonus("incPAD") + buffs.effect_total("watk")
	return attack + ammo_attack() if ranged else attack


## The ammo item the held weapon fires (Item.wz id); 0 when it is not a bow, crossbow, claw or gun. Endless: it is never
## consumed, and it follows the weapon family, job and level (Ammo.item_for).
func ammo_id() -> int:
	return _ammo_id


## The current ammo's incPAD (setup.ammo_info, Item.wz); 0 without ammo.
func ammo_attack() -> float:
	return float(setup.get("ammo_info", {}).get(_ammo_id, {}).get("incPAD", 0))


## The ammo a tooltip of weapon `weapon` lists: {"item_id", "incPAD"} of the ammo this character would fire with it (the
## window adds the String.wz name); {} for a melee weapon.
func ammo_tooltip(weapon: int) -> Dictionary:
	var id := Ammo.item_for(data.get("ammo", {}), WeaponInfo.family(weapon), progression.job_id, progression.level, jobs)
	if id == 0:
		return {}
	return {"item_id": id, "incPAD": int(setup.get("ammo_info", {}).get(id, {}).get("incPAD", 0))}


## Recomputes the current ammo; emits ammo_upgraded when the held family's ammo moved to a higher tier (a weapon swap or
## the first computation is silent). Called by _refresh_caster, which every level-up, job change and weapon change reaches.
func _sync_ammo() -> void:
	var family := held_weapon_family()
	var id := Ammo.item_for(data.get("ammo", {}), family, progression.job_id, progression.level, jobs)
	if id != _ammo_id and _ammo_id != 0 and id != 0 and family == _ammo_family:
		var from := _ammo_id
		_ammo_id = id
		emit("ammo_upgraded", {"family": family, "from_item_id": from, "item_id": id, "level": progression.level})
	_ammo_id = id
	_ammo_family = family


## What worn equipment adds to one `inc*` stat (the "bonus" of the Stat window's base + bonus).
func equipment_bonus(field: String) -> float:
	return Equipment.total(equipment.worn, field)


## Wears inventory item `index`; "" or the Equipment reason it failed (nothing changes then). See the header.
func equip_item(index: int) -> String:
	if index < 0 or index >= equipment.inventory.size():
		return "no_item"
	var id := int(equipment.inventory[index].id)
	var who := {"level": progression.level, "job_id": progression.job_id}
	who.merge(_attributes)
	var reason := Equipment.equip(equipment, index, Equipment.info_of(setup.get("equipment_info", {}), id), who,
		inventory_slots())
	if reason == "":
		_equipment_changed("equip", Equipment.slot_of(id), id)
	return reason


## Moves the item worn in `slot` to the inventory; "" or the Equipment reason (empty, inventory_full).
func unequip_item(slot: String) -> String:
	var id := int(equipment.worn[slot].id) if equipment.worn.has(slot) else 0
	var reason := Equipment.unequip(equipment, slot, inventory_slots())
	if reason == "":
		_equipment_changed("unequip", slot, id)
	return reason


## Destroys inventory item `index`; "" or "no_item". Worn equipment cannot be discarded.
func discard_item(index: int) -> String:
	var id := int(equipment.inventory[index].id) if index >= 0 and index < equipment.inventory.size() else 0
	var reason := Equipment.discard(equipment, index)
	if reason == "":
		_equipment_changed("discard", "", id)
	return reason


## Destroys the whole stack of scroll `item_id` (the Item window's discard; #110 fills the stacks); "" or "no_item".
func discard_scrolls(item_id: int) -> String:
	var key := str(item_id)
	if not scrolls.has(key):
		return "no_item"
	scrolls.erase(key)
	emit("equipment_changed", {"action": "discard", "slot": "", "item_id": item_id})
	return ""


## The canonical info of scroll `scroll_id` (setup.scroll_info; {} when absent).
func scroll_info(scroll_id: int) -> Dictionary:
	var infos: Dictionary = setup.get("scroll_info", {})
	return infos.get(scroll_id, infos.get(str(scroll_id), {}))


## Adds up to `count` scrolls to the Use tab (a stack stops at its info/slotMax, 100 without one; the two potion
## stacks take two of the Use tab's slots); returns how many were added. Test and tool hook until shops exist.
func grant_scrolls(scroll_id: int, count: int) -> int:
	return Scrolls.add(scrolls, scroll_id, count, int(scroll_info(scroll_id).get("slotMax", 0)),
		Shop.use_stack_limit(potions.stock))


## What Free Market NPC `npc_id` (shops.json) sells this character's job: Shop.stock entries, [] for an unknown NPC.
func shop_stock(npc_id: int) -> Array:
	for npc: Dictionary in data.get("shops", {}).get("npcs", []):
		if int(npc.id) == npc_id:
			return Shop.stock(npc, data.shops, data.get("scrolls", {}), data.get("equipment_drops", {}).get("items", []),
				setup.get("equipment_info", {}), progression.job_id)
	return []


## Buys `count` scrolls `scroll_id` from NPC `npc_id` (Shop.buy; "not_sold" when its stock lacks the scroll).
func buy_scroll(npc_id: int, scroll_id: int, count: int) -> String:
	for entry: Dictionary in shop_stock(npc_id):
		if int(entry.id) == scroll_id:
			var state := _shop_state()
			var reason := Shop.buy(state, scroll_id, count, int(entry.price), int(scroll_info(scroll_id).get("slotMax", 0)))
			if reason == "":
				_shop_done("buy", scroll_id, state)
			return reason
	return "not_sold"


## Sells the spare equipment at inventory `index` at its info/price (Shop.sell_equipment).
func sell_item(index: int) -> String:
	var id := int(equipment.inventory[index].id) if index >= 0 and index < equipment.inventory.size() else 0
	var state := _shop_state()
	var reason := Shop.sell_equipment(state, index, Equipment.info_of(setup.get("equipment_info", {}), id))
	if reason == "":
		_shop_done("sell", id, state)
	return reason


## Sells `count` scrolls `scroll_id` at their info/price (Shop.sell_scrolls).
func sell_scrolls(scroll_id: int, count: int) -> String:
	var state := _shop_state()
	var reason := Shop.sell_scrolls(state, scroll_id, count, scroll_info(scroll_id))
	if reason == "":
		_shop_done("sell", scroll_id, state)
	return reason


## Reads scroll `scroll_id` onto the item worn in `slot` (Scrolls.use with the scroll stream): "" once it was used up
## (success, failure or destruction, reported by `scroll_used`), or the refusal with the scroll kept. See the header.
func use_scroll(scroll_id: int, slot: String) -> String:
	if int(scrolls.get(str(scroll_id), 0)) <= 0:
		return "no_item"
	var item_id := int(equipment.worn[slot].id) if equipment.worn.has(slot) else 0
	var result := Scrolls.use(equipment.worn, slot, scroll_id, scroll_info(scroll_id), scroll_rng)
	if not result in Scrolls.OUTCOMES:
		return result
	Scrolls.take(scrolls, scroll_id)
	_equipment_changed("scroll", slot, item_id)
	emit("scroll_used", {"result": result, "scroll_id": scroll_id, "slot": slot, "item_id": item_id})
	return ""


## The Equip tab's capacity (balance.player.inventory_slots).
func inventory_slots() -> int:
	return int(balance.get("player", {}).get("inventory_slots", DEFAULT_INVENTORY_SLOTS))


## The character state Shop works on: mesos by value, the Use stacks and Equip tab by reference.
func _shop_state() -> Dictionary:
	return {"mesos": mesos, "scrolls": scrolls, "equipment": equipment, "potions": potions.stock}


func _shop_done(action: String, item_id: int, state: Dictionary) -> void:
	mesos = int(state.mesos)
	emit("equipment_changed", {"action": action, "slot": "", "item_id": item_id})


func _equipment_changed(action: String, slot: String, id: int) -> void:
	refresh_player_stats(false)
	emit("equipment_changed", {"action": action, "slot": slot, "item_id": id})


## Wears the weapon an advancement grants and moves the previous one to the inventory (a grant never checks
## requirements: a Beginner whose AP is all STR still wears the Bowman's bow). The grant is, in order: the chosen weapon
## path's item (tier B: the v83 Beginner weapons of the instructors), balance.player.weapon_grants (tier C: Magician 200
## -> Wooden Wand; tier B: Warrior 100 -> the Beginner Warrior's sword 1302077), or a second job's advancement weapons
## (JobTree.branch_grant, tier C, spec #165 #180): the one of the held weapon's family is worn, else the first family's;
## the branch's other advancement weapons join the Equip tab after the displaced weapon (_hand_over).
## tier C: what the grant takes off (the previous weapon; a two-handed grant also the shield) and the full Equip tab has
## no room for is dropped at the player's feet as a normal equipment pickup (pickup_spawned; the magnet collects it once
## a slot is free), so advancing never fails.
func _grant_job_weapon(job_id: int, path := "") -> void:
	var id := int(balance.get("player", {}).get("weapon_grants", {}).get(str(job_id), 0))
	var others: Array = []
	if path != "":
		id = int(jobs.path_of(job_id, path).get("item_id", id))
	else:
		# One pass: the first weapon of the held family is worn, the rest are `others`; with none of that family the
		# first entry is worn (it comes back off the front of `others`).
		var weapons: Array = jobs.branch_grant(job_id).get("weapons", [])
		var worn := -1
		for raw: Variant in weapons:
			var w: Dictionary = raw
			if worn < 0 and String(w.family) == held_weapon_family():
				worn = int(w.item_id)
			else:
				others.append(int(w.item_id))
		if worn < 0 and not others.is_empty():
			worn = int(others.pop_front())
		if worn >= 0:
			id = worn
	if id <= 0:
		return
	var instance := Equipment.create(id, Equipment.info_of(setup.get("equipment_info", {}), id))
	# Every slot the grant displaces (the weapon, and the shield of a two-handed grant) goes to the Equip tab while it
	# has room; the rest, last slot first (the shield), is taken off here and dropped after the grant is worn.
	var displaced := Equipment.displaced_slots(equipment.worn, id)
	var room := maxi(0, inventory_slots() - equipment.inventory.size())
	var spilled: Array = []
	while displaced.size() > room:
		var slot: String = displaced.pop_back()
		spilled.append(equipment.worn[slot])
		equipment.worn.erase(slot)
	var error := Equipment.grant(equipment, instance, inventory_slots())
	assert(error == "", "a job grant always fits once the displaced items are spilled")
	_equipment_changed("grant", "weapon", id)
	for item: Dictionary in spilled:
		spawn_equipment(player.pos, item)
	for other: int in others:
		_hand_over(other)


## Hands the Equip items of the job's survivor `grants.items` (tier C: the Warrior's Lv 10 Spear and Steel Pipe) to the Equip
## tab, followed by the chosen path's optional extra_items (#186), after whatever the weapon grant displaced;
## an item the full tab has no room for lies at the player's feet as a
## normal equipment pickup, so advancing never fails. A grant never checks requirements.
func _grant_job_items(job_id: int, path := "") -> void:
	var items: Array = jobs.job(job_id).get("grants", {}).get("items", []).duplicate()
	# tier B: Kyrin gives both Pirate weapons. Path extras follow the same overflow rule as grants.items.
	items.append_array(jobs.path_of(job_id, path).get("extra_items", []))
	for raw: Variant in items if items is Array else []:
		_hand_over(int(raw))


## Gives a new instance of item `id` to the Equip tab, or to the player's feet when the tab is full.
func _hand_over(id: int) -> void:
	var instance := Equipment.create(id, Equipment.info_of(setup.get("equipment_info", {}), id))
	if equipment.inventory.size() < inventory_slots():
		equipment.inventory.append(instance)
		_equipment_changed("grant", "", id)
	else:
		spawn_equipment(player.pos, instance)


## Per-slot mob stance snapshot (bosses' and ordinary mobs' authored stances) for MobSwarm and the renderer;
## borrowed, read it at once (MobActions.view).
func mob_action_view() -> Dictionary:
	return mob_actions.view(bosses.action_snapshot(swarm), bosses, swarm, time)


## Live defense at a mob slot; later timed boss buffs can override this shared hit seam. The per-tick projectile
## defense (MobSkillRunner.fill_live_defense in _step_player_attacks) computes both cases in bulk: keep them equal.
func mob_defense(m: int, magic: bool) -> float:
	var kind: MobKind = mob_kinds[swarm.kind[m]]
	var defense := float(kind.mdd if magic else kind.pdd) + mob_skills.defense_bonus(m,magic,time)
	return defense if magic else swarm.threatened_pdd(m, defense) # Threaten (#183) lowers weapon defence only


## Whether a physical impact may damage this slot at the current simulation time.
func physical_hit_allowed(m: int) -> bool:
	return mob_skills.physical_hit_allowed(m, time)


## Spawns a mob of kind index k on foothold fh at pos with max_hp x hp_mult; emits mob_spawned. Returns the slot.
func spawn_mob(k: int, pos: Vector2, fh: int, hp_mult: float, elite: bool) -> int:
	if k < 0 or k >= mob_kinds.size():
		return -1
	var mk: MobKind = mob_kinds[k]
	var i := swarm.spawn(k, pos.x, pos.y, fh, maxi(1, roundi(mk.max_hp * hp_mult)))
	_sync_slots()
	mob_elite[i] = 1 if elite else 0
	mob_boss[i] = -1
	mob_summon_owner[i] = -1
	mob_skills.reset_slot(i)
	mob_attacks.reset_slot(i)
	mob_actions.reset_slot(i)
	emit("mob_spawned", {"mob": i, "mob_id": mk.id, "pos": Vector2(swarm.x[i], swarm.y[i]), "elite": elite,
		"relocated_from": -1})
	return i


## Moves live mob i to pos on foothold fh like a new spawn (SpawnDirector relocation): the slot is freed and the same
## kind spawned there with its logical identity, HP, max HP, remaining MP and elite flag, fading in; emits mob_spawned with relocated_from =
## i (new spawns have -1). Returns the new slot (-1 when i is not a live mob).
func relocate_mob(i: int, pos: Vector2, fh: int) -> int:
	if i < 0 or i >= swarm.capacity() or swarm.active[i] == 0:
		return -1
	var k := swarm.kind[i]
	var elite := mob_elite[i] != 0
	var boss_index := mob_boss[i]
	var summon_owner := mob_summon_owner[i]
	var j := swarm.relocate(i, pos, fh)
	_sync_slots()
	mob_elite[j] = 1 if elite else 0
	mob_boss[j] = boss_index
	swarm.steady[j] = 1 if boss_index >= 0 else 0
	mob_summon_owner[j] = summon_owner
	mob_skills.move_slot(i,j)
	mob_attacks.move_slot(i, j)
	mob_actions.reset_slot(i)
	mob_actions.reset_slot(j)
	if boss_index >= 0:
		bosses.records[boss_index].slot = j
	emit("mob_spawned", {"mob": j, "mob_id": mob_kinds[k].id, "pos": Vector2(swarm.x[j], swarm.y[j]), "elite": elite,
		"relocated_from": i})
	return j


## One instant damage line with live defence; hv = hit visual index. Optional hit_rng selects basic stream 5.
func hit_mob(m: int, st: Dictionary, hv: int, hit_rng: RandomNumberGenerator = null) -> void:
	if swarm.active[m] == 0:
		return
	var dtype := CombatMath.damage_type_of(String(st.get("damage_type", "")), bool(st.get("magic", false)))
	var magic := dtype == "magic"
	if not magic and not physical_hit_allowed(m):
		return
	var mk: MobKind = mob_kinds[swarm.kind[m]]
	var roll := ProjectileSystem.roll_damage(float(st.damage_min), float(st.damage_max), magic,
		mob_defense(m, magic), projectiles.magic_defense_k, float(st.crit), float(st.crit_mult),
		hit_rng if hit_rng != null else rng, mk.element_multiplier(String(st.get("element", ""))), dtype,
		float(st.get("damage_pct", 1.0)), int(st.get("player_level", progression.level)), mk.level,
		float(st.get("crit_damage_bonus", 0.0)))
	var dir := 1 if swarm.x[m] >= player.pos.x else -1
	emit("mob_hit", {
		"mob": m, "mob_id": mk.id, "damage": roll.x, "crit": roll.y != 0,
		"pos": Vector2(swarm.x[m], swarm.y[m] + mk.hitbox.position.y),
		"hit_visual": String(visual_paths[hv]) if hv >= 0 else "", "skill": String(st.skill),
	})
	_instant_dealt += roll.x
	if roll.x > 0:
		_on_player_hit(m, {"skill": String(st.skill), "level": int(st.get("level", 0)), "magic": magic,
			"damage": roll.x, "element": String(st.get("element", "")), "damage_type": dtype})
	if swarm.apply_hit(m, roll.x, dir):
		_on_kill(m)


## Registers a listener(slot, hit) after on-hit statuses and before damage/kill resolution, once per damaging line.
func add_hit_listener(listener: Callable) -> void:
	_hit_listeners.append(listener)


func _steal_hit(slot: int, hit: Dictionary) -> void:
	var steal: Dictionary = book.def(String(hit.skill)).get("steal", {})
	if steal.is_empty() or swarm.stolen[slot] != 0:
		return
	var chance := book.canonical(String(hit.skill), int(hit.level), String(steal.chance_field))
	# Owner #167: only Steal success uses stream 15, once per damaging line, including lethal hits and bosses.
	if thief_rng.randf() * 100.0 >= chance:
		return
	drop_mob_loot(slot, true)
	swarm.stolen[slot] = 1


func _mp_eater_hit(slot: int, hit: Dictionary) -> void:
	if not bool(hit.magic) or int(hit.damage) <= 0 or swarm.mp[slot] <= 0:
		return
	# Branch-exclusive learn cards allow only one MP Eater per normal run, preserving the old proc order.
	for key: String in loadout.order:
		var absorb: Dictionary = book.def(key).get("absorb_mp", {})
		if absorb.is_empty():
			continue
		var level := loadout.level(key)
		if level <= 0:
			continue
		var chance := book.canonical(key, level, String(absorb.chance_field))
		var percent := book.canonical(key, level, String(absorb.percent_field))
		# tier C: truncate fractional MP to whole points (integer interpretation).
		var amount := mini(swarm.mp[slot], int(swarm.mob_kind(slot).max_mp * percent / 100.0))
		if chance <= 0.0 or amount <= 0:
			continue
		if chance < 100.0 and rng.randf() * 100.0 >= chance:
			continue
		swarm.mp[slot] -= amount
		restore_player("mp", amount, key)
		# tier C: absorb art also plays at full player MP; gain numbers use player_restored's actual capped gain.
		emit("mp_eater_absorbed", {"mob": slot, "amount": amount, "skill": key, "pos": player.pos})


## Final Attack (#161): after a damaging physical line of a held matching family, an owned Final Attack skill
## (`final_attack: {chance_field}` in skills.json, damage "physical") rolls its canonical `prop` percent on stream 12
## and queues one follow-up on the same target. The follow-up plays after the tick's attacks (_play_final_attacks), so
## it never resolves inside the line that triggered it. Its own lines never trigger another (no chains).
## tier C: one roll per damaging line, not per attack (a multi-line skill rolls once per line).
func _final_attack_hit(slot: int, hit: Dictionary) -> void:
	if _final_keys_version != loadout.version:
		_final_keys.clear()
		for key: String in loadout.order:
			if book.def(key).has("final_attack"):
				_final_keys.append(key)
		_final_keys_version = loadout.version
	if _final_keys.is_empty() or int(hit.damage) <= 0 or String(hit.get("damage_type", "")) != "physical" \
			or book.def(String(hit.skill)).has("final_attack"):
		return
	var held := held_weapon_family()
	for key: String in _final_keys:
		if not book.usable_with(key, held):
			continue
		var chance := book.canonical(key, loadout.level(key), String(book.def(key).final_attack.chance_field))
		if chance <= 0.0 or (chance < 100.0 and final_rng.randf() * 100.0 >= chance):
			continue
		_final_queue.append({"slot": slot, "identity": swarm.identity[slot], "skill": key})


## Plays the queued follow-ups at their still-living original targets (tier C: a target the trigger killed gets none).
func _play_final_attacks() -> void:
	if _final_queue.is_empty():
		return
	var queue := _final_queue
	_final_queue = []
	for entry: Dictionary in queue:
		var slot := int(entry.slot)
		if swarm.active[slot] == 0 or swarm.identity[slot] != entry.identity:
			continue
		var key := String(entry.skill)
		if not book.usable_with(key, held_weapon_family()):
			continue
		var st := runner.stats_of(self, key)
		# The follow-up plays the skill's own stance when its data has one (tier C: it replaces a swing still playing).
		start_action(String(st.action), float(st.action_time), false, float(st.speed_factor))
		emit("final_attack", {"skill": key, "skill_id": int(st.skill_id), "level": int(st.level), "mob": slot,
			"pos": player.pos, "facing": player.facing, "action": String(st.action), "effect": String(st.effect)})
		var hit_visual := visual_index(String(st.hit))
		hit_mob(slot, st, hit_visual, final_rng)
		for extra: int in _spread_targets(slot, int(st.count) - 1):
			hit_mob(extra, st, hit_visual, final_rng)


## Spread (#181): up to `want` live mobs other than `target` whose body centre is within the held weapon's swing reach
## (BasicAttack.reach) of the target's body centre, nearest the target first (scheduled bosses first, then the slot,
## RunWorld.targets_before). Uses no RNG. tier C: ours; reach is measured around the struck target, as a circle.
func _spread_targets(target: int, want: int) -> Array[int]:
	var found: Array[int] = []
	if want <= 0:
		return found
	var reach := basic.reach(self)
	if reach <= 0.0:
		return found
	var centre := mob_center(target)
	var buffer := PackedInt32Array()
	var candidates := PackedInt32Array()
	var count := mob_grid.query_radius(centre, reach + body_pad, buffer)
	var distance := {}
	for i in count:
		var m := buffer[i]
		if m == target or swarm.active[m] == 0:
			continue
		var d2 := mob_center(m).distance_squared_to(centre)
		if d2 > reach * reach:
			continue
		candidates.append(m)
		distance[m] = d2
	var ordered: Array = Array(candidates)
	ordered.sort_custom(func(a: int, b: int) -> bool: return targets_before(a, distance[a], b, distance[b]))
	for m: int in ordered.slice(0, want):
		found.append(m)
	return found


func _on_player_hit(slot: int, hit: Dictionary) -> void:
	var key := String(hit.skill)
	var level := int(hit.level)
	var status: Dictionary = book.def(key).get("on_hit", {})
	if not status.is_empty():
		var chance_field := String(status.get("chance_field", ""))
		var chance := book.canonical(key, level, chance_field) if chance_field != "" else 100.0
		if chance > 0.0 and (chance >= 100.0 or rng.randf() * 100.0 < chance):
			var params := {"time": book.canonical(key, level, String(status.get("duration_field", "time"))),
				"level": level, "skill": key, "x": book.canonical(key, level, "x")}
			if String(hit.element) != "":
				params["element"] = String(hit.element)
			swarm.apply_status(slot, String(status.get("status", "")), params, events)
	for listener: Callable in _hit_listeners:
		listener.call(slot, hit)


func _stream(n: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value * 1000003 + n * 7919
	return r


func _build_mob_kinds() -> void:
	var imgs: Dictionary = setup.get("mob_imgs", {})
	var overrides: Dictionary = data.get("mobs", {}).get("mobs", {})
	var speed_mult := float(balance.get("mob_speed_factor", MobKind.SPEED_SCALE)) / MobKind.SPEED_SCALE
	for id in StageRoster.mob_ids(stage, imgs, setup.get("mob_skill_img", {})):
		var img: Variant = imgs.get(id, imgs.get(str(id)))
		if not (img is Dictionary) or img.is_empty():
			warnings.append("no mob img for %d: dropped from the pools" % id)
			continue
		var ov: Dictionary = overrides.get(str(id), {}).duplicate()
		ov["speed_mult"] = float(ov.get("speed_mult", 1.0)) * speed_mult
		kind_of_id[id] = mob_kinds.size()
		mob_kinds.append(MobKind.from_wz(img, id, ov))


func _init_player() -> void:
	var pb: Dictionary = balance.get("player", {})
	_base_hp = float(pb.get("hp", 50.0))
	_base_mp = float(pb.get("mp", 5.0))
	_base_fortune = float(pb.get("fortune", 0.0))
	var starting: Dictionary = pb.get("stats", {})
	for stat: String in _base_stats:
		_base_stats[stat] = int(starting.get(stat, _base_stats[stat]))
	var b: Variant = pb.get("body")
	if b is Array and b.size() == 4:
		body = Rect2(float(b[0]), float(b[1]), float(b[2]), float(b[3]))
	cast_height = float(pb.get("cast_height", DEFAULT_CAST_HEIGHT))
	cast_forward = float(pb.get("cast_forward", DEFAULT_CAST_FORWARD))
	player.place(PortalSet.start_point(setup.get("map_img", {}), fhm, bounds, spawn_rng), fhm)
	if setup.has("character"):
		_restore_character(setup.character)
	else:
		equipment.worn = Equipment.worn_from_ids(Equipment.DEFAULT_OUTFIT, setup.get("equipment_info", {}))
	_init_cash()
	refresh_player_stats()
	_hp = _max_hp
	_mp = _max_mp
	if not setup.has("character"):
		for key: Variant in pb.get("skills", []):
			learn_skill(String(key))
	_action = player.stance()


func _restore_character(source: Dictionary) -> void:
	assert(int(source.get("format", 0)) in CharacterSnapshot.FORMATS, "Unsupported CharacterSnapshot format")
	var character := CharacterSnapshot.migrate(source, jobs, setup.get("equipment_info", {}))
	progression.level = int(character.level)
	progression.exp = int(character.exp)
	progression.job_id = int(character.job_id)
	_base_stats = CharacterSnapshot.integers(character.base_attributes)
	_earned_ap = int(character.earned_ap)
	_base_hp = float(character.base_hp)
	_base_mp = float(character.base_mp)
	_job_mp = float(character.job_mp)
	_base_fortune = float(character.base_fortune)
	CharacterSnapshot.restore_loadout(character, loadout)
	for kind: String in potions.stock:
		potions.stock[kind] = CharacterSnapshot.integers(character.potions[kind])
	character_look = character.get("look", {}).duplicate(true)
	for field: String in ["skin", "face", "hair"]:
		if character_look.has(field):
			character_look[field] = int(character_look[field])
	equipment = Equipment.normalized(character.equipment)
	scrolls = CharacterSnapshot.integers(character.scrolls)
	mesos = int(character.mesos)
	_cash_carried = CharacterSnapshot.integers(character.get("cash", {}))
	_pet_carried = int(character.get("pet", 0))
	weapon_path = String(character.get("weapon_path", ""))


## Sets the ALERT levels from {hp, mp} (fractions of max, clamped; 0 = do not alert). The pet reads them every tick, so
## a change takes effect at once (a live round follows the Options window, spec #34 #121).
func set_alert(levels: Dictionary) -> void:
	alert = {"hp": clampf(float(levels.get("hp", 0.0)), 0.0, 1.0), "mp": clampf(float(levels.get("mp", 0.0)), 0.0, 1.0)}


## The cash catalog of this round's data, built once.
func _cash_catalog() -> CashCatalog:
	if _catalog == null:
		_catalog = CashCatalog.from_data(data)
	return _catalog


## Resolves the account, the worn cash equipment and the pet of this round (spec #34); what the account does not
## own is ignored and reported in `warnings`.
func _init_cash() -> void:
	var account: Dictionary = setup.get("account", {})
	account_owned = Array(account.get("owned", []))
	set_alert(setup.get("alert", {}))
	var resolved := _cash_catalog().resolve(_cash_carried, _pet_carried, account_owned)
	worn_cash = resolved.worn
	pet = resolved.pet
	cash_fortune = resolved.fortune
	for message: String in resolved.warnings:
		warnings.append(message)
	if pet > 0:
		_init_pet(_cash_catalog())


## Wears the owned cash equipment `id` (the Equip window's Cash tab, spec #34 #122): it takes its slots and replaces what
## covered them (CashCatalog.wear: an overall clears top and bottom, a two-handed cover weapon and shield). "" or
## "not_cash" (not cash equipment) / "not_owned" (the account does not own it); nothing changes on a refusal. Wearing
## never uses the item up. Fortune follows at once, so the next card draw uses it.
func wear_cash(id: int) -> String:
	var catalog := _cash_catalog()
	if catalog.kind_of(id) != "equip" or catalog.slots_for(id).is_empty():
		return "not_cash"
	if not Account.owns(account_owned, id):
		return "not_owned"
	_cash_carried = catalog.wear(_cash_carried, id)
	_cash_changed("wear_cash", "", id)
	return ""


## Takes off the cash equipment worn in `slot` (every slot it covers); "" or "empty" when nothing is worn there.
func take_off_cash(slot: String) -> String:
	var catalog := _cash_catalog()
	var id := int(_cash_carried.get(slot, 0))
	if id == 0:
		return "empty"
	_cash_carried = catalog.take_off(_cash_carried, slot)
	_cash_changed("take_off_cash", slot, id)
	return ""


## Brings the owned pet `species` out in place of any other, or none (0). "" or "not_pet" / "not_owned"; nothing
## changes on a refusal. The pet is simulated from the next tick, at the player's feet, with the owned upgrades.
func set_pet(species: int) -> String:
	var catalog := _cash_catalog()
	if species != 0:
		if catalog.kind_of(species) != "pet":
			return "not_pet"
		if not Account.owns(account_owned, species):
			return "not_owned"
	_pet_carried = species
	pet = species
	pet_system = null
	if species > 0:
		_init_pet(catalog)
	emit("equipment_changed", {"action": "pet", "slot": "", "item_id": species})
	return ""


## Re-reads the worn cash equipment after a change (Fortune included) and announces it.
func _cash_changed(action: String, slot: String, id: int) -> void:
	var resolved := _cash_catalog().resolve(_cash_carried, 0, account_owned)
	worn_cash = resolved.worn
	cash_fortune = resolved.fortune
	_equipment_changed(action, slot, id)


## The pet simulation of this round: abilities from the owned upgrades whose prerequisites the account meets.
func _init_pet(catalog: CashCatalog) -> void:
	var abilities := {}
	var owned := PetSystem.abilities_from(account_owned)
	for ability: String in owned:
		var id := int(PetSystem.ABILITY_ITEMS[ability])
		if bool(owned[ability]) and not catalog.prerequisites_met(id, account_owned):
			warnings.append("pet upgrade %d is owned but its prerequisites are not: ignored" % id)
		else:
			abilities[ability] = bool(owned[ability])
	pet_system = PetSystem.new(pet, abilities, data.get("cash_items", {}).get("pet", {}), physics)
	pet_system.place_beside(player, fhm)


## Recentres the view rect on the player, clamped to the bounds (step() does this every tick).
func update_view() -> void:
	var r := Rect2(player.pos - view_size * 0.5, view_size)
	if bounds.size.x > view_size.x:
		r.position.x = clampf(r.position.x, bounds.position.x, bounds.end.x - view_size.x)
	else:
		r.position.x = bounds.get_center().x - view_size.x * 0.5
	if bounds.size.y > view_size.y:
		r.position.y = clampf(r.position.y, bounds.position.y, bounds.end.y - view_size.y)
	else:
		r.position.y = bounds.get_center().y - view_size.y * 0.5
	view = r


## The active buffs' totals that feed the caster (matk, watk, acc, attack_speed); a change refreshes _refresh_caster.
func _caster_buff_totals() -> Vector4:
	return Vector4(buffs.effect_total("matk"), buffs.effect_total("watk"), buffs.effect_total("acc"),
		buffs.effect_total("attack_speed"))


## Active Hyper Body percentages: Vector2(Max HP %, Max MP %), integers like 2..60 straight from the buff snapshots.
func _max_buff_percents() -> Vector2:
	return Vector2(buffs.effect_total(MAX_HP_PCT), buffs.effect_total(MAX_MP_PCT))


## Recomputes the maxima when the Hyper Body percentages changed (cast or expiry). Current HP/MP keep their values
## except that the new maximum clamps them (refresh_player_stats; nothing is granted).
func _refresh_max_buffs() -> void:
	if _max_buff_percents() != _max_buff_applied:
		refresh_player_stats(false)


func _tick_timers(dt: float) -> void:
	var caster_buffs := _caster_buff_totals()
	_hp = minf(_max_hp, _hp + upkeep.tick(dt, events))
	if caster_buffs != _caster_buff_totals():
		_refresh_caster()
	_refresh_max_buffs()
	refresh_player_speed()
	if _dead:
		return
	for _pulse in upkeep.regen_pulses(dt):
		_hp = minf(_max_hp, _hp + upkeep.pulse_hp() + hp_regen + loadout.regen_bonus("hp", progression.level))
		_mp = minf(_max_mp, _mp + upkeep.pulse_mp() + mp_regen + loadout.regen_bonus("mp", progression.level))
	var recovery := upkeep.periodic_recovery(dt, loadout)
	_hp = minf(_max_hp, _hp + recovery.x)
	_mp = minf(_max_mp, _mp + recovery.y)
	_end_buffs_above_hp()


## Ends the buffs whose `end_hp_above` fraction the character's HP has passed (Oak Barrel's barrel once HP is back above
## 60%, #194). Runs after every HP change of the tick (potions, buff pulses, regeneration).
func _end_buffs_above_hp() -> void:
	if not buffs.ends_on_hp():
		return
	for skill: String in buffs.active.keys():
		var above := float(buffs.active[skill].get("end_hp_above", 0.0))
		if above > 0.0 and _hp > float(_max_hp) * above:
			buffs.end(skill, events)


func _sync_slots() -> void:
	if mob_skills != null:
		mob_skills.resize(swarm.capacity())
	if mob_attacks != null:
		mob_attacks.resize(swarm.capacity())
	mob_actions.resize(swarm.capacity())
	if mob_summon_owner.size() < swarm.capacity():
		var old := mob_summon_owner.size()
		mob_summon_owner.resize(swarm.capacity())
		for slot in range(old,mob_summon_owner.size()):
			mob_summon_owner[slot] = -1
	if mob_elite.size() < swarm.capacity():
		mob_elite.resize(swarm.capacity())
	if mob_boss.size() < swarm.capacity():
		var old_size := mob_boss.size()
		mob_boss.resize(swarm.capacity())
		for index in range(old_size, mob_boss.size()):
			mob_boss[index] = -1


func _on_kill(m: int) -> void:
	kills += 1
	var mk := swarm.mob_kind(m)
	var elite := mob_elite[m] != 0
	var pos := swarm.pos(m)
	if mob_boss[m] >= 0:
		_on_boss_kill(m, mk, pos, elite)
		return
	var mult := float(balance.get("exp_mult", 1.0)) * float(stage.get("exp_mult", 1.0))
	if elite:
		mult *= float(stage.get("elites", {}).get("exp_mult", 5.0))
	var e := roundi(mk.exp * mult)
	emit("mob_died", {"mob": m, "mob_id": mk.id, "pos": pos, "exp": e, "elite": elite})
	if e > 0:
		var p := pickups.spawn(pos, e, mk.exp_item, player.pos)
		emit("pickup_spawned", {"pickup": p, "item_id": mk.exp_item, "pos": pos,
			"kind": "exp", "potion_kind": "", "count": 0})
	var chances: Dictionary = balance.get("potions", {}).get("drops", {}).get("elite" if elite else "normal", {})
	for kind: String in ["hp", "mp"]:
		var chance := float(chances.get(kind, 0.0))
		# Only HP has a stage curve; normal MP is one flat chance everywhere (owner, 2026-10-16, #80).
		if kind == "hp" and not elite:
			chance = director.normal_hp_drop_chance_at(time, chance)
		if chance > 0.0 and potion_rng.randf() < chance:
			spawn_potion(kind, pos)
	drop_mob_loot(m)


## Normal equipment/meso roll, also callable for a living mob. `single` guarantees exactly one extra Steal item.
## tier C: single loot uses the ordinary equipment chance/pool, else a guaranteed normal meso bundle; no EXP/potions.
## Ordinary death rolls retain their meso-then-equipment order and streams; Steal content never uses stream 15.
func drop_mob_loot(m: int, single := false) -> void:
	var pos := swarm.pos(m)
	var mk := swarm.mob_kind(m)
	var meso_cfg: Dictionary = balance.get("mesos", {})
	var meso_chance := float(meso_cfg.get("chance", 0.0))
	if not single and meso_chance > 0.0 and meso_rng.randf() < meso_chance:
		spawn_meso(pos, _roll_mesos(mk))
	var equip_chance := float(data.get("equipment_drops", {}).get("chance", 0.0))
	if equip_chance > 0.0 and equip_rng.randf() < equip_chance:
		if _drop_equipment(pos, false) and single:
			return
	if single:
		spawn_meso(pos, _roll_mesos(mk))


## Rolls one meso amount for a mob kind: its listed v83 range (or the level fallback) times balance.mesos.mult.
func _roll_mesos(mk: MobKind) -> int:
	var cfg: Dictionary = balance.get("mesos", {})
	var span := MesoDrops.amount_range(mk.level, mk.mesos, cfg.get("fallback", {}))
	return MesoDrops.roll(meso_rng, span, float(cfg.get("mult", 1.0)))


## One equipment drop for the character's current job, level and held weapon family (EquipmentDrops; `boss` takes the
## top of the level window) with v83 random stats, from the equipment stream; nothing when no listed item has info and
## fits. A weapon only drops from the family held now; bare hands get none (#159).
func _drop_equipment(pos: Vector2, boss: bool) -> bool:
	var cfg: Dictionary = data.get("equipment_drops", {})
	var infos: Dictionary = setup.get("equipment_info", {})
	var items: Array = cfg.get("items", [])
	var family := held_weapon_family()
	var id := EquipmentDrops.pick_boss(items, infos, progression.job_id, progression.level, cfg, equip_rng, family) if boss \
		else EquipmentDrops.pick(items, infos, progression.job_id, progression.level, cfg, equip_rng, family)
	if id > 0:
		return spawn_equipment(pos, Equipment.create_drop(id, Equipment.info_of(infos, id), equip_rng)) >= 0
	return false


## Drops an equipment instance on the ground at pos (drawn with the item's icon); the magnet collects it while the
## Equip tab has room, otherwise it lies there (pickup_blocked) until a slot is free. Returns the pickup slot.
func spawn_equipment(pos: Vector2, instance: Dictionary) -> int:
	var slot := pickups.spawn_equipment(pos, instance)
	if slot >= 0:
		equips_dropped += 1
		emit("pickup_spawned", {"pickup": slot, "item_id": int(instance.id), "pos": pos,
			"kind": "equip", "potion_kind": "", "count": 1})
	return slot


## Drops `amount` mesos on the ground at pos (the sprite follows the amount); the magnet collects them like EXP.
func spawn_meso(pos: Vector2, amount: int) -> int:
	var slot := pickups.spawn_meso(pos, amount)
	if slot >= 0:
		emit("pickup_spawned", {"pickup": slot, "item_id": pickups.item_id[slot], "pos": pos,
			"kind": "meso", "potion_kind": "", "count": amount})
	return slot


## A scheduled boss died: boss_died, mob_died with the boss reward EXP (canonical EXP x rewards.exp_mult; no ordinary
## EXP or random potion rolls), its canonical revive list, then the reward shower and bonus choices.
func _on_boss_kill(m: int, mk: MobKind, pos: Vector2, elite: bool) -> void:
	var rewards := bosses.reward_config(mob_boss[m])
	var e := maxi(0, roundi(mk.exp * float(rewards.get("exp_mult", 1.0))))
	bosses.mark_dead(mob_boss[m], m, pos, self)
	emit("mob_died", {"mob": m, "mob_id": mk.id, "pos": pos, "exp": e, "elite": elite})
	_spawn_revives(m, pos)
	_drop_boss_rewards(pos, e, mk.exp_item, rewards)
	_drop_boss_mesos(pos, mk, float(rewards.get("spread", 0.0)))
	var spread := float(rewards.get("spread", 0.0))
	for i in int(data.get("equipment_drops", {}).get("boss_drops", 0)):
		_drop_equipment(pos + Vector2(equip_rng.randf_range(-spread, spread) if spread > 0.0 else 0.0, 0), true)


## balance.mesos.boss_drops bundles, each rolled from the boss's range and scattered over `spread` px (no chance roll).
func _drop_boss_mesos(pos: Vector2, mk: MobKind, spread: float) -> void:
	var count := int(balance.get("mesos", {}).get("boss_drops", 0))
	for i in count:
		var point := pos + Vector2(meso_rng.randf_range(-spread, spread) if spread > 0.0 else 0.0, 0)
		spawn_meso(point, _roll_mesos(mk))


func _spawn_revives(source: int, pos: Vector2) -> void:
	var id: int = mob_kinds[swarm.kind[source]].id
	var list: Dictionary = mob_img(id).get("info", {}).get("revive", {})
	if list.is_empty() or swarm.platform[source] < 0:
		return
	# Every canonical revive entry is spawned once (Skill200's living limit applies to casts, not to this list).
	var children: Array[Dictionary] = []
	for slot in spawn_offspring(source, pos.x, StageRoster.list_ids(list), mob_boss[source]):
		children.append({"mob": slot, "mob_id": swarm.mob_kind(slot).id})
	emit("mob_revives_spawned", {"boss_index": mob_boss[source], "mob": source, "mob_id": id,
		"pos": pos, "revives": children, "time": time})


func _drop_boss_rewards(pos: Vector2, total: int, item_id: int, config: Dictionary) -> void:
	var count := mini(total, maxi(1, int(config.get("exp_drops", 1))))
	var spread := float(config.get("spread", 0.0))
	for i in count:
		var amount := total / count + (1 if i < total % count else 0)
		var point := pos + Vector2(reward_rng.randf_range(-spread, spread), 0)
		var slot := pickups.spawn(point, amount, item_id, player.pos)
		emit("pickup_spawned", {"pickup": slot, "item_id": item_id, "pos": point,
			"kind": "exp", "potion_kind": "", "count": 0})
	var bundles: Dictionary = config.get("potions", {})
	var potion_spread := float(config.get("potion_spread", 0.0))
	spawn_potion("hp", pos - Vector2(potion_spread, 0), int(bundles.get("hp", 0)))
	spawn_potion("mp", pos + Vector2(potion_spread, 0), int(bundles.get("mp", 0)))
	pending_bonus_choices += maxi(0, int(config.get("bonus_choices", 1)))


func _touch() -> void:
	# Hidden (#194): walking into a monster deals no contact damage.
	if _dead or god or upkeep.invincible_t > 0.0 or is_hidden():
		return
	var box := player_box()
	var c := box.get_center()
	var n := mob_grid.query_radius(c, body.size.length() * 0.5 + body_pad, _touch_buf)
	for j in n:
		var m := _touch_buf[j]
		# tier C (owner): a frozen monster deals no touch damage.
		if not swarm.can_act(m):
			continue
		var mk: MobKind = mob_kinds[swarm.kind[m]]
		if not mk.body_attack:
			continue
		if not mk.hitbox_at(swarm.x[m], swarm.y[m], swarm.facing[m]).intersects(box):
			continue
		_player_hit(m, mk)
		return


func _player_hit(m: int, mk: MobKind) -> void:
	var boss_index := mob_boss[m]
	var source := {"mob": m, "mob_id": mk.id, "accuracy": mk.acc,
		"elite": mob_elite[m] != 0, "boss": boss_index >= 0, "source_kind": "touch"}
	if boss_index >= 0:
		source["dmg_mult"] = bosses.damage_multiplier(boss_index)
	# Threaten (#183): a threatened mob's contact weapon attack is lowered by the level's flat amount, floor 0.
	var attack := swarm.threatened_pad(m, float(mk.pad))
	take_hit(attack, false, "", Vector2(swarm.x[m], swarm.y[m]), source)


## Defense inputs for a monster hit; overridable by subsequent equipment and buff rules.
func hit_defense() -> Dictionary:
	return {"pdd": player_pdd + buffs.effect_total("pdd"), "mdd": player_mdd + buffs.effect_total("mdd"), "resistance": {}}


## Magic Guard's current percentage; overridable by the timed-buff rules.
func magic_guard_ratio() -> float:
	return buffs.effect_total("mp_guard")


## Only explicit source scaling: elites use stage.elites.damage_mult; boss sources may pass dmg_mult.
func hit_source_multiplier(source: Dictionary) -> float:
	var mult := float(source.get("dmg_mult", 1.0))
	if bool(source.get("elite", false)):
		mult *= float(stage.get("elites", {}).get("damage_mult", 1.0))
	return mult


## Whether the hit window (hit invincibility) turns this source's hit away right now. Boss skill attacks and balls
## ignore it (spec #88, tier C); this is the window only: god and death are take_hit's own guards. Balls ask this before
## take_hit, since take_hit returns 0 for a blocked hit and a miss alike.
func hit_window_blocks(source: Dictionary) -> bool:
	return _window_blocks(PlayerUpkeep.bypasses_window(source))


## The window check for a source already classified by PlayerUpkeep.bypasses_window (take_hit classifies once).
func _window_blocks(bypass: bool) -> bool:
	return upkeep.invincible_t > 0.0 and not bypass


## Applies one monster hit through avoid, defense, Magic Guard and hit reaction; returns whole damage (0 on miss).
## Source fields: accuracy (canonical acc), elite, dmg_mult, mob, mob_id, boss. Events snapshot max_hp at hit time.
func take_hit(attack: float, magic: bool, element: String, source_pos: Vector2, source: Dictionary = {}) -> int:
	var bypass := PlayerUpkeep.bypasses_window(source)
	# Hidden (#194): nothing from a monster lands, whatever its source (the callers also skip the attack itself).
	if _dead or god or _window_blocks(bypass) or is_hidden():
		return 0
	var dir := 1 if player.pos.x >= source_pos.x else -1
	if CombatMath.roll_miss(player_avoid + buffs.effect_total("avoid"), float(source.get("accuracy", 0.0)), rng):
		_emit_player_hit(0, 0, true, dir, source)
		return 0
	var dmg := CombatMath.monster_hit(attack, magic, element, hit_defense(), rng,
		hit_source_multiplier(source))
	if not magic:
		# tier C: apply canonical Invincible percent to the whole weapon hit, before Magic Guard; minimum 1.
		dmg = maxi(1, roundi(dmg * (1.0 - clampf(buffs.effect_total("weapon_damage_reduction"), 0.0, 100.0) / 100.0)))
	# Power Guard (#182): a no-op, with no RNG and no event, unless the buff is active and this is contact damage.
	var reflect := _power_guard_reflect(dmg, magic, source)
	dmg -= reflect
	var split := CombatMath.magic_guard_split(dmg, magic_guard_ratio(), floori(_mp))
	_hp -= split.x
	_mp -= split.y
	_emit_player_hit(dmg, split.y, false, dir, source)
	upkeep.land_hit(bypass)
	if reflect > 0:
		_apply_reflect(int(source.mob), reflect)
	if _hp <= 0.0:
		_hp = 0.0
		_dead = true
		state = DEAD
		emit("player_died", {"pos": player.pos})
	else:
		player.knockback(dir)
	_write_player_state(0.0)
	return dmg


## Power Guard (#182, spec #165): the part of `damage` (the hit after defence and Invincible, before Magic Guard's split)
## that goes back to the touching monster. Contact damage only (`source_kind` "touch"; mob attacks, boss attacks,
## projectiles and magic are never reflected). Amount = damage x the buff's x%, halved against a boss, at most 10% of
## that monster's Max HP; 0 when no Power Guard is active. Tier B: the rule (third-party v83 reimplementation).
## Tier C: both amounts are floored, so a monster whose 10% floors to 0 reflects nothing and the hit is not reduced.
func _power_guard_reflect(damage: int, magic: bool, source: Dictionary) -> int:
	if magic or String(source.get("source_kind", "")) != "touch":
		return 0
	var percent := buffs.effect_total(POWER_GUARD_STAT)
	var m := int(source.get("mob", -1))
	if percent <= 0.0 or m < 0 or m >= swarm.capacity() or swarm.active[m] == 0:
		return 0
	var boss: bool = mob_boss[m] >= 0 or (mob_kinds[swarm.kind[m]] as MobKind).boss
	var amount := floori(float(damage) * percent * (0.5 if boss else 1.0) / 100.0)
	return clampi(amount, 0, floori(float(swarm.max_hp[m]) * POWER_GUARD_CAP))


## Hands a Power Guard reflect to monster `m` as the character's own damage (tier C): a damage number, and a kill gives
## EXP and drops like any other. It does not go through the hit listeners (no Final Attack, no on-hit status).
func _apply_reflect(m: int, amount: int) -> void:
	var mk: MobKind = mob_kinds[swarm.kind[m]]
	var key := buffs.skill_with_effect(POWER_GUARD_STAT)
	emit("mob_hit", {"mob": m, "mob_id": mk.id, "damage": amount, "crit": false,
		"pos": Vector2(swarm.x[m], swarm.y[m] + mk.hitbox.position.y), "hit_visual": "", "skill": key})
	_instant_dealt += amount
	if swarm.apply_hit(m, amount, 1 if swarm.x[m] >= player.pos.x else -1):
		_on_kill(m)


func _emit_player_hit(damage: int, mp_absorbed: int, miss: bool, dir: int, source: Dictionary) -> void:
	emit("player_hit", {"damage": damage, "mp_absorbed": mp_absorbed, "miss": miss, "dir": dir,
		"pos": player.pos, "mob": int(source.get("mob", -1)), "mob_id": int(source.get("mob_id", 0)),
		"boss": bool(source.get("boss", false)), "max_hp": _max_hp, "source_kind": String(source.get("source_kind", "other"))})


## Whether auto-actions may cast now: hanging on a rope/ladder blocks new casts, not their cooldowns or effects.
func can_cast() -> bool:
	return state == PLAYING and not _dead and player.state != PlayerMotion.ST_LADDER


func _gain_exp(n: int) -> void:
	var before := progression.level
	var gained := progression.add_exp(n)
	for k in gained:
		_on_level_up(before + k + 1)


func _on_level_up(level: int) -> void:
	var g: Dictionary = _job_value(balance.get("growth", {}), {})
	_base_hp += float(g.get("hp", 0.0))
	# Improved MaxHP Increase: the skill's HP per level-up at its rank now, never retroactive (tier B, v83 Cosmic).
	_base_hp += loadout.passive_total(Loadout.MAX_HP_PER_LEVEL)
	_base_mp += float(g.get("mp", 0.0))
	var divisor := float(g.get("int_mp_divisor", 0.0))
	if divisor > 0.0:
		_base_mp += floorf(float(_attributes.int) / divisor)
	_earned_ap += int(balance.get("player", {}).get("ap_per_level", 5))
	_level_ranks(level)
	refresh_player_stats(false)
	var refill: Dictionary = balance.get("level_up_refill", DEFAULT_LEVEL_UP_REFILL)
	_hp = minf(_max_hp, _hp + float(refill.get("hp", DEFAULT_LEVEL_UP_REFILL.hp)) * _max_hp)
	_mp = minf(_max_mp, _mp + float(refill.get("mp", DEFAULT_LEVEL_UP_REFILL.mp)) * _max_mp)
	emit("level_up", {"level": level})


## Skills with `level_ranks` ({character level: rank}, skills.json) reach at least that rank at that level (like the
## SP a v83 Beginner spends on Three Snails); cards may get there sooner.
func _level_ranks(level: int) -> void:
	for key: String in loadout.order:
		var lr: Variant = book.def(key).get("level_ranks")
		if not (lr is Dictionary):
			continue
		var want := 0
		for k: Variant in lr:
			if int(k) <= level:
				want = maxi(want, int(lr[k]))
		if want > loadout.rank(key):
			loadout.set_rank(key, want)


## The current job's table entry, else its nearest ancestor's. AP tables optionally check "<job>:<weapon_path>"
## before that job's plain key; a branch's own row therefore wins over its first-job path's row.
func _job_value(table: Variant, fallback: Variant, by_path := false) -> Variant:
	if not (table is Dictionary):
		return fallback
	for j in jobs.lineage(progression.job_id):
		var path_key := "%d:%s" % [j, weapon_path]
		if by_path and weapon_path != "" and table.has(path_key):
			return table[path_key]
		if table.has(str(j)):
			return table[str(j)]
	return table.get("0", fallback)


func _advance_queue() -> void:
	while pending_bonus_choices > 0:
		choice_bonus = true
		var bonus_cards := upgrades.roll_choices(self, card_rng, 3)
		pending_cards = bonus_cards
		state = CHOOSING_UPGRADE
		emit("choice_pending", {"cards": bonus_cards.duplicate(true), "bonus": true, "advancement": false})
		return
	while progression.has_pending():
		var lvl := progression.front()
		if not _job_checked:
			_job_checked = true
			if jobs.should_offer(progression.job_id, lvl):
				pending_jobs = jobs.advancements(progression.job_id, lvl)
				state = CHOOSING_JOB
				emit("job_advance_pending", {"options": pending_jobs.duplicate(true)})
				return
		choice_bonus = false
		var cards := upgrades.roll_choices(self, card_rng, 3)
		pending_cards = cards
		state = CHOOSING_UPGRADE
		emit("choice_pending", {"cards": cards.duplicate(true), "bonus": false, "advancement": false})
		return
	state = PLAYING


func _write_player_state(dt: float) -> void:
	var a := "dead" if _dead else player.stance()
	if not _dead and upkeep.cast_left > 0.0 and (player.state == PlayerMotion.ST_STAND
			or (upkeep.action_airborne and player.state == PlayerMotion.ST_AIR)):
		a = upkeep.cast_action
	if a != _action:
		_action = a
		_action_t = 0.0
	else:
		_action_t += dt
	player_state["hp"] = ceili(_hp) if _hp > 0.0 else 0
	player_state["mp"] = floori(_mp)
	player_state["mp_short"] = runner.waiting_mp
	player_state["buffs"] = buffs.snapshot()
	player_state["hidden"] = is_hidden()
	player_state["morph"] = 0 if _dead else morph_id()
	player_state["max_hp"] = _max_hp
	player_state["max_mp"] = _max_mp
	player_state["exp"] = progression.exp
	player_state["exp_next"] = progression.exp_to_next()
	player_state["slow"] = mob_skills.slow_state(time)
	player_state["level"] = progression.level
	player_state["job_id"] = progression.job_id
	for stat: String in _attributes:
		player_state[stat] = _attributes[stat]
	player_state["pdd"] = player_pdd
	player_state["mdd"] = player_mdd
	player_state["avoid"] = player_avoid + buffs.effect_total("avoid")
	# Total accuracy also feeds outgoing critical chance (every job and damage type; no player MISS).
	player_state["acc"] = loadout.acc
	player_state["fortune"] = _own_fortune() + cash_fortune
	player_state["invincible_t"] = upkeep.invincible_t
	player_state["action"] = _action
	player_state["action_t"] = _action_t
	player_state["action_scale"] = upkeep.action_scale
	player_state["dead"] = _dead
	player_state["potions"] = potions.snapshot()
