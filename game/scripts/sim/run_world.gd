class_name RunWorld
extends RefCounted
## One survivor run (docs/ARCHITECTURE.md 4.3, 4.4, 4.4.1-4.4.3): built from a setup Dictionary, advanced by fixed
## 1/60 s step() calls, reporting what happened through `events`. Pure: no nodes, input, time, files or autoloads.
##
## Per PLAYING tick: drinks -> portals/movement -> view/timers (regen/buffs) -> swarm -> boss lifecycle,
## skills/attacks/monster balls -> ordinary spawns/hash -> SkillRunner -> player shots/kills/rewards ->
## pickups -> touch -> collected EXP/level-ups -> state snapshot. Death during that tick takes priority. After all
## bosses and choices finish, clear settlement sweeps drops and resolves their choices without another combat tick.
##
## Pause protocol (4.4.2): step() does nothing unless `state` is PLAYING. Each queued level opens CHOOSING_UPGRADE +
## choice_pending with cards drawn when the window opens; apply_choice(id) applies the card and moves to the next queued
## level, clear settlement or PLAYING. It returns false (and changes nothing) in the wrong state or with an id that is not
## on offer.
##
## The character's job (ADR 0006): one job, fixed for the round and the character's life. progression.job_id holds it;
## set_job() is its only writer: _init_player calls it once with the character's job (a restored snapshot's job_id, else
## setup.job, else JobTree.default_job()), and a fresh round learns that job's JobTree.start_skills at rank 1. There is no
## advancement, no weapon path and no basic attack; weapons gate no skill.
##
## Events: every emitted Dictionary has `type` plus exactly the fields of EVENT_FIELDS[type]. `player_hit.damage` is the
## whole hit (the number shown); `miss` hits do no damage and
## cause no knockback or invincibility. `choice_pending` card `rank` is the
## rank the card gives when taken. Swarm/projectile/pickup visuals are read from state (4.4.3).
##
## Player stats live in `player_state` (hp, max_hp, exp, level, job_id, str, dex, int, luk, pdd, mdd,
## avoid, acc, fortune (survivor card-tier stat, separate from LUK), invincible_t, action,
## action_t, action_scale, dead, plus exp_next = EXP needed for the next level); `action` is the body stance to draw
## ("dead", the cast stance while standing, else PlayerMotion.stance()), `action_t` seconds since it started,
## `action_scale` the fraction of the canonical frame time an attack stance plays in (attack speed). Main stats, W.DEF,
## M.DEF, acc, avoid and max HP are totals: worn equipment's `inc*` adds on top of the base (equipment_bonus()).
##
## Live character state (docs/ARCHITECTURE.md 4.4): RunWorld owns the character's worn equipment and inventory
## (`equipment`, the Equipment state shape), `scrolls` and `mesos`. UI and bots change them only through these
## methods, which apply the pure Equipment functions, refresh the derived stats and emit `equipment_changed`; each
## returns "" on success or an Equipment reason (reqLevel, reqJob, reqSTR..., inventory_full, no_item, empty) and then
## changes nothing:
##   equip_item(inventory_index)  - wear an inventory item (only the item's job class is checked, #292)
##   unequip_item(slot)           - move a worn item to the inventory
##   discard_item(inventory_index) - destroy an inventory item (worn items cannot be discarded)
## Equipment drops (#109) come from kills and bosses (EquipmentDrops, equipment_drops.json); collecting one appends it
## to the inventory (`equipment_changed` action "pickup") while the Equip tab has room, otherwise it stays on the
## ground and `pickup_blocked` (reason inventory_full) is emitted. equips_dropped / equips_collected count them. An item
## for an empty slot that displaces nothing and whose requirements are met is then worn at once (action "auto_equip",
## Equipment.auto_wear_error, #222).
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
## weapon_id() is the worn weapon (0 bare-handed), weapon_attack() the W.ATT summed over all worn items.
##
## Separate seeded RNG streams keep e.g. card draws independent of damage rolls: 1 combat rolls, 2 spawning, 3 card
## draws, 4 drop pops, 5 reserved (the removed basic attack, #284), 6 boss reward scatter, 7 reserved (removed potion
## rolls, spec #237), 8 reserved (the removed bot job draws, #284),
## 9 meso drop chance and amount rolls, 10 equipment drop chance, item and stat rolls, 11 scroll success and curse rolls,
## 12 Final Attack proc and follow-up damage/crit rolls; 13 Threaten (spec #165; no prop in v83, so unused),
## 14 reserved for Bowman,
## 15 Thief-only rolls (thief_rng, Steal success in #214),
## 16 Pirate-only rolls (pirate_rng, e.g. Oak Barrel's failure chance in #194),
## 17 Banish destination portal draws (banish_rng, MobSkill 129 in #256).
## Each stream has exactly one owner.

const PLAYING := 0
const CHOOSING_UPGRADE := 1
const DEAD := 2
const CLEARED := 3
const STATE_NAMES := ["PLAYING", "CHOOSING_UPGRADE", "DEAD", "CLEARED"]
## Production stage names for the optional clock-free instrumentation callback, in execution order.
const STEP_PARTS := ["player", "monsters", "player_attacks", "pet", "pickups", "touch", "gain_exp",
	"player_state", "end_tick"]

## Event type -> its fields (besides `type`), docs/ARCHITECTURE.md 4.4.3.
const EVENT_FIELDS := {
	"teleport": ["skill", "skill_id", "level", "phase", "pos", "facing", "effect"],
	"cast": ["skill", "skill_id", "level", "pos", "facing", "action", "effect"],
	"player_restored": ["stat", "amount", "skill", "pos"],
	"final_attack": ["skill", "skill_id", "level", "mob", "pos", "facing", "action", "effect"],
	"skill_impact": ["skill", "pos", "effect"],
	# tier C: a presentation-only ammo flight; Final Attack damage still lands immediately on stream 12.
	"ammo_shot": ["skill", "from", "to", "seconds", "ball", "rotate"],
	"boss_skill": ["mob", "mob_id", "skill_id", "level", "pos", "facing", "action", "duration", "effect", "player_effect", "targets", "summon_effect", "recipient_effect"],
	# #256: a boss's Banish (MobSkill 129) moved the character from `from` to `pos` on the same map.
	"player_banished": ["mob", "mob_id", "skill_id", "level", "from", "pos", "effect", "message"],
	"buff_cast": ["skill", "skill_id", "level", "duration"],
	"buff_expired": ["skill", "skill_id"],
	# #194: a buff cast with a failure chance (Oak Barrel) that failed; nothing started.
	"buff_failed": ["skill", "skill_id", "level"],
	"buff_pulse": ["skill", "skill_id", "amount"],
	"mob_spawned": ["mob", "mob_id", "pos", "elite", "relocated_from"],
	"mob_hit": ["mob", "mob_id", "damage", "crit", "pos", "hit_visual", "skill"],
	"mob_status_applied": ["mob", "mob_id", "status", "duration"],
	"skill_mob_effect": ["skill", "mob", "pos", "effect"],
	"mob_status_expired": ["mob", "mob_id", "status"],
	"mob_died": ["mob", "mob_id", "pos", "exp", "elite"],
	"mob_revives_spawned": ["boss_index", "mob", "mob_id", "pos", "revives", "time"],
	"player_hit": ["damage", "miss", "dir", "pos", "mob", "mob_id", "boss", "max_hp", "source_kind"],
	"player_jump": ["pos"],
	"portal_used": ["portal", "target", "pos"],
	"player_died": ["pos"],
	"pickup_spawned": ["pickup", "item_id", "pos", "kind", "potion_kind", "count"],
	"pickup_collected": ["pickup", "item_id", "exp", "pos", "kind", "potion_kind", "count", "collector"],
	"potion_used": ["kind", "item_id", "restored"],
	# Spec #34 pet events (only with a pet out): its own drinks (never counted as the player's) and its teleports.
	"pet_potion_used": ["kind", "item_id", "restored"],
	"pet_teleported": ["from", "pos"],
	"potion_tier_up": ["kind", "from_item_id", "item_id"],
	"level_up": ["level"],
	"choice_pending": ["cards", "bonus"],
	"upgrade_applied": ["id", "rank", "tier", "magnitude"],
	"skill_learned": ["skill", "skill_id"],
	"burst": ["count"],
	"stage_cleared": ["time"],
	"map_cleared": ["map_index"],
	"map_entered": ["map_index", "map_id"],
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
	"skill_landed": ["skill", "cast_time", "pos", "effect"],

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
## balance.level_up_refill fallback: fraction of the new maximum HP restored per level-up. Tier C (owner choice: no
## heal on level-up).
const DEFAULT_LEVEL_UP_REFILL := {"hp": 0.0}
## tier C: px between MobSkill 200 summons and revive offspring when balance.mob_skills has no summon_spacing.
const DEFAULT_SUMMON_SPACING := 24.0
## balance.player.inventory_slots fallback. tier A: a new v83 character's Equip tab has 24 slots.
const DEFAULT_INVENTORY_SLOTS := 24
## Grid candidates skill_box_count checks before it reads the whole query. Performance only, not behaviour (no
## tier): the count is the same for any value.
const BOX_PROBE := 16
## Buff effect stat of Hyper Body (percent of the whole Max HP); a buff leaves current HP alone (spec #165 ticket #184).
const MAX_HP_PCT := "max_hp_pct" # tier B: percent of the whole maximum (GAME_DESIGN 11, Hyper Body); the values are tier A.
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
var potion_rng: RandomNumberGenerator # Stream 7 reserved; never drawn (spec #237).
var meso_rng: RandomNumberGenerator
var equip_rng: RandomNumberGenerator
var scroll_rng: RandomNumberGenerator
var reward_rng: RandomNumberGenerator
## Final Attack's proc and damage/crit rolls only (stream 12, #161).
var final_rng: RandomNumberGenerator
## Thief-only rolls (stream 15, #207): reserved for Steal's success chance (#214).
var thief_rng: RandomNumberGenerator
## Pirate-only rolls (stream 16, #186): today Oak Barrel's failure chance (#194). A future non-Pirate failure chance
## needs its own stream.
var pirate_rng: RandomNumberGenerator
## Banish's destination `sp` portal draws only (stream 17, #256), so a Banish never shifts spawning or map arrivals.
var banish_rng: RandomNumberGenerator
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
## Current map and its entry on the total round clock (tier C: spec #241 scheduled map pacing).
var map_index := 0
var map_entered_at := 0.0
## Entry seconds from round start, indexed by the reached map (map 1 starts at zero).
var map_times: Array = [0.0]
## Presentation may hold this boundary without advancing simulation time; advance_map completes it explicitly.
var transfer_pending := false
var _map_clearing := false
var _map_swept := false
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
## The ammo item the held ranged weapon uses (0 for a melee weapon or bare hands), derived from the weapon family, job and
## level by _sync_ammo; never saved, never consumed (Ammo, spec #151 #155).
var _ammo_id := 0
var _ammo_family := ""
## Cards of the open window.
var pending_cards: Array = []
## Offered cards / selected cards per displayed tier, counting cards once rather than the steps they grant.
var card_tiers_offered := UpgradePool.empty_tier_counts()
var card_tiers_picked := UpgradePool.empty_tier_counts()
## Setup problems the sim worked around (e.g. a pool mob without a mob img).
var warnings := PackedStringArray()
## Largest feet-to-body-box-corner distance over all mob kinds (pads feet-point hash queries).
var body_pad := 64.0
var magnet_r := 90.0
## Additional HP per regeneration pulse; Recovery's separate PlayerBuffs timeline heals independently.
var hp_regen := 0.0
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
var _max_hp := 1
## The Hyper Body Max HP percentage already inside _max_hp; a change refreshes the maximum.
var _max_buff_applied := 0.0
## Common passive state (#289): the Recovery passive's percent of Max HP per second, refreshed with the stats, and the
## fraction of EXP the Holy Symbol bonus has not paid out yet.
var _passive_regen_pct := 0.0
var _passive_speed_pct := 0.0
var _exp_carry := 0.0
var _base_hp := 50.0
var _base_stats := DEFAULT_STATS.duplicate()
var _attributes := {}
var _earned_ap := 0
## Tiers the character started the round with (CharacterSnapshot.tiers_unlocked); tier 1 is always unlocked.
var _tiers_unlocked := 1
var _base_fortune := 0.0
## Spec #34 cash items. `setup.account` ({owned: [item ids]}, absent = an empty account) decides which of the
## character's worn cash equipment and pet count; `setup.alert` ({hp}: a fraction of max HP, 0 = do not alert).
## worn_cash: {slot: id} of the cash slots actually filled by owned items; pet: the owned pet species out (0 = none);
## cash_fortune: the Fortune those slots add, computed live and added to player_state.fortune, never stored in the
## character; account_owned: the owned item ids; alert: {hp}.
var account_owned: Array = []
var worn_cash := {}
var pet := 0
var cash_fortune := 0.0
var alert := {"hp": 0.0}
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
## The held weapon's swing reach and envelope (weapon_reach skills, Final Attack spread).
var weapon_reach: WeaponReach
var _action := ""
var _action_t := 0.0
var _instant_dealt := 0
var _ctx := {}
var _visual_ids := {}
var _touch_buf := PackedInt32Array()


func _init(p_setup: Dictionary = {}) -> void:
	setup = p_setup
	data = setup.get("data", {})
	balance = data.get("balance", {})
	stage_key = DataRepo.canonical_stage_key(String(setup.get("stage", "")))
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
	add_hit_listener(_final_attack_hit)
	add_hit_listener(_damage_heal_hit)
	add_hit_listener(_steal_hit)
	update_view()
	_write_player_state(0.0)


## One seeded stream per owner (see the header).
func _init_rng_streams() -> void:
	rng = _stream(1)
	# Stream 5 reserved (the removed basic attack, #284): do not renumber any other RNG stream.
	spawn_rng = _stream(2)
	card_rng = _stream(3)
	drop_rng = _stream(4)
	potion_rng = _stream(7) # Reserved: do not renumber any other RNG stream.
	reward_rng = _stream(6)
	# Stream 8 reserved (the removed bot job draws, #284).
	meso_rng = _stream(9) # tier C: meso rolls never shift another stream, #107.
	equip_rng = _stream(10) # tier C: equipment rolls never shift another stream, #109.
	scroll_rng = _stream(11) # tier C: scroll success/curse rolls never shift another stream, #110.
	final_rng = _stream(12) # tier C: Final Attack procs and follow-up rolls never shift another stream, #161.
	thief_rng = _stream(15) # tier C: independent Thief-only rolls; reserved for Steal success, #207/#214.
	pirate_rng = _stream(16) # tier C: Pirate-only rolls never shift another stream; 14 reserved, #186.
	banish_rng = _stream(17) # tier C: Banish portal draws never shift another stream, #256.


## Physics, footholds, bounds, ropes, portals and the two mob navigation graphs from the map img.
func _init_map() -> void:
	var map_img := _current_map_img()
	physics = PhysicsConstants.from_wz(setup.get("physics_img", {}))
	fhm = FootholdMap.from_wz(map_img)
	bounds = MapBounds.from_map(map_img, fhm)
	ladders = LadderSet.from_wz(map_img)
	portals = PortalSet.from_wz(map_img, current_map_id(), balance.get("portals", {}))
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


## Player shots, pickups and unlimited potion cooldowns.
func _init_drops_and_shots() -> void:
	projectiles = ProjectileSystem.new(64, rng)
	projectiles.paths = visual_paths
	projectiles.bounds = bounds
	projectiles.magic_defense_k = float(balance.get("magic_defense_k", CombatMath.MAGIC_DEFENSE_K))
	projectiles.pierce_floor = float(balance.get("combat", {}).get("pierce_floor", 0.0))
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
	loadout.pierce_floor = projectiles.pierce_floor
	var crit: Dictionary = balance.get("crit", {})
	loadout.crit_chance = float(crit.get("chance", 0.0))
	loadout.crit_mult = float(crit.get("mult", 1.5))
	loadout.crit_per_acc = float(crit.get("per_acc", 0.0))
	runner = SkillRunner.new()
	weapon_reach = WeaponReach.new(setup.get("body_img", {}), setup.get("afterimage_imgs", {}))
	progression = RunProgression.new(ExpCurve.from_data(balance.get("exp_curve", {})),
		int(balance.get("max_level", 200)))
	jobs = JobTree.from_data(data.get("jobs", {}), data.get("jobs_survivor", {}))
	upgrades = UpgradePool.from_data(data.get("upgrades", {}))
	upgrades.add_pool_skills(book, jobs)


## Ordinary spawning, the boss schedule and the bosses' canonical skills.
func _init_directors() -> void:
	var spawn_stage := stage
	if not _map_images_available() and stage.has("maps"):
		spawn_stage = stage.duplicate()
		spawn_stage.erase("maps") # no map_imgs: preserve legacy curve pools and the absolute boss schedule
	director = SpawnDirector.create(spawn_stage, kind_of_id, balance.get("spawn", {}))
	var map_imgs: Array = setup.get("map_imgs", [])
	var pools: Array = []
	for i in stage.get("maps", []).size():
		pools.append(StagePools.resolve(stage.maps[i], map_imgs[i] if i < map_imgs.size() else {}))
	director.map_pools = pools
	bosses = BossDirector.new(_stage_bosses(), balance.get("bosses", {}))
	if map_sequence_enabled():
		bosses.arm_map(self)
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


## Scheduled pacing clock; a slow boss kill never pushes the next map's opening ahead (tier C: spec #241).
func curve_time() -> float:
	return map_index * float(stage.get("map_seconds", 300.0)) + (time - map_entered_at)


## Original MapleStory id of the current map; legacy stages retain their single map.
func current_map_id() -> int:
	var maps: Array = stage.get("maps", [])
	return int(maps[map_index].get("map_id", stage.get("map_id", 0))) if not maps.is_empty() \
		else int(stage.get("map_id", 0))


## Transfers require complete map entries and aligned images; pool-only fixtures retain their legacy boss schedule.
func map_sequence_enabled() -> bool:
	if not _map_images_available():
		return false
	for entry: Dictionary in stage.maps:
		if not entry.has("map_id") or entry.get("boss", {}).is_empty():
			return false
	return true


func _map_images_available() -> bool:
	return not stage.get("maps", []).is_empty() and setup.has("map_imgs") \
		and setup.map_imgs.size() == stage.maps.size()


func _current_map_img() -> Dictionary:
	return setup.map_imgs[map_index] if _map_images_available() else setup.get("map_img", {})


func _stage_bosses() -> Array:
	# Legacy/pool-only fixtures retain their absolute schedule; region data uses the binding #243 projection.
	if stage.get("maps", []).is_empty():
		return stage.get("bosses", [])
	for entry: Dictionary in stage.maps:
		if entry.get("boss", {}).is_empty():
			return stage.get("bosses", [])
	var entries := DataRepo.stage_bosses(stage)
	for entry: Dictionary in entries:
		entry.map_id = int(stage.maps[int(entry.map_index)].map_id)
	return entries


## Completes the frozen map boundary. Character state and RNG streams survive; map entities and boss statuses do not.
func advance_map() -> void:
	if not transfer_pending:
		return
	map_index += 1
	map_entered_at = time
	map_times.append(time)
	_init_map()
	# Keep pooled systems and their round counters; empty their map-local contents without kill/drop events.
	for slot in swarm.capacity():
		swarm.despawn(slot)
	swarm.fhm = fhm
	mob_elite.fill(0)
	mob_boss.fill(-1)
	mob_summon_owner.fill(-1)
	mob_grid = SpatialHash.new(64.0, bounds.grow(64.0))
	_ctx.merge({"fhm": fhm, "nav": nav, "nav_jump": nav_jump, "bounds": bounds}, true)
	for slot in projectiles.capacity():
		projectiles.despawn(slot)
	projectiles.bounds = bounds
	for slot in pickups.capacity():
		pickups.despawn(slot)
	_final_queue.clear()
	runner.clear_pending()
	mob_skills = MobSkillRunner.new(setup, balance.get("mob_skills", {}))
	mob_attacks = MobAttacks.new(self)
	mob_actions = MobActions.new()
	mob_projectiles = MobProjectileSystem.new()
	boss_attacks = BossAttacks.new()
	_sync_slots()
	director = director.reset_for_map(map_index, curve_time(), balance.get("spawn", {}))
	player.place(PortalSet.start_point(_current_map_img(), fhm, bounds, spawn_rng), fhm)
	if pet_system != null:
		pet_system.place_beside(player, fhm)
	bosses.arm_map(self)
	refresh_player_speed()
	update_view()
	transfer_pending = false
	_map_clearing = false
	_write_player_state(0.0)
	emit("map_entered", {"map_index": map_index, "map_id": current_map_id()})


## The character as it leaves this round (CharacterSnapshot, format 3): job, look, equipment, scrolls, mesos, cash, pet
## and its unlocked tiers, which a CLEARED round advances. Everything picked up stays, whether the round was cleared, lost
## or quit; the build (level, skills, cards) is not part of it. Always available, even with a choice pending.
func character_snapshot() -> Dictionary:
	var snapshot := {"format": CharacterSnapshot.FORMAT, "job_id": progression.job_id,
		"look": character_look.duplicate(true), "equipment": equipment.duplicate(true),
		"scrolls": scrolls.duplicate(), "mesos": mesos, "tiers_unlocked": tiers_unlocked_now()}
	# Spec #34 optional keys: written only when set, so characters without cash items keep their exact old bytes.
	if not _cash_carried.is_empty():
		snapshot["cash"] = _cash_carried.duplicate()
	if _pet_carried > 0:
		snapshot["pet"] = _pet_carried
	return snapshot


## The tiers the character has unlocked now: those it started the round with, plus the next tier when this round is CLEARED.
func tiers_unlocked_now() -> int:
	var stages: Dictionary = data.get("stages", {})
	return CharacterSnapshot.unlocked_after_round(_tiers_unlocked, NxAward.tier_of(stages, stage_key),
		state == CLEARED, stages.get("tiers", []).size())


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


## The objective is complete only after all mandatory choices; settlement may queue more from swept EXP.
func can_clear() -> bool:
	var objective := bosses.all_dead() if bosses.has_bosses() else time >= duration - 1e-6
	return objective and pending_bonus_choices == 0 and not choice_bonus and not progression.has_pending() \
		and pending_cards.is_empty()


## Drinks one HP potion instantly while playing, including on ropes; false during cooldown or without a restore spec.
func drink_potion(kind: String) -> bool:
	return _drink(kind, false)


## The shared drink: `by_pet` counts it in the pet's totals and reports `pet_potion_used` instead of `potion_used`.
func _drink(kind: String, by_pet: bool) -> bool:
	if state != PLAYING or _dead:
		return false
	var sip := potions.consume(kind, by_pet)
	if sip.is_empty():
		return false
	var before := int(player_state.hp)
	_hp = minf(_max_hp, _hp + int(sip.amount))
	_write_player_state(0.0)
	emit("pet_potion_used" if by_pet else "potion_used", {"kind": kind, "item_id": int(sip.item_id),
		"restored": int(player_state.hp) - before})
	return true


## Upgrades a potion kind's current item, preserving its cooldown and exposing the new icon/restoration immediately; emits
## potion_tier_up.
func upgrade_potion(kind: String, item_id: int) -> bool:
	var from_id := potions.item_id(kind)
	if not potions.upgrade(kind, item_id):
		return false
	_write_player_state(0.0)
	emit("potion_tier_up", {"kind": kind, "from_item_id": from_id, "item_id": item_id})
	return true


## Applies every potion step of balance.potions.schedule due at `level` (PotionSchedule.due: re-scanned each time, no
## applied-step state). Level-ups announce each step; a snapshot load applies them silently. Tier C.
func apply_potion_schedule(level: int, announce: bool) -> void:
	var current := {}
	for kind: String in PotionInventory.DEFAULT_ITEMS:
		current[kind] = potions.item_id(kind)
	for step: Dictionary in PotionSchedule.due(PotionSchedule.steps(balance), level, current):
		if announce:
			upgrade_potion(String(step.kind), int(step.item))
		else:
			potions.upgrade(String(step.kind), int(step.item)) # a load: player_state is written by the caller's setup


## Whether an inactive buff meets its optional survivor HP threshold; casting/cooldown gates remain in SkillRunner.
func can_start_buff(skill: String, stats: Dictionary) -> bool:
	var threshold := float(stats.hp_threshold)
	return not buffs.has(skill) and (threshold <= 0 or _hp < float(_max_hp) * threshold)


## Whether the character is Hidden (docs/GAME_DESIGN.md 7.18): an active buff makes monsters, bosses included, ignore
## the character and stops its attacks. Oak Barrel (#194) and Thief Dark Sight (#167) use it.
func is_hidden() -> bool:
	return buffs.hidden()


## MobSkill 129 Banish (#256): moves the character to a random `sp` portal of the current map other than the one nearest
## it (when there are two or more), dropped onto the floor (PortalSet.start_point_away_from on stream 17, the
## map-arrival placement), brings an out pet beside it like a map arrival
## (`pet_pos` jump announced by `pet_teleported`) and emits `player_banished` with `cast`'s mob, mob_id, skill_id,
## level, effect and message. tier C: v83 sends the character to `info/ban`'s town map, outside the round.
func banish_player(cast: Dictionary) -> void:
	var from := player.pos
	player.place(PortalSet.start_point_away_from(_current_map_img(), fhm, bounds, banish_rng, from), fhm)
	if pet_system != null:
		var pet_from := pet_system.motion.pos
		pet_system.place_beside(player, fhm)
		emit("pet_teleported", {"from": pet_from, "pos": pet_system.motion.pos})
	update_view()
	var fields := cast.duplicate()
	fields.merge({"from": from, "pos": player.pos}, true)
	emit("player_banished", fields)


## The Morph.wz id the character is drawn as while a morphing buff is active, 0 for the plain avatar.
func morph_id() -> int:
	return buffs.morph()


## Starts a resolved timed buff; SkillRunner applies the shared casting gate before this call. A buff with a
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


## Advances the run by dt seconds (no-op unless PLAYING). Optional after_stage(name) observes production boundaries;
## timing stays with the caller. Observers must not mutate the world or draw RNG.
func step(dt: float, input: MoveInput, after_stage: Callable = Callable()) -> void:
	if state != PLAYING or transfer_pending:
		return
	if _settle_map():
		return
	if _settle_clear():
		return
	time += dt
	potions.tick(dt)
	refresh_player_speed()
	_step_player(dt, input)
	if after_stage.is_valid():
		after_stage.call("player")
	_step_monsters(dt)
	if after_stage.is_valid():
		after_stage.call("monsters")
	if _settle_map():
		return
	_step_player_attacks(dt)
	if _settle_map():
		return
	if after_stage.is_valid():
		after_stage.call("player_attacks")
	if pet_system != null:
		_step_pet(dt)
	if after_stage.is_valid():
		after_stage.call("pet")
	var got := _step_pickups(dt)
	if after_stage.is_valid():
		after_stage.call("pickups")
	_touch()
	if after_stage.is_valid():
		after_stage.call("touch")
	if got > 0 and not _dead:
		_gain_exp(got)
	if after_stage.is_valid():
		after_stage.call("gain_exp")
	_write_player_state(dt)
	if after_stage.is_valid():
		after_stage.call("player_state")
	_end_tick()
	if after_stage.is_valid():
		after_stage.call("end_tick")


## Drinks, then a same-map portal warp or ordinary movement, the view, and the player's timers.
func _step_player(dt: float, input: MoveInput) -> void:
	_teleport_left = maxf(0.0, _teleport_left - dt)
	if input.drink_hp:
		drink_potion("hp")
	_try_manual_buffs(input)
	if not _try_rush(input) and not _try_teleport(input) and not _take_portal(dt, input):
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


## Owned manual skill of skill key `id`, or "".
func manual_skill(id: String) -> String:
	for key: String in loadout.order:
		if skill_key_of(key) == id:
			return key
	return ""


## Owned Teleport key (a job line's variant), or "" before the character has one.
func teleport_skill() -> String:
	for key: String in loadout.order:
		if _is_teleport(key):
			return key
	return ""


## HUD readiness of an owned skill: `left` seconds until ready (>= 0), the cooldown `total` set at its last cast
## (0 before any). Teleport reports its repeat timer.
func skill_readiness(key: String) -> Dictionary:
	return {"left": _cooldown_left(key), "total": _cooldown_total(key)}


## The HUD's per-frame readiness of every owned skill, in loadout.order, written into the caller's reused buffers
## (resized in place; nothing is allocated once they have the right size): left and total as skill_readiness reports
## them.
func read_skill_cooldowns(left: PackedFloat32Array, total: PackedFloat32Array) -> void:
	var n := loadout.order.size()
	left.resize(n)
	total.resize(n)
	for i in n:
		var key: String = loadout.order[i]
		left[i] = _cooldown_left(key)
		total[i] = _cooldown_total(key)


## Pressing (or holding) the skill key of a manual buff such as Dash casts it: it needs no cooldown left, no active
## copy and a free casting state; otherwise the press does nothing (no event). Teleport has
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


## A Rush press (or hold): dashes toward the pressed side arrow, else the facing (Up and Down are ignored, as in v83);
## true when the dash started, which replaces this tick's ordinary movement. tier C: ours (#302).
func _try_rush(input: MoveInput) -> bool:
	if not input.skill_requested("rush"):
		return false
	var key := manual_skill("rush")
	if key == "":
		return false
	var side := input.dir() if input.dir() != 0 else player.facing
	return runner.cast_dash(self, key, side)


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
	if dest.is_empty():
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
	_ctx.speed_mult = director.value_at("speed", curve_time())
	# Hidden (#194): the swarm gets no target to chase, so ground mobs patrol and flyers hover.
	_ctx["hidden"] = is_hidden()
	_ctx["boss_actions"] = mob_actions.view(bosses.prepare_actions(self), bosses, swarm, time)
	_ctx["events"] = events
	swarm.step(dt, _ctx)
	bosses.step(self, dt)
	if map_sequence_enabled() and map_index < stage.maps.size() - 1 and bosses.map_done(map_index):
		return # a missing-image skip completes this map without admitting attacks/spawns
	mob_skills.step(self)
	boss_attacks.step(self)
	mob_attacks.step(self, dt)
	mob_projectiles.step(dt, self)
	director.step(dt, self)
	_sync_slots()
	mob_grid.rebuild(swarm.x, swarm.y, swarm.active, swarm.capacity())


## Auto-casts, then the player's shots against live defense/immunity; kills drop their rewards.
func _step_player_attacks(dt: float) -> void:
	runner.step(dt, self)
	if _map_clearing:
		return
	_fill_live_defense()
	if map_sequence_enabled():
		projectiles.step(dt, swarm, mob_grid, events, _live_mdd, _live_physical_allowed,
			_on_player_hit, _live_pdd, _projectile_kill)
	else:
		projectiles.step(dt, swarm, mob_grid, events, _live_mdd, _live_physical_allowed, _on_player_hit, _live_pdd)
		for m in projectiles.kills:
			_on_kill(m)
	if _map_clearing:
		return
	_play_final_attacks()


func _projectile_kill(slot: int) -> bool:
	_on_kill(slot)
	return _map_clearing


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


## Moves and collects drops. Returns the EXP collected this tick.
func _step_pickups(dt: float) -> int:
	var equip_room := maxi(0, inventory_slots() - equipment.inventory.size())
	var got := 0
	if pet_system == null:
		got = pickups.step(dt, player.pos, magnet_r, fhm, events, equip_room)
	else:
		got = pickups.step(dt, player.pos, magnet_r, fhm, events, equip_room, pet_system.center(),
			pet_system.pickup_radius(), pet_system.abilities.vac)
		pet_system.pickups += pickups.pet_collected
	_credit_pickups()
	return got


func _credit_pickups() -> void:
	mesos += pickups.step_mesos
	for instance: Dictionary in pickups.collected_equipment:
		equipment.inventory.append(instance)
		equips_collected += 1
		_equipment_changed("pickup", "", int(instance.id))
		# tier C (ours, #222): an item for an empty slot that this character may wear is worn at once
		if auto_wear_error(int(instance.id)) == "":
			_wear(equipment.inventory.size() - 1, "auto_equip")


## The pet's tick: movement, then its auto-potion drinks (below the ALERT level, using the shared cooldown).
func _step_pet(dt: float) -> void:
	pet_system.step(dt, player, fhm, bounds, pickups, events, maxi(0, inventory_slots() - equipment.inventory.size()))
	if pet_system.should_drink("hp", _hp, _max_hp, float(alert.hp), potions.is_ready("hp")) and _drink("hp", true):
		pet_system.drank("hp")


## What the pet looks like right now ({} without a pet): species, pos (feet), facing (-1/1), action (stand, move, jump,
## hang), fetching, abilities. Position jumps are announced by `pet_teleported` events.
func pet_state() -> Dictionary:
	return pet_system.view() if pet_system != null else {}


## Whether a pet with `ability` (auto_hp, wing_boots, binocular, vac) is out.
func pet_has(ability: String) -> bool:
	return pet_system != null and bool(pet_system.abilities.get(ability, false))


## After a living tick: boss bonus choices first, then clear settlement, then queued level-ups.
func _end_tick() -> void:
	if _dead:
		return
	if _settle_map():
		return
	if pending_bonus_choices > 0:
		_advance_queue()
		if state != PLAYING:
			return
	if _settle_clear():
		return
	if progression.has_pending():
		_advance_queue()


## tier C: owner choices (2026-10-21), clear wins after the last answer and sweeps all map loot before carry.
## Same-tick combat death still wins. Full-tab equipment uses the ordinary blocked-on-ground pickup rule.
func _settle_clear() -> bool:
	if _dead or state == CLEARED or not can_clear():
		return false
	_sweep_map_drops()
	if progression.has_pending():
		_advance_queue() # normal job/advancement/card flow; step stays frozen until every answer is in
	else:
		state = CLEARED
		emit("stage_cleared", {"time": time})
	return true


## Collects and credits clear loot, retrying space freed by auto-wear before applying its EXP.
func _sweep_map_drops() -> void:
	var got := 0
	while true:
		var before := pickups.active_count()
		got += pickups.collect_all(events, maxi(0, inventory_slots() - equipment.inventory.size()))
		_credit_pickups()
		if pickups.active_count() == 0 or pickups.active_count() == before \
				or equipment.inventory.size() >= inventory_slots():
			break
		# Auto-wear may free a slot for another drop; reuse it without admitting a combat tick.
	if got > 0:
		_gain_exp(got)
	_write_player_state(0.0)


## Frozen intermediate-map settlement: sweep once before choices, then discard mobs and await presentation.
func _settle_map() -> bool:
	if not _map_clearing and map_sequence_enabled() and map_index < stage.maps.size() - 1 \
			and bosses.map_done(map_index):
		_map_clearing = true
		_map_swept = false
	if not _map_clearing or _dead:
		return false
	if not _map_swept:
		_map_swept = true
		_sweep_map_drops()
	if pending_bonus_choices > 0 or progression.has_pending():
		_advance_queue()
	elif not transfer_pending:
		for slot in swarm.capacity():
			swarm.despawn(slot)
		transfer_pending = true
		emit("map_cleared", {"map_index": map_index})
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
	if choice_bonus:
		pending_bonus_choices -= 1
		choice_bonus = false
	else:
		progression.pop_front()
	state = PLAYING
	_advance_queue()
	_write_player_state(0.0)
	return true


## Sets the character's job (see the header): the only writer of progression.job_id. It grants, learns and wears
## nothing; the stats that follow the job (AP split, growth, accuracy, ammo) are refreshed. _init_player calls it once;
## tests and debug drivers call it before play to stand a character of another line.
func set_job(job_id: int) -> void:
	progression.job_id = job_id
	refresh_player_stats(false)


## The character's job id (progression.job_id).
func job_id() -> int:
	return progression.job_id


## Learns a skill (emits skill_learned); false when unknown or owned.
func learn_skill(key: String) -> bool:
	if not loadout.add_skill(key):
		return false
	emit("skill_learned", {"skill": key, "skill_id": book.skill_id(key)})
	refresh_player_stats()
	return true


## Restores `fraction` of max HP (stat "hp"); any other stat restores nothing.
func heal_fraction(stat: String, fraction: float) -> void:
	if stat == "hp":
		_hp = minf(_max_hp, _hp + fraction * _max_hp)
	_write_player_state(0.0)


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


## Restores HP (stat "hp"), clamped to its maximum; returns and emits the actual integer gain (no event at zero).
func restore_player(stat: String, amount: int, skill: String) -> int:
	if stat != "hp" or amount <= 0:
		return 0
	var before := ceili(_hp)
	_hp = minf(_max_hp, _hp + amount)
	_write_player_state(0.0)
	var gain := int(player_state[stat]) - before
	if gain > 0:
		emit("player_restored", {"stat": stat, "amount": gain, "skill": skill, "pos": player.pos})
	return gain


## Recomputes max HP, speed, magnet, regen, defence and the caster inputs from the base stats, job and upgrade
## modifiers. Explicit max HP modifiers grant the difference. Equipment refreshes pass grant_growth=false and only
## clamp HP; level growth suppresses flat grants too, before the separate level-up refill (#41).
## `attribute_level` lets a batch EXP gain allocate AP for each intermediate level; -1 uses the current level.
func refresh_player_stats(grant_growth: bool = true, attribute_level: int = -1) -> void:
	# Earned AP splits between the job's secondary stat (AutoAp, ticket #106) and its primary stat: the job's one
	# balance.player.ap row (#284), else its nearest ancestor's.
	var row: Dictionary = _job_value(balance.get("player", {}).get("ap", {}), {})
	var primary := String(row.get("primary", "str"))
	var secondary := String(row.get("secondary", ""))
	if secondary == primary or not _base_stats.has(secondary):
		secondary = ""
	var secondary_ap := 0
	if secondary != "":
		secondary_ap = AutoAp.secondary_ap(_earned_ap, progression.level if attribute_level < 0 else attribute_level,
			float(_base_stats[secondary]), row.get("keyframes", []))
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
	# tier C: equipment max HP adds flat after card modifiers. The Hyper Body buff then scales that whole total (base,
	# growth, passives, equipment; tier B, v83).
	_max_buff_applied = _max_buff_percent()
	# tier C: the Max HP passive (Hyper Body card, #289) scales the same total before the Hyper Body buff does.
	_max_hp = maxi(1, roundi((loadout.player_stat("max_hp", _base_hp) + equipment_bonus("incMHP"))
		* (1.0 + loadout.passive_total(Loadout.MAX_HP_PCT) / 100.0) * (1.0 + _max_buff_applied / 100.0)))
	if grant_growth and _max_hp > old_hp:
		_hp += _max_hp - old_hp
	_hp = minf(_hp, _max_hp)
	_passive_regen_pct = loadout.passive_total(Loadout.REGEN_PCT)
	_passive_speed_pct = loadout.passive_total(Loadout.SPEED_PCT)
	_equipment_speed = equipment_bonus("incSpeed")
	_equipment_jump = equipment_bonus("incJump")
	player_acc = CombatMath.base_accuracy(float(_attributes.dex), float(_attributes.luk), jobs.lineage(progression.job_id)) \
		+ equipment_bonus("incACC")
	refresh_player_speed()
	magnet_r = loadout.player_stat("magnet", float(balance.get("magnet_radius", 90.0)))
	hp_regen = loadout.player_stat("hp_regen", float(balance.get("hp_regen", 0.0)))
	player_pdd = loadout.player_stat("pdd", equipment_bonus("incPDD")) + loadout.passive_total("pdd")
	player_mdd = loadout.player_stat("mdd", equipment_bonus("incMDD")) + loadout.passive_total("mdd")
	player_avoid = loadout.player_stat("avoid", float(_attributes.dex) * AVOID_DEX_FACTOR
		+ float(_attributes.luk) * AVOID_LUK_FACTOR + equipment_bonus("incEVA")) + loadout.passive_total("avoid")
	_refresh_caster()
	_write_player_state(0.0)


## Upgraded movement speed plus worn equipment's incSpeed and active canonical buff points, capped at the v83 140
## (Equipment.SPEED_CAP), then the Haste passive's percent (tier C: applied after the cap, #289), then composed with the
## canonical-area slow. The passive percent is read when the stats were last refreshed.
func player_speed_stat() -> float:
	var speed := loadout.player_stat("speed", 100.0) + _equipment_speed + buffs.effect_total("speed")
	return minf(speed, Equipment.SPEED_CAP) * (1.0 + _passive_speed_pct / 100.0) \
		* mob_skills.speed_multiplier(time)


func _refresh_caster() -> void:
	loadout.weapon_id = weapon_id()
	loadout.weapon_family = held_weapon_family()
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
	# Passives (#161): mastery replaces the untrained 10%; crit chance is a percent; crit damage is the
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


## Attack speed steps the active Boosters add (positive = faster).
func attack_speed_boost() -> int:
	return roundi(buffs.effect_total("attack_speed"))


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


## Starts a stance for its frame time; airborne plays the same stance in the air without changing motion; `scale`
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
	return _wear(index, "equip")


## Whether item `id` would be worn the moment it is picked up (#222): "" or the Equipment.auto_wear_error reason.
func auto_wear_error(id: int) -> String:
	return Equipment.auto_wear_error(equipment.worn, id, Equipment.info_of(setup.get("equipment_info", {}), id),
		_wearer())


## The character fields Equipment checks requirements against: only the job (ADR 0006, #292).
func _wearer() -> Dictionary:
	return {"job_id": progression.job_id}


## Wears inventory item `index` and emits `equipment_changed` with `action` ("equip", or "auto_equip" from a pickup).
func _wear(index: int, action: String) -> String:
	if index < 0 or index >= equipment.inventory.size():
		return "no_item"
	var id := int(equipment.inventory[index].id)
	var reason := Equipment.equip(equipment, index, Equipment.info_of(setup.get("equipment_info", {}), id), _wearer(),
		inventory_slots())
	if reason == "":
		_equipment_changed(action, Equipment.slot_of(id), id)
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


## Adds up to `count` scrolls to the Use tab's 24 slots (a stack stops at its info/slotMax, 100 without one);
## returns how many were added. Test and tool hook.
func grant_scrolls(scroll_id: int, count: int) -> int:
	return Scrolls.add(scrolls, scroll_id, count, int(scroll_info(scroll_id).get("slotMax", 0)),
		Shop.use_stack_limit())


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
	return {"mesos": mesos, "scrolls": scrolls, "equipment": equipment}


func _shop_done(action: String, item_id: int, state: Dictionary) -> void:
	mesos = int(state.mesos)
	emit("equipment_changed", {"action": action, "slot": "", "item_id": item_id})


func _equipment_changed(action: String, slot: String, id: int) -> void:
	refresh_player_stats(false)
	emit("equipment_changed", {"action": action, "slot": slot, "item_id": id})


## Wears a new instance of item `id` (its canonical stats from setup.equipment_info) without requirements; what it
## displaces goes to the Equip tab. "" or Equipment.grant's reason (inventory_full), changing nothing then. A hook for
## tests, debug drivers and fixture tools only: no gameplay path grants an item (#284 removed the job weapon grant).
func wear_new_item(id: int) -> String:
	var error := Equipment.grant(equipment, Equipment.create(id, Equipment.info_of(setup.get("equipment_info", {}), id)),
		inventory_slots())
	if error == "":
		_equipment_changed("grant", Equipment.slot_of(id), id)
	return error


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


## Spawns kind k with HP scaled by hp_mult and the round opening ramp; bosses capture it on arrival. Emits mob_spawned.
func spawn_mob(k: int, pos: Vector2, fh: int, hp_mult: float, elite: bool) -> int:
	if k < 0 or k >= mob_kinds.size():
		return -1
	var mk: MobKind = mob_kinds[k]
	hp_mult *= opening_multiplier("hp")
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
## kind spawned there with its logical identity, HP, max HP and elite flag, fading in; emits mob_spawned with relocated_from =
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


## One instant damage line with live defence; hv = hit visual index. Optional hit_rng replaces stream 1 (Final Attack's 12).
func hit_mob(m: int, st: Dictionary, hv: int, hit_rng: RandomNumberGenerator = null) -> void:
	if _map_clearing or swarm.active[m] == 0:
		return
	var dtype := CombatMath.damage_type_of(String(st.get("damage_type", "")), bool(st.get("magic", false)))
	var magic := dtype == "magic"
	if not magic and not physical_hit_allowed(m):
		return
	var mk: MobKind = mob_kinds[swarm.kind[m]]
	var roll := ProjectileSystem.roll_damage(float(st.damage_min), float(st.damage_max), magic,
		mob_defense(m, magic), projectiles.magic_defense_k, float(st.crit), float(st.crit_mult),
		hit_rng if hit_rng != null else rng, swarm.element_multiplier(m, String(st.get("element", ""))), dtype,
		float(st.get("damage_pct", 1.0)), float(st.get("crit_damage_bonus", 0.0)))
	var dir := 1 if swarm.x[m] >= player.pos.x else -1
	emit("mob_hit", {
		"mob": m, "mob_id": mk.id, "damage": roll.x, "crit": roll.y != 0,
		"pos": Vector2(swarm.x[m], swarm.y[m] + mk.hitbox.position.y),
		"hit_visual": String(visual_paths[hv]) if hv >= 0 else "", "skill": String(st.skill),
	})
	_instant_dealt += roll.x
	if roll.x > 0:
		_on_player_hit(m, {"skill": String(st.skill), "level": int(st.get("level", 0)), "magic": magic,
			"damage": roll.x, "element": String(st.get("element", "")), "damage_type": dtype,
			"push_side": int(st.get("push_side", 0))})
	if swarm.apply_hit(m, roll.x, dir):
		_on_kill(m)


## Registers a listener(slot, hit) after on-hit statuses and before damage/kill resolution, once per damaging line.
func add_hit_listener(listener: Callable) -> void:
	_hit_listeners.append(listener)


func _damage_heal_hit(slot: int, hit: Dictionary) -> void:
	var key := String(hit.skill)
	var heal: Dictionary = book.def(key).get("damage_heal", {})
	if heal.is_empty():
		return
	var percent := book.canonical(key, int(hit.level), String(heal.percent_field))
	# tier C: truncate fractional healing to whole HP after the resolved damage line (including crit/defence).
	var amount := floori(float(hit.damage) * percent / 100.0)
	if heal.has("max_hp_fraction"):
		amount = mini(amount, floori(_max_hp * float(heal.max_hp_fraction)))
	if bool(heal.get("target_max_hp", false)):
		amount = mini(amount, swarm.max_hp[slot])
	restore_player("hp", amount, key)


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
	for key: String in _final_keys:
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
		var st := runner.stats_of(self, key)
		# The follow-up plays the skill's own stance when its data has one (tier C: it replaces a swing still playing).
		start_action(String(st.action), float(st.action_time), false, float(st.speed_factor))
		emit("final_attack", {"skill": key, "skill_id": int(st.skill_id), "level": int(st.level), "mob": slot,
			"pos": player.pos, "facing": player.facing, "action": String(st.action), "effect": String(st.effect)})
		var hit_visual := visual_index(String(st.hit))
		_final_attack_visual(slot, key)
		hit_mob(slot, st, hit_visual, final_rng)
		for extra: int in _spread_targets(slot, int(st.count) - 1):
			_final_attack_visual(extra, key)
			hit_mob(extra, st, hit_visual, final_rng)


func _final_attack_visual(slot: int, key: String) -> void:
	if not WeaponInfo.is_ranged(weapon_id()):
		return
	var shot := Ammo.projectile(data.get("ammo", {}), held_weapon_family())
	if shot.is_empty():
		return
	var aim := mob_center(slot)
	var start := shot_origin(aim)
	# tier C: visual-only straight flight at the current ammo's speed, no hit delay or damage projectile.
	emit("ammo_shot", {"skill": key, "from": start, "to": aim,
		"seconds": start.distance_to(aim) / maxf(1.0, float(shot.speed)),
		"ball": Ammo.bullet_path(ammo_id()), "rotate": bool(shot.rotate)})


## Spread (#181): up to `want` live mobs other than `target` whose body centre is within the held weapon's swing/ranged
## reach of the target's body centre, nearest the target first (scheduled bosses first, then the slot,
## RunWorld.targets_before). Uses no RNG. tier C: ours; reach is measured around the struck target, as a circle.
func _spread_targets(target: int, want: int) -> Array[int]:
	var found: Array[int] = []
	if want <= 0:
		return found
	var reach := weapon_reach.reach(self)
	if WeaponInfo.is_ranged(weapon_id()):
		reach = maxf(reach, float(WeaponInfo.RANGED_REACH.get(held_weapon_family(), 0.0)))
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
			if status.has("element"):
				params["element"] = String(status.element)
			swarm.apply_status(slot, String(status.get("status", "")), params, events)
	var knockback: Dictionary = book.def(key).get("knockback", {})
	if not knockback.is_empty() and not swarm.mob_kind(slot).boss and swarm.steady[slot] == 0:
		# tier C: one stream-1 roll per struck non-boss, including the 0/100% endpoints; a block without a chance field
		# always applies and draws nothing (Rush, #302).
		var always: bool = not knockback.has("chance_field")
		if always or rng.randf() * 100.0 < book.canonical(key, level, String(knockback.chance_field)):
			# `direction: "dash"` shoves along the dash that hit it instead of away from the player's final position.
			swarm.knockback(slot, player.pos.x, float(knockback.get("distance", 0.0)), fhm, bounds,
				int(hit.get("push_side", 0)) if String(knockback.get("direction", "")) == "dash" else 0)
	for listener: Callable in _hit_listeners:
		listener.call(slot, hit)


func _stream(n: int) -> RandomNumberGenerator:
	return _seeded_stream(seed_value, n)


## Resets the scroll stream from a saved hub-state seed using the same derivation as world construction.
func reseed_scroll_rng(p_seed: int) -> void:
	scroll_rng = _seeded_stream(p_seed, 11)


static func _seeded_stream(p_seed: int, n: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = p_seed * 1000003 + n * 7919
	return r


func _build_mob_kinds() -> void:
	var imgs: Dictionary = setup.get("mob_imgs", {})
	var overrides: Dictionary = data.get("mobs", {}).get("mobs", {})
	var speed_mult := float(balance.get("mob_speed_factor", MobKind.SPEED_SCALE)) / MobKind.SPEED_SCALE
	# Normalize legacy/pool-only schedules for StageRoster's map-based API; live region data already has maps.
	var roster := stage
	if stage.has("bosses"):
		roster = stage.duplicate(true)
		roster["maps"] = roster.get("maps", [])
		for boss: Dictionary in _stage_bosses():
			roster.maps.append({"boss": boss})
	var ids := StageRoster.mob_ids(roster, imgs, setup.get("mob_skill_img", {}),
		setup.map_imgs if _map_images_available() else [])
	for id in ids:
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
	_base_fortune = float(pb.get("fortune", 0.0))
	var starting: Dictionary = pb.get("stats", {})
	for stat: String in _base_stats:
		_base_stats[stat] = int(starting.get(stat, _base_stats[stat]))
	var b: Variant = pb.get("body")
	if b is Array and b.size() == 4:
		body = Rect2(float(b[0]), float(b[1]), float(b[2]), float(b[3]))
	cast_height = float(pb.get("cast_height", DEFAULT_CAST_HEIGHT))
	cast_forward = float(pb.get("cast_forward", DEFAULT_CAST_FORWARD))
	player.place(PortalSet.start_point(_current_map_img(), fhm, bounds, spawn_rng), fhm)
	if setup.has("character"):
		_restore_character(setup.character)
	else:
		progression.job_id = int(setup.get("job", jobs.default_job()))
		equipment.worn = Equipment.worn_from_ids(Equipment.DEFAULT_OUTFIT, setup.get("equipment_info", {}))
	set_job(progression.job_id)
	_init_cash()
	refresh_player_stats()
	_hp = _max_hp
	# Every round of the job has its start skills (Teleport on its key from Lv1, #284); a carried character keeps its rank.
	for key in jobs.start_skills(progression.job_id):
		if book.has(key) and not loadout.has(key):
			learn_skill(key)
	_action = player.stance()


func _restore_character(source: Dictionary) -> void:
	assert(int(source.get("format", 0)) in CharacterSnapshot.FORMATS, "Unsupported CharacterSnapshot format")
	var character := CharacterSnapshot.migrate(source, jobs, setup.get("equipment_info", {}))
	progression.job_id = int(character.job_id) # handed to set_job by _init_player
	character_look = character.look.duplicate(true)
	for field: String in ["skin", "face", "hair"]:
		if character_look.has(field):
			character_look[field] = int(character_look[field])
	equipment = Equipment.normalized(character.equipment)
	scrolls = CharacterSnapshot.integers(character.scrolls)
	mesos = int(character.mesos)
	_tiers_unlocked = int(character.tiers_unlocked)
	_cash_carried = CharacterSnapshot.integers(character.get("cash", {}))
	_pet_carried = int(character.get("pet", 0))


## Sets the HP ALERT level from {hp} (a fraction of max HP, clamped; 0 = do not alert; an old `mp` key is ignored).
## The pet reads it every tick, so a change takes effect at once (a live round follows the Options window, spec #34 #121).
func set_alert(levels: Dictionary) -> void:
	alert = {"hp": clampf(float(levels.get("hp", 0.0)), 0.0, 1.0)}


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


## Active Hyper Body Max HP percentage, integers like 2..60 straight from the buff snapshots.
func _max_buff_percent() -> float:
	return buffs.effect_total(MAX_HP_PCT)


## Recomputes max HP when the Hyper Body percentage changed (cast or expiry). Current HP keeps its value except that
## the new maximum clamps it (refresh_player_stats; nothing is granted).
func _refresh_max_buffs() -> void:
	if _max_buff_percent() != _max_buff_applied:
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
		_hp = minf(_max_hp, _hp + upkeep.pulse_hp() + hp_regen + loadout.regen_bonus())
	_hp = minf(_max_hp, _hp + upkeep.periodic_recovery(dt, loadout))
	_hp = minf(_max_hp, _hp + float(_max_hp) * _passive_regen_pct / 100.0 * dt)
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


## One equipment drop for the character's job (EquipmentDrops; `boss` takes the top third of the band) inside the reqLevel
## band of this stage's tier (stages.json drop_bands; never the character's level, #292), a weapon only from the job's
## weapon families, with v83 random stats, from the equipment stream; nothing when no listed item has info and fits.
## Returns whether an equipment pickup was spawned (Steal falls back to mesos when none fits).
func _drop_equipment(pos: Vector2, boss: bool) -> bool:
	var cfg: Dictionary = data.get("equipment_drops", {})
	var infos: Dictionary = setup.get("equipment_info", {})
	var items: Array = cfg.get("items", [])
	var band := drop_band()
	var families := jobs.weapon_families(progression.job_id)
	var id := EquipmentDrops.pick_boss(items, infos, progression.job_id, band, cfg, equip_rng, families) if boss \
		else EquipmentDrops.pick(items, infos, progression.job_id, band, cfg, equip_rng, families)
	if id > 0:
		return spawn_equipment(pos, Equipment.create_drop(id, Equipment.info_of(infos, id), equip_rng)) >= 0
	return false


## The reqLevel band [min, max] this stage's equipment drops come from (its tier's stages.json drop_bands entry).
func drop_band() -> Array:
	var stages: Dictionary = data.get("stages", {})
	return EquipmentDrops.band_of(stages, NxAward.tier_of(stages, stage_key))


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
## ordinary EXP rolls), its canonical revive list, then the reward shower and bonus choices.
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
	if map_sequence_enabled() and map_index < stage.maps.size() - 1:
		_map_clearing = true
		_map_swept = false


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
	take_hit(mob_weapon_attack(m, float(mk.pad)), false, "", Vector2(swarm.x[m], swarm.y[m]), source)


## Weapon attack `pad` of the mob in slot m at a physical hit (touch or attackN impact): Threaten's flat cut (#183,
## floor 0) first, then Attack Up's multiplier (MobSkill 100/110, #255); the source's boss/elite/dmg_mult multipliers
## apply later, in take_hit.
func mob_weapon_attack(m: int, pad: float) -> float:
	return swarm.threatened_pad(m, pad) * mob_skills.attack_multiplier(m, time)


## Defense inputs for a monster hit; overridable by subsequent equipment and buff rules.
func hit_defense() -> Dictionary:
	return {"pdd": player_pdd + buffs.effect_total("pdd"), "mdd": player_mdd + buffs.effect_total("mdd"), "resistance": {}}


## Tier C (#307): survivor opening multiplier on the whole round clock; absent ramps preserve existing strength.
func opening_multiplier(stat: String) -> float:
	var ramp: Dictionary = stage.get("opening_ramp", {})
	var maps: Array = stage.get("maps", [])
	if map_index >= 0 and map_index < maps.size():
		ramp = maps[map_index].get("opening_ramp", ramp)
	var values: Dictionary = ramp.get(stat, {})
	var seconds := float(ramp.get("seconds", 0.0))
	var progress := clampf(time / seconds, 0.0, 1.0) if seconds > 0.0 else 1.0
	progress = pow(progress, float(ramp.get("power", 1.0)))
	return lerpf(float(values.get("start", 1.0)), float(values.get("end", 1.0)), progress)


## Survivor scales stack after defense: ordinary opening ramp, elite scale, and explicit source scale.
## Tier C: scheduled boss sources already include the ramp captured at arrival.
func hit_source_multiplier(source: Dictionary) -> float:
	var mult := float(source.get("dmg_mult", 1.0))
	if not bool(source.get("boss", false)):
		mult *= opening_multiplier("damage")
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


## Applies one monster hit through avoid, defense and hit reaction; returns whole damage (0 on miss).
## Source fields: accuracy (canonical acc), elite, dmg_mult, mob, mob_id, boss. Events snapshot max_hp at hit time.
func take_hit(attack: float, magic: bool, element: String, source_pos: Vector2, source: Dictionary = {}) -> int:
	var bypass := PlayerUpkeep.bypasses_window(source)
	# Hidden (#194): nothing from a monster lands, whatever its source (the callers also skip the attack itself).
	if _dead or _map_clearing or god or _window_blocks(bypass) or is_hidden():
		return 0
	var dir := 1 if player.pos.x >= source_pos.x else -1
	if CombatMath.roll_miss(player_avoid + buffs.effect_total("avoid"), float(source.get("accuracy", 0.0)), rng):
		_emit_player_hit(0, true, dir, source)
		return 0
	var dmg := CombatMath.monster_hit(attack, magic, element, hit_defense(), rng,
		hit_source_multiplier(source))
	if not magic:
		# tier C: apply canonical Invincible percent to the whole weapon hit; minimum 1.
		dmg = maxi(1, roundi(dmg * (1.0 - clampf(buffs.effect_total("weapon_damage_reduction"), 0.0, 100.0) / 100.0)))
	# The Armor passive (Iron Body card, #289): a flat amount off every hit, physical or magic; minimum 1.
	dmg = maxi(1, dmg - roundi(loadout.passive_total(Loadout.ARMOR_FLAT)))
	# Power Guard (#182): a no-op, with no RNG and no event, unless the buff is active and this is contact damage.
	var reflect := _power_guard_reflect(dmg, magic, source)
	dmg -= reflect
	_hp -= dmg
	_emit_player_hit(dmg, false, dir, source)
	upkeep.land_hit(bypass)
	if reflect > 0:
		_apply_reflect(int(source.mob), reflect)
	if _hp <= 0.0:
		_hp = 0.0
		_dead = true
		state = DEAD
		emit("player_died", {"pos": player.pos})
	elif bypass or upkeep.may_knock_back():
		# tier C (owner, #223): a hit inside the knockback guard does its damage without pushing the player; a boss
		# skill attack/ball (window bypass) always knocks back and restarts the guard.
		player.knockback(dir)
		upkeep.start_knockback_guard()
	_write_player_state(0.0)
	return dmg


## Power Guard (#182, spec #165): the part of `damage` (the hit after defence and Invincible)
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


func _emit_player_hit(damage: int, miss: bool, dir: int, source: Dictionary) -> void:
	emit("player_hit", {"damage": damage, "miss": miss, "dir": dir,
		"pos": player.pos, "mob": int(source.get("mob", -1)), "mob_id": int(source.get("mob_id", 0)),
		"boss": bool(source.get("boss", false)), "max_hp": _max_hp, "source_kind": String(source.get("source_kind", "other"))})


## Whether auto-actions may cast now: hanging on a rope/ladder blocks new casts, not their cooldowns or effects.
func can_cast() -> bool:
	return state == PLAYING and not _dead and not _map_clearing and player.state != PlayerMotion.ST_LADDER


func _gain_exp(n: int) -> void:
	var before := progression.level
	# The Holy Symbol passive (#289): +x% on every gain; the fraction that does not make a whole point carries over, so
	# many small orbs lose nothing.
	var bonus := loadout.passive_total(Loadout.EXP_PCT)
	if bonus > 0.0 and n > 0:
		var total := float(n) * (1.0 + bonus / 100.0) + _exp_carry
		n = floori(total + 1e-9)
		_exp_carry = maxf(0.0, total - float(n))
	var gained := progression.add_exp(n)
	for k in gained:
		_on_level_up(before + k + 1)


func _on_level_up(level: int) -> void:
	var g: Dictionary = _job_value(balance.get("growth", {}), {})
	_base_hp += float(g.get("hp", 0.0))
	# Improved MaxHP Increase: the skill's HP per level-up at its rank now, never retroactive (tier B, v83 Cosmic).
	_base_hp += loadout.passive_total(Loadout.MAX_HP_PER_LEVEL)
	_earned_ap += int(balance.get("player", {}).get("ap_per_level", 5))
	_level_ranks(level)
	apply_potion_schedule(level, true)
	refresh_player_stats(false, level)
	var refill: Dictionary = balance.get("level_up_refill", DEFAULT_LEVEL_UP_REFILL)
	_hp = minf(_max_hp, _hp + float(refill.get("hp", DEFAULT_LEVEL_UP_REFILL.hp)) * _max_hp)
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


## The current job's table entry, else its nearest ancestor's (balance.json per-job rows).
func _job_value(table: Variant, fallback: Variant) -> Variant:
	if not (table is Dictionary):
		return fallback
	for j in jobs.lineage(progression.job_id):
		if table.has(str(j)):
			return table[str(j)]
	return table.get("0", fallback)


func _advance_queue() -> void:
	while pending_bonus_choices > 0:
		choice_bonus = true
		var bonus_cards := upgrades.roll_choices(self, card_rng, 3)
		if bonus_cards.is_empty():
			pending_bonus_choices -= 1 # no card at all (no filler in the data): never open an unanswerable window
			choice_bonus = false
			continue
		pending_cards = bonus_cards
		state = CHOOSING_UPGRADE
		emit("choice_pending", {"cards": bonus_cards.duplicate(true), "bonus": true})
		return
	while progression.has_pending():
		choice_bonus = false
		var cards := upgrades.roll_choices(self, card_rng, 3)
		if cards.is_empty():
			progression.pop_front() # no card at all (no filler in the data): consume the level instead of soft-locking
			continue
		pending_cards = cards
		state = CHOOSING_UPGRADE
		emit("choice_pending", {"cards": cards.duplicate(true), "bonus": false})
		return
	state = PLAYING
	if not _settle_map():
		_settle_clear()


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
	player_state["buffs"] = buffs.snapshot()
	player_state["hidden"] = is_hidden()
	player_state["morph"] = 0 if _dead else morph_id()
	player_state["max_hp"] = _max_hp
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
